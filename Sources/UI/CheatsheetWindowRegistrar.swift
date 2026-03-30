import AppKit
import SwiftUI

/// Registers `openWindow(id: "cheatsheet")` at process start. `MenuBarExtra` window content often
/// does not load until the user opens the menu bar UI once, so controller-triggered cheatsheet
/// would otherwise call a nil opener.
struct CheatsheetWindowRegistrar: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CheatsheetOpenerHookView(openCheatsheet: { openWindow(id: "cheatsheet") })
            .environmentObject(appModel)
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}

/// Grabs the hosting `NSWindow` once so we can hide the hook window immediately after wiring `openWindow`.
private struct CheatsheetOpenerHookView: NSViewRepresentable {
    @EnvironmentObject private var appModel: AppModel
    var openCheatsheet: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        v.isHidden = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.didRegister { return }
        context.coordinator.didRegister = true
        appModel.registerWindowOpeners(cheatsheet: openCheatsheet)
        window.orderOut(nil)
        window.isExcludedFromWindowsMenu = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didRegister = false
    }
}
