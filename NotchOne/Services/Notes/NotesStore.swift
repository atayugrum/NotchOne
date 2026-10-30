import Foundation

/// The quick note: one scratchpad, saved as plain text in Application Support a moment
/// after you stop typing. It never leaves your Mac.
@MainActor
@Observable
final class NotesStore {
    var text: String {
        didSet { if text != oldValue { scheduleSave() } }
    }
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let maxLength = 100_000

    init(fileURL: URL = NotesStore.defaultURL) {
        self.fileURL = fileURL
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NotchOne/Notes.txt")
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The first line with something on it, for the Home card.
    var firstLine: String? {
        text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    func clear() {
        text = ""
    }

    /// Writes now (quitting, or the tab closing).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write(text)
    }

    private func scheduleSave() {
        if text.count > Self.maxLength { text = String(text.prefix(Self.maxLength)) }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.write(self.text)
        }
    }

    private func write(_ text: String) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // Keeps the text in memory; the next change tries again.
        }
    }
}
