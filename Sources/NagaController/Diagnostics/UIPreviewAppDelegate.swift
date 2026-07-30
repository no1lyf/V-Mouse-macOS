import Cocoa

final class UIPreviewAppDelegate: NSObject, NSApplicationDelegate {
    enum Mode { case popover, main, hardware, mapping, scroll, tutorial, permission }
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let requestedLanguage = ProcessInfo.processInfo.environment["NAGA_UI_LANGUAGE"],
           let language = AppLanguage(rawValue: requestedLanguage) {
            L10n.setLanguage(language)
        }
        ThemeManager.shared.applyAppAppearance()
        if mode == .permission {
            NSApp.setActivationPolicy(.regular)
            PermissionManager.shared.presentUnifiedGuideIfNeeded(force: true)
            guard let guideWindow = PermissionManager.shared.guideWindowForPreview else {
                NSApp.terminate(nil)
                return
            }
            self.window = guideWindow
            if let path = ProcessInfo.processInfo.environment["NAGA_UI_SNAPSHOT_PATH"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.writeSnapshot(of: guideWindow, to: path)
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if ProcessInfo.processInfo.environment["NAGA_UI_LIVE_HID"] == "1" {
            HIDListener.shared.start(wait: true)
            if ProcessInfo.processInfo.environment["NAGA_UI_SELECT_FIRST_DEVICE"] == "1",
               let group = HIDListener.shared.deviceCandidateGroups.first(where: \.isSupported) {
                _ = HIDListener.shared.setStandardDevice(deviceKey: group.deviceKey, enabled: true)
            }
        }
        if mode == .popover {
            NSApp.setActivationPolicy(.accessory)
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.title = "N"
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 640, height: 500)
            let controller = MainViewController()
            controller.onLanguageChanged = { [weak self] in self?.rebuildPopoverPreview() }
            controller.preferredContentSize = popover.contentSize
            popover.contentViewController = controller
            if let button = item.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            statusItem = item
            self.popover = popover
            return
        }
        NSApp.setActivationPolicy(.regular)
        let controller: NSViewController
        switch mode {
        case .popover, .permission: fatalError("handled above")
        case .main:
            let main = MainViewController()
            main.onLanguageChanged = { [weak self] in self?.rebuildMainPreview() }
            controller = main
        case .mapping: controller = MappingViewController()
        case .scroll: controller = ScrollSettingsViewController()
        case .hardware: controller = HardwareDefinitionViewController(previewMode: true)
        case .tutorial: controller = TutorialViewController()
        }
        let window = NSWindow(contentViewController: controller)
        switch mode {
        case .popover, .permission: fatalError("handled above")
        case .main: window.title = "\(AppIdentity.productName) — \(L10n.text("主界面 UI 预览"))"
        case .mapping: window.title = "\(AppIdentity.productName) — \(L10n.text("按键映射 UI 预览"))"
        case .scroll: window.title = "\(AppIdentity.productName) — \(L10n.text("滚轮设置 UI 预览"))"
        case .hardware: window.title = "\(AppIdentity.productName) — \(L10n.text("鼠标按键定义 UI 预览"))"
        case .tutorial: window.title = "\(AppIdentity.productName) — \(L10n.text("帮助中心"))"
        }
        window.styleMask = [.titled, .closable, .resizable]
        switch mode {
        case .popover, .permission: fatalError("handled above")
        case .main: window.setContentSize(NSSize(width: 640, height: 500))
        case .mapping: window.setContentSize(NSSize(width: 1120, height: 820))
        case .scroll: window.setContentSize(NSSize(width: 650, height: 720))
        case .hardware: window.setContentSize(NSSize(width: 900, height: 700))
        case .tutorial: window.setContentSize(NSSize(width: 820, height: 700))
        }
        if let requestedSize = ProcessInfo.processInfo.environment["NAGA_UI_SNAPSHOT_SIZE"] {
            let parts = requestedSize.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            }
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        if let path = ProcessInfo.processInfo.environment["NAGA_UI_SNAPSHOT_PATH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.writeSnapshot(of: window, to: path)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func rebuildMainPreview() {
        guard case .main = mode, let window else { return }
        let controller = MainViewController()
        controller.onLanguageChanged = { [weak self] in self?.rebuildMainPreview() }
        window.contentViewController = controller
        window.title = "\(AppIdentity.productName) — \(L10n.text("主界面 UI 预览"))"
    }

    private func rebuildPopoverPreview() {
        guard case .popover = mode, let popover else { return }
        let controller = MainViewController()
        controller.onLanguageChanged = { [weak self] in self?.rebuildPopoverPreview() }
        controller.preferredContentSize = NSSize(width: 640, height: 500)
        popover.contentSize = controller.preferredContentSize
        popover.contentViewController = controller
    }

    private func writeSnapshot(of window: NSWindow, to path: String) {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        guard let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("UI snapshot: \(path)")
        } catch {
            fputs("UI snapshot failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
