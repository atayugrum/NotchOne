import Foundation

/// Owns the services and starts/stops them when their setting changes.
@MainActor
final class ServiceCoordinator {
    let activity = ActivityState()
    private let battery: BatteryService
    private var nowPlaying: NowPlayingService?
    private var mediaKeys: MediaKeyService?
    private var bluetooth: BluetoothService?
    private var meeting: MeetingMonitor?
    private var focus: FocusMonitor?
    private var lockScreen: LockScreenController?
    private var notifications: NotificationMirror?
    private var defaultsObserver: NSObjectProtocol?
    private(set) lazy var input = ExternalInput(store: activity.live)
    private lazy var fileCatcher = FileCatcher(activity: activity)
    private var catcherSettings: (screenshots: Bool, downloads: Bool)?
    private var weatherPlace: String?

    init() {
        battery = BatteryService(activity: activity)
    }

    func start() {
        // Battery is event driven and cheap; it also feeds the % in the open notch.
        battery.start()
        input.start()
        applySettings()
        activity.updates.checkIfDue()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    func stop() {
        activity.notes.saveNow()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        battery.stop()
        input.stop()
        fileCatcher.stop()
        activity.live.removeAll()
        nowPlaying?.stop()
        mediaKeys?.stop()
        meeting?.stop()
        meeting = nil
        focus?.stop()
        focus = nil
        lockScreen?.stop()
        lockScreen = nil
        notifications?.stop()
        notifications = nil
        bluetooth?.stop()
        activity.clipboard.stop()
        nowPlaying = nil
        mediaKeys = nil
        bluetooth = nil
    }

    private func applySettings() {
        toggle(
            &nowPlaying,
            enabled: Self.isOn(SettingsKey.nowPlayingEnabled, SettingsDefault.nowPlayingEnabled),
            make: { NowPlayingService(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        nowPlaying?.setSystemSourceEnabled(
            Self.isOn(SettingsKey.systemNowPlayingEnabled, SettingsDefault.systemNowPlayingEnabled)
        )
        toggle(
            &mediaKeys,
            enabled: Self.isOn(SettingsKey.mediaKeysEnabled, SettingsDefault.mediaKeysEnabled),
            make: { MediaKeyService(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        if Self.isOn(SettingsKey.clipboardEnabled, SettingsDefault.clipboardEnabled) {
            activity.clipboard.start()
        } else if activity.clipboard.isRunning {
            activity.clipboard.stop()
        }
        // Watching Desktop and Downloads makes macOS ask for folder access: only once you've
        // pressed Allow for it (tour or Settings → Privacy).
        let folders = PermissionGate.allows(.folders)
        let catcher = (
            screenshots: folders && Self.isOn(SettingsKey.catchScreenshots, SettingsDefault.catchScreenshots),
            downloads: folders && Self.isOn(SettingsKey.catchDownloads, SettingsDefault.catchDownloads)
        )
        if catcherSettings.map({ $0 != catcher }) ?? true {
            catcherSettings = catcher
            fileCatcher.start(screenshots: catcher.screenshots, downloads: catcher.downloads)
        }
        toggle(
            &meeting,
            enabled: Self.isOn(SettingsKey.meetingModeEnabled, SettingsDefault.meetingModeEnabled),
            make: { MeetingMonitor(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        toggle(
            &lockScreen,
            enabled: Self.isOn(SettingsKey.lockScreenWidget, SettingsDefault.lockScreenWidget),
            make: { LockScreenController(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        toggle(
            &notifications,
            enabled: Self.isOn(SettingsKey.notificationsEnabled, SettingsDefault.notificationsEnabled),
            make: { NotificationMirror(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        toggle(
            &focus,
            enabled: Self.isOn(SettingsKey.focusIndicatorEnabled, SettingsDefault.focusIndicatorEnabled),
            make: { FocusMonitor(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
        // A new place (or weather turned back on) gets its forecast right away.
        let defaults = UserDefaults.standard
        let place = [SettingsKey.weatherEnabled, SettingsKey.weatherLocationSource, SettingsKey.weatherCityName,
                     SettingsKey.weatherCityLatitude, SettingsKey.weatherCityLongitude]
            .map { defaults.object(forKey: $0).map { "\($0)" } ?? "" }
            .joined(separator: "|")
        if let weatherPlace, weatherPlace != place { activity.weather.refreshNow() }
        weatherPlace = place
        toggle(
            &bluetooth,
            // Reading paired devices makes macOS ask for Bluetooth: only once allowed.
            enabled: Self.isOn(SettingsKey.bluetoothAlertsEnabled, SettingsDefault.bluetoothAlertsEnabled)
                && PermissionGate.allows(.bluetooth),
            make: { BluetoothService(activity: $0) },
            start: { $0.start() },
            stop: { $0.stop() }
        )
    }

    private func toggle<Service>(
        _ service: inout Service?,
        enabled: Bool,
        make: (ActivityState) -> Service,
        start: (Service) -> Void,
        stop: (Service) -> Void
    ) {
        if enabled, service == nil {
            let created = make(activity)
            start(created)
            service = created
        } else if !enabled, let existing = service {
            stop(existing)
            service = nil
        }
    }

    private static func isOn(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.bool(forKey: key, default: fallback)
    }
}
