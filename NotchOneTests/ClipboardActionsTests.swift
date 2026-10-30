import Foundation
import Testing
@testable import NotchOne

struct ClipboardActionsTests {
    private func actions(_ text: String) -> [ClipboardAction] {
        ClipboardActions.available(for: text, smart: SmartText.classify(text))
    }

    // MARK: - Links

    @Test func cleanLinkDropsTrackersOnly() {
        let dirty = "https://example.com/a?utm_source=x&id=7&fbclid=abc&UTM_Medium=y#top"
        #expect(ClipboardActions.apply(.cleanLink, to: dirty) == "https://example.com/a?id=7#top")
    }

    @Test func cleanLinkRemovesAnEmptyQuery() {
        #expect(ClipboardActions.apply(.cleanLink, to: "https://example.com/?gclid=1") == "https://example.com/")
    }

    @Test func cleanLinkKeepsEncodingOfOtherParameters() {
        let dirty = "https://example.com/s?q=a%20b%26c&flag&utm_campaign=z"
        #expect(ClipboardActions.apply(.cleanLink, to: dirty) == "https://example.com/s?q=a%20b%26c&flag")
    }

    @Test func shareTrackerIsRemovedOnlyWhereItIsOne() {
        #expect(ClipboardActions.apply(.cleanLink, to: "https://youtu.be/abc?si=xyz&t=30") == "https://youtu.be/abc?t=30")
        #expect(ClipboardActions.apply(.cleanLink, to: "https://music.youtube.com/watch?v=1&si=xyz") == "https://music.youtube.com/watch?v=1")
        #expect(ClipboardActions.apply(.cleanLink, to: "https://notyoutube.com/?si=xyz") == nil)
        #expect(ClipboardActions.apply(.cleanLink, to: "https://example.com/?si=xyz") == nil)
    }

    @Test func cleanLinkIsOfferedOnlyWhenThereIsSomethingToClean() {
        #expect(actions("https://example.com/a?utm_source=x").contains(.cleanLink))
        #expect(!actions("https://example.com/a?id=1").contains(.cleanLink))
    }

    // MARK: - JSON

    @Test func jsonCanBeFormattedAndMinified() throws {
        let compact = #"{"a":1}"#
        let pretty = try #require(ClipboardActions.apply(.formatJSON, to: compact))
        #expect(pretty.contains("\n"))
        #expect(ClipboardActions.apply(.minifyJSON, to: pretty) == compact)
    }

    @Test func jsonOffersOnlyTheFormItIsNotIn() throws {
        let compact = #"{"a":1}"#
        #expect(actions(compact).contains(.formatJSON))
        #expect(!actions(compact).contains(.minifyJSON))
        let pretty = try #require(ClipboardActions.apply(.formatJSON, to: compact))
        #expect(!actions(pretty).contains(.formatJSON))
        #expect(actions(pretty).contains(.minifyJSON))
    }

    // MARK: - Colours

    @Test func colourConvertsBetweenFormats() {
        #expect(ClipboardActions.apply(.colorRGB, to: "#ff0000") == "rgb(255, 0, 0)")
        #expect(ClipboardActions.apply(.colorHSL, to: "#ff0000") == "hsl(0, 100%, 50%)")
        #expect(ClipboardActions.apply(.colorHex, to: "rgb(0, 128, 255)") == "#0080FF")
        #expect(ClipboardActions.apply(.colorHSL, to: "#808080") == "hsl(0, 0%, 50%)")
    }

    @Test func colourKeepsAlpha() {
        #expect(ClipboardActions.apply(.colorRGB, to: "#ff000080") == "rgba(255, 0, 0, 0.5)")
        #expect(ClipboardActions.apply(.colorHex, to: "rgba(255, 0, 0, 0.5)") == "#FF000080")
        #expect(ClipboardActions.apply(.colorHSL, to: "rgba(255, 0, 0, 0.5)") == "hsla(0, 100%, 50%, 0.5)")
    }

    @Test func hslIsRecognisedSoConvertedColoursStayColours() {
        guard case .color(let red, let green, let blue, let alpha) = SmartText.classify("hsl(120, 100%, 50%)") else {
            Issue.record("not a colour")
            return
        }
        #expect(red == 0 && green == 1 && blue == 0 && alpha == 1)
        #expect(SmartText.color("hsl(120, 100, 50)") == nil)
        #expect(SmartText.color("hsl(400, 100%, 50%)") == nil)
        #expect(ClipboardActions.apply(.colorHex, to: "hsla(0, 100%, 50%, 0.5)") == "#FF000080")
    }

    @Test func colourOffersTheOtherFormats() {
        #expect(actions("#FF0000") == [.colorRGB, .colorHSL, .addToNotes])
        #expect(actions("#ff0000") == [.colorRGB, .colorHSL, .addToNotes])
        #expect(actions("rgb(1, 2, 3)") == [.colorHex, .colorHSL, .addToNotes])
        #expect(actions("hsl(0, 100%, 50%)") == [.colorHex, .colorRGB, .addToNotes])
    }

    // MARK: - Text

    @Test func plainTextCanBeTranslatedAndNoted() {
        #expect(actions("Merhaba dünya") == [.translate, .addToNotes])
    }

    @Test func actionsThatTransformDoNothingOnTheWrongText() {
        #expect(ClipboardActions.apply(.colorRGB, to: "not a colour") == nil)
        #expect(ClipboardActions.apply(.formatJSON, to: "not json") == nil)
        #expect(ClipboardActions.apply(.cleanLink, to: "not a link") == nil)
        #expect(ClipboardActions.apply(.translate, to: "hello") == nil)
    }
}

@MainActor
struct NotesAppendTests {
    private func store() -> NotesStore {
        NotesStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt"))
    }

    @Test func firstAppendIsTheWholeNote() {
        let notes = store()
        notes.append("  hello\n")
        #expect(notes.text == "hello")
    }

    @Test func laterAppendsGoOnTheirOwnLines() {
        let notes = store()
        notes.text = "first\n"
        notes.append("second")
        #expect(notes.text == "first\n\nsecond")
    }
}
