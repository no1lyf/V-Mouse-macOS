import XCTest
import Carbon.HIToolbox
@testable import NagaController

final class NagaV2HSReportCodecTests: XCTestCase {
    func testExactDescriptorIsSupported() {
        XCTAssertTrue(NagaV2HSReportCodec.supports(
            vendorID: 0x068e,
            product: "Naga V2 HS",
            descriptor: NagaV2HSReportCodec.physicalReportDescriptor,
            maximumReportSize: 9
        ))
        XCTAssertFalse(NagaV2HSReportCodec.supports(
            vendorID: 0x1532,
            product: "Naga V2 HS",
            descriptor: NagaV2HSReportCodec.physicalReportDescriptor,
            maximumReportSize: 9
        ))
    }

    func testKnownReportLengthsAreExact() {
        XCTAssertEqual(
            (1...6).map { NagaV2HSReportCodec.payloadLength(for: UInt32($0)) },
            [8, 7, 8, 8, 8, 7]
        )
        XCTAssertNil(NagaV2HSReportCodec.payloadLength(for: 0))
        XCTAssertNil(NagaV2HSReportCodec.payloadLength(for: 7))
    }

    func testReport1HorizontalPanDirection() {
        XCTAssertEqual(NagaV2HSReportCodec.horizontalPanDirection(
            inReport1: [0, 0, 1, 0, 0, 0, 0, 0]
        ), 1)
        XCTAssertEqual(NagaV2HSReportCodec.horizontalPanDirection(
            inReport1: [0, 0, 0xff, 0, 0, 0, 0, 0]
        ), -1)
        XCTAssertNil(NagaV2HSReportCodec.horizontalPanDirection(
            inReport1: [0, 0, 0, 0, 0, 0, 0, 0]
        ))
        XCTAssertNil(NagaV2HSReportCodec.horizontalPanDirection(inReport1: [0, 0, 1]))
    }

    func testReceiverCompositeFingerprintIsSupportedAndUnknownFailsClosed() {
        let receiver = HIDDeviceIdentity(
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
        XCTAssertEqual(NagaHIDCodecRegistry.codec(for: receiver), .v2HyperSpeedReceiver)
        XCTAssertTrue(NagaHIDCodecRegistry.summary(for: receiver).isSupported)

        let unknown = HIDDeviceIdentity(
            vendorID: receiver.vendorID,
            productID: receiver.productID,
            product: receiver.product,
            descriptor: Data([0x05, 0x01, 0x09, 0x02]),
            maximumInputReportSize: 16,
            transport: receiver.transport,
            locationID: receiver.locationID,
            primaryUsagePage: 1,
            primaryUsage: 2,
            isBuiltIn: false
        )
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: unknown))
        XCTAssertTrue(NagaHIDCodecRegistry.summary(for: unknown).supportsStandardHID)
        XCTAssertTrue(NagaHIDCodecRegistry.summary(for: unknown).isSupported)
    }

    func testReceiverCodecRequiresEveryAuditedIdentityField() {
        let descriptor = NagaHIDCodecRegistry.v2HyperSpeedReceiverCompositeDescriptor
        func identity(
            vendorID: Int = 0x1532,
            productID: Int = 0x00b4,
            descriptor: Data = NagaHIDCodecRegistry.v2HyperSpeedReceiverCompositeDescriptor,
            maximumInputReportSize: Int = 16
        ) -> HIDDeviceIdentity {
            HIDDeviceIdentity(
                vendorID: vendorID, productID: productID,
                product: "Razer Naga V2 HyperSpeed", descriptor: descriptor,
                maximumInputReportSize: maximumInputReportSize,
                transport: "USB", locationID: 0x01143300,
                primaryUsagePage: 1, primaryUsage: 6, isBuiltIn: false
            )
        }

        XCTAssertEqual(NagaHIDCodecRegistry.codec(for: identity()), .v2HyperSpeedReceiver)
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: identity(vendorID: 0x068e)))
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: identity(productID: 0x00b5)))
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: identity(maximumInputReportSize: 15)))

        var corrupted = descriptor
        corrupted[corrupted.startIndex] ^= 0xff
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: identity(descriptor: corrupted)))
        XCTAssertNotEqual(
            NagaHIDCodecRegistry.descriptorFingerprint(descriptor),
            NagaHIDCodecRegistry.descriptorFingerprint(corrupted)
        )
    }

    func testFamilyScopedEnhancedDeviceIdentityFallsBackSafely() {
        XCTAssertEqual(
            DeviceIdentityPolicy.deviceKey(vendorID: 0x1532, productID: 0x00b4, serialNumber: "RX 01"),
            "1532:00b4#serial=RX%2001"
        )
        XCTAssertEqual(
            DeviceIdentityPolicy.deviceKey(vendorID: 0x1532, productID: 0x00b4, serialNumber: "unknown"),
            "1532:00b4"
        )
        XCTAssertEqual(
            DeviceIdentityPolicy.deviceKey(
                vendorID: 0x068e, productID: 0x0001, serialNumber: "LEGACY-1",
                codecIdentifier: NagaHIDCodec.legacyV2HS.rawValue
            ),
            "068e:0001#serial=LEGACY-1"
        )
        XCTAssertEqual(
            DeviceIdentityPolicy.deviceKey(vendorID: 0x1234, productID: 0x5678, serialNumber: "GENERIC"),
            "1234:5678"
        )
        XCTAssertEqual(DeviceIdentityPolicy.baseKey(from: "1532:00b4#serial=RX01"), "1532:00b4")
    }

    func testEnhancedIdentityRequiresEverySelectedCondition() {
        let facts = DeviceIdentityObservedFacts(
            vendorID: 0x1234, productID: 0x5678,
            productName: "Strict Mouse", serialNumber: "UNIT-1",
            descriptorFingerprint: "ABCDEF", maximumInputReportSize: 16,
            primaryUsagePage: 1, primaryUsage: 2, transport: "USB",
            codecIdentifier: nil
        )
        let matching = DeviceIdentityRule(
            baseKey: "1234:5678", enhancedRecognitionEnabled: true,
            conditions: [
                DeviceIdentityCondition(field: .productName, expectedValue: "Strict Mouse"),
                DeviceIdentityCondition(field: .descriptorFingerprint, expectedValue: "abcdef"),
                DeviceIdentityCondition(field: .maximumInputReportSize, expectedValue: "16")
            ],
            discriminatorFields: [.serialNumber]
        )
        XCTAssertEqual(matching.totalConditionCount, 5)
        XCTAssertEqual(
            DeviceIdentityRuleEvaluator.deviceKey(facts: facts, rule: matching),
            "1234:5678#serial=UNIT-1"
        )
        var oneMismatch = matching
        oneMismatch.conditions[2].expectedValue = "15"
        XCTAssertEqual(DeviceIdentityRuleEvaluator.deviceKey(facts: facts, rule: oneMismatch), "1234:5678")
        var missingRequiredValue = matching
        missingRequiredValue.discriminatorFields = [.serialNumber, .transport]
        var missingFacts = facts
        missingFacts.transport = ""
        XCTAssertEqual(
            DeviceIdentityRuleEvaluator.deviceKey(facts: missingFacts, rule: missingRequiredValue),
            "1234:5678"
        )
    }

    func testVendorPrivateUnknownDeviceFailsClosed() {
        let unknown = HIDDeviceIdentity(
            vendorID: 0x9999,
            productID: 1,
            product: "Private protocol",
            descriptor: Data([0x06, 0x00, 0xff]),
            maximumInputReportSize: 64,
            transport: "USB",
            locationID: 7,
            primaryUsagePage: 0xff00,
            primaryUsage: 1,
            isBuiltIn: false
        )
        let summary = NagaHIDCodecRegistry.summary(for: unknown)
        XCTAssertNil(NagaHIDCodecRegistry.codec(for: unknown))
        XCTAssertFalse(summary.supportsStandardHID)
        XCTAssertFalse(summary.isSupported)
    }

    func testReceiverKeyboardReportOneDecodesFourteenKeySlots() {
        var payload = Array(repeating: UInt8(0), count: 15)
        payload[0] = 0x08
        payload[1] = 0x04
        payload[14] = 0x1e
        XCTAssertEqual(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 1, bytes: payload),
            .keyboard(modifiers: 0x08, usages: [0x04, 0x1e])
        )
        XCTAssertEqual(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 1, bytes: [1] + payload),
            .keyboard(modifiers: 0x08, usages: [0x04, 0x1e])
        )
        XCTAssertNil(NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 1, bytes: Array(payload.dropLast())))
    }

    func testReceiverMouseReportTenUsesReceiverPanOffset() {
        var payload = Array(repeating: UInt8(0), count: 9)
        payload[0] = 0b0010_0100
        payload[2] = 0xff // Vendor byte must not be interpreted as AC Pan.
        payload[3] = 1
        XCTAssertEqual(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 10, bytes: payload),
            .pointer(buttons: 0b0010_0100, horizontalPanDirection: 1)
        )
        XCTAssertNil(NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 6, bytes: payload))
    }

    func testReceiverConsumerAndSystemFixturesDecodeExactly() {
        var consumer = Array(repeating: UInt8(0), count: 15)
        consumer[0] = 0x34
        consumer[1] = 0x02
        XCTAssertEqual(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 2, bytes: consumer),
            .consumer(usage: 0x0234)
        )

        var system = Array(repeating: UInt8(0), count: 15)
        system[0] = 0b0000_0101
        XCTAssertEqual(
            NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 3, bytes: [3] + system),
            .system(usages: [0x81, 0x83])
        )
        XCTAssertNil(NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 2, bytes: consumer + [0]))
        XCTAssertNil(NagaHIDCodec.v2HyperSpeedReceiver.decode(reportID: 3, bytes: []))
    }

    func testCommonKeyboardUsageConversion() {
        XCTAssertEqual(HIDUsageKeyCodeMap.keyCode(for: 0x04), 0)
        XCTAssertEqual(HIDUsageKeyCodeMap.keyCode(for: 0x1e), 18)
        XCTAssertEqual(HIDUsageKeyCodeMap.keyCode(for: 0xe3), 55)
        XCTAssertTrue(HIDUsageKeyCodeMap.isModifier(0xe3))
        XCTAssertFalse(HIDUsageKeyCodeMap.isModifier(0x1e))
    }

    func testUnifiedInputCatalogIncludesWheelTilt() {
        L10n.withTemporaryLanguage(.chineseSimplified) {
            XCTAssertEqual(InputSourceCatalog.supportedIndices, 1...16)
            XCTAssertEqual(InputSourceCatalog.name(for: 13), "DPI+")
            XCTAssertEqual(InputSourceCatalog.name(for: 14), "DPI−")
            XCTAssertEqual(InputSourceCatalog.name(for: 15), "滚轮左键")
            XCTAssertEqual(InputSourceCatalog.name(for: 16), "滚轮右键")
        }
    }

    func testLegacyFixedDPIPlaceholderRecognitionIsExact() {
        let placeholder = HardwareKey(
            usagePage: 0x01,
            usage: UInt32.max,
            keyCode: 2000,
            displayString: "legacy"
        )
        let realKey = HardwareKey(
            usagePage: 0x07,
            usage: 0x1e,
            keyCode: 18,
            displayString: "1"
        )
        XCTAssertTrue(ConfigManager.isLegacyFixedDPIDefinition(index: "13", key: placeholder))
        XCTAssertFalse(ConfigManager.isLegacyFixedDPIDefinition(index: "14", key: placeholder))
        XCTAssertFalse(ConfigManager.isLegacyFixedDPIDefinition(index: "13", key: realKey))
    }

    func testRuntimeTokensRequireLearnedInterceptedSource() {
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07,
            usage: 0x04,
            hasBinding: false,
            bindingIntercepted: false,
            interceptionOverride: nil
        ))
        XCTAssertTrue(HIDListener.shouldCreateRuntimeToken(
            page: 0x07,
            usage: 0x04,
            hasBinding: true,
            bindingIntercepted: true,
            interceptionOverride: nil
        ))
        XCTAssertTrue(HIDListener.shouldCreateRuntimeToken(
            page: 0x07,
            usage: 0xe3,
            hasBinding: false,
            bindingIntercepted: false,
            interceptionOverride: true
        ))
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07,
            usage: 0xe3,
            hasBinding: false,
            bindingIntercepted: false,
            interceptionOverride: false
        ))
    }

    func testLegacyHardwareKeyDecodesWithoutDirectionalFields() throws {
        let data = #"{"usagePage":7,"usage":30,"keyCode":18,"displayString":"1"}"#.data(using: .utf8)!
        let key = try JSONDecoder().decode(HardwareKey.self, from: data)
        XCTAssertNil(key.valueDirection)
        XCTAssertNil(key.eventDirection)
    }

    func testNagaContinuousWheelIsNotMisclassifiedAsTrackpad() {
        XCTAssertFalse(ScrollEventCharacteristics(
            isContinuous: true, scrollPhase: 0, momentumPhase: 0, scrollCount: 1
        ).isTrackpadLike)
        XCTAssertTrue(ScrollEventCharacteristics(
            isContinuous: false, scrollPhase: 1, momentumPhase: 0, scrollCount: 0
        ).isTrackpadLike)
    }

    func testScrollSettingsValidationAndMosDuration() {
        var settings = ScrollSettings.defaults
        settings.step = -1
        settings.speed = 99
        settings.duration = 99
        settings.deadZone = 0
        let validated = settings.validated()
        XCTAssertEqual(validated.step, 1)
        XCTAssertEqual(validated.speed, 8)
        XCTAssertEqual(validated.duration, 5)
        XCTAssertEqual(validated.deadZone, 0.05)
        XCTAssertGreaterThan(validated.durationTransition, 0)

        settings.simulateTrackpad = true
        XCTAssertEqual(settings.validated().duration, 4.75)
    }

    func testSystemActionCatalogIdentifiersAreUniqueAndResolvable() {
        let identifiers = SystemActionDefinition.all.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        for identifier in identifiers {
            XCTAssertNotNil(SystemActionDefinition.definition(for: identifier))
        }
    }

    func testMacShortcutGroupsAliasesAndHeldModifiers() {
        XCTAssertEqual(SystemActionDefinition.categories.count, 8)
        XCTAssertEqual(Set(SystemActionDefinition.all.map(\.category)), Set(SystemActionDefinition.categories))
        XCTAssertEqual(
            SystemActionDefinition.definition(for: "screenshotToolbar")?.identifier,
            "screenshotAndRecording"
        )
        XCTAssertEqual(
            SystemActionDefinition.definition(for: "modifierCommand")?.executionMode,
            .stateful
        )
        XCTAssertTrue(
            SystemActionDefinition.all.allSatisfy { !$0.stroke.formattedShortcut().contains("未知键") }
        )
        XCTAssertEqual(SystemActionDefinition.definition(for: "shutdownDialog")?.stroke.keyCode, 127)
        XCTAssertEqual(SystemActionDefinition.definition(for: "shutdownDialog")?.stroke.modifiers, ["ctrl"])
        XCTAssertEqual(SystemActionDefinition.definition(for: "previousTab")?.stroke.keyCode, UInt16(kVK_Tab))
        XCTAssertEqual(SystemActionDefinition.definition(for: "previousTab")?.stroke.modifiers, ["ctrl", "shift"])
        XCTAssertEqual(SystemActionDefinition.definition(for: "nextTab")?.stroke.keyCode, UInt16(kVK_Tab))
        XCTAssertEqual(SystemActionDefinition.definition(for: "nextTab")?.stroke.modifiers, ["ctrl"])
    }

    func testCalibrationCountdownIsTwentySecondsAndClamped() {
        XCTAssertEqual(CalibrationTiming.timeoutSeconds, 20)
        XCTAssertEqual(CalibrationTiming.remainingSeconds(deadline: 120, now: 100), 20)
        XCTAssertEqual(CalibrationTiming.remainingSeconds(deadline: 120, now: 119.1), 1)
        XCTAssertEqual(CalibrationTiming.remainingSeconds(deadline: 120, now: 121), 0)
    }

    func testFiveLanguagesCoverPrimaryScreens() {
        let keys = [
            "语言", "按键映射", "启用按键自定义", "帮助中心...",
            "未连接", "跟随系统", "浅色", "暗色", "输入设备", "自动选择",
            "仅诊断，不支持", "V-Mouse鼠标映射 版本 %@，构建 %@",
            "mac快捷键", "读取当前鼠标按键定义", "滚轮设置", "保存"
        ]
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        for language in AppLanguage.allCases {
            XCTAssertTrue(keys.allSatisfy { L10n.hasTranslation($0, for: language) })
        }
    }

    func testFiveLanguageHelpContentUsesOneSchema() {
        XCTAssertEqual(helpContentValidationFailures(), [])
    }

    func testFiveLanguagesCoverEveryMainScreenLocalizationKey() {
        XCTAssertEqual(mainScreenLocalizationKeys.count, 36)
        for language in AppLanguage.allCases {
            for key in mainScreenLocalizationKeys {
                XCTAssertTrue(
                    L10n.hasTranslation(key, for: language),
                    "Missing main-screen translation for \(language.rawValue): \(key)"
                )
            }
        }
    }

    func testOnboardCommandControlSwapIsBackwardCompatibleAndDeterministic() throws {
        let legacy = try JSONDecoder().decode(
            HardwareKey.self,
            from: #"{"usagePage":7,"usage":25,"keyCode":9,"displayString":"⌘V","modifierFlags":1048576,"interceptEnabled":false}"#.data(using: .utf8)!
        )
        XCTAssertFalse(legacy.isCommandControlSwapEnabled)
        var configured = legacy
        configured.swapCommandControl = true
        let transformed = try XCTUnwrap(OnboardKeyTransform.swappingCommandAndControl(key: configured))
        let flags = CGEventFlags(rawValue: transformed.modifierFlags)
        XCTAssertTrue(flags.contains(.maskControl))
        XCTAssertFalse(flags.contains(.maskCommand))
        XCTAssertEqual(transformed.keyCode, 9)
    }

    func testHelpCenterSchemaParityAcrossFiveLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        XCTAssertEqual(helpContentValidationFailures(), [])
    }

    func testLegacyButtonActionStillDecodesWithoutNewFields() throws {
        let data = #"{"type":"keySequence","keys":[{"key":"c","modifiers":["cmd"],"keyCode":8}],"description":"复制"}"#.data(using: .utf8)!
        let action = try JSONDecoder().decode(ButtonAction.self, from: data)
        XCTAssertEqual(action.type, "keySequence")
        XCTAssertNil(action.systemAction)
        XCTAssertNil(action.target)
        XCTAssertNil(action.scrollControl)
    }
}
