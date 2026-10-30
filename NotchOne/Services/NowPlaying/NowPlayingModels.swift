import Foundation

enum PlayerApp: String, CaseIterable, Sendable {
    case music
    case spotify
    /// Any other app, read from the system-wide Now Playing (browsers, video players…).
    case system

    /// Players with their own notifications and AppleScript support.
    static let scriptable: [PlayerApp] = [.music, .spotify]

    /// Empty for `.system`; the real app is in `NowPlayingInfo.appBundleID`.
    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .system: ""
        }
    }

    var displayName: String {
        switch self {
        case .music: String(localized: "Music")
        case .spotify: String(localized: "Spotify")
        case .system: String(localized: "Now Playing")
        }
    }

    /// Distributed notification the player posts on every track or state change.
    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .system: Notification.Name("")
        }
    }

    /// Spotify's AppleScript reports track duration in milliseconds, Music in seconds.
    var scriptDurationIsMilliseconds: Bool { self == .spotify }

    /// Only Spotify includes the playback position in its notification.
    var notificationIncludesPosition: Bool { self == .spotify }
}

enum PlayerCommand: Sendable {
    case playPause
    case next
    case previous
}

@MainActor
protocol PlayerControlling: AnyObject {
    func perform(_ command: PlayerCommand)
    /// Ask the player for an exact position (it drifts while we interpolate).
    func refreshPosition()
}

struct NowPlayingInfo: Equatable, Sendable {
    var source: PlayerApp
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    /// Position at `updatedAt`, in seconds.
    var position: TimeInterval
    var isPlaying: Bool
    var updatedAt: Date
    /// App that is playing, for `.system` sources (e.g. "com.google.Chrome").
    var appBundleID: String? = nil

    /// Identifies a track across notifications and script results.
    /// The app that's playing it: Music or Spotify, or the browser or player behind the
    /// system's Now Playing.
    var playerBundleID: String? {
        let id = source == .system ? appBundleID : source.bundleID
        return id.flatMap { $0.isEmpty ? nil : $0 }
    }

    var trackKey: String { "\(source.rawValue)|\(appBundleID ?? "")|\(title)|\(artist)|\(album)" }

    /// Position now, moving forward while playing, clamped to the track length.
    func position(at date: Date) -> TimeInterval {
        var value = position
        if isPlaying {
            value += max(0, date.timeIntervalSince(updatedAt))
        }
        if let duration {
            value = min(value, duration)
        }
        return max(0, value)
    }
}

/// Raw values from the player's AppleScript state query.
struct ScriptTrackFields: Equatable, Sendable {
    var state: String
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var position: Double?
}
