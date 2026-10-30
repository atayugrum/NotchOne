import AppKit
import Testing
@testable import NotchOne

@MainActor
struct SettingsInNotchTests {
    private func makeModel(mode: NotchMode = .full) -> NotchViewModel {
        let metrics = NotchMetrics(notchRect: CGRect(x: 865, y: 1050, width: 190, height: 30), hasHardwareNotch: false)
        let model = NotchViewModel(activity: ActivityState(), metrics: metrics, panelFrame: CGRect(x: 576, y: 600, width: 768, height: 480))
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(NotchOutline.pill.rawValue, forKey: SettingsKey.notchOutline)
        defaults.set(mode.rawValue, forKey: SettingsKey.notchMode)
        model.applySettings(defaults)
        defaults.removePersistentDomain(forName: name)
        return model
    }

    @Test func openingSettingsShowsThePageBigAndHeld() {
        let model = makeModel()
        model.openSettings(.weather)
        #expect(model.isOpen)
        #expect(model.isHeld)
        #expect(model.settingsPage == .weather)
        #expect(model.openSize == NotchLayout.settingsSize(base: PanelSize.regular.openSize))
        // City search is typed into.
        #expect(model.wantsKeyboard)

        model.showSettingsPage(.about)
        #expect(model.settingsPage == .about)
        model.closeSettings()
        #expect(model.settingsPage == nil)
        #expect(model.openSize == PanelSize.regular.openSize)
    }

    @Test func closingTheNotchLeavesSettings() {
        let model = makeModel()
        model.openSettings()
        model.close()
        #expect(model.settingsPage == nil)
        model.open()
        #expect(model.settingsPage == nil)
    }

    @Test func settingsAlwaysGetTheFullNotchInCompactMode() {
        let model = makeModel(mode: .compact)
        model.open()
        #expect(model.showsCompact)
        model.openSettings(.general)
        #expect(!model.showsCompact)
        model.closeSettings()
        #expect(model.showsCompact)
    }

    @Test func anOpenMenuKeepsOnlyAnOpenNotchOpen() {
        let model = makeModel()
        model.isMenuOpen = true
        // The menu bar's own menu mustn't open the notch.
        #expect(!model.isPinnedOpen)
        model.open()
        #expect(model.isPinnedOpen)
        model.isMenuOpen = false
        #expect(!model.isPinnedOpen)
    }

    @Test func everyPageHasATitleAndARealSymbol() {
        for page in SettingsPage.allCases {
            #expect(!page.title.isEmpty)
            #expect(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func settingsOpenerReachesItsHandler() {
        var opened: SettingsPage?
        SettingsOpener.handler = { opened = $0 }
        defer { SettingsOpener.handler = nil }
        SettingsOpener.open(page: .translate)
        #expect(opened == .translate)
    }
}
