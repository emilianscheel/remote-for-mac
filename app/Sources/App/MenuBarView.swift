import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: AppService

    var body: some View {
        Button(
            statusText,
            systemImage: service.connectionState.isConnected ? "checkmark" : "xmark"
        ) {}
        .labelStyle(.titleAndIcon)
        .disabled(true)
        .onAppear(perform: service.refreshPermissions)

        Divider()

        Button(action: service.openBluetoothSettings) {
            Label {
                Text("Open Bluetooth Settings…")
            } icon: {
                Image("BluetoothSettingsIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
        }
        .labelStyle(.titleAndIcon)

        if service.connectionState.isConnected {
            Button("Disconnect", systemImage: "xmark", action: service.disconnect)
                .labelStyle(.titleAndIcon)
        } else {
            Button("Hold 􀯷 Back and 􀁌 Volume Up for 5s") {}
                .disabled(true)

            Button("Connect to it via System Settings") {}
                .disabled(true)

            if !service.nearbyRemotes.isEmpty {
                ForEach(service.nearbyRemotes) { remote in
                    Button(remote.name, systemImage: "appletvremote.gen4") {
                        service.connect(to: remote)
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }

        Divider()

        if !service.hasDeviceControlPermission {
            Button(
                "Open Device Control Settings…",
                systemImage: "hand.raised",
                action: service.openDeviceControlSettings
            )
            .labelStyle(.titleAndIcon)
        }

        Divider()

        Button(AppVersion.current) {}
            .disabled(true)

        Button("Quit", systemImage: "power", action: service.quit)
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("q")
    }

    private var statusText: String {
        let connection = service.connectionState.isConnected ? "Connected" : "Disconnected"
        return service.hasDeviceControlPermission ? connection : "\(connection) · Permission required"
    }
}
