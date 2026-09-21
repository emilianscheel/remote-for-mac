import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)

    var statusText: String {
        switch self {
        case .disconnected: "Not connected"
        case .scanning: "Searching…"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected to \(name)"
        case .failed(let message): message
        }
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

struct NearbyRemote: Identifiable, Equatable {
    let id: String
    let name: String
    let isPaired: Bool
}

enum Direction: Hashable {
    case up, down, left, right
}

enum RemoteInput: Hashable {
    case direction(Direction)
    case swipe(Direction)
    case center
    case back
    case tv
    case siri
    case playPause
    case mute
    case volumeUp
    case volumeDown
    case power
    case circularClockwise
    case circularCounterclockwise
}

enum MediaKey: Equatable {
    case playPause, mute, volumeUp, volumeDown, fastForward, rewind
}

enum MacAction: Equatable {
    case arrow(Direction)
    case enter
    case escape
    case media(MediaKey)
    case missionControl
    case siri
    case lockScreen
}

enum RemoteActionMap {
    static func action(for input: RemoteInput) -> MacAction {
        switch input {
        case .direction(let direction), .swipe(let direction): .arrow(direction)
        case .center: .enter
        case .back: .escape
        case .tv: .missionControl
        case .siri: .siri
        case .playPause: .media(.playPause)
        case .mute: .media(.mute)
        case .volumeUp: .media(.volumeUp)
        case .volumeDown: .media(.volumeDown)
        case .power: .lockScreen
        case .circularClockwise: .media(.fastForward)
        case .circularCounterclockwise: .media(.rewind)
        }
    }
}

struct RemoteMatcher {
    static let appleBluetoothVendorID = 0x004C
    static let a2854ProductID = 0x0315

    static func isA2854(vendorID: Int, productID: Int) -> Bool {
        vendorID == appleBluetoothVendorID && productID == a2854ProductID
    }

    static func isDiscoverableRemote(name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("siriremote")
            || name.contains("siri remote")
            || name.contains("apple tv remote")
    }
}

struct ButtonEdgeDeduplicator<Input: Hashable> {
    private var states: [Input: Bool] = [:]

    mutating func accepts(_ input: Input, pressed: Bool) -> Bool {
        guard states[input] != pressed else { return false }
        states[input] = pressed
        return true
    }

    mutating func reset() {
        states.removeAll()
    }
}
