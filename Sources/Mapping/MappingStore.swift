import Foundation

enum BindingUpdateResult {
    case ok
    case conflict(existing: ControllerBinding)
}

final class MappingStore {
    private enum Keys {
        static let savedMappings = "PlaudeCode.savedMappings"
        static let activeProfile = "PlaudeCode.activeProfile"
        static let legacySavedMappings = "MacControllerBridge.savedMappings"
        static let legacyActiveProfile = "MacControllerBridge.activeProfile"
        static let appSupportFolder = "PlaudeCode"
        static let legacyAppSupportFolder = "MacControllerBridge"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var profiles: [MappingProfile]

    var activeProfileID: UUID {
        didSet {
            UserDefaults.standard.set(activeProfileID.uuidString, forKey: Keys.activeProfile)
        }
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let loadedProfiles = Self.loadFromDisk(decoder: decoder)
            ?? Self.loadFromUserDefaults(decoder: decoder)
            ?? Self.defaultProfiles()
        var migrated = loadedProfiles
        let stripped = Self.stripTouchpadCheatSheetSpam(&migrated)
        let ensuredCheatsheet = Self.ensureOptionsCheatsheetIfMissing(&migrated)
        self.profiles = migrated

        let resolvedActive: UUID? = {
            for key in [Keys.activeProfile, Keys.legacyActiveProfile] {
                if let raw = UserDefaults.standard.string(forKey: key),
                   let uuid = UUID(uuidString: raw),
                   migrated.contains(where: { $0.id == uuid }) {
                    return uuid
                }
            }
            return nil
        }()
        if let uuid = resolvedActive {
            self.activeProfileID = uuid
        } else {
            self.activeProfileID = migrated.first?.id ?? UUID()
        }

        if profile(id: activeProfileID) == nil, let first = migrated.first {
            self.activeProfileID = first.id
        }

        if stripped || ensuredCheatsheet {
            persist()
        }

        migrateStorageFromLegacyIfNeeded()
    }

    /// Stops capacitive touch → cheatsheet spam from older saved profiles.
    private static func stripTouchpadCheatSheetSpam(_ profiles: inout [MappingProfile]) -> Bool {
        var changed = false
        for i in profiles.indices {
            let before = profiles[i].bindings.count
            profiles[i].bindings.removeAll {
                $0.trigger.button == .touchpad && $0.action == .toggleCheatSheet
            }
            if profiles[i].bindings.count != before { changed = true }
        }
        return changed
    }

    /// Minimal / older saves could omit cheatsheet; then Options had no mapping.
    private static func ensureOptionsCheatsheetIfMissing(_ profiles: inout [MappingProfile]) -> Bool {
        var changed = false
        for i in profiles.indices {
            let hasCheatsheet = profiles[i].bindings.contains {
                if case .toggleCheatSheet = $0.action { return true }
                return false
            }
            guard !hasCheatsheet else { continue }
            let plainOptionsTaken = profiles[i].bindings.contains {
                $0.trigger.button == .options && $0.trigger.modifiers.isEmpty
            }
            guard !plainOptionsTaken else { continue }
            profiles[i].bindings.append(
                ControllerBinding(trigger: InputTrigger(button: .options), action: .toggleCheatSheet)
            )
            changed = true
        }
        return changed
    }

    func profile(id: UUID) -> MappingProfile? {
        profiles.first { $0.id == id }
    }

    @discardableResult
    func updateBinding(profileID: UUID, bindingID: UUID, newTrigger: InputTrigger) -> BindingUpdateResult {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return .ok }
        guard let bindingIndex = profiles[profileIndex].bindings.firstIndex(where: { $0.id == bindingID }) else { return .ok }

        if let conflicting = profiles[profileIndex].bindings.first(where: {
            $0.id != bindingID && $0.trigger == newTrigger
        }) {
            return .conflict(existing: conflicting)
        }

        profiles[profileIndex].bindings[bindingIndex].trigger = newTrigger
        persist()
        return .ok
    }

    func updateAction(profileID: UUID, bindingID: UUID, action: Action) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard let bindingIndex = profiles[profileIndex].bindings.firstIndex(where: { $0.id == bindingID }) else { return }
        profiles[profileIndex].bindings[bindingIndex].action = action
        persist()
    }

    /// Replaces bindings with the built-in essential layout (see `essentialBindings()`).
    func applyBuiltInClaudeLayout(profileID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[profileIndex].bindings = Self.essentialBindings()
        persist()
    }

    func persist() {
        guard let data = try? encoder.encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Keys.savedMappings)
        try? FileManager.default.createDirectory(
            at: Self.storageDirectory,
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.storageFileURL, options: [.atomic])
    }

    /// Copies mappings into `Application Support/PlaudeCode` and new `UserDefaults` keys when upgrading from MacControllerBridge storage.
    private func migrateStorageFromLegacyIfNeeded() {
        let newFile = Self.storageFileURL
        let legacyFile = Self.legacyStorageDirectory.appendingPathComponent("mappings.json")
        let newUDPresent = UserDefaults.standard.data(forKey: Keys.savedMappings) != nil
        let legacyUDPresent = UserDefaults.standard.data(forKey: Keys.legacySavedMappings) != nil
        let newFilePresent = FileManager.default.fileExists(atPath: newFile.path)
        let legacyFilePresent = FileManager.default.fileExists(atPath: legacyFile.path)
        let shouldMigrate = (!newFilePresent && legacyFilePresent) || (!newUDPresent && legacyUDPresent)
        guard shouldMigrate else { return }
        persist()
    }

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Keys.appSupportFolder, isDirectory: true)
    }

    private static var legacyStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Keys.legacyAppSupportFolder, isDirectory: true)
    }

    private static var storageFileURL: URL {
        storageDirectory.appendingPathComponent("mappings.json")
    }

    private static func loadFromDisk(decoder: JSONDecoder) -> [MappingProfile]? {
        if let data = try? Data(contentsOf: storageFileURL),
           let decoded = try? decoder.decode([MappingProfile].self, from: data) {
            return decoded
        }
        let legacyFile = legacyStorageDirectory.appendingPathComponent("mappings.json")
        guard let data = try? Data(contentsOf: legacyFile) else { return nil }
        return try? decoder.decode([MappingProfile].self, from: data)
    }

    private static func loadFromUserDefaults(decoder: JSONDecoder) -> [MappingProfile]? {
        for key in [Keys.savedMappings, Keys.legacySavedMappings] {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? decoder.decode([MappingProfile].self, from: data) else { continue }
            return decoded
        }
        return nil
    }

    private static func defaultProfiles() -> [MappingProfile] {
        [
            MappingProfile(name: "Essential", bindings: essentialBindings()),
            MappingProfile(name: "Minimal", bindings: minimalBindings())
        ]
    }

    /// Default: face + D-pad + L1 app switcher + L2 hold-Fn (Wispr) + Share Plaude Code toggle + Options cheatsheet (touchpad left free).
    private static func essentialBindings() -> [ControllerBinding] {
        [
            ControllerBinding(trigger: InputTrigger(button: .cross), action: .terminal(.enter)),
            ControllerBinding(trigger: InputTrigger(button: .circle), action: .terminal(.escape)),
            ControllerBinding(trigger: InputTrigger(button: .square), action: .terminal(.backspace)),
            ControllerBinding(trigger: InputTrigger(button: .triangle), action: .terminal(.tab)),
            ControllerBinding(trigger: InputTrigger(button: .dpadUp), action: .terminal(.arrowUp)),
            ControllerBinding(trigger: InputTrigger(button: .dpadDown), action: .terminal(.arrowDown)),
            ControllerBinding(trigger: InputTrigger(button: .dpadLeft), action: .terminal(.arrowLeft)),
            ControllerBinding(trigger: InputTrigger(button: .dpadRight), action: .terminal(.arrowRight)),
            ControllerBinding(trigger: InputTrigger(button: .l1), action: .terminal(.cmdTab)),
            ControllerBinding(trigger: InputTrigger(button: .l2), action: .terminal(.fnKey)),
            ControllerBinding(trigger: InputTrigger(button: .share), action: .toggleInjectionEnabled),
            ControllerBinding(trigger: InputTrigger(button: .options), action: .toggleCheatSheet)
        ]
    }

    /// Same as Essential (older Minimal omitted cheatsheet and left Options unused).
    private static func minimalBindings() -> [ControllerBinding] {
        essentialBindings()
    }
}
