import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: AppService

    var body: some View {
        Button(
            statusText,
            systemImage: statusIcon
        ) {}
        .labelStyle(.titleAndIcon)
        .disabled(true)
        .onAppear(perform: service.refreshPermissions)

        Divider()

        if service.connectionState.isConnected {
            Button("Disconnect", systemImage: "xmark", action: service.disconnect)
                .labelStyle(.titleAndIcon)

            Divider()

            bluetoothSettingsButton

            permissionButtons

            Menu("Help", systemImage: "questionmark.circle") {
                pairingInstructions
            }
            .labelStyle(.titleAndIcon)
        } else {
            bluetoothSettingsButton

            pairingInstructions

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

        if !service.connectionState.isConnected {
            permissionButtons

            if !service.hasRequiredPermissions {
                Divider()
            }
        }

        Button(AppVersion.current) {}
            .disabled(true)

        Button("Quit", systemImage: "power", action: service.quit)
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("q")
    }

    private var bluetoothSettingsButton: some View {
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
    }

    @ViewBuilder
    private var pairingInstructions: some View {
        Button("Hold 􀯷 Back and 􀁌 Volume Up for 5s") {}
            .disabled(true)

        Button("Connect to it via System Settings") {}
            .disabled(true)

        Button("Remote will appear as “Bluetooth Device” in Settings") {}
            .disabled(true)

        Button("Make sure to “Forget this device” on nearby Macs") {}
            .disabled(true)
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if !service.hasDeviceControlPermission {
            Button(
                "Grant Device Control…",
                systemImage: "hand.raised",
                action: service.openDeviceControlSettings
            )
            .labelStyle(.titleAndIcon)
        }

        if !service.hasInputMonitoringPermission {
            Button(
                "Grant Input Monitoring…",
                systemImage: "keyboard",
                action: service.openInputMonitoringSettings
            )
            .labelStyle(.titleAndIcon)
        }
    }

    private var statusText: String {
        let connection = service.connectionState.isConnected ? "Connected" : "Disconnected"
        return service.hasRequiredPermissions ? connection : "\(connection) · Permission required"
    }

    private var statusIcon: String {
        guard service.connectionState.isConnected else { return "xmark" }
        return service.hasRequiredPermissions ? "checkmark" : "exclamationmark.triangle"
    }
}
