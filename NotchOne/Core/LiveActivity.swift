import Foundation

/// Something ongoing that wants room in the notch: a CLI job, a notification, a
/// message. New sources post these instead of adding cases to the notch layout.
struct LiveActivity: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case job
        case message
        /// A macOS notification from another app.
        case notification
        /// Camera or microphone in use (meeting mode).
        case meeting
        /// A `notchone://` link, which any web page or app can open: always shown with a
        /// link symbol, so it can't pass for the system.
        case link
    }

    enum Status: Equatable, Sendable {
        case running(fraction: Double?)
        case succeeded
        case failed
        case info
        case meeting(mic: Bool, camera: Bool, muted: Bool)
    }

    let id: String
    var source: Source
    var title: String
    var detail: String?
    var status: Status
    var startedAt: Date
    var finishedAt: Date?
    /// App to bring forward when the activity is clicked.
    var appPID: Int32?
    var expiresAt: Date?
    /// App shown with the activity (the app using the microphone).
    var appBundleID: String?
    /// Name of the app a notification came from.
    var appName: String?

    /// Higher wins the ears. Now Playing is 10 (see `ActivityState.ears`).
    var priority: Int {
        switch (source, status) {
        // Anyone can open a link, so it never pushes aside a real job or notification.
        case (.link, _): 30
        case (_, .meeting): 100
        case (_, .failed): 70
        case (.job, .running): 60
        case (_, .succeeded): 50
        case (_, .info): 40
        case (_, .running): 5
        }
    }

    var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var symbol: String {
        if source == .link { return "link" }
        return switch status {
        case .meeting(_, let camera, let muted): muted ? "mic.slash.fill" : (camera ? "video.fill" : "mic.fill")
        case .failed: "xmark.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .info: "text.bubble.fill"
        case .running: "terminal.fill"
        }
    }
}

/// Pure rules for turning commands into activities. Time is passed in for tests.
enum LiveActivityLogic {
    static let maxCount = 8
    static let finishedLifetime: TimeInterval = 8
    static let messageLifetime: TimeInterval = 5
    /// A job that stops reporting (killed CLI) disappears after this.
    static let staleLifetime: TimeInterval = 60 * 60

    /// `fromLink`: the command came from a `notchone://` URL. Its items are kept apart
    /// from the CLI's and marked as coming from a link.
    static func apply(_ command: NotchCommand, to activities: [LiveActivity], now: Date, fromLink: Bool = false) -> [LiveActivity] {
        guard fromLink else { return applyCommand(command, to: activities, now: now) }
        // Own ids, so a link can't change or relabel a job the `notch` tool is running.
        let command: NotchCommand = switch command {
        case .progress(let id, let label, let fraction): .progress(id: "link." + id, label: label, fraction: fraction)
        case .finish(let id, let label, let success, let seconds): .finish(id: "link." + id, label: label, success: success, seconds: seconds)
        default: command
        }
        let applied = applyCommand(command, to: activities, now: now)
        // The item this command made or changed: mark it as a link's.
        let changed = applied.filter { item in !activities.contains(item) }
        return applied.map { item in
            guard changed.contains(where: { $0.id == item.id }) else { return item }
            var marked = item
            marked.source = .link
            marked.detail = String(localized: "From a link")
            return marked
        }
    }

    private static func applyCommand(_ command: NotchCommand, to activities: [LiveActivity], now: Date) -> [LiveActivity] {
        var list = prune(activities, now: now)
        switch command {
        case .progress(let id, let label, let fraction):
            let key = "job:" + id
            var item = list.first { $0.id == key } ?? LiveActivity(
                id: key, source: .job, title: "Job", status: .running(fraction: nil), startedAt: now
            )
            if !label.isEmpty { item.title = label }
            item.status = .running(fraction: fraction)
            item.finishedAt = nil
            item.expiresAt = now + staleLifetime
            upsert(item, into: &list)

        case .finish(let id, let label, let success, let seconds):
            let key = "job:" + id
            let existing = list.first { $0.id == key }
            let started = existing?.startedAt ?? now
            upsert(LiveActivity(
                id: key,
                source: .job,
                title: label.isEmpty ? (existing?.title ?? String(localized: "Job")) : label,
                status: success ? .succeeded : .failed,
                startedAt: seconds.map { now - $0 } ?? started,
                finishedAt: now,
                expiresAt: now + finishedLifetime
            ), into: &list)

        case .say(let text):
            upsert(LiveActivity(
                id: "say:\(now.timeIntervalSince1970)",
                source: .message,
                title: text,
                status: .info,
                startedAt: now,
                expiresAt: now + messageLifetime
            ), into: &list)
        }
        return trim(list)
    }

    /// A macOS notification, shown for a few seconds and clickable to open its app.
    static func apply(_ banner: NotificationBanner, appPID: Int32?, appBundleID: String?, to activities: [LiveActivity], now: Date) -> [LiveActivity] {
        var list = prune(activities, now: now)
        upsert(LiveActivity(
            id: "notification:" + banner.id,
            source: .notification,
            title: banner.title,
            detail: banner.body.isEmpty ? banner.app : banner.body,
            status: .info,
            startedAt: now,
            appPID: appPID,
            expiresAt: now + NotificationBannerLogic.lifetime,
            appBundleID: appBundleID,
            appName: banner.app
        ), into: &list)
        return trim(list)
    }

    static func prune(_ activities: [LiveActivity], now: Date) -> [LiveActivity] {
        activities.filter { ($0.expiresAt ?? .distantFuture) > now }
    }

    /// The one the closed notch shows: highest priority, newest first on ties.
    static func top(_ activities: [LiveActivity]) -> LiveActivity? {
        activities.max { a, b in
            a.priority != b.priority ? a.priority < b.priority : a.startedAt < b.startedAt
        }
    }

    private static func upsert(_ item: LiveActivity, into list: inout [LiveActivity]) {
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
    }

    /// Keeps at most `maxCount`, dropping the lowest-priority, oldest ones.
    private static func trim(_ list: [LiveActivity]) -> [LiveActivity] {
        guard list.count > maxCount else { return list }
        let keep = list
            .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.startedAt > $1.startedAt }
            .prefix(maxCount)
            .map(\.id)
        return list.filter { keep.contains($0.id) }
    }
}
