import Foundation

/// The header item a tour step points at. The rest of the header dims.
enum SpotlightTarget: Equatable, Sendable {
    case tabBar
    case actions
    case status
}

/// One page of the first-launch tour (and of the `?` tutorial).
enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case tabs
    case drop
    case shortcuts
    case permissions
    case done

    var id: String { rawValue }

    /// The onboarding version that added this step. A later version shows only its new
    /// steps to people who saw an older one ("what's new").
    var since: Int {
        switch self {
        case .welcome, .tabs, .drop, .shortcuts, .done: 1
        // Version 2: every permission is asked from its own button.
        case .permissions: 2
        }
    }

    var target: SpotlightTarget? {
        switch self {
        case .welcome: .status
        case .tabs: .tabBar
        case .done: .actions
        case .drop, .shortcuts, .permissions: nil
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .tabs: "square.grid.2x2"
        case .drop: "tray.and.arrow.down"
        case .shortcuts: "command"
        case .permissions: "hand.raised"
        case .done: "checkmark"
        }
    }

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to NotchOne")
        case .tabs: String(localized: "Everything has a tab")
        case .drop: String(localized: "Drop files on the notch")
        case .shortcuts: String(localized: "Keyboard shortcuts")
        case .permissions: String(localized: "Optional permissions")
        case .done: String(localized: "You're all set")
        }
    }

    var message: String {
        switch self {
        case .welcome:
            String(localized: "Your notch now shows what's playing, the weather, your devices and running jobs. The weather and the battery stay on the right.")
        case .tabs:
            String(localized: "Home sums everything up. Reorder or hide tabs in Settings → Appearance, or switch to a smaller compact notch.")
        case .drop:
            String(localized: "Drag files onto the notch to keep them on the Shelf, send them with AirDrop, or convert and compress images and PDFs.")
        case .shortcuts:
            String(localized: "These work from any app, even while the notch is closed.")
        case .permissions:
            String(localized: "NotchOne asks for nothing until you press a button here. Each one is only for the feature next to it; skip any, and turn them on later in Settings → Privacy.")
        case .done:
            String(localized: "Press ? next to the tabs to see this tour again. Settings are behind the gear.")
        }
    }
}

enum OnboardingLogic {
    /// Bump when steps are added; give the new steps this `since`.
    static let currentVersion = 2

    static func steps(seenVersion: Int) -> [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.since > seenVersion }
    }

    /// The first launch shows the tour; later launches show only steps added since.
    static func pendingSteps(_ defaults: UserDefaults = .standard) -> [OnboardingStep] {
        steps(seenVersion: defaults.integer(forKey: SettingsKey.onboardingVersion))
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: SettingsKey.onboardingVersion)
    }
}
