import Foundation
import Testing
@testable import NotchOne

struct EarIslandTests {
    @Test func airPodsShowEachPart() throws {
        let devices = [DeviceBattery(name: "AirPods Pro", symbol: "airpodspro", levels: [.left: 80, .right: 78, .case: 100])]
        let content = EarContent.peek(.bluetooth(symbol: "airpodspro", connected: true, battery: 78, name: "AirPods Pro"))
        let island = try #require(EarIsland.make(for: content, devices: devices))
        #expect(island.title == "AirPods Pro")
        #expect(island.gauges.map(\.value) == [80, 78, 100])
    }

    @Test func aDeviceWithoutLevelsStillShows() throws {
        let content = EarContent.peek(.bluetooth(symbol: "headphones", connected: true, battery: nil, name: "Headset"))
        let island = try #require(EarIsland.make(for: content, devices: []))
        #expect(island.gauges.isEmpty)
        #expect(island.detail != nil)
    }

    @Test func aDisconnectShowsNoLevels() throws {
        let devices = [DeviceBattery(name: "Headset", symbol: "headphones", levels: [.single: 50])]
        let content = EarContent.peek(.bluetooth(symbol: "headphones", connected: false, battery: nil, name: "Headset"))
        #expect(try #require(EarIsland.make(for: content, devices: devices)).gauges.isEmpty)
    }

    @Test func levelsAndMusicStayBesideTheNotch() {
        #expect(EarIsland.make(for: .nowPlaying, devices: []) == nil)
        #expect(EarIsland.make(for: .peek(.volume(level: 0.5, muted: false)), devices: []) == nil)
        #expect(EarIsland.make(for: nil, devices: []) == nil)
    }

    @Test func anIslandOpensDownward() {
        #expect(EarLayout.drop(for: .peek(.lowBattery(percent: 9))) == EarLayout.islandDrop)
        #expect(EarLayout.drop(for: .peek(.volume(level: 0.5, muted: false))) == 0)
    }
}

struct ClosedNotchLogicTests {
    @Test func clicksAreSplitByEar() {
        #expect(ClosedNotchLogic.side(x: 10, width: 260, notchWidth: 180) == .left)
        #expect(ClosedNotchLogic.side(x: 130, width: 260, notchWidth: 180) == .center)
        #expect(ClosedNotchLogic.side(x: 250, width: 260, notchWidth: 180) == .right)
    }

    @Test func nowPlayingEarsDoWhatTheyWereSetTo() {
        let click = { side in ClosedNotchLogic.click(ears: .nowPlaying, side: side, left: .openPlayer, right: .playPause) }
        #expect(click(.left) == .ear(.openPlayer))
        #expect(click(.right) == .ear(.playPause))
        #expect(click(.center) == .open)
    }

    @Test func everythingElseOpensTheNotch() {
        #expect(ClosedNotchLogic.click(ears: nil, side: .left, left: .playPause, right: .playPause) == .open)
        #expect(ClosedNotchLogic.click(ears: .peek(.focus(on: true)), side: .right, left: .playPause, right: .playPause) == .open)
    }

    @Test func wheelVolumeStaysInRange() {
        #expect(ClosedNotchLogic.wheelVolume(1, dy: 3) == 1)
        #expect(ClosedNotchLogic.wheelVolume(0, dy: -3) == 0)
        #expect(ClosedNotchLogic.wheelVolume(0.5, dy: 1) > 0.5)
    }

    @Test func previewDropsOnlyForNowPlaying() {
        #expect(EarLayout.drop(for: .nowPlaying, previewing: true) == EarLayout.previewDrop)
        #expect(EarLayout.drop(for: .nowPlaying) == 0)
        #expect(EarLayout.drop(for: nil, previewing: true) == 0)
    }
}
