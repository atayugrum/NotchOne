import AppKit
import Testing
@testable import NotchOne

struct BatteryPeekLogicTests {
    private func status(_ percent: Int, plugged: Bool = false) -> BatteryStatus {
        BatteryStatus(percent: percent, isPluggedIn: plugged, isCharging: plugged, isCharged: false)
    }

    @Test func firstReadingNeverPeeks() {
        let result = BatteryPeekLogic.evaluate(previous: nil, current: status(50), warned: [])
        #expect(result.peek == nil)
        #expect(result.warned.isEmpty)
    }

    @Test func launchingBelowThresholdDoesNotWarnForIt() {
        let result = BatteryPeekLogic.evaluate(previous: nil, current: status(15), warned: [])
        #expect(result.warned == [20])
    }

    @Test func pluggingInPeeksAndResetsWarnings() {
        let result = BatteryPeekLogic.evaluate(previous: status(15), current: status(15, plugged: true), warned: [20])
        #expect(result.peek == .power(pluggedIn: true, percent: 15))
        #expect(result.warned.isEmpty)
    }

    @Test func unpluggingPeeks() {
        let result = BatteryPeekLogic.evaluate(previous: status(80, plugged: true), current: status(80), warned: [])
        #expect(result.peek == .power(pluggedIn: false, percent: 80))
    }

    @Test func crossingTwentyWarnsOnce() {
        let first = BatteryPeekLogic.evaluate(previous: status(21), current: status(20), warned: [])
        #expect(first.peek == .lowBattery(percent: 20))
        #expect(first.warned == [20])

        let again = BatteryPeekLogic.evaluate(previous: status(20), current: status(19), warned: first.warned)
        #expect(again.peek == nil)
    }

    @Test func crossingTenAfterTwentyWarnsAgain() {
        let result = BatteryPeekLogic.evaluate(previous: status(11), current: status(10), warned: [20])
        #expect(result.peek == .lowBattery(percent: 10))
        #expect(result.warned == [20, 10])
    }

    @Test func chargingChangesDoNotPeek() {
        let result = BatteryPeekLogic.evaluate(
            previous: status(50, plugged: true),
            current: status(51, plugged: true),
            warned: []
        )
        #expect(result.peek == nil)
    }

    @Test @MainActor func batterySymbolsExist() {
        let names = [0, 10, 30, 50, 70, 95].map { status($0).symbolName } + [status(50, plugged: true).symbolName]
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing symbol \(name)")
        }
    }
}

struct LayoutTests {
    @Test func earWidths() {
        #expect(EarLayout.width(for: nil) == 0)
        #expect(EarLayout.width(for: .nowPlaying) == EarLayout.nowPlayingWidth)
        #expect(EarLayout.width(for: .peek(.lowBattery(percent: 9))) == EarLayout.islandWidth)
    }

    @Test func closedHoverAreaGrowsWithEars() {
        let notch = CGRect(x: 640, y: 924, width: 185, height: 32)
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: screen)
        let plain = ScreenGeometry.hoverRect(notchRect: notch, isOpen: false, panelFrame: frame)
        let withEars = ScreenGeometry.hoverRect(notchRect: notch, isOpen: false, panelFrame: frame, earWidth: 34)

        #expect(withEars.width == plain.width + 68)
        #expect(withEars.contains(CGPoint(x: notch.minX - 30, y: notch.midY)))
        #expect(!plain.contains(CGPoint(x: notch.minX - 30, y: notch.midY)))
    }

    @Test func clockFormatting() {
        #expect(TimeFormatting.clock(0) == "0:00")
        #expect(TimeFormatting.clock(-5) == "0:00")
        #expect(TimeFormatting.clock(.nan) == "0:00")
        #expect(TimeFormatting.clock(187.9) == "3:07")
        #expect(TimeFormatting.clock(3765) == "1:02:45")
    }
}
