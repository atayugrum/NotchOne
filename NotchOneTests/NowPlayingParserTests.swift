import Foundation
import Testing
@testable import NotchOne

struct NowPlayingParserTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: Notifications

    @Test func parsesMusicNotification() throws {
        let info = try #require(NowPlayingParser.parse(
            notification: [
                "Player State": "Playing",
                "Name": "Song",
                "Artist": "Band",
                "Album": "Record",
                "Total Time": 215_000,
            ],
            source: .music,
            now: now
        ))
        #expect(info.isPlaying)
        #expect(info.title == "Song")
        #expect(info.duration == 215)
        #expect(info.position == 0)
    }

    @Test func parsesSpotifyNotificationWithPosition() throws {
        let info = try #require(NowPlayingParser.parse(
            notification: [
                "Player State": "Paused",
                "Name": "Track",
                "Artist": "Artist",
                "Album": "Album",
                "Duration": 180_000,
                "Playback Position": 42.5,
            ],
            source: .spotify,
            now: now
        ))
        #expect(!info.isPlaying)
        #expect(info.duration == 180)
        #expect(info.position == 42.5)
    }

    @Test func stoppedOrEmptyNotificationMeansNothingPlaying() {
        #expect(NowPlayingParser.parse(notification: ["Player State": "Stopped"], source: .music, now: now) == nil)
        #expect(NowPlayingParser.parse(
            notification: ["Player State": "Playing", "Name": "  "],
            source: .spotify,
            now: now
        ) == nil)
    }

    @Test func zeroDurationIsTreatedAsUnknown() throws {
        let info = try #require(NowPlayingParser.parse(
            notification: ["Player State": "Playing", "Name": "Radio", "Total Time": 0],
            source: .music,
            now: now
        ))
        #expect(info.duration == nil)
    }

    // MARK: Script fields

    @Test func spotifyScriptDurationIsConvertedFromMilliseconds() throws {
        let fields = ScriptTrackFields(state: "playing", title: "T", artist: "A", album: "B", duration: 200_000, position: 12)
        let info = try #require(NowPlayingParser.parse(fields: fields, source: .spotify, now: now))
        #expect(info.duration == 200)
        #expect(info.position == 12)
    }

    @Test func musicScriptDurationIsAlreadySeconds() throws {
        let fields = ScriptTrackFields(state: "paused", title: "T", artist: nil, album: nil, duration: 200, position: nil)
        let info = try #require(NowPlayingParser.parse(fields: fields, source: .music, now: now))
        #expect(info.duration == 200)
        #expect(info.position == 0)
        #expect(info.artist.isEmpty)
    }

    @Test func readsFieldsFromAppleScriptList() throws {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        list.insert(NSAppleEventDescriptor(string: "Title"), at: 2)
        list.insert(NSAppleEventDescriptor(string: "Artist"), at: 3)
        list.insert(NSAppleEventDescriptor(string: "Album"), at: 4)
        list.insert(NSAppleEventDescriptor(double: 245.5), at: 5)
        list.insert(NSAppleEventDescriptor(double: 10), at: 6)

        let fields = try #require(NowPlayingParser.fields(from: list))
        #expect(fields == ScriptTrackFields(
            state: "playing", title: "Title", artist: "Artist", album: "Album", duration: 245.5, position: 10
        ))
    }

    @Test func readsStoppedFromSingleItemList() throws {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "stopped"), at: 1)
        let fields = try #require(NowPlayingParser.fields(from: list))
        #expect(fields.state == "stopped")
        #expect(fields.title == nil)
        #expect(NowPlayingParser.parse(fields: fields, source: .music, now: now) == nil)
    }

    // MARK: Position

    @Test func positionAdvancesOnlyWhilePlayingAndClampsToDuration() {
        var info = NowPlayingInfo(
            source: .music, title: "T", artist: "", album: "",
            duration: 100, position: 10, isPlaying: true, updatedAt: now
        )
        #expect(info.position(at: now.addingTimeInterval(5)) == 15)
        #expect(info.position(at: now.addingTimeInterval(500)) == 100)

        info.isPlaying = false
        #expect(info.position(at: now.addingTimeInterval(5)) == 10)
    }

    @Test func musicNotificationKeepsRunningPositionForSameTrack() {
        let previous = NowPlayingInfo(
            source: .music, title: "T", artist: "A", album: "B",
            duration: 100, position: 20, isPlaying: true, updatedAt: now
        )
        var new = previous
        new.position = 0
        new.isPlaying = false
        new.updatedAt = now.addingTimeInterval(10)

        let merged = NowPlayingParser.carryPosition(into: new, from: previous, now: now.addingTimeInterval(10))
        #expect(merged.position == 30)
    }

    @Test func newTrackStartsFromZero() {
        let previous = NowPlayingInfo(
            source: .music, title: "Old", artist: "A", album: "B",
            duration: 100, position: 50, isPlaying: true, updatedAt: now
        )
        var new = previous
        new.title = "New"
        new.position = 0
        #expect(NowPlayingParser.carryPosition(into: new, from: previous, now: now).position == 0)
    }

    // MARK: Selection

    @Test func playingBeatsPausedAndNewestWins() {
        let pausedNewer = NowPlayingInfo(
            source: .spotify, title: "S", artist: "", album: "",
            duration: nil, position: 0, isPlaying: false, updatedAt: now.addingTimeInterval(60)
        )
        let playing = NowPlayingInfo(
            source: .music, title: "M", artist: "", album: "",
            duration: nil, position: 0, isPlaying: true, updatedAt: now
        )
        #expect(NowPlayingParser.select([pausedNewer, playing])?.source == .music)
        #expect(NowPlayingParser.select([pausedNewer])?.source == .spotify)
        #expect(NowPlayingParser.select([NowPlayingInfo]()) == nil)
    }

    @Test func appleScriptErrorCodesMap() {
        #expect(AppleScriptRunner.error(code: -1743, message: "") == .notPermitted)
        #expect(AppleScriptRunner.error(code: -600, message: "") == .appNotRunning)
        #expect(AppleScriptRunner.error(code: -1728, message: "x") == .failed(code: -1728, message: "x"))
    }
}
