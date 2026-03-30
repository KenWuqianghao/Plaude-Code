import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var controllerConnected = false
    @Published var activeProfileID: UUID
    @Published var lastActionLabel = "No actions yet"
    @Published var showSnippetMenu = false
    @Published var remapCaptureTarget: UUID?
    @Published var permissions = AppPermissions.current()
    @Published var isInjectionEnabled = true
    @Published var autoFocusGhostty = true
    /// DualSense touch surface → pointer, left click, two-finger scroll (requires Accessibility + Plaude Code on).
    @Published var dualSenseTrackpadAsMouse = true

    let controllerManager: ControllerManager
    let mappingStore: MappingStore
    private let actionRouter: ActionRouter

    private var openMappingsWindow: (() -> Void)?
    private var openCheatsheetWindowAction: (() -> Void)?
    private weak var cheatsheetHostWindow: NSWindow?
    private var lastCheatsheetOpenWindowAttempt: Date?
    private var lastToggleCheatsheetAt: Date?
    /// Set when presenting cheatsheet before `openWindow` has been captured (menu bar UI not loaded yet).
    private var pendingCheatsheetPresentation = false

    init() {
        self.mappingStore = MappingStore()
        self.activeProfileID = mappingStore.activeProfileID
        self.controllerManager = ControllerManager()
        self.actionRouter = ActionRouter()

        controllerManager.dualSenseTrackpadPointerInjectionAllowed = { [weak self] in
            guard let self else { return false }
            return self.isInjectionEnabled && self.permissions.canInjectKeystrokes && self.dualSenseTrackpadAsMouse
        }

        bindController()
        controllerManager.start()
        refreshPermissions()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.actionRouter.releaseFnKeyHold(force: true)
            }
        }
    }

    var activeProfile: MappingProfile? {
        mappingStore.profile(id: activeProfileID)
    }

    var activeBindings: [ControllerBinding] {
        activeProfile?.bindings.sorted {
            if $0.action.cheatCategory != $1.action.cheatCategory {
                return $0.action.cheatCategory.sortOrder < $1.action.cheatCategory.sortOrder
            }
            return $0.trigger.descriptionLabel.localizedCaseInsensitiveCompare($1.trigger.descriptionLabel) == .orderedAscending
        } ?? []
    }

    func activateProfile(id: UUID) {
        activeProfileID = id
        mappingStore.activeProfileID = id
    }

    func refreshPermissions() {
        permissions = AppPermissions.current()
    }

    /// Call from any view that has the matching environment actions (menu popover, Settings, cheatsheet window).
    func registerWindowOpeners(mappings: (() -> Void)? = nil, cheatsheet: (() -> Void)? = nil) {
        if let mappings { openMappingsWindow = mappings }
        if let cheatsheet {
            openCheatsheetWindowAction = cheatsheet
            drainPendingCheatsheetPresentation()
        }
    }

    func presentMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let openMappingsWindow {
            openMappingsWindow()
        } else {
            for window in NSApplication.shared.windows where window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    func presentCheatsheetWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let w = cheatsheetHostWindow {
            if w.isMiniaturized {
                w.deminiaturize(nil)
            }
            w.makeKeyAndOrderFront(nil)
            pendingCheatsheetPresentation = false
            return
        }
        guard openCheatsheetWindowAction != nil else {
            pendingCheatsheetPresentation = true
            lastActionLabel = "Cheatsheet — waiting for window hook (try again in a moment)"
            return
        }
        let now = Date()
        if let last = lastCheatsheetOpenWindowAttempt, now.timeIntervalSince(last) < 0.45 {
            return
        }
        lastCheatsheetOpenWindowAttempt = now
        pendingCheatsheetPresentation = false
        openCheatsheetWindowAction?()
    }

    private func drainPendingCheatsheetPresentation() {
        guard pendingCheatsheetPresentation, openCheatsheetWindowAction != nil else { return }
        pendingCheatsheetPresentation = false
        lastCheatsheetOpenWindowAttempt = nil
        presentCheatsheetWindow()
    }

    /// Called from the cheatsheet SwiftUI host so we can reuse a single window instead of stacking duplicates.
    func attachCheatsheetHostWindow(_ window: NSWindow?) {
        guard let window else { return }
        if let prev = cheatsheetHostWindow, prev != window {
            prev.orderOut(nil)
        }
        cheatsheetHostWindow = window
    }

    func updateBinding(_ binding: ControllerBinding, with trigger: InputTrigger) {
        guard let profile = activeProfile else { return }
        let update = mappingStore.updateBinding(
            profileID: profile.id,
            bindingID: binding.id,
            newTrigger: trigger
        )
        switch update {
        case .ok:
            lastActionLabel = "Updated mapping: \(binding.action.label)"
            objectWillChange.send()
        case .conflict(let existing):
            lastActionLabel = "Conflict with \(existing.action.label)"
        }
    }

    func setBindingAction(bindingID: UUID, action: Action) {
        guard let profile = activeProfile else { return }
        mappingStore.updateAction(profileID: profile.id, bindingID: bindingID, action: action)
        objectWillChange.send()
        lastActionLabel = "Command set: \(action.label)"
    }

    func restoreBuiltInClaudeBindings() {
        guard let profile = activeProfile else { return }
        mappingStore.applyBuiltInClaudeLayout(profileID: profile.id)
        objectWillChange.send()
        lastActionLabel = "Restored essential default mappings"
    }

    /// Run from snippet UI: respect Ghostty focus and accessibility like controller path.
    func performSnippet(_ action: Action) -> Bool {
        guard permissions.canInjectKeystrokes else { return false }
        if action.expectsGhosttyTarget {
            if autoFocusGhostty {
                actionRouter.focusGhostty()
            } else if !actionRouter.isGhosttyFrontmost {
                return false
            }
        }
        return actionRouter.perform(action: action)
    }

    private func bindController() {
        controllerManager.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            Task { @MainActor in
                self.controllerConnected = connected
                if connected {
                    self.lastActionLabel = "Gamepad ready — try Cross (bottom button)"
                } else {
                    self.lastActionLabel = "No gamepad (need extended or micro profile — pair DualSense/DS4)"
                }
            }
        }

        controllerManager.onInputEvent = { [weak self] event in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handle(event)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        self.handle(event)
                    }
                }
            }
        }
    }

    private func handle(_ event: InputEvent) {
        if remapCaptureTarget != nil {
            if event.phase == .pressed {
                lastActionLabel = "Remap mode — press a button to assign"
            }
            captureRemap(event)
            return
        }

        // Release must not use `binding(for: event.trigger)`: other held buttons (e.g. L1) stay in
        // chord modifiers, so lookup fails and Fn key-up never runs — Wispr stuck + keyboard/space breaks.
        if event.phase == .released {
            if let profile = activeProfile,
               profile.bindings.contains(where: {
                   $0.trigger.button == event.trigger.button && $0.action == .terminal(.fnKey)
               }) {
                _ = actionRouter.releaseFnKeyHold(force: false)
                lastActionLabel = "Fn released"
            }
            return
        }

        // Only act on down/repeat; Fn uses .released above.
        guard event.phase == .pressed || event.phase == .repeated else { return }

        if event.isPanicCombo {
            _ = actionRouter.releaseFnKeyHold(force: true)
            isInjectionEnabled = false
            lastActionLabel = "Emergency lock enabled"
            return
        }

        guard let profile = activeProfile else {
            lastActionLabel = "No active profile — check Settings → Profiles"
            return
        }

        guard let binding = profile.binding(for: event.trigger) else {
            lastActionLabel = "Unmapped: \(event.trigger.descriptionLabel) (see Settings)"
            return
        }

        switch binding.action {
        case .toggleInjectionEnabled:
            isInjectionEnabled.toggle()
            lastActionLabel = isInjectionEnabled
                ? "Plaude Code on — keys go to Ghostty"
                : "Plaude Code off — controller idle (map Share to turn on)"
            return
        case .toggleCheatSheet:
            let nowToggle = Date()
            if let t0 = lastToggleCheatsheetAt, nowToggle.timeIntervalSince(t0) < 0.35 {
                return
            }
            lastToggleCheatsheetAt = nowToggle
            presentCheatsheetWindow()
            lastActionLabel = "Cheatsheet window"
            return
        case .toggleSnippetMenu:
            showSnippetMenu.toggle()
            lastActionLabel = "Snippet menu \(showSnippetMenu ? "opened" : "closed")"
            return
        default:
            break
        }

        guard isInjectionEnabled else {
            lastActionLabel = "Plaude Code off — enable in menu or map Toggle Plaude Code"
            return
        }

        guard permissions.canInjectKeystrokes else {
            lastActionLabel = "Enable Accessibility for this app in System Settings"
            return
        }

        if case .terminal(.fnKey) = binding.action {
            if event.phase == .repeated { return }
            if actionRouter.pressFnKeyHold() {
                lastActionLabel = "Fn down (hold for Wispr)"
            } else {
                lastActionLabel = "Fn hold failed"
            }
            return
        }

        if binding.action.expectsGhosttyTarget {
            if autoFocusGhostty {
                actionRouter.focusGhostty()
            } else if !actionRouter.isGhosttyFrontmost {
                lastActionLabel = "Ghostty not focused"
                return
            }
        }

        if actionRouter.perform(action: binding.action) {
            lastActionLabel = "Sent: \(binding.action.label)"
        } else {
            lastActionLabel = "Failed: \(binding.action.label)"
        }
    }

    private func captureRemap(_ event: InputEvent) {
        guard event.phase == .pressed else { return }
        guard let target = remapCaptureTarget else { return }
        guard let profile = activeProfile else { return }

        guard let binding = profile.bindings.first(where: { $0.id == target }) else {
            remapCaptureTarget = nil
            return
        }

        updateBinding(binding, with: event.trigger)
        remapCaptureTarget = nil
    }
}
