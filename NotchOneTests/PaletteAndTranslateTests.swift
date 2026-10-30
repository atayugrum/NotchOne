import Foundation
import Testing
@testable import NotchOne

struct PaletteLogicTests {
    let now = Date()

    private func clip(_ text: String) -> ClipboardItem {
        ClipboardItem(content: .text(text), sourceBundleID: nil, copiedAt: now)
    }

    @Test func findsClipboardItemsIgnoringCaseAndAccents() {
        let items = [clip("Meeting notes for Monday"), clip("Şirket adresi: İstanbul"), clip("unrelated")]
        let results = PaletteLogic.results(query: "istanbul", clipboard: items, shelf: [], tabs: [])
        #expect(results.first?.kind == .clipboard(items[1].id))
        #expect(!results.contains { $0.kind == .clipboard(items[2].id) })
    }

    @Test func wordStartsRankAboveMiddleMatches() {
        #expect(PaletteLogic.score("report final", query: "fin") == 2)
        #expect(PaletteLogic.score("define", query: "fin") == 1)
        #expect(PaletteLogic.score("abc", query: "x") == 0)
        let items = [clip("define it"), clip("final report")]
        let results = PaletteLogic.results(query: "fin", clipboard: items, shelf: [], tabs: [])
        #expect(results.first?.kind == .clipboard(items[1].id))
    }

    @Test func emptyQueryShowsRecentClipboardOnly() {
        let items = (0..<12).map { clip("item \($0)") }
        let results = PaletteLogic.results(query: "", clipboard: items, shelf: [URL(fileURLWithPath: "/a.pdf")], tabs: [.shelf])
        #expect(results.count == PaletteLogic.maxResults)
        #expect(results.allSatisfy { if case .clipboard = $0.kind { true } else { false } })
    }

    @Test func shelfAndTabsShowUp() {
        #expect(PaletteLogic.results(query: "shel", clipboard: [], shelf: [], tabs: [.shelf]).first?.kind == .tab(.shelf))
        #expect(PaletteLogic.results(query: "notes", clipboard: [], shelf: [URL(fileURLWithPath: "/x/notes.txt")], tabs: [])
            .first?.kind == .shelf(URL(fileURLWithPath: "/x/notes.txt")))
    }
}

struct TranslateLogicTests {
    private func pair(_ detected: String?, from: String = TranslateLogic.auto, to: String = "tr", otherwise: String = "en") -> TranslationPair {
        TranslateLogic.pair(detected: detected, from: from, to: to, otherwise: otherwise)
    }

    @Test func detectWithTurkishAndEnglishWorksLikeBefore() {
        // Turkish text goes to English; anything else goes to Turkish.
        #expect(pair("tr").target == TranslateLogic.english)
        #expect(pair("en").target == TranslateLogic.turkish)
        #expect(pair("de") == TranslationPair(source: Locale.Language(identifier: "de"), target: TranslateLogic.turkish))
        // Undetectable text is taken as the other language.
        #expect(pair(nil) == TranslationPair(source: TranslateLogic.english, target: TranslateLogic.turkish))
    }

    @Test func anyPairOfLanguagesWorks() {
        #expect(pair("ja", to: "de", otherwise: "fr").target == Locale.Language(identifier: "de"))
        #expect(pair("de", to: "de", otherwise: "fr").target == Locale.Language(identifier: "fr"))
        // A chosen From wins over detection.
        let chosen = pair("en", from: "es", to: "pt-BR")
        #expect(chosen.source == Locale.Language(identifier: "es"))
        #expect(chosen.target == Locale.Language(identifier: "pt-BR"))
    }

    @Test func scriptsCountAsDifferentLanguages() {
        #expect(!TranslateLogic.isSame(Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "zh-Hant")))
        #expect(TranslateLogic.isSame(Locale.Language(identifier: "en"), Locale.Language(identifier: "en-GB")))
    }

    @Test func defaultsFollowTheSystemLanguage() {
        #expect(TranslateLogic.defaultTarget(preferred: ["tr-TR", "en-TR"]) == "tr")
        #expect(TranslateLogic.defaultOtherwise(preferred: ["tr-TR", "en-TR"]) == "en")
        #expect(TranslateLogic.defaultTarget(preferred: ["en-US"]) == "en")
        #expect(TranslateLogic.defaultOtherwise(preferred: ["en-US"]) == "es")
        #expect(TranslateLogic.defaultTarget(preferred: ["zh-Hans-CN"]) == "zh")
        #expect(TranslateLogic.defaultTarget(preferred: []) == "en")
    }

    @Test func languageMenuIsNamedSortedAndWithoutDuplicates() {
        let languages = ["tr", "en", "de", "en"].map(Locale.Language.init(identifier:))
        let menu = TranslateLogic.menu(languages, locale: Locale(identifier: "en_US"))
        #expect(menu.map(\.id) == ["en", "de", "tr"])
        #expect(menu.map(\.name) == ["English", "German", "Turkish"])
        #expect(TranslateLogic.displayName(TranslateLogic.auto) == "Detect")
    }

    @Test func detectsLanguages() {
        #expect(TranslateLogic.detect("Bugün hava çok güzel, dışarı çıkalım mı?") == "tr")
        #expect(TranslateLogic.detect("The weather is lovely today, shall we go outside?") == "en")
    }

    @Test func searchTabIsNotOfferedFromItself() {
        let results = PaletteLogic.results(query: "sea", clipboard: [], shelf: [], tabs: [.search, .weather])
        #expect(!results.contains { $0.kind == .tab(.search) })
    }
}

@MainActor
struct TranslateStoreTests {
    private func makeStore() -> (TranslateStore, UserDefaults, String) {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(TranslateLogic.auto, forKey: SettingsKey.translateFrom)
        defaults.set("tr", forKey: SettingsKey.translateTo)
        defaults.set("en", forKey: SettingsKey.translateOtherwise)
        return (TranslateStore(defaults: defaults), defaults, name)
    }

    @Test func swappingWithDetectUsesTheDetectedLanguage() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.translate("Guten Morgen, wie geht es dir heute?")
        #expect(store.lastSource == "de")

        store.swap()
        #expect(defaults.string(forKey: SettingsKey.translateFrom) == "tr")
        #expect(defaults.string(forKey: SettingsKey.translateTo) == "de")
    }

    @Test func swappingAChosenPairTurnsItAround() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.setFrom("es")
        store.swap()
        #expect(defaults.string(forKey: SettingsKey.translateFrom) == "tr")
        #expect(defaults.string(forKey: SettingsKey.translateTo) == "es")
    }

    @Test func emptyTextClearsTheResult() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.showFailure("x")
        store.input = "   "
        store.translateInput()
        #expect(store.state == nil)
        store.translate("Merhaba")
        #expect(store.state == .working(source: "Merhaba"))
        store.clear()
        #expect(store.input.isEmpty)
        #expect(store.state == nil)
    }
}

@MainActor
struct HoldAndTabSizeTests {
    private func makeModel() -> NotchViewModel {
        let metrics = NotchMetrics(notchRect: CGRect(x: 865, y: 1050, width: 190, height: 30), hasHardwareNotch: false)
        let model = NotchViewModel(activity: ActivityState(), metrics: metrics, panelFrame: CGRect(x: 576, y: 600, width: 768, height: 480))
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(NotchOutline.pill.rawValue, forKey: SettingsKey.notchOutline)
        model.applySettings(defaults)
        defaults.removePersistentDomain(forName: name)
        return model
    }

    @Test func holdKeepsItOpenUntilClosed() {
        let model = makeModel()
        model.hold()
        #expect(model.isOpen)
        #expect(model.isPinnedOpen)
        model.close()
        #expect(!model.isHeld)
        #expect(!model.isPinnedOpen)
    }

    @Test func typingTabsAreTallerAndTakeTheKeyboard() {
        let model = makeModel()
        model.open()
        for tab in [NotchTab.search, .translate] {
            model.show(tab)
            #expect(model.openSize.height == NotchLayout.typingHeight)
            #expect(model.wantsKeyboard)
        }
        model.show(.weather)
        #expect(model.openSize == PanelSize.regular.openSize)
        #expect(!model.wantsKeyboard)
    }
}
