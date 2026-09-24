import Foundation
@preconcurrency import IOBluetooth
import OSLog

@MainActor
final class BluetoothService: NSObject, BluetoothServicing {
    var onRemotesChanged: (([NearbyRemote]) -> Void)?
    var onPairingCompleted: ((NearbyRemote) -> Void)?
    var onForgetCompleted: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private static let inquiryDuration: UInt8 = 10
    private static let pairingTimeout: TimeInterval = 15
    private static let forgetTimeout: TimeInterval = 10
    private static let removeSelector = NSSelectorFromString("remove")
    private static let logger = Logger(subsystem: "com.local.RemoteForMac", category: "Bluetooth")

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairer: IOBluetoothDevicePair?
    private var devices: [String: IOBluetoothDevice] = [:]
    private var discoveryDates: [String: Date] = [:]
    private var selectedAddress: String?
    private var pairingRemote: NearbyRemote?
    private var pairingTimer: Timer?
    private var forgettingDevice: IOBluetoothDevice?
    private var forgetTimer: Timer?
    private var forgetDeadline: Date?
    private var wantsScanning = false
    private var scanGeneration = 0
    private var addressesFoundByInquiry = Set<String>()

    func startScanning() {
        wantsScanning = true
        refreshPairedDevices()
        publishRemotes()
        beginInquiry()
    }

    func stopScanning() {
        wantsScanning = false
        scanGeneration += 1
        if let inquiry {
            _ = inquiry.stop()
        }
        inquiry = nil
    }

    func connect(to remote: NearbyRemote) {
        guard let device = devices[normalized(remote.id)] else {
            onFailure?("Remote is no longer nearby")
            return
        }

        stopScanning()
        selectedAddress = normalized(remote.id)

        if device.isPaired() {
            onPairingCompleted?(remoteWithCurrentName(remote, device: device, paired: true))
            return
        }

        pairingRemote = remote
        let pairer = IOBluetoothDevicePair(device: device)
        pairer?.delegate = self
        self.pairer = pairer

        guard let pairer else {
            self.pairer = nil
            pairingRemote = nil
            onFailure?("Could not start pairing with \(remote.name)")
            resumeScanningAfterFailure()
            return
        }

        let result = pairer.start()
        Self.logger.info("Pairing start address=\(remote.id, privacy: .public) name=\(remote.name, privacy: .public) result=\(result)")
        guard result == kIOReturnSuccess else {
            pairer.delegate = nil
            self.pairer = nil
            pairingRemote = nil
            onFailure?("Could not start pairing with \(remote.name)")
            resumeScanningAfterFailure()
            return
        }
        startPairingTimeout()
    }

    func forget(address: String?) {
        stopScanning()
        pairingTimer?.invalidate()
        pairingTimer = nil
        pairer?.stop()
        pairer = nil
        pairingRemote = nil

        if let address, !address.isEmpty {
            let addressKey = normalized(address)
            selectedAddress = addressKey
            if devices[addressKey] == nil,
               let device = IOBluetoothDevice(addressString: address) {
                devices[addressKey] = device
            }
        }
        refreshPairedDevices()

        guard let device = selectedDeviceForForgetting() else {
            onFailure?("Could not find the paired Apple TV Remote")
            return
        }

        guard device.responds(to: Self.removeSelector) else {
            onFailure?("This macOS version cannot forget the Apple TV Remote in the app")
            return
        }

        selectedAddress = normalized(device.addressString ?? "")
        forgettingDevice = device
        Self.logger.info("Forget start address=\(device.addressString ?? "<missing>", privacy: .public) name=\(device.name ?? "<missing>", privacy: .public) paired=\(device.isPaired()) connected=\(device.isConnected())")
        device.perform(Self.removeSelector)
        forgetDeadline = Date().addingTimeInterval(Self.forgetTimeout)
        forgetTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(forgetTimerFired),
            userInfo: nil,
            repeats: true
        )
        forgetTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        checkForgetProgress()
    }

    private func beginInquiry() {
        guard wantsScanning, inquiry == nil, pairer == nil, forgetTimer == nil else { return }

        let inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.searchType = kIOBluetoothDeviceSearchLE.rawValue
        inquiry?.inquiryLength = Self.inquiryDuration
        inquiry?.updateNewDeviceNames = true
        addressesFoundByInquiry.removeAll()
        self.inquiry = inquiry

        guard let inquiry, inquiry.start() == kIOReturnSuccess else {
            self.inquiry = nil
            onFailure?("Bluetooth is unavailable or access is denied")
            return
        }
    }

    private func restartScanningIfNeeded() {
        guard wantsScanning else { return }
        scanGeneration += 1
        let generation = scanGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, wantsScanning, scanGeneration == generation else { return }
            refreshPairedDevices()
            publishRemotes()
            beginInquiry()
        }
    }

    private func resumeScanningAfterFailure() {
        wantsScanning = true
        restartScanningIfNeeded()
    }

    private func startPairingTimeout() {
        pairingTimer?.invalidate()
        let timer = Timer(
            timeInterval: Self.pairingTimeout,
            target: self,
            selector: #selector(pairingTimedOut),
            userInfo: nil,
            repeats: false
        )
        pairingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func pairingTimedOut() {
        guard let pairer else { return }
        let device = pairer.device()
        Self.logger.error("Pairing timed out address=\(device?.addressString ?? "<missing>", privacy: .public) name=\(device?.name ?? "<missing>", privacy: .public)")
        pairer.stop()
        pairer.delegate = nil
        self.pairer = nil
        pairingRemote = nil
        pairingTimer = nil
        onFailure?("Could not pair with Apple TV Remote")
        resumeScanningAfterFailure()
    }

    private func refreshPairedDevices() {
        for device in Self.pairedDevices() where RemoteMatcher.isDiscoverableRemote(name: device.name) {
            remember(device)
        }
    }

    private static func pairedDevices() -> [IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    private func remember(_ device: IOBluetoothDevice) {
        guard let address = device.addressString, !address.isEmpty else { return }
        devices[normalized(address)] = device
    }

    private func rememberInquiryDevice(_ device: IOBluetoothDevice, markSeen: Bool = true) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let addressKey = normalized(address)
        guard RemoteMatcher.isPotentialInquiryRemote(name: device.name) else {
            addressesFoundByInquiry.remove(addressKey)
            if !device.isPaired() {
                devices.removeValue(forKey: addressKey)
                discoveryDates.removeValue(forKey: addressKey)
            }
            return
        }
        addressesFoundByInquiry.insert(addressKey)
        devices[addressKey] = device
        if markSeen {
            discoveryDates[addressKey] = Date()
        }
    }

    private func reconcileInquiryDevices(_ sender: IOBluetoothDeviceInquiry) {
        let foundDevices = sender.foundDevices() as? [IOBluetoothDevice] ?? []
        for device in foundDevices {
            rememberInquiryDevice(device, markSeen: false)
        }

        devices = devices.filter { address, device in
            device.isPaired() || addressesFoundByInquiry.contains(address)
        }
        discoveryDates = discoveryDates.filter { devices[$0.key] != nil }
    }

    private func publishRemotes() {
        var namedRemotes: [NearbyRemote] = []
        var anonymousRemotes: [(remote: NearbyRemote, seen: Date)] = []

        for (addressKey, device) in devices {
            guard let address = device.addressString,
                  RemoteMatcher.isPotentialInquiryRemote(name: device.name) else { continue }
            let remote = NearbyRemote(
                id: address,
                name: device.name.flatMap {
                    let generic = $0.caseInsensitiveCompare("Bluetooth Device") == .orderedSame
                    return RemoteMatcher.isDiscoverableRemote(name: $0) && !generic ? $0 : nil
                } ?? "Bluetooth Device",
                isPaired: device.isPaired()
            )
            if remote.name == "Bluetooth Device" && !remote.isPaired {
                anonymousRemotes.append((remote, discoveryDates[addressKey] ?? .distantPast))
            } else {
                namedRemotes.append(remote)
            }
        }

        if let newestAnonymous = anonymousRemotes.max(by: { $0.seen < $1.seen }) {
            namedRemotes.append(newestAnonymous.remote)
        }
        let remotes = namedRemotes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        onRemotesChanged?(remotes)
    }

    private func selectedDeviceForForgetting() -> IOBluetoothDevice? {
        if let selectedAddress, let selected = devices[selectedAddress], selected.isPaired() {
            return selected
        }

        let candidates = Self.pairedDevices().filter {
            RemoteMatcher.isDiscoverableRemote(name: $0.name)
        }
        let paired = candidates.first(where: { $0.isConnected() })
            ?? candidates.first {
                $0.name?.caseInsensitiveCompare("Bluetooth Device") != .orderedSame
            }
            ?? (candidates.count == 1 ? candidates.first : nil)
        if let paired { remember(paired) }
        return paired
    }

    @objc private func forgetTimerFired() {
        checkForgetProgress()
    }

    private func checkForgetProgress() {
        guard let device = forgettingDevice else { return }
        let address = normalized(device.addressString ?? "")
        let stillListed = Self.pairedDevices().contains {
            normalized($0.addressString ?? "") == address
        }

        if !device.isPaired(), !stillListed {
            Self.logger.info("Forget confirmed address=\(address, privacy: .public)")
            forgetTimer?.invalidate()
            forgetTimer = nil
            forgetDeadline = nil
            forgettingDevice = nil
            devices.removeValue(forKey: address)
            discoveryDates.removeValue(forKey: address)
            selectedAddress = nil
            publishRemotes()
            onForgetCompleted?()
            return
        }

        if let forgetDeadline, Date() >= forgetDeadline {
            Self.logger.error("Forget timed out address=\(address, privacy: .public) paired=\(device.isPaired()) listed=\(stillListed)")
            forgetTimer?.invalidate()
            forgetTimer = nil
            self.forgetDeadline = nil
            forgettingDevice = nil
            onFailure?("Could not forget the Apple TV Remote")
        }
    }

    private func finishPairing(_ device: IOBluetoothDevice, error: IOReturn) {
        let remote = pairingRemote
        pairingTimer?.invalidate()
        pairingTimer = nil
        Self.logger.info("Pairing finished address=\(device.addressString ?? "<missing>", privacy: .public) name=\(device.name ?? "<missing>", privacy: .public) error=\(error) paired=\(device.isPaired())")
        let completedPairer = pairer
        completedPairer?.delegate = nil
        pairer = nil
        pairingRemote = nil
        DispatchQueue.main.async {
            completedPairer?.stop()
        }

        guard error == kIOReturnSuccess, device.isPaired(), let remote else {
            onFailure?("Could not pair with \(remote?.name ?? "Apple TV Remote")")
            resumeScanningAfterFailure()
            return
        }

        remember(device)
        let pairedRemote = remoteWithCurrentName(remote, device: device, paired: true)
        publishRemotes()
        onPairingCompleted?(pairedRemote)
    }

    private func remoteWithCurrentName(
        _ remote: NearbyRemote,
        device: IOBluetoothDevice,
        paired: Bool
    ) -> NearbyRemote {
        NearbyRemote(
            id: device.addressString ?? remote.id,
            name: device.name ?? remote.name,
            isPaired: paired
        )
    }

    private func normalized(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }
}

extension BluetoothService: @preconcurrency IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!
    ) {
        guard let device else { return }
        rememberInquiryDevice(device)
        publishRemotes()
    }

    func deviceInquiryDeviceNameUpdated(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!,
        devicesRemaining: UInt32
    ) {
        guard let device else { return }
        rememberInquiryDevice(device)
        publishRemotes()
    }

    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!,
        error: IOReturn,
        aborted: Bool
    ) {
        guard inquiry === sender else { return }
        if let sender {
            reconcileInquiryDevices(sender)
            publishRemotes()
        }
        inquiry = nil
        if !aborted, error != kIOReturnSuccess {
            onFailure?("Bluetooth search failed")
        }
        restartScanningIfNeeded()
    }
}

extension BluetoothService: @preconcurrency IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard let pairer = sender as? IOBluetoothDevicePair else { return }
        finishPairing(pairer.device(), error: error)
    }

    func devicePairingUserConfirmationRequest(
        _ sender: Any!,
        numericValue: BluetoothNumericValue
    ) {
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        pairer?.stop()
        pairer = nil
        pairingRemote = nil
        onFailure?("The Apple TV Remote requested an unsupported PIN")
        resumeScanningAfterFailure()
    }
}
