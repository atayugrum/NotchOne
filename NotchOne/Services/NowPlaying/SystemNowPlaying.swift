import Foundation

/// One JSON line from `SystemNowPlaying.js`.
struct SystemSnapshot: Decodable, Equatable, Sendable {
    var bundle: String?
    var parentBundle: String?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var rate: Double?
    /// Seconds since 1970 when `elapsed` was measured.
    var timestamp: Double?
    var playing: Bool?
    var none: Bool?
    var unavailable: Bool?
}

enum SystemLine: Equatable, Sendable {
    case nothingPlaying
    /// MediaRemote couldn't be loaded on this macOS.
    case unavailable
    case snapshot(SystemSnapshot)
}

/// Pure parsing for the system Now Playing helper.
enum SystemNowPlayingParser {
    static func parse(line: Data) -> SystemLine? {
        guard let snapshot = try? JSONDecoder().decode(SystemSnapshot.self, from: line) else { return nil }
        if snapshot.unavailable == true { return .unavailable }
        if snapshot.none == true { return .nothingPlaying }
        return .snapshot(snapshot)
    }

    /// The app to credit. Web content in Safari reports a WebKit helper process,
    /// so its parent app is used instead.
    static func appBundleID(for snapshot: SystemSnapshot) -> String? {
        guard let bundle = snapshot.bundle, !bundle.isEmpty else { return snapshot.parentBundle }
        if bundle.hasPrefix("com.apple.WebKit") {
            return snapshot.parentBundle ?? "com.apple.Safari"
        }
        return bundle
    }

    static func info(from snapshot: SystemSnapshot, now: Date) -> NowPlayingInfo? {
        guard let title = snapshot.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }

        let rate = snapshot.rate ?? 0
        let isPlaying = snapshot.playing ?? (rate > 0)
        let measuredAt = snapshot.timestamp.map { Date(timeIntervalSince1970: $0) } ?? now
        // A timestamp in the future would make the position run backwards.
        let updatedAt = min(measuredAt, now)
        let duration = snapshot.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        return NowPlayingInfo(
            source: .system,
            title: title,
            artist: snapshot.artist ?? "",
            album: snapshot.album ?? "",
            duration: duration,
            position: max(0, snapshot.elapsed ?? 0),
            isPlaying: isPlaying,
            updatedAt: updatedAt,
            appBundleID: appBundleID(for: snapshot)
        )
    }

    /// Splits a growing stdout buffer into complete lines, returning the leftover.
    static func splitLines(_ buffer: Data) -> (lines: [Data], rest: Data) {
        var lines: [Data] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[start..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            start = buffer.index(after: newline)
        }
        return (lines, Data(buffer[start...]))
    }
}
