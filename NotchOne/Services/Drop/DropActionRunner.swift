import AppKit

/// Runs a drop zone's action. File work happens off the main thread; progress and the
/// result show as a live activity, and new files land on the shelf.
@MainActor
final class DropActionRunner {
    private let shelf: ShelfStore
    private let live: LiveActivityStore

    init(shelf: ShelfStore, live: LiveActivityStore) {
        self.shelf = shelf
        self.live = live
    }

    func perform(_ action: DropAction, on urls: [URL]) {
        let urls = urls.filter(\.isFileURL)
        guard !urls.isEmpty else { return }
        switch action {
        case .shelf:
            shelf.add(urls)
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                live.handle(.say(text: String(localized: "AirDrop isn't available")))
                return
            }
            service.perform(withItems: urls)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            live.handle(.say(text: urls.count == 1 ? String(localized: "Path copied") : String(localized: "\(urls.count) paths copied")))
        case .removeBackground:
            run(String(localized: "Removing background"), done: String(localized: "Background removed"), urls: urls) { source, fallback in
                let target = OutputNaming.url(for: source, suffix: "nobg", ext: "png", fallbackFolder: fallback)
                try ImageTools.removeBackground(from: source, to: target)
                return target
            }
        case .compress:
            run(String(localized: "Compressing"), done: String(localized: "Compressed"), urls: urls) { source, fallback in
                let isPDF = source.pathExtension.lowercased() == "pdf"
                let target = OutputNaming.url(for: source, suffix: "small", ext: isPDF ? "pdf" : "jpg", fallbackFolder: fallback)
                if isPDF {
                    try PDFTools.compress(source, to: target)
                } else {
                    try ImageTools.compress(source, to: target)
                }
                return target
            }
        case .convert:
            run(String(localized: "Converting"), done: String(localized: "Converted"), urls: urls) { source, fallback in
                let ext = OutputNaming.convertExtension(for: source)
                let target = OutputNaming.url(for: source, suffix: "", ext: ext, fallbackFolder: fallback)
                try ImageTools.convert(source, to: target)
                return target
            }
        case .merge:
            runOnce(String(localized: "Merging PDFs"), done: String(localized: "PDFs merged"), urls: urls) { sources, fallback in
                let target = OutputNaming.url(for: sources[0], suffix: "merged", ext: "pdf", fallbackFolder: fallback)
                try PDFTools.merge(sources, to: target)
                return target
            }
        }
    }

    /// Applies `work` to each file in turn.
    private func run(
        _ label: String,
        done: String,
        urls: [URL],
        work: @escaping @Sendable (URL, URL) throws -> URL
    ) {
        runOnce(label, done: done, urls: urls, work: { sources, fallback in
            try work(sources[0], fallback)
        }, collectAll: true)
    }

    private func runOnce(
        _ label: String,
        done: String,
        urls: [URL],
        work: @escaping @Sendable ([URL], URL) throws -> URL,
        collectAll: Bool = false
    ) {
        let id = "drop-\(UUID().uuidString.prefix(8))"
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let started = Date()
        live.handle(.progress(id: id, label: label, fraction: nil))
        shelf.addPending(PendingShelfItem(id: id, title: label, source: urls[0]))

        Task {
            let result: Result<[URL], Error> = await Task.detached(priority: .userInitiated) {
                do {
                    if collectAll {
                        // Each file separately, so one failure doesn't lose the others.
                        var outputs: [URL] = []
                        var lastError: Error?
                        for source in urls {
                            do { outputs.append(try work([source], fallback)) } catch { lastError = error }
                        }
                        if outputs.isEmpty, let lastError { throw lastError }
                        return .success(outputs)
                    }
                    return .success([try work(urls, fallback)])
                } catch {
                    return .failure(error)
                }
            }.value

            let seconds = Date().timeIntervalSince(started)
            shelf.finishPending(id)
            switch result {
            case .success(let outputs):
                shelf.add(outputs)
                live.handle(.finish(id: id, label: Self.summary(done, inputs: urls, outputs: outputs), success: true, seconds: seconds))
            case .failure(let error):
                live.handle(.finish(id: id, label: "\(label): \(error.localizedDescription)", success: false, seconds: seconds))
            }
        }
    }

    /// "Compressed 4.2 MB → 1.1 MB" for a single file, otherwise just the action.
    private static func summary(_ done: String, inputs: [URL], outputs: [URL]) -> String {
        guard inputs.count == 1, outputs.count == 1,
              let before = size(of: inputs[0]), let after = size(of: outputs[0])
        else { return done }
        return "\(done) \(OutputNaming.sizeText(before)) → \(OutputNaming.sizeText(after))"
    }

    private static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}
