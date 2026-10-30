import AppKit

/// Borderless, transparent, non-activating panel that sits above the menu bar
/// on every Space, including over full-screen apps.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = SystemPromptWatcher.normalLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    /// True only while the search palette is open: then the panel takes typing.
    /// Otherwise it never takes keyboard focus from the app you're working in.
    var allowsKey = false
    /// Called when the panel loses keyboard focus (a click elsewhere).
    var onResignKey: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override var canBecomeKey: Bool { allowsKey }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
    override var canBecomeMain: Bool { false }
}
