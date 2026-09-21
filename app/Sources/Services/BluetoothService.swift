import CoreBluetooth
import Foundation

final class BluetoothService: NSObject, BluetoothServicing {
    var onRemotesChanged: (([NearbyRemote]) -> Void)?
    var onConnected: ((NearbyRemote) -> Void)?
    var onFailure: ((String) -> Void)?

    private static let knownPeripheralIDsKey = "knownRemotePeripheralIDs"
    private static var hidService: CBUUID { CBUUID(string: "1812") }
    private static var reportMapCharacteristic: CBUUID { CBUUID(string: "2A4B") }

    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var names: [UUID: String] = [:]
    private var selectedID: UUID?
    private var wantsScanning = false

    func startScanning() {
        wantsScanning = true
        _ = central
        restoreKnownRemotes()
        beginScanWhenReady()
    }

    func stopScanning() {
        wantsScanning = false
        central.stopScan()
    }

    func connect(to remote: NearbyRemote) {
        guard let id = UUID(uuidString: remote.id), let peripheral = peripherals[id] else {
            onFailure?("Remote is no longer nearby")
            return
        }

        stopScanning()
        selectedID = id
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func disconnect() {
        guard let selectedID, let peripheral = peripherals[selectedID] else { return }
        central.cancelPeripheralConnection(peripheral)
        self.selectedID = nil
    }

    private func beginScanWhenReady() {
        guard wantsScanning else { return }

        switch central.state {
        case .poweredOn:
            if !central.isScanning {
                central.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            }
        case .poweredOff:
            onFailure?("Bluetooth is off")
        case .unauthorized:
            onFailure?("Allow Bluetooth access")
        case .unsupported:
            onFailure?("Bluetooth unavailable")
        case .resetting, .unknown:
            break
        @unknown default:
            onFailure?("Bluetooth unavailable")
        }
    }

    private func restoreKnownRemotes() {
        let ids = knownPeripheralIDs
        guard !ids.isEmpty else { return }

        for peripheral in central.retrievePeripherals(withIdentifiers: Array(ids)) {
            guard let name = peripheral.name, RemoteMatcher.isDiscoverableRemote(name: name) else { continue }
            remember(peripheral, name: name)
        }
    }

    private func remember(_ peripheral: CBPeripheral, name: String) {
        peripherals[peripheral.identifier] = peripheral
        names[peripheral.identifier] = name
        publishRemotes()
    }

    private func publishRemotes() {
        let known = knownPeripheralIDs
        let remotes = peripherals.compactMap { id, _ -> NearbyRemote? in
            guard let name = names[id] else { return nil }
            return NearbyRemote(id: id.uuidString, name: name, isPaired: known.contains(id))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onRemotesChanged?(remotes)
    }

    private var knownPeripheralIDs: Set<UUID> {
        get {
            let values = UserDefaults.standard.stringArray(forKey: Self.knownPeripheralIDsKey) ?? []
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString).sorted(), forKey: Self.knownPeripheralIDsKey)
        }
    }

    private func saveAsKnown(_ id: UUID) {
        var ids = knownPeripheralIDs
        ids.insert(id)
        knownPeripheralIDs = ids
    }
}

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        beginScanWhenReady()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard RemoteMatcher.isDiscoverableRemote(name: name), let name else { return }
        remember(peripheral, name: name)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        saveAsKnown(peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices([Self.hidService])

        let name = names[peripheral.identifier] ?? peripheral.name ?? "Siri Remote"
        let remote = NearbyRemote(id: peripheral.identifier.uuidString, name: name, isPaired: true)
        publishRemotes()
        onConnected?(remote)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onFailure?("Could not connect to \(names[peripheral.identifier] ?? "Siri Remote")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard selectedID == peripheral.identifier else { return }
        selectedID = nil
        if let error { onFailure?("Remote disconnected: \(error.localizedDescription)") }
    }
}

extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            onFailure?("Could not read remote services")
            return
        }

        guard let hidService = peripheral.services?.first(where: { $0.uuid == Self.hidService }) else {
            onFailure?("Unsupported remote")
            return
        }
        peripheral.discoverCharacteristics(nil, for: hidService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            onFailure?("Could not initialize remote")
            return
        }

        // Reading the protected HID report map asks macOS to establish the bond.
        // Once bonded, the system HID driver exposes the remote through IOHIDManager.
        if let reportMap = service.characteristics?.first(where: { $0.uuid == Self.reportMapCharacteristic }) {
            peripheral.readValue(for: reportMap)
        }
    }
}
