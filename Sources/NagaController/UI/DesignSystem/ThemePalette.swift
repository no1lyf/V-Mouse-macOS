import Cocoa

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct ThemePalette {
    let windowBackground: NSColor
    let toolbarBackground: NSColor
    let sectionBackground: NSColor

    let cardBackground: NSColor
    let cardHoverBackground: NSColor
    let cardPressedBackground: NSColor
    let cardSelectedBackground: NSColor

    let popoverBackground: NSColor

    let controlBackground: NSColor
    let controlHoverBackground: NSColor
    let controlPressedBackground: NSColor

    let borderNormal: NSColor
    let borderSubtle: NSColor
    let divider: NSColor
    let focusRing: NSColor

    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let textDisabled: NSColor
    let textOnAccent: NSColor

    let accentFill: NSColor
    let accentHover: NSColor
    let accentPressed: NSColor
    let accentText: NSColor
    let accentSoft: NSColor

    let warningBackground: NSColor
    let warningBorder: NSColor
    let warningText: NSColor

    let dangerBackground: NSColor
    let dangerBorder: NSColor
    let dangerText: NSColor
    let dangerHover: NSColor
    let dangerFill: NSColor

    let successBackground: NSColor
    let successBorder: NSColor
    let successText: NSColor
    
    let shadowColor: NSColor
}

extension ThemePalette {
    static let light = ThemePalette(
        windowBackground: NSColor(hex: 0xF5F5F7),
        toolbarBackground: NSColor(hex: 0xFAFAFC),
        sectionBackground: NSColor(hex: 0xECEEF2),

        cardBackground: NSColor(hex: 0xFFFFFF),
        cardHoverBackground: NSColor(hex: 0xF7F8FA),
        cardPressedBackground: NSColor(hex: 0xEFF1F4),
        cardSelectedBackground: NSColor(hex: 0xEAF3FF),

        popoverBackground: NSColor(hex: 0xFFFFFF),

        controlBackground: NSColor(hex: 0xFFFFFF),
        controlHoverBackground: NSColor(hex: 0xF0F1F3),
        controlPressedBackground: NSColor(hex: 0xE5E7EB),

        borderNormal: NSColor(hex: 0xD0D3D8),
        borderSubtle: NSColor(hex: 0xDEE0E4),
        divider: NSColor(hex: 0xD8DADF),
        focusRing: NSColor(hex: 0x006EDB),

        textPrimary: NSColor(hex: 0x1D1D1F),
        textSecondary: NSColor(hex: 0x5F6268),
        textTertiary: NSColor(hex: 0x707078),
        textDisabled: NSColor(hex: 0x9A9AA0),
        textOnAccent: NSColor(hex: 0xFFFFFF),

        accentFill: NSColor(hex: 0x006EDB),
        accentHover: NSColor(hex: 0x005FC4),
        accentPressed: NSColor(hex: 0x0052AA),
        accentText: NSColor(hex: 0x0062CC),
        accentSoft: NSColor(hex: 0xEAF3FF),

        warningBackground: NSColor(hex: 0xFFF4E5),
        warningBorder: NSColor(hex: 0xF3C37A),
        warningText: NSColor(hex: 0x8A3B00),

        dangerBackground: NSColor(hex: 0xFFF0F0),
        dangerBorder: NSColor(hex: 0xE6C3C3),
        dangerText: NSColor(hex: 0x992B2B),
        dangerHover: NSColor(hex: 0xD24537),
        dangerFill: NSColor(hex: 0xA93226),

        successBackground: NSColor(hex: 0xECFDF3),
        successBorder: NSColor(hex: 0xABEFC6),
        successText: NSColor(hex: 0x067647),
        
        shadowColor: NSColor(white: 0, alpha: 0.18)
    )

    static let dark = ThemePalette(
        windowBackground: NSColor(hex: 0x1C1C1E),
        toolbarBackground: NSColor(hex: 0x222224),
        sectionBackground: NSColor(hex: 0x242426),

        cardBackground: NSColor(hex: 0x2C2C2E),
        cardHoverBackground: NSColor(hex: 0x343437),
        cardPressedBackground: NSColor(hex: 0x3A3A3D),
        cardSelectedBackground: NSColor(hex: 0x103A5C),

        popoverBackground: NSColor(hex: 0x29292C),

        controlBackground: NSColor(hex: 0x3A3A3C),
        controlHoverBackground: NSColor(hex: 0x464649),
        controlPressedBackground: NSColor(hex: 0x505054),

        borderNormal: NSColor(hex: 0x48484C),
        borderSubtle: NSColor(hex: 0x3A3A3E),
        divider: NSColor(hex: 0x3A3A3C),
        focusRing: NSColor(hex: 0x409CFF),

        textPrimary: NSColor(hex: 0xF5F5F7),
        textSecondary: NSColor(hex: 0xD1D1D6),
        textTertiary: NSColor(hex: 0xA1A1A6),
        textDisabled: NSColor(hex: 0x747478),
        textOnAccent: NSColor(hex: 0xFFFFFF),

        accentFill: NSColor(hex: 0x0071E3),
        accentHover: NSColor(hex: 0x1684EA),
        accentPressed: NSColor(hex: 0x0062C4),
        accentText: NSColor(hex: 0x409CFF),
        accentSoft: NSColor(hex: 0x103A5C),

        warningBackground: NSColor(hex: 0x4A2A00),
        warningBorder: NSColor(hex: 0x805000),
        warningText: NSColor(hex: 0xFFB340),

        dangerBackground: NSColor(hex: 0x331414),
        dangerBorder: NSColor(hex: 0x5C2424),
        dangerText: NSColor(hex: 0xE06C66),
        dangerHover: NSColor(hex: 0xB94040),
        dangerFill: NSColor(hex: 0x8F2A2A),

        successBackground: NSColor(hex: 0x123A24),
        successBorder: NSColor(hex: 0x23643E),
        successText: NSColor(hex: 0x5ED98A),
        
        shadowColor: NSColor(white: 0, alpha: 0.45)
    )
}
