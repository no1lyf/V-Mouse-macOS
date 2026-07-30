import XCTest
@testable import NagaController

final class BuiltInTrackpadManagerTests: XCTestCase {
    func testReadsEffectiveValueFromMultitouchPreferences() {
        let properties: NSDictionary = [
            "Built-In": true,
            "Product": "Apple Internal Keyboard / Trackpad",
            "MultitouchPreferences": [
                "USBMouseStopsTrackpad": 1
            ]
        ]

        XCTAssertEqual(BuiltInTrackpadManager.effectivePolicyValue(in: properties), true)
    }

    func testReadsEffectiveValueFromHIDEventServiceProperties() {
        let properties: NSDictionary = [
            "Built-In": true,
            "Product": "Apple Internal Keyboard / Trackpad",
            "HIDEventServiceProperties": [
                "USBMouseStopsTrackpad": 0
            ]
        ]

        XCTAssertEqual(BuiltInTrackpadManager.effectivePolicyValue(in: properties), false)
    }

    func testRejectsRegistryEntryWithoutEffectivePolicy() {
        XCTAssertNil(BuiltInTrackpadManager.effectivePolicyValue(in: [
            "Built-In": true,
            "Product": "Apple Internal Keyboard / Trackpad"
        ]))
    }

}
