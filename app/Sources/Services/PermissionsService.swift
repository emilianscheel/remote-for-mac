import ApplicationServices
import IOKit.hid

enum PermissionsService {
    private static let accessibilityRequestKey = "didRequestAccessibilityAccess"

    static func requestRequiredPermissions() {
        requestAccessibilityIfNeeded()

        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static var hasRequiredPermissions: Bool {
        AXIsProcessTrusted() && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: accessibilityRequestKey) else { return }

        defaults.set(true, forKey: accessibilityRequestKey)
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
