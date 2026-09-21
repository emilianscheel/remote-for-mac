import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: AppService

    var body: some View {
        Text(service.connectionState.isConnected ? "Connected" : "Disconnected")
            .disabled(true)

        Divider()

        if service.connectionState.isConnected {
            Button(action: service.disconnect) {
                Label("Disconnect", systemImage: "xmark.circle")
            }
        } else {
            Text("Hold Back + Volume Up for 5 seconds.")
                .disabled(true)

            Button(action: service.openBluetoothSettings) {
                Label("Open Bluetooth Settings…", systemImage: "gearshape")
            }

            if service.nearbyRemotes.isEmpty {
                Label("Searching…", systemImage: "dot.radiowaves.left.and.right")
                    .disabled(true)
            } else {
                ForEach(service.nearbyRemotes) { remote in
                    Button {
                        service.connect(to: remote)
                    } label: {
                        Label(remote.name, systemImage: "appletvremote.gen4")
                    }
                }
            }
        }

        Divider()

        Button(action: service.quit) {
            Label("Quit", systemImage: "power")
        }
            .keyboardShortcut("q")
    }
}
