import AppKit
import ApplicationServices

/// One macOS notification banner, as read from its accessibility text.
struct NotificationBanner: Equatable, Sendable {
    let id: String
    let app: String
    let title: String
    let body: String
}

/// A notification kept for reading later.
struct NotificationRecord: Identifiable, Equatable, Sendable {
    let id: String
    let banner: NotificationBanner
    let date: Date
    let appPID: Int32?
    let appBundleID: String?
}

/// Pure rules for reading a banner.
enum NotificationBannerLogic {
    static let lifetime: TimeInterval = 7
    /// How many stay in the Notifications tab. They're kept in memory, until NotchOne quits.
    static let historyLimit = 50
    /// macOS shows a few banners at most; more than this is Notification Center's list.
    static let maxBannersAtOnce = 3
    /// Height of the menu bar row where the clock opens Notification Center.
    static let menuBarReach: CGFloat = 40

    /// Scrolling or clicking anywhere else mustn't leave the macOS banner on screen.
    static func openedNotificationCenter(secondsSinceClick: Double, pointerBelowTop: CGFloat) -> Bool {
        secondsSinceClick < 1 && pointerBelowTop < menuBarReach
    }

    /// Newest first, at most `historyLimit`, and the same notification only once.
    static func adding(_ record: NotificationRecord, to history: [NotificationRecord]) -> [NotificationRecord] {
        Array(([record] + history.filter { $0.id != record.id }).prefix(historyLimit))
    }

    /// macOS describes a banner as "App, title, subtitle, body", so the app is the first part.
    static func banner(id: String, description: String?, title: String?, subtitle: String?, body: String?) -> NotificationBanner? {
        let app = description?.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let heading = [title, subtitle].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ": ")
        let text = body ?? ""
        guard !id.isEmpty, !heading.isEmpty || !text.isEmpty else { return nil }
        return NotificationBanner(id: id, app: app, title: heading.isEmpty ? app : heading, body: text)
    }

    /// The banner's actions end with its close button; its name depends on the Mac's language.
    static func closeAction(in actions: [String]) -> String? {
        actions.last { $0.hasPrefix("Name:") }
    }
}

/// Shows macOS notifications in the notch. They're read from the banners through Accessibility
/// when they appear and kept in memory for the Notifications tab until NotchOne quits; nothing
/// is written to disk. With "hide banners"
/// on, the macOS banner is closed so only the notch shows it.
@MainActor
final class NotificationMirror {
    private static let bundleID = "com.apple.notificationcenterui"
    private static let events = [kAXWindowCreatedNotification, kAXLayoutChangedNotification]

    private let activity: ActivityState
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var seen: [String] = []
    private var trustObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard trustObserver == nil else { return }
        // Turns on as soon as Accessibility is allowed, and follows Notification Center restarts.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.attach()
            }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    func stop() {
        if let trustObserver { DistributedNotificationCenter.default().removeObserver(trustObserver) }
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        trustObserver = nil
        launchObserver = nil
        detach()
    }

    private func attach() {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return }
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        detach()

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let mirror = Unmanaged<NotificationMirror>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { mirror.readBanners() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        Self.events.forEach { AXObserverAddNotification(created, element, $0 as CFString, context) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedPID = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    private func readBanners() {
        guard let pid = observedPID else { return }
        let windows: [AXUIElement] = Self.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
        let banners = windows.flatMap { Self.banners(in: $0, depth: 0) }
        // Opening Notification Center lists old notifications the same way: those are left alone.
        guard banners.count <= NotificationBannerLogic.maxBannersAtOnce else { return }
        let mayHide = !Self.userJustActed
            && UserDefaults.standard.bool(forKey: SettingsKey.notificationsHideBanners, default: SettingsDefault.notificationsHideBanners)
        banners.forEach { show($0, hide: mayHide) }
    }

    /// A click on the menu bar just now may have opened Notification Center: nothing is closed then.
    private static var userJustActed: Bool {
        let top = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame.maxY ?? .infinity
        return NotificationBannerLogic.openedNotificationCenter(
            secondsSinceClick: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
            pointerBelowTop: top - NSEvent.mouseLocation.y
        )
    }

    private func show(_ element: AXUIElement, hide: Bool) {
        let id: String = Self.value(element, kAXIdentifierAttribute) ?? ""
        guard !seen.contains(id) else { return }
        if hide { Self.moveOffScreen(element) }
        let children: [AXUIElement] = Self.value(element, kAXChildrenAttribute) ?? []
        let text = { (name: String) -> String? in
            children.first { Self.value($0, kAXIdentifierAttribute) == name }.flatMap { Self.value($0, kAXValueAttribute) }
        }
        guard let banner = NotificationBannerLogic.banner(
            id: id, description: Self.value(element, kAXDescriptionAttribute),
            title: text("title"), subtitle: text("subtitle"), body: text("body")
        ) else { return }
        seen = (seen + [id]).suffix(50)
        let app = NSWorkspace.shared.runningApplications.first { $0.localizedName == banner.app }
        activity.live.show(banner, appPID: app?.processIdentifier, appBundleID: app?.bundleIdentifier)
        guard hide else { return }
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        if let action = NotificationBannerLogic.closeAction(in: names as? [String] ?? []) {
            AXUIElementPerformAction(element, action as CFString)
        }
    }

    /// Closing a banner takes about a second, so its window is moved away first and it's never seen.
    private static func moveOffScreen(_ banner: AXUIElement) {
        var position = CGPoint(x: 20000, y: 0)
        guard let window: AXUIElement = value(banner, kAXWindowAttribute),
              let value = AXValueCreate(.cgPoint, &position)
        else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func banners(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        if value(element, kAXSubroleAttribute) == "AXNotificationCenterBanner" { return [element] }
        guard depth < 6 else { return [] }
        let children: [AXUIElement] = value(element, kAXChildrenAttribute) ?? []
        return children.flatMap { banners(in: $0, depth: depth + 1) }
    }

    private static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
