import AppKit

/// Clipboard history. macOS has no "clipboard changed" notification, so the
/// pasteboard's change counter is checked twice a second (a single integer read).
///
/// History lives in memory only and is gone when the app quits. Copies that apps mark
/// as private, and anything copied from a password manager, are never recorded.
@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private(set) var isRunning = false
    /// Briefly set after an item is copied back, for a checkmark in the UI.
    private(set) var lastCopiedID: UUID?

    @ObservationIgnored private let pasteboard = NSPasteboard.general
    @ObservationIgnored private var lastChangeCount = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var pausedUntil: ContinuousClock.Instant?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Don't record whatever was already on the clipboard before we started.
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        items.removeAll()
    }

    /// Puts an item back on the clipboard (it also moves to the top of the list).
    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        case .files(let urls):
            pasteboard.writeObjects(urls as [NSURL])
        }
        // Our own write shouldn't be recorded as a new copy.
        lastChangeCount = pasteboard.changeCount
        items = ClipboardLogic.insert(
            ClipboardItem(
                id: item.id,
                content: item.content,
                sourceBundleID: item.sourceBundleID,
                copiedAt: Date(),
                smart: item.smart
            ),
            into: items
        )
        showCopied(item.id)
    }

    /// Puts the result of a clipboard action on the clipboard, as a new item at the top.
    func copy(text: String, from sourceBundleID: String?) {
        copy(ClipboardItem(content: .text(text), sourceBundleID: sourceBundleID, copiedAt: Date()))
    }

    /// Ignore clipboard changes for a moment (a simulated ⌘C to read a selection).
    func pause(for duration: Duration) {
        pausedUntil = .now + duration
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Private

    private func check() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        if let pausedUntil, .now < pausedUntil { return }

        let types = pasteboard.types?.map(\.rawValue) ?? []
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardLogic.shouldRecord(types: types, sourceBundleID: source),
              let content = readContent() else { return }

        items = ClipboardLogic.insert(
            ClipboardItem(content: content, sourceBundleID: source, copiedAt: Date()),
            into: items
        )
    }

    /// Files first (Finder also puts their names as text), then images, then text.
    private func readContent() -> ClipboardContent? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        if let data = imageData(), data.count <= ClipboardLogic.maxImageBytes {
            return .image(data)
        }
        if let text = pasteboard.string(forType: .string).flatMap(ClipboardLogic.normalizedText) {
            return .text(text)
        }
        return nil
    }

    private func imageData() -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        // Skip huge images before converting them on the main thread.
        guard let tiff = pasteboard.data(forType: .tiff),
              tiff.count <= ClipboardLogic.maxImageBytes * 4,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Shows the checkmark on an item for a moment.
    func showCopied(_ id: UUID) {
        lastCopiedID = id
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.lastCopiedID = nil
        }
    }
}
