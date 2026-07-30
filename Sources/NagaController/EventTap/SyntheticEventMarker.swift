import CoreGraphics

enum SyntheticEventMarker {
    // ASCII "NAGACTRL". Physical events never carry this value.
    static let value: Int64 = 0x4e41_4741_4354_524c

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: value)
    }

    static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == value
    }
}
