import Foundation
import Testing
@testable import NotchOne

struct ShelfLogicTests {
    @Test func mergeAppendsWithoutDuplicates() {
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        let aAgain = URL(fileURLWithPath: "/tmp/./a.txt")
        #expect(ShelfLogic.merge([a], adding: [b, aAgain]) == [a, b])
    }

    @Test func mergeIgnoresNonFileURLs() {
        let web = URL(string: "https://example.com")!
        #expect(ShelfLogic.merge([], adding: [web]).isEmpty)
    }

    @Test func mergeKeepsNewestWhenFull() {
        let urls = (0..<30).map { URL(fileURLWithPath: "/tmp/f\($0)") }
        let merged = ShelfLogic.merge([], adding: urls)
        #expect(merged.count == ShelfLogic.maxItems)
        #expect(merged.last == urls.last)
    }

    @Test func existingDropsMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let present = dir.appendingPathComponent("here.txt")
        try Data("x".utf8).write(to: present)
        let missing = dir.appendingPathComponent("gone.txt")
        #expect(ShelfLogic.existing([present, missing]) == [present])
    }
}

struct ClipboardLogicTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(content: .text(text), sourceBundleID: "com.apple.TextEdit", copiedAt: now)
    }

    @Test func skipsConcealedAndTransientCopies() {
        #expect(!ClipboardLogic.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundleID: nil))
        #expect(!ClipboardLogic.shouldRecord(types: ["org.nspasteboard.TransientType"], sourceBundleID: nil))
        #expect(ClipboardLogic.shouldRecord(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari"))
    }

    @Test func skipsPasswordManagers() {
        #expect(!ClipboardLogic.shouldRecord(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Passwords"))
        #expect(!ClipboardLogic.shouldRecord(types: ["public.utf8-plain-text"], sourceBundleID: "com.1password.1password"))
    }

    @Test func blankTextIsIgnoredAndLongTextCapped() {
        #expect(ClipboardLogic.normalizedText("   \n\t ") == nil)
        #expect(ClipboardLogic.normalizedText("hi") == "hi")
        let long = String(repeating: "a", count: ClipboardLogic.maxTextLength + 10)
        #expect(ClipboardLogic.normalizedText(long)?.count == ClipboardLogic.maxTextLength)
    }

    @Test func newestFirstAndCopyingAgainMovesToTop() {
        var items: [ClipboardItem] = []
        items = ClipboardLogic.insert(item("one"), into: items)
        items = ClipboardLogic.insert(item("two"), into: items)
        items = ClipboardLogic.insert(item("one"), into: items)
        #expect(items.map(\.content) == [.text("one"), .text("two")])
    }

    @Test func historyIsCapped() {
        var items: [ClipboardItem] = []
        for index in 0..<40 { items = ClipboardLogic.insert(item("\(index)"), into: items) }
        #expect(items.count == ClipboardLogic.maxItems)
        #expect(items.first?.content == .text("39"))
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        #expect(ClipboardLogic.preview("a\n\n  b\tc") == "a b c")
        #expect(ClipboardLogic.preview(String(repeating: "x", count: 200), limit: 10) == "xxxxxxxxxx…")
    }
}

struct HoverAndEarsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dragKeepsOpenNotchOpen() {
        #expect(HoverLogic.holdsOpen(state: .open, mouseButtonsDown: true))
        #expect(!HoverLogic.holdsOpen(state: .open, mouseButtonsDown: false))
        #expect(!HoverLogic.holdsOpen(state: .closed, mouseButtonsDown: true))
    }
}

struct StatusIndicatorTests {
    private let notch = CGRect(x: 645, y: 924, width: 180, height: 32)

    @Test func indicatorNextToTheNotchNarrowsTheEars() {
        // macOS's mic dot 50 pt right of the notch: 50 - 6 (corner) - 4 (gap) left.
        let mic = CGRect(x: 875, y: 926, width: 28, height: 28)
        let limit = EarLayout.limit(notchRect: notch, indicators: [mic], corner: 6)
        #expect(limit == 40)
        #expect(EarLayout.width(for: .peek(.focus(on: true)), limit: limit) == 40)
        #expect(EarLayout.width(for: .nowPlaying, limit: limit) == EarLayout.nowPlayingWidth)
    }

    @Test func farOrLowerIndicatorsDontMatter() {
        let farRight = CGRect(x: 1443, y: 926, width: 28, height: 28)
        #expect(EarLayout.limit(notchRect: notch, indicators: [farRight], corner: 6) == 608)
        let belowMenuBar = CGRect(x: 830, y: 500, width: 28, height: 28)
        #expect(EarLayout.limit(notchRect: notch, indicators: [belowMenuBar], corner: 6) == nil)
        #expect(EarLayout.limit(notchRect: notch, indicators: [], corner: 6) == nil)
    }

    @Test func tooLittleRoomHidesTheEars() {
        let close = CGRect(x: 830, y: 926, width: 28, height: 28)
        let limit = EarLayout.limit(notchRect: notch, indicators: [close], corner: 6)
        #expect(EarLayout.width(for: .nowPlaying, limit: limit) == 0)
        let left = CGRect(x: 600, y: 926, width: 28, height: 28)
        #expect(EarLayout.limit(notchRect: notch, indicators: [left], corner: 6) == 7)
    }

    @Test func onlyTheWindowServersTopWindowCounts() {
        #expect(StatusIndicatorWatcher.isIndicator(owner: "Window Server", name: "StatusIndicator", layer: 0))
        #expect(StatusIndicatorWatcher.isIndicator(owner: "Window Server", name: nil, layer: 2_147_483_630))
        #expect(!StatusIndicatorWatcher.isIndicator(owner: "Window Server", name: "Menubar", layer: 24))
        #expect(!StatusIndicatorWatcher.isIndicator(owner: "Teams", name: "StatusIndicator", layer: 2_147_483_630))
    }
}

struct LockScreenCardTests {
    @Test func staysCentredUnderTheNotchWhereverTheScreenIs() {
        let screen = CGRect(x: 225, y: -956, width: 1470, height: 956)
        let notch = CGRect(x: 870, y: -32, width: 180, height: 32)
        let frame = LockScreenController.cardFrame(screen: screen, notchRect: notch)
        #expect(frame.midX == notch.midX)
        #expect(frame.maxY < screen.maxY - 300)
        #expect(frame.minY > screen.minY)
    }
}

struct MenuClearanceTests {
    private let notch = CGRect(x: 645, y: 924, width: 180, height: 32)

    @Test func earsStopBeforeTheNearestMenu() {
        let menus = [CGRect(x: 560, y: 930, width: 52, height: 24), CGRect(x: 850, y: 930, width: 60, height: 24)]
        // Left gap 33, right gap 25: the tighter one wins, less the corner and gap.
        #expect(EarLayout.menuLimit(notchRect: notch, menus: menus, corner: 6) == 15)
    }

    @Test func menusBehindTheNotchAndEmptyOnesDontCount() {
        let behind = CGRect(x: 700, y: 930, width: 50, height: 24)
        let empty = CGRect(x: 830, y: 930, width: 0, height: 24)
        #expect(EarLayout.menuLimit(notchRect: notch, menus: [behind, empty], corner: 6) == nil)
    }

    @Test @MainActor func onlyEarsThatStayKeepClear() {
        let activity = ActivityState()
        activity.menuEarLimit = 22
        activity.nowPlaying = NowPlayingInfo(source: .spotify, title: "T", artist: "", album: "", duration: nil, position: 0, isPlaying: true, updatedAt: .now)
        #expect(activity.earWidth == 22)
        activity.showPeek(.focus(on: true))
        #expect(activity.earWidth == EarLayout.peekWidth)
    }
}
