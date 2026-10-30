import Foundation
import Testing
@testable import NotchOne

struct ClipboardPinTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ text: String, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(content: .text(text), sourceBundleID: nil, copiedAt: now, isPinned: pinned)
    }

    @Test func pinsStayFirstAndOutsideTheLimit() {
        var items = [item("pin", pinned: true)]
        for index in 0..<(ClipboardLogic.maxItems + 5) {
            items = ClipboardLogic.insert(item("\(index)"), into: items)
        }
        #expect(items.first?.isPinned == true)
        #expect(items.count == ClipboardLogic.maxItems + 1)
    }

    @Test func copyingAPinnedTextKeepsThePin() {
        let items = ClipboardLogic.insert(item("same"), into: [item("same", pinned: true)])
        #expect(items.count == 1)
        #expect(items[0].isPinned)
    }

    @Test func clearKeepsOnlyPins() {
        let items = ClipboardLogic.cleared([item("a"), item("b", pinned: true)])
        #expect(items.map(\.content) == [.text("b")])
    }

    @Test func onlyPinnedTextIsSaved() {
        let image = ClipboardItem(content: .image(Data()), sourceBundleID: nil, copiedAt: now, isPinned: true)
        #expect(ClipboardLogic.savedPins([item("a"), item("b", pinned: true), image]) == ["b"])
    }

    @Test @MainActor func pinsComeBackAfterARestart() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(["kept"]).write(to: url)
        let store = ClipboardStore(pinsURL: url)
        #expect(store.items.map(\.content) == [.text("kept")])
        store.clear()
        #expect(store.items.count == 1)
        store.togglePin(store.items[0])
        #expect(ClipboardStore(pinsURL: url).items.isEmpty)
    }
}

struct EmailTextTests {
    @Test func emailsAreRecognised() {
        #expect(SmartText.classify("ata@example.com") == .email("ata@example.com"))
        #expect(SmartText.classify(" a.b+c@mail.example.co ") == .email("a.b+c@mail.example.co"))
        #expect(SmartText.classify("not an@email here") != .email("not an@email here"))
        #expect(SmartText.classify("a@b") == .plain(words: 1))
    }

    @Test func emailsOfferANewMessage() {
        let actions = ClipboardActions.available(for: "ata@example.com", smart: .email("ata@example.com"))
        #expect(actions == [.composeEmail, .addToNotes])
        #expect(ClipboardActions.mailto("ata@example.com")?.absoluteString == "mailto:ata@example.com")
    }
}

struct MacLockTests {
    // Only finds the system call; calling it would lock the Mac running the tests.
    @Test func theSystemCallIsFound() {
        #expect(MacLock.isAvailable)
    }
}

struct PaletteCommandTests {
    @Test func commandsAreFoundByName() {
        let results = PaletteLogic.results(query: PaletteCommand.settings.title(keepAwakeIsOn: false), clipboard: [], shelf: [], tabs: [])
        #expect(results.contains { $0.kind == .command(.settings) })
    }

    @Test func keepAwakeNamesWhatItWillDo() {
        #expect(PaletteCommand.keepAwake.title(keepAwakeIsOn: true) != PaletteCommand.keepAwake.title(keepAwakeIsOn: false))
    }

    @Test func digitsPickTabsByPlace() {
        let tabs: [NotchTab] = [.home, .shelf]
        #expect(PaletteLogic.tab(forDigit: "2", in: tabs) == .shelf)
        #expect(PaletteLogic.tab(forDigit: "3", in: tabs) == nil)
        #expect(PaletteLogic.tab(forDigit: "0", in: tabs) == nil)
    }
}

struct EarExtraTests {
    @Test @MainActor func keepAwakeShowsWhenNothingElseDoes() {
        let activity = ActivityState()
        #expect(activity.ears == nil)
        activity.keepAwake.toggle()
        defer { activity.keepAwake.toggle() }
        #expect(activity.ears == .keepAwake)
        #expect(activity.earWidth == EarLayout.nowPlayingWidth)
    }

    @Test @MainActor func aSecondActivitySitsBesideTheMusic() {
        let activity = ActivityState()
        activity.nowPlaying = NowPlayingInfo(source: .spotify, title: "T", artist: "", album: "", duration: nil, position: 0, isPlaying: true, updatedAt: .now)
        #expect(activity.earExtra == nil)
        activity.keepAwake.toggle()
        defer { activity.keepAwake.toggle() }
        #expect(activity.earExtra == .keepAwake)
        #expect(activity.earWidth == EarLayout.nowPlayingWidth + EarLayout.extraWidth)
    }

    @Test func keepAwakeEarClicksToggleIt() {
        #expect(ClosedNotchLogic.click(ears: .keepAwake, side: .left, left: .open, right: .open) == .ear(.keepAwake))
        #expect(ClosedNotchLogic.click(ears: .keepAwake, side: .center, left: .open, right: .open) == .open)
    }
}
