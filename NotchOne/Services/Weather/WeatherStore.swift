import AppKit

/// The forecast the notch shows. Nothing runs in the background: it refreshes when the
/// notch opens (at most every 30 minutes) and keeps the last answer, also across restarts.
@MainActor
@Observable
final class WeatherStore {
    enum Status: Equatable {
        case idle
        case loading
        /// No permission asked yet and no city chosen: the tab offers both.
        case needsLocation
        /// Location access was turned off for NotchOne.
        case locationDenied
        case failed(String)
    }

    private(set) var snapshot: WeatherSnapshot?
    private(set) var status: Status = .idle
    /// Name shown with the forecast: the chosen city, or nil for the current location.
    private(set) var placeName: String?

    @ObservationIgnored private let provider: any WeatherProvider
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private lazy var location = LocationProvider()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped per refresh, so a cancelled one doesn't clear the handle of its successor.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastFailure: Date?

    init(provider: any WeatherProvider = OpenMeteoProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        snapshot = defaults.data(forKey: SettingsKey.weatherCache)
            .flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: SettingsKey.weatherEnabled, default: SettingsDefault.weatherEnabled)
    }

    private var source: WeatherLocationSource {
        defaults.value(forKey: SettingsKey.weatherLocationSource, default: SettingsDefault.weatherLocationSource)
    }

    /// The city from Settings, if one is chosen and valid.
    private var city: (name: String, coordinate: Coordinate)? {
        guard let name = defaults.string(forKey: SettingsKey.weatherCityName), !name.isEmpty,
              defaults.object(forKey: SettingsKey.weatherCityLatitude) != nil
        else { return nil }
        let coordinate = Coordinate(
            latitude: defaults.double(forKey: SettingsKey.weatherCityLatitude),
            longitude: defaults.double(forKey: SettingsKey.weatherCityLongitude)
        )
        return coordinate.isValid ? (name, coordinate) : nil
    }

    /// A recent forecast for the place that's chosen now, for the small badge in the header.
    func badgeSnapshot(now: Date = Date()) -> WeatherSnapshot? {
        guard isEnabled, let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < WeatherLogic.badgeMaxAge else { return nil }
        return snapshot
    }

    /// Called when the notch opens. Never shows a permission prompt.
    func refreshIfNeeded() {
        guard isEnabled, task == nil else { return }
        start(force: false)
    }

    /// "Retry", or after the place changed in Settings.
    func refreshNow() {
        guard isEnabled else { return }
        task?.cancel()
        lastFailure = nil
        start(force: true)
    }

    /// The user pressed "Use my location": switch to it and ask macOS for access.
    func useCurrentLocation() {
        defaults.set(WeatherLocationSource.current.rawValue, forKey: SettingsKey.weatherLocationSource)
        location.onAccessChange = { [weak self] access in
            if access == .granted { self?.refreshNow() } else if access == .denied { self?.status = .locationDenied }
        }
        if location.access == .notAsked {
            location.requestAccess()
        } else {
            refreshNow()
        }
    }

    private func start(force: Bool) {
        generation += 1
        let current = generation
        task = Task { [weak self] in
            await self?.refresh(force: force)
            if self?.generation == current { self?.task = nil }
        }
    }

    func openWeatherApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func refresh(force: Bool) async {
        guard let place = await resolvePlace() else { return }
        placeName = place.name
        let now = Date()
        guard force || WeatherLogic.shouldRefresh(snapshot: snapshot, coordinate: place.coordinate, lastFailure: lastFailure, now: now)
        else {
            if status == .loading || status == .needsLocation { status = .idle }
            return
        }
        status = .loading
        do {
            let fresh = try await provider.forecast(at: place.coordinate, now: now)
            guard !Task.isCancelled else { return }
            snapshot = fresh
            status = .idle
            lastFailure = nil
            if let data = try? JSONEncoder().encode(fresh) { defaults.set(data, forKey: SettingsKey.weatherCache) }
        } catch {
            guard !Task.isCancelled else { return }
            lastFailure = Date()
            // A stale forecast beats an empty card; only say it failed when there's nothing.
            status = snapshot == nil ? .failed(Self.message(for: error)) : .idle
        }
    }

    private func resolvePlace() async -> (name: String?, coordinate: Coordinate)? {
        switch source {
        case .city:
            guard let city else {
                status = .needsLocation
                return nil
            }
            return (city.name, city.coordinate)
        case .current:
            switch location.access {
            case .notAsked:
                status = .needsLocation
                return nil
            case .denied:
                status = .locationDenied
                return nil
            case .granted:
                guard let coordinate = await location.current() else {
                    if snapshot == nil { status = .failed("Couldn't find where this Mac is right now.") }
                    return nil
                }
                return (nil, coordinate)
            }
        }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? WeatherError, let text = error.errorDescription { return text }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline." }
        return "Couldn't load the weather."
    }
}
