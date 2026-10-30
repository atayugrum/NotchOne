import Foundation

/// Pure parsing and selection rules for Now Playing. No AppKit, no side effects.
enum NowPlayingParser {

    /// Parses the `userInfo` of a player's distributed notification.
    /// Returns nil when stopped or when there's no track.
    static func parse(notification userInfo: [String: Any], source: PlayerApp, now: Date) -> NowPlayingInfo? {
        guard let isPlaying = isPlaying(state: userInfo["Player State"] as? String),
              let title = nonEmpty(userInfo["Name"] as? String) else { return nil }

        let durationKey = source == .music ? "Total Time" : "Duration"
        let durationMs = number(userInfo[durationKey])
        let position = source.notificationIncludesPosition ? number(userInfo["Playback Position"]) ?? 0 : 0

        return NowPlayingInfo(
            source: source,
            title: title,
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            duration: positive(durationMs.map { $0 / 1000 }),
            position: max(0, position),
            isPlaying: isPlaying,
            updatedAt: now
        )
    }

    /// Parses the result of `PlayerScripts.state(for:)`.
    static func parse(fields: ScriptTrackFields, source: PlayerApp, now: Date) -> NowPlayingInfo? {
        guard let isPlaying = isPlaying(state: fields.state),
              let title = nonEmpty(fields.title) else { return nil }

        let duration = fields.duration.map { source.scriptDurationIsMilliseconds ? $0 / 1000 : $0 }

        return NowPlayingInfo(
            source: source,
            title: title,
            artist: fields.artist ?? "",
            album: fields.album ?? "",
            duration: positive(duration),
            position: max(0, fields.position ?? 0),
            isPlaying: isPlaying,
            updatedAt: now
        )
    }

    /// Music's notification has no position. If it's the same track, keep counting
    /// from where we were instead of jumping back to 0.
    static func carryPosition(into new: NowPlayingInfo, from previous: NowPlayingInfo?, now: Date) -> NowPlayingInfo {
        guard !new.source.notificationIncludesPosition,
              let previous,
              previous.trackKey == new.trackKey else { return new }
        var updated = new
        updated.position = previous.position(at: now)
        return updated
    }

    /// The most recently updated playing track wins; otherwise the most recent paused one.
    static func select(_ infos: some Collection<NowPlayingInfo>) -> NowPlayingInfo? {
        infos.filter(\.isPlaying).max { $0.updatedAt < $1.updatedAt }
            ?? infos.max { $0.updatedAt < $1.updatedAt }
    }

    /// Player state text from notifications ("Playing") or AppleScript ("playing").
    static func isPlaying(state: String?) -> Bool? {
        switch state?.lowercased() {
        case "playing": true
        case "paused": false
        default: nil
        }
    }

    /// Reads `{state, title, artist, album, duration, position}` from an AppleScript list.
    static func fields(from descriptor: NSAppleEventDescriptor) -> ScriptTrackFields? {
        let count = descriptor.numberOfItems
        guard count >= 1, let state = descriptor.atIndex(1)?.stringValue else { return nil }

        func item(_ index: Int) -> NSAppleEventDescriptor? {
            index <= count ? descriptor.atIndex(index) : nil
        }
        func number(_ index: Int) -> Double? {
            guard let value = item(index)?.doubleValue, value.isFinite else { return nil }
            return value
        }

        return ScriptTrackFields(
            state: state,
            title: item(2)?.stringValue,
            artist: item(3)?.stringValue,
            album: item(4)?.stringValue,
            duration: number(5),
            position: number(6)
        )
    }

    // MARK: - Helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
