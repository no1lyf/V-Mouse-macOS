import Darwin
import Foundation
import IOKit

/// Bridges the macOS Accessibility preference named “Ignore built-in
/// trackpad when mouse or wireless trackpad is present”. macOS exposes no
/// supported API for unconditionally powering a built-in trackpad on/off, so
/// this is the system-defined behavior behind the main-page control.
enum BuiltInTrackpadManager {
    // System Settings keeps this option in both the built-in and Bluetooth
    // multitouch domains. Updating only the first domain changes the plist but
    // leaves IOHID's effective setting unchanged for wireless pointing devices.
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    private static let key = "USBMouseStopsTrackpad" as CFString
    private static let appPreferenceKey = "trackpad.stopWhenExternalMousePresent"
    private static let pointerControlSettingsDidChange =
        Notification.Name("UADomainPointerControlSettingsDidChangeNotification")
    private typealias IgnoreTrackpadSetter = @convention(c) (Bool) -> Void

    /// System Settings uses this private setter to update both preferences and
    /// the live IOHID event services. Resolve it dynamically so a future macOS
    /// removal degrades to the verified preference fallback instead of making
    /// the app fail to launch because of an unresolved private symbol.
    private static let systemPolicySetter: IgnoreTrackpadSetter? = {
        let candidates = [
            "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Frameworks/UniversalAccessCore.framework/Versions/A/UniversalAccessCore",
            "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/UniversalAccess",
            "/usr/lib/libUniversalAccess.dylib",
        ]

        for candidate in candidates {
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else { continue }
            guard let symbol = dlsym(handle, "UAIgnoreTrackpadWhenExternalMouseSetEnabled") else {
                dlclose(handle)
                continue
            }
            // Keep the successful framework handle open for the process
            // lifetime; the returned function pointer is invalid after close.
            return unsafeBitCast(symbol, to: IgnoreTrackpadSetter.self)
        }
        return nil
    }()

    /// The V-Mouse-owned preference. On first use, inherit the current macOS
    /// policy so upgrading does not unexpectedly invert the visible switch.
    static var stopsTrackpadWhenExternalMousePresent: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: appPreferenceKey) != nil {
            return defaults.bool(forKey: appPreferenceKey)
        }
        let inherited = systemStopsTrackpadWhenExternalMousePresent
        defaults.set(inherited, forKey: appPreferenceKey)
        return inherited
    }

    @discardableResult
    static func setStopsTrackpadWhenExternalMousePresent(_ enabled: Bool) -> Bool {
        guard applySystemPolicy(enabled) else { return false }
        UserDefaults.standard.set(enabled, forKey: appPreferenceKey)
        return true
    }

    /// Reapply the user's saved V-Mouse choice when the app starts.
    @discardableResult
    static func applySavedPolicy() -> Bool {
        applySystemPolicy(stopsTrackpadWhenExternalMousePresent)
    }

    /// The macOS setting is global and otherwise outlives this process. Release
    /// it on normal app termination so V-Mouse cannot leave the trackpad
    /// disabled after it is no longer running. The saved app choice is kept and
    /// will be reapplied on the next launch.
    @discardableResult
    static func releaseSystemPolicyForApplicationExit() -> Bool {
        applySystemPolicy(false)
    }

    private static func applySystemPolicy(_ shouldStopTrackpad: Bool) -> Bool {
        if let setter = systemPolicySetter {
            for _ in 0..<2 {
                setter(shouldStopTrackpad)
                if waitForEffectivePolicy(shouldStopTrackpad, timeout: 0.35) {
                    return true
                }
            }
            NSLog(
                "[Trackpad] macOS setter did not propagate USBMouseStopsTrackpad=%d to IOHID.",
                shouldStopTrackpad ? 1 : 0
            )
        } else {
            NSLog("[Trackpad] macOS private setter is unavailable; using the compatibility fallback.")
        }

        // Compatibility fallback for a future macOS where the private setter
        // has moved or is unavailable. Preferences alone are not considered
        // success when a built-in trackpad exposes a live IOHID value.
        guard writePolicyPreferences(shouldStopTrackpad) else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            pointerControlSettingsDidChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return waitForEffectivePolicy(shouldStopTrackpad, timeout: 0.35)
    }

    private static func writePolicyPreferences(_ shouldStopTrackpad: Bool) -> Bool {
        var synchronized = true

        for domainName in domains {
            let domain = domainName as CFString
            CFPreferencesSetAppValue(key, NSNumber(value: shouldStopTrackpad), domain)
            synchronized = CFPreferencesAppSynchronize(domain) && synchronized
        }
        return synchronized
    }

    private static func waitForEffectivePolicy(_ expected: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let values = liveBuiltInTrackpadPolicyValues()
            if values.isEmpty {
                // A desktop Mac has no built-in trackpad to verify. In that
                // case, persistence is the only applicable state.
                if systemStopsTrackpadWhenExternalMousePresent == expected { return true }
            } else if values.allSatisfy({ $0 == expected }) {
                return true
            }
            usleep(50_000)
        } while Date() < deadline
        return false
    }

    /// Reads the effective policy from live built-in trackpad event services,
    /// not merely from preference files. Multiple services can represent the
    /// keyboard/trackpad composite device, so every observed value must agree.
    private static func liveBuiltInTrackpadPolicyValues() -> [Bool] {
        guard let matching = IOServiceMatching("IOHIDEventService") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var values: [Bool] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &unmanagedProperties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS, let unmanagedProperties else {
                continue
            }

            let properties = unmanagedProperties.takeRetainedValue() as NSDictionary
            guard isBuiltInTrackpad(properties: properties, service: service),
                  let value = effectivePolicyValue(in: properties) else {
                continue
            }
            values.append(value)
        }
        return values
    }

    private static func isBuiltInTrackpad(properties: NSDictionary, service: io_service_t) -> Bool {
        let product = (properties["Product"] as? String)?.lowercased() ?? ""
        let preferenceIdentifier = properties["ApplePreferenceIdentifier"] as? String
        let ioClass = (IOObjectCopyClass(service)?.takeRetainedValue() as String?)?.lowercased() ?? ""
        let isBuiltIn = boolValue(properties["Built-In"]) == true ||
            boolValue(properties["TrackpadEmbedded"]) == true ||
            boolValue(properties["MT Built-In"]) == true
        let isTrackpad = product.contains("trackpad") ||
            ioClass.contains("trackpad") ||
            preferenceIdentifier == "com.apple.AppleMultitouchTrackpad"
        return isBuiltIn && isTrackpad
    }

    /// Internal for deterministic XCTest coverage of registry layouts seen on
    /// both Apple Silicon and Intel trackpad services.
    static func effectivePolicyValue(in properties: NSDictionary) -> Bool? {
        if let value = boolValue(properties[key as String]) { return value }
        for containerKey in ["MultitouchPreferences", "HIDEventServiceProperties"] {
            guard let nested = properties[containerKey] as? NSDictionary else { continue }
            if let value = boolValue(nested[key as String]) { return value }
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        return nil
    }

    private static var systemStopsTrackpadWhenExternalMousePresent: Bool {
        domains.allSatisfy { domainName in
            guard let value = CFPreferencesCopyAppValue(key, domainName as CFString),
                  let number = value as? NSNumber else {
                return false
            }
            return number.boolValue
        }
    }
}
