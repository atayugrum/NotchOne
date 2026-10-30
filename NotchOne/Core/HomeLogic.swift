import CoreGraphics
import Foundation

/// How much the open notch shows.
enum NotchMode: String, CaseIterable, Identifiable, Sendable {
    /// Tab bar and the selected tab.
    case full
    /// One row of glanceable things; click to see everything.
    case compact

    var id: String { rawValue }
    var title: String { self == .full ? String(localized: "Full") : String(localized: "Compact") }
}

/// A card on the Home tab. Each one leads to its tab.
enum HomeCard: String, CaseIterable, Identifiable, Sendable {
    case nowPlaying, weather, battery, activity, devices, system, notes, clipboard, shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: String(localized: "Now Playing")
        case .weather: String(localized: "Weather")
        case .battery: String(localized: "Battery")
        case .activity: String(localized: "Notifications")
        case .devices: String(localized: "Devices")
        case .system: String(localized: "System")
        case .notes: String(localized: "Notes")
        case .clipboard: String(localized: "Clipboard")
        case .shelf: String(localized: "Shelf")
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .weather: "cloud.sun"
        case .battery: "battery.75percent"
        case .activity: "bell"
        case .devices: "airpodspro"
        case .system: "gauge.with.dots.needle.33percent"
        case .notes: "note.text"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.full"
        }
    }

    /// The tab a click on the card opens (Battery and Notifications have none).
    var tab: NotchTab? {
        switch self {
        case .nowPlaying: .nowPlaying
        case .weather: .weather
        case .battery: nil
        case .activity: nil
        case .devices: .system
        case .system: .system
        case .notes: .notes
        case .clipboard: .clipboard
        case .shelf: .shelf
        }
    }
}

/// A card and how many of a row's columns it takes.
struct HomeSlot: Identifiable, Equatable, Sendable {
    let card: HomeCard
    var span: Int
    var id: HomeCard { card }
}

enum HomeLogic {
    /// Two rows of three fit every size.
    static let maxCards = 6
    static let maxRows = 2
    static let columns = 3

    /// All cards in the saved order; cards missing from it go last, so new ones show up.
    static func ordered(_ order: String) -> [HomeCard] {
        var result: [HomeCard] = []
        for name in order.split(separator: ",") {
            if let card = HomeCard(rawValue: String(name)), !result.contains(card) { result.append(card) }
        }
        return result + HomeCard.allCases.filter { !result.contains($0) }
    }

    static func encode(_ cards: [HomeCard]) -> String {
        cards.map(\.rawValue).joined(separator: ",")
    }

    /// Cards to show, in the saved order: turned on, with something to show, and whose
    /// tab (if any) isn't hidden.
    static func cards(hasContent: Set<HomeCard>, hidden: String, visibleTabs: [NotchTab], order: String = "") -> [HomeCard] {
        let hiddenSet = Set(hidden.split(separator: ",").compactMap { HomeCard(rawValue: String($0)) })
        let cards = ordered(order).filter { card in
            hasContent.contains(card) && !hiddenSet.contains(card) && (card.tab.map(visibleTabs.contains) ?? true)
        }
        return Array(cards.prefix(maxCards))
    }

    /// Cards laid out on rows of three columns; a wide card takes two. The last card in a
    /// row takes what's left, and cards past the last row don't show.
    static func rows(_ cards: [HomeCard], wide: String = "") -> [[HomeSlot]] {
        var rows: [[HomeSlot]] = []
        var row: [HomeSlot] = []
        var used = 0

        func finish() {
            guard !row.isEmpty else { return }
            row[row.count - 1].span += columns - used
            rows.append(row)
            row = []
            used = 0
        }

        for card in cards {
            let span = LayoutLogic.contains(card.rawValue, in: wide) ? 2 : 1
            if used + span > columns { finish() }
            row.append(HomeSlot(card: card, span: span))
            used += span
        }
        finish()
        return Array(rows.prefix(maxRows))
    }
}
