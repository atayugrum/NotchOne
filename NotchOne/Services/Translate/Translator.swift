import Foundation
import NaturalLanguage
import Translation

/// What the Translate tab shows for the current text.
enum TranslationState: Equatable, Sendable {
    case reading
    case working(source: String)
    case done(source: String, result: String, from: String, to: String)
    /// The language packs for this pair aren't on this Mac yet.
    case needsDownload(source: String, languages: String)
    case failed(String)
}

/// The languages one translation goes between.
struct TranslationPair: Equatable, Sendable {
    var source: Locale.Language
    var target: Locale.Language
}

/// Pure language rules. "From" can be Detect; when the text is already in the "To"
/// language, it goes into the "Otherwise" language instead (Turkish ⟷ English, say).
enum TranslateLogic {
    static let auto = "auto"
    static let turkish = Locale.Language(identifier: "tr")
    static let english = Locale.Language(identifier: "en")

    /// Into the user's first language in System Settings; English speakers get Spanish as
    /// the other side. (`Locale.current` would say English: the app's own UI is English.)
    static func defaultTarget(preferred: [String] = Locale.preferredLanguages) -> String {
        preferred.first.flatMap { Locale.Language(identifier: $0).languageCode?.identifier } ?? "en"
    }

    static func defaultOtherwise(preferred: [String] = Locale.preferredLanguages) -> String {
        defaultTarget(preferred: preferred) == "en" ? "es" : "en"
    }

    static func pair(detected: String?, from: String, to: String, otherwise: String) -> TranslationPair {
        let target = Locale.Language(identifier: to)
        let fallback = Locale.Language(identifier: otherwise)
        guard from == auto else {
            return TranslationPair(source: Locale.Language(identifier: from), target: target)
        }
        let source = detected.map(Locale.Language.init(identifier:)) ?? fallback
        return TranslationPair(source: source, target: isSame(source, target) ? fallback : target)
    }

    static func isSame(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode && a.script == b.script
    }

    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    static func displayName(_ language: Locale.Language, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.languageCode.flatMap { locale.localizedString(forLanguageCode: $0.identifier) }
            ?? language.minimalIdentifier
    }

    static func displayName(_ identifier: String) -> String {
        identifier == auto ? String(localized: "Detect") : displayName(Locale.Language(identifier: identifier))
    }

    /// One entry per language, named in the user's language and sorted by that name.
    static func menu(_ languages: [Locale.Language], locale: Locale = .current) -> [(id: String, name: String)] {
        var seen = Set<String>()
        return languages
            .compactMap { language -> (id: String, name: String)? in
                let id = language.minimalIdentifier
                guard seen.insert(id).inserted else { return nil }
                return (id, displayName(language, locale: locale))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// On-device translation with Apple's Translation framework.
enum Translator {
    /// Apple's Translation framework arrived in macOS 15.
    static var isSupported: Bool {
        if #available(macOS 15.0, *) { true } else { false }
    }

    /// Every language this Mac can translate between.
    static func supportedLanguages() async -> [Locale.Language] {
        guard #available(macOS 15.0, *) else { return [] }
        return await LanguageAvailability().supportedLanguages
    }

    static func availability(_ pair: TranslationPair) async -> LanguageStatus {
        guard #available(macOS 15.0, *) else { return .unsupported }
        return switch await LanguageAvailability().status(from: pair.source, to: pair.target) {
        case .installed: .installed
        case .supported: .downloadable
        default: .unsupported
        }
    }

    static func translate(_ text: String, pair: TranslationPair) async -> TranslationState {
        let from = TranslateLogic.displayName(pair.source)
        let to = TranslateLogic.displayName(pair.target)
        if TranslateLogic.isSame(pair.source, pair.target) {
            return .done(source: text, result: text, from: from, to: to)
        }

        guard #available(macOS 15.0, *) else {
            return .failed(String(localized: "Translation isn't available."))
        }
        switch await LanguageAvailability().status(from: pair.source, to: pair.target) {
        case .installed:
            do {
                let result: String
                if #available(macOS 26.0, *) {
                    let session = TranslationSession(installedSource: pair.source, target: pair.target)
                    result = try await session.translate(text).targetText
                } else {
                    result = try await SessionTranslation.shared.translate(text, pair: pair)
                }
                return .done(source: text, result: result, from: from, to: to)
            } catch {
                return .failed(String(localized: "Translation failed: \(error.localizedDescription)"))
            }
        case .supported:
            return .needsDownload(source: text, languages: String(localized: "\(from) and \(to)"))
        case .unsupported:
            return .failed(String(localized: "\(from) to \(to) can't be translated on this Mac."))
        @unknown default:
            return .failed(String(localized: "Translation isn't available."))
        }
    }
}
