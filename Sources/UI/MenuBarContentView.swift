import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plaude Code")
                .font(.headline)
            Label(
                appModel.controllerConnected ? "Gamepad wired (getting input)" : "No gamepad input profile",
                systemImage: appModel.controllerConnected ? "checkmark.circle.fill" : "xmark.circle"
            )
            .foregroundStyle(appModel.controllerConnected ? .green : .secondary)

            Label(
                appModel.permissions.canInjectKeystrokes ? "Accessibility OK (can send keys)" : "Allow Accessibility for this app",
                systemImage: appModel.permissions.canInjectKeystrokes ? "lock.open.fill" : "lock.fill"
            )
            .foregroundStyle(appModel.permissions.canInjectKeystrokes ? .green : .orange)

            Text("Last action: \(appModel.lastActionLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack(spacing: 8) {
                Button("Mappings") { appModel.presentMainWindow() }
                Button("Cheatsheet") { appModel.presentCheatsheetWindow() }
                Button("Fn tap") {
                    let ok = appModel.performSnippet(.terminal(.fnKey))
                    appModel.lastActionLabel = ok ? "Fn tap" : "Fn failed — Accessibility?"
                }
                .disabled(!appModel.permissions.canInjectKeystrokes)
            }

            Toggle("Enable action injection", isOn: $appModel.isInjectionEnabled)
            Toggle("Auto-focus Ghostty", isOn: $appModel.autoFocusGhostty)
            Button("Refresh permissions") {
                appModel.refreshPermissions()
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            appModel.registerWindowOpeners(
                mappings: { openSettings() },
                cheatsheet: { openWindow(id: "cheatsheet") }
            )
        }
        .sheet(isPresented: $appModel.showSnippetMenu) {
            SnippetMenuView(appModel: appModel)
        }
    }
}
