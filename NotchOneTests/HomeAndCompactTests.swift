import Foundation
import Testing
@testable import NotchOne

struct HomeLogicTests {
    let allTabs = NotchTab.allCases

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
    @Test func everyTemplateFillsItsRows() {
        for template in HomeTemplate.allCases {
            #expect(template.rows.allSatisfy { $0.reduce(0, +) == HomeLogic.rowUnits })
            #expect(template.slotCount <= HomeLogic.maxSlots)
        }
    }

    @Test func savedBoxesKeepTheirPlaces() {
        let slots = HomeLogic.slots("weather,,bogus")
        #expect(slots.count == HomeLogic.maxSlots)
        #expect(slots[0] == .weather)
        #expect(slots[1] == nil)
        #expect(slots[2] == nil)
        #expect(HomeLogic.slots(HomeLogic.encode(HomeLogic.defaultSlots)) == HomeLogic.defaultSlots)
        #expect(HomeLogic.slots("") == HomeLogic.defaultSlots)
    }

    @Test func aCardChosenTwiceSwaps() {
        let slots: [HomeCard?] = [.nowPlaying, .weather, nil]
        #expect(HomeLogic.assign(.weather, to: 0, in: slots) == [.weather, .nowPlaying, nil])
        #expect(HomeLogic.assign(.battery, to: 2, in: slots) == [.nowPlaying, .weather, .battery])
        #expect(HomeLogic.assign(nil, to: 1, in: slots) == [.nowPlaying, nil, nil])
    }

    @Test func aBoxOffersOnlyCardsNotInOtherBoxes() {
        let slots: [HomeCard?] = [.nowPlaying, .weather, .battery, .notes, .clipboard, .shelf]
        let options = HomeLogic.options(forSlot: 0, in: slots, template: .feature)
        #expect(options.contains(.nowPlaying))
        #expect(!options.contains(.weather))
        #expect(!options.contains(.clipboard))
        // The feature template has five boxes, so the sixth doesn't count.
        #expect(options.contains(.shelf))
        #expect(options.contains(.system))
    }

    @Test func boxesShareTheRow() {
        #expect(HomeLogic.width(span: 3, count: 2, in: 308, spacing: 8) == 150)
        #expect(HomeLogic.width(span: 6, count: 1, in: 300, spacing: 8) == 300)
    }

    @Test func rowsKnowTheirFirstBox() {
        #expect(HomeLogic.firstSlot(ofRow: 1, in: .feature) == 2)
        #expect(HomeLogic.firstSlot(ofRow: 1, in: .even) == 3)
    }

    @Test func movingPutsATabBeforeAnother() {
        #expect(LayoutLogic.move(3, before: 1, in: [1, 2, 3]) == [3, 1, 2])
        #expect(LayoutLogic.move(1, before: 9, in: [1, 2]) == [1, 2])
    }

    @Test func listsAddAndRemoveNames() {
        #expect(LayoutLogic.setting("b", in: "a", to: true) == "a,b")
        #expect(LayoutLogic.setting("a", in: "a,b", to: false) == "b")
        #expect(!LayoutLogic.contains("ab", in: "abc"))
    }

    @Test func musicFirstKeepsOnlyUrgentThingsOverTheMusic() {
        #expect(EarPriority.music.beatsMusic(70))
        #expect(!EarPriority.music.beatsMusic(60))
        #expect(EarPriority.balanced.beatsMusic(40))
    }
}
