import XCTest
@testable import NagaController

/// Scenarios for the one-shot device-first migration: the legacy rule
/// (boundProfile ?? global current ?? fallback) must fold into per-device
/// active profiles, and alias pairs must split into independent devices that
/// share their profiles.
final class DeviceFirstMigrationTests: XCTestCase {
    func testIdentityRuleMigrationRejectsConflictAndCanResolveExplicitly() throws {
        var base = DeviceConfiguration()
        base.customDisplayName = "Base"
        var instance = DeviceConfiguration()
        instance.customDisplayName = "Instance"
        let configurations = [
            "1234:5678": base,
            "1234:5678#serial=ONE": instance
        ]

        XCTAssertThrowsError(try ConfigManager.migratedIdentityConfigurations(
            configurations,
            moves: [("1234:5678#serial=ONE", "1234:5678")]
        ))
        let resolved = try ConfigManager.migratedIdentityConfigurations(
            configurations,
            moves: [("1234:5678#serial=ONE", "1234:5678")],
            conflictResolution: .keepSource
        )
        XCTAssertEqual(resolved["1234:5678"], instance)
        XCTAssertNil(resolved["1234:5678#serial=ONE"])
    }


    private let existing: Set<String> = ["Default", "游戏", "办公"]

    func testRemovingLastMountedProfileCreatesExplicitZeroProfileState() {
        var config = DeviceConfiguration()
        config.boundProfile = "Default"
        config.profileRefs = ["Default"]
        config.activeProfile = "Default"

        let result = ConfigManager.configurationByRemovingProfile(
            "Default",
            from: config,
            profileExists: { self.existing.contains($0) }
        )

        XCTAssertEqual(result.profileRefs, [])
        XCTAssertNil(result.activeProfile)
        XCTAssertNil(result.boundProfile)
        XCTAssertNil(ConfigManager.resolvedProfileName(
            for: result,
            profileExists: { self.existing.contains($0) },
            fallbackProfile: "Default"
        ))
    }

    func testRemovingActiveProfileActivatesNextMountedProfile() {
        var config = DeviceConfiguration()
        config.profileRefs = ["游戏", "办公"]
        config.activeProfile = "游戏"
        let result = ConfigManager.configurationByRemovingProfile(
            "游戏",
            from: config,
            profileExists: { self.existing.contains($0) }
        )
        XCTAssertEqual(result.profileRefs, ["办公"])
        XCTAssertEqual(result.activeProfile, "办公")
    }

    private func migrate(
        _ input: [String: DeviceConfiguration],
        aliases: [String: String] = [:],
        legacyCurrent: String? = "Default"
    ) -> [String: DeviceConfiguration] {
        ConfigManager.deviceFirstMigratedConfigurations(
            input,
            aliases: aliases,
            legacyCurrentProfile: legacyCurrent,
            profileExists: { self.existing.contains($0) },
            fallbackProfile: "Default"
        )
    }

    func testPureGlobalUserAdoptsLegacyCurrentProfile() {
        let result = migrate(["devA": DeviceConfiguration()])
        XCTAssertEqual(result["devA"]?.activeProfile, "Default")
        XCTAssertEqual(result["devA"]?.profileRefs, ["Default"])
    }

    func testBoundDeviceKeepsItsBoundProfileAndMountsLegacyCurrent() {
        var config = DeviceConfiguration()
        config.boundProfile = "游戏"
        let result = migrate(["devA": config])
        XCTAssertEqual(result["devA"]?.activeProfile, "游戏")
        // The old globally-selected profile rides along as a mounted (not
        // active) profile so it stays reachable under the device.
        XCTAssertEqual(result["devA"]?.profileRefs, ["游戏", "Default"])
    }

    func testDanglingBoundProfileFallsBackToLegacyCurrent() {
        var config = DeviceConfiguration()
        config.boundProfile = "已删除的配置"
        let result = migrate(["devA": config], legacyCurrent: "办公")
        XCTAssertEqual(result["devA"]?.activeProfile, "办公")
    }

    func testMissingLegacyCurrentFallsBackToDefault() {
        let result = migrate(["devA": DeviceConfiguration()], legacyCurrent: "不存在")
        XCTAssertEqual(result["devA"]?.activeProfile, "Default")
    }

    func testAliasPairSplitsIntoIndependentDevicesSharingProfile() {
        var primary = DeviceConfiguration()
        primary.hardwareMapping = ["1": HardwareKey(usagePage: 7, usage: 30, keyCode: 18, displayString: "1")]
        primary.customNames = ["1": "治疗"]
        primary.boundProfile = "游戏"
        let result = migrate(
            ["devA": primary],
            aliases: ["devB": "devA"]
        )
        // The former alias source becomes a standalone device with its own
        // copy of the learned table and names…
        XCTAssertEqual(result["devB"]?.hardwareMapping, primary.hardwareMapping)
        XCTAssertEqual(result["devB"]?.customNames, ["1": "治疗"])
        // …and both connection identities run the same profile by reference.
        XCTAssertEqual(result["devA"]?.activeProfile, "游戏")
        XCTAssertEqual(result["devB"]?.activeProfile, "游戏")
    }

    func testAliasSplitPrefersPrimaryDataOverStaleSourceSnapshot() {
        // The alias period redirected all reads/writes to the primary, so a
        // source's own pre-alias record is frozen and must lose to the
        // primary's live data on split.
        var stale = DeviceConfiguration()
        stale.hardwareMapping = ["1": HardwareKey(usagePage: 7, usage: 30, keyCode: 1, displayString: "旧")]
        stale.boundProfile = "办公"
        var primary = DeviceConfiguration()
        primary.hardwareMapping = ["1": HardwareKey(usagePage: 7, usage: 31, keyCode: 2, displayString: "新")]
        primary.boundProfile = "游戏"
        let result = migrate(["devA": primary, "devB": stale], aliases: ["devB": "devA"])
        XCTAssertEqual(result["devB"]?.hardwareMapping, primary.hardwareMapping)
        XCTAssertEqual(result["devB"]?.activeProfile, "游戏")
    }

    func testAlreadyMigratedConfigurationIsUntouched() {
        var config = DeviceConfiguration()
        config.activeProfile = "办公"
        config.profileRefs = ["办公", "游戏"]
        config.boundProfile = "游戏"
        let result = migrate(["devA": config], legacyCurrent: "游戏")
        XCTAssertEqual(result["devA"]?.activeProfile, "办公")
        XCTAssertEqual(result["devA"]?.profileRefs, ["办公", "游戏"])
    }

    func testMixedFleetMigratesEachDeviceIndependently() {
        var bound = DeviceConfiguration()
        bound.boundProfile = "游戏"
        let result = migrate(
            ["devA": bound, "devB": DeviceConfiguration()],
            legacyCurrent: "办公"
        )
        XCTAssertEqual(result["devA"]?.activeProfile, "游戏")
        XCTAssertEqual(result["devB"]?.activeProfile, "办公")
    }

    func testEnhancedIdentityCopiesBaseConfigurationOnceAndKeepsTemplate() {
        var base = DeviceConfiguration()
        base.hardwareMapping = ["1": HardwareKey(usagePage: 7, usage: 30, keyCode: 18, displayString: "1")]
        base.customNames = ["1": "治疗"]
        var configurations = ["1532:00b4": base]
        let enhanced = "1532:00b4#serial=RX01"

        XCTAssertTrue(ConfigManager.seedEnhancedIdentityConfiguration(
            &configurations,
            enhancedKey: enhanced,
            baseKey: "1532:00b4"
        ))
        XCTAssertEqual(configurations[enhanced], base)
        XCTAssertEqual(configurations["1532:00b4"], base)

        configurations[enhanced]?.customNames = ["1": "实例专属"]
        XCTAssertFalse(ConfigManager.seedEnhancedIdentityConfiguration(
            &configurations,
            enhancedKey: enhanced,
            baseKey: "1532:00b4"
        ))
        XCTAssertEqual(configurations[enhanced]?.customNames, ["1": "实例专属"])
        XCTAssertEqual(configurations["1532:00b4"]?.customNames, ["1": "治疗"])
    }
}
