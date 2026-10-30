import Foundation
import CoreGraphics
import Testing
@testable import NotchOne

struct SwipeLogicTests {
    @Test func closedNotchSkipsTracksOnlyWithMusic() {
        #expect(SwipeLogic.action(direction: .left, isOpen: false, tab: .home, inHeader: false, hasMusic: true) == .nextTrack)
        #expect(SwipeLogic.action(direction: .right, isOpen: false, tab: .home, inHeader: false, hasMusic: true) == .previousTrack)
        #expect(SwipeLogic.action(direction: .right, isOpen: false, tab: .home, inHeader: false) == SwipeAction.none)
    }

    @Test func mouseWheelScrollsSidewaysLists() {
        #expect(SwipeLogic.wheelScrollsSideways(tab: .clipboard, isOpen: true, hasPhase: false, dx: 0, dy: -3))
        #expect(SwipeLogic.wheelScrollsSideways(tab: .shelf, isOpen: true, hasPhase: false, dx: 0, dy: 3))
        // Trackpads, closed notch, other tabs and real sideways wheels stay as they are.
        #expect(!SwipeLogic.wheelScrollsSideways(tab: .clipboard, isOpen: true, hasPhase: true, dx: 0, dy: 3))
        #expect(!SwipeLogic.wheelScrollsSideways(tab: .clipboard, isOpen: false, hasPhase: false, dx: 0, dy: 3))
        #expect(!SwipeLogic.wheelScrollsSideways(tab: .notes, isOpen: true, hasPhase: false, dx: 0, dy: 3))
        #expect(!SwipeLogic.wheelScrollsSideways(tab: .clipboard, isOpen: true, hasPhase: false, dx: 3, dy: 0))
    }

    @Test func sidewaysEventMovesTheVerticalDelta() throws {
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -7, wheel2: 0, wheel3: 0))
        let turned = try #require(SwipeLogic.sideways(event))
        #expect(turned.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 0)
        #expect(turned.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        #expect(turned.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 0)
    }

    @Test func directionFollowsFingersWithEitherScrollSetting() {
        // Natural scrolling: deltas follow the fingers.
        #expect(SwipeLogic.direction(dx: 50, dy: 3, inverted: true) == .right)
        #expect(SwipeLogic.direction(dx: 0, dy: 50, inverted: true) == .down)
        // Classic scrolling: deltas are reversed.
        #expect(SwipeLogic.direction(dx: 50, dy: 3, inverted: false) == .left)
        #expect(SwipeLogic.direction(dx: 0, dy: -50, inverted: false) == .down)
    }

    @Test func smallOrDiagonalMovesAreIgnored() {
        #expect(SwipeLogic.direction(dx: 20, dy: 0, inverted: true) == nil)
        #expect(SwipeLogic.direction(dx: 50, dy: 45, inverted: true) == nil)
    }

    @Test func actionsDependOnTabAndWhereTheSwipeStarted() {
        #expect(SwipeLogic.action(direction: .left, isOpen: true, tab: .system, inHeader: false) == .nextTab)
        #expect(SwipeLogic.action(direction: .right, isOpen: true, tab: .system, inHeader: false) == .previousTab)
        #expect(SwipeLogic.action(direction: .left, isOpen: true, tab: .nowPlaying, inHeader: false) == .nextTrack)
        #expect(SwipeLogic.action(direction: .left, isOpen: true, tab: .nowPlaying, inHeader: true) == .nextTab)
        // Lists scroll sideways in Shelf and Clipboard, so only the header switches tabs.
        #expect(SwipeLogic.action(direction: .left, isOpen: true, tab: .shelf, inHeader: false) == SwipeAction.none)
        #expect(SwipeLogic.action(direction: .left, isOpen: true, tab: .clipboard, inHeader: true) == .nextTab)
        #expect(SwipeLogic.action(direction: .down, isOpen: false, tab: .shelf, inHeader: false) == .open)
        #expect(SwipeLogic.action(direction: .left, isOpen: false, tab: .shelf, inHeader: false) == SwipeAction.none)
    }

    @Test func neighbourStopsAtTheEnds() {
        let tabs: [NotchTab] = [.nowPlaying, .shelf, .notes]
        #expect(SwipeLogic.neighbour(of: .shelf, in: tabs, forward: true) == .notes)
        #expect(SwipeLogic.neighbour(of: .notes, in: tabs, forward: true) == nil)
        #expect(SwipeLogic.neighbour(of: .nowPlaying, in: tabs, forward: false) == nil)
    }
}

struct MeetingTests {
    let now = Date(timeIntervalSince1970: 1000)

    @Test func noMeetingWhenNothingIsInUse() {
        #expect(MeetingLogic.activity(mic: false, camera: false, muted: true, appBundleID: nil, appName: nil, since: now) == nil)
    }

    @Test func mutedMicShowsSlashedSymbol() throws {
        let item = try #require(MeetingLogic.activity(
            mic: true, camera: false, muted: true, appBundleID: nil, appName: nil, since: now
        ))
        #expect(item.symbol == "mic.slash.fill")
        #expect(item.title == "Microphone in use")
        #expect(item.detail == "Microphone muted")
    }

    @Test func cameraOnlyMeeting() throws {
        let item = try #require(MeetingLogic.activity(
            mic: false, camera: true, muted: false, appBundleID: nil, appName: nil, since: now
        ))
        #expect(item.title == "Camera in use")
        #expect(item.symbol == "video.fill")
    }
}

struct KeyboardLightTests {
    @Test func illuminationKeysParse() {
        // NX_KEYTYPE_ILLUMINATION_UP (21), key down.
        #expect(MediaKeyParser.parse(subtype: 8, data1: (21 << 16) | (0xA << 8)) == MediaKeyEvent(key: .illuminationUp, isDown: true, isRepeat: false))
        #expect(MediaKeyParser.parse(subtype: 8, data1: (23 << 16) | (0xB << 8))?.key == .illuminationToggle)
    }

    @MainActor @Test func toggleRemembersTheLevel() {
        #expect(KeyboardBacklight.toggledLevel(current: 0.75) == 0)
        #expect(KeyboardBacklight.toggledLevel(current: 0) == 0.75)
    }

    @Test func mirrorTabStartsHidden() {
        let tabs = AppearanceLogic.tabs(order: SettingsDefault.tabOrder, hidden: SettingsDefault.hiddenTabs)
        #expect(!tabs.contains(.mirror))
        #expect(tabs.contains(.home))
        #expect(!HomeLogic.defaultSlots.contains(.system))
    }
}
