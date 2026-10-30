import AppKit

/// Files parked on the notch. Only paths are kept (nothing is copied), and they're
/// saved so the shelf survives a restart. Missing files are dropped on load.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [URL] = []
    /// Results still being made (drop actions), shown as placeholders at the end.
    private(set) var pending: [PendingShelfItem] = []

    @ObservationIgnored private let defaults: UserDefaults
    private static let defaultsKey = "shelfPaths"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        items = ShelfLogic.existing(paths.map { URL(fileURLWithPath: $0) })
    }

    func add(_ urls: [URL]) {
        items = ShelfLogic.merge(items, adding: ShelfLogic.existing(urls))
        save()
    }

    func addPending(_ item: PendingShelfItem) {
        pending.append(item)
    }

    func finishPending(_ id: PendingShelfItem.ID) {
        pending.removeAll { $0.id == id }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var canAirDrop: Bool {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: items)
    }

    func airDropAll() {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else { return }
        service.perform(withItems: items)
    }

    private func save() {
        defaults.set(items.map(\.path), forKey: Self.defaultsKey)
    }
}

/// A shelf placeholder for a file that's still being made.
struct PendingShelfItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: URL
}

/// Pure shelf rules.
enum ShelfLogic {
    static let maxItems = 24

    /// Adds new file URLs after the existing ones, without duplicates, newest kept
    /// when over the limit.
    static func merge(_ existing: [URL], adding new: [URL]) -> [URL] {
        var seen = Set(existing.map(\.standardizedFileURL))
        var result = existing
        for url in new where url.isFileURL {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized).inserted {
                result.append(standardized)
            }
        }
        return Array(result.suffix(maxItems))
    }

    static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }
}
