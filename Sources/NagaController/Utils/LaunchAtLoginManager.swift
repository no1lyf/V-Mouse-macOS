import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService (macOS 13+, matches this target's
/// minimum deployment). No helper app or login-item bundle is needed: the
/// main app registers itself directly.
enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting enabled state. Registration can fail (e.g. the
    /// app is not in /Applications, or the user denies it in System
    /// Settings), so the caller must re-read isEnabled rather than assume
    /// the requested state took effect.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return true }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status != .enabled { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[LaunchAtLogin] Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)")
            return false
        }
    }
}
