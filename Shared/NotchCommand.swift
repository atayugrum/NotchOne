import Foundation

/// What Claude Code reported through a hook.
enum ClaudeEventKind: String, Equatable, Sendable {
    /// A prompt was submitted; Claude is working.
    case started
    /// Claude is waiting for permission or input.
    case needsYou
    /// Claude finished its turn.
    case finished
}

struct ClaudeEvent: Equatable, Sendable {
    var kind: ClaudeEventKind
    var session: String
    /// Project folder name (last path component of the working directory).
    var project: String
    var message: String?
    /// The app that hosts the session (Terminal, iTerm, VS Code…), to bring it forward.
    var appPID: Int32?
}

/// A message to the app from the `notch` command line tool or a `notchone://` URL.
///
/// Shared by the app and the CLI. Both sides go through `fields`/`init?(fields:)`, which
/// is also where untrusted input is checked: lengths are capped, control characters
/// removed, numbers clamped, and unknown fields ignored.
enum NotchCommand: Equatable, Sendable {
    /// A job is running. `fraction` nil means "no known progress". An empty label keeps
    /// the job's previous one.
    case progress(id: String, label: String, fraction: Double?)
    case finish(id: String, label: String, success: Bool, seconds: Double?)
    case say(text: String)
    case claude(ClaudeEvent)

    /// Distributed notification the CLI posts; `userInfo` is `fields`.
    static let notificationName = "com.atayug.notchone.command"
    static let urlScheme = "notchone"

    static let maxText = 160
    static let maxID = 64

    // MARK: - Encoding

    var fields: [String: String] {
        switch self {
        case .progress(let id, let label, let fraction):
            var fields = ["cmd": "progress", "id": id, "label": label]
            if let fraction { fields["fraction"] = String(fraction) }
            return fields
        case .finish(let id, let label, let success, let seconds):
            var fields = ["cmd": "finish", "id": id, "label": label, "success": success ? "1" : "0"]
            if let seconds { fields["seconds"] = String(seconds) }
            return fields
        case .say(let text):
            return ["cmd": "say", "text": text]
        case .claude(let event):
            var fields = ["cmd": "claude", "event": event.kind.rawValue, "session": event.session, "project": event.project]
            if let message = event.message { fields["message"] = message }
            if let pid = event.appPID { fields["pid"] = String(pid) }
            return fields
        }
    }

    // MARK: - Decoding

    init?(fields: [String: String]) {
        func text(_ key: String, max: Int = NotchCommand.maxText) -> String? {
            guard let raw = fields[key] else { return nil }
            let value = Self.clean(raw, max: max)
            return value.isEmpty ? nil : value
        }

        switch fields["cmd"] {
        case "progress":
            guard let id = text("id", max: Self.maxID) else { return nil }
            let fraction = fields["fraction"].flatMap(Double.init).flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
            self = .progress(id: id, label: text("label") ?? "", fraction: fraction)
        case "finish":
            guard let id = text("id", max: Self.maxID) else { return nil }
            let seconds = fields["seconds"].flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            self = .finish(id: id, label: text("label") ?? "", success: fields["success"] != "0", seconds: seconds)
        case "say":
            guard let message = text("text") else { return nil }
            self = .say(text: message)
        case "claude":
            guard let kind = fields["event"].flatMap(ClaudeEventKind.init(rawValue:)),
                  let session = text("session", max: Self.maxID)
            else { return nil }
            let pid = fields["pid"].flatMap(Int32.init).flatMap { $0 > 0 ? $0 : nil }
            self = .claude(ClaudeEvent(
                kind: kind,
                session: session,
                project: text("project") ?? "Claude Code",
                message: text("message"),
                appPID: pid
            ))
        default:
            return nil
        }
    }

    /// `notchone://progress?id=build&label=Building&fraction=0.4`
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              let host = url.host(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var fields = ["cmd": host.lowercased()]
        for item in components.queryItems ?? [] where item.name != "cmd" {
            if let value = item.value { fields[item.name] = value }
        }
        self.init(fields: fields)
    }

    /// Trims, drops control characters and caps the length.
    static func clean(_ raw: String, max: Int) -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        return text.count > max ? String(text.prefix(max - 1)) + "…" : text
    }
}
