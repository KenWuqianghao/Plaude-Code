import Foundation

struct ControllerBinding: Codable, Identifiable, Hashable {
    let id: UUID
    var trigger: InputTrigger
    var action: Action

    init(id: UUID = UUID(), trigger: InputTrigger, action: Action) {
        self.id = id
        self.trigger = trigger
        self.action = action
    }
}

struct MappingProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var bindings: [ControllerBinding]

    init(id: UUID = UUID(), name: String, bindings: [ControllerBinding]) {
        self.id = id
        self.name = name
        self.bindings = bindings
    }

    /// Exact match first, then plain (no-chord) binding for the same button when the trigger has no modifiers.
    func binding(for trigger: InputTrigger) -> ControllerBinding? {
        if let exact = bindings.first(where: { $0.trigger == trigger }) {
            return exact
        }
        if trigger.modifiers.isEmpty {
            return bindings.first(where: {
                $0.trigger.button == trigger.button && $0.trigger.modifiers.isEmpty
            })
        }
        return nil
    }
}
