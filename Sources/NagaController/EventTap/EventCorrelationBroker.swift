import Foundation
import Darwin

enum CorrelatedEventKind: Hashable {
    case keyboard(Int)
    case modifier(Int)
    case mouse(Int)
    case scroll
    case horizontalScroll(Int)
    case systemDefined
}

struct CorrelatedMatch {
    let buttonIndex: Int?
    let pressed: Bool
    /// Stable key of the physical device that produced the HID transition,
    /// so multiple simultaneously consumed mice resolve their own actions.
    let deviceKey: String?
}

/// One-shot bridge from a report emitted by the verified Naga device to the
/// corresponding system event. Unlike v0.1.1, no "recently pressed" state is
/// reusable: one HID transition can consume at most one CGEvent.
final class EventCorrelationBroker {
    static let shared = EventCorrelationBroker()

    private struct Token {
        let kind: CorrelatedEventKind
        let pressed: Bool
        let buttonIndex: Int?
        let deviceKey: String?
        let expectedTimestampNs: UInt64
        let toleranceNs: UInt64
        let expiresAtNs: UInt64
    }

    private var lock = os_unfair_lock()
    private var tokens: [Token] = []

    private init() {}

    func enqueue(
        kind: CorrelatedEventKind,
        pressed: Bool,
        buttonIndex: Int?,
        deviceKey: String? = nil,
        hidTimestamp: UInt64,
        offsetNs: Int64?,
        toleranceNs: UInt64?
    ) {
        let hidNs = MonotonicClock.nanoseconds(fromMachAbsolute: hidTimestamp)
        let expected = Self.addSigned(hidNs, offsetNs ?? ConfigManager.shared.getCorrelationOffsetNs())
        let maximumTolerance: UInt64
        switch kind {
        case .scroll, .horizontalScroll: maximumTolerance = 50_000_000
        default: maximumTolerance = 20_000_000
        }
        let tolerance = min(
            max(toleranceNs ?? ConfigManager.shared.getCorrelationToleranceNs(), 500_000),
            maximumTolerance
        )
        let now = MonotonicClock.nowNanoseconds()
        let token = Token(
            kind: kind,
            pressed: pressed,
            buttonIndex: buttonIndex,
            deviceKey: deviceKey,
            expectedTimestampNs: expected,
            toleranceNs: tolerance,
            expiresAtNs: now &+ 100_000_000
        )

        os_unfair_lock_lock(&lock)
        tokens.removeAll { $0.expiresAtNs < now }
        if tokens.count >= 128 { tokens.removeFirst(tokens.count - 127) }
        tokens.append(token)
        os_unfair_lock_unlock(&lock)
    }

    func consume(kind: CorrelatedEventKind, pressed: Bool, eventTimestampNs: UInt64) -> CorrelatedMatch? {
        let now = MonotonicClock.nowNanoseconds()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        tokens.removeAll { $0.expiresAtNs < now }

        var bestIndex: Int?
        var bestDistance = UInt64.max
        for (index, token) in tokens.enumerated() where token.kind == kind && token.pressed == pressed {
            let distance = Self.distance(token.expectedTimestampNs, eventTimestampNs)
            guard distance <= token.toleranceNs, distance < bestDistance else { continue }
            bestIndex = index
            bestDistance = distance
        }
        guard let bestIndex else { return nil }
        let token = tokens.remove(at: bestIndex)
        return CorrelatedMatch(
            buttonIndex: token.buttonIndex,
            pressed: token.pressed,
            deviceKey: token.deviceKey
        )
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        tokens.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
    }

    /// A single discrete HID wheel step may be represented by more than one
    /// CGEvent or coalesced with adjacent steps. Scroll evidence is therefore
    /// reusable inside its short window; keyboard and button tokens remain
    /// strictly one-shot.
    func matchesScroll(eventTimestampNs: UInt64) -> Bool {
        let now = MonotonicClock.nowNanoseconds()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        tokens.removeAll { $0.expiresAtNs < now }
        return tokens.contains { token in
            token.kind == .scroll &&
                token.pressed &&
                Self.distance(token.expectedTimestampNs, eventTimestampNs) <= token.toleranceNs
        }
    }

    private static func distance(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }

    private static func addSigned(_ value: UInt64, _ delta: Int64) -> UInt64 {
        if delta >= 0 {
            let (result, overflow) = value.addingReportingOverflow(UInt64(delta))
            return overflow ? UInt64.max : result
        }
        let magnitude = UInt64(delta.magnitude)
        return value >= magnitude ? value - magnitude : 0
    }
}

enum MonotonicClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nanoseconds(fromMachAbsolute value: UInt64) -> UInt64 {
        if timebase.numer == timebase.denom { return value }
        return UInt64((Double(value) * Double(timebase.numer)) / Double(timebase.denom))
    }

    static func nowNanoseconds() -> UInt64 {
        nanoseconds(fromMachAbsolute: mach_absolute_time())
    }
}

/// Shared macOS virtual-key facts. Single source of truth for "is this key
/// code a modifier" so the tap, mapper and scroll manager can never disagree.
enum MacKeyCodes {
    static func isModifier(_ code: Int) -> Bool {
        switch code {
        case 54, 55, 56, 58, 59, 60, 61, 62, 63: return true
        default: return false
        }
    }
}

enum HIDUsageKeyCodeMap {
    private static let keyCodes: [UInt32: Int] = [
        0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3,
        0x0a: 5, 0x0b: 4, 0x0c: 34, 0x0d: 38, 0x0e: 40, 0x0f: 37,
        0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15,
        0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1a: 13, 0x1b: 7,
        0x1c: 16, 0x1d: 6,
        0x1e: 18, 0x1f: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22,
        0x24: 26, 0x25: 28, 0x26: 25, 0x27: 29,
        0x28: 36, 0x29: 53, 0x2a: 51, 0x2b: 48, 0x2c: 49,
        0x2d: 27, 0x2e: 24, 0x2f: 33, 0x30: 30, 0x31: 42,
        0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44,
        0x39: 57,
        0x3a: 122, 0x3b: 120, 0x3c: 99, 0x3d: 118, 0x3e: 96, 0x3f: 97,
        0x40: 98, 0x41: 100, 0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
        0x46: 105, 0x47: 107, 0x48: 113,
        0x49: 114, 0x4a: 115, 0x4b: 116, 0x4c: 117, 0x4d: 119, 0x4e: 121,
        0x4f: 124, 0x50: 123, 0x51: 125, 0x52: 126,
        0xe0: 59, 0xe1: 56, 0xe2: 58, 0xe3: 55,
        0xe4: 62, 0xe5: 60, 0xe6: 61, 0xe7: 54
    ]

    static func keyCode(for usage: UInt32) -> Int? { keyCodes[usage] }
    static func isModifier(_ usage: UInt32) -> Bool { (0xe0...0xe7).contains(usage) }
}
