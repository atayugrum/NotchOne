import AppKit

/// Invisible window exactly over the notch that accepts file drags.
///
/// The main notch panel ignores mouse events while closed (so the menu bar stays
/// clickable), which also means it can't see a drag arriving. This small window can:
/// when files are dragged over the notch it opens the notch, and a drop here adds the
/// files to the shelf.
final class DropCatcherPanel: NSPanel {
    var onDragEnter: (([URL]) -> Void)? {
        get { catcher.onDragEnter }
        set { catcher.onDragEnter = newValue }
    }

    var onDrop: (([URL]) -> Void)? {
        get { catcher.onDrop }
        set { catcher.onDrop = newValue }
    }

    var onClick: (() -> Void)? {
        get { catcher.onClick }
        set { catcher.onClick = newValue }
    }

    private let catcher = DropCatcherView()

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        // Fully transparent windows are skipped by hit-testing; this is invisible but hittable.
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        contentView = catcher
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DropCatcherView: NSView {
    var onDragEnter: (([URL]) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // This window sits over the notch, so clicks on the middle of it land here.
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        onDragEnter?(urls)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func fileURLs(from info: any NSDraggingInfo) -> [URL] {
        DragPasteboard.fileURLs(info.draggingPasteboard)
    }
}
