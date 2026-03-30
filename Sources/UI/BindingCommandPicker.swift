import SwiftUI

struct BindingCommandPicker: View {
    let binding: ControllerBinding
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let idx = ActionPresets.index(matching: binding.action) {
                Picker("", selection: Binding(
                    get: { idx },
                    set: { v in
                        appModel.setBindingAction(bindingID: binding.id, action: ActionPresets.all[v].action)
                    }
                )) {
                    ForEach(0 ..< ActionPresets.all.count, id: \.self) { i in
                        Text(ActionPresets.all[i].title).tag(i)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200, alignment: .leading)
            } else {
                Menu {
                    ForEach(0 ..< ActionPresets.all.count, id: \.self) { i in
                        Button(ActionPresets.all[i].title) {
                            appModel.setBindingAction(bindingID: binding.id, action: ActionPresets.all[i].action)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(binding.action.label)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 200, alignment: .leading)
            }
        }
    }
}
