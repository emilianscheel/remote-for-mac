import ApplicationServices
import IOKit.hid

struct PermissionState: Equatable {
    let hasAccessibility: Bool
    let hasInputMonitoring: Bool

    var hasRequiredPermissions: Bool {
        hasAccessibility && hasInputMonitoring
    }
}

@MainActor
final class PermissionsService: PermissionServicing {
    private static let accessibilityRequestKey = "didRequestAccessibilityAccess"

    var onChange: ((PermissionState) -> Void)?

    var current: PermissionState {
        PermissionState(
            hasAccessibility: AXIsProcessTrusted(),
            hasInputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        )
    }

    private var timer: Timer?
    private var lastState: PermissionState?

    func requestRequiredPermissions() {
        requestAccessibilityIfNeeded()

        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    func startMonitoring() {
        guard timer == nil else { return }
        publishIfChanged()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishIfChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func publishIfChanged() {
        let state = current
        guard state != lastState else { return }
        lastState = state
        onChange?(state)
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.accessibilityRequestKey) else { return }

        defaults.set(true, forKey: Self.accessibilityRequestKey)
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
