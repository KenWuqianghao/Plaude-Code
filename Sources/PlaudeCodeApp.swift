import AppKit
import SwiftUI

@main
struct PlaudeCodeApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    var body: some Scene {
        /// Captures `openWindow` at launch (before the menu bar window is ever opened).
        WindowGroup(id: "_cheatsheetOpener") {
            CheatsheetWindowRegistrar()
                .environmentObject(appModel)
        }

        MenuBarExtra("Plaude Code", systemImage: "gamecontroller") {
            MenuBarContentView()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }

        WindowGroup(id: "cheatsheet") {
            CheatSheetView()
                .environmentObject(appModel)
        }
    }
}
