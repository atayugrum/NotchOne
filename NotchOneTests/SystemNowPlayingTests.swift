import Foundation
import Testing
@testable import NotchOne

struct SystemNowPlayingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesRealHelperOutput() throws {
        // Captured from the helper on this Mac while Spotify was playing.
        let json = """
        {"bundle":"com.spotify.client","parentBundle":null,"title":"AMARGURA","artist":"KAROL G",\
        "album":"MAÑANA SERÁ BONITO","duration":166.48,"elapsed":0,"rate":1,\
        "timestamp":1793271632.205464,"playing":true}
        """
        guard case .snapshot(let snapshot) = try #require(SystemNowPlayingParser.parse(line: line(json))) else {
            Issue.record("expected a snapshot")
            return
        }
        let info = try #require(SystemNowPlayingParser.info(from: snapshot, now: now))
        #expect(info.source == .system)
        #expect(info.appBundleID == "com.spotify.client")
        #expect(info.title == "AMARGURA")
        #expect(info.duration == 166.48)
        #expect(info.isPlaying)
        #expect(info.updatedAt == Date(timeIntervalSince1970: 1793271632.205464))
    }

    @Test func specialLines() {
        #expect(SystemNowPlayingParser.parse(line: line(#"{"none":true}"#)) == .nothingPlaying)
        #expect(SystemNowPlayingParser.parse(line: line(#"{"unavailable":true}"#)) == .unavailable)
        #expect(SystemNowPlayingParser.parse(line: line("not json")) == nil)
    }

    @Test func webKitContentIsCreditedToParentApp() {
        var snapshot = SystemSnapshot(bundle: "com.apple.WebKit.GPU", parentBundle: "com.apple.Safari")
        #expect(SystemNowPlayingParser.appBundleID(for: snapshot) == "com.apple.Safari")
        snapshot.parentBundle = nil
        #expect(SystemNowPlayingParser.appBundleID(for: snapshot) == "com.apple.Safari")
        #expect(SystemNowPlayingParser.appBundleID(for: SystemSnapshot(bundle: "com.google.Chrome")) == "com.google.Chrome")
    }

    @Test func missingTitleMeansNothing() {
        #expect(SystemNowPlayingParser.info(from: SystemSnapshot(bundle: "x", title: "  "), now: now) == nil)
        #expect(SystemNowPlayingParser.info(from: SystemSnapshot(bundle: "x"), now: now) == nil)
    }

    @Test func playingFallsBackToRate() throws {
        let paused = try #require(SystemNowPlayingParser.info(from: SystemSnapshot(title: "T", rate: 0), now: now))
        let playing = try #require(SystemNowPlayingParser.info(from: SystemSnapshot(title: "T", rate: 1), now: now))
        #expect(!paused.isPlaying)
        #expect(playing.isPlaying)
    }

    @Test func futureTimestampIsClampedToNow() throws {
        let snapshot = SystemSnapshot(title: "T", elapsed: 10, rate: 1, timestamp: now.timeIntervalSince1970 + 30, playing: true)
        let info = try #require(SystemNowPlayingParser.info(from: snapshot, now: now))
        #expect(info.updatedAt == now)
        #expect(info.position(at: now) == 10)
    }

    @Test func positionRunsFromTimestamp() throws {
        let snapshot = SystemSnapshot(
            title: "T", duration: 300, elapsed: 20, rate: 1,
            timestamp: now.timeIntervalSince1970 - 15, playing: true
        )
        let info = try #require(SystemNowPlayingParser.info(from: snapshot, now: now))
        #expect(info.position(at: now) == 35)
    }

    @Test func splitsBufferIntoLines() {
        let (lines, rest) = SystemNowPlayingParser.splitLines(Data("a\n\nbb\ncc".utf8))
        #expect(lines == [Data("a".utf8), Data("bb".utf8)])
        #expect(rest == Data("cc".utf8))

        let (none, all) = SystemNowPlayingParser.splitLines(Data("partial".utf8))
        #expect(none.isEmpty)
        #expect(all == Data("partial".utf8))
    }

    @Test func differentAppsAreDifferentTracks() {
        let chrome = NowPlayingInfo(
            source: .system, title: "Video", artist: "", album: "",
            duration: nil, position: 0, isPlaying: true, updatedAt: now, appBundleID: "com.google.Chrome"
        )
        var safari = chrome
        safari.appBundleID = "com.apple.Safari"
        #expect(chrome.trackKey != safari.trackKey)
    }

    @Test func mediaKeyDataRoundTrips() {
        let down = MediaKeyPoster.data1(keyCode: 16, down: true)
        let up = MediaKeyPoster.data1(keyCode: 16, down: false)
        #expect((down & 0xFFFF_0000) >> 16 == 16)
        #expect((down & 0xFF00) >> 8 == 0xA)
        #expect((up & 0xFF00) >> 8 == 0xB)
        // Our own volume/brightness tap must ignore play keys.
        #expect(MediaKeyParser.parse(subtype: 8, data1: down) == nil)
    }

    @Test @MainActor func playKeyCodes() {
        #expect(MediaKeyPoster.keyCode(for: .playPause) == 16)
        #expect(MediaKeyPoster.keyCode(for: .next) == 17)
        #expect(MediaKeyPoster.keyCode(for: .previous) == 18)
    }
}

private extension SystemSnapshot {
    init(
        bundle: String? = nil, parentBundle: String? = nil, title: String? = nil,
        duration: Double? = nil, elapsed: Double? = nil, rate: Double? = nil,
        timestamp: Double? = nil, playing: Bool? = nil
    ) {
        self.init(
            bundle: bundle, parentBundle: parentBundle, title: title, artist: nil, album: nil,
            duration: duration, elapsed: elapsed, rate: rate, timestamp: timestamp,
            playing: playing, none: nil, unavailable: nil
        )
    }
}
