import Foundation
import CoreGraphics

// Keys for persistence
private let kRemappingEnabledKey = "remappingEnabled"
private let kCurrentProfileKey = "currentProfile"

/// Route definition used by the fixed codec. The optional legacy fields remain
/// decodable so older profile files can still be imported safely.
struct HardwareKey: Codable, Equatable {
    var usagePage: UInt32
    var usage: UInt32
    var keyCode: Int
    var displayString: String
    var groupId: String?
    var interceptEnabled: Bool?   // nil = default true (backward compatible)
    var modifierFlags: UInt64? = nil
    var timestampOffsetNs: Int64? = nil
    var timestampToleranceNs: UInt64? = nil
    var valueDirection: Int? = nil
    var eventDirection: Int? = nil
    /// When the learned onboard shortcut contains Command or Control, suppress
    /// that original shortcut and repost it with those two modifiers swapped.
    /// Optional for backward-compatible decoding of every existing config.
    var swapCommandControl: Bool? = nil

    var isIntercepted: Bool { interceptEnabled ?? true }
    var isCommandControlSwapEnabled: Bool { swapCommandControl ?? false }
    var hasCommandOrControlModifier: Bool {
        let flags = CGEventFlags(rawValue: modifierFlags ?? 0)
        return flags.contains(.maskCommand) || flags.contains(.maskControl)
    }
    /// Normal Mac mapping wins when it is enabled. The modifier transform is
    /// the independent fallback used while the onboard input would otherwise
    /// pass through.
    var usesCommandControlTransform: Bool {
        !isIntercepted && isCommandControlSwapEnabled && hasCommandOrControlModifier
    }
    var requiresRuntimeInterception: Bool {
        isIntercepted || usesCommandControlTransform
    }
}


struct ProfilesFile: Codable {
    var profiles: [String: Profile]
    var settings: Settings?
    /// Full per-device state (learned tables, profile mounts, custom sources,
    /// names…) so "export all" is a complete backup that restores identically.
    var deviceConfigurations: [String: DeviceConfiguration]?
    /// Present only in a full backup. A single-profile export must remain
    /// portable and must not alter another Mac's hardware identity policy.
    var identityRules: DeviceIdentityRuleArchive? = nil
}

struct Settings: Codable {
    var currentProfile: String?
    var autoSwitchProfiles: Bool?
    var showNotifications: Bool?
    var reverseScrollWheel: Bool?
    var hardwareMapping: [String: HardwareKey]?
}

struct Profile: Codable {
    var buttons: [String: ButtonAction]
}

/// A user-visible input group owned by one device. The three stable IDs keep
/// the legacy side/DPI/wheel sections backward compatible; UUID-backed IDs are
/// user-created groups. Source indices live in exactly one normalized group.
struct DeviceInputGroup: Codable, Equatable, Identifiable {
    static let sideID = "side"
    static let dpiID = "dpi"
    static let scrollID = "scroll"
    static let builtInIDs: Set<String> = [sideID, dpiID, scrollID]

    var id: String
    var title: String?
    var sourceIndices: [Int]

    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }
}

struct PendingCustomInput: Equatable {
    let sourceIndex: Int
    let ordinal: Int
    let groupID: String
}

/// Device-scoped aliases for physical inputs that emit the same observable
/// HID signature. They may have separate names and display groups, but the OS
/// cannot distinguish them at runtime, so they route through one canonical
/// logical source deterministically.
struct HardwareSignalAliasGroup: Codable, Equatable, Identifiable {
    var id: String
    var usagePage: UInt32
    var usage: UInt32
    var valueDirection: Int
    var canonicalSourceIndex: Int
    var memberSourceIndices: [Int]
}

/// Everything scoped to one persistent device identity: VID/PID is the stable
/// base, while opted-in device families may append a reliable serial number to
/// distinguish same-model units. Transport and location remain display/debug
/// facts and never split one physical device's persistent configuration.
struct DeviceConfiguration: Codable, Equatable {
    var hardwareMapping: [String: HardwareKey]?
    /// Legacy (pre-device-first) binding. Read only as a migration source.
    var boundProfile: String?
    /// The device's ORIGINAL product name as reported by HID. Auto-updated on
    /// every connect; never edited by the user.
    var displayName: String?
    /// User-defined button names by source index ("1"…"16"), e.g. 侧键1 → "xxx".
    var customNames: [String: String]?
    /// User-defined mapping-window section titles by section key
    /// ("side" / "dpi" / "scroll"), e.g. 侧键 1–12 → "MMO 键区".
    var customSectionTitles: [String: String]?
    /// Profiles mounted on this device, in user order. A name appearing in
    /// several devices' lists means those devices share that profile.
    var profileRefs: [String]?
    /// The profile this device's buttons execute. Nil is an intentional,
    /// supported state when the user unmounts the device's last profile.
    var activeProfile: String?
    /// Raw HID transport of the identity ("USB" / "Bluetooth" …), remembered
    /// so offline devices still display their connection kind.
    var transport: String?
    /// User-chosen display name. Kept apart from `displayName` so a reconnect
    /// can never clobber the user's rename, and the original stays visible in
    /// the device-details panel.
    var customDisplayName: String?
    /// Identity snapshot (device-identification facts), persisted so the
    /// details panel works while the device is offline.
    var vendorID: Int?
    var productID: Int?
    var serialNumber: String?
    var lastLocationID: Int?
    var descriptorFingerprint: String?
    var codecBacked: Bool?
    /// Archived devices are hidden from the runtime and the status-bar list
    /// and collapsed into the sidebar's archived group, but keep every
    /// setting so unarchiving restores them intact.
    var archived: Bool?
    /// Extra learnable input sources beyond the fixed 1–16 layout, so mice or
    /// keyboards with more buttons can be adapted. Stored as source indices
    /// (17+); their names live in customNames like the standard sources.
    var customSourceIndices: [Int]?
    /// Standard 1–16 sources the user removed for this device (e.g. a mouse
    /// with only 8 side keys). Hidden from the sheet and grid; recoverable.
    var removedStandardIndices: [Int]?
    /// Ordered device-owned groups. Optional for backward decoding; legacy
    /// configurations are normalized from the fixed sections on first load.
    var inputGroups: [DeviceInputGroup]?
    /// Monotonic auto-name sequence. Deleting 自定义键N never reuses N.
    var nextCustomSourceOrdinal: Int?
    /// Duplicate observable HID signals, normalized from `hardwareMapping`.
    /// Kept separate from `inputGroups`, which controls only UI organization.
    var signalAliasGroups: [HardwareSignalAliasGroup]?
}

struct ButtonAction: Codable {
    let type: String
    let keys: [KeyStroke]? // for keySequence
    let description: String?
    let path: String? // for application
    let command: String? // for systemCommand
    let text: String? // for textSnippet
    let steps: [MacroStep]? // for macro
    let profile: String? // for profileSwitch
    let mouseButton: Int? // for mouseClick
    let systemAction: String? // for predefined macOS actions
    let target: String? // for files, folders and URLs
    let scrollControl: ScrollControlRole? // held Mos-style scroll controls
}

final class ConfigManager {
    static let shared = ConfigManager()
    /// Purely visual/device-metadata changes. Runtime consumers must not react
    /// by dropping held keys or rebuilding interception tables.
    static let presentationDidChangeNotification = Notification.Name("NagaController.presentationDidChange")
    /// Profile names, mounts and sidebar structure changed.
    static let profileStructureDidChangeNotification = Notification.Name("NagaController.profileStructureDidChange")
    /// Hardware definitions, active profiles or actions changed in a way that
    /// affects event routing/execution.
    static let runtimeRoutingDidChangeNotification = Notification.Name("NagaController.runtimeRoutingDidChange")
    static let runtimeSettingsDidChangeNotification = Notification.Name("NagaController.runtimeSettingsDidChange")
    static let saveStateDidChangeNotification = Notification.Name("NagaController.saveStateDidChange")

    private(set) var profiles: [String: Profile] = [:]
    private(set) var currentProfileName: String = "Default"
    private(set) var lastProfileSaveError: String?

    private init() {}

    private func postPresentationChange() {
        NotificationCenter.default.post(name: Self.presentationDidChangeNotification, object: self)
    }

    private func postProfileStructureChange() {
        NotificationCenter.default.post(name: Self.profileStructureDidChangeNotification, object: self)
    }

    private func postRuntimeRoutingChange() {
        NotificationCenter.default.post(name: Self.runtimeRoutingDidChangeNotification, object: self)
    }

    enum IdentityRuleMigrationError: LocalizedError {
        case conflictingConfigurations(String, String)

        var errorDescription: String? {
            switch self {
            case .conflictingConfigurations(let oldKey, let newKey):
                return L10n.format("身份规则会将「%@」合并到「%@」，但两者配置不同。未保存规则，以避免覆盖。", oldKey, newKey)
            }
        }
    }

    enum IdentityRuleConflictResolution {
        case reject
        case keepSource
        case keepDestination
    }

    /// Atomically prepares per-device configuration keys before committing one
    /// VID/PID rule override. Every live interface in the family is evaluated;
    /// incompatible merges are rejected instead of choosing a winner silently.
    func applyIdentityRuleOverride(
        _ overrideRule: DeviceIdentityRule?,
        forBaseKey baseKey: String,
        candidates: [HIDDeviceCandidateSummary]? = nil,
        conflictResolution: IdentityRuleConflictResolution = .reject
    ) throws {
        let normalizedBase = baseKey.lowercased()
        let familyCandidates = (candidates ?? HIDListener.shared.deviceCandidates)
            .filter { $0.baseDeviceKey == normalizedBase }
        let previousConfigurations = getDeviceConfigurations()
        var migrated = previousConfigurations

        var moves: [(old: String, new: String)] = []
        for candidate in familyCandidates {
            let facts = candidate.observedIdentityFacts
            let oldKey = DeviceIdentityPolicy.deviceKey(facts: facts)
            let replacement = overrideRule
                ?? DeviceIdentityRuleStore.builtInDefaultRule(
                    baseKey: normalizedBase,
                    codecIdentifier: facts.codecIdentifier
                )
            let newKey = DeviceIdentityRuleEvaluator.deviceKey(facts: facts, rule: replacement)
            if oldKey != newKey, !moves.contains(where: { $0.old == oldKey && $0.new == newKey }) {
                moves.append((oldKey, newKey))
            }
        }

        // Disabling enhancement can also migrate offline instance records. It
        // is safe because the destination is the explicitly selected base key.
        if overrideRule?.enhancedRecognitionEnabled == false {
            for key in migrated.keys where DeviceIdentityPolicy.baseKey(from: key) == normalizedBase && key != normalizedBase {
                if !moves.contains(where: { $0.old == key && $0.new == normalizedBase }) {
                    moves.append((key, normalizedBase))
                }
            }
        }

        migrated = try Self.migratedIdentityConfigurations(
            migrated,
            moves: moves.map { ($0.old, $0.new) },
            conflictResolution: conflictResolution
        )

        guard setDeviceConfigurations(migrated) else {
            throw NSError(
                domain: "ConfigManager.DeviceConfigurations",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("设备配置编码失败，当前更改未保存")]
            )
        }
        do {
            if let overrideRule {
                try DeviceIdentityRuleStore.shared.setOverride(overrideRule)
            } else {
                try DeviceIdentityRuleStore.shared.removeOverride(for: normalizedBase)
            }
        } catch {
            setDeviceConfigurations(previousConfigurations)
            throw error
        }
        postPresentationChange()
        postRuntimeRoutingChange()
        HIDListener.shared.refreshIdentityRules()
    }

    /// Pure migration primitive shared with regression tests.
    static func migratedIdentityConfigurations(
        _ configurations: [String: DeviceConfiguration],
        moves: [(String, String)],
        conflictResolution: IdentityRuleConflictResolution = .reject
    ) throws -> [String: DeviceConfiguration] {
        var migrated = configurations
        for (oldKey, newKey) in moves {
            guard let source = migrated[oldKey] else { continue }
            if let destination = migrated[newKey], destination != source {
                switch conflictResolution {
                case .reject:
                    throw IdentityRuleMigrationError.conflictingConfigurations(oldKey, newKey)
                case .keepSource:
                    migrated[newKey] = source
                case .keepDestination:
                    break
                }
            } else {
                migrated[newKey] = source
            }
            // Keep the VID/PID base as a future split template. Enhanced records
            // moving back to the base are retired after conflict resolution.
            if DeviceIdentityPolicy.isEnhanced(oldKey), !DeviceIdentityPolicy.isEnhanced(newKey) {
                migrated.removeValue(forKey: oldKey)
            }
        }
        return migrated
    }

    func load() {
        migrateLegacyBundlePreferencesIfNeeded()
        // Load bundled defaults first
        var mergedProfiles: [String: Profile] = [:]
        var mergedSettings: Settings? = nil
        if let url = Bundle.main.url(forResource: "default-profiles", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let pf = try JSONDecoder().decode(ProfilesFile.self, from: data)
                mergedProfiles = pf.profiles
                mergedSettings = pf.settings
            } catch {
                NSLog("[Config] Failed to load bundled defaults: \(error.localizedDescription)")
            }
        } else {
            NSLog("[Config] default-profiles.json not found in bundle")
        }

        // Overlay with user profiles if present
        if let userURL = try? userProfilesURL(), FileManager.default.fileExists(atPath: userURL.path) {
            do {
                let userData = try Data(contentsOf: userURL)
                let upf = try JSONDecoder().decode(ProfilesFile.self, from: userData)
                // Overlay: replace/merge profiles
                for (name, profile) in upf.profiles { mergedProfiles[name] = profile }
                // Overlay settings
                if let s = upf.settings { mergedSettings = s }
            } catch {
                NSLog("[Config] Failed to load user profiles: \(error.localizedDescription)")
            }
        }

        // Adopt merged
        self.profiles = mergedProfiles

        // A standalone hardware definition in UserDefaults is authoritative.
        // Import older profile files only when no local definition exists yet.
        if UserDefaults.standard.data(forKey: "hardwareMapping") == nil,
           let importedHardware = mergedSettings?.hardwareMapping,
           !importedHardware.isEmpty {
            setHardwareMapping(importedHardware)
        }

        // Preferred profile: UserDefaults > settings.currentProfile > "Default"
        let ud = UserDefaults.standard
        migrateLegacyScrollSettingsIfNeeded()
        if let saved = ud.string(forKey: kCurrentProfileKey) {
            currentProfileName = saved
        } else if let bundled = mergedSettings?.currentProfile {
            currentProfileName = bundled
        } else {
            currentProfileName = "Default"
        }

        migrateToDeviceFirstIfNeeded()
        migrateInputGroupsIfNeeded()

        // Prime the runtime fallback table; per-device tables follow via
        // HIDListener's notification observer once devices are consumed.
        let mapping = runtimeFallbackProfileName().map { mappingForProfile(named: $0) } ?? [:]
        if mapping.isEmpty {
            applyFallbackMapping()
        } else {
            ButtonMapper.shared.updateMapping(mapping)
        }
    }

    /// The public bundle identity changed from the historical placeholder.
    /// Copy only missing keys once so existing test users keep their devices,
    /// mappings, language and scroll preferences after installing the renamed
    /// release. Application Support profile storage already has a stable path.
    func migrateLegacyBundlePreferencesIfNeeded() {
        let marker = "vmouse.bundleIdentityMigration.v1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: marker) else { return }
        for legacyDomain in ["com.example.NagaController"] {
            guard let values = defaults.persistentDomain(forName: legacyDomain) else { continue }
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
    }

    func setCurrentProfile(_ name: String) {
        guard profiles[name] != nil else { return }
        currentProfileName = name
        UserDefaults.standard.set(name, forKey: kCurrentProfileKey)
        refreshRuntimeMappings()
        // Interception is profile-sensitive: a source without a Mac custom
        // value must remain pass-through in the newly selected profile.
        postRuntimeRoutingChange()
    }

    func getRemappingEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: kRemappingEnabledKey)
    }

    func setRemappingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: kRemappingEnabledKey)
    }

    func getReverseScrollWheel() -> Bool {
        let settings = getScrollSettings()
        return settings.enabled && settings.reverse
    }

    func setReverseScrollWheel(_ enabled: Bool) {
        var settings = getScrollSettings()
        settings.enabled = enabled
        settings.reverse = enabled
        setScrollSettings(settings)
    }

    func getReverseHorizontalScrollWheel() -> Bool {
        getScrollSettings().reverseHorizontal
    }

    func setReverseHorizontalScrollWheel(_ enabled: Bool) {
        var settings = getScrollSettings()
        settings.reverseHorizontal = enabled
        setScrollSettings(settings)
    }

    private var scrollSettingsCache: ScrollSettings?
    private var scrollSettingsLock = os_unfair_lock()

    func getScrollSettings() -> ScrollSettings {
        os_unfair_lock_lock(&scrollSettingsLock)
        defer { os_unfair_lock_unlock(&scrollSettingsLock) }
        if let cached = scrollSettingsCache { return cached }
        let loaded: ScrollSettings
        if let data = UserDefaults.standard.data(forKey: "scrollSettings"),
           let decoded = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            loaded = decoded.validated()
        } else {
            loaded = .defaults
        }
        scrollSettingsCache = loaded
        return loaded
    }

    func setScrollSettings(_ settings: ScrollSettings) {
        let settings = settings.validated()
        os_unfair_lock_lock(&scrollSettingsLock)
        scrollSettingsCache = settings
        os_unfair_lock_unlock(&scrollSettingsLock)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "scrollSettings")
        }
        NotificationCenter.default.post(name: Self.runtimeSettingsDidChangeNotification, object: self)
    }

    private func migrateLegacyScrollSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: "scrollSettings") == nil else { return }
        var settings = ScrollSettings.defaults
        if defaults.object(forKey: "reverseScrollWheel") != nil {
            settings.enabled = defaults.bool(forKey: "reverseScrollWheel")
            settings.reverse = settings.enabled
            settings.reverseHorizontal = defaults.bool(forKey: "reverseHorizontalScrollWheel")
        }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: "scrollSettings")
        }
    }

    func getCorrelationOffsetNs() -> Int64 {
        Int64(UserDefaults.standard.integer(forKey: "correlationOffsetNs"))
    }

    func getCorrelationToleranceNs() -> UInt64 {
        let stored = UserDefaults.standard.integer(forKey: "correlationToleranceNs")
        return stored > 0 ? UInt64(stored) : 8_000_000
    }

    func setCorrelationTiming(offsetNs: Int64, toleranceNs: UInt64) {
        UserDefaults.standard.set(offsetNs, forKey: "correlationOffsetNs")
        UserDefaults.standard.set(Int(min(toleranceNs, UInt64(Int.max))), forKey: "correlationToleranceNs")
    }

    private var hardwareMappingCache: [String: HardwareKey] = [:]
    private var hardwareMappingLoaded = false
    private var hardwareMappingLock = os_unfair_lock()

    // MARK: - Per-device configuration

    private static let deviceConfigurationsKey = "deviceConfigurations"
    private static let deviceAliasesKey = "deviceAliases"
    private var deviceConfigurationsCache: [String: DeviceConfiguration]?
    private var deviceConfigurationsLock = os_unfair_lock()
    private var deviceAliasesCache: [String: String]?
    private var deviceAliasesLock = os_unfair_lock()

    /// The device group whose hardware table the mapping UI is editing.
    /// Explicit UI state — never inferred from runtime input any more.
    private(set) var editingDeviceKey: String?

    // MARK: - Device aliases (one mouse reachable over USB and Bluetooth)

    func getDeviceAliases() -> [String: String] {
        os_unfair_lock_lock(&deviceAliasesLock)
        defer { os_unfair_lock_unlock(&deviceAliasesLock) }
        if let cached = deviceAliasesCache { return cached }
        let loaded = (UserDefaults.standard.dictionary(forKey: Self.deviceAliasesKey) as? [String: String]) ?? [:]
        deviceAliasesCache = loaded
        return loaded
    }

    /// Device-first model: every VID/PID family is a configuration group unless
    /// that family opts into an enhanced, stable per-instance identifier.
    /// Kept as a funnel so historical call sites stay uniform; alias resolution
    /// was retired (sharing now happens at the profile level).
    func configKey(forDeviceKey deviceKey: String) -> String {
        deviceKey
    }

    func getDeviceConfigurations() -> [String: DeviceConfiguration] {
        os_unfair_lock_lock(&deviceConfigurationsLock)
        defer { os_unfair_lock_unlock(&deviceConfigurationsLock) }
        return loadDeviceConfigurationsLocked()
    }

    private func loadDeviceConfigurationsLocked() -> [String: DeviceConfiguration] {
        if let cached = deviceConfigurationsCache { return cached }
        let loaded: [String: DeviceConfiguration]
        if let data = UserDefaults.standard.data(forKey: Self.deviceConfigurationsKey),
           let decoded = try? JSONDecoder().decode([String: DeviceConfiguration].self, from: data) {
            loaded = decoded
        } else {
            loaded = [:]
        }
        deviceConfigurationsCache = loaded
        return loaded
    }

    @discardableResult
    private func setDeviceConfigurations(_ configurations: [String: DeviceConfiguration]) -> Bool {
        os_unfair_lock_lock(&deviceConfigurationsLock)
        defer { os_unfair_lock_unlock(&deviceConfigurationsLock) }
        guard let data = try? JSONEncoder().encode(configurations) else {
            reportDeviceConfigurationSaveFailure()
            return false
        }
        deviceConfigurationsCache = configurations
        UserDefaults.standard.set(data, forKey: Self.deviceConfigurationsKey)
        return true
    }

    @discardableResult
    func updateDeviceConfiguration(forKey deviceKey: String, _ body: (inout DeviceConfiguration) -> Void) -> Bool {
        os_unfair_lock_lock(&deviceConfigurationsLock)
        defer { os_unfair_lock_unlock(&deviceConfigurationsLock) }
        var configurations = loadDeviceConfigurationsLocked()
        var configuration = configurations[deviceKey] ?? DeviceConfiguration()
        body(&configuration)
        configurations[deviceKey] = configuration
        guard let data = try? JSONEncoder().encode(configurations) else {
            reportDeviceConfigurationSaveFailure()
            return false
        }
        deviceConfigurationsCache = configurations
        UserDefaults.standard.set(data, forKey: Self.deviceConfigurationsKey)
        return true
    }

    /// Atomic whole-store mutation for operations that touch several device
    /// records (profile rename/import/migration). Encoding and persistence stay
    /// inside the same lock so an older writer cannot land after a newer one.
    @discardableResult
    private func updateDeviceConfigurations(_ body: (inout [String: DeviceConfiguration]) -> Void) -> Bool {
        os_unfair_lock_lock(&deviceConfigurationsLock)
        defer { os_unfair_lock_unlock(&deviceConfigurationsLock) }
        var configurations = loadDeviceConfigurationsLocked()
        body(&configurations)
        guard let data = try? JSONEncoder().encode(configurations) else {
            reportDeviceConfigurationSaveFailure()
            return false
        }
        deviceConfigurationsCache = configurations
        UserDefaults.standard.set(data, forKey: Self.deviceConfigurationsKey)
        return true
    }

    private func reportDeviceConfigurationSaveFailure() {
        NSLog("[Config] Failed to encode device configurations; in-memory state was not changed")
        DispatchQueue.main.async {
            self.lastProfileSaveError = L10n.text("设备配置编码失败，当前更改未保存")
            NotificationCenter.default.post(name: Self.saveStateDidChangeNotification, object: self)
        }
    }

    // MARK: - Device-first profiles (mounting, sharing, activation)

    /// Default used only to seed new and legacy device records.
    func defaultProfileName() -> String {
        if profiles["Default"] != nil { return "Default" }
        return profiles.keys.sorted().first ?? "Default"
    }

    /// The profile whose actions a device's buttons execute. An explicit
    /// `profileRefs == []` is a deliberate zero-profile state and must not be
    /// replaced by Default on reconnect or runtime refresh.
    static func resolvedProfileName(
        for configuration: DeviceConfiguration?,
        profileExists: (String) -> Bool,
        fallbackProfile: String
    ) -> String? {
        if let refs = configuration?.profileRefs {
            if let active = configuration?.activeProfile,
               refs.contains(active), profileExists(active) { return active }
            return refs.first(where: profileExists)
        }
        if let active = configuration?.activeProfile, profileExists(active) { return active }
        if let bound = configuration?.boundProfile, profileExists(bound) { return bound }
        return fallbackProfile
    }

    func effectiveProfileName(forDeviceKey deviceKey: String) -> String? {
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]
        return Self.resolvedProfileName(
            for: configuration,
            profileExists: { profiles[$0] != nil },
            fallbackProfile: defaultProfileName()
        )
    }

    /// Profiles mounted on a device, in user order. An explicit empty array is
    /// preserved; dangling names (deleted profiles) are hidden.
    func profileNames(forDeviceKey deviceKey: String) -> [String] {
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]
        var names = (configuration?.profileRefs ?? []).filter { profiles[$0] != nil }
        if let active = effectiveProfileName(forDeviceKey: deviceKey), !names.contains(active) {
            names.append(active)
        }
        return names
    }

    /// Devices whose mounted list references a profile — the "used by" facts
    /// shown in the profile header.
    func deviceKeysUsing(profile name: String) -> [String] {
        getDeviceConfigurations()
            .filter { _, configuration in
                configuration.profileRefs?.contains(name) == true || configuration.activeProfile == name
            }
            .keys
            .sorted()
    }

    /// Switch which mounted profile a device executes. Unmounted names are
    /// mounted on the fly (profileSwitch actions may target any profile).
    func setActiveProfile(_ name: String, forDeviceKey deviceKey: String) {
        guard profiles[name] != nil else { return }
        guard updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey), { configuration in
            var refs = configuration.profileRefs ?? []
            if !refs.contains(name) { refs.append(name) }
            configuration.profileRefs = refs
            configuration.activeProfile = name
        }) else { return }
        refreshRuntimeMappings()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    /// Create a profile under a device. Names are global storage keys, so a
    /// clash gets a numeric suffix; the final name is returned.
    @discardableResult
    func createProfile(name: String, underDeviceKey deviceKey: String, basedOn base: String? = nil, activate: Bool = true) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let previousConfigurations = getDeviceConfigurations()
        var candidate = trimmed
        var suffix = 2
        while profiles[candidate] != nil {
            candidate = "\(trimmed) \(suffix)"
            suffix += 1
        }
        if let base, let baseProfile = profiles[base] {
            profiles[candidate] = baseProfile
        } else {
            profiles[candidate] = Profile(buttons: [:])
        }
        guard updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey), { configuration in
            var refs = configuration.profileRefs ?? []
            refs.append(candidate)
            configuration.profileRefs = refs
            if activate { configuration.activeProfile = candidate }
        }) else {
            profiles.removeValue(forKey: candidate)
            return nil
        }
        guard saveUserProfiles() else {
            profiles.removeValue(forKey: candidate)
            _ = setDeviceConfigurations(previousConfigurations)
            return nil
        }
        refreshRuntimeMappings()
        postProfileStructureChange()
        postRuntimeRoutingChange()
        return candidate
    }

    /// Mount an existing profile (typically another device's) onto a device.
    /// Both devices then edit the same underlying action table.
    func shareProfile(_ name: String, withDeviceKey deviceKey: String, activate: Bool = false) {
        guard profiles[name] != nil else { return }
        guard updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey), { configuration in
            var refs = configuration.profileRefs ?? []
            if !refs.contains(name) { refs.append(name) }
            configuration.profileRefs = refs
            if activate { configuration.activeProfile = name }
        }) else { return }
        refreshRuntimeMappings()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    /// Unmount a profile from one device without touching the stored profile
    /// or other devices that share it. Removing the last mounted profile leaves
    /// an explicit zero-profile device; the legacy binding is cleared so the
    /// removed profile cannot be resurrected through migration fallback.
    static func configurationByRemovingProfile(
        _ name: String,
        from configuration: DeviceConfiguration,
        profileExists: (String) -> Bool
    ) -> DeviceConfiguration {
        var updated = configuration
        let refs = (configuration.profileRefs ?? []).filter { $0 != name && profileExists($0) }
        updated.activeProfile = updated.activeProfile.flatMap {
            $0 != name && profileExists($0) && refs.contains($0) ? $0 : nil
        } ?? refs.first
        updated.profileRefs = refs
        if updated.boundProfile == name { updated.boundProfile = nil }
        return updated
    }

    func removeProfile(_ name: String, fromDeviceKey deviceKey: String) {
        guard updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey), { configuration in
            configuration = Self.configurationByRemovingProfile(
                name,
                from: configuration,
                profileExists: { profiles[$0] != nil }
            )
        }) else { return }
        refreshRuntimeMappings()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    /// Legacy accessor retained for the migration path and diagnostics.
    func boundProfile(forDeviceKey deviceKey: String) -> String? {
        getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?.boundProfile
    }

    /// Deprecated shim for pre-device-first callers: binding a profile now
    /// means activating it on the device.
    func setBoundProfile(_ profile: String?, forDeviceKey deviceKey: String) {
        if let profile { setActiveProfile(profile, forDeviceKey: deviceKey) }
    }

    /// Push fresh action tables to the runtime. Per-device tables rebuild via
    /// HIDListener's notification observer; the global table is the fallback
    /// for events without a device identity and follows the device that
    /// produced input most recently.
    func refreshRuntimeMappings() {
        let mapping = runtimeFallbackProfileName().map { mappingForProfile(named: $0) } ?? [:]
        ButtonMapper.shared.updateMapping(mapping)
    }

    private func runtimeFallbackProfileName() -> String? {
        if let last = HIDListener.shared.lastInputDeviceKey {
            return effectiveProfileName(forDeviceKey: last)
        }
        if let consumed = HIDListener.shared.consumedDeviceKeys.sorted().first {
            return effectiveProfileName(forDeviceKey: consumed)
        }
        return defaultProfileName()
    }

    // MARK: - One-shot device-first migration

    private static let deviceFirstMigratedKey = "deviceFirstMigrated"

    /// Pure device-first fold, separated from UserDefaults so migration
    /// scenarios are unit-testable: alias sources become standalone devices
    /// carrying a copy of their primary's device-level data, then every
    /// device adopts its legacy effective profile (bound ?? global current ??
    /// fallback) as its active profile.
    static func deviceFirstMigratedConfigurations(
        _ input: [String: DeviceConfiguration],
        aliases: [String: String],
        legacyCurrentProfile: String?,
        profileExists: (String) -> Bool,
        fallbackProfile: String
    ) -> [String: DeviceConfiguration] {
        var configurations = input

        for (source, primary) in aliases {
            var configuration = configurations[source] ?? DeviceConfiguration()
            if let primaryConfiguration = configurations[primary] {
                // The alias period redirected every read and write to the
                // primary, so the primary's data is what this identity was
                // actually using; the source's own record is a frozen
                // pre-alias snapshot and must not win over it.
                if primaryConfiguration.hardwareMapping?.isEmpty == false {
                    configuration.hardwareMapping = primaryConfiguration.hardwareMapping
                }
                if primaryConfiguration.customNames != nil {
                    configuration.customNames = primaryConfiguration.customNames
                }
                if primaryConfiguration.customSectionTitles != nil {
                    configuration.customSectionTitles = primaryConfiguration.customSectionTitles
                }
                if primaryConfiguration.inputGroups != nil {
                    configuration.inputGroups = primaryConfiguration.inputGroups
                    configuration.nextCustomSourceOrdinal = primaryConfiguration.nextCustomSourceOrdinal
                }
                if primaryConfiguration.signalAliasGroups != nil {
                    configuration.signalAliasGroups = primaryConfiguration.signalAliasGroups
                }
                if primaryConfiguration.boundProfile != nil {
                    configuration.boundProfile = primaryConfiguration.boundProfile
                }
            }
            configurations[source] = configuration
        }

        for (key, configuration) in configurations {
            var updated = configuration
            let legacyEffective: String
            if let bound = configuration.boundProfile, profileExists(bound) {
                legacyEffective = bound
            } else if let legacyCurrentProfile, profileExists(legacyCurrentProfile) {
                legacyEffective = legacyCurrentProfile
            } else {
                legacyEffective = fallbackProfile
            }
            if updated.activeProfile == nil { updated.activeProfile = legacyEffective }
            var refs = updated.profileRefs ?? []
            if let active = updated.activeProfile, !refs.contains(active) { refs.append(active) }
            // The old globally-selected profile stays reachable where the
            // user will look for it — mounted on the device, not active.
            if let legacyCurrentProfile, profileExists(legacyCurrentProfile),
               !refs.contains(legacyCurrentProfile) {
                refs.append(legacyCurrentProfile)
            }
            updated.profileRefs = refs
            configurations[key] = updated
        }
        return configurations
    }

    /// Fold the legacy three-source rule into per-device active profiles.
    /// Idempotent; legacy keys are left in place so downgrading stays safe.
    private func migrateToDeviceFirstIfNeeded() {
        let defaults = UserDefaults.standard
        let existing = getDeviceConfigurations()
        // Self-heal: a downgrade round-trip re-encodes configurations with
        // the pre-device-first schema and silently drops the new fields.
        // When the flag is set but no configuration kept an active profile,
        // fold again instead of trusting the flag.
        if defaults.bool(forKey: Self.deviceFirstMigratedKey),
           existing.isEmpty || existing.values.contains(where: { $0.activeProfile != nil }) {
            return
        }
        let aliases = (defaults.dictionary(forKey: Self.deviceAliasesKey) as? [String: String]) ?? [:]
        // currentProfileName already resolved the full legacy priority chain
        // (UserDefaults > profiles.json settings > Default) in load().
        let configurations = Self.deviceFirstMigratedConfigurations(
            existing,
            aliases: aliases,
            legacyCurrentProfile: currentProfileName,
            profileExists: { profiles[$0] != nil },
            fallbackProfile: defaultProfileName()
        )
        setDeviceConfigurations(configurations)
        defaults.removeObject(forKey: Self.deviceAliasesKey)
        os_unfair_lock_lock(&deviceAliasesLock)
        deviceAliasesCache = [:]
        os_unfair_lock_unlock(&deviceAliasesLock)
        defaults.set(true, forKey: Self.deviceFirstMigratedKey)
        NSLog("[Config] Device-first migration complete: %d device configuration(s)", configurations.count)
    }

    /// Profiles no device references — migration leftovers surfaced in the
    /// sidebar's "unmounted" group so nothing silently disappears.
    func unmountedProfileNames() -> [String] {
        let configurations = getDeviceConfigurations()
        var referenced = Set<String>()
        for configuration in configurations.values {
            referenced.formUnion(configuration.profileRefs ?? [])
            if let active = configuration.activeProfile { referenced.insert(active) }
        }
        return profiles.keys.filter { !referenced.contains($0) }.sorted()
    }

    /// Select which device group the mapping UI edits. Pure UI state.
    func setEditingDevice(key: String?) {
        guard key != editingDeviceKey else { return }
        editingDeviceKey = key
        postPresentationChange()
    }

    /// Book-keeping when a device joins the consumed set: refresh its
    /// identity snapshot (original name, transport, VID/PID, serial, …),
    /// seed a profile only for new/legacy records, and migrate the legacy single global
    /// table one-shot to the first codec-backed (Naga) group — never to a
    /// generic mouse it was not learned on. The user's customDisplayName is
    /// deliberately never touched here.
    func noteDeviceSeen(summary: HIDDeviceCandidateSummary, codecBacked: Bool) {
        let groupKey = configKey(forDeviceKey: summary.deviceKey)
        let baseKey = summary.baseDeviceKey
        var changed = false
        var runtimeChanged = false
        updateDeviceConfigurations { configurations in
            // Enhanced instance keys inherit the legacy VID/PID record once.
            // Keep the base record as a migration template so a second serial-
            // identified instance starts with the same previous configuration
            // and can then diverge independently.
            let wasMissing = configurations[groupKey] == nil
            let inherited = groupKey != baseKey ? configurations[baseKey] : nil
            let seeded = Self.seedEnhancedIdentityConfiguration(
                &configurations,
                enhancedKey: groupKey,
                baseKey: baseKey
            )
            var configuration = configurations[groupKey] ?? DeviceConfiguration()
            changed = wasMissing
            if inherited != nil, seeded {
                runtimeChanged = true
                NSLog("[Config] Migrated base device group %@ to enhanced instance %@", baseKey, groupKey)
            }
            func update<T: Equatable>(_ keyPath: WritableKeyPath<DeviceConfiguration, T?>, to value: T?) {
                guard let value, configuration[keyPath: keyPath] != value else { return }
                configuration[keyPath: keyPath] = value
                changed = true
            }
            update(\.displayName, to: summary.product.isEmpty ? nil : summary.product)
            update(\.transport, to: summary.transport.isEmpty ? nil : summary.transport)
            update(\.vendorID, to: summary.vendorID)
            update(\.productID, to: summary.productID)
            update(\.serialNumber, to: summary.serialNumber.isEmpty ? nil : summary.serialNumber)
            update(\.lastLocationID, to: summary.locationID)
            update(\.descriptorFingerprint, to: summary.descriptorFingerprint.isEmpty ? nil : summary.descriptorFingerprint)
            update(\.codecBacked, to: codecBacked)
            if configuration.profileRefs == nil {
                let fallback = defaultProfileName()
                configuration.activeProfile = fallback
                configuration.profileRefs = [fallback]
                changed = true
                runtimeChanged = true
            } else {
                let refs = (configuration.profileRefs ?? []).filter { profiles[$0] != nil }
                if refs != configuration.profileRefs {
                    configuration.profileRefs = refs
                    changed = true
                }
                let resolvedActive = configuration.activeProfile.flatMap { refs.contains($0) ? $0 : nil }
                    ?? refs.first
                if configuration.activeProfile != resolvedActive {
                    configuration.activeProfile = resolvedActive
                    changed = true
                    runtimeChanged = true
                }
            }
            let migrationDone = UserDefaults.standard.bool(forKey: "legacyHardwareMappingMigrated")
            if codecBacked, !migrationDone, configuration.hardwareMapping?.isEmpty != false {
                let legacy = loadLegacyGlobalHardwareMapping()
                if !legacy.isEmpty {
                    configuration.hardwareMapping = legacy
                    UserDefaults.standard.set(true, forKey: "legacyHardwareMappingMigrated")
                    NSLog("[Config] Migrated legacy global hardware mapping to device group %@", groupKey)
                    changed = true
                    runtimeChanged = true
                }
            }
            if changed { configurations[groupKey] = configuration }
        }
        if changed { postPresentationChange() }
        if runtimeChanged { postRuntimeRoutingChange() }
    }

    /// Pure migration primitive used by startup/device discovery and tests.
    /// Returns true only when an enhanced instance was seeded from its VID/PID
    /// base record. The base is intentionally retained for further instances.
    @discardableResult
    static func seedEnhancedIdentityConfiguration(
        _ configurations: inout [String: DeviceConfiguration],
        enhancedKey: String,
        baseKey: String
    ) -> Bool {
        guard enhancedKey != baseKey,
              configurations[enhancedKey] == nil,
              let baseConfiguration = configurations[baseKey] else { return false }
        configurations[enhancedKey] = baseConfiguration
        return true
    }

    // MARK: - Known devices (shared by both editor windows)

    /// Every device group the user could edit: previously configured groups,
    /// aliased keys and everything currently connected/consumed.
    func knownDeviceKeys() -> [String] {
        var keys = Set(getDeviceConfigurations().keys)
        keys.formUnion(getDeviceAliases().keys)
        var liveKeys = HIDListener.shared.consumedDeviceKeys
        keys.formUnion(liveKeys)
        for group in HIDListener.shared.deviceCandidateGroups where group.isSupported {
            keys.insert(group.deviceKey)
            liveKeys.insert(group.deviceKey)
        }
        // Once an enhanced instance exists, the base VID/PID record is a hidden
        // migration template rather than a second editable physical device.
        let enhancedBases = Set(keys.filter(DeviceIdentityPolicy.isEnhanced).map(DeviceIdentityPolicy.baseKey(from:)))
        keys.subtract(enhancedBases.subtracting(liveKeys))
        return keys.sorted()
    }

    /// Short, user-facing transport label ("USB" / 蓝牙 / raw). One source of
    /// truth for both the mapping window and the status-bar popover, so the
    /// same connection identity is named identically everywhere.
    static func transportLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.contains("bluetooth") || lower.contains("btle") { return L10n.text("蓝牙") }
        if lower.contains("usb") { return "USB" }
        return raw
    }

    /// The device's original HID product name (never the user's rename).
    func deviceOriginalName(forKey deviceKey: String) -> String {
        let configurations = getDeviceConfigurations()
        if let name = configurations[deviceKey]?.displayName, !name.isEmpty {
            return name
        }
        if let group = HIDListener.shared.deviceCandidateGroups.first(where: { $0.deviceKey == deviceKey }),
           !group.product.isEmpty {
            return group.product
        }
        return deviceKey
    }

    /// Base display name without the transport suffix: the user's custom
    /// name when set, else the original product name.
    func deviceBaseName(forKey deviceKey: String) -> String {
        if let custom = getDeviceConfigurations()[deviceKey]?.customDisplayName, !custom.isEmpty {
            return custom
        }
        return deviceOriginalName(forKey: deviceKey)
    }

    /// Empty or whitespace-only names clear the customization and fall back
    /// to the original product name.
    func setCustomDeviceName(_ name: String?, forDeviceKey deviceKey: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) {
            $0.customDisplayName = trimmed.isEmpty ? nil : trimmed
        }
        postPresentationChange()
    }

    /// Every fact that can identify this device, for the details panel.
    /// Persisted snapshot first, falling back to the live candidate group so
    /// the panel is as complete as possible in both online and offline states.
    func deviceIdentityFacts(forKey deviceKey: String) -> [(label: String, value: String)] {
        let configuration = getDeviceConfigurations()[deviceKey]
        let live = HIDListener.shared.deviceCandidateGroups
            .first(where: { $0.deviceKey == deviceKey })?.candidates.first
        var facts: [(String, String)] = []
        if let custom = configuration?.customDisplayName, !custom.isEmpty {
            facts.append((L10n.text("自定义名称"), custom))
        }
        facts.append((L10n.text("原始设备名"), deviceOriginalName(forKey: deviceKey)))
        facts.append((L10n.text("设备标识符"), deviceKey))
        if DeviceIdentityPolicy.isEnhanced(deviceKey) {
            facts.append((L10n.text("基础设备族 (VID:PID)"), DeviceIdentityPolicy.baseKey(from: deviceKey)))
        }
        let baseKey = DeviceIdentityPolicy.baseKey(from: deviceKey)
        let liveFamily = HIDListener.shared.deviceCandidates.first { $0.baseDeviceKey == baseKey }
        let effectiveRule = liveFamily.flatMap { DeviceIdentityRuleStore.shared.effectiveRule(for: $0.observedIdentityFacts) }
            ?? DeviceIdentityRuleStore.shared.overrideRule(for: baseKey)
        if let effectiveRule {
            let origin = DeviceIdentityRuleStore.shared.overrideRule(for: baseKey) == nil
                ? L10n.text("软件默认")
                : L10n.text("用户自定义")
            let state = effectiveRule.enhancedRecognitionEnabled ? L10n.text("已启用") : L10n.text("已关闭")
            facts.append((
                L10n.text("身份识别规则"),
                L10n.format("%@ · %@ · %d 项条件", origin, state, effectiveRule.totalConditionCount)
            ))
        } else {
            facts.append((L10n.text("身份识别规则"), L10n.text("仅 VID/PID（2 项基础条件）")))
        }
        let vendorID = configuration?.vendorID ?? live?.vendorID
        let productID = configuration?.productID ?? live?.productID
        if let vendorID, vendorID > 0 {
            facts.append(("Vendor ID", String(format: "0x%04X (%d)", vendorID, vendorID)))
        }
        if let productID, productID > 0 {
            facts.append(("Product ID", String(format: "0x%04X (%d)", productID, productID)))
        }
        let rawTransport = configuration?.transport ?? live?.transport
        if let rawTransport, !rawTransport.isEmpty {
            let label = Self.transportLabel(rawTransport)
            facts.append((
                L10n.text("连接方式"),
                label == nil || label == rawTransport ? rawTransport : "\(label!)(\(rawTransport))"
            ))
        }
        let serial = configuration?.serialNumber ?? (live?.serialNumber.isEmpty == false ? live?.serialNumber : nil)
        facts.append((L10n.text("序列号"), serial?.isEmpty == false ? serial! : L10n.text("设备未报告")))
        if let location = configuration?.lastLocationID ?? live?.locationID, location != 0 {
            facts.append(("Location ID", String(format: "0x%X", location)))
        }
        if let fingerprint = configuration?.descriptorFingerprint ?? live?.descriptorFingerprint,
           !fingerprint.isEmpty {
            facts.append((L10n.text("描述符指纹"), fingerprint))
        }
        if let codecBacked = configuration?.codecBacked ?? live.map({ $0.codecIdentifier != nil }) {
            facts.append((
                L10n.text("协议"),
                codecBacked ? L10n.text("专用编解码器") : L10n.text("标准 HID")
            ))
        }
        return facts
    }

    /// User-facing connection label for a device's title suffix.
    func deviceTransportDisplayLabel(forKey deviceKey: String) -> String? {
        let stored = getDeviceConfigurations()[deviceKey]?.transport
        let live = HIDListener.shared.deviceCandidateGroups
            .first(where: { $0.deviceKey == deviceKey })?.transport
        return Self.transportLabel(stored ?? live)
    }

    /// Device-first naming: every connection identity is its own device, so
    /// the display name carries the connection kind ("Naga V2 HS · USB").
    func deviceDisplayName(forKey deviceKey: String) -> String {
        let base = deviceBaseName(forKey: deviceKey)
        if let label = deviceTransportDisplayLabel(forKey: deviceKey),
           !base.localizedCaseInsensitiveContains(label) {
            return "\(base) · \(label)"
        }
        return base
    }

    // MARK: - Device archiving

    func isDeviceArchived(_ deviceKey: String) -> Bool {
        getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?.archived == true
    }

    /// Archived device keys, sorted — the sidebar's collapsed archived group.
    func archivedDeviceKeys() -> [String] {
        getDeviceConfigurations()
            .filter { $0.value.archived == true }
            .keys
            .sorted()
    }

    func setDeviceArchived(_ archived: Bool, forDeviceKey deviceKey: String) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) {
            $0.archived = archived ? true : nil
        }
        // Archiving pulls the device out of the runtime; release anything it is
        // currently holding so no synthetic key stays stuck.
        if archived {
            ButtonMapper.shared.releaseSyntheticInputs(forDeviceKey: deviceKey, reason: "device archived")
        }
        // Runtime tables and the popover list both drop archived devices.
        postPresentationChange()
        postRuntimeRoutingChange()
    }

    // MARK: - Custom input sources (adapt to other button counts)

    private static let firstCustomSourceIndex = 17

    private static func builtInGroup(for index: Int) -> String {
        switch index {
        case 1...12: return DeviceInputGroup.sideID
        case 13...14: return DeviceInputGroup.dpiID
        default: return DeviceInputGroup.scrollID
        }
    }

    static func normalizedInputGroups(for configuration: DeviceConfiguration) -> [DeviceInputGroup] {
        let removed = Set(configuration.removedStandardIndices ?? [])
        let presentStandard = InputSourceCatalog.supportedIndices.filter { !removed.contains($0) }
        let presentCustom = Array(Set((configuration.customSourceIndices ?? []).filter { $0 >= firstCustomSourceIndex })).sorted()
        let present = Set(presentStandard + presentCustom)

        let isLegacyConfiguration = configuration.inputGroups == nil
        var groups = configuration.inputGroups ?? [
            DeviceInputGroup(id: DeviceInputGroup.sideID, title: configuration.customSectionTitles?["side"], sourceIndices: []),
            DeviceInputGroup(id: DeviceInputGroup.dpiID, title: configuration.customSectionTitles?["dpi"], sourceIndices: []),
            DeviceInputGroup(id: DeviceInputGroup.scrollID, title: configuration.customSectionTitles?["scroll"], sourceIndices: [])
        ]
        var seenGroupIDs = Set<String>()
        var seenSources = Set<Int>()
        groups = groups.compactMap { original in
            guard !original.id.isEmpty, seenGroupIDs.insert(original.id).inserted else { return nil }
            var group = original
            group.sourceIndices = original.sourceIndices.filter {
                present.contains($0) && seenSources.insert($0).inserted
            }
            return group
        }
        if isLegacyConfiguration {
            for id in [DeviceInputGroup.sideID, DeviceInputGroup.dpiID, DeviceInputGroup.scrollID]
                where !seenGroupIDs.contains(id) {
                groups.insert(DeviceInputGroup(id: id, title: configuration.customSectionTitles?[id], sourceIndices: []),
                              at: min(groups.count, id == DeviceInputGroup.sideID ? 0 : id == DeviceInputGroup.dpiID ? 1 : 2))
                seenGroupIDs.insert(id)
            }
        }
        for index in presentStandard where !seenSources.contains(index) {
            let id = builtInGroup(for: index)
            if let position = groups.firstIndex(where: { $0.id == id }) {
                groups[position].sourceIndices.append(index)
                seenSources.insert(index)
            }
        }
        let orphanedStandard = presentStandard.filter { !seenSources.contains($0) }
        if !orphanedStandard.isEmpty {
            let ungroupedID = "ungrouped"
            if let position = groups.firstIndex(where: { $0.id == ungroupedID }) {
                groups[position].sourceIndices.append(contentsOf: orphanedStandard)
            } else {
                groups.append(DeviceInputGroup(id: ungroupedID, title: L10n.text("未分组"), sourceIndices: orphanedStandard))
            }
            seenSources.formUnion(orphanedStandard)
        }
        let orphanedCustom = presentCustom.filter { !seenSources.contains($0) }
        if !orphanedCustom.isEmpty {
            let migrationID = "custom-migrated"
            if let position = groups.firstIndex(where: { $0.id == migrationID }) {
                groups[position].sourceIndices.append(contentsOf: orphanedCustom)
            } else {
                groups.append(DeviceInputGroup(id: migrationID, title: L10n.text("自定义按键"), sourceIndices: orphanedCustom))
            }
        }
        return groups.map {
            var group = $0
            group.sourceIndices.sort()
            return group
        }
    }

    static func configurationByMigratingInputGroups(_ original: DeviceConfiguration) -> DeviceConfiguration {
        var migrated = original
        migrated.inputGroups = normalizedInputGroups(for: original)
        let nextByIndex = max(1, (original.customSourceIndices?.max() ?? 16) - 15)
        migrated.nextCustomSourceOrdinal = max(original.nextCustomSourceOrdinal ?? 1, nextByIndex)
        normalizeSignalAliases(in: &migrated)
        return migrated
    }

    private func migrateInputGroupsIfNeeded() {
        updateDeviceConfigurations { configurations in
            for (key, original) in configurations {
                guard original.inputGroups == nil || original.nextCustomSourceOrdinal == nil || original.signalAliasGroups == nil else { continue }
                configurations[key] = Self.configurationByMigratingInputGroups(original)
            }
        }
    }

    func inputGroups(forDeviceKey deviceKey: String?) -> [DeviceInputGroup] {
        let configuration = deviceKey
            .flatMap { getDeviceConfigurations()[configKey(forDeviceKey: $0)] }
            ?? DeviceConfiguration()
        return Self.normalizedInputGroups(for: configuration)
    }

    func inputGroupTitle(_ group: DeviceInputGroup) -> String {
        if let title = group.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        switch group.id {
        case DeviceInputGroup.sideID: return L10n.text("侧键 1–12")
        case DeviceInputGroup.dpiID: return L10n.text("DPI ±")
        case DeviceInputGroup.scrollID: return L10n.text("滚轮左右键")
        default: return L10n.text("自定义分组")
        }
    }

    @discardableResult
    func addInputGroup(forDeviceKey deviceKey: String, title: String? = nil) -> String {
        let groupKey = configKey(forDeviceKey: deviceKey)
        let id = UUID().uuidString.lowercased()
        updateDeviceConfiguration(forKey: groupKey) { configuration in
            var groups = Self.normalizedInputGroups(for: configuration)
            let sequence = groups.filter { !$0.isBuiltIn }.count + 1
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            groups.append(DeviceInputGroup(
                id: id,
                title: trimmed.isEmpty ? L10n.format("自定义分组 %d", sequence) : trimmed,
                sourceIndices: []
            ))
            configuration.inputGroups = groups
            configuration.nextCustomSourceOrdinal = configuration.nextCustomSourceOrdinal ?? 1
        }
        postPresentationChange()
        return id
    }

    func renameInputGroup(_ groupID: String, title: String, forDeviceKey deviceKey: String) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var groups = Self.normalizedInputGroups(for: configuration)
            guard let position = groups.firstIndex(where: { $0.id == groupID }) else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            groups[position].title = trimmed.isEmpty ? nil : trimmed
            configuration.inputGroups = groups
            if DeviceInputGroup.builtInIDs.contains(groupID) {
                var legacy = configuration.customSectionTitles ?? [:]
                if trimmed.isEmpty { legacy.removeValue(forKey: groupID) } else { legacy[groupID] = trimmed }
                configuration.customSectionTitles = legacy.isEmpty ? nil : legacy
            }
        }
        postPresentationChange()
    }

    func moveInputGroup(_ groupID: String, offset: Int, forDeviceKey deviceKey: String) {
        guard offset != 0 else { return }
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var groups = Self.normalizedInputGroups(for: configuration)
            guard let position = groups.firstIndex(where: { $0.id == groupID }) else { return }
            let destination = position + offset
            guard groups.indices.contains(destination) else { return }
            groups.swapAt(position, destination)
            configuration.inputGroups = groups
        }
        postPresentationChange()
    }

    @discardableResult
    func removeInputGroup(_ groupID: String, forDeviceKey deviceKey: String) -> Bool {
        var removed = false
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var groups = Self.normalizedInputGroups(for: configuration)
            guard let position = groups.firstIndex(where: { $0.id == groupID }),
                  groups[position].sourceIndices.isEmpty else { return }
            groups.remove(at: position)
            configuration.inputGroups = groups
            if DeviceInputGroup.builtInIDs.contains(groupID) {
                configuration.customSectionTitles?.removeValue(forKey: groupID)
                if configuration.customSectionTitles?.isEmpty == true {
                    configuration.customSectionTitles = nil
                }
            }
            removed = true
        }
        if removed { postPresentationChange() }
        return removed
    }

    func moveSource(_ index: Int, toGroupID groupID: String, forDeviceKey deviceKey: String) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var groups = Self.normalizedInputGroups(for: configuration)
            guard groups.contains(where: { $0.id == groupID }) else { return }
            for position in groups.indices { groups[position].sourceIndices.removeAll { $0 == index } }
            if let destination = groups.firstIndex(where: { $0.id == groupID }) {
                groups[destination].sourceIndices.append(index)
                groups[destination].sourceIndices.sort()
            }
            configuration.inputGroups = groups
        }
        postPresentationChange()
    }

    func pendingCustomInput(forDeviceKey deviceKey: String, groupID: String) -> PendingCustomInput? {
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)] ?? DeviceConfiguration()
        let groups = Self.normalizedInputGroups(for: configuration)
        guard groups.contains(where: { $0.id == groupID }) else { return nil }
        let existing = Set(configuration.customSourceIndices ?? [])
        var index = Self.firstCustomSourceIndex
        while existing.contains(index) { index += 1 }
        let ordinal = max(1, configuration.nextCustomSourceOrdinal ?? max(1, (existing.max() ?? 16) - 15))
        return PendingCustomInput(sourceIndex: index, ordinal: ordinal, groupID: groupID)
    }

    @discardableResult
    func commitCustomInput(
        _ pending: PendingCustomInput,
        learnedKey: HardwareKey,
        forDeviceKey deviceKey: String
    ) -> Bool {
        var committed = false
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var custom = configuration.customSourceIndices ?? []
            guard !custom.contains(pending.sourceIndex) else { return }
            var groups = Self.normalizedInputGroups(for: configuration)
            guard let groupPosition = groups.firstIndex(where: { $0.id == pending.groupID }) else { return }
            custom.append(pending.sourceIndex)
            custom.sort()
            configuration.customSourceIndices = custom
            configuration.hardwareMapping?[String(pending.sourceIndex)] = learnedKey
            if configuration.hardwareMapping == nil {
                configuration.hardwareMapping = [String(pending.sourceIndex): learnedKey]
            }
            var names = configuration.customNames ?? [:]
            names[String(pending.sourceIndex)] = L10n.format("自定义键%d", pending.ordinal)
            configuration.customNames = names
            groups[groupPosition].sourceIndices.append(pending.sourceIndex)
            groups[groupPosition].sourceIndices.sort()
            configuration.inputGroups = groups
            configuration.nextCustomSourceOrdinal = pending.ordinal + 1
            Self.normalizeSignalAliases(in: &configuration)
            committed = true
        }
        if committed {
            postPresentationChange()
            postRuntimeRoutingChange()
        }
        return committed
    }

    /// All learnable source indices for a device: the fixed 1–16 layout minus
    /// any the user removed, plus any user-added custom sources, sorted. This
    /// lets a device show exactly the buttons it physically has (e.g. 8 side
    /// keys, or a 26-key keyboard).
    func sourceIndices(forDeviceKey deviceKey: String?) -> [Int] {
        let configuration = deviceKey.flatMap { getDeviceConfigurations()[configKey(forDeviceKey: $0)] }
        let removed = Set(configuration?.removedStandardIndices ?? [])
        var indices = InputSourceCatalog.supportedIndices.filter { !removed.contains($0) }
        indices.append(contentsOf: configuration?.customSourceIndices ?? [])
        return indices.sorted()
    }

    func customSourceIndices(forDeviceKey deviceKey: String) -> [Int] {
        (getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?.customSourceIndices ?? []).sorted()
    }

    /// True if any standard 1–16 source is hidden for this device.
    func hasRemovedStandardSources(forDeviceKey deviceKey: String) -> Bool {
        getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?.removedStandardIndices?.isEmpty == false
    }

    /// Append a new custom source (next free index ≥ 17), optionally named.
    @discardableResult
    func addCustomSource(forDeviceKey deviceKey: String, name: String?) -> Int {
        let groupKey = configKey(forDeviceKey: deviceKey)
        let existing = getDeviceConfigurations()[groupKey]?.customSourceIndices ?? []
        let nextIndex = max(Self.firstCustomSourceIndex - 1, existing.max() ?? 0) + 1
        updateDeviceConfiguration(forKey: groupKey) {
            var custom = $0.customSourceIndices ?? []
            custom.append(nextIndex)
            $0.customSourceIndices = custom
            var groups = Self.normalizedInputGroups(for: $0)
            var target = groups.firstIndex(where: { !$0.isBuiltIn })
            if target == nil {
                groups.append(DeviceInputGroup(id: "custom-migrated", title: L10n.text("自定义按键"), sourceIndices: []))
                target = groups.indices.last
            }
            if let target { groups[target].sourceIndices.append(nextIndex) }
            if let target {
                groups[target].sourceIndices = Array(Set(groups[target].sourceIndices)).sorted()
            }
            $0.inputGroups = groups
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { setCustomName(trimmed, forDeviceKey: deviceKey, index: nextIndex) }
        postPresentationChange()
        return nextIndex
    }

    /// Remove any source from a device — a custom source disappears entirely;
    /// a standard 1–16 source is hidden for this device (recoverable via
    /// restoreDefaultSources). Either way its learned table entry and name are
    /// cleared.
    func removeSource(forDeviceKey deviceKey: String, index: Int) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            if index >= Self.firstCustomSourceIndex {
                configuration.customSourceIndices?.removeAll { $0 == index }
                if configuration.customSourceIndices?.isEmpty == true { configuration.customSourceIndices = nil }
            } else {
                var removed = configuration.removedStandardIndices ?? []
                if !removed.contains(index) { removed.append(index) }
                configuration.removedStandardIndices = removed
            }
            var groups = Self.normalizedInputGroups(for: configuration)
            for position in groups.indices { groups[position].sourceIndices.removeAll { $0 == index } }
            configuration.inputGroups = groups
            configuration.hardwareMapping?.removeValue(forKey: String(index))
            configuration.customNames?.removeValue(forKey: String(index))
            Self.normalizeSignalAliases(in: &configuration)
        }
        postPresentationChange()
        postRuntimeRoutingChange()
    }

    /// Un-hide every standard 1–16 source that was removed from this device.
    func restoreDefaultSources(forDeviceKey deviceKey: String) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            let removed = Set(configuration.removedStandardIndices ?? [])
            var groups = Self.normalizedInputGroups(for: configuration)
            let requiredGroupIDs = Set(removed.map(Self.builtInGroup(for:)))
            for id in [DeviceInputGroup.sideID, DeviceInputGroup.dpiID, DeviceInputGroup.scrollID]
                where requiredGroupIDs.contains(id) && !groups.contains(where: { $0.id == id }) {
                groups.append(DeviceInputGroup(id: id, title: configuration.customSectionTitles?[id], sourceIndices: []))
            }
            configuration.inputGroups = groups
            configuration.removedStandardIndices = nil
            configuration.inputGroups = Self.normalizedInputGroups(for: configuration)
        }
        postPresentationChange()
    }

    static func isCustomSourceIndex(_ index: Int) -> Bool { index >= firstCustomSourceIndex }

    // MARK: - Custom button names

    func customName(forDeviceKey deviceKey: String, index: Int) -> String? {
        let name = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?
            .customNames?[String(index)]
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// Empty or whitespace-only names clear the customization.
    func setCustomName(_ name: String?, forDeviceKey deviceKey: String, index: Int) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var names = configuration.customNames ?? [:]
            if trimmed.isEmpty {
                names.removeValue(forKey: String(index))
            } else {
                names[String(index)] = trimmed
            }
            configuration.customNames = names.isEmpty ? nil : names
        }
        postPresentationChange()
    }

    /// Display name for a button row: the user's custom name, falling back to
    /// the catalog default. Both editor windows resolve through this.
    func buttonDisplayName(forDeviceKey deviceKey: String?, index: Int) -> String {
        if let deviceKey, let custom = customName(forDeviceKey: deviceKey, index: index) {
            return custom
        }
        return InputSourceCatalog.mappingName(for: index)
    }

    // MARK: - Custom section titles (mapping window group headers)

    func customSectionTitle(forDeviceKey deviceKey: String, section: String) -> String? {
        let title = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)]?
            .customSectionTitles?[section]
        return (title?.isEmpty ?? true) ? nil : title
    }

    /// Empty or whitespace-only titles clear the customization.
    func setCustomSectionTitle(_ title: String?, forDeviceKey deviceKey: String, section: String) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            var titles = configuration.customSectionTitles ?? [:]
            if trimmed.isEmpty {
                titles.removeValue(forKey: section)
            } else {
                titles[section] = trimmed
            }
            configuration.customSectionTitles = titles.isEmpty ? nil : titles
        }
        postPresentationChange()
    }

    // MARK: - Transactional editing (hardware-definition sheet cancel)

    func deviceConfigurationsSnapshot() -> [String: DeviceConfiguration] {
        getDeviceConfigurations()
    }

    func restoreDeviceConfigurations(_ snapshot: [String: DeviceConfiguration]) {
        setDeviceConfigurations(snapshot)
        postPresentationChange()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    /// Restore only one device edited by a modal hardware-definition session.
    /// Other devices may have connected or changed while the sheet was open and
    /// must not be overwritten by Cancel.
    func restoreDeviceConfiguration(_ snapshot: DeviceConfiguration?, forKey deviceKey: String) {
        updateDeviceConfigurations { configurations in
            if let snapshot { configurations[deviceKey] = snapshot }
            else { configurations.removeValue(forKey: deviceKey) }
        }
        postPresentationChange()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    func restoreDeviceConfigurations(
        existing snapshots: [String: DeviceConfiguration],
        removing missingKeys: Set<String>
    ) {
        updateDeviceConfigurations { configurations in
            for key in missingKeys { configurations.removeValue(forKey: key) }
            for (key, snapshot) in snapshots { configurations[key] = snapshot }
        }
        postPresentationChange()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    /// Copy another group's learned table into a device's group — recovery
    /// path when the one-shot migration landed on the other transport of the
    /// same physical mouse.
    func copyHardwareMapping(fromConfigKey source: String, toDeviceKey deviceKey: String) {
        let mapping = getDeviceConfigurations()[source]?.hardwareMapping ?? [:]
        guard !mapping.isEmpty else { return }
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            configuration.hardwareMapping = mapping
            Self.normalizeSignalAliases(in: &configuration)
        }
        postRuntimeRoutingChange()
    }

    private func loadLegacyGlobalHardwareMapping() -> [String: HardwareKey] {
        guard let data = UserDefaults.standard.data(forKey: "hardwareMapping"),
              let decoded = try? JSONDecoder().decode([String: HardwareKey].self, from: data) else {
            return [:]
        }
        return Self.normalizedHardwareDisplays(decoded)
    }

    /// Learned table of one configuration group (alias-resolved device key).
    func hardwareMapping(forConfigKey groupKey: String) -> [String: HardwareKey] {
        getDeviceConfigurations()[groupKey]?.hardwareMapping ?? [:]
    }

    private static func signalAliasID(page: UInt32, usage: UInt32, direction: Int) -> String {
        String(format: "signal-%08x-%08x-%d", page, usage, direction)
    }

    /// Rebuild duplicate-signal aliases from the authoritative learned table.
    /// The smallest logical index is canonical, so JSON/dictionary order can
    /// never change which action runs. Interception is shared by mirroring the
    /// canonical value to every member.
    static func normalizeSignalAliases(in configuration: inout DeviceConfiguration) {
        var mapping = configuration.hardwareMapping ?? [:]
        let previousGroups = configuration.signalAliasGroups ?? []
        let entries = mapping.compactMap { key, value -> (Int, HardwareKey)? in
            guard let index = Int(key), index >= 1 else { return nil }
            return (index, value)
        }
        let buckets = Dictionary(grouping: entries) { entry in
            HIDUsageSignature(
                page: entry.1.usagePage,
                usage: entry.1.usage,
                direction: entry.1.valueDirection ?? 0
            )
        }
        var groups: [HardwareSignalAliasGroup] = []
        for (signature, members) in buckets {
            let sorted = members.sorted { $0.0 < $1.0 }
            let previous = previousGroups.first {
                $0.usagePage == signature.page &&
                    $0.usage == signature.usage &&
                    $0.valueDirection == signature.direction
            }
            // If the former canonical source was deleted, keep its profile
            // slot as a stable action anchor for the remaining physical key.
            // Reusing that source for another learned signal intentionally
            // releases the old anchor to avoid routing two signals to one slot.
            let preservedCanonical = previous.flatMap { group in
                mapping[String(group.canonicalSourceIndex)] == nil ? group.canonicalSourceIndex : nil
            }
            guard sorted.count > 1 || preservedCanonical != nil else { continue }
            let canonicalIndex = preservedCanonical ?? sorted[0].0
            let canonicalIntercept = sorted.first(where: { $0.0 == canonicalIndex })?.1.interceptEnabled
                ?? sorted[0].1.interceptEnabled
            let id = signalAliasID(page: signature.page, usage: signature.usage, direction: signature.direction)
            for (index, var key) in sorted {
                key.interceptEnabled = canonicalIntercept
                key.groupId = id // backward-readable hint; UI grouping is stored elsewhere.
                mapping[String(index)] = key
            }
            groups.append(HardwareSignalAliasGroup(
                id: id,
                usagePage: signature.page,
                usage: signature.usage,
                valueDirection: signature.direction,
                canonicalSourceIndex: canonicalIndex,
                memberSourceIndices: sorted.map(\.0)
            ))
        }
        let activeIDs = Set(groups.map(\.id))
        for (index, var key) in mapping {
            guard let groupID = key.groupId,
                  groupID.hasPrefix("signal-"),
                  !activeIDs.contains(groupID) else { continue }
            key.groupId = nil
            mapping[index] = key
        }
        configuration.hardwareMapping = mapping
        configuration.signalAliasGroups = groups.sorted { $0.canonicalSourceIndex < $1.canonicalSourceIndex }
    }

    func signalCanonicalSourceIndex(forDeviceKey deviceKey: String?, index: Int) -> Int {
        guard let deviceKey else { return index }
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)] ?? DeviceConfiguration()
        return configuration.signalAliasGroups?
            .first(where: { $0.memberSourceIndices.contains(index) })?
            .canonicalSourceIndex ?? index
    }

    func signalAliasMembers(forDeviceKey deviceKey: String?, index: Int) -> [Int] {
        guard let deviceKey else { return [index] }
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)] ?? DeviceConfiguration()
        return configuration.signalAliasGroups?
            .first(where: { $0.memberSourceIndices.contains(index) })?
            .memberSourceIndices ?? [index]
    }

    static func runtimeAliasResolvedMapping(
        _ mapping: [String: HardwareKey],
        groups: [HardwareSignalAliasGroup]
    ) -> [String: HardwareKey] {
        var resolved = mapping
        for group in groups where resolved[String(group.canonicalSourceIndex)] == nil {
            guard let member = group.memberSourceIndices.first,
                  let key = resolved[String(member)] else { continue }
            resolved[String(group.canonicalSourceIndex)] = key
        }
        return resolved
    }

    func setSignalInterceptEnabled(_ enabled: Bool, forDeviceKey deviceKey: String, index: Int) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            let members = configuration.signalAliasGroups?
                .first(where: { $0.memberSourceIndices.contains(index) })?
                .memberSourceIndices ?? [index]
            for member in members {
                guard var key = configuration.hardwareMapping?[String(member)] else { continue }
                key.interceptEnabled = enabled
                configuration.hardwareMapping?[String(member)] = key
            }
            Self.normalizeSignalAliases(in: &configuration)
        }
        postRuntimeRoutingChange()
    }

    func setSignalCommandControlSwapEnabled(_ enabled: Bool, forDeviceKey deviceKey: String, index: Int) {
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            let members = configuration.signalAliasGroups?
                .first(where: { $0.memberSourceIndices.contains(index) })?
                .memberSourceIndices ?? [index]
            for member in members {
                guard var key = configuration.hardwareMapping?[String(member)],
                      key.hasCommandOrControlModifier else { continue }
                key.swapCommandControl = enabled ? true : nil
                configuration.hardwareMapping?[String(member)] = key
            }
            Self.normalizeSignalAliases(in: &configuration)
        }
        postRuntimeRoutingChange()
    }

    func setHardwareMapping(_ mapping: [String: HardwareKey], forDeviceKey deviceKey: String) {
        let normalized = Self.normalizedHardwareDisplays(mapping)
        updateDeviceConfiguration(forKey: configKey(forDeviceKey: deviceKey)) { configuration in
            configuration.hardwareMapping = normalized
            Self.normalizeSignalAliases(in: &configuration)
        }
        postRuntimeRoutingChange()
    }

    /// Editing-scope accessors used by the mapping UI: they follow the device
    /// group explicitly chosen in the mapping window. With no editing device
    /// they fall back to the legacy global table (pre-0.3.5 installs).
    func getHardwareMapping() -> [String: HardwareKey] {
        if let editingDeviceKey {
            return hardwareMapping(forConfigKey: configKey(forDeviceKey: editingDeviceKey))
        }
        return legacyGlobalHardwareMapping()
    }

    func setHardwareMapping(_ mapping: [String: HardwareKey]) {
        if let editingDeviceKey {
            setHardwareMapping(mapping, forDeviceKey: editingDeviceKey)
            return
        }
        let mapping = Self.normalizedHardwareDisplays(mapping)
        os_unfair_lock_lock(&hardwareMappingLock)
        hardwareMappingCache = mapping
        hardwareMappingLoaded = true
        os_unfair_lock_unlock(&hardwareMappingLock)

        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: "hardwareMapping")
        }
        postRuntimeRoutingChange()
    }

    private func legacyGlobalHardwareMapping() -> [String: HardwareKey] {
        os_unfair_lock_lock(&hardwareMappingLock)
        defer { os_unfair_lock_unlock(&hardwareMappingLock) }
        if !hardwareMappingLoaded {
            if let data = UserDefaults.standard.data(forKey: "hardwareMapping"),
               let decoded = try? JSONDecoder().decode([String: HardwareKey].self, from: data) {
                hardwareMappingCache = Self.normalizedHardwareDisplays(decoded)
                if hardwareMappingCache != decoded,
                   let migrated = try? JSONEncoder().encode(hardwareMappingCache) {
                    UserDefaults.standard.set(migrated, forKey: "hardwareMapping")
                }
            }
            hardwareMappingLoaded = true
        }
        return hardwareMappingCache
    }

    static func isLegacyFixedDPIDefinition(index: String, key: HardwareKey) -> Bool {
        guard index == "13" || index == "14" else { return false }
        return key.usagePage == 0x01 &&
            key.usage == UInt32.max &&
            ((index == "13" && key.keyCode == 2000) ||
             (index == "14" && key.keyCode == 2001))
    }

    private static func normalizedHardwareDisplays(_ mapping: [String: HardwareKey]) -> [String: HardwareKey] {
        var result = mapping
        for (index, key) in mapping {
            // Builds 19–21 briefly persisted synthetic DPI placeholders. They
            // are not mouse reports and must not survive into the unified
            // three-sample learning path. Match the exact old tuple so a real
            // user definition or its assigned action is never removed.
            if isLegacyFixedDPIDefinition(index: index, key: key) {
                result.removeValue(forKey: index)
                continue
            }
            var updated = key
            if key.usagePage == 0x07 {
                updated.displayString = HardwareKeyDisplay.keyboard(
                    keyCode: key.keyCode & 0xffff,
                    modifierFlags: key.modifierFlags ?? 0
                )
            } else if key.usagePage == 0x0c, key.usage == 0x0238,
                      let direction = key.valueDirection, direction != 0 {
                updated.displayString = direction > 0
                    ? L10n.text("横向滚轮（硬件方向 +）")
                    : L10n.text("横向滚轮（硬件方向 −）")
            } else if key.usagePage == 0x0c || key.usagePage == 0x01 {
                updated.displayString = HardwareKeyDisplay.system(
                    usagePage: key.usagePage,
                    usage: key.usage
                )
            } else if key.usagePage == 0x09, key.usage >= 3 {
                updated.displayString = key.usage == 3
                    ? L10n.text("中键（滚轮按下）")
                    : L10n.format("鼠标按键 %d（额外鼠标键）", Int(key.usage))
            }
            result[index] = updated
        }
        return result
    }

    /// Manual definitions for side buttons, remapped DPI buttons and wheel
    /// tilt. Physical left and right buttons remain excluded. Middle-button
    /// signals cannot be distinguished from the physical middle button.
    /// Editing-scope variant used by the mapping UI. The "has a Mac custom
    /// value" filter follows the editing device's EFFECTIVE profile (its bound
    /// profile when set): judging by the globally selected profile made
    /// interception impossible to enable for devices bound to another profile.
    func runtimeHardwareMapping() -> [String: HardwareKey] {
        if let editingDeviceKey,
           effectiveProfileName(forDeviceKey: editingDeviceKey) == nil {
            return Self.zeroProfileRuntimeMapping(getHardwareMapping())
        }
        return filteredRuntimeMapping(
            getHardwareMapping(),
            assigned: Set(editingEffectiveMapping().keys)
        )
    }

    /// Action table of the editing device's effective profile.
    func editingEffectiveMapping() -> [Int: ActionType] {
        if let editingDeviceKey {
            return effectiveProfileName(forDeviceKey: editingDeviceKey)
                .map { mappingForProfile(named: $0) } ?? [:]
        }
        return mappingForCurrentProfile()
    }

    /// Runtime variant: one device's learned table filtered by that device's
    /// effective profile, so interception never consumes an onboard value the
    /// device has no Mac custom value for.
    func runtimeHardwareMapping(forDeviceKey deviceKey: String) -> [String: HardwareKey] {
        let configuration = getDeviceConfigurations()[configKey(forDeviceKey: deviceKey)] ?? DeviceConfiguration()
        let mapping = Self.runtimeAliasResolvedMapping(
            configuration.hardwareMapping ?? [:],
            groups: configuration.signalAliasGroups ?? []
        )
        guard let profileName = effectiveProfileName(forDeviceKey: deviceKey) else {
            // Removing the final profile disables every Mac action and every
            // ordinary/pure-suppression intercept. A device-level modifier
            // transform explicitly enabled by the user remains available.
            return Self.zeroProfileRuntimeMapping(mapping)
        }
        // A deleted canonical alias remains a stable profile-action anchor.
        // Add a runtime-only key at that index so HID routing still selects
        // the same action; persistence continues to contain physical sources
        // only, and the visible remaining source remains independently named.
        return filteredRuntimeMapping(
            mapping,
            assigned: Set(mappingForProfile(named: profileName).keys)
        )
    }

    static func zeroProfileRuntimeMapping(_ mapping: [String: HardwareKey]) -> [String: HardwareKey] {
        mapping.filter { key, value in
            (Int(key).map { $0 >= 1 } ?? false) && value.usesCommandControlTransform
        }
    }

    private func filteredRuntimeMapping(
        _ mapping: [String: HardwareKey],
        assigned: Set<Int>
    ) -> [String: HardwareKey] {
        _ = assigned
        return mapping.filter { key, value in
            // Keep every learned source at a valid index. An intercepted key is
            // honored even without a Mac custom value, so users can block an
            // onboard key outright (pure suppression); a non-intercepted key
            // stays for source identification and passes through.
            Int(key).map { $0 >= 1 } ?? false
        }
    }

    /// Per-device action tables for ButtonMapper: each consumed device
    /// executes its effective profile's actions.
    func deviceActionMappings(forDeviceKeys keys: [String]) -> [String: [Int: ActionType]] {
        var result: [String: [Int: ActionType]] = [:]
        for key in keys {
            result[key] = effectiveProfileName(forDeviceKey: key)
                .map { mappingForProfile(named: $0) } ?? [:]
        }
        return result
    }

    /// Mirrors HIDListener's binding validation so UI state never promises
    /// that an invalid or ambiguous source is active.
    func usableRuntimeSourceIndices() -> Set<Int> {
        var resolved = Set<Int>()
        for (indexString, key) in runtimeHardwareMapping() {
            guard let index = Int(indexString) else { continue }
            let signature = HIDUsageSignature(
                page: key.usagePage,
                usage: key.usage,
                direction: key.valueDirection ?? 0
            )
            if signature.page == 0x09 && signature.usage <= 2 { continue }
            resolved.insert(index)
        }
        return resolved
    }

    func availableProfiles() -> [String] {
        return Array(profiles.keys).sorted()
    }

    func mappingForCurrentProfile() -> [Int: ActionType] {
        mappingForProfile(named: currentProfileName)
    }

    func mappingForProfile(named name: String) -> [Int: ActionType] {
        guard let profile = profiles[name] else { return [:] }
        var result: [Int: ActionType] = [:]
        for (key, action) in profile.buttons {
            if let idx = Int(key), let mapped = convert(action: action) {
                result[idx] = mapped
            }
        }
        return result
    }

    // MARK: - Profile Management

    @discardableResult
    func createProfile(name: String, basedOn base: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profiles[trimmed] == nil else { return false }
        if let base = base, let p = profiles[base] {
            profiles[trimmed] = p
        } else {
            profiles[trimmed] = Profile(buttons: [:])
        }
        setCurrentProfile(trimmed)
        return true
    }

    @discardableResult
    func duplicateProfile(source: String, as newName: String) -> Bool {
        return createProfile(name: newName, basedOn: source)
    }

    @discardableResult
    func renameProfile(from oldName: String, to newName: String) -> Bool {
        let newTrim = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard oldName != newTrim, !newTrim.isEmpty, let existing = profiles[oldName], profiles[newTrim] == nil else { return false }
        let previousConfigurations = getDeviceConfigurations()
        let previousCurrentProfile = currentProfileName
        profiles.removeValue(forKey: oldName)
        profiles[newTrim] = existing
        if currentProfileName == oldName { currentProfileName = newTrim }
        guard remapBoundProfiles(from: oldName, to: newTrim) else {
            profiles.removeValue(forKey: newTrim)
            profiles[oldName] = existing
            currentProfileName = previousCurrentProfile
            return false
        }
        UserDefaults.standard.set(currentProfileName, forKey: kCurrentProfileKey)
        guard saveUserProfiles() else {
            _ = setDeviceConfigurations(previousConfigurations)
            profiles.removeValue(forKey: newTrim)
            profiles[oldName] = existing
            currentProfileName = previousCurrentProfile
            UserDefaults.standard.set(previousCurrentProfile, forKey: kCurrentProfileKey)
            refreshRuntimeMappings()
            postProfileStructureChange()
            postRuntimeRoutingChange()
            return false
        }
        postProfileStructureChange()
        postRuntimeRoutingChange()
        return true
    }

    /// Device references follow profile renames and drop deleted profiles so
    /// a stale name can never yank a device onto a nonexistent profile. On
    /// deletion (newName == nil) the device falls back to its next mounted
    /// profile, or becomes an explicit zero-profile device when none remain.
    @discardableResult
    private func remapBoundProfiles(from oldName: String, to newName: String?) -> Bool {
        updateDeviceConfigurations { configurations in
            for (key, configuration) in configurations {
                var updated = configuration
                var touched = false
                if updated.boundProfile == oldName {
                    updated.boundProfile = newName
                    touched = true
                }
                if var refs = updated.profileRefs, refs.contains(oldName) {
                    if let newName {
                        refs = refs.map { $0 == oldName ? newName : $0 }
                    } else {
                        refs.removeAll { $0 == oldName }
                    }
                    updated.profileRefs = refs
                    touched = true
                }
                if updated.activeProfile == oldName {
                    if newName == nil, updated.profileRefs == nil {
                        updated.profileRefs = []
                    }
                    updated.activeProfile = newName
                        ?? updated.profileRefs?.first(where: { profiles[$0] != nil })
                    touched = true
                }
                if touched { configurations[key] = updated }
            }
        }
    }

    @discardableResult
    func deleteProfile(named name: String) -> Bool {
        guard profiles[name] != nil else { return false }
        // Prevent deleting the last profile
        if profiles.count <= 1 { return false }
        let previousConfigurations = getDeviceConfigurations()
        let previousCurrentProfile = currentProfileName
        let removedProfile = profiles[name]!
        profiles.removeValue(forKey: name)
        guard remapBoundProfiles(from: name, to: nil) else {
            profiles[name] = removedProfile
            return false
        }
        if currentProfileName == name {
            // Switch to an arbitrary remaining profile
            if let next = profiles.keys.sorted().first {
                setCurrentProfile(next)
            }
        } else {
            refreshRuntimeMappings()
            // Devices using the deleted profile must drop its cached action
            // table immediately, not keep executing a ghost profile.
            postProfileStructureChange()
            postRuntimeRoutingChange()
        }
        guard saveUserProfiles() else {
            _ = setDeviceConfigurations(previousConfigurations)
            profiles[name] = removedProfile
            currentProfileName = previousCurrentProfile
            UserDefaults.standard.set(previousCurrentProfile, forKey: kCurrentProfileKey)
            refreshRuntimeMappings()
            postProfileStructureChange()
            postRuntimeRoutingChange()
            return false
        }
        return true
    }

    // MARK: - Import / Export

    func importProfiles(from url: URL, merge: Bool = true) throws {
        let data = try Data(contentsOf: url)
        let pf = try JSONDecoder().decode(ProfilesFile.self, from: data)
        if let identityRules = pf.identityRules {
            try DeviceIdentityRuleStore.shared.validateArchive(identityRules)
        }
        if merge, pf.identityRules != nil {
            throw NSError(
                domain: "ConfigManager.IdentityRules",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("完整备份包含设备身份规则。为避免合并时改变现有设备归属，请使用覆盖导入。")]
            )
        }
        let previousProfiles = profiles
        let previousCurrentProfile = currentProfileName
        let previousDevices = getDeviceConfigurations()
        let previousIdentityRules = DeviceIdentityRuleStore.shared.archive()
        do {
            if merge {
                for (key, value) in pf.profiles { profiles[key] = value }
            } else {
                profiles = pf.profiles
            }
            // Restore the per-device state a full backup carried, so learned
            // tables, mounts and custom sources survive the round-trip. Merge
            // over existing devices; replace import adopts the file's set.
            if let importedDevices = pf.deviceConfigurations {
                let normalizedDevices = importedDevices.mapValues(Self.configurationByMigratingInputGroups)
                let saved: Bool
                if merge {
                    saved = updateDeviceConfigurations { configurations in
                        for (key, value) in normalizedDevices { configurations[key] = value }
                    }
                } else {
                    saved = setDeviceConfigurations(normalizedDevices)
                }
                guard saved else {
                    throw NSError(
                        domain: "ConfigManager.DeviceConfigurations",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: L10n.text("设备配置编码失败，当前更改未保存")]
                    )
                }
            }
            if let identityRules = pf.identityRules {
                try DeviceIdentityRuleStore.shared.replaceArchive(identityRules)
            }
            if let profile = pf.settings?.currentProfile, profiles[profile] != nil {
                currentProfileName = profile
            } else if profiles[currentProfileName] == nil {
                currentProfileName = defaultProfileName()
            }
            try persistUserProfiles()
            UserDefaults.standard.set(currentProfileName, forKey: kCurrentProfileKey)
            lastProfileSaveError = nil
            NotificationCenter.default.post(name: Self.saveStateDidChangeNotification, object: self)
        } catch {
            profiles = previousProfiles
            currentProfileName = previousCurrentProfile
            setDeviceConfigurations(previousDevices)
            try? DeviceIdentityRuleStore.shared.replaceArchive(previousIdentityRules)
            UserDefaults.standard.set(previousCurrentProfile, forKey: kCurrentProfileKey)
            lastProfileSaveError = error.localizedDescription
            NotificationCenter.default.post(name: Self.saveStateDidChangeNotification, object: self)
            refreshRuntimeMappings()
            postPresentationChange()
            postProfileStructureChange()
            postRuntimeRoutingChange()
            HIDListener.shared.refreshIdentityRules()
            throw error
        }
        HIDListener.shared.refreshIdentityRules()
        refreshRuntimeMappings()
        postPresentationChange()
        postProfileStructureChange()
        postRuntimeRoutingChange()
    }

    func exportCurrentProfile(to url: URL) throws {
        try exportProfile(named: currentProfileName, to: url)
    }

    func exportProfile(named name: String, to url: URL) throws {
        guard let p = profiles[name] else { return }
        let pf = ProfilesFile(profiles: [name: p], settings: currentSettings())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pf)
        try data.write(to: url, options: .atomic)
    }

    func exportAllProfiles(to url: URL) throws {
        // Full backup: every profile plus every device's learned tables and
        // mounts, independent of which device the UI is currently editing.
        let pf = ProfilesFile(
            profiles: profiles,
            settings: currentSettings(),
            deviceConfigurations: getDeviceConfigurations(),
            identityRules: DeviceIdentityRuleStore.shared.archive()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pf)
        try data.write(to: url, options: .atomic)
    }

    /// Profile names in an import file that already exist and would be
    /// overwritten — surfaced to the user for confirmation before importing.
    func conflictingProfileNames(in url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let pf = try JSONDecoder().decode(ProfilesFile.self, from: data)
        return pf.profiles.keys.filter { profiles[$0] != nil }.sorted()
    }

    private func convert(action: ButtonAction) -> ActionType? {
        switch action.type {
        case "keySequence":
            return .keySequence(keys: action.keys ?? [], description: action.description)
        case "application":
            if let path = action.path { return .application(path: path, description: action.description) }
            return nil
        case "systemCommand":
            if let cmd = action.command { return .systemCommand(command: cmd, description: action.description) }
            return nil
        case "textSnippet":
            if let text = action.text { return .textSnippet(text: text, description: action.description) }
            return nil
        case "macro":
            return .macro(steps: action.steps ?? [], description: action.description)
        case "profileSwitch":
            if let p = action.profile { return .profileSwitch(profile: p, description: action.description) }
            return nil
        case "mouseClick":
            if let b = action.mouseButton { return .mouseClick(button: b, description: action.description) }
            return nil
        case "systemAction":
            if let identifier = action.systemAction { return .systemAction(identifier: identifier, description: action.description) }
            return nil
        case "openTarget":
            if let target = action.target { return .openTarget(target: target, description: action.description) }
            return nil
        case "scrollControl":
            if let role = action.scrollControl { return .scrollControl(role: role, description: action.description) }
            return nil
        default:
            return nil
        }
    }

    private func toButtonAction(_ action: ActionType) -> ButtonAction {
        switch action {
        case .keySequence(let keys, let description):
            return ButtonAction(type: "keySequence", keys: keys, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .application(let path, let description):
            return ButtonAction(type: "application", keys: nil, description: description, path: path, command: nil, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .systemCommand(let command, let description):
            return ButtonAction(type: "systemCommand", keys: nil, description: description, path: nil, command: command, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .textSnippet(let text, let description):
            return ButtonAction(type: "textSnippet", keys: nil, description: description, path: nil, command: nil, text: text, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .macro(let steps, let description):
            return ButtonAction(type: "macro", keys: nil, description: description, path: nil, command: nil, text: nil, steps: steps, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .profileSwitch(let profile, let description):
            return ButtonAction(type: "profileSwitch", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: profile, mouseButton: nil, systemAction: nil, target: nil, scrollControl: nil)
        case .mouseClick(let button, let description):
            return ButtonAction(type: "mouseClick", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mouseButton: button, systemAction: nil, target: nil, scrollControl: nil)
        case .systemAction(let identifier, let description):
            return ButtonAction(type: "systemAction", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: identifier, target: nil, scrollControl: nil)
        case .openTarget(let target, let description):
            return ButtonAction(type: "openTarget", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: target, scrollControl: nil)
        case .scrollControl(let role, let description):
            return ButtonAction(type: "scrollControl", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mouseButton: nil, systemAction: nil, target: nil, scrollControl: role)
        }
    }

    /// Update a single button's action in an explicit profile — the editor
    /// always names its target so edits can never land in the wrong table.
    func setAction(forButton index: Int, action: ActionType?, inProfile profileName: String) {
        var profile = profiles[profileName] ?? Profile(buttons: [:])
        let key = String(index)
        if let action = action {
            profile.buttons[key] = toButtonAction(action)
        } else {
            profile.buttons.removeValue(forKey: key)
        }
        profiles[profileName] = profile
        refreshRuntimeMappings()
        postRuntimeRoutingChange()
    }

    // Legacy entry point: writes the globally selected profile.
    func setAction(forButton index: Int, action: ActionType?) {
        setAction(forButton: index, action: action, inProfile: currentProfileName)
    }

    private func persistUserProfiles() throws {
        let url = try userProfilesURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pf = ProfilesFile(profiles: profiles, settings: currentSettings())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pf)
        try data.write(to: url, options: .atomic)
        NSLog("[Config] Saved profiles to: \(url.path)")
    }

    // Persist current profiles to Application Support and expose the result so
    // the UI never claims an unsuccessful write was saved.
    @discardableResult
    func saveUserProfiles() -> Bool {
        do {
            try persistUserProfiles()
            lastProfileSaveError = nil
            NotificationCenter.default.post(name: Self.saveStateDidChangeNotification, object: self)
            return true
        } catch {
            NSLog("[Config] Failed to save profiles: \(error.localizedDescription)")
            lastProfileSaveError = error.localizedDescription
            NotificationCenter.default.post(name: Self.saveStateDidChangeNotification, object: self)
            return false
        }
    }

    private func userProfilesURL() throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return appSupport.appendingPathComponent("NagaController/profiles.json")
    }

    private func currentSettings() -> Settings {
        // hardwareMapping is a legacy single-table field; per-device tables now
        // live in deviceConfigurations, so leave it nil rather than letting the
        // export depend on which device the UI happens to be editing.
        Settings(
            currentProfile: currentProfileName,
            autoSwitchProfiles: nil,
            showNotifications: nil,
            reverseScrollWheel: getReverseScrollWheel(),
            hardwareMapping: nil
        )
    }

    private func applyFallbackMapping() {
        // A clean installation must never execute test or example actions.
        ButtonMapper.shared.updateMapping([:])
    }
}
