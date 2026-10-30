import Foundation
import IOBluetooth

/// Shows a peek when a Bluetooth device connects or disconnects.
///
/// Not main-actor isolated on purpose: IOBluetooth calls back on its own background
/// queue (`com.apple.bluetooth.iobluetooth.coordinatorQueue`). State is guarded by
/// `lock`, and only the finished, `Sendable` peek is sent to the main actor.
final class BluetoothService: NSObject, @unchecked Sendable {
    private let activity: ActivityState
    private let lock = NSLock()
    // Guarded by `lock`.
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Devices already connected; the connect callback also fires for these at registration.
    private var connected: Set<String> = []
    private var isStarting = false

    init(activity: ActivityState) {
        self.activity = activity
    }

    /// Returns at once. The first IOBluetooth call waits for the Bluetooth permission prompt to
    /// be answered, so it runs in the background; the notch never freezes on it. Once it has
    /// returned, the permission is decided and registering (on the main thread) can't block.
    func start() {
        let begin = lock.withLock { () -> Bool in
            guard connectNotification == nil, !isStarting else { return false }
            isStarting = true
            return true
        }
        guard begin else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let connectedNow = Set(paired.filter { $0.isConnected() }.compactMap(\.addressString))
            DispatchQueue.main.async { [self] in
                // Stopped while waiting: don't register.
                guard lock.withLock({ isStarting }) else { return }
                lock.withLock { connected = connectedNow }
                // Registered outside the lock: IOBluetooth may call back right away.
                let notification = IOBluetoothDevice.register(
                    forConnectNotifications: self,
                    selector: #selector(deviceConnected(_:device:))
                )
                lock.withLock {
                    connectNotification = notification
                    isStarting = false
                }
            }
        }
    }

    func stop() {
        let notifications: [IOBluetoothUserNotification] = lock.withLock {
            let all = [connectNotification].compactMap { $0 } + Array(disconnectNotifications.values)
            connectNotification = nil
            isStarting = false
            disconnectNotifications.removeAll()
            connected.removeAll()
            return all
        }
        notifications.forEach { $0.unregister() }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }

        let needsDisconnectWatch = lock.withLock { disconnectNotifications[address] == nil }
        if needsDisconnectWatch,
           let watch = device.register(
               forDisconnectNotification: self,
               selector: #selector(deviceDisconnected(_:device:))
           ) {
            lock.withLock { disconnectNotifications[address] = watch }
        }

        let isNew = lock.withLock { connected.insert(address).inserted }
        guard isNew else { return }
        show(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        let watch = lock.withLock {
            connected.remove(address)
            return disconnectNotifications.removeValue(forKey: address)
        }
        watch?.unregister()
        show(device, connected: false)
    }

    /// Runs on IOBluetooth's queue; builds a Sendable peek and hands it to the main actor.
    private func show(_ device: IOBluetoothDevice, connected: Bool) {
        let enabled = UserDefaults.standard.bool(
            forKey: SettingsKey.bluetoothAlertsEnabled,
            default: SettingsDefault.bluetoothAlertsEnabled
        )
        guard enabled else { return }
        let symbol = BluetoothDeviceKind.symbol(
            name: device.name ?? "",
            majorClass: device.deviceClassMajor,
            minorClass: device.deviceClassMinor
        )
        let peek = Peek.bluetooth(
            symbol: symbol,
            connected: connected,
            battery: connected ? Self.batteryPercent(of: device) : nil
        )
        let activity = activity
        Task { @MainActor in
            activity.showPeek(peek)
            activity.devices.refresh()
        }
    }

    /// AirPods and some Beats expose battery through private properties. Checked with
    /// `responds(to:)` first, so a missing property can never crash.
    private static func batteryPercent(of device: IOBluetoothDevice) -> Int? {
        let keys = ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight"]
        for key in keys where device.responds(to: NSSelectorFromString(key)) {
            if let value = device.value(forKey: key) as? Int, (1...100).contains(value) {
                return value
            }
        }
        return nil
    }
}

enum BluetoothDeviceKind {
    // Bluetooth Class of Device: major classes and peripheral minor bits.
    private static let majorComputer: UInt32 = 0x01
    private static let majorPhone: UInt32 = 0x02
    private static let majorAudio: UInt32 = 0x04
    private static let majorPeripheral: UInt32 = 0x05
    private static let minorKeyboardBit: UInt32 = 0x10
    private static let minorPointingBit: UInt32 = 0x20

    static func symbol(name: String, majorClass: UInt32, minorClass: UInt32) -> String {
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("trackpad") { return "hand.point.up.left.fill" }

        switch majorClass {
        case majorAudio:
            return "headphones"
        case majorPeripheral:
            if minorClass & minorPointingBit != 0 { return "computermouse.fill" }
            if minorClass & minorKeyboardBit != 0 { return "keyboard.fill" }
            return "gamecontroller.fill"
        case majorPhone:
            return "iphone"
        case majorComputer:
            return "laptopcomputer"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
