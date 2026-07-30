import Foundation

enum InputSourceCatalog {
    static let supportedIndices = 1...16

    static func name(for index: Int) -> String {
        switch index {
        case 13: return L10n.text("DPI+")
        case 14: return L10n.text("DPI−")
        case 15: return L10n.text("滚轮左键")
        case 16: return L10n.text("滚轮右键")
        case let i where i >= 17: return L10n.format("自定义键%d", i - 16)
        default: return L10n.format("侧键 %d", index)
        }
    }

    static func mappingName(for index: Int) -> String {
        switch index {
        case 13: return L10n.text("DPI 增加")
        case 14: return L10n.text("DPI 减少")
        case 15: return L10n.text("滚轮左键")
        case 16: return L10n.text("滚轮右键")
        case let i where i >= 17: return L10n.format("自定义键%d", i - 16)
        default: return L10n.format("侧键 %d", index)
        }
    }

    static func compactLabel(for index: Int) -> String {
        switch index {
        case 13: return "D+"
        case 14: return "D−"
        case 15: return "W←"
        case 16: return "W→"
        case let i where i >= 17: return String(format: "C%d", i - 16)
        default: return String(format: "%02d", index)
        }
    }
}
