import AppKit

enum ConnectionSound: Equatable {
    case connectedReady
    case connectedNeedsPermission
    case disconnected
}

@MainActor
final class SystemConnectionSoundService: ConnectionSoundPlaying {
    private var currentSound: NSSound?

    func play(_ cue: ConnectionSound) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        currentSound?.stop()
        guard let sound = NSSound(named: name(for: cue)) else {
            NSSound.beep()
            return
        }

        currentSound = sound
        sound.play()
    }

    private func name(for cue: ConnectionSound) -> NSSound.Name {
        switch cue {
        case .connectedReady: NSSound.Name("Glass")
        case .connectedNeedsPermission: NSSound.Name("Tink")
        case .disconnected: NSSound.Name("Pop")
        }
    }
}
