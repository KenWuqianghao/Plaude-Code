import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var mappingFilter = ""

    var body: some View {
        NavigationSplitView {
            Form {
                Section {
                    LabeledContent {
                        Label(
                            appModel.controllerConnected ? "Connected" : "Disconnected",
                            systemImage: appModel.controllerConnected ? "checkmark.circle.fill" : "xmark.circle"
                        )
                    } label: {
                        Text("Gamepad")
                    }
                    .foregroundStyle(appModel.controllerConnected ? Color(red: 0.06, green: 0.53, blue: 0.38) : .orange)

                    LabeledContent {
                        Label(
                            appModel.permissions.canInjectKeystrokes ? "Granted" : "Required",
                            systemImage: appModel.permissions.canInjectKeystrokes ? "checkmark.shield" : "exclamationmark.shield"
                        )
                    } label: {
                        Text("Accessibility")
                    }
                    .foregroundStyle(appModel.permissions.canInjectKeystrokes ? Color(red: 0.06, green: 0.53, blue: 0.38) : .orange)

                    Toggle("Inject keys into Ghostty", isOn: $appModel.isInjectionEnabled)
                        .toggleStyle(.switch)
                    Toggle("DualSense touchpad as mouse & scroll", isOn: $appModel.dualSenseTrackpadAsMouse)
                        .toggleStyle(.switch)
                    Toggle("Bring Ghostty forward before send", isOn: $appModel.autoFocusGhostty)
                        .toggleStyle(.switch)
                    Button("Refresh permissions") { appModel.refreshPermissions() }
                }

                Section("Profile") {
                    Picker("Active profile", selection: Binding(
                        get: { appModel.activeProfileID },
                        set: { appModel.activateProfile(id: $0) }
                    )) {
                        ForEach(appModel.mappingStore.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    Button("Restore essential defaults") {
                        appModel.restoreBuiltInClaudeBindings()
                    }
                }

                Section("Reference") {
                    Button("Open cheatsheet") { appModel.presentCheatsheetWindow() }
                }
            }
            .formStyle(.grouped)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor)
                VStack(alignment: .leading, spacing: 0) {
                    editorHeader
                    Divider()
                    mappingEditor
                }
            }
            .frame(minWidth: 640)
            .sheet(isPresented: $appModel.showSnippetMenu) {
                SnippetMenuView(appModel: appModel)
            }
        }
        .onAppear {
            appModel.registerWindowOpeners(
                mappings: { openSettings() },
                cheatsheet: { openWindow(id: "cheatsheet") }
            )
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapping editor")
                        .font(.title2.weight(.semibold))
                        .tracking(-0.4)
                    Text("Face = typing; D-pad = arrows; L1 = Cmd+Tab; L2 = hold Fn (Wispr); Share = toggle Plaude Code; Options = cheatsheet. With “touchpad as mouse”, surface = pointer, two fingers = scroll, press = click (turn off to map touchpad in the table below).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                Spacer()
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by input or command", text: $mappingFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
            }
            Text("Last: \(appModel.lastActionLabel)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private var mappingEditor: some View {
        let rows = filteredBindings.sorted {
            $0.trigger.descriptionLabel.localizedCaseInsensitiveCompare($1.trigger.descriptionLabel) == .orderedAscending
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, binding in
                    mappingRow(binding)
                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
                    }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filteredBindings: [ControllerBinding] {
        let q = mappingFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appModel.activeBindings }
        return appModel.activeBindings.filter {
            $0.trigger.descriptionLabel.lowercased().contains(q)
                || $0.action.label.lowercased().contains(q)
        }
    }

    private func mappingRow(_ binding: ControllerBinding) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(binding.trigger.descriptionLabel)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 168, alignment: .leading)
            BindingCommandPicker(binding: binding)
                .environmentObject(appModel)
            Spacer(minLength: 8)
            remapButton(for: binding)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func remapButton(for binding: ControllerBinding) -> some View {
        let capturing = appModel.remapCaptureTarget == binding.id
        return Button {
            appModel.remapCaptureTarget = capturing ? nil : binding.id
        } label: {
            Text(capturing ? "Press a button…" : "Capture input")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(capturing ? Color(red: 0.12, green: 0.36, blue: 0.52) : nil)
        .fixedSize()
    }
}

struct SnippetMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appModel: AppModel

    private var items: [(String, Action)] {
        ActionPresets.all.compactMap { entry -> (String, Action)? in
            switch entry.action {
            case .runSnippet, .sendText:
                return (entry.title, entry.action)
            default:
                return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Claude Code commands")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 6)
            Text("Inserts and runs a slash command in the focused terminal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button {
                            let ok = appModel.performSnippet(item.1)
                            appModel.lastActionLabel = ok ? "Sent: \(item.0)" : "Failed: \(item.0)"
                            dismiss()
                        } label: {
                            HStack {
                                Text(item.0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        }
                    }
                }
            }
            Button("Close") { dismiss() }
                .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 360, height: 420)
    }
}
