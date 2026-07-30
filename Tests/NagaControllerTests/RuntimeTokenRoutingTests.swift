import XCTest
@testable import NagaController

final class RuntimeTokenRoutingTests: XCTestCase {
    func testPureModifierWithoutChordEvidencePassesThrough() {
        // A modifier-only report resolves no chord route (override nil/false)
        // and must not create an interception token, so the onboard Shift or
        // Command side key keeps its native behavior.
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0xe1, hasBinding: false,
            bindingIntercepted: false, interceptionOverride: nil
        ))
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0xe3, hasBinding: false,
            bindingIntercepted: false, interceptionOverride: false
        ))
    }

    func testModifierFollowsInterceptedChordRoute() {
        XCTAssertTrue(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0xe0, hasBinding: false,
            bindingIntercepted: false, interceptionOverride: true
        ))
    }

    func testRegularKeyRequiresLearnedAndEnabledBinding() {
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0x04, hasBinding: false,
            bindingIntercepted: false, interceptionOverride: nil
        ))
        XCTAssertFalse(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0x04, hasBinding: true,
            bindingIntercepted: false, interceptionOverride: nil
        ))
        XCTAssertTrue(HIDListener.shouldCreateRuntimeToken(
            page: 0x07, usage: 0x04, hasBinding: true,
            bindingIntercepted: true, interceptionOverride: nil
        ))
    }

    func testModifierKeyCodeFactsAreShared() {
        for code in [54, 55, 56, 58, 59, 60, 61, 62, 63] {
            XCTAssertTrue(MacKeyCodes.isModifier(code))
        }
        XCTAssertFalse(MacKeyCodes.isModifier(0))
        XCTAssertFalse(MacKeyCodes.isModifier(57)) // caps lock is not held state
    }

    func testSameCGCodeKeepsIndependentMappedSources() {
        var registry = MultiSourceRegistry<String>()
        XCTAssertTrue(registry.insert("device-a/button-1", for: 8))
        XCTAssertTrue(registry.insert("device-b/button-4", for: 8))
        XCTAssertFalse(registry.insert("device-a/button-1", for: 8))
        XCTAssertEqual(registry.sourcesByCode[8]?.count, 2)

        registry.remove("device-a/button-1", for: 8)
        XCTAssertTrue(registry.isActive(8))
        XCTAssertEqual(registry.sourcesByCode[8], Set(["device-b/button-4"]))

        registry.remove("device-b/button-4", for: 8)
        XCTAssertFalse(registry.isActive(8))
    }
}
