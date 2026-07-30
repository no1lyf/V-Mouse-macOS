import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var batteryObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?
    private var welcomeController: WelcomeWindowController?
    private var didAlertLowBattery = false
    private var useEmojiInStatus = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must run before theme/language/settings singletons read the new
        // bundle domain, otherwise the first launch after the identity change
        // would temporarily look like a fresh install.
        ConfigManager.shared.migrateLegacyBundlePreferencesIfNeeded()

        // Apply theme early on
        ThemeManager.shared.applyAppAppearance()

        // Ensure Accessibility permissions
        PermissionManager.shared.ensureAccessibilityPermission()

        // Load configuration (profiles, settings)
        ConfigManager.shared.load()

        // The trackpad policy is owned by V-Mouse while it is running. The
        // user's saved choice is reapplied at launch and released on exit.
        if !BuiltInTrackpadManager.applySavedPolicy() {
            NSLog("[Trackpad] Failed to apply the saved external-mouse policy.")
        }

        // Start HID listener (filters Naga device presses)
        _ = HIDListener.shared

        // Start Bluetooth battery monitoring (BLE Battery Service 0x180F)
        BatteryMonitor.shared.start()

        // Status bar item (variable length to show %)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuBar") {
                icon.isTemplate = true
                button.image = icon
                button.imagePosition = .imageLeading
            } else {
                // Fallback to an SF Symbol if available; else use emoji in the title
                if let sym = UIStyle.symbol("computermouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("mouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("battery.100", size: 14, weight: .regular) {
                    sym.isTemplate = true
                    button.image = sym
                    button.imagePosition = .imageLeading
                } else {
                    useEmojiInStatus = true
                }
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Popover content
        popover.behavior = .transient
        updatePopoverTheme()
        NotificationCenter.default.addObserver(forName: .appThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updatePopoverTheme()
        }
        popover.contentViewController = MainViewController()

        // Rebuild every visible surface when the in-app language changes.
        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.popover.isShown { self.popover.performClose(nil) }
            self.popover.contentViewController = MainViewController()
            MappingWindowController.shared.refreshInterfaceIfVisible()
            ScrollSettingsWindowController.shared.refreshInterfaceIfVisible()
            TutorialWindowController.shared.refreshInterfaceIfVisible()
            self.updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)
        }

        // Notifications (low battery alerts)
        requestNotificationAuthorizationIfPossible()

        // Observe battery updates
        batteryObserver = NotificationCenter.default.addObserver(forName: BatteryMonitor.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleBatteryUpdate()
        }
        // Initialize status item text
        updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)

        // Restore button mapping and scroll enhancement from persisted settings.
        InputCoordinator.shared.start()
        // Discovery is observation-only and remains available while mapping is
        // off, allowing the user to choose a physical input device first.
        HIDListener.shared.start()

        // First launch: no saved language preference yet — offer the picker.
        if !L10n.hasPersistedLanguage {
            let welcome = WelcomeWindowController()
            welcome.onComplete = { [weak self] in self?.welcomeController = nil }
            welcomeController = welcome
            welcome.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConfigManager.shared.saveUserProfiles()
        InputCoordinator.shared.stop(wait: true)
        if !BuiltInTrackpadManager.releaseSystemPolicyForApplicationExit() {
            NSLog("[Trackpad] Failed to release the external-mouse policy during termination.")
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let mainVC = popover.contentViewController as? MainViewController {
                mainVC.refreshPermissionStatuses()
                let visibleHeight = (button.window?.screen?.visibleFrame.height ?? 700) - 96
                popover.contentSize = NSSize(
                    width: mainVC.preferredContentSize.width,
                    height: min(mainVC.preferredContentSize.height, visibleHeight)
                )
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updatePopoverTheme() {
        if #available(macOS 10.14, *) {
            switch ThemeManager.shared.currentMode {
            case .light:
                popover.appearance = NSAppearance(named: .vibrantLight)
            case .dark:
                popover.appearance = NSAppearance(named: .vibrantDark)
            case .system:
                popover.appearance = nil
            }
        }
    }

    private func handleBatteryUpdate() {
        let level = BatteryMonitor.shared.batteryLevel
        updateStatusItemBattery(level: level)
        guard let lvl = level else { return }
        if lvl <= 20 && !didAlertLowBattery {
            didAlertLowBattery = true
            let content = UNMutableNotificationContent()
            content.title = L10n.text("鼠标电量低")
            content.body = L10n.format("您的鼠标电量为 %d%%", lvl)
            let req = UNNotificationRequest(identifier: "vmouse.lowbattery", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
        if lvl >= 25 {
            didAlertLowBattery = false
        }
    }

    private func updateStatusItemBattery(level: Int?) {
        guard let button = statusItem.button else { return }
        let hasImage = (button.image != nil)
        if let lvl = level {
            button.title = (hasImage ? " " : "🖱️ ") + "\(lvl)%"
            button.toolTip = L10n.format("鼠标电量：%d%%", lvl)
        } else {
            button.title = hasImage ? "" : "🖱️"
            button.toolTip = L10n.text("鼠标电量：—")
        }
    }

    private func requestNotificationAuthorizationIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] Skipping authorization; bundle identifier missing (likely running via swift run).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
