import AppKit
import SwiftUI

/// What a two-finger swipe on the notch does.
enum SwipeAction: Equatable, Sendable {
    case previousTab
    case nextTab
    case previousTrack
    case nextTrack
    case open
    /// Let the view handle it (horizontal lists in Shelf and Clipboard scroll).
    case none
}

/// Pure swipe rules, so they can be tested.
enum SwipeLogic {
    /// Points of finger travel before a swipe counts.
    static let threshold: CGFloat = 36

    enum Direction: Equatable, Sendable {
        case left, right, up, down
    }

    /// Direction the fingers moved, regardless of the "natural scrolling" setting.
    static func direction(dx: CGFloat, dy: CGFloat, inverted: Bool) -> Direction? {
        // Natural scrolling (inverted) reports deltas that follow the fingers.
        let fingerX = inverted ? dx : -dx
        let fingerY = inverted ? dy : -dy
        if abs(fingerX) >= threshold, abs(fingerX) > abs(fingerY) * 1.5 {
            return fingerX > 0 ? .right : .left
        }
        if abs(fingerY) >= threshold, abs(fingerY) > abs(fingerX) * 1.5 {
            return fingerY > 0 ? .down : .up
        }
        return nil
    }

    /// - Parameters:
    ///   - inHeader: the swipe started on the tab bar row.
    static func action(direction: Direction, isOpen: Bool, tab: NotchTab, inHeader: Bool) -> SwipeAction {
        guard isOpen else { return direction == .down ? .open : .none }
        let horizontal: (SwipeAction, SwipeAction)
        switch (tab, inHeader) {
        case (_, true), (.home, _), (.weather, _), (.system, _), (.mirror, _):
            horizontal = (.previousTab, .nextTab)
        case (.nowPlaying, false):
            horizontal = (.previousTrack, .nextTrack)
        case (.shelf, false), (.clipboard, false), (.search, false), (.translate, false), (.notes, false), (.notifications, false):
            return .none
        }
        switch direction {
        // Fingers moving right reveal what's on the left, like pages.
        case .right: return horizontal.0
        case .left: return horizontal.1
        case .up, .down: return .none
        }
    }

    static func neighbour(of tab: NotchTab, in tabs: [NotchTab], forward: Bool) -> NotchTab? {
        guard let index = tabs.firstIndex(of: tab) else { return tabs.first }
        let next = index + (forward ? 1 : -1)
        return tabs.indices.contains(next) ? tabs[next] : nil
    }
}

/// Watches trackpad scroll gestures over the notch window and turns them into swipes:
/// switch tabs, skip tracks, or open the closed notch with a swipe down.
@MainActor
final class SwipeController {
    private let model: NotchViewModel
    /// The notch panel and the drop catcher over the closed notch.
    private let windows: () -> [NSWindow]
    /// Screen y below which the open notch's header ends.
    private let headerBottom: () -> CGFloat
    private var monitor: Any?
    private var accumulated = CGSize.zero
    private var startedInHeader = false
    private var fired = false

    init(model: NotchViewModel, windows: @escaping () -> [NSWindow], headerBottom: @escaping () -> CGFloat) {
        self.model = model
        self.windows = windows
        self.headerBottom = headerBottom
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event was used as a swipe and shouldn't scroll anything.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window, windows().contains(where: { $0 === window }),
              UserDefaults.standard.bool(forKey: SettingsKey.gesturesEnabled, default: SettingsDefault.gesturesEnabled),
              event.hasPreciseScrollingDeltas,
              event.momentumPhase.isEmpty,
              // Settings scrolls; its swipes aren't tab switches.
              model.settingsPage == nil
        else { return false }

        if event.phase.contains(.began) {
            accumulated = .zero
            fired = false
            startedInHeader = NSEvent.mouseLocation.y >= headerBottom()
        }
        guard !event.phase.contains(.ended), !event.phase.contains(.cancelled) else {
            accumulated = .zero
            return false
        }
        accumulated.width += event.scrollingDeltaX
        accumulated.height += event.scrollingDeltaY
        guard !fired, let direction = SwipeLogic.direction(
            dx: accumulated.width, dy: accumulated.height, inverted: event.isDirectionInvertedFromDevice
        ) else { return false }

        let action = SwipeLogic.action(
            direction: direction, isOpen: model.isOpen, tab: model.selectedTab, inHeader: startedInHeader
        )
        guard action != .none else { return false }
        fired = true
        perform(action)
        return true
    }

    private func perform(_ action: SwipeAction) {
        switch action {
        case .previousTab, .nextTab:
            if let tab = SwipeLogic.neighbour(of: model.selectedTab, in: model.barTabs, forward: action == .nextTab) {
                withAnimation(Motion.tab) { model.selectedTab = tab }
            }
        case .previousTrack:
            model.activity.player?.perform(.previous)
        case .nextTrack:
            model.activity.player?.perform(.next)
        case .open:
            model.open()
        case .none:
            break
        }
    }
}
