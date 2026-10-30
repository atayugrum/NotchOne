import Foundation

/// AppleScript sources for Music and Spotify. Apps are addressed by bundle ID, and
/// callers must check the app is running first: `tell application` launches it otherwise.
enum PlayerScripts {

    /// Returns `{state}` when stopped, else `{state, title, artist, album, duration, position}`.
    static func state(for app: PlayerApp) -> String {
        """
        with timeout of 3 seconds
            tell application id "\(app.bundleID)"
                set s to player state as text
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position}
            end tell
        end timeout
        """
    }

    static func command(_ command: PlayerCommand, for app: PlayerApp) -> String {
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return """
        with timeout of 3 seconds
            tell application id "\(app.bundleID)" to \(verb)
        end timeout
        """
    }

    /// Music returns raw image data; Spotify returns an https artwork URL.
    /// Nil for `.system`, which has no AppleScript.
    static func artwork(for app: PlayerApp) -> String? {
        let expression: String
        switch app {
        case .music: expression = "raw data of artwork 1 of current track"
        case .spotify: expression = "artwork url of current track"
        case .system: return nil
        }
        return """
        with timeout of 3 seconds
            tell application id "\(app.bundleID)" to get \(expression)
        end timeout
        """
    }
}
