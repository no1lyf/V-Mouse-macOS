import Foundation

enum DeviceIdentityConditionField: String, Codable, CaseIterable, Hashable {
    case productName
    case descriptorFingerprint
    case maximumInputReportSize
    case primaryUsagePage
    case primaryUsage
    case transport
    case codecIdentifier

    var displayName: String {
        switch self {
        case .productName: return L10n.text("产品名称")
        case .descriptorFingerprint: return L10n.text("描述符指纹")
        case .maximumInputReportSize: return L10n.text("最大输入报告长度")
        case .primaryUsagePage: return "Primary Usage Page"
        case .primaryUsage: return "Primary Usage"
        case .transport: return L10n.text("连接方式")
        case .codecIdentifier: return L10n.text("专用协议标识")
        }
    }
}

enum DeviceIdentityDiscriminatorField: String, Codable, CaseIterable, Hashable {
    case serialNumber
    case transport
    case descriptorFingerprint

    var displayName: String {
        switch self {
        case .serialNumber: return L10n.text("序列号")
        case .transport: return L10n.text("连接方式")
        case .descriptorFingerprint: return L10n.text("描述符指纹")
        }
    }

    var keyComponentName: String {
        switch self {
        case .serialNumber: return "serial"
        case .transport: return "transport"
        case .descriptorFingerprint: return "descriptor"
        }
    }
}

struct DeviceIdentityCondition: Codable, Equatable, Hashable {
    var field: DeviceIdentityConditionField
    var expectedValue: String
}

struct DeviceIdentityRule: Codable, Equatable, Hashable {
    var baseKey: String
    var enhancedRecognitionEnabled: Bool
    var conditions: [DeviceIdentityCondition]
    var discriminatorFields: [DeviceIdentityDiscriminatorField]

    var totalConditionCount: Int { 2 + conditions.count }
}

struct DeviceIdentityRuleArchive: Codable, Equatable {
    var schemaVersion: Int
    var rules: [DeviceIdentityRule]
}

struct DeviceIdentityObservedFacts: Equatable {
    var vendorID: Int
    var productID: Int
    var productName: String
    var serialNumber: String
    var descriptorFingerprint: String
    var maximumInputReportSize: Int
    var primaryUsagePage: Int
    var primaryUsage: Int
    var transport: String
    var codecIdentifier: String?

    var baseKey: String { String(format: "%04x:%04x", vendorID, productID) }

    func conditionValue(_ field: DeviceIdentityConditionField) -> String? {
        switch field {
        case .productName: return Self.normalizedText(productName)
        case .descriptorFingerprint: return Self.normalizedText(descriptorFingerprint)?.lowercased()
        case .maximumInputReportSize: return String(maximumInputReportSize)
        case .primaryUsagePage: return String(primaryUsagePage)
        case .primaryUsage: return String(primaryUsage)
        case .transport: return Self.normalizedText(transport)?.lowercased()
        case .codecIdentifier: return codecIdentifier.flatMap(Self.normalizedText)
        }
    }

    func discriminatorValue(_ field: DeviceIdentityDiscriminatorField) -> String? {
        switch field {
        case .serialNumber: return Self.normalizedStableIdentityText(serialNumber)
        case .transport: return Self.normalizedStableIdentityText(transport)?.lowercased()
        case .descriptorFingerprint: return Self.normalizedStableIdentityText(descriptorFingerprint)?.lowercased()
        }
    }

    static func normalizedExpectedValue(_ raw: String, field: DeviceIdentityConditionField) -> String? {
        guard let value = normalizedText(raw) else { return nil }
        switch field {
        case .descriptorFingerprint, .transport: return value.lowercased()
        default: return value
        }
    }

    private static func normalizedText(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedStableIdentityText(_ raw: String) -> String? {
        guard let value = normalizedText(raw) else { return nil }
        let lower = value.lowercased()
        guard lower != "unknown", lower != "none", lower != "null", lower != "0" else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

enum DeviceIdentityRuleEvaluator {
    static func deviceKey(facts: DeviceIdentityObservedFacts, rule: DeviceIdentityRule?) -> String {
        let base = facts.baseKey
        guard let rule,
              rule.baseKey.lowercased() == base,
              rule.enhancedRecognitionEnabled else { return base }

        // User-confirmed contract: every enabled condition is mandatory. A
        // missing value is a mismatch, never a partial/threshold match.
        for condition in rule.conditions {
            guard let observed = facts.conditionValue(condition.field),
                  let expected = DeviceIdentityObservedFacts.normalizedExpectedValue(
                    condition.expectedValue,
                    field: condition.field
                  ),
                  observed == expected else { return base }
        }

        guard !rule.discriminatorFields.isEmpty else { return base }
        var components: [String] = []
        for field in rule.discriminatorFields {
            guard let value = facts.discriminatorValue(field) else { return base }
            components.append("\(field.keyComponentName)=\(value)")
        }
        return base + "#" + components.joined(separator: "&")
    }
}

final class DeviceIdentityRuleStore {
    static let shared = DeviceIdentityRuleStore()
    static let schemaVersion = 1
    static let defaultsKey = "deviceIdentityRules.v1"

    private let lock = NSLock()
    private var cachedOverrides: [String: DeviceIdentityRule]?

    private init() {}

    func effectiveRule(for facts: DeviceIdentityObservedFacts) -> DeviceIdentityRule? {
        let key = facts.baseKey
        if let override = rulesByBaseKey()[key] { return override }
        return Self.builtInDefaultRule(baseKey: key, codecIdentifier: facts.codecIdentifier)
    }

    func overrideRule(for baseKey: String) -> DeviceIdentityRule? {
        rulesByBaseKey()[baseKey.lowercased()]
    }

    func allOverrideRules() -> [DeviceIdentityRule] {
        rulesByBaseKey().values.sorted { $0.baseKey < $1.baseKey }
    }

    func archive() -> DeviceIdentityRuleArchive {
        DeviceIdentityRuleArchive(schemaVersion: Self.schemaVersion, rules: allOverrideRules())
    }

    func replaceArchive(_ archive: DeviceIdentityRuleArchive) throws {
        try validateArchive(archive)
        try replaceOverrides(archive.rules)
    }

    func validateArchive(_ archive: DeviceIdentityRuleArchive) throws {
        guard archive.schemaVersion == Self.schemaVersion else {
            throw NSError(
                domain: "DeviceIdentityRuleStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("不支持的设备身份规则版本")]
            )
        }
        for rule in archive.rules { _ = try Self.validated(rule) }
    }

    func setOverride(_ rule: DeviceIdentityRule) throws {
        var rules = rulesByBaseKey()
        let normalized = try Self.validated(rule)
        rules[normalized.baseKey] = normalized
        try persist(rules)
    }

    func removeOverride(for baseKey: String) throws {
        var rules = rulesByBaseKey()
        rules.removeValue(forKey: baseKey.lowercased())
        try persist(rules)
    }

    func replaceOverrides(_ rules: [DeviceIdentityRule]) throws {
        var result: [String: DeviceIdentityRule] = [:]
        for rule in rules {
            let normalized = try Self.validated(rule)
            result[normalized.baseKey] = normalized
        }
        try persist(result)
    }

    static func builtInDefaultRule(baseKey: String, codecIdentifier: String?) -> DeviceIdentityRule? {
        if baseKey.lowercased() == "1532:00b4" || codecIdentifier != nil {
            return DeviceIdentityRule(
                baseKey: baseKey.lowercased(),
                enhancedRecognitionEnabled: true,
                conditions: [],
                discriminatorFields: [.serialNumber]
            )
        }
        return nil
    }

    private func rulesByBaseKey() -> [String: DeviceIdentityRule] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedOverrides { return cachedOverrides }
        let loaded: [String: DeviceIdentityRule]
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let archive = try? JSONDecoder().decode(DeviceIdentityRuleArchive.self, from: data),
           archive.schemaVersion == Self.schemaVersion {
            loaded = Dictionary(uniqueKeysWithValues: archive.rules.map { ($0.baseKey.lowercased(), $0) })
        } else {
            loaded = [:]
        }
        cachedOverrides = loaded
        return loaded
    }

    private func persist(_ rules: [String: DeviceIdentityRule]) throws {
        let archive = DeviceIdentityRuleArchive(
            schemaVersion: Self.schemaVersion,
            rules: rules.values.sorted { $0.baseKey < $1.baseKey }
        )
        let data = try JSONEncoder().encode(archive)
        lock.lock()
        cachedOverrides = rules
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        lock.unlock()
    }

    private static func validated(_ rule: DeviceIdentityRule) throws -> DeviceIdentityRule {
        let base = rule.baseKey.lowercased()
        let pattern = try! NSRegularExpression(pattern: "^[0-9a-f]{4}:[0-9a-f]{4}$")
        guard pattern.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)) != nil else {
            throw NSError(
                domain: "DeviceIdentityRuleStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("VID/PID 格式无效")]
            )
        }
        var seen: Set<DeviceIdentityConditionField> = []
        var conditions: [DeviceIdentityCondition] = []
        for condition in rule.conditions where seen.insert(condition.field).inserted {
            guard let value = DeviceIdentityObservedFacts.normalizedExpectedValue(
                condition.expectedValue,
                field: condition.field
            ) else { continue }
            conditions.append(DeviceIdentityCondition(field: condition.field, expectedValue: value))
        }
        let discriminators = rule.discriminatorFields.reduce(into: [DeviceIdentityDiscriminatorField]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return DeviceIdentityRule(
            baseKey: base,
            enhancedRecognitionEnabled: rule.enhancedRecognitionEnabled,
            conditions: conditions,
            discriminatorFields: discriminators
        )
    }
}
