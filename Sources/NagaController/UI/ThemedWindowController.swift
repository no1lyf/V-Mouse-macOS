import Cocoa

/// Reference-counted activation-policy lease shared by every standalone
/// window. Closing one window cannot return the menu-bar app to .accessory
/// while another settings window still needs to become key.
final class ActivationPolicyCoordinator {
    static let shared = ActivationPolicyCoordinator()

    private var owners: Set<ObjectIdentifier> = []
    private var baselinePolicy: NSApplication.ActivationPolicy?

    private init() {}

    func acquire(for owner: AnyObject) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(owner)
        guard owners.insert(id).inserted else { return }
        if owners.count == 1 {
            baselinePolicy = NSApp.activationPolicy()
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        }
    }

    func release(for owner: AnyObject) {
        precondition(Thread.isMainThread)
        guard owners.remove(ObjectIdentifier(owner)) != nil, owners.isEmpty else { return }
        if let baselinePolicy, NSApp.activationPolicy() != baselinePolicy {
            NSApp.setActivationPolicy(baselinePolicy)
        }
        baselinePolicy = nil
    }
}

/// Shared behavior for the app's standalone windows: a menu-bar (.accessory)
/// app must switch to .regular while a window is shown so it can become key,
/// restore the previous policy on close, and rebuild its content when the
/// in-app language changed while it was hidden.
class ThemedWindowController: NSWindowController, NSWindowDelegate {
    private var contentLanguage = L10n.language
    private var hasPositionedWindow = false

    /// Subclasses return a freshly built content controller in the current language.
    func makeContentViewController() -> NSViewController {
        fatalError("Subclasses must override makeContentViewController()")
    }

    /// Subclasses return the window title in the current language.
    func makeTitle() -> String {
        fatalError("Subclasses must override makeTitle()")
    }

    /// Called on every show() after any rebuild; subclasses refresh live state here.
    func willShow() {}

    func show() {
        guard let window else { return }
        if !window.isVisible && contentLanguage != L10n.language {
            rebuild()
        }
        willShow()
        ActivationPolicyCoordinator.shared.acquire(for: self)
        window.delegate = self
        fitWindowToVisibleScreen(window)
        if !hasPositionedWindow {
            let autosaveName = window.frameAutosaveName
            let hasSavedFrame = !autosaveName.isEmpty &&
                UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
            if !hasSavedFrame { window.center() }
            hasPositionedWindow = true
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshInterfaceIfVisible() {
        guard let window, window.isVisible else { return }
        rebuild()
    }

    private func rebuild() {
        window?.contentViewController = makeContentViewController()
        window?.title = makeTitle()
        contentLanguage = L10n.language
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicyCoordinator.shared.release(for: self)
    }

    /// Keep every standalone settings window reachable on small displays while
    /// preserving the position selected by the user after the first showing.
    private func fitWindowToVisibleScreen(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let margin: CGFloat = 24
        let maximum = NSSize(
            width: max(240, visible.width - margin * 2),
            height: max(240, visible.height - margin * 2)
        )
        var frame = window.frame
        frame.size.width = min(frame.width, maximum.width)
        frame.size.height = min(frame.height, maximum.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        frame.origin.y = min(max(frame.origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        window.setFrame(frame, display: false)
    }
}
