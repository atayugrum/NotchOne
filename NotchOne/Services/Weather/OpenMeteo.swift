import Foundation

/// Where forecasts come from. Open-Meteo is the only one today; Apple Weather through
/// Shortcuts (or WeatherKit) can be added later behind the same protocol.
protocol WeatherProvider: Sendable {
    func forecast(at coordinate: Coordinate, now: Date) async throws -> WeatherSnapshot
}

enum WeatherError: LocalizedError, Equatable {
    case badResponse(Int)
    case unreadable
    case noLocation

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): String(localized: "The weather service answered with an error (\(code)).")
        case .unreadable: String(localized: "The weather service sent something unexpected.")
        case .noLocation: String(localized: "No location for the weather yet.")
        }
    }
}

/// Open-Meteo (open-meteo.com): free, no account or key. Data under CC BY 4.0, so the
/// app credits it wherever the forecast is shown.
enum OpenMeteo {
    static var attribution: String { String(localized: "Weather data by Open-Meteo.com") }
    static let days = 5
    static let hours = 12

    static func url(for coordinate: Coordinate) -> URL {
        let place = coordinate.rounded
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: String(days + 1)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    // MARK: - Parsing

    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double?
            var apparent_temperature: Double?
            var weather_code: Int?
            var is_day: Int?
        }
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var weather_code: [Int?]
            var is_day: [Int?]?
            var precipitation_probability: [Int?]?
        }
        struct Daily: Decodable {
            var time: [Double]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var precipitation_probability_max: [Int?]?
        }
        var utc_offset_seconds: Int?
        var current: Current
        var hourly: Hourly?
        var daily: Daily?
    }

    /// Anything missing or malformed in the answer is dropped rather than trusted; only a
    /// missing current temperature makes the whole answer unusable.
    static func snapshot(from data: Data, coordinate: Coordinate, now: Date) throws -> WeatherSnapshot {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let temperature = response.current.temperature_2m, temperature.isFinite
        else { throw WeatherError.unreadable }

        let current = response.current
        let isDay = (current.is_day ?? 1) == 1
        return WeatherSnapshot(
            temperature: temperature,
            feelsLike: current.apparent_temperature.flatMap { $0.isFinite ? $0 : nil } ?? temperature,
            condition: WeatherCondition(wmoCode: current.weather_code ?? -1),
            isDay: isDay,
            hours: response.hourly.map { hours(from: $0, now: now) } ?? [],
            days: response.daily.map { days(from: $0, now: now) } ?? [],
            fetchedAt: now,
            coordinate: coordinate.rounded,
            utcOffsetSeconds: response.utc_offset_seconds ?? 0
        )
    }

    /// The next hours, starting with the hour that's under way.
    private static func hours(from hourly: Response.Hourly, now: Date) -> [WeatherSnapshot.Hour] {
        var result: [WeatherSnapshot.Hour] = []
        for (index, stamp) in hourly.time.enumerated() {
            let time = Date(timeIntervalSince1970: stamp)
            guard time > now.addingTimeInterval(-3600),
                  let temperature = hourly.temperature_2m[safe: index] ?? nil, temperature.isFinite
            else { continue }
            result.append(WeatherSnapshot.Hour(
                time: time,
                temperature: temperature,
                condition: WeatherCondition(wmoCode: (hourly.weather_code[safe: index] ?? nil) ?? -1),
                isDay: ((hourly.is_day?[safe: index] ?? nil) ?? 1) == 1,
                precipitationChance: hourly.precipitation_probability?[safe: index] ?? nil
            ))
            if result.count == Self.hours { break }
        }
        return result
    }

    /// Today and the next days. A day's time is its local midnight.
    private static func days(from daily: Response.Daily, now: Date) -> [WeatherSnapshot.Day] {
        var result: [WeatherSnapshot.Day] = []
        for (index, stamp) in daily.time.enumerated() {
            let date = Date(timeIntervalSince1970: stamp)
            guard date > now.addingTimeInterval(-24 * 3600),
                  let high = daily.temperature_2m_max[safe: index] ?? nil, high.isFinite,
                  let low = daily.temperature_2m_min[safe: index] ?? nil, low.isFinite
            else { continue }
            result.append(WeatherSnapshot.Day(
                date: date,
                low: low,
                high: high,
                condition: WeatherCondition(wmoCode: (daily.weather_code[safe: index] ?? nil) ?? -1),
                precipitationChance: daily.precipitation_probability_max?[safe: index] ?? nil
            ))
            if result.count == Self.days { break }
        }
        return result
    }
}

struct OpenMeteoProvider: WeatherProvider {
    /// No cookies, no cache on disk: each request carries only the rounded place.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// Far more than a real answer (about 10 KB); anything bigger isn't a forecast.
    private static let maxBytes = 1_000_000

    func forecast(at coordinate: Coordinate, now: Date) async throws -> WeatherSnapshot {
        guard coordinate.isValid else { throw WeatherError.noLocation }
        let (data, response) = try await session.data(from: OpenMeteo.url(for: coordinate))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw WeatherError.badResponse(status) }
        guard data.count <= Self.maxBytes else { throw WeatherError.unreadable }
        return try OpenMeteo.snapshot(from: data, coordinate: coordinate, now: now)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
