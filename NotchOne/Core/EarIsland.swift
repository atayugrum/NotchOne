import Foundation

/// A short event shown under the closed notch: a symbol and two lines of text on the left,
/// ring gauges for any levels on the right.
struct EarIsland: Equatable, Sendable {
    enum Tint: Equatable, Sendable {
        case neutral, green, red, indigo
    }

    struct Gauge: Equatable, Sendable, Identifiable {
        let label: String
        /// 0…100.
        let value: Int
        var id: String { label }
    }

    let symbol: String
    let tint: Tint
    let title: String
    var detail: String?
    var gauges: [Gauge] = []

    /// Long-running things (music, meetings, jobs) and level popups stay beside the notch;
    /// a new file does too, so its thumbnail can be dragged.
    static func make(for content: EarContent?, devices: [DeviceBattery]) -> EarIsland? {
        switch content {
        case .peek(.bluetooth(let symbol, let connected, let battery, let name)):
            return bluetooth(symbol: symbol, connected: connected, battery: battery, name: name, devices: devices)
        case .peek(.power(let pluggedIn, let percent)):
            return EarIsland(
                symbol: pluggedIn ? "bolt.fill" : "powerplug",
                tint: pluggedIn ? .green : .neutral,
                title: pluggedIn ? String(localized: "Charging") : String(localized: "On battery"),
                gauges: [Gauge(label: String(localized: "Battery"), value: percent)]
            )
        case .peek(.lowBattery(let percent)):
            return EarIsland(symbol: "battery.25percent", tint: .red, title: String(localized: "Low battery"),
                             gauges: [Gauge(label: String(localized: "Battery"), value: percent)])
        case .peek(.focus(let on)):
            return EarIsland(symbol: on ? "moon.fill" : "moon", tint: on ? .indigo : .neutral,
                             title: on ? String(localized: "Focus on") : String(localized: "Focus off"))
        case .peek(.keepAwake(let on)):
            return EarIsland(symbol: on ? "cup.and.saucer.fill" : "cup.and.saucer", tint: on ? .green : .neutral,
                             title: on ? String(localized: "Keeping your Mac awake") : String(localized: "Your Mac can sleep"))
        case .live(let item):
            return live(item)
        default:
            return nil
        }
    }

    private static func bluetooth(symbol: String, connected: Bool, battery: Int?, name: String, devices: [DeviceBattery]) -> EarIsland {
        let title = name.isEmpty ? String(localized: "Bluetooth device") : name
        guard connected else {
            return EarIsland(symbol: symbol, tint: .neutral, title: title, detail: String(localized: "Disconnected"))
        }
        var gauges = gauges(for: devices.first { $0.name == name })
        if gauges.isEmpty, let battery {
            gauges = [Gauge(label: String(localized: "Battery"), value: battery)]
        }
        return EarIsland(symbol: symbol, tint: .green, title: title, detail: String(localized: "Connected"), gauges: gauges)
    }

    private static func gauges(for device: DeviceBattery?) -> [Gauge] {
        guard let device else { return [] }
        let parts: [(DeviceBattery.Part, String)] = [
            (.left, String(localized: "battery.left")),
            (.right, String(localized: "battery.right")),
            (.case, String(localized: "battery.case")),
            (.single, String(localized: "Battery")),
        ]
        return parts.compactMap { part, label in
            device.levels[part].map { Gauge(label: label, value: $0) }
        }
    }

    private static func live(_ item: LiveActivity) -> EarIsland? {
        guard item.source != .notification, item.source != .meeting else { return nil }
        let duration = item.duration.map(LiveStyle.duration)
        switch item.status {
        case .succeeded:
            return EarIsland(symbol: item.symbol, tint: .green, title: item.title, detail: item.detail ?? duration)
        case .failed:
            return EarIsland(symbol: item.symbol, tint: .red, title: item.title, detail: item.detail ?? duration)
        case .info:
            return EarIsland(symbol: item.symbol, tint: .neutral, title: item.title, detail: item.detail)
        case .running, .meeting:
            return nil
        }
    }
}
