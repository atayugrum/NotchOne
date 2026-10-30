import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Pure rules for which new files are worth a peek.
enum FileCatchLogic {
    /// Unfinished downloads and temp files.
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]
    /// A file older than this when first seen isn't "new" (e.g. moved in from elsewhere).
    static let maxAge: TimeInterval = 60

    static func isCandidate(name: String) -> Bool {
        guard !name.hasPrefix("."), !name.isEmpty else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return !partialExtensions.contains(ext)
    }

    /// Screenshots and screen recordings are the images/movies in the screenshot folder.
    static func isScreenshot(name: String) -> Bool {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    static func newNames(previous: Set<String>, current: Set<String>) -> [String] {
        current.subtracting(previous).filter(isCandidate).sorted()
    }

    /// The screenshot folder from `com.apple.screencapture`, else the Desktop.
    static func screenshotFolder(setting: String?, home: URL) -> URL {
        guard let setting, !setting.isEmpty else { return home.appending(path: "Desktop") }
        let expanded = (setting as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

/// Watches the screenshot folder and Downloads. A new file shows a thumbnail peek that
/// can be dragged straight into another app.
///
/// Uses a kqueue vnode source per folder (the kernel wakes us on change; no polling).
/// macOS asks once for Desktop/Downloads access.
@MainActor
final class FileCatcher {
    private struct Watch {
        let folder: URL
        let isScreenshots: Bool
        let source: DispatchSourceFileSystemObject
        var names: Set<String>
    }

    private let activity: ActivityState
    private var watches: [Watch] = []
    private var debounce: [URL: Task<Void, Never>] = [:]

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start(screenshots: Bool, downloads: Bool) {
        stop()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let screenshotFolder = FileCatchLogic.screenshotFolder(
            setting: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: home
        )
        let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        if screenshots { watch(screenshotFolder, isScreenshots: true) }
        if downloads, downloadsFolder.standardizedFileURL != screenshotFolder.standardizedFileURL || !screenshots {
            watch(downloadsFolder, isScreenshots: false)
        }
    }

    func stop() {
        watches.forEach { $0.source.cancel() }
        watches.removeAll()
        debounce.values.forEach { $0.cancel() }
        debounce.removeAll()
    }

    var isRunning: Bool { !watches.isEmpty }

    private func watch(_ folder: URL, isScreenshots: Bool) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged(folder) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watches.append(Watch(folder: folder, isScreenshots: isScreenshots, source: source, names: Self.names(in: folder)))
    }

    /// Screenshots are written under a hidden name and then renamed, and downloads
    /// change several times; wait for things to settle before looking.
    private func folderChanged(_ folder: URL) {
        debounce[folder]?.cancel()
        debounce[folder] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.scan(folder)
        }
    }

    private func scan(_ folder: URL) {
        guard let index = watches.firstIndex(where: { $0.folder == folder }) else { return }
        let current = Self.names(in: folder)
        let added = FileCatchLogic.newNames(previous: watches[index].names, current: current)
        watches[index].names = current
        let isScreenshots = watches[index].isScreenshots

        let fresh = added
            .map { folder.appending(path: $0) }
            .filter { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return Date().timeIntervalSince(created) < FileCatchLogic.maxAge
            }
        guard let url = fresh.last else { return }
        let isScreenshot = isScreenshots && FileCatchLogic.isScreenshot(name: url.lastPathComponent)
        guard isScreenshots ? isScreenshot : true else { return }
        Task { await show(url, isScreenshot: isScreenshot) }
    }

    private func show(_ url: URL, isScreenshot: Bool) async {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 44, height: 44),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        activity.showFilePeek(url: url, isScreenshot: isScreenshot, thumbnail: thumbnail?.nsImage)
    }

    private static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }
}
