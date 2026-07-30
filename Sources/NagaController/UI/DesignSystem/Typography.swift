import Cocoa

enum Typography {
    static let windowTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)
    static let sectionTitle = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let cardTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let mappingValue = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let bodyNormal = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodySecondary = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    static let bodyTertiary = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let buttonText = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let menuTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
}
