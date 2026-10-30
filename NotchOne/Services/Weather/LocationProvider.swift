import CoreLocation
import MapKit

/// Where the forecast is for: the Mac's approximate location, or a city from Settings.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Access: Equatable {
        case notAsked, granted, denied
    }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Coordinate?, Never>] = []
    private var lastFix: (coordinate: Coordinate, date: Date)?
    /// You rarely move far in a few hours; reuse the last fix until then.
    private static let fixMaxAge: TimeInterval = 3 * 60 * 60

    var onAccessChange: ((Access) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // City level is all a forecast needs.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var access: Access {
        switch manager.authorizationStatus {
        case .notDetermined: .notAsked
        case .authorized, .authorizedAlways: .granted
        default: .denied
        }
    }

    /// Shows the system prompt. Only call this after the user asked for their location.
    func requestAccess() {
        SystemPromptWatcher.expectPrompt()
        manager.requestWhenInUseAuthorization()
    }

    /// nil without permission or when no fix comes in time.
    func current(now: Date = Date()) async -> Coordinate? {
        guard access == .granted else { return nil }
        if let lastFix, now.timeIntervalSince(lastFix.date) < Self.fixMaxAge { return lastFix.coordinate }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
    }

    private func finish(_ coordinate: Coordinate?) {
        if let coordinate { lastFix = (coordinate, Date()) }
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume(returning: coordinate) }
    }

    // CLLocationManager calls back on the thread that made it: the main thread here.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        MainActor.assumeIsolated { finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            onAccessChange?(access)
            if access == .denied { finish(nil) }
        }
    }
}

/// A city found by name, for Settings → Weather.
struct CityResult: Identifiable, Equatable, Sendable {
    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
    var name: String
    var detail: String
    var coordinate: Coordinate
}

enum CitySearch {
    static func search(_ query: String) async -> [CityResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(6).compactMap { item in
            let location = item.location.coordinate
            let coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
            guard coordinate.isValid else { return nil }
            return CityResult(
                name: item.name ?? text,
                detail: item.address?.shortAddress ?? "",
                coordinate: coordinate
            )
        }
    }
}
