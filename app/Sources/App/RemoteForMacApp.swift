import SwiftUI

@main
struct RemoteForMacApp: App {
    @StateObject private var service = AppService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: service)
        } label: {
            Label(
                "Remote for Mac",
                systemImage: service.isReady ? "appletvremote.gen4.fill" : "appletvremote.gen4"
            )
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: true, initial: true) { _, _ in
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                service.start()
            }
        }
    }
}
