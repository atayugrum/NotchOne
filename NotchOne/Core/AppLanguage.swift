import AppKit

/// The app's own language (Settings → General). macOS reads it when the app starts, so a
/// change needs a restart.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    /// Each language in its own words, so it can be found from any language.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }

    static let key = "AppleLanguages"

    /// The language chosen for this app only (not the Mac's global list).
    static func current(defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) -> AppLanguage {
        let chosen = domain.flatMap { defaults.persistentDomain(forName: $0)?[key] as? [String] }?.first
        return chosen.flatMap { code in allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } } ?? .system
    }

    static func set(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set([language.rawValue], forKey: key)
        }
    }

    /// Starts a new copy a moment after this one quits, so two notches never overlap.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
