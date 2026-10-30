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

struct HomeLayoutTests {
    @Test func savedOrderIsKeptAndNewCardsGoLast() {
        let cards = HomeLogic.ordered("notes,bogus,weather,notes")
        #expect(Array(cards.prefix(2)) == [.notes, .weather])
        #expect(cards.count == HomeCard.allCases.count)
    }

    @Test func aWideCardTakesTwoColumnsAndRowsAreFilled() {
        let rows = HomeLogic.rows([.nowPlaying, .weather, .battery, .notes], wide: "nowPlaying")
        #expect(rows.map { $0.map(\.span) } == [[2, 1], [1, 2]])
    }

    @Test func aWideCardThatDoesntFitStartsTheNextRow() {
        let rows = HomeLogic.rows([.weather, .battery, .nowPlaying], wide: "nowPlaying")
        #expect(rows.map { $0.map(\.card) } == [[.weather, .battery], [.nowPlaying]])
        #expect(rows.map { $0.map(\.span) } == [[1, 2], [3]])
    }

    @Test func cardsPastTheLastRowDontShow() {
        let rows = HomeLogic.rows(HomeCard.allCases, wide: "nowPlaying,weather,battery,activity,devices")
        #expect(rows.count == HomeLogic.maxRows)
    }

    @Test func movingPutsACardBeforeAnother() {
        #expect(LayoutLogic.move(3, before: 1, in: [1, 2, 3]) == [3, 1, 2])
        #expect(LayoutLogic.move(1, before: 3, in: [1, 2, 3]) == [2, 1, 3])
        #expect(LayoutLogic.move(1, before: 9, in: [1, 2]) == [1, 2])
    }

    @Test func listsAddAndRemoveNames() {
        #expect(LayoutLogic.setting("b", in: "a", to: true) == "a,b")
        #expect(LayoutLogic.setting("a", in: "a,b", to: false) == "b")
        #expect(LayoutLogic.contains("a", in: "a,b"))
        #expect(!LayoutLogic.contains("ab", in: "abc"))
    }

    @Test func everyPresetCoversEveryCard() {
        for preset in HomePreset.allCases {
            #expect(Set(preset.order) == Set(HomeCard.allCases))
            #expect(preset.order.count == HomeCard.allCases.count)
        }
    }

    @Test func musicFirstKeepsOnlyUrgentThingsOverTheMusic() {
        #expect(EarPriority.music.beatsMusic(100))
        #expect(EarPriority.music.beatsMusic(70))
        #expect(!EarPriority.music.beatsMusic(60))
        #expect(EarPriority.balanced.beatsMusic(40))
    }
}
