import AppKit
import Foundation
import GameController

/// Maps DualSense / DualShock style input. Left-stick history navigation is emitted **without**
/// putting virtual D-pad presses into the chord modifier set, so face buttons still match
/// bindings that expect no modifiers.
final class ControllerManager {
    var onConnectionChanged: ((Bool) -> Void)?
    var onInputEvent: ((InputEvent) -> Void)?
    /// When true, DualSense `touchpadPrimary` / `touchpadSecondary` + click post pointer events instead of `.touchpad` bindings.
    var dualSenseTrackpadPointerInjectionAllowed: () -> Bool = { false }

    private var connectedController: GCController?
    private var isGamepadWired = false
    /// Buttons currently held that participate in chord matching (all digital bindings except stick-emulated navigation).
    private var physicalPressed: Set<ControllerButton> = []
    private var repeatTimers: [ControllerButton: Timer] = [:]
    private var stickVirtualDirection: ControllerButton?
    private var stickRepeatTimers: [ControllerButton: Timer] = [:]
    private var inputPollTimer: Timer?
    private var lastPolledPhysical: Set<ControllerButton> = []
    /// Single threshold on analog L2/R2 flutters around the cutoff; Wispr never sees a clean release.
    private var l2PullLatch = false
    private var r2PullLatch = false

    private let pointerEmitter = PointerEmitter()
    private let dualSenseHID = DualSenseHIDTouchReader()
    private let touchMagnitudeDead: Float = 0.045
    /// macOS often mirrors the same coordinates on `touchpadPrimary` and `touchpadSecondary` for one finger; require real separation for two-finger scroll.
    private let touchSecondFingerSeparate: Float = 0.06
    private let touchMoveScale: CGFloat = 28
    /// Vendor HID coordinates update at ~controller report rate; scale up so motion matches trackpad expectation.
    private let touchMoveScaleHIDMultiplier: CGFloat = 4.5
    /// Pixels per ±1 normalized touch unit between consecutive HID samples (pad edge-to-edge ≈ 2 units each axis).
    private var touchHIDWarpGain: CGFloat { touchMoveScale * touchMoveScaleHIDMultiplier * 5 }
    /// Ignore tiny normalized L1 jitter so the pointer doesn’t “hop” when the finger hasn’t meaningfully moved.
    private let touchHIDNormJitterDead: Float = 0.004
    private let touchScrollScale: CGFloat = 95
    private var tpLastTouchpadButton = false
    private var tpPrimaryX: Float = 0
    private var tpPrimaryY: Float = 0
    private var tpHasPrimarySample = false
    private var tpAvgY: Float = 0
    private var tpHasTwoFingerSample = false
    /// Last position applied for a distinct `DualSenseHIDTouchReader.touchReportSequence` value.
    private var tpHIDAnchorX: Float = 0
    private var tpHIDAnchorY: Float = 0
    private var tpHIDSeqAtAnchor: UInt64 = 0
    /// Last warped screen point and last HID norm — incremental `warp` so motion starts from the real cursor and batching stays correct.
    private var tpHIDLastWarpX: CGFloat = 0
    private var tpHIDLastWarpY: CGFloat = 0
    private var tpHIDLastNormX: Float = 0
    private var tpHIDLastNormY: Float = 0

    private let repeatStartDelay: TimeInterval = 0.35
    private let repeatRate: TimeInterval = 0.08
    private let triggerThreshold = 0.6
    /// Analog triggers are used for their own bindings (e.g. L2 = Fn), not as chord modifiers — resting axis noise was making Options register as `options + l2` and miss the cheatsheet binding.
    private static let chordModifierExclusions: Set<ControllerButton> = [.l2, .r2]
    /// DualSense face / menu buttons often expose pressure as `value` while `isPressed` stays false in polled reads.
    private static let analogButtonThreshold: Float = 0.12
    /// L1/R1 analog noise at 0.12 falsely adds shoulders to chord → Options reads as L1+R1+Options → panic, not cheatsheet.
    private static let shoulderPollThreshold: Float = 0.55

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    /// Call after `onConnectionChanged` / `onInputEvent` are set (e.g. from `AppModel`).
    func start() {
        // macOS 11.3+ defaults to false: no input while another app is frontmost without this.
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        connectedController = GCController.controllers().first
        wireController()
    }

    deinit {
        invalidateAllTimers()
        NotificationCenter.default.removeObserver(self)
    }

    private func invalidateAllTimers() {
        repeatTimers.values.forEach { $0.invalidate() }
        repeatTimers.removeAll()
        stickRepeatTimers.values.forEach { $0.invalidate() }
        stickRepeatTimers.removeAll()
        inputPollTimer?.invalidate()
        inputPollTimer = nil
        lastPolledPhysical.removeAll()
        l2PullLatch = false
        r2PullLatch = false
        if tpLastTouchpadButton {
            _ = pointerEmitter.leftMouseUp()
        }
        resetDualSenseTouchState()
    }

    @objc private func controllerConnected(_ notification: Notification) {
        connectedController = notification.object as? GCController
        wireController()
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        guard let disconnected = notification.object as? GCController else { return }
        if disconnected == connectedController {
            dualSenseHID.stop()
            connectedController = nil
            physicalPressed.removeAll()
            stickVirtualDirection = nil
            invalidateAllTimers()
            isGamepadWired = false
            notifyInputReadyState()
        }
    }

    private func notifyInputReadyState() {
        let ready = connectedController != nil && isGamepadWired
        onConnectionChanged?(ready)
    }

    private func wireController() {
        isGamepadWired = false
        guard let controller = connectedController else {
            notifyInputReadyState()
            return
        }

        if let gamepad = controller.extendedGamepad {
            wireExtendedGamepad(gamepad, controller: controller)
            isGamepadWired = true
        } else if let gamepad = controller.microGamepad {
            wireMicroGamepad(gamepad, controller: controller)
            isGamepadWired = true
        }

        notifyInputReadyState()
    }

    private func wireExtendedGamepad(_ gamepad: GCExtendedGamepad, controller: GCController) {
        if gamepad is GCDualSenseGamepad {
            dualSenseHID.start()
        } else {
            dualSenseHID.stop()
        }
        if let ds = gamepad as? GCDualSenseGamepad {
            ds.touchpadPrimary.valueChangedHandler = nil
            ds.touchpadSecondary.valueChangedHandler = nil
            for key in gamepad.dpads.keys where key.localizedCaseInsensitiveContains("touch") {
                gamepad.dpads[key]?.valueChangedHandler = nil
            }
            for key in gamepad.axes.keys where key.localizedCaseInsensitiveContains("touch") {
                gamepad.axes[key]?.valueChangedHandler = nil
            }
        }
        // Poll on the main run loop; `pressedChangedHandler` delivery is unreliable for this app type.
        startExtendedInputPolling(gamepad: gamepad, controller: controller)
    }

    private func startExtendedInputPolling(gamepad: GCExtendedGamepad, controller: GCController) {
        inputPollTimer?.invalidate()
        lastPolledPhysical = []
        if tpLastTouchpadButton {
            _ = pointerEmitter.leftMouseUp()
        }
        resetDualSenseTouchState()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.pollExtendedGamepad(gamepad: gamepad, controller: controller)
        }
        inputPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollExtendedGamepad(gamepad: GCExtendedGamepad, controller: GCController) {
        // Fresh state for this tick — live `extendedGamepad` can otherwise hold stale DualSense touch axes on macOS.
        let pollGP = controller.capture().extendedGamepad ?? gamepad
        let pollPhysical = controller.physicalInputProfile.capture()

        let current = polledPhysicalSet(extended: pollGP, controller: controller)
        let previous = lastPolledPhysical
        for b in ControllerButton.allCases where b != .ps {
            let now = current.contains(b)
            let was = previous.contains(b)
            if now != was {
                handlePhysicalButton(button: b, pressed: now)
            }
        }
        lastPolledPhysical = current

        let y = Float(pollGP.leftThumbstick.yAxis.value)
        handleStickVertical(y: y)

        if let ds = pollGP as? GCDualSenseGamepad {
            let liveGP = controller.extendedGamepad ?? pollGP
            let livePhys = controller.physicalInputProfile
            processDualSenseTrackpad(
                ds: ds,
                extendedLive: liveGP,
                physicalCapture: pollPhysical,
                physicalLive: livePhys
            )
        }
    }

    private static func buttonDown(_ b: GCControllerButtonInput, threshold: Float) -> Bool {
        b.isPressed || b.value > threshold
    }

    private func polledPhysicalSet(extended gp: GCExtendedGamepad, controller: GCController) -> Set<ControllerButton> {
        let t = Self.analogButtonThreshold
        let st = Self.shoulderPollThreshold
        var s = Set<ControllerButton>()
        if Self.buttonDown(gp.buttonA, threshold: t) { s.insert(.cross) }
        if Self.buttonDown(gp.buttonB, threshold: t) { s.insert(.circle) }
        if Self.buttonDown(gp.buttonX, threshold: t) { s.insert(.square) }
        if Self.buttonDown(gp.buttonY, threshold: t) { s.insert(.triangle) }
        if Self.buttonDown(gp.leftShoulder, threshold: st) { s.insert(.l1) }
        if Self.buttonDown(gp.rightShoulder, threshold: st) { s.insert(.r1) }
        if let l3 = gp.leftThumbstickButton, Self.buttonDown(l3, threshold: t) { s.insert(.l3) }
        if let r3 = gp.rightThumbstickButton, Self.buttonDown(r3, threshold: t) { s.insert(.r3) }
        if Self.buttonDown(gp.dpad.up, threshold: t) { s.insert(.dpadUp) }
        if Self.buttonDown(gp.dpad.down, threshold: t) { s.insert(.dpadDown) }
        if Self.buttonDown(gp.dpad.left, threshold: t) { s.insert(.dpadLeft) }
        if Self.buttonDown(gp.dpad.right, threshold: t) { s.insert(.dpadRight) }
        if Self.buttonDown(gp.buttonMenu, threshold: t) { s.insert(.options) }
        if let share = gp.buttonOptions, Self.buttonDown(share, threshold: t) { s.insert(.share) }
        updateTriggerLatch(value: gp.leftTrigger.value, latch: &l2PullLatch)
        updateTriggerLatch(value: gp.rightTrigger.value, latch: &r2PullLatch)
        if l2PullLatch { s.insert(.l2) }
        if r2PullLatch { s.insert(.r2) }
        if let ds = gp as? GCDualSenseGamepad, ds.touchpadButton.isPressed {
            if !dualSenseTrackpadPointerInjectionAllowed() {
                s.insert(.touchpad)
            }
        }
        return s
    }

    /// Reads `(px,py)` / `(sx,sy)` from `GCControllerTouchpad` when available. If unavailable,
    /// falls back to touch-labeled dpads from `GCPhysicalInputProfile`, then finally legacy DualSense axes.
    private func dualSenseTouchAxesFromProfile(
        extendedLive: GCExtendedGamepad,
        physicalCapture: GCPhysicalInputProfile,
        physicalLive: GCPhysicalInputProfile,
        legacy: GCDualSenseGamepad
    ) -> (
        px: Float, py: Float, sx: Float, sy: Float, profilePads: Int, profileUsed: Bool, touchState0: String, source: String
    ) {
        let pads: [GCControllerTouchpad] = physicalLive.touchpads.keys.sorted().compactMap { physicalLive.touchpads[$0] }
        if pads.isEmpty {
            if let live = Self.readTouchpad12(from: physicalLive) {
                return (live.0, live.1, live.2, live.3, 0, true, "n/a", "profileAxis2Live")
            }
            if let ext = Self.readTouchpad12(from: extendedLive) {
                return (ext.0, ext.1, ext.2, ext.3, 0, true, "n/a", "profileAxis2ExtLive")
            }
            if let cap = Self.readTouchpad12(from: physicalCapture) {
                return (cap.0, cap.1, cap.2, cap.3, 0, true, "n/a", "profileAxis2Cap")
            }
            let touchDpads: [GCControllerDirectionPad] = physicalLive.dpads.keys
                .sorted()
                .filter { $0.localizedCaseInsensitiveContains("touch") }
                .compactMap { physicalLive.dpads[$0] }
            let touchDpadsCap: [GCControllerDirectionPad] = physicalCapture.dpads.keys
                .sorted()
                .filter { $0.localizedCaseInsensitiveContains("touch") }
                .compactMap { physicalCapture.dpads[$0] }
            let dpadLive = touchDpads
            let dpadCap = touchDpadsCap
            if !dpadLive.isEmpty {
                let p = dpadLive[0]
                if dpadLive.count > 1 {
                    let s = dpadLive[1]
                    return (p.xAxis.value, p.yAxis.value, s.xAxis.value, s.yAxis.value, 0, true, "n/a", "profileDpad2Live")
                }
                return (
                    p.xAxis.value,
                    p.yAxis.value,
                    legacy.touchpadSecondary.xAxis.value,
                    legacy.touchpadSecondary.yAxis.value,
                    0,
                    true,
                    "n/a",
                    "profileDpad1Live+legacy2"
                )
            }
            if !dpadCap.isEmpty {
                let p = dpadCap[0]
                if dpadCap.count > 1 {
                    let s = dpadCap[1]
                    return (p.xAxis.value, p.yAxis.value, s.xAxis.value, s.yAxis.value, 0, true, "n/a", "profileDpad2Cap")
                }
                return (
                    p.xAxis.value,
                    p.yAxis.value,
                    legacy.touchpadSecondary.xAxis.value,
                    legacy.touchpadSecondary.yAxis.value,
                    0,
                    true,
                    "n/a",
                    "profileDpad1Cap+legacy2"
                )
            }
            return (
                legacy.touchpadPrimary.xAxis.value,
                legacy.touchpadPrimary.yAxis.value,
                legacy.touchpadSecondary.xAxis.value,
                legacy.touchpadSecondary.yAxis.value,
                0,
                false,
                "legacy",
                "legacy"
            )
        }

        func activePos(_ pad: GCControllerTouchpad) -> (Float, Float)? {
            switch pad.touchState {
            case .down, .moving:
                return (pad.touchSurface.xAxis.value, pad.touchSurface.yAxis.value)
            default:
                return nil
            }
        }

        let active = pads.compactMap { p -> (Float, Float)? in activePos(p) }
        let t0: String
        switch pads[0].touchState {
        case .up: t0 = "up"
        case .down: t0 = "down"
        case .moving: t0 = "moving"
        @unknown default: t0 = "unknown"
        }

        if active.isEmpty {
            return (0, 0, 0, 0, pads.count, true, t0, "profileTouchpad")
        }
        if active.count >= 2 {
            return (active[0].0, active[0].1, active[1].0, active[1].1, pads.count, true, t0, "profileTouchpad")
        }
        let sx = legacy.touchpadSecondary.xAxis.value
        let sy = legacy.touchpadSecondary.yAxis.value
        return (active[0].0, active[0].1, sx, sy, pads.count, true, t0, "profileTouchpad+legacy2")
    }

    private static func readTouchpad12(from profile: GCPhysicalInputProfile) -> (Float, Float, Float, Float)? {
        guard let tx1 = profile.axes["Touchpad 1 X Axis"]?.value,
              let ty1 = profile.axes["Touchpad 1 Y Axis"]?.value,
              let tx2 = profile.axes["Touchpad 2 X Axis"]?.value,
              let ty2 = profile.axes["Touchpad 2 Y Axis"]?.value
        else {
            return nil
        }
        return (tx1, ty1, tx2, ty2)
    }

    private func processDualSenseTrackpad(
        ds: GCDualSenseGamepad,
        extendedLive: GCExtendedGamepad,
        physicalCapture: GCPhysicalInputProfile,
        physicalLive: GCPhysicalInputProfile
    ) {
        let axes = dualSenseTouchAxesFromProfile(
            extendedLive: extendedLive,
            physicalCapture: physicalCapture,
            physicalLive: physicalLive,
            legacy: ds
        )
        /// Prefer PlayStation HID norms whenever the session is open — `hasPrimary` alone flickers and falls back to stuck GameController axes.
        let useHidCoords = dualSenseHID.isHIDSessionActive
        let px = useHidCoords ? dualSenseHID.primaryNorm.x : axes.px
        let py = useHidCoords ? dualSenseHID.primaryNorm.y : axes.py
        let sx = useHidCoords ? dualSenseHID.secondaryNorm.x : axes.sx
        let sy = useHidCoords ? dualSenseHID.secondaryNorm.y : axes.sy

        func magnitude(_ x: Float, _ y: Float) -> Float { abs(x) + abs(y) }

        let a1 = magnitude(px, py) > touchMagnitudeDead
        let a2 = magnitude(sx, sy) > touchMagnitudeDead
        let secondFingerDistinct =
            abs(px - sx) > touchSecondFingerSeparate
            || abs(py - sy) > touchSecondFingerSeparate
        let twoFingerScroll = a1 && a2 && secondFingerDistinct

        let allowed = dualSenseTrackpadPointerInjectionAllowed()
        let tb = ds.touchpadButton.isPressed

        guard allowed else {
            if tpLastTouchpadButton {
                _ = pointerEmitter.leftMouseUp()
            }
            resetDualSenseTouchState()
            return
        }

        if tb != tpLastTouchpadButton {
            if tb {
                _ = pointerEmitter.leftMouseDown()
            } else {
                _ = pointerEmitter.leftMouseUp()
            }
            tpLastTouchpadButton = tb
        }

        if twoFingerScroll {
            let avgY = (py + sy) / 2
            if tpHasTwoFingerSample {
                let d = CGFloat(avgY - tpAvgY) * touchScrollScale
                _ = pointerEmitter.scrollBy(deltaY: -d)
            }
            tpAvgY = avgY
            tpHasTwoFingerSample = true
            tpHasPrimarySample = false
        } else if a1 {
            if useHidCoords {
                let seq = dualSenseHID.touchReportSequence
                let gain = touchHIDWarpGain
                if !tpHasPrimarySample {
                    let ml = NSEvent.mouseLocation
                    tpHIDLastWarpX = ml.x
                    tpHIDLastWarpY = ml.y
                    tpHIDLastNormX = px
                    tpHIDLastNormY = py
                    tpHIDAnchorX = px
                    tpHIDAnchorY = py
                    tpHIDSeqAtAnchor = seq
                } else if seq != tpHIDSeqAtAnchor {
                    let dnx = px - tpHIDLastNormX
                    let dny = py - tpHIDLastNormY
                    let jitter = abs(dnx) + abs(dny)
                    if jitter < touchHIDNormJitterDead {
                        tpHIDLastNormX = px
                        tpHIDLastNormY = py
                        tpHIDSeqAtAnchor = seq
                    } else {
                        let nx = tpHIDLastWarpX + CGFloat(dnx) * gain
                        let ny = tpHIDLastWarpY + CGFloat(dny) * gain
                        _ = pointerEmitter.warpTo(x: nx, y: ny)
                        tpHIDLastWarpX = nx
                        tpHIDLastWarpY = ny
                        tpHIDLastNormX = px
                        tpHIDLastNormY = py
                        tpHIDSeqAtAnchor = seq
                    }
                    tpHIDAnchorX = px
                    tpHIDAnchorY = py
                }
                tpPrimaryX = px
                tpPrimaryY = py
                tpHasPrimarySample = true
                tpHasTwoFingerSample = false
            } else {
                if tpHasPrimarySample {
                    let dx = CGFloat(px - tpPrimaryX) * touchMoveScale
                    let dy = CGFloat(py - tpPrimaryY) * touchMoveScale
                    _ = pointerEmitter.moveBy(deltaX: dx, deltaY: -dy)
                }
                tpPrimaryX = px
                tpPrimaryY = py
                tpHasPrimarySample = true
                tpHasTwoFingerSample = false
            }
        } else {
            tpHasPrimarySample = false
            tpHasTwoFingerSample = false
            tpHIDSeqAtAnchor = 0
        }
    }

    private func resetDualSenseTouchState() {
        tpLastTouchpadButton = false
        tpHasPrimarySample = false
        tpHasTwoFingerSample = false
        tpHIDSeqAtAnchor = 0
    }

    private func updateTriggerLatch(value: Float, latch: inout Bool) {
        let press: Float = 0.40
        let release: Float = 0.10
        if latch {
            if value < release { latch = false }
        } else {
            if value > press { latch = true }
        }
    }

    private func wireMicroGamepad(_ gamepad: GCMicroGamepad, controller: GCController) {
        // Micro profile only exposes A, X, dpad, and Menu. Full DualSense/DS4 should use `extendedGamepad`.
        bindDigitalButton(gamepad.buttonA, as: .cross)
        bindDigitalButton(gamepad.buttonX, as: .square)
        bindDigitalButton(gamepad.dpad.up, as: .dpadUp)
        bindDigitalButton(gamepad.dpad.down, as: .dpadDown)
        bindDigitalButton(gamepad.dpad.left, as: .dpadLeft)
        bindDigitalButton(gamepad.dpad.right, as: .dpadRight)
        bindDigitalButton(gamepad.buttonMenu, as: .options)
        if let touchpadButton = controller.physicalInputProfile.buttons.first(where: { key, _ in
            key.localizedCaseInsensitiveContains("touch")
        })?.value {
            bindDigitalButton(touchpadButton, as: .touchpad)
        }
    }

    private func chordModifiers(excluding button: ControllerButton) -> Set<ControllerButton> {
        physicalPressed.subtracting([button]).subtracting(Self.chordModifierExclusions)
    }

    private func emitPhysical(button: ControllerButton, phase: InputPhase) {
        let modifiers = chordModifiers(excluding: button)
        let event = InputEvent(
            trigger: InputTrigger(button: button, modifiers: modifiers),
            phase: phase,
            timestamp: Date()
        )
        onInputEvent?(event)
    }

    /// Stick-driven Up/Down does not add D-pad to `physicalPressed`, so other buttons keep clean modifier sets.
    private func emitStickVirtual(button: ControllerButton, phase: InputPhase) {
        let modifiers = physicalPressed.subtracting(Self.chordModifierExclusions)
        let event = InputEvent(
            trigger: InputTrigger(button: button, modifiers: modifiers),
            phase: phase,
            timestamp: Date()
        )
        onInputEvent?(event)
    }

    private func bindDigitalButton(_ buttonInput: GCControllerButtonInput, as button: ControllerButton) {
        buttonInput.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handlePhysicalButton(button: button, pressed: pressed)
        }
    }

    private func handlePhysicalButton(button: ControllerButton, pressed: Bool) {
        if pressed {
            physicalPress(button)
        } else {
            physicalRelease(button)
        }
    }

    private func physicalPress(_ button: ControllerButton) {
        guard !physicalPressed.contains(button) else { return }
        physicalPressed.insert(button)
        emitPhysical(button: button, phase: .pressed)
        guard shouldAutoRepeat(button) else { return }
        startRepeat(for: button) { [weak self] b, phase in
            self?.emitPhysical(button: b, phase: phase)
        }
    }

    /// Menu / shoulders / triggers should not auto-repeat — holding **Options** was firing cheatsheet every repeat tick.
    private func shouldAutoRepeat(_ button: ControllerButton) -> Bool {
        switch button {
        case .options, .share, .touchpad, .l1, .r1, .l2, .r2, .l3, .r3, .ps:
            return false
        case .cross, .circle, .square, .triangle,
             .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            return true
        }
    }

    private func physicalRelease(_ button: ControllerButton) {
        guard physicalPressed.contains(button) else { return }
        physicalPressed.remove(button)
        stopRepeat(for: button, timers: &repeatTimers)
        emitPhysical(button: button, phase: .released)
    }

    private func handleStickVertical(y: Float) {
        let desired: ControllerButton?
        if y > Float(triggerThreshold) {
            desired = .dpadUp
        } else if y < -Float(triggerThreshold) {
            desired = .dpadDown
        } else {
            desired = nil
        }

        if desired == stickVirtualDirection { return }

        if let old = stickVirtualDirection {
            stopStickRepeat(old)
            emitStickVirtual(button: old, phase: .released)
        }
        stickVirtualDirection = desired

        if let new = desired {
            emitStickVirtual(button: new, phase: .pressed)
            startStickRepeat(new)
        }
    }

    private func startStickRepeat(_ button: ControllerButton) {
        stopStickRepeat(button)
        let timer = Timer.scheduledTimer(withTimeInterval: repeatStartDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.stickVirtualDirection != button { return }
            self.emitStickVirtual(button: button, phase: .repeated)
            let repeatingTimer = Timer.scheduledTimer(withTimeInterval: self.repeatRate, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.stickVirtualDirection == button {
                    self.emitStickVirtual(button: button, phase: .repeated)
                }
            }
            self.stickRepeatTimers[button]?.invalidate()
            self.stickRepeatTimers[button] = repeatingTimer
            RunLoop.main.add(repeatingTimer, forMode: .common)
        }
        stickRepeatTimers[button] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStickRepeat(_ button: ControllerButton) {
        stickRepeatTimers[button]?.invalidate()
        stickRepeatTimers[button] = nil
    }

    private func startRepeat(for button: ControllerButton, emitter: @escaping (ControllerButton, InputPhase) -> Void) {
        stopRepeat(for: button, timers: &repeatTimers)
        let timer = Timer.scheduledTimer(withTimeInterval: repeatStartDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.physicalPressed.contains(button) { return }
            emitter(button, .repeated)
            let repeatingTimer = Timer.scheduledTimer(withTimeInterval: self.repeatRate, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.physicalPressed.contains(button) {
                    emitter(button, .repeated)
                }
            }
            self.repeatTimers[button]?.invalidate()
            self.repeatTimers[button] = repeatingTimer
            RunLoop.main.add(repeatingTimer, forMode: .common)
        }
        repeatTimers[button] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRepeat(for button: ControllerButton, timers: inout [ControllerButton: Timer]) {
        timers[button]?.invalidate()
        timers[button] = nil
    }
}
