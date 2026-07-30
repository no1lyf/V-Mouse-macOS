import Foundation

struct ScrollHotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: [String]

    var displayText: String {
        switch keyCode {
        case 54, 55: return "⌘ Command"
        case 56, 60: return "⇧ Shift"
        case 58, 61: return "⌥ Option"
        case 59, 62: return "⌃ Control"
        case 63: return "Fn"
        default: break
        }
        return KeyStroke(key: KeyStroke.canonicalKeyString(for: keyCode, characters: nil),
                         modifiers: modifiers,
                         keyCode: keyCode).formattedShortcut()
    }
}

struct ScrollSettings: Codable, Equatable {
    var enabled: Bool
    var smooth: Bool
    var smoothVertical: Bool
    var smoothHorizontal: Bool
    var simulateTrackpad: Bool
    var reverse: Bool
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var step: Double
    var speed: Double
    var duration: Double
    var deadZone: Double
    var dashHotkey: ScrollHotkey?
    var shiftAxisHotkey: ScrollHotkey?
    var blockSmoothHotkey: ScrollHotkey?

    static let defaults = ScrollSettings(
        enabled: false,
        smooth: false,
        smoothVertical: true,
        smoothHorizontal: true,
        simulateTrackpad: false,
        reverse: true,
        reverseVertical: true,
        reverseHorizontal: false,
        step: 33.6,
        speed: 2.70,
        duration: 4.35,
        deadZone: 1.0,
        dashHotkey: ScrollHotkey(keyCode: 58, modifiers: []),
        shiftAxisHotkey: ScrollHotkey(keyCode: 56, modifiers: []),
        blockSmoothHotkey: ScrollHotkey(keyCode: 55, modifiers: [])
    )

    var durationTransition: Double {
        let value = 1.0 - sqrt(duration / 5.2)
        return min(0.95, max(0.03, value))
    }

    func validated() -> ScrollSettings {
        var value = self
        value.step = min(120, max(1, value.step))
        value.speed = min(8, max(0.1, value.speed))
        value.duration = value.simulateTrackpad ? 4.75 : min(5.0, max(0.1, value.duration))
        value.deadZone = min(5, max(0.05, value.deadZone))
        return value
    }
}

extension ScrollSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled, smooth, smoothVertical, smoothHorizontal, simulateTrackpad
        case reverse, reverseVertical, reverseHorizontal
        case step, speed, duration, deadZone
        case dashHotkey, shiftAxisHotkey, blockSmoothHotkey
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaults
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        smooth = try values.decodeIfPresent(Bool.self, forKey: .smooth) ?? fallback.smooth
        smoothVertical = try values.decodeIfPresent(Bool.self, forKey: .smoothVertical) ?? fallback.smoothVertical
        smoothHorizontal = try values.decodeIfPresent(Bool.self, forKey: .smoothHorizontal) ?? fallback.smoothHorizontal
        simulateTrackpad = try values.decodeIfPresent(Bool.self, forKey: .simulateTrackpad) ?? fallback.simulateTrackpad
        reverse = try values.decodeIfPresent(Bool.self, forKey: .reverse) ?? fallback.reverse
        reverseVertical = try values.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? fallback.reverseVertical
        reverseHorizontal = try values.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? fallback.reverseHorizontal
        step = try values.decodeIfPresent(Double.self, forKey: .step) ?? fallback.step
        speed = try values.decodeIfPresent(Double.self, forKey: .speed) ?? fallback.speed
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? fallback.duration
        deadZone = try values.decodeIfPresent(Double.self, forKey: .deadZone) ?? fallback.deadZone
        dashHotkey = values.contains(.dashHotkey)
            ? try values.decodeIfPresent(ScrollHotkey.self, forKey: .dashHotkey)
            : fallback.dashHotkey
        shiftAxisHotkey = values.contains(.shiftAxisHotkey)
            ? try values.decodeIfPresent(ScrollHotkey.self, forKey: .shiftAxisHotkey)
            : fallback.shiftAxisHotkey
        blockSmoothHotkey = values.contains(.blockSmoothHotkey)
            ? try values.decodeIfPresent(ScrollHotkey.self, forKey: .blockSmoothHotkey)
            : fallback.blockSmoothHotkey
    }
}

enum ScrollControlRole: String, Codable, CaseIterable {
    case accelerate
    case shiftAxis
    case blockSmooth

    var displayName: String {
        switch self {
        case .accelerate: return L10n.text("滚轮加速（按住）")
        case .shiftAxis: return L10n.text("纵向滚动转为横向（按住）")
        case .blockSmooth: return L10n.text("临时禁用平滑（按住）")
        }
    }
}
