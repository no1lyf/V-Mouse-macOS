import XCTest
@testable import NagaController

final class InputGroupMigrationTests: XCTestCase {
    func testLegacyFixedSectionsAndCustomSourcesMigrateWithoutLoss() throws {
        var legacy = DeviceConfiguration()
        legacy.customSourceIndices = [17, 19]
        legacy.removedStandardIndices = [4]
        legacy.customSectionTitles = ["side": "MMO 键区"]

        let migrated = ConfigManager.configurationByMigratingInputGroups(legacy)
        let groups = try XCTUnwrap(migrated.inputGroups)

        XCTAssertEqual(groups.first(where: { $0.id == DeviceInputGroup.sideID })?.sourceIndices,
                       [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(groups.first(where: { $0.id == DeviceInputGroup.sideID })?.title, "MMO 键区")
        XCTAssertEqual(groups.first(where: { !$0.isBuiltIn })?.sourceIndices, [17, 19])
        XCTAssertEqual(migrated.nextCustomSourceOrdinal, 4)
        XCTAssertEqual(try JSONDecoder().decode(DeviceConfiguration.self, from: JSONEncoder().encode(migrated)), migrated)
    }

    func testNormalizationAssignsEveryPresentSourceExactlyOnce() {
        var configuration = DeviceConfiguration()
        configuration.customSourceIndices = [17, 18]
        configuration.inputGroups = [
            DeviceInputGroup(id: DeviceInputGroup.sideID, title: nil, sourceIndices: [1, 2, 17]),
            DeviceInputGroup(id: "gaming", title: "游戏", sourceIndices: [17, 18, 18])
        ]

        let groups = ConfigManager.normalizedInputGroups(for: configuration)
        let flattened = groups.flatMap(\.sourceIndices)

        XCTAssertEqual(flattened.count, Set(flattened).count)
        XCTAssertEqual(Set(flattened), Set(Array(1...18)))
        XCTAssertEqual(
            groups.first(where: { $0.id == DeviceInputGroup.sideID })?.sourceIndices,
            Array(1...12) + [17]
        )
        XCTAssertEqual(groups.first(where: { $0.id == "gaming" })?.sourceIndices, [18])
    }

    func testCustomDefaultNameUsesOneBasedCustomKeySequence() {
        let value = L10n.withTemporaryLanguage(.chineseSimplified) {
            InputSourceCatalog.name(for: 17)
        }
        XCTAssertEqual(value, "自定义键1")
    }

    func testBuiltInAndCustomGroupsPreserveOneSharedOrder() throws {
        var configuration = ConfigManager.configurationByMigratingInputGroups(DeviceConfiguration())
        let groups = try XCTUnwrap(configuration.inputGroups)
        configuration.inputGroups = [groups[2], groups[0], groups[1]]

        XCTAssertEqual(
            ConfigManager.configurationByMigratingInputGroups(configuration).inputGroups?.map(\.id),
            [DeviceInputGroup.scrollID, DeviceInputGroup.sideID, DeviceInputGroup.dpiID]
        )
    }

    func testDeletedBuiltInGroupIsNotRecreatedByNormalization() throws {
        var configuration = ConfigManager.configurationByMigratingInputGroups(DeviceConfiguration())
        var groups = try XCTUnwrap(configuration.inputGroups)
        let dpi = try XCTUnwrap(groups.first(where: { $0.id == DeviceInputGroup.dpiID }))
        let sidePosition = try XCTUnwrap(groups.firstIndex(where: { $0.id == DeviceInputGroup.sideID }))
        groups[sidePosition].sourceIndices.append(contentsOf: dpi.sourceIndices)
        groups.removeAll { $0.id == DeviceInputGroup.dpiID }
        configuration.inputGroups = groups

        let normalized = ConfigManager.normalizedInputGroups(for: configuration)

        XCTAssertFalse(normalized.contains(where: { $0.id == DeviceInputGroup.dpiID }))
        XCTAssertEqual(Set(normalized.flatMap(\.sourceIndices)), Set(1...16))
    }

    func testDuplicateSignalsBecomeDeterministicAliases() throws {
        var configuration = DeviceConfiguration()
        configuration.hardwareMapping = [
            "17": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: false
            ),
            "2": HardwareKey(
                usagePage: 0x07, usage: 0x1e, keyCode: 18, displayString: "1",
                groupId: nil, interceptEnabled: true
            )
        ]

        ConfigManager.normalizeSignalAliases(in: &configuration)

        let alias = try XCTUnwrap(configuration.signalAliasGroups?.first)
        XCTAssertEqual(alias.canonicalSourceIndex, 2)
        XCTAssertEqual(alias.memberSourceIndices, [2, 17])
        XCTAssertTrue(try XCTUnwrap(configuration.hardwareMapping?["2"]?.isIntercepted))
        XCTAssertTrue(try XCTUnwrap(configuration.hardwareMapping?["17"]?.isIntercepted))
        XCTAssertEqual(
            HIDListener.buildBindingTable(from: configuration.hardwareMapping ?? [:])[
                HIDUsageSignature(page: 0x07, usage: 0x1e)
            ]?.buttonIndex,
            2
        )
        XCTAssertEqual(
            try JSONDecoder().decode(DeviceConfiguration.self, from: JSONEncoder().encode(configuration)),
            configuration
        )

        configuration.hardwareMapping?.removeValue(forKey: "2")
        ConfigManager.normalizeSignalAliases(in: &configuration)
        let runtime = ConfigManager.runtimeAliasResolvedMapping(
            configuration.hardwareMapping ?? [:],
            groups: configuration.signalAliasGroups ?? []
        )
        XCTAssertEqual(configuration.signalAliasGroups?.first?.canonicalSourceIndex, 2)
        XCTAssertEqual(configuration.signalAliasGroups?.first?.memberSourceIndices, [17])
        XCTAssertEqual(
            HIDListener.buildBindingTable(from: runtime)[HIDUsageSignature(page: 0x07, usage: 0x1e)]?.buttonIndex,
            2
        )
    }
}
