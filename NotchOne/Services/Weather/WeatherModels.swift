import Foundation

/// A place on Earth, in degrees.
struct Coordinate: Equatable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    /// About 1 km: plenty for a forecast, and the exact spot never leaves the Mac.
    var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

/// Sky conditions, from the WMO weather codes Open-Meteo uses.
enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear, mainlyClear, partlyCloudy, overcast, fog
    case drizzle, freezingDrizzle, rain, freezingRain, snow
    case rainShowers, snowShowers, thunderstorm, unknown

    init(wmoCode code: Int) {
        switch code {
        case 0: self = .clear
        case 1: self = .mainlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63, 65: self = .rain
        case 66, 67: self = .freezingRain
        case 71, 73, 75, 77: self = .snow
        case 80, 81, 82: self = .rainShowers
        case 85, 86: self = .snowShowers
        case 95, 96, 99: self = .thunderstorm
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .clear: String(localized: "weather.clear", defaultValue: "Clear")
        case .mainlyClear: String(localized: "Mostly clear")
        case .partlyCloudy: String(localized: "Partly cloudy")
        case .overcast: String(localized: "Cloudy")
        case .fog: String(localized: "Fog")
        case .drizzle: String(localized: "Drizzle")
        case .freezingDrizzle: String(localized: "Freezing drizzle")
        case .rain: String(localized: "Rain")
        case .freezingRain: String(localized: "Freezing rain")
        case .snow: String(localized: "Snow")
        case .rainShowers: String(localized: "Showers")
        case .snowShowers: String(localized: "Snow showers")
        case .thunderstorm: String(localized: "Thunderstorms")
        case .unknown: "—"
        }
    }

    /// SF Symbol, with a moon instead of a sun at night.
    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear, .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snowShowers: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "cloud.fill"
        }
    }
}

/// A forecast as shown in the notch. Temperatures are always in °C; views convert.
struct WeatherSnapshot: Equatable, Codable, Sendable {
    struct Hour: Equatable, Codable, Sendable {
        var time: Date
        var temperature: Double
        var condition: WeatherCondition
        var isDay: Bool
        var precipitationChance: Int?
    }

    struct Day: Equatable, Codable, Sendable {
        var date: Date
        var low: Double
        var high: Double
        var condition: WeatherCondition
        var precipitationChance: Int?
    }

    var temperature: Double
    var feelsLike: Double
    var condition: WeatherCondition
    var isDay: Bool
    var hours: [Hour]
    var days: [Day]
    var fetchedAt: Date
    /// The rounded coordinate the forecast is for.
    var coordinate: Coordinate
    /// Offset of the forecast place from UTC, so hours show in local time there.
    var utcOffsetSeconds: Int
}

enum WeatherUnit: String, CaseIterable, Identifiable, Sendable {
    case system, celsius, fahrenheit

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .celsius: String(localized: "°C")
        case .fahrenheit: String(localized: "°F")
        }
    }
}

enum WeatherLocationSource: String, CaseIterable, Identifiable, Sendable {
    case current, city

    var id: String { rawValue }
    var title: String { self == .current ? String(localized: "Current location") : String(localized: "A city") }
}

/// Pure rules: when to refresh, and how to show a temperature.
enum WeatherLogic {
    /// Never ask more often than this. Forecasts don't change faster.
    static let refreshInterval: TimeInterval = 30 * 60
    /// After a failed request, wait this long before trying again.
    static let retryInterval: TimeInterval = 5 * 60
    /// Older than this, the forecast isn't shown next to the battery any more.
    static let badgeMaxAge: TimeInterval = 3 * 60 * 60

    static func shouldRefresh(
        snapshot: WeatherSnapshot?,
        coordinate: Coordinate,
        lastFailure: Date?,
        now: Date
    ) -> Bool {
        if let lastFailure, now.timeIntervalSince(lastFailure) < retryInterval { return false }
        guard let snapshot, snapshot.coordinate == coordinate.rounded else { return true }
        return now.timeIntervalSince(snapshot.fetchedAt) >= refreshInterval
    }

    /// "18°" in the chosen unit (`.system` follows the region's setting).
    static func format(_ celsius: Double, unit: WeatherUnit, locale: Locale = .current) -> String {
        let value: Double
        switch unit {
        case .celsius: value = celsius
        case .fahrenheit: value = celsius * 9 / 5 + 32
        case .system:
            value = locale.measurementSystem == .us ? celsius * 9 / 5 + 32 : celsius
        }
        let degrees = Int(value.rounded())
        return "\(degrees == 0 ? 0 : degrees)°"   // no "-0°"
    }
}
