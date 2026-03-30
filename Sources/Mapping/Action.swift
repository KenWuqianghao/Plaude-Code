import Foundation

enum TerminalControl: String, Codable {
    case enter
    case escape
    case backspace
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case ctrlC
    case ctrlD
    case ctrlL
    case ctrlF
    case optionLeft
    case optionRight
    case cmdK
    /// Hardware Fn (virtual key); many setups use this for Wispr Flow / dictation shortcuts.
    case fnKey
    /// macOS application switcher (⌘ Tab).
    case cmdTab
}

enum CheatSheetCategory: String, CaseIterable, Comparable {
    case navigation = "Navigation"
    case claudeCode = "Claude Code"
    case sessionKeys = "Session keys"
    case appChrome = "Plaude Code"

    static func < (lhs: CheatSheetCategory, rhs: CheatSheetCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .navigation: return 0
        case .sessionKeys: return 1
        case .claudeCode: return 2
        case .appChrome: return 3
        }
    }
}

enum Action: Codable, Hashable {
    case terminal(TerminalControl)
    case sendText(String)
    case runSnippet(String)
    case toggleCheatSheet
    case toggleSnippetMenu
    case toggleInjectionEnabled

    var label: String {
        switch self {
        case .terminal(let control):
            switch control {
            case .enter: return "Enter"
            case .escape: return "Escape"
            case .backspace: return "Backspace"
            case .tab: return "Tab"
            case .arrowUp: return "Up"
            case .arrowDown: return "Down"
            case .arrowLeft: return "Left"
            case .arrowRight: return "Right"
            case .ctrlC: return "Ctrl+C (cancel)"
            case .ctrlD: return "Ctrl+D (exit)"
            case .ctrlL: return "Ctrl+L (clear screen)"
            case .ctrlF: return "Ctrl+F (agents)"
            case .optionLeft: return "Option+Left"
            case .optionRight: return "Option+Right"
            case .cmdK: return "Cmd+K"
            case .fnKey: return "Fn (Wispr / system)"
            case .cmdTab: return "Cmd+Tab (apps)"
            }
        case .sendText(let text):
            return "Type: \(text)"
        case .runSnippet(let snippet):
            return "Run: \(snippet)"
        case .toggleCheatSheet:
            return "Cheatsheet"
        case .toggleSnippetMenu:
            return "Quick menu"
        case .toggleInjectionEnabled:
            return "Toggle Plaude Code on/off"
        }
    }

    var cheatCategory: CheatSheetCategory {
        switch self {
        case .terminal(let c):
            switch c {
            case .ctrlC, .ctrlD, .ctrlL, .ctrlF:
                return .sessionKeys
            case .fnKey, .cmdTab:
                return .appChrome
            default:
                return .navigation
            }
        case .sendText, .runSnippet:
            return .claudeCode
        case .toggleCheatSheet, .toggleSnippetMenu, .toggleInjectionEnabled:
            return .appChrome
        }
    }

    /// If false, skip Ghostty focus checks (app switcher, Plaude Code toggles, overlays, Wispr Fn).
    var expectsGhosttyTarget: Bool {
        switch self {
        case .toggleCheatSheet, .toggleSnippetMenu, .toggleInjectionEnabled:
            return false
        case .terminal(.cmdTab), .terminal(.fnKey):
            return false
        case .terminal, .sendText, .runSnippet:
            return true
        }
    }
}
