import Foundation

/// A newer NotchOne on the release feed.
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let download: URL
    let page: URL?
    let notes: String?
}

/// Pure rules for the update check: reading the feed and comparing versions.
enum UpdateLogic {
    /// Releases are signed with this team's Developer ID; nothing else gets installed.
    static let teamID = "4CALNLY425"
    static let bundleID = "com.atayug.notchone"
    /// At most one automatic check a day.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// A release feed answer is a few KB; the app zip about 10 MB.
    static let maxFeedBytes = 1_000_000
    static let maxDownloadBytes: Int64 = 200_000_000

    /// The code requirement a downloaded app must meet: this app, signed with a Developer
    /// ID certificate (not a development one) issued by Apple to this team.
    static var requirement: String {
        "anchor apple generic and identifier \"\(bundleID)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// "v2.1.0" → [2, 1, 0]. Nil for anything that isn't dotted numbers.
    static func components(_ version: String) -> [Int]? {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// 2.1 is newer than 2.0.9; 2.1 and 2.1.0 are the same.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        let count = max(new.count, old.count)
        let a = new + Array(repeating: 0, count: count - new.count)
        let b = old + Array(repeating: 0, count: count - old.count)
        return b.lexicographicallyPrecedes(a)
    }

    /// Reads a GitHub "latest release" answer. Drafts and pre-releases are skipped, and
    /// only an HTTPS zip named like the app is taken.
    static func update(fromRelease data: Data, current: String) -> AvailableUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              isNewer(tag, than: current),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        let zip = assets.lazy.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String,
                  name.hasPrefix("NotchOne"), name.hasSuffix(".zip"),
                  let link = asset["browser_download_url"] as? String,
                  let url = URL(string: link), url.scheme == "https"
            else { return nil }
            return url
        }.first
        guard let zip, let version = components(tag)?.map(String.init).joined(separator: ".") else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let notes = (json["body"] as? String).map { NotchCommand.clean($0, max: 600) }.flatMap { $0.isEmpty ? nil : $0 }
        return AvailableUpdate(version: version, download: zip, page: page, notes: notes)
    }

    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval || lastCheck > now
    }
}
