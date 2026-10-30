import Foundation
import Intents

/// Is a Focus mode on? Uses the public Focus Status API (permission asked when the
/// setting is turned on). The API has no change callback, so it's read every 30 s with
/// a loose timer, which costs one tiny wake-up.
@MainActor
final class FocusMonitor {
    private let activity: ActivityState
    private var timer: Timer?
    /// The first reading after starting isn't a change worth showing.
    private var hasRead = false

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard timer == nil else { return }
        let center = INFocusStatusCenter.default
        if center.authorizationStatus == .notDetermined {
            SystemPromptWatcher.expectPrompt()
            // Called back on a background queue.
            center.requestAuthorization { @Sendable [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasRead = false
        activity.isFocused = false
    }

    func refresh() {
        let center = INFocusStatusCenter.default
        let focused = center.authorizationStatus == .authorized && center.focusStatus.isFocused == true
        defer { hasRead = true }
        guard activity.isFocused != focused else { return }
        activity.isFocused = focused
        // Show it in the closed notch too, briefly, like a volume change.
        if hasRead { activity.showPeek(.focus(on: focused)) }
    }
}
