import AppKit
import SwiftUI

/// Watches the mouse and opens/closes the notch with small delays.
///
/// Uses global + local mouse-move monitors (no Accessibility permission needed for
/// mouse events). While open it also polls the cursor at 20 Hz, because a
/// non-activating panel does not reliably receive mouse-moved events itself.
@MainActor
final class HoverController {
    private let model: NotchViewModel
    private let hoverRect: @MainActor (NotchState) -> CGRect
    private let onInsideChange: @MainActor (Bool) -> Void
    private let notchRect: @MainActor () -> CGRect?

    private var monitors: [Any] = []
    private var pending: HoverDecision?
    private var pendingTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var lastInside: Bool?
    private var untuckTask: Task<Void, Never>?
    private static let untuckDelay: Duration = .milliseconds(1500)

    init(
        model: NotchViewModel,
        hoverRect: @escaping @MainActor (NotchState) -> CGRect,
        notchRect: @escaping @MainActor () -> CGRect?,
        onInsideChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.notchRect = notchRect
        self.model = model
        self.hoverRect = hoverRect
        self.onInsideChange = onInsideChange
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }) {
            monitors.append(local)
        }
        evaluate()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelPending()
        setPolling(false)
    }

    /// Re-check the cursor against the current hover area.
    func evaluate() {
        #if DEBUG
        // `-debugPinOpen YES` keeps the notch open, for screenshots while developing.
        if UserDefaults.standard.bool(forKey: "debugPinOpen") {
            model.open()
            return
        }
        #endif
        // The notch can also be opened from outside (a file drag), so sync polling here.
        setPolling(model.isOpen)
        updateTuck()
        let inside = hoverRect(model.state).contains(NSEvent.mouseLocation)
        if inside != lastInside {
            lastInside = inside
            onInsideChange(inside)
        }

        // Stay open while a mouse button is held, so dragging a file out of the shelf
        // doesn't close (and cancel) the drag halfway.
        // A notch opened by a hotkey stays until the cursor has visited it and left again.
        if model.isHeld, model.isOpen {
            if inside {
                model.heldWasHovered = true
            } else if model.heldWasHovered {
                model.release()
            }
        }
        let holdOpen = HoverLogic.holdsOpen(state: model.state, mouseButtonsDown: NSEvent.pressedMouseButtons != 0)
            || model.isPinnedOpen

        let opensOnHover = UserDefaults.standard.bool(forKey: SettingsKey.openOnHover, default: SettingsDefault.openOnHover)
            && !model.activity.isShowingFilePeek
        switch HoverLogic.decide(
            state: model.state,
            isInside: inside || holdOpen,
            pending: pending,
            opensOnHover: opensOnHover
        ) {
        case .scheduleOpen:
            schedule(.scheduleOpen, delayMs: Self.delay(SettingsKey.openDelayMs, SettingsDefault.openDelayMs)) {
                $0.model.open()
            }
        case .scheduleClose:
            schedule(.scheduleClose, delayMs: Self.delay(SettingsKey.closeDelayMs, SettingsDefault.closeDelayMs)) {
                $0.model.close()
            }
        case .cancelPending:
            cancelPending()
        case .none:
            break
        }
    }

    /// Ears move out of the way when the pointer heads for the menu bar beside them, and come
    /// back a moment after it leaves, so a menu that's open stays readable.
    private func updateTuck() {
        guard let notchRect = notchRect(), !model.isOpen else { return setTucked(false) }
        let pointer = NSEvent.mouseLocation
        let activity = model.activity
        let near = EarLayout.pointerNearEars(pointer, notchRect: notchRect, earWidth: EarLayout.width(for: activity.ears, limit: activity.earLimit))
        if near || (activity.earsTucked && EarLayout.pointerOnMenuBar(pointer, notchRect: notchRect)) {
            untuckTask?.cancel()
            untuckTask = nil
            setTucked(true)
        } else if activity.earsTucked, untuckTask == nil {
            untuckTask = Task { [weak self] in
                try? await Task.sleep(for: Self.untuckDelay)
                guard !Task.isCancelled else { return }
                self?.untuckTask = nil
                self?.setTucked(false)
            }
        }
    }

    private func setTucked(_ tucked: Bool) {
        guard model.activity.earsTucked != tucked else { return }
        withAnimation(Motion.quick) { model.activity.earsTucked = tucked }
    }

    private func schedule(
        _ decision: HoverDecision,
        delayMs: Double,
        action: @escaping @MainActor (HoverController) -> Void
    ) {
        pendingTask?.cancel()
        pending = decision
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delayMs)))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.pendingTask = nil
            action(self)
            self.setPolling(self.model.isOpen)
            self.evaluate()
        }
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
    }

    private func setPolling(_ enabled: Bool) {
        if enabled, pollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !enabled {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private static func delay(_ key: String, _ fallback: Double) -> Double {
        max(0, UserDefaults.standard.double(forKey: key, default: fallback))
    }
}
