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

        if service.connectionState.isConnected {
            Button("Disconnect", systemImage: "xmark", action: service.disconnect)
                .labelStyle(.titleAndIcon)
        } else {
            Button("Hold Back + Volume Up for 5 seconds.", systemImage: "info") {}
                .labelStyle(.titleAndIcon)
                .disabled(true)

            if service.nearbyRemotes.isEmpty {
                Button("Searching…", systemImage: "dot.radiowaves.left.and.right") {}
                    .labelStyle(.titleAndIcon)
                    .disabled(true)
            } else {
                ForEach(service.nearbyRemotes) { remote in
                    Button(remote.name, systemImage: "appletvremote.gen4") {
                        service.connect(to: remote)
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }

        Divider()

        if !service.connectionState.isConnected {
            Button("Open Bluetooth Settings…", systemImage: "gearshape", action: service.openBluetoothSettings)
                .labelStyle(.titleAndIcon)
        }

        if !service.hasDeviceControlPermission {
            Button(
                "Open Device Control Settings…",
                systemImage: "hand.raised",
                action: service.openDeviceControlSettings
            )
            .labelStyle(.titleAndIcon)
        }

        Divider()

        Button("Quit", systemImage: "power", action: service.quit)
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("q")
    }

    private var statusText: String {
        let connection = service.connectionState.isConnected ? "Connected" : "Disconnected"
        return service.hasDeviceControlPermission ? connection : "\(connection) · Permission required"
    }
}
