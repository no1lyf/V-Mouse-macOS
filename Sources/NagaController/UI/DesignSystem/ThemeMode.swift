import Cocoa

enum ThemeMode: String, CaseIterable, Codable {
    case system
    case light
    case dark
    
    var displayName: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .light: return L10n.text("浅色")
        case .dark: return L10n.text("暗色")
        }
    }
}
