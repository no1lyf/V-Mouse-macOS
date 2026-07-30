import Cocoa

final class ThemeManager {
    static let shared = ThemeManager()

    private let themeDefaultsKey = "appTheme"

    // isDark(appearance:) runs inside every dynamic-color resolution during
    // layer updates — a hot path. Cache the mode instead of hitting
    // UserDefaults on each call; setTheme is the only writer.
    private(set) lazy var currentMode: ThemeMode = {
        guard let raw = UserDefaults.standard.string(forKey: themeDefaultsKey),
              let saved = ThemeMode(rawValue: raw) else { return .system }
        return saved
    }()

    func setTheme(_ newTheme: ThemeMode) {
        guard newTheme != currentMode else { return }
        currentMode = newTheme
        UserDefaults.standard.set(newTheme.rawValue, forKey: themeDefaultsKey)
        applyAppAppearance()
        NotificationCenter.default.post(name: .appThemeDidChange, object: newTheme)
    }
    
    func applyAppAppearance() {
        let appearance: NSAppearance?
        switch currentMode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
    
    func isDark(appearance: NSAppearance) -> Bool {
        if currentMode == .dark { return true }
        if currentMode == .light { return false }
        
        // For .system, check actual appearance
        let darkNames: [NSAppearance.Name] = [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
        return darkNames.contains(appearance.name)
    }
}

extension Notification.Name {
    static let appThemeDidChange = Notification.Name("NagaController.AppThemeDidChange")
}

