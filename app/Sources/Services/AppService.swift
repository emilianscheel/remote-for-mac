import AppKit
import Combine

@MainActor
final class AppService: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var nearbyRemotes: [NearbyRemote] = []
    @Published private(set) var hasDeviceControlPermission = false
    @Published private(set) var hasInputMonitoringPermission = false
    @Published private(set) var hasRequiredPermissions = false

    var isReady: Bool {
        connectionState.isConnected && hasRequiredPermissions
    }

    private let bluetooth: BluetoothServicing
    private let remoteInput: RemoteInputServicing
    private let actionDispatcher: MacActionDispatching
    private let applicationContext: ApplicationContextProviding
    private let sounds: SoundPlaying
    private let feedback: RemoteFeedbackDisplaying
    private let menuPresentation: MenuPresentationMonitoring
    private let permissions: PermissionServicing
    private let updater: UpdateServicing
    private var bluetoothRemotes: [NearbyRemote] = []
    private var hasSystemRemote = false
    private var selectedRemote: NearbyRemote?
    private var userDisconnected = false
    private var isMenuPresented = false
    private var hasStarted = false

    init(
        bluetooth: BluetoothServicing = BluetoothService(),
        remoteInput: RemoteInputServicing = RemoteInputService(),
        actionDispatcher: MacActionDispatching = MacActionDispatcher(),
        applicationContext: ApplicationContextProviding = ApplicationContextService(),
        sounds: SoundPlaying = SystemSoundService(),
        feedback: RemoteFeedbackDisplaying = RemoteFeedbackService(),
        menuPresentation: MenuPresentationMonitoring = MenuPresentationMonitor(),
        permissions: PermissionServicing = PermissionsService(),
        updater: UpdateServicing = UpdateService()
    ) {
        self.bluetooth = bluetooth
        self.remoteInput = remoteInput
        self.actionDispatcher = actionDispatcher
        self.applicationContext = applicationContext
        self.sounds = sounds
        self.feedback = feedback
        self.menuPresentation = menuPresentation
        self.permissions = permissions
        self.updater = updater
        apply(permissions.current)
        bindServices()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updater.start()
        menuPresentation.start()
        permissions.requestRequiredPermissions()
        refreshPermissions()
        permissions.startMonitoring()
        remoteInput.start()
        beginScanning()
    }

    func refreshPermissions() {
        apply(permissions.current)
    }

    func beginScanning() {
        guard !connectionState.isConnected else { return }
        transition(to: .scanning)
        bluetooth.startScanning()
    }

    func connect(to remote: NearbyRemote) {
        userDisconnected = false
        selectedRemote = remote
        transition(to: .connecting(remote.name))
        remoteInput.start()

        if remote.id == Self.systemRemote.id {
            transition(to: .connected(remote.name))
            remoteInput.setEnabled(true)
        } else {
            bluetooth.connect(to: remote)
        }
    }

    func disconnect() {
        userDisconnected = true
        remoteInput.setEnabled(false)
        bluetooth.disconnect()
        selectedRemote = nil
        transition(to: .disconnected)
        bluetooth.startScanning()
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    func openDeviceControlSettings() {
        NSWorkspace.shared.open(Self.deviceControlSettingsURL)
    }

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(Self.inputMonitoringSettingsURL)
    }

    func quit() {
        menuPresentation.stop()
        permissions.stopMonitoring()
        remoteInput.stop()
        bluetooth.stopScanning()
        NSApplication.shared.terminate(nil)
    }

    private func bindServices() {
        menuPresentation.onChange = { [weak self] isPresented in
            self?.isMenuPresented = isPresented
        }
        permissions.onChange = { [weak self] state in
            self?.apply(state)
        }
        bluetooth.onRemotesChanged = { [weak self] remotes in
            guard let self else { return }
            bluetoothRemotes = remotes
            publishNearbyRemotes()
            if !connectionState.isConnected, selectedRemote == nil { transition(to: .scanning) }
        }
        bluetooth.onConnected = { [weak self] remote in
            guard let self, !userDisconnected else { return }
            selectedRemote = remote
            transition(to: .connected(remote.name))
            remoteInput.start()
            remoteInput.setEnabled(true)
        }
        bluetooth.onFailure = { [weak self] message in
            guard let self, !userDisconnected, !connectionState.isConnected else { return }
            transition(to: .failed(message))
        }
        remoteInput.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            hasSystemRemote = connected
            publishNearbyRemotes()

            if connected, !userDisconnected {
                let remote = selectedRemote ?? Self.systemRemote
                selectedRemote = remote
                let name = remote.name
                transition(to: .connected(name))
                remoteInput.setEnabled(true)
            } else if !connected, connectionState.isConnected {
                userDisconnected = true
                remoteInput.stop()
                selectedRemote = nil
                transition(to: .disconnected)
                bluetooth.startScanning()
            }
        }
        remoteInput.onInput = { [weak self] input in
            guard let self else { return }
            if isMenuPresented, let edge = RemoteFeedbackMap.edge(for: input) {
                feedback.show(edge)
                sounds.play(.slideNavigation)
                return
            }
            let context = applicationContext.currentContext()
            let action = RemoteActionMap.action(for: input, in: context)
            if context != .standard, case .arrow(.left) = action {
                sounds.play(.slideNavigation)
            } else if context != .standard, case .arrow(.right) = action {
                sounds.play(.slideNavigation)
            }
            actionDispatcher.dispatch(action)
        }
    }

    private func apply(_ permissions: PermissionState) {
        let wasReady = isReady
        hasDeviceControlPermission = permissions.hasAccessibility
        hasInputMonitoringPermission = permissions.hasInputMonitoring
        hasRequiredPermissions = permissions.hasRequiredPermissions

        if connectionState.isConnected, !wasReady, hasRequiredPermissions {
            sounds.play(.connectedReady)
        }
    }

    private func transition(to newState: ConnectionState) {
        let wasConnected = connectionState.isConnected
        let isConnected = newState.isConnected
        connectionState = newState

        if !wasConnected, isConnected {
            sounds.play(hasRequiredPermissions ? .connectedReady : .connectedNeedsPermission)
        } else if wasConnected, !isConnected {
            sounds.play(.disconnected)
        }
    }

    private func publishNearbyRemotes() {
        var remotes = bluetoothRemotes
        if hasSystemRemote {
            remotes.removeAll {
                $0.name.compare(Self.systemRemote.name, options: .caseInsensitive) == .orderedSame
            }
            remotes.append(Self.systemRemote)
        }
        nearbyRemotes = remotes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static let systemRemote = NearbyRemote(
        id: "system-connected-remote",
        name: "Apple TV Remote",
        isPaired: true
    )

    static let deviceControlSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    static let inputMonitoringSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )!
}
