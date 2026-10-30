import AppKit
import Testing
@testable import NotchOne

struct WeatherLogicTests {
    let istanbul = Coordinate(latitude: 41.008_24, longitude: 28.978_36)
    let now = Date(timeIntervalSince1970: 1_793_289_600)   // the "current.time" below

    @Test func coordinatesAreRoundedToAboutOneKilometre() {
        #expect(istanbul.rounded == Coordinate(latitude: 41.01, longitude: 28.98))
        #expect(Coordinate(latitude: -33.868_8, longitude: 151.209_3).rounded == Coordinate(latitude: -33.87, longitude: 151.21))
        #expect(!Coordinate(latitude: 91, longitude: 0).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
    }

    @Test func requestSendsOnlyTheRoundedPlace() throws {
        let url = OpenMeteo.url(for: istanbul)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.scheme == "https")
        #expect(url.host() == "api.open-meteo.com")
        #expect(items.first { $0.name == "latitude" }?.value == "41.01")
        #expect(items.first { $0.name == "longitude" }?.value == "28.98")
        #expect(!url.absoluteString.contains("41.008"))
    }

    @Test func wmoCodesMapToConditions() {
        #expect(WeatherCondition(wmoCode: 0) == .clear)
        #expect(WeatherCondition(wmoCode: 3) == .overcast)
        #expect(WeatherCondition(wmoCode: 63) == .rain)
        #expect(WeatherCondition(wmoCode: 95) == .thunderstorm)
        #expect(WeatherCondition(wmoCode: 1234) == .unknown)
        #expect(WeatherCondition.clear.symbol(isDay: false) == "moon.stars.fill")
    }

    @Test func everyConditionHasARealSymbol() {
        for condition in WeatherCondition.allCases {
            for isDay in [true, false] {
                #expect(NSImage(systemSymbolName: condition.symbol(isDay: isDay), accessibilityDescription: nil) != nil)
            }
        }
    }

    @Test func temperaturesFollowTheUnit() {
        #expect(WeatherLogic.format(15.9, unit: .celsius) == "16°")
        #expect(WeatherLogic.format(15.9, unit: .fahrenheit) == "61°")
        #expect(WeatherLogic.format(-0.4, unit: .celsius) == "0°")
        #expect(WeatherLogic.format(20, unit: .system, locale: Locale(identifier: "en_US")) == "68°")
        #expect(WeatherLogic.format(20, unit: .system, locale: Locale(identifier: "tr_TR")) == "20°")
    }

    @Test func refreshesOnlyWhenOldOrMovedAndWaitsAfterAFailure() throws {
        let fresh = try OpenMeteo.snapshot(from: Fixture.response, coordinate: istanbul, now: now)
        #expect(WeatherLogic.shouldRefresh(snapshot: nil, coordinate: istanbul, lastFailure: nil, now: now))
        #expect(!WeatherLogic.shouldRefresh(snapshot: fresh, coordinate: istanbul, lastFailure: nil, now: now.addingTimeInterval(29 * 60)))
        #expect(WeatherLogic.shouldRefresh(snapshot: fresh, coordinate: istanbul, lastFailure: nil, now: now.addingTimeInterval(31 * 60)))
        // A different place needs its own forecast right away.
        let ankara = Coordinate(latitude: 39.93, longitude: 32.86)
        #expect(WeatherLogic.shouldRefresh(snapshot: fresh, coordinate: ankara, lastFailure: nil, now: now))
        #expect(!WeatherLogic.shouldRefresh(snapshot: nil, coordinate: istanbul, lastFailure: now.addingTimeInterval(-60), now: now))
    }
}

struct OpenMeteoParserTests {
    let place = Coordinate(latitude: 41.008, longitude: 28.978)
    let now = Date(timeIntervalSince1970: 1_793_289_600)

    @Test func readsCurrentHoursAndDays() throws {
        let snapshot = try OpenMeteo.snapshot(from: Fixture.response, coordinate: place, now: now)
        #expect(snapshot.temperature == 15.9)
        #expect(snapshot.feelsLike == 14.1)
        #expect(snapshot.condition == .overcast)
        #expect(!snapshot.isDay)
        #expect(snapshot.utcOffsetSeconds == 10_800)
        #expect(snapshot.coordinate == place.rounded)
        #expect(snapshot.fetchedAt == now)

        // Starts at the hour under way, skips the earlier one and the hour without a temperature.
        #expect(snapshot.hours.map(\.temperature) == [15.9, 15.2, 13.8])
        #expect(snapshot.hours.first?.time == now)
        #expect(snapshot.hours[1].precipitationChance == 40)

        #expect(snapshot.days.count == 2)
        #expect(snapshot.days[0].low == 11.2)
        #expect(snapshot.days[0].high == 18.4)
        #expect(snapshot.days[1].condition == .rain)
    }

    @Test func rejectsAnswersWithoutACurrentTemperature() {
        let broken = Data(#"{"current":{"weather_code":3}}"#.utf8)
        #expect(throws: WeatherError.unreadable) { try OpenMeteo.snapshot(from: broken, coordinate: place, now: now) }
        #expect(throws: WeatherError.unreadable) { try OpenMeteo.snapshot(from: Data("<html>".utf8), coordinate: place, now: now) }
    }

    @Test func missingSectionsLeaveEmptyLists() throws {
        let minimal = Data(#"{"current":{"temperature_2m":4.5}}"#.utf8)
        let snapshot = try OpenMeteo.snapshot(from: minimal, coordinate: place, now: now)
        #expect(snapshot.temperature == 4.5)
        #expect(snapshot.feelsLike == 4.5)
        #expect(snapshot.condition == .unknown)
        #expect(snapshot.hours.isEmpty)
        #expect(snapshot.days.isEmpty)
    }
}

@MainActor
struct WeatherStoreTests {
    /// Answers from a list, one per call; records the places asked for.
    final class FakeProvider: WeatherProvider, @unchecked Sendable {
        var answers: [Result<Data, any Error>]
        var asked: [Coordinate] = []
        init(_ answers: [Result<Data, any Error>]) { self.answers = answers }

        func forecast(at coordinate: Coordinate, now: Date) async throws -> WeatherSnapshot {
            asked.append(coordinate)
            let data = try answers.removeFirst().get()
            return try OpenMeteo.snapshot(from: data, coordinate: coordinate, now: now)
        }
    }

    private func cityDefaults() -> (UserDefaults, String) {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(WeatherLocationSource.city.rawValue, forKey: SettingsKey.weatherLocationSource)
        defaults.set("İstanbul", forKey: SettingsKey.weatherCityName)
        defaults.set(41.008, forKey: SettingsKey.weatherCityLatitude)
        defaults.set(28.978, forKey: SettingsKey.weatherCityLongitude)
        return (defaults, name)
    }

    private func settle(_ store: WeatherStore) async {
        for _ in 0..<50 where store.status == .loading || store.snapshot == nil && store.status == .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func fetchesForTheCityAndCachesIt() async {
        let (defaults, name) = cityDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = FakeProvider([.success(Fixture.response)])
        let store = WeatherStore(provider: provider, defaults: defaults)

        store.refreshNow()
        await settle(store)

        #expect(store.snapshot?.temperature == 15.9)
        #expect(store.placeName == "İstanbul")
        #expect(provider.asked == [Coordinate(latitude: 41.008, longitude: 28.978)])
        // A new store (an app restart) shows the cached forecast before asking again.
        let restarted = WeatherStore(provider: FakeProvider([]), defaults: defaults)
        #expect(restarted.snapshot?.temperature == 15.9)
    }

    @Test func aFailureKeepsTheLastForecast() async {
        let (defaults, name) = cityDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = FakeProvider([.success(Fixture.response), .failure(URLError(.notConnectedToInternet))])
        let store = WeatherStore(provider: provider, defaults: defaults)
        store.refreshNow()
        await settle(store)

        store.refreshNow()
        for _ in 0..<50 where provider.asked.count < 2 || store.status == .loading {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(provider.asked.count == 2)
        #expect(store.snapshot?.temperature == 15.9)
        #expect(store.status == .idle)
    }

    @Test func withoutACityItAsksForAPlaceAndSendsNothing() async {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(WeatherLocationSource.city.rawValue, forKey: SettingsKey.weatherLocationSource)
        let provider = FakeProvider([])
        let store = WeatherStore(provider: provider, defaults: defaults)

        store.refreshNow()
        for _ in 0..<50 where store.status != .needsLocation {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.status == .needsLocation)
        #expect(provider.asked.isEmpty)
    }
}

/// Shaped like a real Open-Meteo answer (timeformat=unixtime, timezone=auto), trimmed.
private enum Fixture {
    static let response = Data(#"""
    {"latitude":41.02,"longitude":28.94,"utc_offset_seconds":10800,"timezone":"Europe/Istanbul",
     "current":{"time":1793289600,"interval":900,"temperature_2m":15.9,"apparent_temperature":14.1,"weather_code":3,"is_day":0},
     "hourly":{"time":[1793282400,1793289600,1793293200,1793296800,1793300400],
               "temperature_2m":[16.4,15.9,15.2,null,13.8],
               "weather_code":[3,3,61,61,2],
               "is_day":[1,0,0,0,0],
               "precipitation_probability":[10,20,40,null,5]},
     "daily":{"time":[1793221200,1793307600],
              "weather_code":[3,63],
              "temperature_2m_max":[18.4,16.0],
              "temperature_2m_min":[11.2,10.1],
              "precipitation_probability_max":[20,80]}}
    """#.utf8)
}
