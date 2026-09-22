import XCTest
import Carbon.HIToolbox
import CoreGraphics
@testable import RemoteForMac

final class RemoteForMacTests: XCTestCase {
    func testA2854MatchingIsExact() {
        XCTAssertTrue(RemoteMatcher.isA2854(vendorID: 0x004C, productID: 0x0315))
        XCTAssertFalse(RemoteMatcher.isA2854(vendorID: 0x004C, productID: 0x030E))
        XCTAssertFalse(RemoteMatcher.isA2854(vendorID: 0x05AC, productID: 0x0315))
    }

    func testDiscoveryNameFiltering() {
        XCTAssertTrue(RemoteMatcher.isDiscoverableRemote(name: "Siri Remote"))
        XCTAssertTrue(RemoteMatcher.isDiscoverableRemote(name: "siriremote"))
        XCTAssertTrue(RemoteMatcher.isDiscoverableRemote(name: "Apple TV Remote"))
        XCTAssertFalse(RemoteMatcher.isDiscoverableRemote(name: "Magic Keyboard"))
    }

    func testEveryInputHasTheExpectedAction() {
        XCTAssertEqual(RemoteActionMap.action(for: .direction(.left)), .arrow(.left))
        XCTAssertEqual(RemoteActionMap.action(for: .swipe(.right)), .arrow(.right))
        XCTAssertEqual(RemoteActionMap.action(for: .center), .enter)
        XCTAssertEqual(RemoteActionMap.action(for: .back), .escape)
        XCTAssertEqual(RemoteActionMap.action(for: .tv), .missionControl)
        XCTAssertEqual(RemoteActionMap.action(for: .siri), .siri)
        XCTAssertEqual(RemoteActionMap.action(for: .playPause), .media(.playPause))
        XCTAssertEqual(RemoteActionMap.action(for: .mute), .media(.mute))
        XCTAssertEqual(RemoteActionMap.action(for: .volumeUp), .media(.volumeUp))
        XCTAssertEqual(RemoteActionMap.action(for: .volumeDown), .media(.volumeDown))
        XCTAssertEqual(RemoteActionMap.action(for: .power), .lockScreen)
        XCTAssertEqual(RemoteActionMap.action(for: .circularClockwise), .media(.fastForward))
        XCTAssertEqual(RemoteActionMap.action(for: .circularCounterclockwise), .media(.rewind))
    }

    func testKeynoteOverridesAreDeclarativeAndContextual() {
        let playShortcut = KeyboardShortcut(key: .p, modifiers: [.command, .option])

        XCTAssertEqual(
            RemoteActionMap.action(for: .playPause, in: .keynote),
            .keyboardShortcut(playShortcut)
        )
        XCTAssertEqual(RemoteActionMap.action(for: .back, in: .keynote), .escape)
        XCTAssertEqual(RemoteActionMap.action(for: .playPause, in: .standard), .media(.playPause))
    }

    func testPresentationApplicationDetection() {
        XCTAssertEqual(ApplicationContextService.context(for: "com.apple.Keynote"), .keynote)
        XCTAssertEqual(ApplicationContextService.context(for: "com.apple.iWork.Keynote"), .keynote)
        XCTAssertEqual(ApplicationContextService.context(for: "com.microsoft.Powerpoint"), .powerPoint)
        XCTAssertEqual(ApplicationContextService.context(for: "com.apple.TextEdit"), .standard)
        XCTAssertEqual(ApplicationContextService.context(for: nil), .standard)
    }

    func testPowerPointOverridesAreDeclarativeAndContextual() {
        let playShortcut = KeyboardShortcut(key: .return, modifiers: [.command])

        XCTAssertEqual(
            RemoteActionMap.action(for: .playPause, in: .powerPoint),
            .keyboardShortcut(playShortcut)
        )
        XCTAssertEqual(RemoteActionMap.action(for: .back, in: .powerPoint), .escape)
        XCTAssertEqual(RemoteActionMap.action(for: .direction(.right), in: .powerPoint), .arrow(.right))
    }

    func testVerticalPresentationNavigationMovesSlides() {
        for context in [ApplicationContext.keynote, .powerPoint] {
            XCTAssertEqual(RemoteActionMap.action(for: .direction(.up), in: context), .arrow(.right))
            XCTAssertEqual(RemoteActionMap.action(for: .swipe(.up), in: context), .arrow(.right))
            XCTAssertEqual(RemoteActionMap.action(for: .direction(.down), in: context), .arrow(.left))
            XCTAssertEqual(RemoteActionMap.action(for: .swipe(.down), in: context), .arrow(.left))
        }
    }

    func testRemoteFeedbackEdgesMatchSlideDirection() {
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .direction(.left)), .left)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .direction(.down)), .left)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .direction(.right)), .right)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .direction(.up)), .right)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .swipe(.left)), .left)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .swipe(.down)), .left)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .swipe(.right)), .right)
        XCTAssertEqual(RemoteFeedbackMap.edge(for: .swipe(.up)), .right)
        XCTAssertNil(RemoteFeedbackMap.edge(for: .playPause))
    }

    func testPresentationShortcutKeyCodesAndModifiers() {
        let keynote = KeyboardShortcutResolver.event(
            for: KeyboardShortcut(key: .p, modifiers: [.command, .option])
        )
        XCTAssertEqual(keynote.keyCode, CGKeyCode(kVK_ANSI_P))
        XCTAssertEqual(keynote.flags, [.maskCommand, .maskAlternate])
        XCTAssertFalse(keynote.flags.contains(.maskShift))

        let powerPoint = KeyboardShortcutResolver.event(
            for: KeyboardShortcut(key: .return, modifiers: [.command])
        )
        XCTAssertEqual(powerPoint.keyCode, CGKeyCode(kVK_Return))
        XCTAssertEqual(powerPoint.flags, [.maskCommand])
    }

    func testHIDUsages() {
        XCTAssertEqual(RemoteInputService.input(usagePage: 0x0C, usage: 0x44), .direction(.left))
        XCTAssertEqual(RemoteInputService.input(usagePage: 0x0C, usage: 0xE2), .mute)
        XCTAssertEqual(RemoteInputService.input(usagePage: 0x0C, usage: 0x30), .power)
        XCTAssertNil(RemoteInputService.input(usagePage: 0x01, usage: 0x02))
    }

    func testConnectionStatusText() {
        XCTAssertEqual(ConnectionState.disconnected.statusText, "Not connected")
        XCTAssertEqual(ConnectionState.scanning.statusText, "Searching…")
        XCTAssertEqual(ConnectionState.connecting("Living Room").statusText, "Connecting to Living Room…")
        XCTAssertEqual(ConnectionState.connected("Living Room").statusText, "Connected to Living Room")
    }

    func testMirroredHIDEdgesAreDeduplicated() {
        var deduplicator = ButtonEdgeDeduplicator<RemoteInput>()
        XCTAssertTrue(deduplicator.accepts(.playPause, pressed: true))
        XCTAssertFalse(deduplicator.accepts(.playPause, pressed: true))
        XCTAssertTrue(deduplicator.accepts(.playPause, pressed: false))
        XCTAssertFalse(deduplicator.accepts(.playPause, pressed: false))
        deduplicator.reset()
        XCTAssertTrue(deduplicator.accepts(.playPause, pressed: true))
    }

    @MainActor
    func testAppServiceConnectionLifecycleAndMenuState() {
        let bluetooth = BluetoothMock()
        let input = RemoteInputMock()
        let dispatcher = ActionDispatcherMock()
        let service = AppService(
            bluetooth: bluetooth,
            remoteInput: input,
            actionDispatcher: dispatcher
        )
        let remote = NearbyRemote(id: "remote", name: "Siri Remote", isPaired: true)

        service.beginScanning()
        XCTAssertEqual(service.connectionState, .scanning)
        XCTAssertFalse(service.connectionState.isConnected)
        XCTAssertEqual(bluetooth.startScanningCount, 1)

        bluetooth.onRemotesChanged?([remote])
        XCTAssertEqual(service.nearbyRemotes, [remote])

        service.connect(to: remote)
        XCTAssertEqual(service.connectionState, .connecting("Siri Remote"))
        XCTAssertEqual(input.startCount, 1)
        bluetooth.onConnected?(remote)
        XCTAssertEqual(service.connectionState, .connected("Siri Remote"))
        XCTAssertTrue(service.connectionState.isConnected)
        XCTAssertEqual(input.enabledValues.last, true)

        input.onInput?(.playPause)
        XCTAssertEqual(dispatcher.actions, [.media(.playPause)])

        service.disconnect()
        XCTAssertEqual(service.connectionState, .disconnected)
        XCTAssertFalse(service.connectionState.isConnected)
        XCTAssertEqual(input.enabledValues.last, false)
        XCTAssertEqual(input.stopCount, 0)
        XCTAssertEqual(bluetooth.disconnectCount, 1)
        XCTAssertEqual(service.nearbyRemotes, [remote])

        bluetooth.onFailure?("Cancelled")
        XCTAssertEqual(service.connectionState, .disconnected)
    }

    @MainActor
    func testSystemConnectedRemoteRemainsAvailableForReconnect() {
        let bluetooth = BluetoothMock()
        let input = RemoteInputMock()
        let service = AppService(
            bluetooth: bluetooth,
            remoteInput: input,
            actionDispatcher: ActionDispatcherMock()
        )

        input.onConnectionChanged?(true)
        XCTAssertEqual(service.connectionState, .connected("Apple TV Remote"))
        XCTAssertEqual(service.nearbyRemotes.map(\.name), ["Apple TV Remote"])

        service.disconnect()
        XCTAssertEqual(service.connectionState, .disconnected)
        XCTAssertEqual(service.nearbyRemotes.map(\.name), ["Apple TV Remote"])
        XCTAssertEqual(input.enabledValues.last, false)

        let remote = try! XCTUnwrap(service.nearbyRemotes.first)
        service.connect(to: remote)
        XCTAssertEqual(service.connectionState, .connected("Apple TV Remote"))
        XCTAssertEqual(input.enabledValues.last, true)
        XCTAssertTrue(bluetooth.connectedRemotes.isEmpty)
    }

    @MainActor
    func testSystemConnectedRemoteWinsOverDuplicateBluetoothEntry() {
        let bluetooth = BluetoothMock()
        let input = RemoteInputMock()
        let service = AppService(
            bluetooth: bluetooth,
            remoteInput: input,
            actionDispatcher: ActionDispatcherMock()
        )
        let bluetoothEntry = NearbyRemote(
            id: UUID().uuidString,
            name: "Apple TV Remote",
            isPaired: true
        )

        bluetooth.onRemotesChanged?([bluetoothEntry])
        input.onConnectionChanged?(true)

        let availableRemote = try! XCTUnwrap(service.nearbyRemotes.first)
        XCTAssertEqual(service.nearbyRemotes.count, 1)
        XCTAssertEqual(availableRemote.id, "system-connected-remote")

        service.disconnect()
        service.connect(to: availableRemote)

        XCTAssertEqual(service.connectionState, .connected("Apple TV Remote"))
        XCTAssertTrue(bluetooth.connectedRemotes.isEmpty)
        XCTAssertEqual(Array(input.enabledValues.suffix(2)), [false, true])
    }

    @MainActor
    func testConnectionSoundsReflectReadinessWithoutDuplicates() {
        let permissions = PermissionMock(
            current: PermissionState(hasAccessibility: false, hasInputMonitoring: false)
        )
        let sounds = SoundMock()
        let bluetooth = BluetoothMock()
        let input = RemoteInputMock()
        let service = AppService(
            bluetooth: bluetooth,
            remoteInput: input,
            actionDispatcher: ActionDispatcherMock(),
            sounds: sounds,
            permissions: permissions
        )
        let remote = NearbyRemote(id: "remote", name: "Siri Remote", isPaired: true)

        bluetooth.onConnected?(remote)
        input.onConnectionChanged?(true)
        XCTAssertEqual(sounds.played, [.connectedNeedsPermission])

        permissions.send(PermissionState(hasAccessibility: true, hasInputMonitoring: true))
        XCTAssertEqual(sounds.played, [.connectedNeedsPermission, .connectedReady])

        service.disconnect()
        service.disconnect()
        XCTAssertEqual(sounds.played, [.connectedNeedsPermission, .connectedReady, .disconnected])
    }

    @MainActor
    func testReadyRemoteUsesReadyConnectionSound() {
        let permissions = PermissionMock(
            current: PermissionState(hasAccessibility: true, hasInputMonitoring: true)
        )
        let sounds = SoundMock()
        let input = RemoteInputMock()
        let service = AppService(
            bluetooth: BluetoothMock(),
            remoteInput: input,
            actionDispatcher: ActionDispatcherMock(),
            sounds: sounds,
            permissions: permissions
        )

        input.onConnectionChanged?(true)

        XCTAssertEqual(sounds.played, [.connectedReady])
        _ = service
    }

    @MainActor
    func testAppServiceUsesTheForegroundApplicationContext() {
        let input = RemoteInputMock()
        let dispatcher = ActionDispatcherMock()
        let service = AppService(
            bluetooth: BluetoothMock(),
            remoteInput: input,
            actionDispatcher: dispatcher,
            applicationContext: ApplicationContextMock(context: .keynote)
        )

        input.onInput?(.playPause)

        XCTAssertEqual(
            dispatcher.actions,
            [.keyboardShortcut(KeyboardShortcut(key: .p, modifiers: [.command, .option]))]
        )
        _ = service
    }

    @MainActor
    func testMenuPresentationConsumesNavigationForVisualFeedback() {
        let input = RemoteInputMock()
        let dispatcher = ActionDispatcherMock()
        let feedback = FeedbackMock()
        let sounds = SoundMock()
        let menuPresentation = MenuPresentationMonitorMock()
        let service = AppService(
            bluetooth: BluetoothMock(),
            remoteInput: input,
            actionDispatcher: dispatcher,
            sounds: sounds,
            feedback: feedback,
            menuPresentation: menuPresentation
        )

        menuPresentation.send(true)
        input.onInput?(.direction(.up))
        input.onInput?(.direction(.down))
        XCTAssertEqual(feedback.edges, [.right, .left])
        XCTAssertEqual(sounds.played, [.slideNavigation, .slideNavigation])
        XCTAssertTrue(dispatcher.actions.isEmpty)

        menuPresentation.send(false)
        input.onInput?(.direction(.up))
        XCTAssertEqual(dispatcher.actions, [.arrow(.up)])
        _ = service
    }

    @MainActor
    func testLivePresentationNavigationDoesNotPlayFeedbackSound() {
        let input = RemoteInputMock()
        let sounds = SoundMock()
        let service = AppService(
            bluetooth: BluetoothMock(),
            remoteInput: input,
            actionDispatcher: ActionDispatcherMock(),
            applicationContext: ApplicationContextMock(context: .keynote),
            sounds: sounds
        )
        let navigationInputs: [RemoteInput] = [
            .direction(.left), .direction(.right), .direction(.up), .direction(.down),
            .swipe(.left), .swipe(.right), .swipe(.up), .swipe(.down),
        ]

        navigationInputs.forEach { input.onInput?($0) }

        XCTAssertTrue(sounds.played.isEmpty)
        _ = service
    }

    @MainActor
    func testAppServiceTracksPermissionRevocationAndStartsServicesOnce() {
        let permissions = PermissionMock(
            current: PermissionState(hasAccessibility: true, hasInputMonitoring: true)
        )
        let updater = UpdateMock()
        let menuPresentation = MenuPresentationMonitorMock()
        let service = AppService(
            bluetooth: BluetoothMock(),
            remoteInput: RemoteInputMock(),
            actionDispatcher: ActionDispatcherMock(),
            menuPresentation: menuPresentation,
            permissions: permissions,
            updater: updater
        )

        XCTAssertTrue(service.hasDeviceControlPermission)
        XCTAssertTrue(service.hasInputMonitoringPermission)
        XCTAssertTrue(service.hasRequiredPermissions)

        service.start()
        service.start()
        XCTAssertEqual(permissions.requestCount, 1)
        XCTAssertEqual(permissions.startMonitoringCount, 1)
        XCTAssertEqual(updater.startCount, 1)
        XCTAssertEqual(menuPresentation.startCount, 1)

        permissions.send(PermissionState(hasAccessibility: false, hasInputMonitoring: true))
        XCTAssertFalse(service.hasDeviceControlPermission)
        XCTAssertTrue(service.hasInputMonitoringPermission)
        XCTAssertFalse(service.hasRequiredPermissions)

        permissions.send(PermissionState(hasAccessibility: true, hasInputMonitoring: false))
        XCTAssertTrue(service.hasDeviceControlPermission)
        XCTAssertFalse(service.hasInputMonitoringPermission)
        XCTAssertFalse(service.hasRequiredPermissions)

        permissions.send(PermissionState(hasAccessibility: true, hasInputMonitoring: true))
        XCTAssertTrue(service.hasDeviceControlPermission)
        XCTAssertTrue(service.hasInputMonitoringPermission)
        XCTAssertTrue(service.hasRequiredPermissions)
    }

    @MainActor
    func testPermissionSettingsDestinations() {
        XCTAssertEqual(
            AppService.deviceControlSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(
            AppService.inputMonitoringSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    @MainActor
    func testReleaseVersionIsExposedToTheMenu() {
        XCTAssertEqual(AppVersion.current, "1.4")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Double,
            86_400
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://remote-for-mac.vercel.app/appcast.xml"
        )
    }
}

private final class BluetoothMock: BluetoothServicing {
    var onRemotesChanged: (([NearbyRemote]) -> Void)?
    var onConnected: ((NearbyRemote) -> Void)?
    var onFailure: ((String) -> Void)?
    var startScanningCount = 0
    var disconnectCount = 0
    var connectedRemotes: [NearbyRemote] = []

    func startScanning() { startScanningCount += 1 }
    func stopScanning() {}
    func connect(to remote: NearbyRemote) { connectedRemotes.append(remote) }
    func disconnect() { disconnectCount += 1 }
}

private final class RemoteInputMock: RemoteInputServicing {
    var onConnectionChanged: ((Bool) -> Void)?
    var onInput: ((RemoteInput) -> Void)?
    var enabledValues: [Bool] = []
    var startCount = 0
    var stopCount = 0

    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        enabledValues.append(false)
    }
    func setEnabled(_ enabled: Bool) { enabledValues.append(enabled) }
}

private final class ActionDispatcherMock: MacActionDispatching {
    var actions: [MacAction] = []
    func dispatch(_ action: MacAction) { actions.append(action) }
}

@MainActor
private final class SoundMock: SoundPlaying {
    var played: [AppSoundCue] = []
    func play(_ cue: AppSoundCue) { played.append(cue) }
}

private struct ApplicationContextMock: ApplicationContextProviding {
    let context: ApplicationContext
    func currentContext() -> ApplicationContext { context }
}

@MainActor
private final class FeedbackMock: RemoteFeedbackDisplaying {
    var edges: [RemoteFeedbackEdge] = []
    func show(_ edge: RemoteFeedbackEdge) { edges.append(edge) }
}

@MainActor
private final class MenuPresentationMonitorMock: MenuPresentationMonitoring {
    var onChange: ((Bool) -> Void)?
    var startCount = 0

    func start() { startCount += 1 }
    func stop() { onChange?(false) }
    func send(_ isPresented: Bool) { onChange?(isPresented) }
}

@MainActor
private final class PermissionMock: PermissionServicing {
    var current: PermissionState
    var onChange: ((PermissionState) -> Void)?
    var requestCount = 0
    var startMonitoringCount = 0

    init(current: PermissionState) {
        self.current = current
    }

    func requestRequiredPermissions() { requestCount += 1 }
    func startMonitoring() { startMonitoringCount += 1 }
    func stopMonitoring() {}

    func send(_ state: PermissionState) {
        current = state
        onChange?(state)
    }
}

@MainActor
private final class UpdateMock: UpdateServicing {
    var startCount = 0
    func start() { startCount += 1 }
}
