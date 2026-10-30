import AppKit
import CoreGraphics

/// macOS draws its orange mic, green camera and purple screen-recording dot as a small window
/// above the menu bar, sometimes right next to the notch. This watches for it and narrows the
/// closed notch's ears so they never cover it. Reading window owners and frames needs no
/// permission, and only the few windows above the notch are read.
@MainActor
final class StatusIndicatorWatcher {
    static let interval: Duration = .seconds(1)
    /// The closed notch's flared top corners, outside each ear.
    static let corner: CGFloat = 6

    private let activity: ActivityState
    private let panel: () -> NSWindow?
    private let notchRect: () -> CGRect?
    private var task: Task<Void, Never>?

    init(activity: ActivityState, panel: @escaping () -> NSWindow?, notchRect: @escaping () -> CGRect?) {
        self.activity = activity
        self.panel = panel
        self.notchRect = notchRect
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        activity.earLimit = nil
    }

    private func check() {
        guard let panel = panel(), let notchRect = notchRect() else { return }
        let limit = EarLayout.limit(
            notchRect: notchRect,
            indicators: Self.indicators(above: CGWindowID(panel.windowNumber)),
            corner: Self.corner
        )
        if limit != activity.earLimit { activity.earLimit = limit }
    }

    /// The indicator windows above the notch, in screen coordinates (origin bottom-left).
    static func indicators(above window: CGWindowID) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], window) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        return list.compactMap { info in
            guard isIndicator(
                owner: info[kCGWindowOwnerName as String] as? String,
                name: info[kCGWindowName as String] as? String,
                layer: info[kCGWindowLayer as String] as? Int
            ),
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds),
                rect.width <= 80, rect.height <= 40
            else { return nil }
            return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    /// The window server's "StatusIndicator", drawn near the top of all window levels. Its
    /// name may be hidden without Screen Recording, so the level is enough.
    nonisolated static func isIndicator(owner: String?, name: String?, layer: Int?) -> Bool {
        guard owner == "Window Server" else { return false }
        if name == "StatusIndicator" { return true }
        return (layer ?? 0) >= Int(Int32.max) - 100
    }
}
