import Foundation
import Sparkle

@MainActor
final class UpdateService: UpdateServicing {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        controller.startUpdater()
    }
}

@MainActor
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
