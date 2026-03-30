import ApplicationServices
import Foundation

struct AppPermissions {
    var accessibilityEnabled: Bool
    var inputMonitoringEnabled: Bool

    /// Posting `CGEvent` / driving Ghostty requires Accessibility trust.
    var canInjectKeystrokes: Bool {
        accessibilityEnabled
    }

    /// Shown for diagnostics; not always required for posting keys.
    var hasFullInputStack: Bool {
        accessibilityEnabled && inputMonitoringEnabled
    }

    static func current() -> AppPermissions {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axEnabled = AXIsProcessTrustedWithOptions(options)
        // There is no direct public API for Input Monitoring; we infer through event tap creation.
        let inputEnabled = CGPreflightListenEventAccess()
        return AppPermissions(accessibilityEnabled: axEnabled, inputMonitoringEnabled: inputEnabled)
    }
}
