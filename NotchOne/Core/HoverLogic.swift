import Foundation

enum NotchState: Equatable, Sendable {
    case closed
    case open
}

/// What the hover controller should do after the mouse moved.
enum HoverDecision: Equatable, Sendable {
    /// Start the open delay (if not already pending).
    case scheduleOpen
    /// Start the close delay (if not already pending).
    case scheduleClose
    /// Cancel whatever is pending; the current state is already right.
    case cancelPending
    /// Nothing to change.
    case none
}

/// Pure hover rules, separated from timers and AppKit so they can be tested.
enum HoverLogic {
    /// - Parameter opensOnHover: false in click-to-open mode, where only a click opens.
    static func decide(
        state: NotchState,
        isInside: Bool,
        pending: HoverDecision?,
        opensOnHover: Bool = true
    ) -> HoverDecision {
        switch (state, isInside) {
        case (.closed, true):
            guard opensOnHover else { return pending == nil ? .none : .cancelPending }
            return pending == .scheduleOpen ? .none : .scheduleOpen
        case (.open, false):
            return pending == .scheduleClose ? .none : .scheduleClose
        case (.closed, false), (.open, true):
            return pending == nil ? .none : .cancelPending
        }
    }

    /// An open notch doesn't close while a mouse button is down (a drag in progress).
    static func holdsOpen(state: NotchState, mouseButtonsDown: Bool) -> Bool {
        state == .open && mouseButtonsDown
    }
}
