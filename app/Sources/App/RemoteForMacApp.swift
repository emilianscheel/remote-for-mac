import SwiftUI

@main
struct RemoteForMacApp: App {
    @StateObject private var service = AppService()

    var body: some Scene {
        MenuBarExtra("Remote for Mac", systemImage: "appletvremote.gen4") {
            MenuBarView(service: service)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: true, initial: true) { _, _ in
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                service.start()
            }
        }
    }
}
