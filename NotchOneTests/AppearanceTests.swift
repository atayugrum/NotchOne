import Foundation
import Testing
@testable import NotchOne

struct AppearanceTests {
    @Test func defaultStrengthGivesAboutFortyPercentTint() {
        #expect(abs(AppearanceLogic.glassDarkness(strength: 0.6) - 0.42) < 0.001)
        #expect(AppearanceLogic.glassDarkness(strength: -1) == AppearanceLogic.glassDarkness(strength: 0))
        #expect(AppearanceLogic.glassDarkness(strength: 2) == AppearanceLogic.glassDarkness(strength: 1))
    }

    @Test func realNotchIsNeverAPill() {
        #expect(AppearanceLogic.outline(setting: .pill, hasHardwareNotch: true) == .notch)
        #expect(AppearanceLogic.outline(setting: .pill, hasHardwareNotch: false) == .pill)
    }

    @Test func tabOrderIsKeptAndMissingTabsAreAppended() {
        let tabs = AppearanceLogic.tabs(order: "notes,bogus,shelf,notes", hidden: "")
        #expect(tabs == [.home, .notes, .shelf, .nowPlaying, .weather, .clipboard, .search, .translate, .system, .mirror])
    }

    @Test func hiddenTabsAreRemovedButOneAlwaysStays() {
        #expect(AppearanceLogic.tabs(order: "", hidden: "clipboard") == [.home, .nowPlaying, .weather, .shelf, .search, .translate, .system, .notes, .mirror])
        let all = AppearanceLogic.encode(NotchTab.allCases)
        // Hiding everything keeps one tab in the bar, and Search (a button) always stays.
        #expect(AppearanceLogic.tabs(order: "shelf", hidden: all) == [.shelf, .search])
    }

    @Test func searchCantBeHiddenAndIsntInTheBar() {
        #expect(AppearanceLogic.tabs(order: "", hidden: "search").contains(.search))
        #expect(!NotchTab.search.inTabBar)
    }

    @Test func movingTabsSwapsNeighboursAndStopsAtTheEnds() {
        let order: [NotchTab] = [.nowPlaying, .shelf, .clipboard, .notes]
        #expect(AppearanceLogic.move(.shelf, by: -1, in: order) == [.shelf, .nowPlaying, .clipboard, .notes])
        #expect(AppearanceLogic.move(.notes, by: 1, in: order) == order)
        #expect(AppearanceLogic.move(.nowPlaying, by: -1, in: order) == order)
    }

    @Test func panelSizesGrow() {
        #expect(PanelSize.compact.openSize.width < PanelSize.regular.openSize.width)
        #expect(PanelSize.large.openSize.width == NotchLayout.maxOpenSize.width)
    }

    @Test func greyArtworkGivesGraphite() {
        #expect(AccentColor.tint(fromAverage: AccentColor(red: 0.5, green: 0.5, blue: 0.52)) == .graphite)
        #expect(AccentColor.tint(fromAverage: AccentColor(red: 0.02, green: 0.03, blue: 0.02)) == .graphite)
    }

    @Test func colourfulArtworkKeepsItsHueAndGetsVisible() {
        let tint = AccentColor.tint(fromAverage: AccentColor(red: 0.3, green: 0.05, blue: 0.05))
        #expect(tint.red > tint.green && tint.red > tint.blue)
        #expect(max(tint.red, tint.green, tint.blue) >= 0.59)
    }

    @Test func clickModeNeverOpensOnHover() {
        #expect(HoverLogic.decide(state: .closed, isInside: true, pending: nil, opensOnHover: false) == HoverDecision.none)
        #expect(HoverLogic.decide(state: .open, isInside: false, pending: nil, opensOnHover: false) == .scheduleClose)
    }
}

struct RemovedTabsTests {
    @Test func savedOrderWithRemovedTabsStillWorks() {
        // Saved before the Claude and Activity tabs were removed.
        let tabs = AppearanceLogic.tabs(order: "home,activity,claude,shelf", hidden: "claude")
        #expect(tabs.prefix(2) == [.home, .shelf])
        #expect(NotchTab(rawValue: "claude") == nil)
        #expect(NotchTab(rawValue: "activity") == nil)
        #expect(NotchTab(rawValue: "timer") == nil)
        // A saved Home with the removed Timer card still loads.
        #expect(HomeCard(rawValue: "timer") == nil)
    }

    @Test func notificationsCardHasNoTab() {
        #expect(HomeCard.activity.tab == nil)
    }
}
