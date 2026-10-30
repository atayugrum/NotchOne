import Foundation

/// The single front door for outside input: distributed notifications from the `notch`
/// CLI, and `notchone://` URLs (handed in by the app delegate). Both become a
/// `NotchCommand` and go to the live activity store.
@MainActor
final class ExternalInput {
    private let store: LiveActivityStore
    private var observers: [NSObjectProtocol] = []
    /// Simple flood guard: at most this many commands per second.
    private static let maxPerSecond = 20
    private var windowStart = Date()
    private var windowCount = 0

    init(store: LiveActivityStore) {
        self.store = store
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [NotchCommand.notificationName].map { name in
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] note in
                // Copy out the Sendable strings before hopping to the main actor.
                let fields = (note.userInfo as? [String: String]) ?? [:]
                MainActor.assumeIsolated { self?.receive(fields: fields) }
            }
        }
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    func receive(url: URL) {
        guard let command = NotchCommand(url: url) else { return }
        deliver(command, fromLink: true)
    }

    private func receive(fields: [String: String]) {
        guard let command = NotchCommand(fields: fields) else { return }
        deliver(command)
    }

    private func deliver(_ command: NotchCommand, fromLink: Bool = false) {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 {
            windowStart = now
            windowCount = 0
        }
        windowCount += 1
        guard windowCount <= Self.maxPerSecond else { return }
        store.handle(command, fromLink: fromLink)
    }
}
