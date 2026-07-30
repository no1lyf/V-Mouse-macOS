import Cocoa

enum DesignSystem {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    enum Radius {
        static let badge: CGFloat = 4
        static let smallButton: CGFloat = 6
        static let control: CGFloat = 7
        static let card: CGFloat = 10
        static let container: CGFloat = 14
    }

    enum Size {
        static let toolbarHeight: CGFloat = 52
        static let cardMinHeight: CGFloat = 126
        static let buttonHeight: CGFloat = 28
        static let toolbarButtonHeight: CGFloat = 30
        static let popoverWidth: CGFloat = 360
    }
    
    enum Colors {
        private static func dynamicColor(_ keyPath: KeyPath<ThemePalette, NSColor>) -> NSColor {
            return NSColor(name: nil) { appearance in
                let isDark = ThemeManager.shared.isDark(appearance: appearance)
                return isDark ? ThemePalette.dark[keyPath: keyPath] : ThemePalette.light[keyPath: keyPath]
            }
        }
        
        static let windowBackground = dynamicColor(\.windowBackground)
        static let toolbarBackground = dynamicColor(\.toolbarBackground)
        static let sectionBackground = dynamicColor(\.sectionBackground)

        static let cardBackground = dynamicColor(\.cardBackground)
        static let cardHoverBackground = dynamicColor(\.cardHoverBackground)
        static let cardPressedBackground = dynamicColor(\.cardPressedBackground)
        static let cardSelectedBackground = dynamicColor(\.cardSelectedBackground)

        static let popoverBackground = dynamicColor(\.popoverBackground)

        static let controlBackground = dynamicColor(\.controlBackground)
        static let controlHoverBackground = dynamicColor(\.controlHoverBackground)
        static let controlPressedBackground = dynamicColor(\.controlPressedBackground)

        static let borderNormal = dynamicColor(\.borderNormal)
        static let borderSubtle = dynamicColor(\.borderSubtle)
        static let divider = dynamicColor(\.divider)
        static let focusRing = dynamicColor(\.focusRing)

        static let textPrimary = dynamicColor(\.textPrimary)
        static let textSecondary = dynamicColor(\.textSecondary)
        static let textTertiary = dynamicColor(\.textTertiary)
        static let textDisabled = dynamicColor(\.textDisabled)
        static let textOnAccent = dynamicColor(\.textOnAccent)

        static let accentFill = dynamicColor(\.accentFill)
        static let accentHover = dynamicColor(\.accentHover)
        static let accentPressed = dynamicColor(\.accentPressed)
        static let accentText = dynamicColor(\.accentText)
        static let accentSoft = dynamicColor(\.accentSoft)

        static let warningBackground = dynamicColor(\.warningBackground)
        static let warningBorder = dynamicColor(\.warningBorder)
        static let warningText = dynamicColor(\.warningText)

        static let dangerBackground = dynamicColor(\.dangerBackground)
        static let dangerBorder = dynamicColor(\.dangerBorder)
        static let dangerText = dynamicColor(\.dangerText)
        static let dangerHover = dynamicColor(\.dangerHover)
        static let dangerFill = dynamicColor(\.dangerFill)

        static let successBackground = dynamicColor(\.successBackground)
        static let successBorder = dynamicColor(\.successBorder)
        static let successText = dynamicColor(\.successText)
        
        static let shadowColor = dynamicColor(\.shadowColor)
    }
}
