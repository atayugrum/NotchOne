import AppKit
import SwiftUI

/// Holds the live activities and removes expired ones. One sleeping task waits for the
/// next expiry, so nothing polls.
@MainActor
@Observable
final class LiveActivityStore {
    private(set) var items: [LiveActivity] = []
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    var top: LiveActivity? { LiveActivityLogic.top(items) }

    func handle(_ command: NotchCommand, fromLink: Bool = false) {
        withAnimation(Motion.peekIn) {
            items = LiveActivityLogic.apply(command, to: items, now: Date(), fromLink: fromLink)
        }
        scheduleExpiry()
    }

    /// For built-in sources that manage their own lifetime (meeting mode).
    func set(_ item: LiveActivity) {
        guard items.first(where: { $0.id == item.id }) != item else { return }
        withAnimation(Motion.peekIn) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else {
                items.append(item)
            }
        }
    }

    func dismiss(_ id: LiveActivity.ID) {
        withAnimation(Motion.peekOut) { items.removeAll { $0.id == id } }
        scheduleExpiry()
    }

    /// Brings the session's app forward (Claude Code) and clears a "needs you".
    func activate(_ activity: LiveActivity) {
        if let pid = activity.appPID, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        if activity.status == .needsYou { dismiss(activity.id) }
    }

    func removeAll() {
        expiryTask?.cancel()
        items.removeAll()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = items.compactMap(\.expiresAt).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.peekOut) {
                self.items = LiveActivityLogic.prune(self.items, now: Date())
            }
            self.scheduleExpiry()
        }
    }
}
