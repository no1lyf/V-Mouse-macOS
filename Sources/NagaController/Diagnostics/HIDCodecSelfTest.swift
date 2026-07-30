import Foundation
import Darwin
import ApplicationServices
import Carbon.HIToolbox

/// Every localized source string referenced directly by MainViewController.
/// Keeping this explicit makes additions to the main surface visible in both
/// the executable self-test and XCTest instead of relying on a small smoke set.
let mainScreenLocalizationKeys = [
    "仅监听模式", "仅诊断，不支持", "同时反向水平滚动", "启用按键自定义", "启用滚轮增强",
    "连接外接鼠标时停用内置触控板", "开启后，仅在 V-Mouse 运行且外接鼠标或无线触控板存在时停用内置触控板；退出 V-Mouse 后自动恢复",
    "无法更新触控板设置", "macOS 没有把更改应用到内置触控板。请在系统设置 → 辅助功能 → 指针控制中手动确认该选项。",
    "已授权", "帮助中心...", "打开平滑、方向、速度和快捷键设置", "打开按键映射编辑器",
    "打开设置", "按键自定义总开关决定已配置的 Mac 自定义键值是否运行；滚轮增强与按键自定义相互独立。",
    "未命名设备", "未授权", "未连接", "权限", "检查中...", "滚轮增强未启用", "滚轮设置...",
    "已自动识别：%@", "已选择：%@", "已选设备未连接", "未发现可用输入设备",
    "电量: %d%%", "电量: —", "界面", "自动选择", "语言", "辅助功能", "输入监控", "输入设备", "退出", "配置按键映射..."
]

enum HIDCodecSelfTest {
    static func run() -> [String] {
        var failures: [String] = []

        check(
            NagaV2HSReportCodec.supports(
                vendorID: 0x068e,
                product: "Naga V2 HS",
                descriptor: NagaV2HSReportCodec.physicalReportDescriptor,
                maximumReportSize: 9
            ),
            "exact descriptor must be supported",
            failures: &failures
        )
        let strictFacts = DeviceIdentityObservedFacts(
            vendorID: 0x1234,
            productID: 0x5678,
            productName: "Strict Mouse",
            serialNumber: "UNIT-1",
            descriptorFingerprint: "abcdef",
            maximumInputReportSize: 16,
            primaryUsagePage: 1,
            primaryUsage: 2,
            transport: "USB",
            codecIdentifier: nil
        )
        let strictRule = DeviceIdentityRule(
            baseKey: "1234:5678",
            enhancedRecognitionEnabled: true,
            conditions: [
                DeviceIdentityCondition(field: .productName, expectedValue: "Strict Mouse"),
                DeviceIdentityCondition(field: .maximumInputReportSize, expectedValue: "16")
            ],
            discriminatorFields: [.serialNumber]
        )
        var mismatchedRule = strictRule
        mismatchedRule.conditions[1].expectedValue = "15"
        check(
            strictRule.totalConditionCount == 4 &&
                DeviceIdentityRuleEvaluator.deviceKey(facts: strictFacts, rule: strictRule) ==
                    "1234:5678#serial=UNIT-1" &&
                DeviceIdentityRuleEvaluator.deviceKey(facts: strictFacts, rule: mismatchedRule) ==
                    "1234:5678",
            "every enabled enhanced identity condition must match; partial matches must fall back",
            failures: &failures
        )
        let identityArchive = DeviceIdentityRuleArchive(schemaVersion: 1, rules: [strictRule])
        check(
            (try? JSONDecoder().decode(
                DeviceIdentityRuleArchive.self,
                from: JSONEncoder().encode(identityArchive)
            )) == identityArchive,
            "identity rule archive must survive a full-backup Codable round trip",
            failures: &failures
        )
        var baseConfiguration = DeviceConfiguration()
        baseConfiguration.customDisplayName = "Base"
        var instanceConfiguration = DeviceConfiguration()
        instanceConfiguration.customDisplayName = "Instance"
        let split = try? ConfigManager.migratedIdentityConfigurations(
            ["1234:5678": baseConfiguration],
            moves: [("1234:5678", "1234:5678#serial=UNIT-1")]
        )
        let rejectedConflict = try? ConfigManager.migratedIdentityConfigurations(
            [
                "1234:5678": baseConfiguration,
                "1234:5678#serial=UNIT-1": instanceConfiguration
            ],
            moves: [("1234:5678#serial=UNIT-1", "1234:5678")]
        )
        let resolvedMerge = try? ConfigManager.migratedIdentityConfigurations(
            [
                "1234:5678": baseConfiguration,
                "1234:5678#serial=UNIT-1": instanceConfiguration
            ],
            moves: [("1234:5678#serial=UNIT-1", "1234:5678")],
            conflictResolution: .keepSource
        )
        check(
            split?["1234:5678"] == baseConfiguration &&
                split?["1234:5678#serial=UNIT-1"] == baseConfiguration &&
                rejectedConflict == nil &&
                resolvedMerge?["1234:5678"] == instanceConfiguration &&
                resolvedMerge?["1234:5678#serial=UNIT-1"] == nil,
            "identity migration must retain split templates, reject silent conflicts, and retire merged instances",
            failures: &failures
        )
        var lastProfile = DeviceConfiguration()
        lastProfile.boundProfile = "Default"
        lastProfile.profileRefs = ["Default"]
        lastProfile.activeProfile = "Default"
        let zeroProfile = ConfigManager.configurationByRemovingProfile(
            "Default",
            from: lastProfile,
            profileExists: { $0 == "Default" || $0 == "Work" }
        )
        var twoProfiles = lastProfile
        twoProfiles.profileRefs = ["Default", "Work"]
        let remainingProfile = ConfigManager.configurationByRemovingProfile(
            "Default",
            from: twoProfiles,
            profileExists: { $0 == "Default" || $0 == "Work" }
        )
        check(
            zeroProfile.profileRefs == [] && zeroProfile.activeProfile == nil && zeroProfile.boundProfile == nil &&
                ConfigManager.resolvedProfileName(
                    for: zeroProfile,
                    profileExists: { $0 == "Default" || $0 == "Work" },
                    fallbackProfile: "Default"
                ) == nil && {
                    var staleActiveZero = zeroProfile
                    staleActiveZero.activeProfile = "Default"
                    return ConfigManager.resolvedProfileName(
                        for: staleActiveZero,
                        profileExists: { $0 == "Default" },
                        fallbackProfile: "Default"
                    ) == nil
                }() &&
                remainingProfile.profileRefs == ["Work"] && remainingProfile.activeProfile == "Work" &&
                ConfigManager.resolvedProfileName(
                    for: DeviceConfiguration(),
                    profileExists: { $0 == "Default" },
                    fallbackProfile: "Default"
                ) == "Default",
            "removing the last mounted profile must preserve an explicit pass-through zero-profile state while legacy records still seed Default",
            failures: &failures
        )
        var legacyGroupedConfiguration = DeviceConfiguration()
        legacyGroupedConfiguration.customSourceIndices = [17, 19]
        legacyGroupedConfiguration.removedStandardIndices = [4]
        legacyGroupedConfiguration.customSectionTitles = ["side": "MMO 键区"]
        let migratedGroups = ConfigManager.configurationByMigratingInputGroups(legacyGroupedConfiguration)
        let migratedCustom = migratedGroups.inputGroups?.first(where: { !$0.isBuiltIn })
        check(
            migratedGroups.inputGroups?.first(where: { $0.id == DeviceInputGroup.sideID })?.sourceIndices ==
                [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12] &&
                migratedGroups.inputGroups?.first(where: { $0.id == DeviceInputGroup.sideID })?.title == "MMO 键区" &&
                migratedCustom?.sourceIndices == [17, 19] &&
                migratedGroups.nextCustomSourceOrdinal == 4 &&
                (try? JSONDecoder().decode(
                    DeviceConfiguration.self,
                    from: JSONEncoder().encode(migratedGroups)
                )) == migratedGroups,
            "legacy fixed sections and custom sources must migrate to ordered input groups without loss",
            failures: &failures
        )
        var reorderedGroups = migratedGroups
        reorderedGroups.inputGroups = [
            migratedGroups.inputGroups!.first(where: { $0.id == DeviceInputGroup.scrollID })!,
            migratedGroups.inputGroups!.first(where: { !$0.isBuiltIn })!,
            migratedGroups.inputGroups!.first(where: { $0.id == DeviceInputGroup.sideID })!,
            migratedGroups.inputGroups!.first(where: { $0.id == DeviceInputGroup.dpiID })!
        ]
        check(
            ConfigManager.configurationByMigratingInputGroups(reorderedGroups).inputGroups?.map(\.id) ==
                reorderedGroups.inputGroups?.map(\.id),
            "built-in and custom input groups must preserve one shared user-defined order",
            failures: &failures
        )
        var deletedBuiltInGroup = ConfigManager.configurationByMigratingInputGroups(DeviceConfiguration())
        var deletableGroups = deletedBuiltInGroup.inputGroups!
        let dpiSources = deletableGroups.first(where: { $0.id == DeviceInputGroup.dpiID })!.sourceIndices
        let sidePosition = deletableGroups.firstIndex(where: { $0.id == DeviceInputGroup.sideID })!
        deletableGroups[sidePosition].sourceIndices.append(contentsOf: dpiSources)
        deletableGroups.removeAll { $0.id == DeviceInputGroup.dpiID }
        deletedBuiltInGroup.inputGroups = deletableGroups
        let afterBuiltInDeletion = ConfigManager.normalizedInputGroups(for: deletedBuiltInGroup)
        check(
            !afterBuiltInDeletion.contains(where: { $0.id == DeviceInputGroup.dpiID }) &&
                Set(afterBuiltInDeletion.flatMap(\.sourceIndices)) == Set(1...16),
            "an intentionally deleted empty built-in group must not be recreated during normalization",
            failures: &failures
        )
        var duplicateSignals = DeviceConfiguration()
        duplicateSignals.hardwareMapping = [
            "17": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: false
            ),
            "2": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: true
            )
        ]
        ConfigManager.normalizeSignalAliases(in: &duplicateSignals)
        let duplicateSignature = HIDUsageSignature(page: 0x07, usage: 0x1e)
        let duplicateTable = HIDListener.buildBindingTable(from: duplicateSignals.hardwareMapping ?? [:])
        check(
            duplicateSignals.signalAliasGroups?.count == 1 &&
                duplicateSignals.signalAliasGroups?.first?.canonicalSourceIndex == 2 &&
                duplicateSignals.signalAliasGroups?.first?.memberSourceIndices == [2, 17] &&
                duplicateSignals.hardwareMapping?["2"]?.isIntercepted == true &&
                duplicateSignals.hardwareMapping?["17"]?.isIntercepted == true &&
                duplicateTable[duplicateSignature]?.buttonIndex == 2 &&
                (try? JSONDecoder().decode(
                    DeviceConfiguration.self,
                    from: JSONEncoder().encode(duplicateSignals)
                )) == duplicateSignals,
            "duplicate onboard signals must persist as aliases and route deterministically through the lowest source index",
            failures: &failures
        )
        duplicateSignals.hardwareMapping?.removeValue(forKey: "2")
        ConfigManager.normalizeSignalAliases(in: &duplicateSignals)
        let survivingAliasTable = HIDListener.buildBindingTable(from: ConfigManager.runtimeAliasResolvedMapping(
            duplicateSignals.hardwareMapping ?? [:],
            groups: duplicateSignals.signalAliasGroups ?? []
        ))
        check(
            duplicateSignals.signalAliasGroups?.first?.canonicalSourceIndex == 2 &&
                duplicateSignals.signalAliasGroups?.first?.memberSourceIndices == [17] &&
                survivingAliasTable[duplicateSignature]?.buttonIndex == 2,
            "deleting a canonical duplicate source must keep the surviving key on the same profile action slot",
            failures: &failures
        )
        check(
            !NagaV2HSReportCodec.supports(
                vendorID: 0x1532,
                product: "Naga V2 HS",
                descriptor: NagaV2HSReportCodec.physicalReportDescriptor,
                maximumReportSize: 9
            ),
            "unverified vendor must be rejected",
            failures: &failures
        )
        let receiverIdentity = HIDDeviceIdentity(
            vendorID: 0x1532,
            productID: 0x00b4,
            product: "Razer Naga V2 HyperSpeed",
            descriptor: NagaHIDCodecRegistry.v2HyperSpeedReceiverCompositeDescriptor,
            maximumInputReportSize: 16,
            transport: "USB",
            locationID: 0x01143300,
            primaryUsagePage: 1,
            primaryUsage: 6,
            isBuiltIn: false
        )
        check(
            NagaHIDCodecRegistry.codec(for: receiverIdentity) == .v2HyperSpeedReceiver &&
                NagaHIDCodecRegistry.summary(for: receiverIdentity).isSupported,
            "audited 2.4 GHz receiver descriptor must select its exact codec",
            failures: &failures
        )
        var corruptedReceiverDescriptor = NagaHIDCodecRegistry.v2HyperSpeedReceiverCompositeDescriptor
        corruptedReceiverDescriptor[corruptedReceiverDescriptor.startIndex] ^= 0xff
        let corruptedReceiver = HIDDeviceIdentity(
            vendorID: receiverIdentity.vendorID,
            productID: receiverIdentity.productID,
            product: receiverIdentity.product,
            descriptor: corruptedReceiverDescriptor,
            maximumInputReportSize: receiverIdentity.maximumInputReportSize,
            transport: receiverIdentity.transport,
            locationID: receiverIdentity.locationID,
            primaryUsagePage: receiverIdentity.primaryUsagePage,
            primaryUsage: receiverIdentity.primaryUsage,
            isBuiltIn: receiverIdentity.isBuiltIn
        )
        check(
            NagaHIDCodecRegistry.codec(for: corruptedReceiver) == nil,
            "receiver codec selection must reject a one-byte descriptor mutation",
            failures: &failures
        )
        let standardKeyboard = HIDDeviceIdentity(
            vendorID: 0x1234,
            productID: 0x5678,
            product: "Generic external keyboard",
            descriptor: Data([0x05, 0x01, 0x09, 0x06]),
            maximumInputReportSize: 8,
            transport: "USB",
            locationID: 0x01000000,
            primaryUsagePage: 0x01,
            primaryUsage: 0x06,
            isBuiltIn: false
        )
        let standardKeyboardSummary = NagaHIDCodecRegistry.summary(for: standardKeyboard)
        check(
            NagaHIDCodecRegistry.codec(for: standardKeyboard) == nil &&
                standardKeyboardSummary.supportsStandardHID &&
                standardKeyboardSummary.isSupported,
            "external standard HID keyboards must remain manually selectable without entering raw-codec mode",
            failures: &failures
        )
        let privateVendorDevice = HIDDeviceIdentity(
            vendorID: 0x1234,
            productID: 0x5678,
            product: "Unknown private device",
            descriptor: Data([0x06, 0x00, 0xff, 0x09, 0x01]),
            maximumInputReportSize: 64,
            transport: "USB",
            locationID: 0x02000000,
            primaryUsagePage: 0xff00,
            primaryUsage: 0x01,
            isBuiltIn: false
        )
        let privateVendorSummary = NagaHIDCodecRegistry.summary(for: privateVendorDevice)
        check(
            NagaHIDCodecRegistry.codec(for: privateVendorDevice) == nil &&
                !privateVendorSummary.supportsStandardHID &&
                !privateVendorSummary.isSupported,
            "unknown vendor-private HID interfaces must fail closed",
            failures: &failures
        )
        let builtInKeyboard = HIDDeviceIdentity(
            vendorID: standardKeyboard.vendorID,
            productID: standardKeyboard.productID,
            product: standardKeyboard.product,
            descriptor: standardKeyboard.descriptor,
            maximumInputReportSize: standardKeyboard.maximumInputReportSize,
            transport: standardKeyboard.transport,
            locationID: standardKeyboard.locationID,
            primaryUsagePage: standardKeyboard.primaryUsagePage,
            primaryUsage: standardKeyboard.primaryUsage,
            isBuiltIn: true
        )
        check(
            !NagaHIDCodecRegistry.summary(for: builtInKeyboard).supportsStandardHID,
            "built-in keyboards must never be offered as general external HID candidates",
            failures: &failures
        )
        let anonymousSystemNode = HIDDeviceIdentity(
            vendorID: -1,
            productID: -1,
            product: "BTM",
            descriptor: standardKeyboard.descriptor,
            maximumInputReportSize: 8,
            transport: "SPMI",
            locationID: 0,
            primaryUsagePage: 0x01,
            primaryUsage: 0x06,
            isBuiltIn: false
        )
        check(
            !NagaHIDCodecRegistry.summary(for: anonymousSystemNode).supportsStandardHID,
            "anonymous macOS system HID nodes must not appear as selectable devices",
            failures: &failures
        )
        var receiverKeyboard = Array(repeating: UInt8(0), count: 15)
        receiverKeyboard[0] = 0x08
        receiverKeyboard[1] = 0x04
        receiverKeyboard[14] = 0x1e
        var receiverPointer = Array(repeating: UInt8(0), count: 9)
        receiverPointer[0] = 0b0010_0100
        receiverPointer[2] = 0xff
        receiverPointer[3] = 1
        check(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 1, bytes: receiverKeyboard) ==
                .keyboard(modifiers: 0x08, usages: [0x04, 0x1e]) &&
                NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 10, bytes: receiverPointer) ==
                .pointer(buttons: 0b0010_0100, horizontalPanDirection: 1) &&
                NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 1, bytes: Array(receiverKeyboard.dropLast())) == nil,
            "receiver keyboard and pointer fixtures must decode with exact lengths and offsets",
            failures: &failures
        )
        check(
            (1...6).map { NagaV2HSReportCodec.payloadLength(for: UInt32($0)) } == [8, 7, 8, 8, 8, 7],
            "known report lengths must remain exact",
            failures: &failures
        )
        check(
            NagaV2HSReportCodec.payloadLength(for: 0) == nil &&
                NagaV2HSReportCodec.payloadLength(for: 7) == nil,
            "unknown report IDs must be rejected",
            failures: &failures
        )
        check(
            NagaV2HSReportCodec.horizontalPanDirection(
                inReport1: [0, 0, 1, 0, 0, 0, 0, 0]
            ) == 1 &&
                NagaV2HSReportCodec.horizontalPanDirection(
                    inReport1: [0, 0, 0xff, 0, 0, 0, 0, 0]
                ) == -1 &&
                NagaV2HSReportCodec.horizontalPanDirection(
                    inReport1: [0, 0, 0, 0, 0, 0, 0, 0]
                ) == nil &&
                NagaV2HSReportCodec.horizontalPanDirection(inReport1: [0, 0, 1]) == nil,
            "Report 1 horizontal pan direction and length must remain exact",
            failures: &failures
        )
        check(
            HIDUsageKeyCodeMap.keyCode(for: 0x1e) == 18 &&
                HIDUsageKeyCodeMap.keyCode(for: 0x04) == 0 &&
                HIDUsageKeyCodeMap.keyCode(for: 0xe3) == 55 &&
                HIDUsageKeyCodeMap.isModifier(0xe3),
            "HID usage conversion must match macOS key codes",
            failures: &failures
        )

        testCorrelationTokensAreOneShot(failures: &failures)
        testRuntimeTokenRouting(failures: &failures)
        testDeviceKeyAndConfiguration(failures: &failures)
        testIDPrefixedReportDecoding(failures: &failures)
        testMultiDeviceRouting(failures: &failures)
        testScrollClassification(failures: &failures)
        testScrollFieldReversal(failures: &failures)
        testScrollSettingsAndActions(failures: &failures)
        testLegacyFixedDPIMigration(failures: &failures)
        testChineseHardwareKeyDefinitions(failures: &failures)
        testMacroCancellation(failures: &failures)
        return failures
    }

    /// Multi-device runtime facts: per-device binding tables stay isolated,
    /// and a correlation token carries its source device key end to end.
    private static func testMultiDeviceRouting(failures: inout [String]) {
        let nagaTable = HIDListener.buildBindingTable(from: [
            "1": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: true
            )
        ])
        let logitechTable = HIDListener.buildBindingTable(from: [
            "2": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: true
            )
        ])
        let signature = HIDUsageSignature(page: 0x07, usage: 0x1e)
        check(
            nagaTable[signature]?.buttonIndex == 1 && logitechTable[signature]?.buttonIndex == 2,
            "identical signatures on different devices must keep separate bindings",
            failures: &failures
        )

        let broker = EventCorrelationBroker.shared
        broker.clear()
        let stamp = mach_absolute_time()
        broker.enqueue(
            kind: .mouse(9),
            pressed: true,
            buttonIndex: 5,
            deviceKey: "046d:c08b",
            hidTimestamp: stamp,
            offsetNs: 0,
            toleranceNs: 8_000_000
        )
        let match = broker.consume(
            kind: .mouse(9),
            pressed: true,
            eventTimestampNs: MonotonicClock.nanoseconds(fromMachAbsolute: stamp)
        )
        broker.clear()
        check(
            match?.buttonIndex == 5 && match?.deviceKey == "046d:c08b",
            "correlation tokens must round-trip their source device key",
            failures: &failures
        )

        var registry = MultiSourceRegistry<String>()
        let first = registry.insert("device-a/button-1", for: 8)
        let second = registry.insert("device-b/button-4", for: 8)
        registry.remove("device-a/button-1", for: 8)
        check(
            first && second && registry.isActive(8) &&
                registry.sourcesByCode[8] == Set(["device-b/button-4"]),
            "one CG code must retain independent mapped sources until each releases",
            failures: &failures
        )
    }

    /// Regression for the Bluetooth Naga crash: transports that keep the
    /// report ID byte in front of the payload must decode identically to the
    /// stripped form instead of trapping on out-of-range slice indices.
    private static func testIDPrefixedReportDecoding(failures: inout [String]) {
        let stripped = NagaHIDCodec.legacyV2HS.decode(
            reportID: 1,
            bytes: [0b0000_0100, 0, 1, 0, 0, 0, 0, 0]
        )
        let prefixed = NagaHIDCodec.legacyV2HS.decode(
            reportID: 1,
            bytes: [1, 0b0000_0100, 0, 1, 0, 0, 0, 0, 0]
        )
        check(
            stripped == .pointer(buttons: 0b0000_0100, horizontalPanDirection: 1) &&
                prefixed == stripped,
            "ID-prefixed pointer report must decode identically, not trap",
            failures: &failures
        )

        let keyboardPrefixed = NagaHIDCodec.legacyV2HS.decode(
            reportID: 6,
            bytes: [6, 0x02, 0x04, 0, 0, 0, 0, 0]
        )
        check(
            keyboardPrefixed == .keyboard(modifiers: 0x02, usages: [0x04]),
            "ID-prefixed keyboard report must decode identically, not trap",
            failures: &failures
        )

        let receiverPrefixed = NagaHIDCodec.v2HyperSpeedReceiver.decode(
            reportID: 10,
            bytes: [10, 0b0000_1000, 0, 0, 0xff, 0, 0, 0, 0, 0]
        )
        check(
            receiverPrefixed == .pointer(buttons: 0b0000_1000, horizontalPanDirection: -1),
            "ID-prefixed receiver pointer report must decode identically",
            failures: &failures
        )
    }

    private static func testDeviceKeyAndConfiguration(failures: inout [String]) {
        // Stable VID:PID device key must ignore port/pairing specifics.
        let identity = HIDDeviceIdentity(
            vendorID: 0x046d, productID: 0xc08b, product: "Logitech G502",
            descriptor: Data([0x05, 0x01]), maximumInputReportSize: 8,
            transport: "USB", locationID: 0x14200000,
            primaryUsagePage: 0x01, primaryUsage: 0x02, isBuiltIn: false
        )
        let summary = NagaHIDCodecRegistry.summary(for: identity)
        check(
            summary.deviceKey == "046d:c08b" && summary.supportsStandardHID && summary.unsupportedReason == nil,
            "standard mouse must expose a stable VID:PID device key",
            failures: &failures
        )

        // Legacy selection identifiers (vid:pid:location:fingerprint) must
        // collapse to the stable device key; malformed values reset to auto.
        check(
            HIDListener.migrateSelectionToDeviceKey("046d:c08b:14200000:0123456789abcdef") == "046d:c08b" &&
                HIDListener.migrateSelectionToDeviceKey("046d:c08b") == "046d:c08b" &&
                HIDListener.migrateSelectionToDeviceKey(nil) == nil &&
                HIDListener.migrateSelectionToDeviceKey("broken") == nil,
            "legacy device selection must migrate to the stable VID:PID key",
            failures: &failures
        )
        check(
            DeviceIdentityPolicy.deviceKey(vendorID: 0x1532, productID: 0x00b4, serialNumber: "RX 01") ==
                "1532:00b4#serial=RX%2001" &&
                DeviceIdentityPolicy.deviceKey(vendorID: 0x1532, productID: 0x00b4, serialNumber: "unknown") ==
                "1532:00b4" &&
                DeviceIdentityPolicy.deviceKey(
                    vendorID: 0x068e, productID: 0x0001, serialNumber: "LEGACY-1",
                    codecIdentifier: NagaHIDCodec.legacyV2HS.rawValue
                ) == "068e:0001#serial=LEGACY-1" &&
                DeviceIdentityPolicy.deviceKey(vendorID: 0x1234, productID: 0x5678, serialNumber: "GENERIC") ==
                "1234:5678",
            "device-family identity rules must enhance only audited families and fall back to VID/PID",
            failures: &failures
        )

        // Unsupported reasons mirror the capability checks.
        let vendorPrivate = HIDDeviceIdentity(
            vendorID: 0x1532, productID: 0x0099, product: "Razer Private Node",
            descriptor: Data(), maximumInputReportSize: 64,
            transport: "USB", locationID: 1,
            primaryUsagePage: 0xff00, primaryUsage: 0x01, isBuiltIn: false
        )
        let nameless = HIDDeviceIdentity(
            vendorID: 0, productID: 0, product: " ",
            descriptor: Data(), maximumInputReportSize: 8,
            transport: "SPI", locationID: 0,
            primaryUsagePage: 0x01, primaryUsage: 0x02, isBuiltIn: false
        )
        check(
            NagaHIDCodecRegistry.summary(for: vendorPrivate).unsupportedReason == .vendorPrivateProtocol &&
                NagaHIDCodecRegistry.summary(for: nameless).unsupportedReason == .invalidIdentity,
            "unsupported candidates must carry a diagnosable reason",
            failures: &failures
        )

        // DeviceConfiguration must round-trip through JSON unchanged.
        let configuration = DeviceConfiguration(
            hardwareMapping: ["1": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1"
            )],
            boundProfile: "游戏",
            displayName: "Razer Naga V2 HyperSpeed",
            customNames: ["1": "施法键", "13": "DPI up"],
            customSectionTitles: ["side": "MMO 键区", "scroll": "滚轮键"]
        )
        if let data = try? JSONEncoder().encode(["1532:00b4": configuration]),
           let decoded = try? JSONDecoder().decode([String: DeviceConfiguration].self, from: data) {
            check(
                decoded["1532:00b4"] == configuration,
                "device configuration must round-trip through JSON",
                failures: &failures
            )
        } else {
            failures.append("device configuration must encode and decode")
        }
        let commandKey = HardwareKey(
            usagePage: 0x07,
            usage: 0x19,
            keyCode: 9,
            displayString: "⌘V",
            interceptEnabled: false,
            modifierFlags: CGEventFlags.maskCommand.rawValue,
            swapCommandControl: true
        )
        let transformed = OnboardKeyTransform.swappingCommandAndControl(key: commandKey)
        let transformedFlags = CGEventFlags(rawValue: transformed?.modifierFlags ?? 0)
        check(
            commandKey.requiresRuntimeInterception &&
                transformed?.keyCode == 9 &&
                transformedFlags.contains(.maskControl) &&
                !transformedFlags.contains(.maskCommand),
            "Command/Control transform must intercept and swap only the requested onboard modifiers",
            failures: &failures
        )
        var mappedCommandKey = commandKey
        mappedCommandKey.interceptEnabled = true
        check(
            OnboardKeyTransform.swappingCommandAndControl(key: mappedCommandKey) == nil,
            "normal Mac mapping interception must take precedence over the onboard modifier transform",
            failures: &failures
        )
        check(
            ConfigManager.zeroProfileRuntimeMapping([
                "1": commandKey,
                "2": mappedCommandKey,
                "invalid": commandKey
            ]) == ["1": commandKey],
            "a zero-profile device must retain only an explicitly enabled device-level modifier transform",
            failures: &failures
        )
        var migration = ["1532:00b4": configuration]
        let enhancedKey = "1532:00b4#serial=RX01"
        check(
            ConfigManager.seedEnhancedIdentityConfiguration(
                &migration,
                enhancedKey: enhancedKey,
                baseKey: "1532:00b4"
            ) && migration[enhancedKey] == configuration && migration["1532:00b4"] == configuration &&
                !ConfigManager.seedEnhancedIdentityConfiguration(
                    &migration,
                    enhancedKey: enhancedKey,
                    baseKey: "1532:00b4"
                ),
            "enhanced identities must copy the VID/PID base configuration exactly once",
            failures: &failures
        )
    }

    private static func testRuntimeTokenRouting(failures: inout [String]) {
        check(
            !HIDListener.shouldCreateRuntimeToken(
                page: 0x07,
                usage: 0x04,
                hasBinding: false,
                bindingIntercepted: false,
                interceptionOverride: nil
            ),
            "an unlearned mouse keyboard source must pass through",
            failures: &failures
        )
        check(
            HIDListener.shouldCreateRuntimeToken(
                page: 0x07,
                usage: 0x04,
                hasBinding: true,
                bindingIntercepted: true,
                interceptionOverride: nil
            ) &&
                !HIDListener.shouldCreateRuntimeToken(
                    page: 0x0c,
                    usage: 0x00e9,
                    hasBinding: true,
                    bindingIntercepted: false,
                    interceptionOverride: nil
                ),
            "normal sources must follow their learned interception switch",
            failures: &failures
        )
        check(
            HIDListener.shouldCreateRuntimeToken(
                page: 0x07,
                usage: 0xe3,
                hasBinding: false,
                bindingIntercepted: false,
                interceptionOverride: true
            ) &&
                !HIDListener.shouldCreateRuntimeToken(
                    page: 0x07,
                    usage: 0xe3,
                    hasBinding: false,
                    bindingIntercepted: false,
                    interceptionOverride: false
                ),
            "mouse chord modifiers must follow only the learned main-key route",
            failures: &failures
        )
    }

    private static func testLegacyFixedDPIMigration(failures: inout [String]) {
        let oldPlus = HardwareKey(
            usagePage: 0x01,
            usage: UInt32.max,
            keyCode: 2000,
            displayString: "系统功能键（未识别定义）"
        )
        let oldMinus = HardwareKey(
            usagePage: 0x01,
            usage: UInt32.max,
            keyCode: 2001,
            displayString: "系统功能键（未识别定义）"
        )
        let realRemappedKey = HardwareKey(
            usagePage: 0x07,
            usage: 0x1e,
            keyCode: 18,
            displayString: "1"
        )
        check(
            ConfigManager.isLegacyFixedDPIDefinition(index: "13", key: oldPlus) &&
                ConfigManager.isLegacyFixedDPIDefinition(index: "14", key: oldMinus),
            "the two exact legacy DPI placeholders must be recognized",
            failures: &failures
        )
        check(
            !ConfigManager.isLegacyFixedDPIDefinition(index: "13", key: realRemappedKey) &&
                !ConfigManager.isLegacyFixedDPIDefinition(index: "1", key: oldPlus),
            "real definitions and non-DPI inputs must survive DPI migration",
            failures: &failures
        )
    }

    private static func testScrollSettingsAndActions(failures: inout [String]) {
        var settings = ScrollSettings.defaults
        settings.step = -1
        settings.speed = 99
        settings.duration = 99
        settings.deadZone = 0
        let validated = settings.validated()
        check(validated.step == 1 && validated.speed == 8 && validated.duration == 5 && validated.deadZone == 0.05,
              "scroll parameters must be clamped to safe ranges", failures: &failures)
        settings.simulateTrackpad = true
        check(settings.validated().duration == 4.75,
              "simulate-trackpad mode must use the Mos-compatible duration", failures: &failures)

        let identifiers = SystemActionDefinition.all.map(\.identifier)
        check(Set(identifiers).count == identifiers.count,
              "predefined system action identifiers must be unique", failures: &failures)
        check(identifiers.allSatisfy { SystemActionDefinition.definition(for: $0) != nil },
              "every predefined system action must be resolvable", failures: &failures)
        check(
            SystemActionDefinition.categories.count == 8 &&
                Set(SystemActionDefinition.all.map(\.category)) == Set(SystemActionDefinition.categories),
            "mac shortcuts must use the Mos groups selected for this editor",
            failures: &failures
        )
        check(
            SystemActionDefinition.definition(for: "screenshotToolbar")?.identifier == "screenshotAndRecording" &&
                SystemActionDefinition.definition(for: "modifierCommand")?.executionMode == .stateful,
            "legacy shortcut aliases and held modifiers must remain safe",
            failures: &failures
        )
        check(
            SystemActionDefinition.all.allSatisfy { !$0.stroke.formattedShortcut().contains("未知键") },
            "mac shortcut labels must not expose unknown key codes",
            failures: &failures
        )
        check(
            SystemActionDefinition.definition(for: "shutdownDialog")?.stroke.keyCode == 127 &&
                SystemActionDefinition.definition(for: "shutdownDialog")?.stroke.modifiers == ["ctrl"] &&
                SystemActionDefinition.definition(for: "previousTab")?.stroke.keyCode == UInt16(kVK_Tab) &&
                SystemActionDefinition.definition(for: "previousTab")?.stroke.modifiers == ["ctrl", "shift"] &&
                SystemActionDefinition.definition(for: "nextTab")?.stroke.keyCode == UInt16(kVK_Tab) &&
                SystemActionDefinition.definition(for: "nextTab")?.stroke.modifiers == ["ctrl"],
            "power dialog and tab navigation shortcuts must use their actual macOS key strokes",
            failures: &failures
        )
        check(
            CalibrationTiming.timeoutSeconds == 20 &&
                CalibrationTiming.remainingSeconds(deadline: 120, now: 100) == 20 &&
                CalibrationTiming.remainingSeconds(deadline: 120, now: 119.1) == 1 &&
                CalibrationTiming.remainingSeconds(deadline: 120, now: 121) == 0,
            "hardware learning must expose an exact twenty-second countdown",
            failures: &failures
        )
        // Device-first primary screen: sidebar chrome, device header,
        // profile actions and the autosave indicator replace the retired
        // profile dropdown / save button / alias controls.
        let localizationSmokeKeys = mainScreenLocalizationKeys + [
            "按键映射", "拦截板载键值",
            "mac快捷键", "读取板载键值...", "滚轮设置",
            "✓ 更改已自动保存", "+ 添加配置", "在此设备启用", "设备详情...",
            "设备", "原始设备名", "序列号",
            "苹果毛玻璃", "黑夜", "原始黑色", "帮助中心", "拷贝",
            "请先设置 Mac 自定义键值，再开启拦截板载键值。",
            "+ 新建自定义分组", "读取新输入", "自定义键%d",
            "⌘ ⇄ Control", "将此板载快捷键中的 ⌘ 与 Control 互换",
            "普通映射拦截已开启，当前由 Mac 动作接管；关闭拦截后互换生效",
            "板载键值：%@ · ⌘/Control 已互换", "⚠ 更改未保存"
        ]
        check(
            AppLanguage.allCases.count == 5 && ThemeMode.allCases.count == 3 && AppLanguage.allCases.allSatisfy { language in
                L10n.hasCompleteTranslation(for: language) &&
                    localizationSmokeKeys.allSatisfy { L10n.hasTranslation($0, for: language) }
            },
            "all five languages and three themes must cover every primary screen",
            failures: &failures
        )
        let helpFailures = helpContentValidationFailures()
        check(
            helpFailures.isEmpty,
            "all five languages must provide the complete help-center catalog: \(helpFailures.joined(separator: "; "))",
            failures: &failures
        )

        let legacy = #"{"type":"keySequence","keys":[{"key":"c","modifiers":["cmd"],"keyCode":8}]}"#.data(using: .utf8)!
        check((try? JSONDecoder().decode(ButtonAction.self, from: legacy)) != nil,
              "legacy profiles must decode without new action fields", failures: &failures)

        let partialScroll = #"{"enabled":true,"reverse":false}"#.data(using: .utf8)!
        if let decoded = try? JSONDecoder().decode(ScrollSettings.self, from: partialScroll) {
            check(decoded.enabled && !decoded.reverse && decoded.step == ScrollSettings.defaults.step,
                  "partial scroll settings must inherit safe defaults", failures: &failures)
            check(decoded.dashHotkey == ScrollSettings.defaults.dashHotkey,
                  "missing scroll hotkeys must inherit defaults", failures: &failures)
        } else {
            failures.append("partial scroll settings must remain decodable")
        }

        let legacyHardware = #"{"usagePage":7,"usage":30,"keyCode":18,"displayString":"1"}"#.data(using: .utf8)!
        if let decoded = try? JSONDecoder().decode(HardwareKey.self, from: legacyHardware) {
            check(decoded.valueDirection == nil && decoded.eventDirection == nil,
                  "legacy hardware definitions must decode without wheel directions", failures: &failures)
        } else {
            failures.append("legacy hardware definitions must remain decodable")
        }
    }

    private static func testChineseHardwareKeyDefinitions(failures: inout [String]) {
        L10n.withTemporaryLanguage(.chineseSimplified) {
            check(
                HardwareKeyDisplay.keyboard(
                    keyCode: 8,
                    modifierFlags: CGEventFlags.maskCommand.rawValue
                ) == "⌘C（复制）",
                "Command-C must include its Chinese definition",
                failures: &failures
            )
            check(
                HardwareKeyDisplay.keyboard(keyCode: 51, modifierFlags: 0) == "Delete（删除）",
                "Delete must include its Chinese definition",
                failures: &failures
            )
            check(
                HardwareKeyDisplay.keyboard(keyCode: 36, modifierFlags: 0) == "Return（回车）",
                "Return must include its Chinese definition",
                failures: &failures
            )
            check(
                HardwareKeyDisplay.system(usagePage: 0x0c, usage: 0x00e9) == "Volume Up（提高音量）",
                "consumer keys must include its Chinese definition",
                failures: &failures
            )
            check(
                KeyStroke(key: "v", modifiers: ["cmd"], keyCode: 9).formattedShortcut() == "⌘V（粘贴）",
                "configured shortcut descriptions must include their Chinese definition",
                failures: &failures
            )
        }
    }

    private static func testMacroCancellation(failures: inout [String]) {
        ButtonMapper.shared.runMacro([
            MacroStep(type: "delay", keyStroke: nil, text: nil, delayMs: 10_000)
        ])
        usleep(50_000)
        let started = CFAbsoluteTimeGetCurrent()
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: "self-test cancellation", wait: true)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        check(elapsed < 0.5, "macro cancellation must unblock release within 500 ms", failures: &failures)
    }

    private static func testCorrelationTokensAreOneShot(failures: inout [String]) {
        let broker = EventCorrelationBroker.shared
        broker.clear()
        let hidTimestamp = mach_absolute_time()
        let eventTimestamp = MonotonicClock.nanoseconds(fromMachAbsolute: hidTimestamp)
        broker.enqueue(
            kind: .keyboard(18),
            pressed: true,
            buttonIndex: 1,
            hidTimestamp: hidTimestamp,
            offsetNs: 0,
            toleranceNs: 1_000_000
        )
        check(
            broker.consume(kind: .keyboard(18), pressed: false, eventTimestampNs: eventTimestamp) == nil,
            "opposite phase must not consume a HID token",
            failures: &failures
        )
        check(
            broker.consume(kind: .keyboard(18), pressed: true, eventTimestampNs: eventTimestamp)?.buttonIndex == 1,
            "matching HID token must identify its button",
            failures: &failures
        )
        check(
            broker.consume(kind: .keyboard(18), pressed: true, eventTimestampNs: eventTimestamp) == nil,
            "a HID token must be consumable only once",
            failures: &failures
        )

        broker.enqueue(
            kind: .keyboard(18),
            pressed: true,
            buttonIndex: 1,
            hidTimestamp: hidTimestamp,
            offsetNs: 0,
            toleranceNs: 1_000_000
        )
        check(
            broker.consume(kind: .keyboard(18), pressed: true, eventTimestampNs: eventTimestamp + 5_000_000) == nil,
            "an out-of-window keyboard event must not be intercepted",
            failures: &failures
        )

        broker.enqueue(
            kind: .horizontalScroll(1),
            pressed: true,
            buttonIndex: 15,
            hidTimestamp: hidTimestamp,
            offsetNs: 0,
            toleranceNs: 1_000_000
        )
        check(
            broker.consume(kind: .horizontalScroll(-1), pressed: true, eventTimestampNs: eventTimestamp) == nil,
            "opposite wheel-tilt direction must not consume a token",
            failures: &failures
        )
        check(
            broker.consume(kind: .horizontalScroll(1), pressed: true, eventTimestampNs: eventTimestamp)?.buttonIndex == 15,
            "matching wheel-tilt token must identify its input",
            failures: &failures
        )
        check(
            InputSourceCatalog.supportedIndices == 1...16 &&
                InputSourceCatalog.compactLabel(for: 15) == "W←" &&
                InputSourceCatalog.compactLabel(for: 16) == "W→" &&
                !InputSourceCatalog.name(for: 15).isEmpty &&
                !InputSourceCatalog.name(for: 16).isEmpty,
            "the unified input catalog must expose all sixteen sources",
            failures: &failures
        )
        broker.clear()
    }

    private static func testScrollClassification(failures: inout [String]) {
        check(
            !ScrollEventCharacteristics(
                isContinuous: false,
                scrollPhase: 0,
                momentumPhase: 0,
                scrollCount: 0
            ).isTrackpadLike,
            "a discrete physical wheel event must be reversible",
            failures: &failures
        )
        check(
            !ScrollEventCharacteristics(
                isContinuous: true,
                scrollPhase: 0,
                momentumPhase: 0,
                scrollCount: 0
            ).isTrackpadLike,
            "a Naga wheel tick marked continuous must still be reversible",
            failures: &failures
        )
        check(
            ScrollEventCharacteristics(
                isContinuous: false,
                scrollPhase: 1,
                momentumPhase: 0,
                scrollCount: 0
            ).isTrackpadLike,
            "phase-based gesture input must not be reversed",
            failures: &failures
        )
    }

    private static func testScrollFieldReversal(failures: inout [String]) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 3,
            wheel2: 0,
            wheel3: 0
        ) else {
            failures.append("unable to create a scroll event for reversal testing")
            return
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 7.5)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 2.25)
        let originalInteger = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let originalPoint = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let originalFixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        ScrollReversalManager.reverse(axis: 1, event: event)
        check(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -originalInteger &&
                event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == -originalPoint &&
                event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -originalFixed,
            "scroll reversal must invert integer, point and fixed-point fields",
            failures: &failures
        )

        let reversedInteger = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let reversedPoint = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let reversedFixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        ScrollReversalManager.moveVerticalDeltaToHorizontal(event)
        check(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0 &&
                event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == 0 &&
                event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 0 &&
                event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == reversedInteger &&
                event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) == reversedPoint &&
                event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == reversedFixed,
            "shift-axis conversion must preserve all delta representations",
            failures: &failures
        )
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append(message) }
    }
}
