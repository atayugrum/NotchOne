import Foundation
import Testing
@testable import NotchOne

struct HomeLogicTests {
    let allTabs = NotchTab.allCases

    @Test func showsOnlyCardsWithSomethingToShowInAFixedOrder() {
        let cards = HomeLogic.cards(hasContent: [.shelf, .notes, .nowPlaying, .battery], hidden: "", visibleTabs: allTabs)
        #expect(cards == [.nowPlaying, .battery, .notes, .shelf])
    }

    @Test func hiddenCardsAndCardsOfHiddenTabsStayAway() {
        let tabs = allTabs.filter { $0 != .clipboard }
        let cards = HomeLogic.cards(hasContent: Set(HomeCard.allCases), hidden: "weather,bogus", visibleTabs: tabs)
        #expect(!cards.contains(.weather))
        #expect(!cards.contains(.clipboard))
        // Battery has no tab of its own, so hiding tabs never hides it.
        #expect(cards.contains(.battery))
    }

    @Test func atMostSixInRowsOfThree() {
        let cards = HomeLogic.cards(hasContent: Set(HomeCard.allCases), hidden: "", visibleTabs: allTabs)
        #expect(cards.count == HomeLogic.maxCards)
        #expect(HomeLogic.rows(cards).map(\.count) == [3, 3])
        #expect(HomeLogic.rows([.notes, .battery]).map(\.count) == [2])
        #expect(HomeLogic.rows([]).isEmpty)
    }

    @Test func homeIsPutFirstForASavedOrderWithoutIt() {
        #expect(AppearanceLogic.tabs(order: "shelf,nowPlaying", hidden: "").prefix(3) == [.home, .shelf, .nowPlaying])
        // Once the user moved it, their place for it wins.
        #expect(AppearanceLogic.tabs(order: "shelf,home", hidden: "").prefix(2) == [.shelf, .home])
    }
}

@MainActor
struct CompactModeTests {
    private func makeModel(mode: NotchMode) -> (NotchViewModel, UserDefaults, String) {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(mode.rawValue, forKey: SettingsKey.notchMode)
        defaults.set(NotchOutline.pill.rawValue, forKey: SettingsKey.notchOutline)
        let metrics = NotchMetrics(notchRect: CGRect(x: 865, y: 1050, width: 190, height: 30), hasHardwareNotch: false)
        let model = NotchViewModel(activity: ActivityState(), metrics: metrics, panelFrame: CGRect(x: 576, y: 600, width: 768, height: 480))
        model.applySettings(defaults)
        return (model, defaults, name)
    }

    @Test func compactUsesTheSmallSizeUntilExpandedAndCloseResetsIt() {
        let (model, defaults, name) = makeModel(mode: .compact)
        defer { defaults.removePersistentDomain(forName: name) }
        model.open()
        #expect(model.showsCompact)
        #expect(model.openSize == NotchLayout.compactSize)

        model.expand(to: .weather)
        #expect(!model.showsCompact)
        #expect(model.selectedTab == .weather)
        #expect(model.openSize == PanelSize.regular.openSize)

        model.close()
        model.open()
        #expect(model.showsCompact)
    }

    @Test func collapseGoesBackToTheRow() {
        let (model, defaults, name) = makeModel(mode: .compact)
        defer { defaults.removePersistentDomain(forName: name) }
        model.open()
        model.expand()
        model.collapse()
        #expect(model.showsCompact)
    }

    @Test func dragsAlwaysGetTheFullNotchAndHotkeysExpandIt() {
        let (model, defaults, name) = makeModel(mode: .compact)
        defer { defaults.removePersistentDomain(forName: name) }
        model.open()
        model.dragChanged([URL(fileURLWithPath: "/tmp/a.png")])
        #expect(!model.showsCompact)
        model.dragChanged([])
        #expect(model.showsCompact)
        // What ⌃⌥K and ⌃⌥T do.
        model.expand(to: .search)
        model.hold()
        #expect(!model.showsCompact)
        #expect(model.wantsKeyboard)
    }

    @Test func compactNeverTakesTheKeyboardForATypingTab() {
        let (model, defaults, name) = makeModel(mode: .compact)
        defer { defaults.removePersistentDomain(forName: name) }
        model.show(.translate)
        model.open()
        #expect(!model.wantsKeyboard)
        model.expand()
        #expect(model.wantsKeyboard)
    }

    @Test func fullModeIgnoresExpand() {
        let (model, defaults, name) = makeModel(mode: .full)
        defer { defaults.removePersistentDomain(forName: name) }
        model.open()
        model.expand(to: .weather)
        #expect(!model.showsCompact)
        #expect(!model.isExpanded)
        #expect(model.selectedTab == .weather)
        // Mirror starts hidden, so it isn't shown.
        model.expand(to: .mirror)
        #expect(model.selectedTab == .weather)
    }
}
