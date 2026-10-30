import AppKit
import CoreGraphics
import Synchronization

/// macOS draws permission prompts at the modal-panel level, below the notch. After an Allow
/// button is pressed, this watches for such a prompt for a while and lowers the notch below it
/// while it's on screen, so the prompt is never hidden behind the open notch. System Settings is
/// an ordinary window, so while it's in front the open notch drops below it too.
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
    /// How long a prompt can take to appear after a button is pressed.
    static let promptDelay: TimeInterval = 2

    /// Where permissions are switched on after a prompt sends you there.
    nonisolated static let settingsBundleID = "com.apple.systempreferences"

    /// Above everything normally; below prompts while one shows; below System Settings while
    /// the open notch would cover it.
    static func level(promptShowing: Bool, settingsInFront: Bool, notchOpen: Bool) -> NSWindow.Level {
        if settingsInFront && notchOpen { return .normal }
        return promptShowing ? belowPrompts : normalLevel
    }

    private let windows: () -> [NSWindow]
    private let notchOpen: () -> Bool
    private var observer: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var promptShowing = false

    init(windows: @escaping () -> [NSWindow], notchOpen: @escaping () -> Bool) {
        self.windows = windows
        self.notchOpen = notchOpen
    }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: Self.expected, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch(expected: true) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let expected = Self.lastExpected.withLock({ $0 }).map { Date().timeIntervalSince($0) < Self.watchFor } ?? false
        // A prompt can already be waiting from before this launch.
        if expected || Self.isPromptShowing() { watch(expected: expected) }
        refresh()
    }

    /// The notch opened: a prompt that's waiting mustn't end up behind it.
    func notchOpened() {
        guard task == nil else { return }
        watch(expected: false)
    }

    /// Call when the notch opens or closes, or the front app changes.
    func refresh() {
        let settingsInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleID
        let level = Self.level(promptShowing: promptShowing, settingsInFront: settingsInFront, notchOpen: notchOpen())
        for window in windows() where window.level != level {
            window.level = level
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        task?.cancel()
        task = nil
        setLowered(false)
    }

    private func watch(expected: Bool) {
        task?.cancel()
        // Lowered at once: a prompt takes a moment to appear and mustn't start behind the notch.
        if expected { setLowered(true) }
        task = Task { [weak self] in
            let start = Date()
            let end = start.addingTimeInterval(Self.watchFor)
            var showing = false
            // A prompt stays until it's answered, however long that takes.
            while !Task.isCancelled, Date() < end || showing {
                let waiting = expected && Date().timeIntervalSince(start) < Self.promptDelay
                showing = Self.isPromptShowing()
                self?.setLowered(waiting || showing)
                try? await Task.sleep(for: .milliseconds(waiting ? 50 : 250))
            }
            self?.setLowered(false)
            self?.task = nil
        }
    }

    private func setLowered(_ lowered: Bool) {
        promptShowing = lowered
        refresh()
    }

    /// A window from another process above normal windows but below the Dock: where macOS
    /// shows its permission prompts (UserNotificationCenter draws them at the modal-panel
    /// level). Reading levels and owners needs no permission.
    static func isPromptShowing() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        // Up to the notch's own level: the location prompt sits at 25, others at 8.
        let levels = Int(CGWindowLevelForKey(.floatingWindow))..<normalLevel.rawValue
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
        "CoreLocationAgent",
    ]
}
