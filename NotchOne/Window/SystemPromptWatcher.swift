import AppKit
import CoreGraphics
import Synchronization

/// macOS draws permission prompts at the modal-panel level, below the notch. After an Allow
/// button is pressed, this watches for such a prompt for a while and lowers the notch below it
/// while it's on screen, so the prompt is never hidden behind the open notch.
@MainActor
final class SystemPromptWatcher {
    /// Posted when a button is about to make macOS ask for a permission.
    nonisolated static let expected = Notification.Name("com.atayug.notchone.systemPromptExpected")

    /// Safe from any thread: the watcher picks it up on the main queue. Remembered, so a prompt
    /// asked for before the notch window exists (at launch) is still watched for.
    nonisolated static func expectPrompt() {
        lastExpected.withLock { $0 = Date() }
        NotificationCenter.default.post(name: expected, object: nil)
    }

    private nonisolated static let lastExpected = Mutex<Date?>(nil)

    /// The notch's own level, and the one it drops to while a prompt shows.
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let belowPrompts = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
    /// Long enough to read the prompt and answer it.
    static let watchFor: TimeInterval = 90

    private let windows: () -> [NSWindow]
    private var observer: NSObjectProtocol?
    private var task: Task<Void, Never>?

    init(windows: @escaping () -> [NSWindow]) {
        self.windows = windows
    }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: Self.expected, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
        if let since = Self.lastExpected.withLock({ $0 }), Date().timeIntervalSince(since) < Self.watchFor {
            watch()
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        task?.cancel()
        setLowered(false)
    }

    private func watch() {
        task?.cancel()
        task = Task { [weak self] in
            let end = Date().addingTimeInterval(Self.watchFor)
            while !Task.isCancelled, Date() < end {
                self?.setLowered(Self.isPromptShowing())
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.setLowered(false)
        }
    }

    private func setLowered(_ lowered: Bool) {
        let level = lowered ? Self.belowPrompts : Self.normalLevel
        for window in windows() where window.level != level {
            window.level = level
        }
    }

    /// A window from another process above normal windows but below the Dock: where macOS
    /// shows its permission prompts (UserNotificationCenter draws them at the modal-panel
    /// level). Reading levels and owners needs no permission.
    static func isPromptShowing() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let levels = Int(CGWindowLevelForKey(.floatingWindow))..<Int(CGWindowLevelForKey(.dockWindow))
        return list.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  (window[kCGWindowOwnerPID as String] as? Int32) != me
            else { return false }
            return isPrompt(owner: window[kCGWindowOwnerName as String] as? String)
        }
    }

    /// Other apps' floating windows (a mini player, a colour picker) don't count.
    nonisolated static func isPrompt(owner: String?) -> Bool {
        guard let owner else { return false }
        return promptOwners.contains(owner)
    }

    /// The system processes that draw permission prompts.
    nonisolated static let promptOwners: Set<String> = [
        "UserNotificationCenter", "universalAccessAuthWarn", "CoreServicesUIAgent", "SecurityAgent", "tccd",
    ]
}
