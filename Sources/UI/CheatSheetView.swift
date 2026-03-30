import AppKit
import SwiftUI

private struct CheatsheetWindowHost: NSViewRepresentable {
    @EnvironmentObject private var appModel: AppModel

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.isHidden = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            appModel.attachCheatsheetHostWindow(nsView.window)
        }
    }
}

struct CheatSheetView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    private let sectionGap: CGFloat = 14
    private let gridColumns = [
        GridItem(.flexible(minimum: 300), spacing: 10, alignment: .leading),
        GridItem(.flexible(minimum: 300), spacing: 10, alignment: .leading),
        GridItem(.flexible(minimum: 300), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: sectionGap) {
                header

                if let profile = appModel.activeProfile {
                    let grouped = CheatSheetView.grouped(bindings: profile.bindings)
                    ForEach(CheatSheetCategory.allCases.sorted(), id: \.self) { category in
                        if let rows = grouped[category], !rows.isEmpty {
                            section(category.rawValue.uppercased(), rows: rows)
                        }
                    }
                } else {
                    Text("No profile loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 720, idealHeight: 800)
        .background(CheatsheetWindowHost().frame(width: 0, height: 0))
        .onAppear {
            appModel.registerWindowOpeners(cheatsheet: { openWindow(id: "cheatsheet") })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Controller map")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .tracking(-0.4)
            Text(appModel.activeProfile?.name ?? "—")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Last: \(appModel.lastActionLabel)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private func section(_ title: String, rows: [ControllerBinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.0)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.id) { binding in
                    compactRow(binding)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    }
            }
        }
    }

    private func compactRow(_ binding: ControllerBinding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(binding.trigger.descriptionLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 138, alignment: .leading)
                .lineLimit(1)
            Text(binding.action.label)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private static func grouped(bindings: [ControllerBinding]) -> [CheatSheetCategory: [ControllerBinding]] {
        Dictionary(grouping: bindings, by: { $0.action.cheatCategory })
            .mapValues { $0.sorted { $0.trigger.descriptionLabel < $1.trigger.descriptionLabel } }
    }
}

extension InputTrigger {
    var descriptionLabel: String {
        let modifierText = modifiers
            .map(\.rawValue)
            .sorted()
            .joined(separator: " + ")
        if modifierText.isEmpty {
            return button.rawValue
        }
        return "\(modifierText) + \(button.rawValue)"
    }
}
