import Foundation
import Testing
@testable import NotchOne

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
