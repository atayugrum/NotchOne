import AppKit
import ApplicationServices

/// Controls "whatever is playing" by posting the play/next/previous media keys, which
/// macOS routes to the current Now Playing app. Posting events needs Accessibility.
@MainActor
enum MediaKeyPoster {
    /// NX_KEYTYPE_PLAY / NEXT / PREVIOUS.
    static func keyCode(for command: PlayerCommand) -> Int {
        switch command {
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// `data1` for a system-defined aux-control key event.
    nonisolated static func data1(keyCode: Int, down: Bool) -> Int {
        (keyCode << 16) | ((down ? 0xA : 0xB) << 8)
    }

    /// Returns false when Accessibility isn't granted (nothing is sent).
    @discardableResult
    static func post(_ command: PlayerCommand) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let code = keyCode(for: command)
        for down in [true, false] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: MediaKeyParser.auxControlSubtype,
                data1: data1(keyCode: code, down: down),
                data2: -1
            ) else { return false }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// Cached app names and icons by bundle ID.
@MainActor
enum AppInfo {
    private static var names: [String: String] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = names[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        names[bundleID] = name
        return name
    }

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, let url = url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
