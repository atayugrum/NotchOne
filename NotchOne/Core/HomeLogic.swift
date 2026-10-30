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

enum HomeLogic {
    /// Two rows of three fit every size.
    static let maxCards = 6
    static let columns = 3

    /// Cards to show, in their fixed order: turned on, with something to show, and whose
    /// tab (if any) isn't hidden.
    static func cards(hasContent: Set<HomeCard>, hidden: String, visibleTabs: [NotchTab]) -> [HomeCard] {
        let hiddenSet = Set(hidden.split(separator: ",").compactMap { HomeCard(rawValue: String($0)) })
        let cards = HomeCard.allCases.filter { card in
            hasContent.contains(card) && !hiddenSet.contains(card) && (card.tab.map(visibleTabs.contains) ?? true)
        }
        return Array(cards.prefix(maxCards))
    }

    /// Cards split into rows of at most three; up to three cards use one tall row.
    static func rows(_ cards: [HomeCard]) -> [[HomeCard]] {
        stride(from: 0, to: cards.count, by: columns).map { Array(cards[$0..<min($0 + columns, cards.count)]) }
    }
}
