import AppKit
import SwiftUI

/// The Translate tab: the text, its translation and a short history. Kept in memory only
/// (translated text can be private), so it's gone when NotchOne quits.
@MainActor
@Observable
final class TranslateStore {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let source: String
        let result: String
        let from: String
        let to: String
    }

    var input = ""
    private(set) var state: TranslationState?
    private(set) var history: [Entry] = []
    /// Every language this Mac can translate, for the menus (loaded on first use).
    private(set) var languages: [(id: String, name: String)] = []
    /// The language the last text was detected as, so swapping works with Detect.
    private(set) var lastSource: String?

    static let historyLimit = 10

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var from: String { defaults.string(forKey: SettingsKey.translateFrom) ?? SettingsDefault.translateFrom }
    var to: String { defaults.string(forKey: SettingsKey.translateTo) ?? SettingsDefault.translateTo }
    var otherwise: String { defaults.string(forKey: SettingsKey.translateOtherwise) ?? SettingsDefault.translateOtherwise }

    func loadLanguages() async {
        guard languages.isEmpty else { return }
        languages = TranslateLogic.menu(await Translator.supportedLanguages())
    }

    /// ⌃⌥T is reading the selection.
    func showReading() {
        task?.cancel()
        state = .reading
    }

    func showFailure(_ message: String) {
        task?.cancel()
        state = .failed(message)
    }

    /// Translates `text` (the selection, the clipboard) and puts it in the box.
    func translate(_ text: String) {
        input = text
        translateInput()
    }

    func translateInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        guard !text.isEmpty else {
            state = nil
            return
        }
        if case .done(let source, _, _, _) = state, source == text { return }   // already shown
        let detected = TranslateLogic.detect(text)
        let pair = TranslateLogic.pair(detected: detected, from: from, to: to, otherwise: otherwise)
        lastSource = pair.source.minimalIdentifier
        state = .working(source: text)
        task = Task { [weak self] in
            let result = await Translator.translate(text, pair: pair)
            guard !Task.isCancelled, let self else { return }
            self.state = result
            if case .done(let source, let translated, let from, let to) = result, source != translated {
                self.remember(Entry(source: source, result: translated, from: from, to: to))
            }
        }
    }

    /// From becomes To and the other way round. With Detect, the detected language takes
    /// From's place.
    func swap() {
        let newTo = from == TranslateLogic.auto ? (lastSource ?? otherwise) : from
        defaults.set(to, forKey: SettingsKey.translateFrom)
        defaults.set(newTo, forKey: SettingsKey.translateTo)
        if case .done(_, let result, _, _) = state {
            input = result
        }
        state = nil
        translateInput()
    }

    func setFrom(_ id: String) {
        defaults.set(id, forKey: SettingsKey.translateFrom)
        retranslate()
    }

    func setTo(_ id: String) {
        defaults.set(id, forKey: SettingsKey.translateTo)
        retranslate()
    }

    func restore(_ entry: Entry) {
        task?.cancel()
        input = entry.source
        state = .done(source: entry.source, result: entry.result, from: entry.from, to: entry.to)
    }

    func copyResult() {
        guard case .done(_, let result, _, _) = state else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func clear() {
        task?.cancel()
        input = ""
        state = nil
    }

    private func retranslate() {
        state = nil
        translateInput()
    }

    private func remember(_ entry: Entry) {
        history.removeAll { $0.source == entry.source && $0.to == entry.to }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }
}
