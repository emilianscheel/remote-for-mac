import AppKit
import Combine

@MainActor
final class AppService: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var nearbyRemotes: [NearbyRemote] = []

    private let bluetooth: BluetoothServicing
    private let remoteInput: RemoteInputServicing
    private let actionDispatcher: MacActionDispatching
    private var selectedRemote: NearbyRemote?
    private var userDisconnected = false
    private var hasStarted = false

    init(
        bluetooth: BluetoothServicing = BluetoothService(),
        remoteInput: RemoteInputServicing = RemoteInputService(),
        actionDispatcher: MacActionDispatching = MacActionDispatcher()
    ) {
        self.bluetooth = bluetooth
        self.remoteInput = remoteInput
        self.actionDispatcher = actionDispatcher
        bindServices()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        PermissionsService.requestRequiredPermissions()
        remoteInput.start()
        beginScanning()
    }

    func beginScanning() {
        guard !connectionState.isConnected else { return }
        connectionState = .scanning
        bluetooth.startScanning()
    }

    func connect(to remote: NearbyRemote) {
        userDisconnected = false
        selectedRemote = remote
        connectionState = .connecting(remote.name)
        bluetooth.connect(to: remote)
    }

    func disconnect() {
        userDisconnected = true
        remoteInput.setEnabled(false)
        bluetooth.disconnect()
        selectedRemote = nil
        nearbyRemotes.removeAll()
        connectionState = .disconnected
        bluetooth.startScanning()
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        remoteInput.stop()
        bluetooth.stopScanning()
        NSApplication.shared.terminate(nil)
    }

    private func bindServices() {
        bluetooth.onRemotesChanged = { [weak self] remotes in
            guard let self else { return }
            nearbyRemotes = remotes
            if !connectionState.isConnected, selectedRemote == nil { connectionState = .scanning }
        }
        bluetooth.onConnected = { [weak self] remote in
            guard let self, !userDisconnected else { return }
            selectedRemote = remote
            connectionState = .connected(remote.name)
            remoteInput.setEnabled(true)
        }
        bluetooth.onFailure = { [weak self] message in
            guard let self else { return }
            connectionState = .failed(message)
        }
        remoteInput.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            if connected, !userDisconnected {
                let name = selectedRemote?.name ?? "Siri Remote"
                connectionState = .connected(name)
                remoteInput.setEnabled(true)
            } else if !connected, connectionState.isConnected {
                remoteInput.setEnabled(false)
                selectedRemote = nil
                connectionState = .disconnected
                bluetooth.startScanning()
            }
        }
        remoteInput.onInput = { [weak self] input in
            self?.actionDispatcher.dispatch(RemoteActionMap.action(for: input))
        }
    }
}
