import Foundation

/// UserDefaults keys and defaults. Views use them with `@AppStorage`.
enum SettingsKey {
    static let openDelayMs = "openDelayMs"
    static let closeDelayMs = "closeDelayMs"
    static let showOnDisplaysWithoutNotch = "showOnDisplaysWithoutNotch"
    static let nowPlayingEnabled = "nowPlayingEnabled"
    static let batteryAlertsEnabled = "batteryAlertsEnabled"
    static let mediaKeysEnabled = "mediaKeysEnabled"
    static let bluetoothAlertsEnabled = "bluetoothAlertsEnabled"
    static let systemNowPlayingEnabled = "systemNowPlayingEnabled"
    static let clipboardEnabled = "clipboardEnabled"
    static let openOnHover = "openOnHover"
    static let openOnFileDrag = "openOnFileDrag"
    static let notchStyle = "notchStyle"
    static let glassStrength = "glassStrength"
    static let albumTint = "albumTint"
    static let notchOutline = "notchOutline"
    static let panelSize = "panelSize"
    static let tabOrder = "tabOrder"
    static let hiddenTabs = "hiddenTabs"
    static let catchScreenshots = "catchScreenshots"
    static let catchDownloads = "catchDownloads"
    static let meetingModeEnabled = "meetingModeEnabled"
    static let gesturesEnabled = "gesturesEnabled"
    static let earPreview = "earPreview"
    static let hideFromCapture = "hideFromCapture"
    static let leftEarClick = "leftEarClick"
    static let rightEarClick = "rightEarClick"
    static let focusIndicatorEnabled = "focusIndicatorEnabled"
    static let lockScreenWidget = "lockScreenWidget"
    static let notificationsEnabled = "notificationsEnabled"
    static let notificationsHideBanners = "notificationsHideBanners"
    static let weatherEnabled = "weatherEnabled"
    static let weatherLocationSource = "weatherLocationSource"
    static let weatherCityName = "weatherCityName"
    static let weatherCityLatitude = "weatherCityLatitude"
    static let weatherCityLongitude = "weatherCityLongitude"
    static let weatherUnit = "weatherUnit"
    /// Last forecast (JSON), shown right away after a restart.
    static let weatherCache = "weatherCache"
    static let notchMode = "notchMode"
    static let homeTemplate = "homeTemplate"
    static let homeSlots = "homeSlots"
    static let hiddenHeaderItems = "hiddenHeaderItems"
    static let hiddenCompactItems = "hiddenCompactItems"
    static let earPriority = "earPriority"
    /// Language identifiers ("tr", "en-GB", "zh-Hans"); From can also be "auto".
    static let translateFrom = "translateFrom"
    static let translateTo = "translateTo"
    static let translateOtherwise = "translateOtherwise"
    /// The onboarding version last finished or skipped (0: never).
    static let onboardingVersion = "onboardingVersion"
    static let updateChecksEnabled = "updateChecksEnabled"
    static let updateLastCheck = "updateLastCheck"
    /// The newest version already mentioned in the notch.
    static let updateAnnounced = "updateAnnounced"
}

enum SettingsDefault {
    static let openDelayMs: Double = 70
    static let closeDelayMs: Double = 300
    static let showOnDisplaysWithoutNotch = true
    static let nowPlayingEnabled = true
    static let batteryAlertsEnabled = true
    static let mediaKeysEnabled = true
    static let bluetoothAlertsEnabled = true
    static let systemNowPlayingEnabled = true
    static let clipboardEnabled = true
    static let openOnHover = true
    static let openOnFileDrag = true
    static let notchStyle = NotchStyle.glass
    static let glassStrength = 0.6
    static let albumTint = true
    static let notchOutline = NotchOutline.notch
    static let panelSize = PanelSize.regular
    static let tabOrder = AppearanceLogic.encode(NotchTab.allCases)
    /// Mirror is optional, so it starts hidden.
    static let hiddenTabs = "mirror"
    static let catchScreenshots = true
    static let catchDownloads = true
    static let meetingModeEnabled = true
    static let gesturesEnabled = true
    static let earPreview = true
    static let hideFromCapture = false
    static let leftEarClick = EarClick.openPlayer
    static let rightEarClick = EarClick.playPause
    static let focusIndicatorEnabled = false
    /// Experimental (private API), so off until turned on.
    static let lockScreenWidget = false
    static let notificationsEnabled = false
    static let notificationsHideBanners = false
    static let weatherEnabled = true
    static let weatherLocationSource = WeatherLocationSource.current
    static let weatherUnit = WeatherUnit.system
    static let notchMode = NotchMode.full
    static let homeTemplate = HomeTemplate.feature
    /// System is opt-in on Home (it measures while it shows).
    static let homeSlots = HomeLogic.encode(HomeLogic.defaultSlots)
    static let earPriority = EarPriority.balanced
    static let translateFrom = TranslateLogic.auto
    static let translateTo = TranslateLogic.defaultTarget()
    static let translateOtherwise = TranslateLogic.defaultOtherwise()
    static let updateChecksEnabled = true
}

extension UserDefaults {
    func double(forKey key: String, default fallback: Double) -> Double {
        object(forKey: key) == nil ? fallback : double(forKey: key)
    }

    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }

    func value<T: RawRepresentable>(forKey key: String, default fallback: T) -> T where T.RawValue == String {
        string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}
