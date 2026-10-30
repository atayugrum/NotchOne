import Foundation
import Testing
@testable import NotchOne

struct LocalizationTests {
    private var turkish: Bundle? {
        Bundle.main.path(forResource: "tr", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    @Test func turkishShipsWithTheApp() throws {
        let tr = try #require(turkish)
        #expect(tr.localizedString(forKey: "Settings", value: nil, table: nil) == "Ayarlar")
        #expect(tr.localizedString(forKey: "Now Playing", value: nil, table: nil) == "Şimdi Çalıyor")
        // Same word in English, different in Turkish: the weather one has its own key.
        #expect(tr.localizedString(forKey: "Clear", value: nil, table: nil) == "Temizle")
        #expect(tr.localizedString(forKey: "weather.clear", value: nil, table: nil) == "Açık")
        #expect(tr.localizedString(forKey: "weather.now", value: nil, table: nil) == "Şimdi")
        #expect(tr.localizedString(forKey: "weather.today", value: nil, table: nil) == "Bugün")
    }

    @Test func permissionPromptsAreTranslated() throws {
        let tr = try #require(turkish)
        let camera = tr.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
        #expect(camera.contains("Ayna"))
    }

    @Test func formatsKeepTheirArguments() throws {
        let tr = try #require(turkish)
        let format = tr.localizedString(forKey: "Text in %@ goes into %@; everything else into %@.", value: nil, table: nil)
        #expect(String(format: format, "Türkçe", "İngilizce", "Türkçe") == "Türkçe metinler İngilizce diline, diğer her şey Türkçe diline çevrilir.")
    }
}

struct AppLanguageTests {
    @Test func choiceIsStoredForThisAppOnly() {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(AppLanguage.current(defaults: defaults, domain: name) == .system)
        AppLanguage.set(.turkish, defaults: defaults)
        #expect(defaults.persistentDomain(forName: name)?[AppLanguage.key] as? [String] == ["tr"])
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .turkish)
        AppLanguage.set(.system, defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .system)
    }

    @Test func languagesAreNamedInTheirOwnWords() {
        #expect(AppLanguage.turkish.title == "Türkçe")
        #expect(AppLanguage.english.title == "English")
    }
}

struct PlayerAppTests {
    @Test func artworkOpensThePlayingApp() {
        var info = NowPlayingInfo(source: .spotify, title: "Song", artist: "Artist", album: "", duration: nil, position: 0, isPlaying: true, updatedAt: Date())
        #expect(info.playerBundleID == "com.spotify.client")
        info.source = .system
        info.appBundleID = "com.brave.Browser"
        #expect(info.playerBundleID == "com.brave.Browser")
        info.appBundleID = ""
        #expect(info.playerBundleID == nil)
    }
}
