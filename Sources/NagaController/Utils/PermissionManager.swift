import Cocoa
import ApplicationServices

final class PermissionManager: NSObject, NSWindowDelegate {
    static let shared = PermissionManager()
    private var accessibilityAlert: NSAlert?
    private let unifiedGuideKey = "hasShownUnifiedPermissionGuideV3"

    private override init() { super.init() }

    func ensureAccessibilityPermission() {
        let trusted = isProcessTrusted()
        NSLog("[Permissions] Accessibility trusted = \(trusted)")
        // The unified guide covers both permissions, so it must also appear
        // when Accessibility is granted but Input Monitoring is still missing.
        guard !trusted || !hasInputMonitoringPermission() else { return }
        presentUnifiedGuideIfNeeded()
    }

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func hasAccessibilityPermission() -> Bool {
        isProcessTrusted()
    }

    func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    /// Ask macOS for Input Monitoring when the current code identity has not
    /// been granted access yet. Development builds are ad-hoc signed, so a new
    /// executable can legitimately need a fresh TCC decision even when an old
    /// row with the same bundle name is still visible in System Settings.
    @discardableResult
    func requestInputMonitoringPermissionIfNeeded() -> Bool {
        if #available(macOS 10.15, *) {
            let preflight = CGPreflightListenEventAccess()
            NSLog("[Permissions] Input Monitoring preflight = \(preflight)")
            guard !preflight else { return true }
            let granted = CGRequestListenEventAccess()
            NSLog("[Permissions] Input Monitoring request result = \(granted)")
            return granted
        }
        return true
    }

    func openAccessibilityPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func presentUnifiedGuideIfNeeded(force: Bool = false) {
        let missingPermission = !hasAccessibilityPermission() || !hasInputMonitoringPermission()
        guard (force || missingPermission), accessibilityAlert == nil else { return }
        guard force || !UserDefaults.standard.bool(forKey: unifiedGuideKey) else { return }
        UserDefaults.standard.set(true, forKey: unifiedGuideKey)

        let alert = NSAlert()
        alert.messageText = Self.permissionGuideTitle
        alert.informativeText = Self.permissionGuideText
        alert.alertStyle = .warning
        alert.showsSuppressionButton = false
        alert.showsHelp = false
        alert.icon = UIStyle.symbol("lock.shield", size: 48, weight: .regular)
        let accessibilityButton = alert.addButton(withTitle: L10n.text("辅助功能"))
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilityFromAlert)
        let inputButton = alert.addButton(withTitle: L10n.text("输入监控"))
        inputButton.target = self
        inputButton.action = #selector(openInputMonitoringFromAlert)
        let dismissButton = alert.addButton(withTitle: Self.laterTitle)
        dismissButton.target = self
        dismissButton.action = #selector(dismissAccessibilityAlert)

        // runModal() nests AppKit's event loop while the menu-bar popover is
        // still being constructed and can trigger illegal layout recursion.
        // A modeless alert keeps the guidance without blocking application
        // startup or re-entering the layout engine.
        accessibilityAlert = alert
        alert.suppressionButton?.isHidden = true
        alert.window.delegate = self
        alert.window.level = .floating
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var guideWindowForPreview: NSWindow? { accessibilityAlert?.window }

    @objc private func openAccessibilityFromAlert() {
        openAccessibilityPreferences()
        accessibilityAlert?.window.close()
    }

    @objc private func openInputMonitoringFromAlert() {
        openInputMonitoringPreferences()
        accessibilityAlert?.window.close()
    }

    @objc private func dismissAccessibilityAlert() {
        accessibilityAlert?.window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === accessibilityAlert?.window else { return }
        accessibilityAlert = nil
    }

    private static var permissionGuideTitle: String {
        switch L10n.language {
        case .chineseSimplified: return "完成权限设置"
        case .english: return "Finish Permission Setup"
        case .japanese: return "権限設定を完了"
        case .korean: return "권한 설정 완료"
        case .german: return "Berechtigungen einrichten"
        }
    }

    private static var permissionGuideText: String {
        switch L10n.language {
        case .chineseSimplified:
            return "鼠标按键二次映射需要“辅助功能”和“输入监控”。请分别打开系统设置并启用当前版本的 V-Mouse鼠标映射。软件不会自动修改系统权限。"
        case .english:
            return "Mouse-button remapping needs Accessibility and Input Monitoring. Open each System Settings page and enable the current V-Mouse鼠标映射 app. The app never changes system permissions automatically."
        case .japanese:
            return "マウスボタンの再割り当てには「アクセシビリティ」と「入力監視」が必要です。各設定画面で現在のV-Mouse鼠标映射を有効にしてください。"
        case .korean:
            return "마우스 버튼 재매핑에는 손쉬운 사용과 입력 모니터링 권한이 필요합니다. 각 시스템 설정에서 현재 V-Mouse鼠标映射 앱을 활성화하세요."
        case .german:
            return "Für die Neubelegung von Maustasten werden Bedienungshilfen und Eingabeüberwachung benötigt. Aktivieren Sie in beiden Systemeinstellungen die aktuelle V-Mouse鼠标映射-App."
        }
    }

    private static var laterTitle: String {
        switch L10n.language {
        case .chineseSimplified: return "稍后"
        case .english: return "Later"
        case .japanese: return "後で"
        case .korean: return "나중에"
        case .german: return "Später"
        }
    }
}
