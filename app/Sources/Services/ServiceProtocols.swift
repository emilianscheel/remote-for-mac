import Foundation

protocol BluetoothServicing: AnyObject {
    var onRemotesChanged: (([NearbyRemote]) -> Void)? { get set }
    var onConnected: ((NearbyRemote) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func startScanning()
    func stopScanning()
    func connect(to remote: NearbyRemote)
    func disconnect()
}

protocol RemoteInputServicing: AnyObject {
    var onInput: ((RemoteInput) -> Void)? { get set }
    var onConnectionChanged: ((Bool) -> Void)? { get set }
    func start()
    func setEnabled(_ enabled: Bool)
    func stop()
}

protocol MacActionDispatching {
    func dispatch(_ action: MacAction)
}

protocol ApplicationContextProviding {
    func currentContext() -> ApplicationContext
}

@MainActor
protocol PermissionServicing: AnyObject {
    var current: PermissionState { get }
    var onChange: ((PermissionState) -> Void)? { get set }
    func requestRequiredPermissions()
    func startMonitoring()
    func stopMonitoring()
}

@MainActor
protocol UpdateServicing {
    func start()
}
