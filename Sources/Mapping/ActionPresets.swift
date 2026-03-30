import Foundation

/// Picker entries for the mapping editor — defaults in `MappingStore` stay small; this list keeps common extras.
enum ActionPresets {
    struct Entry {
        let title: String
        let subtitle: String
        let action: Action
    }

    static let all: [Entry] = [
        Entry(title: "Enter (submit)", subtitle: "Return", action: .terminal(.enter)),
        Entry(title: "Escape", subtitle: "Cancel", action: .terminal(.escape)),
        Entry(title: "Backspace", subtitle: "Edit line", action: .terminal(.backspace)),
        Entry(title: "Tab", subtitle: "Complete", action: .terminal(.tab)),
        Entry(title: "Arrow up", subtitle: "Up", action: .terminal(.arrowUp)),
        Entry(title: "Arrow down", subtitle: "Down", action: .terminal(.arrowDown)),
        Entry(title: "Arrow left", subtitle: "Left", action: .terminal(.arrowLeft)),
        Entry(title: "Arrow right", subtitle: "Right", action: .terminal(.arrowRight)),
        Entry(title: "Fn", subtitle: "Wispr Flow / system (best-effort)", action: .terminal(.fnKey)),
        Entry(title: "Cmd+Tab", subtitle: "macOS app switcher", action: .terminal(.cmdTab)),
        Entry(title: "Toggle Plaude Code", subtitle: "Stop/start sending keys (default: Share)", action: .toggleInjectionEnabled),
        Entry(title: "Ctrl+C", subtitle: "Interrupt", action: .terminal(.ctrlC)),
        Entry(title: "Ctrl+D", subtitle: "EOF / exit", action: .terminal(.ctrlD)),
        Entry(title: "Ctrl+L", subtitle: "Clear screen", action: .terminal(.ctrlL)),
        Entry(title: "Ctrl+F", subtitle: "Scroll / agents", action: .terminal(.ctrlF)),
        Entry(title: "Option+Left", subtitle: "Word left", action: .terminal(.optionLeft)),
        Entry(title: "Option+Right", subtitle: "Word right", action: .terminal(.optionRight)),
        Entry(title: "Cmd+K", subtitle: "Clear (terminal)", action: .terminal(.cmdK)),
        Entry(title: "/help", subtitle: "Claude Code", action: .runSnippet("/help")),
        Entry(title: "/clear", subtitle: "Claude Code", action: .runSnippet("/clear")),
        Entry(title: "/compact", subtitle: "Claude Code", action: .runSnippet("/compact")),
        Entry(title: "Toggle cheatsheet", subtitle: "This app (default: Options / Create)", action: .toggleCheatSheet),
        Entry(title: "Quick command menu", subtitle: "This app", action: .toggleSnippetMenu)
    ]

    static func index(matching action: Action) -> Int? {
        all.firstIndex(where: { $0.action == action })
    }
}
