import AppKit
import Foundation

final class ActionRouter {
    private let keyEmitter = KeyEmitter()
    private let pasteEmitter = PasteEmitter()
    private var fnKeyHoldIsDown = false
    /// True only after a successful synthetic Fn **down** — avoids orphan ups from L2 analog chatter (logs showed many release pairs/sec).
    private var fnHIDDownPosted = false

    var isGhosttyFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return Self.appIsGhostty(app)
    }

    func focusGhostty() {
        let matches = NSWorkspace.shared.runningApplications.filter { Self.appIsGhostty($0) }
        let chosen = Self.preferGhosttyApp(matches)
        guard let app = chosen else { return }
        app.activate(options: [.activateAllWindows])
    }

    /// Dock / system helpers sometimes pollute name-based matches (log showed `com.apple.dock.external.extra.arm64` beside real Ghostty).
    private static func appIsGhostty(_ app: NSRunningApplication) -> Bool {
        let bid = app.bundleIdentifier?.lowercased() ?? ""
        if bid.hasPrefix("com.apple.") { return false }

        if bid.contains("mitchellh.ghostty") || bid.contains("ghostty") {
            return true
        }
        let exe = app.executableURL?.lastPathComponent.lowercased() ?? ""
        if exe == "ghostty" || exe.contains("ghostty") {
            return true
        }
        let name = app.localizedName?.lowercased() ?? ""
        return name.contains("ghostty")
    }

    private static func preferGhosttyApp(_ apps: [NSRunningApplication]) -> NSRunningApplication? {
        if let exact = apps.first(where: { $0.bundleIdentifier == "com.mitchellh.ghostty" }) {
            return exact
        }
        return apps.first
    }

    /// Controller L2 hold: key-down on press, key-up on release (Wispr Flow / push-to-talk Fn).
    func pressFnKeyHold() -> Bool {
        guard !fnKeyHoldIsDown else { return true }
        guard keyEmitter.keyDownFnHardwareStyle() else { return false }
        fnKeyHoldIsDown = true
        fnHIDDownPosted = true
        return true
    }

    /// - Parameter force: Panic / resign-active: post key-up even if we lost bookkeeping (stuck Wispr).
    func releaseFnKeyHold(force: Bool = false) -> Bool {
        fnKeyHoldIsDown = false
        let shouldPost = force || fnHIDDownPosted
        if fnHIDDownPosted { fnHIDDownPosted = false }
        guard shouldPost else { return true }
        return keyEmitter.keyUpFnHardwareStyle()
    }

    func perform(action: Action) -> Bool {
        switch action {
        case .terminal(let control):
            if case .fnKey = control {
                guard keyEmitter.keyDownFnHardwareStyle() else { return false }
                return keyEmitter.keyUpFnHardwareStyle()
            }
            return keyEmitter.send(control.keyStroke)
        case .sendText(let text):
            return pasteEmitter.pasteText(text, addReturn: false)
        case .runSnippet(let snippet):
            return pasteEmitter.pasteText(snippet, addReturn: true)
        case .toggleCheatSheet, .toggleSnippetMenu, .toggleInjectionEnabled:
            return true
        }
    }
}
