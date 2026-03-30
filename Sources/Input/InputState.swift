import Foundation

enum ControllerButton: String, Codable, CaseIterable {
    case cross
    case circle
    case square
    case triangle
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case l1
    case r1
    case l2
    case r2
    case l3
    case r3
    case options
    case share
    case touchpad
    case ps
}

enum InputPhase: String, Codable {
    case pressed
    case repeated
    case released
}

struct InputTrigger: Hashable, Codable {
    var button: ControllerButton
    var modifiers: Set<ControllerButton> = []
    var holdThresholdMs: Int = 0
}

struct InputEvent {
    let trigger: InputTrigger
    let phase: InputPhase
    let timestamp: Date

    var isPanicCombo: Bool {
        let panicSet: Set<ControllerButton> = [.l1, .r1, .options]
        let all = trigger.modifiers.union([trigger.button])
        return panicSet.isSubset(of: all)
    }
}
