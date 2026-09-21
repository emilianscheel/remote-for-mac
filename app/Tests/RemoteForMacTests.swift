import XCTest
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
        XCTAssertEqual(input.stopCount, 1)
        XCTAssertEqual(bluetooth.disconnectCount, 1)
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
}

private final class BluetoothMock: BluetoothServicing {
    var onRemotesChanged: (([NearbyRemote]) -> Void)?
    var onConnected: ((NearbyRemote) -> Void)?
    var onFailure: ((String) -> Void)?
    var startScanningCount = 0
    var disconnectCount = 0

    func startScanning() { startScanningCount += 1 }
    func stopScanning() {}
    func connect(to remote: NearbyRemote) {}
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

private struct ApplicationContextMock: ApplicationContextProviding {
    let context: ApplicationContext
    func currentContext() -> ApplicationContext { context }
}
