import Cocoa

final class MappingWindowController: ThemedWindowController {
    static let shared = MappingWindowController()

    private init() {
        let vc = MappingViewController()
        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "\(AppIdentity.productName) — \(L10n.text("按键映射"))"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1120, height: 820))
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.setFrameAutosaveName("NagaController.MappingWindow")
        window.isReleasedWhenClosed = false

        // Note: Do not wrap vc.view here. MappingViewController already draws a full-size
        // NSVisualEffectView background. Wrapping again caused a self-subview cycle and hang.
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeContentViewController() -> NSViewController { MappingViewController() }
    override func makeTitle() -> String { "\(AppIdentity.productName) — \(L10n.text("按键映射"))" }

    /// Deep link from the status-bar popover: open the editor with one
    /// device pre-selected in the sidebar.
    func show(selectingDeviceKey deviceKey: String) {
        show()
        (window?.contentViewController as? MappingViewController)?.select(deviceKey: deviceKey)
    }
}
