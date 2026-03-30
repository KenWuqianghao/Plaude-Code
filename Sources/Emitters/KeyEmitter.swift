import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

final class KeyEmitter {
    func send(_ stroke: KeyStroke) -> Bool {
        guard keyDown(stroke) else { return false }
        return keyUp(stroke)
    }

    func keyDown(_ stroke: KeyStroke, eventSource: CGEventSourceStateID = .combinedSessionState) -> Bool {
        postKey(stroke.keyCode, keyDown: true, flags: stroke.flags, eventSource: eventSource)
    }

    func keyUp(_ stroke: KeyStroke, eventSource: CGEventSourceStateID = .combinedSessionState) -> Bool {
        postKey(stroke.keyCode, keyDown: false, flags: stroke.flags, eventSource: eventSource)
    }

    /// Wispr / system Fn may ignore a single tap location; HID + session taps mirror hardware more closely.
    func keyDownFnHardwareStyle() -> Bool {
        postFnHardware(CGKeyCode(kVK_Function), keyDown: true)
    }

    func keyUpFnHardwareStyle() -> Bool {
        postFnHardware(CGKeyCode(kVK_Function), keyDown: false)
    }

    private func postFnHardware(_ code: CGKeyCode, keyDown: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let taps: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap]
        if keyDown {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else {
                return false
            }
            ev.flags = [.maskSecondaryFn]
            for tap in taps { ev.post(tap: tap) }
            return true
        }
        // Key-up: runtime logs showed CGEvent posts succeed but Wispr kept listening. Pair with down, then a
        // no-flags key-up so listeners that track “secondary Fn released” see a clear transition.
        var ok = false
        for flags: CGEventFlags in [[.maskSecondaryFn], []] {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
                continue
            }
            ev.flags = flags
            for tap in taps { ev.post(tap: tap) }
            ok = true
        }
        return ok
    }

    private func postKey(_ code: CGKeyCode, keyDown: Bool, flags: CGEventFlags, eventSource: CGEventSourceStateID) -> Bool {
        guard let source = CGEventSource(stateID: eventSource),
              let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else {
            return false
        }
        ev.flags = flags
        ev.post(tap: .cghidEventTap)
        return true
    }

    func send(sequence: [KeyStroke]) -> Bool {
        sequence.allSatisfy { send($0) }
    }
}

extension TerminalControl {
    var keyStroke: KeyStroke {
        switch self {
        case .enter:
            return KeyStroke(keyCode: CGKeyCode(kVK_Return), flags: [])
        case .escape:
            return KeyStroke(keyCode: CGKeyCode(kVK_Escape), flags: [])
        case .backspace:
            return KeyStroke(keyCode: CGKeyCode(kVK_Delete), flags: [])
        case .tab:
            return KeyStroke(keyCode: CGKeyCode(kVK_Tab), flags: [])
        case .arrowUp:
            return KeyStroke(keyCode: CGKeyCode(kVK_UpArrow), flags: [])
        case .arrowDown:
            return KeyStroke(keyCode: CGKeyCode(kVK_DownArrow), flags: [])
        case .arrowLeft:
            return KeyStroke(keyCode: CGKeyCode(kVK_LeftArrow), flags: [])
        case .arrowRight:
            return KeyStroke(keyCode: CGKeyCode(kVK_RightArrow), flags: [])
        case .ctrlC:
            return KeyStroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: [.maskControl])
        case .ctrlD:
            return KeyStroke(keyCode: CGKeyCode(kVK_ANSI_D), flags: [.maskControl])
        case .ctrlL:
            return KeyStroke(keyCode: CGKeyCode(kVK_ANSI_L), flags: [.maskControl])
        case .ctrlF:
            return KeyStroke(keyCode: CGKeyCode(kVK_ANSI_F), flags: [.maskControl])
        case .optionLeft:
            return KeyStroke(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskAlternate])
        case .optionRight:
            return KeyStroke(keyCode: CGKeyCode(kVK_RightArrow), flags: [.maskAlternate])
        case .cmdK:
            return KeyStroke(keyCode: CGKeyCode(kVK_ANSI_K), flags: [.maskCommand])
        case .fnKey:
            // `kVK_Function` / NX_POWER (63) — best-effort Fn synthesize; some apps listen at lower levels.
            return KeyStroke(keyCode: CGKeyCode(kVK_Function), flags: [])
        case .cmdTab:
            return KeyStroke(keyCode: CGKeyCode(kVK_Tab), flags: [.maskCommand])
        }
    }
}
