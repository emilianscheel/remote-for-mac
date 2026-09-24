import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case forgetting(String)
    case failed(String)

    var statusText: String {
        isConnected ? "Connected" : "Disconnected"
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    var isForgetting: Bool {
        if case .forgetting = self { true } else { false }
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

enum ApplicationContext: Hashable {
    case standard
    case keynote
    case powerPoint
    case preview
    case safari
    case figma
}

enum KeyboardKey: Equatable {
    case f
    case p
    case `return`
}

enum KeyboardModifier: Hashable {
    case command
    case control
    case option
}

struct KeyboardShortcut: Equatable {
    let key: KeyboardKey
    let modifiers: Set<KeyboardModifier>
}

enum MacAction: Equatable {
    case arrow(Direction)
    case enter
    case escape
    case keyboardShortcut(KeyboardShortcut)
    case media(MediaKey)
    case missionControl
    case siri
    case lockScreen
}

enum RemoteActionMap {
    private static let slideNavigation: [RemoteInput: MacAction] = [
        .direction(.up): .arrow(.right),
        .swipe(.up): .arrow(.right),
        .direction(.down): .arrow(.left),
        .swipe(.down): .arrow(.left),
    ]

    private static let presentationOverrides: [ApplicationContext: [RemoteInput: MacAction]] = [
        .keynote: [
            .playPause: .keyboardShortcut(
                KeyboardShortcut(key: .p, modifiers: [.command, .option])
            ),
            .back: .escape,
        ],
        .powerPoint: [
            .playPause: .keyboardShortcut(
                KeyboardShortcut(key: .return, modifiers: [.command])
            ),
            .back: .escape,
        ],
        .preview: [
            .playPause: .keyboardShortcut(
                KeyboardShortcut(key: .f, modifiers: [.command, .control])
            ),
        ],
        .safari: [
            .playPause: .keyboardShortcut(
                KeyboardShortcut(key: .f, modifiers: [.command, .control])
            ),
        ],
        .figma: [
            .playPause: .keyboardShortcut(
                KeyboardShortcut(key: .return, modifiers: [.command, .option])
            ),
        ],
    ]

    static func action(for input: RemoteInput, in context: ApplicationContext = .standard) -> MacAction {
        if let action = slideNavigation[input] {
            return action
        }

        if let action = presentationOverrides[context]?[input] {
            return action
        }

        return switch input {
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

enum RemoteFeedbackEdge: Equatable {
    case left
    case right
}

enum RemoteFeedbackMap {
    static func edge(for input: RemoteInput) -> RemoteFeedbackEdge? {
        switch input {
        case .direction(.left), .swipe(.left), .direction(.down), .swipe(.down): .left
        case .direction(.right), .swipe(.right), .direction(.up), .swipe(.up): .right
        default: nil
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
        guard let name else { return false }
        let lowercaseName = name.lowercased()
        return lowercaseName.contains("siriremote")
            || lowercaseName.contains("siri remote")
            || lowercaseName.contains("apple tv remote")
            || lowercaseName == "bluetooth device"
            || isLikelyAppleSerial(name)
    }

    static func isPotentialInquiryRemote(name: String?) -> Bool {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return isDiscoverableRemote(name: name)
    }

    static func isLikelyAppleSerial(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count == 12,
              name == name.uppercased(),
              name.unicodeScalars.allSatisfy({
                  CharacterSet.uppercaseLetters.contains($0)
                      || CharacterSet.decimalDigits.contains($0)
              }),
              name.unicodeScalars.contains(where: CharacterSet.uppercaseLetters.contains),
              name.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) else {
            return false
        }
        return true
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
