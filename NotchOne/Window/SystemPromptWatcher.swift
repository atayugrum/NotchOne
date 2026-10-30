import AppKit
import CoreGraphics
import Synchronization

/// macOS draws permission prompts below the notch, most at the modal-panel level and the
/// Accessibility one as an ordinary window. After an Allow button is pressed, this watches for
/// such a prompt for a while and lowers the notch below it while it's on screen, so the prompt is
/// never hidden behind the open notch. No level sits above that prompt without covering other
/// apps, so the open notch steps aside until it's answered, and the same while the System
/// Settings it sends you to is in front.
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

    /// Above everything normally; below a prompt while one shows.
    static func level(promptLevel: Int?) -> NSWindow.Level {
        promptLevel.map { $0 > NSWindow.Level.normal.rawValue } == true ? belowPrompts : normalLevel
    }

    /// The open notch would cover an ordinary window it can't drop behind without also going
    /// behind every other app. Only after an Allow button: a system window that's simply on
    /// screen must never hide the notch.
    static func stepsAside(promptLevel: Int?, settingsInFront: Bool, inPermissionFlow: Bool, notchOpen: Bool) -> Bool {
        let ordinaryPrompt = promptLevel.map { $0 <= NSWindow.Level.normal.rawValue } ?? false
        return notchOpen && inPermissionFlow && (ordinaryPrompt || settingsInFront)
    }

    private let windows: () -> [NSWindow]
    private let notchOpen: () -> Bool
    private var observer: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var waiting = false
    private var promptLevel: Int?
    /// From an Allow button until the prompt and the Settings it opened are gone.
    private var inPermissionFlow = false
    private var steppedAside = false

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
        if expected || Self.currentPromptLevel() != nil { watch(expected: expected) }
        refresh()
    }

    /// The notch opened: a prompt that's waiting mustn't end up behind it.
    func notchOpened() {
        guard task == nil else { return }
        watch(expected: false)
    }

    /// Call when the notch opens or closes, or the front app changes.
    func refresh() {
        let awaited = waiting ? NSWindow.Level.modalPanel.rawValue : nil
        let level = Self.level(promptLevel: promptLevel ?? awaited)
        let stepAside = Self.stepsAside(
            promptLevel: promptLevel, settingsInFront: Self.settingsInFront(),
            inPermissionFlow: inPermissionFlow, notchOpen: notchOpen()
        )
        for window in windows() {
            if window.level != level { window.level = level }
            if stepAside != steppedAside {
                if stepAside { window.orderOut(nil) } else { window.orderFrontRegardless() }
            }
        }
        steppedAside = stepAside
    }

    private static func settingsInFront() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == settingsBundleID
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        task?.cancel()
        task = nil
        inPermissionFlow = false
        update(waiting: false, promptLevel: nil)
    }

    private func watch(expected: Bool) {
        task?.cancel()
        if expected { inPermissionFlow = true }
        // Lowered at once: a prompt takes a moment to appear and mustn't start behind the notch.
        if expected { update(waiting: true, promptLevel: Self.currentPromptLevel()) }
        task = Task { [weak self] in
            let start = Date()
            let end = start.addingTimeInterval(Self.watchFor)
            var promptLevel: Int?
            // A prompt stays until it's answered, however long that takes.
            while !Task.isCancelled, Date() < end || promptLevel != nil || self?.settingsOpenInFlow() == true {
                let waiting = expected && Date().timeIntervalSince(start) < Self.promptDelay
                promptLevel = Self.currentPromptLevel()
                self?.update(waiting: waiting, promptLevel: promptLevel)
                try? await Task.sleep(for: .milliseconds(waiting ? 50 : 250))
            }
            guard !Task.isCancelled else { return }
            self?.inPermissionFlow = false
            self?.update(waiting: false, promptLevel: nil)
            self?.task = nil
        }
    }

    private func settingsOpenInFlow() -> Bool {
        inPermissionFlow && Self.settingsInFront()
    }

    private func update(waiting: Bool, promptLevel: Int?) {
        self.waiting = waiting
        self.promptLevel = promptLevel
        refresh()
    }

    /// A window from the processes that draw permission prompts, anywhere below the notch.
    /// Reading levels and owners needs no permission.
    static func currentPromptLevel() -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        // Measured on macOS 27: Accessibility at 0, location at 25, others at 8.
        let levels = Int(NSWindow.Level.normal.rawValue)..<normalLevel.rawValue
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  (window[kCGWindowOwnerPID as String] as? Int32) != me,
                  isPrompt(owner: window[kCGWindowOwnerName as String] as? String, level: layer)
            else { continue }
            return layer
        }
        return nil
    }

    /// Other apps' windows (a mini player, a colour picker) don't count.
    nonisolated static func isPrompt(owner: String?, level: Int) -> Bool {
        guard let owner, promptOwners.contains(owner) else { return false }
        // The other agents keep ordinary windows on screen that aren't prompts.
        return level >= Int(CGWindowLevelForKey(.floatingWindow)) || owner == accessibilityPromptOwner
    }

    /// Draws the Accessibility prompt, the one ordinary-level prompt.
    nonisolated static let accessibilityPromptOwner = "universalAccessAuthWarn"

    /// The system processes that draw permission prompts.
    nonisolated static let promptOwners: Set<String> = [
        "UserNotificationCenter", "universalAccessAuthWarn", "CoreServicesUIAgent", "SecurityAgent", "tccd",
        "CoreLocationAgent",
    ]
}
