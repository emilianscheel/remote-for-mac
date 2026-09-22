import AppKit

enum AppSoundCue: Equatable {
    case connectedReady
    case connectedNeedsPermission
    case disconnected
    case slideNavigation
}

@MainActor
final class SystemSoundService: SoundPlaying {
    private var currentSound: NSSound?

    func play(_ cue: AppSoundCue) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        currentSound?.stop()
        guard let sound = NSSound(named: name(for: cue)) else {
            NSSound.beep()
            return
        }

        sound.volume = volume(for: cue)
        currentSound = sound
        sound.play()
    }

    private func name(for cue: AppSoundCue) -> NSSound.Name {
        switch cue {
        case .connectedReady: NSSound.Name("Glass")
        case .connectedNeedsPermission: NSSound.Name("Tink")
        case .disconnected: NSSound.Name("Pop")
        case .slideNavigation: NSSound.Name("Ping")
        }
    }

    private func volume(for cue: AppSoundCue) -> Float {
        cue == .slideNavigation ? 0.25 : 1
    }
}
