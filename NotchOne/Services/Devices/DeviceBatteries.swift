import Foundation
import IOKit

/// One device's battery: AirPods have a left, right and case level; most have one.
struct DeviceBattery: Identifiable, Equatable, Sendable {
    enum Part: String, Sendable, CaseIterable {
        case single, left, right, `case`
    }

    let name: String
    let symbol: String
    /// Only the parts the device reports, each 1…100.
    var levels: [Part: Int]

    var id: String { name }

    /// The level that matters most: the lowest bud or the only battery. The case doesn't
    /// count unless it's all there is.
    var lowest: Int? {
        let worn = levels.filter { $0.key != .case }.map(\.value)
        return (worn.isEmpty ? Array(levels.values) : worn).min()
    }
}

/// Pure rules: merging what IOKit and Bluetooth report, and when to warn.
enum DeviceBatteryLogic {
    static let lowLevel = 20
    /// A device warned about at or below `lowLevel` is warned again only after it has been
    /// charged above this.
    static let rearmLevel = 30

    /// Combines the sources by name; a device seen twice keeps every part it reported.
    static func merge(_ lists: [[DeviceBattery]]) -> [DeviceBattery] {
        var byName: [String: DeviceBattery] = [:]
        var order: [String] = []
        for device in lists.joined() where !device.levels.isEmpty {
            if var existing = byName[device.name] {
                existing.levels.merge(device.levels) { old, _ in old }
                byName[device.name] = existing
            } else {
                byName[device.name] = device
                order.append(device.name)
            }
        }
        return order.compactMap { byName[$0] }.sorted { ($0.lowest ?? 100) < ($1.lowest ?? 100) }
    }

    /// Devices to warn about now, and the updated set of devices already warned.
    static func lowWarnings(_ devices: [DeviceBattery], warned: Set<String>) -> (warn: [DeviceBattery], warned: Set<String>) {
        var warned = warned
        var warn: [DeviceBattery] = []
        for device in devices {
            guard let level = device.lowest else { continue }
            if level <= lowLevel, !warned.contains(device.name) {
                warn.append(device)
                warned.insert(device.name)
            } else if level > rearmLevel {
                warned.remove(device.name)
            }
        }
        return (warn, warned)
    }

    /// Reads `system_profiler SPBluetoothDataType -json`: connected devices and their
    /// `device_batteryLevel…` values, which are formatted for the Mac's language ("80%", "%80").
    static func devices(fromBluetoothReport data: Data) -> [DeviceBattery] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        let parts: [(String, DeviceBattery.Part)] = [
            ("device_batteryLevelLeft", .left), ("device_batteryLevelRight", .right),
            ("device_batteryLevelCase", .case), ("device_batteryLevelMain", .single),
        ]
        var devices: [DeviceBattery] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (rawName, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    var levels: [DeviceBattery.Part: Int] = [:]
                    for (key, part) in parts {
                        if let level = clamp(percent(info[key] as? String)) { levels[part] = level }
                    }
                    let name = displayName(rawName)
                    guard !levels.isEmpty, !name.isEmpty else { continue }
                    devices.append(DeviceBattery(name: name, symbol: symbol(name: name, minorType: info["device_minorType"] as? String), levels: levels))
                }
            }
        }
        return devices
    }

    /// Without the owner: "Alex's AirPods Pro 3" → "AirPods Pro 3". Shorter in the notch, and
    /// no name on screen while sharing it.
    static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for mark in ["'s ", "’s ", "'S ", "’S "] {
            if let range = trimmed.range(of: mark), !trimmed[..<range.lowerBound].contains(" ") {
                let rest = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? trimmed : rest
            }
        }
        return trimmed
    }

    /// "80%", "%80", "80 %" → 80.
    static func percent(_ text: String?) -> Int? {
        guard let digits = text?.filter(\.isNumber), !digits.isEmpty else { return nil }
        return Int(digits)
    }

    static func symbol(name: String, minorType: String?) -> String {
        // Bluetooth Class of Device bits, as BluetoothDeviceKind expects them.
        let (major, minor): (UInt32, UInt32) = switch minorType?.lowercased() {
        case "headphones", "headset", "speaker", "loudspeaker": (0x04, 0)
        case "keyboard": (0x05, 0x10)
        case "mouse", "trackpad", "pointing device": (0x05, 0x20)
        case "game controller", "gamepad", "joystick": (0x05, 0)
        default: (0, 0)
        }
        return BluetoothDeviceKind.symbol(name: name, majorClass: major, minorClass: minor)
    }

    static func clamp(_ value: Int?) -> Int? {
        value.flatMap { (1...100).contains($0) ? $0 : nil }
    }
}

/// Reads batteries from two places: the I/O Registry (Apple's keyboards, mice and trackpads,
/// no permission) and macOS's Bluetooth report (AirPods and other Bluetooth devices), which is
/// only read once Bluetooth is allowed.
enum DeviceBatteryReader {
    /// Magic Keyboard, Mouse and Trackpad report `BatteryPercent` in the I/O Registry (public,
    /// no permission).
    static func hidDevices() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [DeviceBattery] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let name = property(service, "Product") as? String,
                  let percent = DeviceBatteryLogic.clamp(property(service, "BatteryPercent") as? Int)
            else { continue }
            devices.append(DeviceBattery(name: name, symbol: symbol(for: name), levels: [.single: percent]))
        }
        return devices
    }

    /// Connected Bluetooth devices with a battery (AirPods left, right and case; most others
    /// one level), from macOS's own Bluetooth report. It's quick (about 50 ms) and is run at
    /// most once a minute, only once Bluetooth is allowed.
    static func bluetoothDevices() -> [DeviceBattery] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return DeviceBatteryLogic.devices(fromBluetoothReport: data)
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func symbol(for name: String) -> String {
        BluetoothDeviceKind.symbol(
            name: name,
            majorClass: 0x05,
            minorClass: name.localizedCaseInsensitiveContains("keyboard") ? 0x10 : 0x20
        )
    }
}

/// Device batteries for Home and the System tab, refreshed when the notch opens (at most
/// once a minute) and right after a device connects.
@MainActor
@Observable
final class DeviceBatteryStore {
    private(set) var devices: [DeviceBattery] = []
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var warned: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Told about a device that just went low.
    @ObservationIgnored var onLow: ((DeviceBattery) -> Void)?

    static let minimumInterval: TimeInterval = 60

    func refreshIfNeeded(now: Date = Date()) {
        if let lastRead, now.timeIntervalSince(lastRead) < Self.minimumInterval { return }
        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        lastRead = Date()
        let withBluetooth = PermissionGate.allows(.bluetooth)
        task = Task { [weak self] in
            let devices = await Task.detached(priority: .utility) {
                DeviceBatteryLogic.merge([
                    DeviceBatteryReader.hidDevices(),
                    withBluetooth ? DeviceBatteryReader.bluetoothDevices() : [],
                ])
            }.value
            guard let self else { return }
            self.task = nil
            if devices != self.devices { self.devices = devices }
            let result = DeviceBatteryLogic.lowWarnings(devices, warned: self.warned)
            self.warned = result.warned
            result.warn.forEach { self.onLow?($0) }
        }
    }
}
