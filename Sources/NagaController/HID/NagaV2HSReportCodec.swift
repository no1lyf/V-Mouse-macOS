import Foundation

struct HIDUsageSignature: Hashable {
    let page: UInt32
    let usage: UInt32
    let direction: Int

    init(page: UInt32, usage: UInt32, direction: Int = 0) {
        self.page = page
        self.usage = usage
        self.direction = direction
    }
}

/// Immutable facts audited from the supported Naga V2 HyperSpeed. The runtime
/// opens the device for observation only and rejects every descriptor that is
/// not byte-for-byte identical.
enum NagaV2HSReportCodec {
    static let supportedVendorID = 0x068e
    static let supportedProductName = "Naga V2 HS"
    static let maximumInputReportSize = 9

    static let physicalReportDescriptor = Data(hexString:
        "05010902a10185010901a100050919012906150025017501950681020600ff7501950a8103050c0a38021581257f750895018106050109381581257f7508950181060930093116008026ff7f751095028106c0c0" +
        "050c0901a101850219002a3c021500263c02950175108100950575088101c0" +
        "05010980a1018503198129831500250175019503810295058101750795088101c0" +
        "05010900a10185040903150026ff00350046ff00750895088100c0" +
        "05010900a10185050903150026ff00350046ff00750895088100c0" +
        "05010906a1018506050719e029e715002501750195088102050719002aff00150026ff00750895068100c0"
    )

    static func supports(vendorID: Int, product: String, descriptor: Data, maximumReportSize: Int) -> Bool {
        vendorID == supportedVendorID &&
            product == supportedProductName &&
            descriptor == physicalReportDescriptor &&
            maximumReportSize == maximumInputReportSize
    }

    static func payloadLength(for reportID: UInt32) -> Int? {
        switch reportID {
        case 1: return 8
        case 2: return 7
        case 3, 4, 5: return 8
        case 6: return 7
        default: return nil
        }
    }

    /// The audited descriptor exposes wheel tilt as Consumer AC Pan in the
    /// third byte of Report 1. Return only its direction because magnitude is
    /// relative and can vary with firmware and click cadence.
    static func horizontalPanDirection(inReport1 payload: [UInt8]) -> Int? {
        guard payload.count == 8 else { return nil }
        let value = Int8(bitPattern: payload[2])
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return nil
    }
}

/// A transport-specific decoder selected only after the complete HID report
/// descriptor has matched an audited fixture. Unknown descriptors never reach
/// the runtime input path.
enum NagaHIDCodec: String, Equatable {
    case legacyV2HS
    case v2HyperSpeedReceiver

    func decode(reportID: UInt32, bytes: [UInt8]) -> NagaDecodedReport? {
        let payloadLength: Int
        switch (self, reportID) {
        case (.legacyV2HS, 1): payloadLength = 8
        case (.legacyV2HS, 2): payloadLength = 7
        case (.legacyV2HS, 3...5): payloadLength = 8
        case (.legacyV2HS, 6): payloadLength = 7
        case (.v2HyperSpeedReceiver, 1...3): payloadLength = 15
        case (.v2HyperSpeedReceiver, 10): payloadLength = 9
        default: return nil
        }
        guard let payload = Self.payload(
            reportID: reportID,
            bytes: bytes,
            expectedLength: payloadLength
        ) else { return nil }

        switch (self, reportID) {
        case (.legacyV2HS, 1):
            return .pointer(
                buttons: payload[0],
                horizontalPanDirection: Self.direction(payload[2])
            )
        case (.v2HyperSpeedReceiver, 10):
            // Receiver report 10: buttons, two vendor bytes, AC Pan, wheel, X, Y.
            return .pointer(
                buttons: payload[0],
                horizontalPanDirection: Self.direction(payload[3])
            )
        case (.legacyV2HS, 2), (.v2HyperSpeedReceiver, 2):
            return .consumer(usage: UInt32(payload[0]) | (UInt32(payload[1]) << 8))
        case (.legacyV2HS, 3), (.v2HyperSpeedReceiver, 3):
            var usages: Set<UInt32> = []
            for bit in 0..<3 where payload[0] & UInt8(1 << bit) != 0 {
                usages.insert(UInt32(0x81 + bit))
            }
            return .system(usages: usages)
        case (.legacyV2HS, 6):
            return .keyboard(modifiers: payload[0], usages: Self.keyboardUsages(payload[1..<7]))
        case (.v2HyperSpeedReceiver, 1):
            return .keyboard(modifiers: payload[0], usages: Self.keyboardUsages(payload[1..<15]))
        default:
            return nil
        }
    }

    /// Always returns a zero-based Array. The previous ArraySlice return kept
    /// the original indices: on the ID-prefixed path (Bluetooth framing keeps
    /// the report ID byte) the slice started at 1, so the callers' absolute
    /// subscripts like payload[0] trapped with SIGTRAP.
    private static func payload(
        reportID: UInt32,
        bytes: [UInt8],
        expectedLength: Int
    ) -> [UInt8]? {
        if bytes.count == expectedLength { return bytes }
        if bytes.count == expectedLength + 1,
           bytes.first == UInt8(truncatingIfNeeded: reportID) {
            return Array(bytes.dropFirst())
        }
        return nil
    }

    private static func keyboardUsages(_ bytes: ArraySlice<UInt8>) -> Set<UInt32> {
        Set(bytes.lazy.filter { $0 != 0 }.map(UInt32.init))
    }

    private static func direction(_ byte: UInt8) -> Int? {
        let value = Int8(bitPattern: byte)
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return nil
    }
}

enum NagaDecodedReport: Equatable {
    case pointer(buttons: UInt8, horizontalPanDirection: Int?)
    case consumer(usage: UInt32)
    case system(usages: Set<UInt32>)
    case keyboard(modifiers: UInt8, usages: Set<UInt32>)
}

struct HIDDeviceIdentity: Equatable {
    let vendorID: Int
    let productID: Int
    let product: String
    /// Defaulted so diagnostic fixtures without a serial keep compiling.
    var serialNumber: String = ""
    let descriptor: Data
    let maximumInputReportSize: Int
    let transport: String
    let locationID: Int
    let primaryUsagePage: Int
    let primaryUsage: Int
    let isBuiltIn: Bool
}

/// Why an external HID interface cannot be used, for user-facing diagnostics.
enum HIDUnsupportedReason: String, Equatable {
    case vendorPrivateProtocol
    case invalidIdentity
    case notInputDeviceClass

    var displayText: String {
        switch self {
        case .vendorPrivateProtocol: return L10n.text("厂商私有协议，需专用适配")
        case .invalidIdentity: return L10n.text("设备身份无效")
        case .notInputDeviceClass: return L10n.text("非鼠标/键盘类设备")
        }
    }
}

struct HIDDeviceCandidateSummary: Equatable {
    let identifier: String
    let vendorID: Int
    let productID: Int
    let product: String
    var serialNumber: String = ""
    let transport: String
    let locationID: Int
    let primaryUsagePage: Int
    let primaryUsage: Int
    let maximumInputReportSize: Int
    let descriptorFingerprint: String
    let codecIdentifier: String?
    let supportsStandardHID: Bool
    let physicalGroupIdentifier: String
    let unsupportedReason: HIDUnsupportedReason?

    var isSupported: Bool { codecIdentifier != nil || supportsStandardHID }

    var baseDeviceKey: String { DeviceIdentityPolicy.baseKey(vendorID: vendorID, productID: productID) }

    var observedIdentityFacts: DeviceIdentityObservedFacts {
        DeviceIdentityObservedFacts(
            vendorID: vendorID,
            productID: productID,
            productName: product,
            serialNumber: serialNumber,
            descriptorFingerprint: descriptorFingerprint,
            maximumInputReportSize: maximumInputReportSize,
            primaryUsagePage: primaryUsagePage,
            primaryUsage: primaryUsage,
            transport: transport,
            codecIdentifier: codecIdentifier
        )
    }

    /// VID/PID is always the migration/fallback key. Families with an audited
    /// stable discriminator may opt into an enhanced instance key; otherwise
    /// identical products deliberately continue to share the base key instead
    /// of persisting a volatile port/location identifier as if it were stable.
    var deviceKey: String {
        DeviceIdentityPolicy.deviceKey(facts: observedIdentityFacts)
    }
}

/// Persisted device identity policy. The table is intentionally family-scoped:
/// adding a discriminator for one audited device family cannot silently split
/// every existing generic HID device. Location ID remains runtime-only.
enum DeviceIdentityPolicy {
    static func baseKey(vendorID: Int, productID: Int) -> String {
        String(format: "%04x:%04x", vendorID, productID)
    }

    static func deviceKey(facts: DeviceIdentityObservedFacts, rule: DeviceIdentityRule? = nil) -> String {
        let effectiveRule = rule ?? DeviceIdentityRuleStore.shared.effectiveRule(for: facts)
        return DeviceIdentityRuleEvaluator.deviceKey(facts: facts, rule: effectiveRule)
    }

    static func deviceKey(
        vendorID: Int,
        productID: Int,
        serialNumber: String,
        codecIdentifier: String? = nil
    ) -> String {
        let facts = DeviceIdentityObservedFacts(
            vendorID: vendorID,
            productID: productID,
            productName: "",
            serialNumber: serialNumber,
            descriptorFingerprint: "",
            maximumInputReportSize: 0,
            primaryUsagePage: 0,
            primaryUsage: 0,
            transport: "",
            codecIdentifier: codecIdentifier
        )
        return DeviceIdentityRuleEvaluator.deviceKey(
            facts: facts,
            rule: DeviceIdentityRuleStore.builtInDefaultRule(
                baseKey: facts.baseKey,
                codecIdentifier: codecIdentifier
            )
        )
    }

    static func baseKey(from deviceKey: String) -> String {
        String(deviceKey.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    static func isEnhanced(_ deviceKey: String) -> Bool {
        deviceKey.contains("#")
    }

}

struct HIDPhysicalDeviceCandidateGroup: Equatable {
    let identifier: String
    let product: String
    let transport: String
    let locationID: Int
    let candidates: [HIDDeviceCandidateSummary]

    var isSupported: Bool { candidates.contains(where: \.isSupported) }
    var hasCodec: Bool { candidates.contains(where: { $0.codecIdentifier != nil }) }
    var deviceKey: String { candidates.first?.deviceKey ?? identifier }
    var unsupportedReason: HIDUnsupportedReason? {
        guard !isSupported else { return nil }
        return candidates.compactMap(\.unsupportedReason).first
    }
}

enum NagaHIDCodecRegistry {
    /// Audited on the Razer 2.4 GHz receiver exposed by macOS as the composite
    /// 1532:00b4 "Razer Naga V2 HyperSpeed" IOHIDDevice. Its sibling pointer
    /// and keyboard interfaces deliberately have different descriptors and
    /// remain candidates only; accepting them as well would duplicate input.
    static let v2HyperSpeedReceiverCompositeDescriptor = Data(hexString:
        "05010906a1018501050719e029e71500250175019508810219002aff00150026ff007508950e81000508190129031500250175019503910295059101c0" +
        "05010902a101850a0901a100050919012906150025017501950681027501950281030600ff0940750895021581257f8102050109381581257f7508950181060930093116008026ff7f751095028106c0c0" +
        "050c0901a101850219002a3c021500263c029501751081007508950d8101c0" +
        "05010980a10185031981298315002501750195038102950581017508950e8101c0" +
        "05010900a10185040903150026ff00350046ff007508950f8100c0" +
        "05010900a10185050903150026ff00350046ff007508950f8100c0" +
        "05010900a10185080903150026ff00350046ff007508950f8100c0" +
        "05010900a10185090903150026ff00350046ff007508950f8100c0"
    )

    static func codec(for identity: HIDDeviceIdentity) -> NagaHIDCodec? {
        if NagaV2HSReportCodec.supports(
            vendorID: identity.vendorID,
            product: identity.product,
            descriptor: identity.descriptor,
            maximumReportSize: identity.maximumInputReportSize
        ) {
            return .legacyV2HS
        }
        if identity.vendorID == 0x1532,
           identity.productID == 0x00b4,
           identity.descriptor == v2HyperSpeedReceiverCompositeDescriptor,
           identity.maximumInputReportSize == 16 {
            return .v2HyperSpeedReceiver
        }
        return nil
    }

    static func summary(for identity: HIDDeviceIdentity) -> HIDDeviceCandidateSummary {
        let fingerprint = descriptorFingerprint(identity.descriptor)
        let codec = codec(for: identity)
        let identifier = String(
            format: "%04x:%04x:%x:%@",
            identity.vendorID,
            identity.productID,
            identity.locationID,
            fingerprint
        )
        let physicalGroupIdentifier = String(
            format: "%04x:%04x:%x",
            identity.vendorID,
            identity.productID,
            identity.locationID
        )
        let supportsStandardHID = !identity.isBuiltIn && standardHIDCapable(identity)
        let unsupportedReason: HIDUnsupportedReason? =
            (codec != nil || supportsStandardHID) ? nil : standardHIDUnsupportedReason(identity)
        return HIDDeviceCandidateSummary(
            identifier: identifier,
            vendorID: identity.vendorID,
            productID: identity.productID,
            product: identity.product,
            serialNumber: identity.serialNumber,
            transport: identity.transport,
            locationID: identity.locationID,
            primaryUsagePage: identity.primaryUsagePage,
            primaryUsage: identity.primaryUsage,
            maximumInputReportSize: identity.maximumInputReportSize,
            descriptorFingerprint: fingerprint,
            codecIdentifier: codec?.rawValue,
            supportsStandardHID: supportsStandardHID,
            physicalGroupIdentifier: physicalGroupIdentifier,
            unsupportedReason: unsupportedReason
        )
    }

    /// Mirrors standardHIDCapable's checks to explain a rejection to the user.
    static func standardHIDUnsupportedReason(_ identity: HIDDeviceIdentity) -> HIDUnsupportedReason {
        guard (1...0xffff).contains(identity.vendorID),
              (0...0xffff).contains(identity.productID),
              !identity.product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalidIdentity
        }
        if identity.primaryUsagePage >= 0xff00 { return .vendorPrivateProtocol }
        return .notInputDeviceClass
    }

    static func standardHIDCapable(_ identity: HIDDeviceIdentity) -> Bool {
        // macOS exposes internal audio/SPMI control nodes without a real USB
        // vendor/product identity. They can advertise standard usage pairs but
        // are not user-selectable keyboards or pointing devices.
        guard !identity.isBuiltIn,
              (1...0xffff).contains(identity.vendorID),
              (0...0xffff).contains(identity.productID),
              !identity.product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch (identity.primaryUsagePage, identity.primaryUsage) {
        case (0x01, 0x02), // Mouse
             (0x01, 0x06), // Keyboard
             (0x01, 0x80), // System control
             (0x0c, 0x01): // Consumer control
            return true
        default:
            return false
        }
    }

    /// A stable diagnostic fingerprint, not an authorization decision. Codec
    /// selection always compares the complete descriptor bytes above.
    static func descriptorFingerprint(_ descriptor: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in descriptor {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private extension Data {
    init(hexString: String) {
        precondition(hexString.count.isMultiple(of: 2))
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else {
                preconditionFailure("Invalid HID report descriptor")
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
