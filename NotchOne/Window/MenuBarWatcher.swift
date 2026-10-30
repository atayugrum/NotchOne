import AppKit
import ApplicationServices
import SwiftUI

/// Reads where the front app's menus are, so the ears that stay beside the notch (a playing
/// song, a call) don't cover them. Needs Accessibility; without it the ears keep their size and
/// still step aside when the pointer comes near.
@MainActor
final class MenuBarWatcher {
    /// Apps fill their menus shortly after they come to the front.
    private static let delays: [Duration] = [.milliseconds(300), .seconds(1)]

    private let activity: ActivityState
    private let notchRect: () -> CGRect?
    private var observer: NSObjectProtocol?
    private var task: Task<Void, Never>?

    init(activity: ActivityState, notchRect: @escaping () -> CGRect?) {
        self.activity = activity
        self.notchRect = notchRect
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        task?.cancel()
        activity.menuEarLimit = nil
    }

    private func refresh() {
        task?.cancel()
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primaryHeight = NSScreen.screens.first?.frame.height
        else {
            withAnimation(Motion.peekOut) { activity.menuEarLimit = nil }
            return
        }
        task = Task { [weak self] in
            for delay in Self.delays {
                try? await Task.sleep(for: delay)
                let menus = await Task.detached(priority: .utility) {
                    Self.menus(pid: pid, primaryHeight: primaryHeight)
                }.value
                guard !Task.isCancelled, let self, let notch = self.notchRect() else { return }
                let limit = EarLayout.menuLimit(notchRect: notch, menus: menus, corner: StatusIndicatorWatcher.corner)
                guard limit != self.activity.menuEarLimit else { continue }
                withAnimation(Motion.peekOut) { self.activity.menuEarLimit = limit }
            }
        }
    }

    /// The app's menu titles, in screen coordinates (origin bottom-left).
    private nonisolated static func menus(pid: pid_t, primaryHeight: CGFloat) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar: AXUIElement = value(app, kAXMenuBarAttribute),
              let items: [AXUIElement] = value(bar, kAXChildrenAttribute)
        else { return [] }
        return items.dropFirst().compactMap { item in
            var position = CGPoint.zero, size = CGSize.zero
            guard let origin: AXValue = value(item, kAXPositionAttribute), AXValueGetValue(origin, .cgPoint, &position),
                  let extent: AXValue = value(item, kAXSizeAttribute), AXValueGetValue(extent, .cgSize, &size)
            else { return nil }
            return CGRect(x: position.x, y: primaryHeight - position.y - size.height, width: size.width, height: size.height)
        }
    }

    private nonisolated static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as! T?
    }
}
