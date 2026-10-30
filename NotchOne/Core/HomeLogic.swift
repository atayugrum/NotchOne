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

/// A layout for Home: rows of boxes. Widths are in sixths of a row.
enum HomeTemplate: String, CaseIterable, Identifiable, Sendable {
    case feature, even, pairs, hero

    var id: String { rawValue }

    var rows: [[Int]] {
        switch self {
        case .feature: [[4, 2], [2, 2, 2]]
        case .even: [[2, 2, 2], [2, 2, 2]]
        case .pairs: [[3, 3], [3, 3]]
        case .hero: [[6], [3, 3]]
        }
    }

    var slotCount: Int { rows.joined().count }

    var title: String {
        switch self {
        case .feature: String(localized: "One big box")
        case .even: String(localized: "Six boxes")
        case .pairs: String(localized: "Four boxes")
        case .hero: String(localized: "Full-width box")
        }
    }
}

enum HomeLogic {
    /// As many boxes as the largest template has; a smaller one uses the first few.
    static let maxSlots = 6
    static let rowUnits = 6
    static let defaultSlots: [HomeCard?] = [.nowPlaying, .weather, .battery, .notes, .clipboard, .shelf]

    /// The saved boxes, always `maxSlots` long; an empty name is an empty box.
    static func slots(_ saved: String) -> [HomeCard?] {
        guard !saved.isEmpty else { return defaultSlots }
        let names = saved.split(separator: ",", omittingEmptySubsequences: false)
        return (0..<maxSlots).map { index in
            index < names.count ? HomeCard(rawValue: String(names[index])) : nil
        }
    }

    static func encode(_ slots: [HomeCard?]) -> String {
        slots.map { $0?.rawValue ?? "" }.joined(separator: ",")
    }

    /// Puts `card` in a box. If it was already in another box the two swap, so a card is
    /// never shown twice.
    static func assign(_ card: HomeCard?, to index: Int, in slots: [HomeCard?]) -> [HomeCard?] {
        guard slots.indices.contains(index) else { return slots }
        var copy = slots
        if let card, let other = slots.firstIndex(of: card) { copy[other] = slots[index] }
        copy[index] = card
        return copy
    }

    /// Width of a box `span` sixths wide, in a row of `count` boxes.
    static func width(span: Int, count: Int, in width: CGFloat, spacing: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(count - 1)) * CGFloat(span) / CGFloat(rowUnits))
    }

    /// The first box of each row, so a row can find its cards.
    static func firstSlot(ofRow row: Int, in template: HomeTemplate) -> Int {
        template.rows.prefix(row).joined().count
    }
}
