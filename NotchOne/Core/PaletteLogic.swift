import Foundation

/// One row in the search palette.
struct PaletteResult: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case clipboard(ClipboardItem.ID)
        case shelf(URL)
        case tab(NotchTab)
        case translateClipboard
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let symbol: String

    var id: String {
        switch kind {
        case .clipboard(let id): "clip:\(id)"
        case .shelf(let url): "shelf:\(url.path)"
        case .tab(let tab): "tab:\(tab.rawValue)"
        case .translateClipboard: "translate"
        }
    }
}

/// Pure search rules for the palette, so ranking can be tested.
enum PaletteLogic {
    static let maxResults = 8

    /// 2 = starts with the query (or a word does), 1 = contains it, 0 = no match.
    static func score(_ text: String, query: String) -> Int {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let range = text.range(of: query, options: options) else { return 0 }
        if range.lowerBound == text.startIndex { return 2 }
        let before = text[text.index(before: range.lowerBound)]
        return before.isWhitespace || before.isPunctuation ? 2 : 1
    }

    static func results(
        query: String,
        clipboard: [ClipboardItem],
        shelf: [URL],
        tabs: [NotchTab]
    ) -> [PaletteResult] {
        let query = query.trimmingCharacters(in: .whitespaces)
        var results: [(score: Int, order: Int, result: PaletteResult)] = []
        var order = 0
        func add(_ score: Int, _ result: PaletteResult) {
            guard score > 0 else { return }
            results.append((score, order, result))
            order += 1
        }

        // Empty query: recent clipboard items, so the palette is useful right away.
        let isEmpty = query.isEmpty
        for item in clipboard {
            guard let text = searchableText(item) else { continue }
            add(isEmpty ? 1 : score(text, query: query), PaletteResult(
                kind: .clipboard(item.id),
                title: ClipboardLogic.preview(text, limit: 80),
                subtitle: String(localized: "Clipboard · Return copies it"),
                symbol: "doc.on.clipboard"
            ))
        }
        guard !isEmpty else { return Array(results.prefix(maxResults).map(\.result)) }

        for url in shelf {
            add(score(url.lastPathComponent, query: query), PaletteResult(
                kind: .shelf(url),
                title: url.lastPathComponent,
                subtitle: String(localized: "Shelf · Return opens it"),
                symbol: "doc"
            ))
        }
        for tab in tabs where tab != .search {
            add(score(tab.title, query: query), PaletteResult(
                kind: .tab(tab), title: String(localized: "Show \(tab.title)"), subtitle: String(localized: "Tab"), symbol: tab.symbol
            ))
        }
        let translateTitle = String(localized: "Translate clipboard")
        add(score(translateTitle, query: query), PaletteResult(
            kind: .translateClipboard, title: translateTitle, subtitle: String(localized: "Translate tab"), symbol: "character.bubble"
        ))

        return results
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .prefix(maxResults)
            .map(\.result)
    }

    private static func searchableText(_ item: ClipboardItem) -> String? {
        switch item.content {
        case .text(let text): text
        case .files(let urls): urls.map(\.lastPathComponent).joined(separator: ", ")
        case .image: nil
        }
    }
}
