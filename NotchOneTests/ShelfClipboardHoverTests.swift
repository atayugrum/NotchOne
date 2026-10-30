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

    @Test @MainActor func claudeNeedingYouBeatsNowPlayingInEars() {
        let activity = ActivityState()
        activity.nowPlaying = NowPlayingInfo(
            source: .spotify, title: "T", artist: "", album: "",
            duration: nil, position: 0, isPlaying: true, updatedAt: now
        )
        #expect(activity.ears == .nowPlaying)
        activity.live.handle(.claude(ClaudeEvent(kind: .needsYou, session: "s", project: "p")))
        defer { activity.live.removeAll() }
        guard case .live = activity.ears else {
            Issue.record("expected the Claude item, got \(String(describing: activity.ears))")
            return
        }
    }
}
