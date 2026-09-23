import AppKit
import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem

struct MacActionDispatcher: MacActionDispatching {
    func dispatch(_ action: MacAction) {
        switch action {
        case .arrow(let direction):
            postKey(keyCode(for: direction))
        case .enter:
            postKey(CGKeyCode(kVK_Return))
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        case .keyboardShortcut(let shortcut):
            let event = KeyboardShortcutResolver.event(for: shortcut)
            postKey(event.keyCode, flags: event.flags)
        case .media(let key):
            postMediaKey(mediaKeyCode(for: key))
        case .missionControl:
            openApplication(at: "/System/Applications/Mission Control.app")
        case .siri:
            openApplication(at: "/System/Library/CoreServices/Siri.app")
        case .lockScreen:
            postKey(CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl])
        }
    }

    private func keyCode(for direction: Direction) -> CGKeyCode {
        let code: Int
        switch direction {
        case .up: code = kVK_UpArrow
        case .down: code = kVK_DownArrow
        case .left: code = kVK_LeftArrow
        case .right: code = kVK_RightArrow
        }
        return CGKeyCode(code)
    }

    private func mediaKeyCode(for key: MediaKey) -> Int32 {
        switch key {
        case .playPause: NX_KEYTYPE_PLAY
        case .mute: NX_KEYTYPE_MUTE
        case .volumeUp: NX_KEYTYPE_SOUND_UP
        case .volumeDown: NX_KEYTYPE_SOUND_DOWN
        case .fastForward: NX_KEYTYPE_FAST
        case .rewind: NX_KEYTYPE_REWIND
        }
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private func postMediaKey(_ code: Int32) {
        postMediaKey(code, state: 0xA)
        postMediaKey(code, state: 0xB)
    }

    private func postMediaKey(_ code: Int32, state: Int) {
        let flags = state == 0xA ? 0xA00 : 0xB00
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((code << 16) | Int32(state << 8)),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func openApplication(at path: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
    }
}

struct KeyboardEventDescriptor: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

enum KeyboardShortcutResolver {
    static func event(for shortcut: KeyboardShortcut) -> KeyboardEventDescriptor {
        KeyboardEventDescriptor(
            keyCode: keyCode(for: shortcut.key),
            flags: flags(for: shortcut.modifiers)
        )
    }

    private static func keyCode(for key: KeyboardKey) -> CGKeyCode {
        switch key {
        case .f: CGKeyCode(kVK_ANSI_F)
        case .p: CGKeyCode(kVK_ANSI_P)
        case .return: CGKeyCode(kVK_Return)
        }
    }

    private static func flags(for modifiers: Set<KeyboardModifier>) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            }
        }
    }
}
