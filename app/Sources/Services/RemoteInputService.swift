import Foundation
import IOKit
import IOKit.hid
import OSLog

final class RemoteInputService: RemoteInputServicing {
    private static let logger = Logger(subsystem: "com.local.RemoteForMac", category: "RemoteInput")
    var onInput: ((RemoteInput) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private var buttonEdges = ButtonEdgeDeduplicator<RemoteInput>()
    private var enabled = false
    private let touchService = TouchService()

    var connectedRemoteAddress: String? {
        devices.lazy.compactMap {
            IOHIDDeviceGetProperty($0, kIOHIDSerialNumberKey as CFString) as? String
        }.first
    }

    init() {
        touchService.onInput = { [weak self] input in self?.emit(input) }
    }

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let usagePages = [0x01, 0x09, 0x0C, 0x0B, 0x0D, 0x20, 0xFF00]
        let matches = usagePages.map {
            [
                kIOHIDVendorIDKey: RemoteMatcher.appleBluetoothVendorID,
                kIOHIDProductIDKey: RemoteMatcher.a2854ProductID,
                kIOHIDPrimaryUsagePageKey: $0
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            devices.forEach(openDevice)
            touchService.start()
        } else {
            devices.forEach(closeDevice)
            touchService.stop()
            buttonEdges.reset()
        }
    }

    func stop() {
        setEnabled(false)
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        devices.removeAll()
    }

    fileprivate func deviceAdded(_ device: IOHIDDevice) {
        guard isA2854(device), !devices.contains(where: { CFEqual($0, device) }) else { return }
        devices.append(device)
        Self.logger.info("A2854 HID added address=\(self.address(of: device) ?? "<missing>", privacy: .public)")
        if enabled { openDevice(device) }
        onConnectionChanged?(true)
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        Self.logger.info("A2854 HID removed address=\(self.address(of: device) ?? "<missing>", privacy: .public)")
        devices.removeAll { CFEqual($0, device) }
        buttonEdges.reset()
        if devices.isEmpty { onConnectionChanged?(false) }
    }

    fileprivate func handle(_ value: IOHIDValue) {
        guard enabled else { return }
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard let input = Self.input(usagePage: page, usage: usage) else { return }

        let pressed = IOHIDValueGetIntegerValue(value) != 0
        guard buttonEdges.accepts(input, pressed: pressed) else { return }
        if pressed { emit(input) }
    }

    static func input(usagePage: UInt32, usage: UInt32) -> RemoteInput? {
        switch (usagePage, usage) {
        case (0x0C, 0x42): .direction(.up)
        case (0x0C, 0x43): .direction(.down)
        case (0x0C, 0x44): .direction(.left)
        case (0x0C, 0x45): .direction(.right)
        case (0x0C, 0x80), (0x0C, 0x41), (0x09, 0x01): .center
        case (0x0C, 0x224), (0x01, 0x86), (0x01, 0x40): .back
        case (0x0C, 0x60), (0x0C, 0x223): .tv
        case (0x0C, 0x04), (0xFF00, _), (0x0B, 0x21), (0x0B, 0x2F): .siri
        case (0x0C, 0xCD): .playPause
        case (0x0C, 0xE2), (0x0C, 0x20): .mute
        case (0x0C, 0xE9): .volumeUp
        case (0x0C, 0xEA): .volumeDown
        case (0x0C, 0x30): .power
        default: nil
        }
    }

    private func isA2854(_ device: IOHIDDevice) -> Bool {
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? -1
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? -1
        return RemoteMatcher.isA2854(vendorID: vendor, productID: product)
    }

    private func address(of device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
    }

    private func openDevice(_ device: IOHIDDevice) {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else { return }
        IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private func closeDevice(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func emit(_ input: RemoteInput) {
        guard enabled else { return }
        onInput?(input)
    }
}

private func deviceAddedCallback(
    context: UnsafeMutableRawPointer?, result: IOReturn,
    sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<RemoteInputService>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
}

private func deviceRemovedCallback(
    context: UnsafeMutableRawPointer?, result: IOReturn,
    sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<RemoteInputService>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
}

private func inputValueCallback(
    context: UnsafeMutableRawPointer?, result: IOReturn,
    sender: UnsafeMutableRawPointer?, value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<RemoteInputService>.fromOpaque(context).takeUnretainedValue().handle(value)
}
