import Foundation

/// Something the header can show on its right.
enum HeaderItem: String, CaseIterable, Identifiable, Sendable {
    case focus, keepAwake, weather, battery, clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .keepAwake: String(localized: "Keep Awake")
        case .weather: String(localized: "Weather")
        case .battery: String(localized: "Battery")
        case .clock: String(localized: "Clock")
        }
    }
}

/// Something the compact row can show beside what's playing.
enum CompactItem: String, CaseIterable, Identifiable, Sendable {
    case live, weather, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: String(localized: "Notifications")
        case .weather: String(localized: "Weather")
        case .battery: String(localized: "Battery")
        }
    }
}

/// What wins the closed notch while music plays.
enum EarPriority: String, CaseIterable, Identifiable, Sendable {
    case balanced
    /// Only meetings and failures take over from the music.
    case music

    var id: String { rawValue }
    var title: String { self == .balanced ? String(localized: "Balanced") : String(localized: "Music first") }

    /// True when a live activity of this priority shows instead of the music.
    func beatsMusic(_ priority: Int) -> Bool {
        priority > (self == .music ? Self.musicFirstThreshold : ActivityState.nowPlayingPriority)
    }

    /// A running job's priority: anything above it is urgent.
    private static let musicFirstThreshold = 60
}

/// Pure helpers for the comma-separated lists the layout is saved in.
enum LayoutLogic {
    static func contains(_ name: String, in list: String) -> Bool {
        list.split(separator: ",").contains(Substring(name))
    }

    static func setting(_ name: String, in list: String, to isIn: Bool) -> String {
        var names = Set(list.split(separator: ",").map(String.init))
        if isIn { names.insert(name) } else { names.remove(name) }
        return names.sorted().joined(separator: ",")
    }

    /// `item` moved to just before `target`.
    static func move<T: Equatable>(_ item: T, before target: T, in order: [T]) -> [T] {
        guard item != target, order.contains(item), order.contains(target) else { return order }
        var copy = order.filter { $0 != item }
        copy.insert(item, at: copy.firstIndex(of: target) ?? copy.endIndex)
        return copy
    }
}
