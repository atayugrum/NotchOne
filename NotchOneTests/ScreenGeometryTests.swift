import CoreGraphics
import Testing
@testable import NotchOne

struct ScreenGeometryTests {
    // MacBook Air 13" style display at its default "looks like" size.
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test func hardwareNotchIsBetweenAuxiliaryAreas() {
        let metrics = ScreenGeometry.metrics(
            screenFrame: screen,
            safeTopInset: 32,
            leftAuxWidth: 640,
            rightAuxWidth: 645,
            menuBarHeight: 32
        )
        #expect(metrics.hasHardwareNotch)
        #expect(metrics.notchRect == CGRect(x: 640, y: 924, width: 185, height: 32))
    }

    @Test func notchFollowsScreenOrigin() {
        let secondary = CGRect(x: -1470, y: 200, width: 1470, height: 956)
        let metrics = ScreenGeometry.metrics(
            screenFrame: secondary,
            safeTopInset: 32,
            leftAuxWidth: 640,
            rightAuxWidth: 645,
            menuBarHeight: 32
        )
        #expect(metrics.notchRect.minX == -830)
        #expect(metrics.notchRect.maxY == secondary.maxY)
    }

    @Test func noNotchFallsBackToCenteredPill() {
        let monitor = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let metrics = ScreenGeometry.metrics(
            screenFrame: monitor,
            safeTopInset: 0,
            leftAuxWidth: nil,
            rightAuxWidth: nil,
            menuBarHeight: 25
        )
        #expect(!metrics.hasHardwareNotch)
        #expect(metrics.notchRect.midX == monitor.midX)
        #expect(metrics.notchRect.height == 25)
        #expect(metrics.notchRect.maxY == monitor.maxY)
    }

    @Test func hiddenMenuBarUsesDefaultFallbackHeight() {
        let metrics = ScreenGeometry.metrics(
            screenFrame: screen,
            safeTopInset: 0,
            leftAuxWidth: nil,
            rightAuxWidth: nil,
            menuBarHeight: 0
        )
        #expect(metrics.notchRect.height == NotchLayout.fallbackNotchHeight)
    }

    @Test func insetWithoutAuxiliaryAreasIsTreatedAsNoNotch() {
        let metrics = ScreenGeometry.metrics(
            screenFrame: screen,
            safeTopInset: 32,
            leftAuxWidth: nil,
            rightAuxWidth: 645,
            menuBarHeight: 32
        )
        #expect(!metrics.hasHardwareNotch)
    }

    @Test func panelIsTopAlignedAndCenteredOnNotch() {
        let notch = CGRect(x: 640, y: 924, width: 185, height: 32)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: screen)
        #expect(frame.maxY == screen.maxY)
        #expect(abs(frame.midX - notch.midX) < 0.001)
        #expect(frame.width == NotchLayout.maxOpenSize.width + NotchLayout.shadowPadding * 2)
    }

    @Test func panelIsClampedInsideNarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 800)
        let notch = CGRect(x: 20, y: 776, width: 100, height: 24)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: narrow)
        #expect(frame.minX >= narrow.minX)
        #expect(frame.maxX <= narrow.maxX)
    }

    @Test func closedHoverAreaCoversNotchAndTopEdge() {
        let notch = CGRect(x: 640, y: 924, width: 185, height: 32)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: screen)
        let area = ScreenGeometry.hoverRect(notchRect: notch, isOpen: false, panelFrame: frame)

        #expect(area.contains(CGPoint(x: notch.midX, y: notch.midY)))
        #expect(area.contains(CGPoint(x: notch.midX, y: screen.maxY)))      // cursor pinned to top
        #expect(area.contains(CGPoint(x: notch.minX - 6, y: notch.midY)))  // small side margin
        #expect(!area.contains(CGPoint(x: notch.midX, y: notch.minY - 40)))
        #expect(!area.contains(CGPoint(x: 100, y: 940)))                   // menu bar items
    }

    @Test func openHoverAreaCoversOpenPanel() {
        let notch = CGRect(x: 640, y: 924, width: 185, height: 32)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: screen)
        let area = ScreenGeometry.hoverRect(notchRect: notch, isOpen: true, panelFrame: frame)

        let bottomOfOpen = screen.maxY - NotchLayout.openSize.height
        #expect(area.contains(CGPoint(x: notch.midX, y: bottomOfOpen + 2)))
        #expect(area.contains(CGPoint(x: notch.midX - 300, y: screen.maxY - 50)))
        #expect(!area.contains(CGPoint(x: notch.midX, y: bottomOfOpen - 10)))
    }

    /// Space left for the header and tab, below the top inset and above the bottom padding.
    private func contentHeight(_ outline: NotchOutline, notchHeight: CGFloat, size: CGSize) -> CGFloat {
        let open = NotchLayout.openSize(size, outline: outline, notchHeight: notchHeight)
        let shapeTop = outline == .pill ? NotchLayout.pillGap : 0
        return open.height - shapeTop - NotchLayout.contentTopInset(outline: outline, notchHeight: notchHeight)
    }

    @Test(arguments: [24.0, 32.0, 38.0])
    func notchAndPillGetTheSameContentArea(notchHeight: Double) {
        for size in PanelSize.allCases.map(\.openSize) + [NotchLayout.settingsSize(base: NotchLayout.openSize)] {
            #expect(contentHeight(.notch, notchHeight: notchHeight, size: size) == contentHeight(.pill, notchHeight: notchHeight, size: size))
        }
    }

    @Test func pillKeepsItsSizeAndNotchGrowsByItsNeck() {
        let size = PanelSize.regular.openSize
        #expect(NotchLayout.openSize(size, outline: .pill, notchHeight: 32) == size)
        #expect(NotchLayout.openSize(size, outline: .notch, notchHeight: 32).height == size.height + 32 + 6 - 3 - 12)
    }

    @Test func panelIsTallEnoughForTheLargestNotch() {
        let notch = CGRect(x: 640, y: 918, width: 185, height: 38)
        let frame = ScreenGeometry.panelFrame(notchRect: notch, screenFrame: screen)
        let tallest = NotchLayout.openSize(NotchLayout.maxOpenSize, outline: .notch, notchHeight: notch.height)
        #expect(frame.height >= tallest.height)
    }
}
