import Foundation

struct BatteryStatus: Equatable, Sendable {
    var percent: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var isCharged: Bool

    var isLow: Bool { !isPluggedIn && percent <= (BatteryPeekLogic.lowThresholds.max() ?? 20) }

    var symbolName: String {
        if isPluggedIn { return "battery.100percent.bolt" }
        return switch percent {
        case 88...: "battery.100percent"
        case 63..<88: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }
}

/// Decides when a battery change deserves a peek. Pure, so it's easy to test.
enum BatteryPeekLogic {
    /// Warn once when dropping to or below each of these, until plugged in again.
    static let lowThresholds = [20, 10]

    struct Result: Equatable {
        var peek: Peek?
        /// Thresholds already warned about during this discharge.
        var warned: Set<Int>
    }

    static func evaluate(previous: BatteryStatus?, current: BatteryStatus, warned: Set<Int>) -> Result {
        guard let previous else {
            // First reading at launch: no peek, and don't warn about levels we're already under.
            return Result(peek: nil, warned: current.isPluggedIn ? [] : thresholds(atOrAbove: current.percent))
        }

        if current.isPluggedIn != previous.isPluggedIn {
            return Result(
                peek: .power(pluggedIn: current.isPluggedIn, percent: current.percent),
                warned: current.isPluggedIn ? [] : thresholds(atOrAbove: current.percent)
            )
        }

        if current.isPluggedIn {
            return Result(peek: nil, warned: [])
        }

        let crossed = lowThresholds.filter {
            current.percent <= $0 && previous.percent > $0 && !warned.contains($0)
        }
        guard !crossed.isEmpty else { return Result(peek: nil, warned: warned) }
        return Result(peek: .lowBattery(percent: current.percent), warned: warned.union(crossed))
    }

    private static func thresholds(atOrAbove percent: Int) -> Set<Int> {
        Set(lowThresholds.filter { percent <= $0 })
    }
}
