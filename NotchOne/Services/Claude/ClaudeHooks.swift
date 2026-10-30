import Foundation

/// Adds and removes NotchOne's hooks in Claude Code's `~/.claude/settings.json`.
///
/// The edit is pure (`install` / `remove` on a dictionary) so it can be tested; only
/// `ClaudeHooksFile` touches disk, and it keeps a backup before writing.
enum ClaudeHooks {
    /// Hook events NotchOne listens to.
    static let events = ["UserPromptSubmit", "Notification", "Stop"]
    /// Marks our entries so Disconnect removes only them.
    static let marker = "claude-hook"

    static func command(cliPath: String) -> String {
        "\"\(cliPath)\" \(marker)"
    }

    static func isOurs(_ command: String) -> Bool {
        command.contains("notch\" \(marker)") || command.hasSuffix("notch \(marker)")
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            commands(in: hooks[event]).contains(where: isOurs)
        }
    }

    static func install(into settings: [String: Any], cliPath: String) -> [String: Any] {
        var settings = remove(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command(cliPath: cliPath)]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Removes only NotchOne's hook commands; groups and events left empty go too.
    static func remove(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var settings = settings
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { !isOurs($0["command"] as? String ?? "") }
                if kept.isEmpty { return nil }
                var copy = group
                copy["hooks"] = kept
                return copy
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// The JSON shown to the user before connecting.
    static func preview(cliPath: String) -> String {
        let hooks = install(into: [:], cliPath: cliPath)
        guard let data = try? JSONSerialization.data(
            withJSONObject: hooks,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func commands(in value: Any?) -> [String] {
        let groups = value as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }
}

enum ClaudeHooksError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "~/.claude/settings.json isn't valid JSON, so NotchOne left it alone."
    }
}

/// Reads and writes `~/.claude/settings.json`.
struct ClaudeHooksFile {
    var url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")

    func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }   // no file yet
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeHooksError.unreadable
        }
        return object
    }

    var isInstalled: Bool {
        (try? read()).map(ClaudeHooks.isInstalled) ?? false
    }

    func connect(cliPath: String) throws {
        try write(ClaudeHooks.install(into: read(), cliPath: cliPath))
    }

    func disconnect() throws {
        try write(ClaudeHooks.remove(from: read()))
    }

    private func write(_ settings: [String: Any]) throws {
        let target = url.resolvingSymlinksInPath()
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: target.path) {
            let backup = target.appendingPathExtension("notchone-backup")
            try? manager.removeItem(at: backup)
            try manager.copyItem(at: target, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: target, options: .atomic)
    }
}
