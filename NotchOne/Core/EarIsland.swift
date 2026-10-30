import Foundation

/// A short event shown as a small card under the closed notch: an icon in a circle, a
/// title, one line of detail or a few values, and a status on the right.
struct EarIsland: Equatable, Sendable {
    enum Tint: Equatable, Sendable {
        case neutral, green, red, indigo
    }

    enum Trailing: Equatable, Sendable {
        case none
        case success
        case failure
        case text(String)
    }

    struct Chip: Equatable, Sendable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let symbol: String
    let tint: Tint
    let title: String
    var detail: String?
    var chips: [Chip] = []
    var trailing: Trailing = .none

    /// Long-running things (music, meetings, jobs) and level popups stay beside the notch;
    /// a new file does too, so its thumbnail can be dragged.
    static func make(for content: EarContent?, devices: [DeviceBattery]) -> EarIsland? {
        switch content {
        case .peek(.bluetooth(let symbol, let connected, let battery, let name)):
            return bluetooth(symbol: symbol, connected: connected, battery: battery, name: name, devices: devices)
        case .peek(.power(let pluggedIn, let percent)):
            return pluggedIn
                ? EarIsland(symbol: "bolt.fill", tint: .green, title: String(localized: "Charging"), trailing: .text("\(percent)%"))
                : EarIsland(symbol: "powerplug", tint: .neutral, title: String(localized: "On battery"), trailing: .text("\(percent)%"))
        case .peek(.lowBattery(let percent)):
            return EarIsland(symbol: "battery.25percent", tint: .red, title: String(localized: "Low battery"), trailing: .text("\(percent)%"))
        case .peek(.focus(let on)):
            return EarIsland(symbol: on ? "moon.fill" : "moon", tint: on ? .indigo : .neutral,
                             title: on ? String(localized: "Focus on") : String(localized: "Focus off"))
        case .live(let item):
            return live(item)
        default:
            return nil
        }
    }

    private static func bluetooth(symbol: String, connected: Bool, battery: Int?, name: String, devices: [DeviceBattery]) -> EarIsland {
        let title = name.isEmpty ? String(localized: "Bluetooth device") : name
        guard connected else {
            return EarIsland(symbol: symbol, tint: .neutral, title: title, detail: String(localized: "Disconnected"), trailing: .failure)
        }
        let chips = chips(for: devices.first { $0.name == name })
        if !chips.isEmpty {
            return EarIsland(symbol: symbol, tint: .green, title: title, chips: chips, trailing: .success)
        }
        let detail = battery.map { "\($0)%" } ?? String(localized: "Connected")
        return EarIsland(symbol: symbol, tint: .green, title: title, detail: detail, trailing: .success)
    }

    private static func chips(for device: DeviceBattery?) -> [Chip] {
        guard let device else { return [] }
        let parts: [(DeviceBattery.Part, String)] = [
            (.left, String(localized: "battery.left")),
            (.right, String(localized: "battery.right")),
            (.case, String(localized: "battery.case")),
            (.single, String(localized: "Battery")),
        ]
        return parts.compactMap { part, label in
            device.levels[part].map { Chip(label: label, value: "\($0)%") }
        }
    }

    private static func live(_ item: LiveActivity) -> EarIsland? {
        guard item.source != .notification, item.source != .meeting else { return nil }
        switch item.status {
        case .succeeded:
            return EarIsland(symbol: item.symbol, tint: .green, title: item.title, detail: item.detail,
                             trailing: item.duration.map { .text(LiveStyle.duration($0)) } ?? .success)
        case .failed:
            return EarIsland(symbol: item.symbol, tint: .red, title: item.title, detail: item.detail,
                             trailing: item.duration.map { .text(LiveStyle.duration($0)) } ?? .failure)
        case .info:
            return EarIsland(symbol: item.symbol, tint: .neutral, title: item.title, detail: item.detail)
        case .running, .meeting:
            return nil
        }
    }
}
