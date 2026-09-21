import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: AppService

    var body: some View {
        Text(service.connectionState.statusText)
            .disabled(true)

        if service.connectionState.isConnected {
            Button("Disconnect") { service.disconnect() }
        } else {
            Menu("Connect") {
                Text("Hold Back + Volume Up for 5 seconds.")
                    .disabled(true)
                Button("Open Bluetooth Settings…") {
                    service.openBluetoothSettings()
                }
                Divider()
                if service.nearbyRemotes.isEmpty {
                    Text("Searching…")
                        .disabled(true)
                } else {
                    ForEach(service.nearbyRemotes) { remote in
                        Button(remote.name) { service.connect(to: remote) }
                    }
                }
            }
        }

        Divider()
        Button("Quit") { service.quit() }
            .keyboardShortcut("q")
    }
}
