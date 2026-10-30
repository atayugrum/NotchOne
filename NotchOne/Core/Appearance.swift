import CoreGraphics
import Foundation

/// Look of the open notch.
enum NotchStyle: String, CaseIterable, Identifiable, Sendable {
    /// Black neck that fades into a Liquid Glass body.
    case glass
    /// Solid black, like v1.
    case classic

    var id: String { rawValue }
    var title: String { self == .glass ? String(localized: "Glass") : String(localized: "Classic black") }
}

/// Outline used on displays without a hardware notch. A real notch always uses `.notch`.
enum NotchOutline: String, CaseIterable, Identifiable, Sendable {
    case notch
    case pill

    var id: String { rawValue }
    var title: String { self == .notch ? String(localized: "Notch") : String(localized: "Pill") }
}

/// Size of the open notch.
enum PanelSize: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular
    case large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .regular: String(localized: "Regular")
        case .large: String(localized: "Large")
        }
    }

    var openSize: CGSize {
        switch self {
        case .compact: CGSize(width: 580, height: 176)
        case .regular: CGSize(width: 640, height: 190)
        case .large: CGSize(width: 720, height: 210)
        }
    }
}

/// Pure rules behind the appearance settings, kept out of views so they can be tested.
enum AppearanceLogic {
    /// Opacity of the dark tint over the glass. Strength 0 is nearly solid, 1 is the clearest
    /// that still keeps white text readable; the default (0.6) gives about 40%.
    static func glassDarkness(strength: Double) -> Double {
        0.75 - 0.55 * min(1, max(0, strength))
    }

    /// Real notches can't be drawn as a pill: the camera cutout would show.
    static func outline(setting: NotchOutline, hasHardwareNotch: Bool) -> NotchOutline {
        hasHardwareNotch ? .notch : setting
    }

    /// Visible tabs in the saved order. Unknown names are dropped, tabs missing from the
    /// saved order are appended (so new tabs show up; Home goes first), and at least one
    /// tab stays visible.
    static func tabs(order: String, hidden: String) -> [NotchTab] {
        var result: [NotchTab] = []
        for name in order.split(separator: ",") {
            if let tab = NotchTab(rawValue: String(name)), !result.contains(tab) {
                result.append(tab)
            }
        }
        let firstSaved = result.first
        if !result.isEmpty, !result.contains(.home) { result.insert(.home, at: 0) }
        result += NotchTab.allCases.filter { !result.contains($0) }

        // Search is a button now, not a tab you can hide; ⌃⌥K must always find it.
        let hiddenSet = Set(hidden.split(separator: ",").compactMap { NotchTab(rawValue: String($0)) }).subtracting([.search])
        let visible = result.filter { !hiddenSet.contains($0) }
        // At least one tab stays in the tab bar.
        guard !visible.contains(where: \.inTabBar) else { return visible }
        let keep = [firstSaved, result.first(where: \.inTabBar)].compactMap { $0 }.first { $0.inTabBar } ?? .home
        return result.filter { $0 == keep || $0 == .search }
    }

    /// All tabs in the saved order, hidden ones included (for the Settings list).
    static func allTabs(order: String) -> [NotchTab] {
        tabs(order: order, hidden: "")
    }

    /// The hidden list without `tab`, so it shows in the tab bar.
    static func showing(_ tab: NotchTab, hidden: String) -> String {
        hidden.split(separator: ",").filter { $0 != Substring(tab.rawValue) }.joined(separator: ",")
    }

    static func encode(_ tabs: [NotchTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }

    /// Moves `tab` one place up (-1) or down (+1) in `order`.
    static func move(_ tab: NotchTab, by offset: Int, in order: [NotchTab]) -> [NotchTab] {
        guard let index = order.firstIndex(of: tab) else { return order }
        let target = index + offset
        guard order.indices.contains(target) else { return order }
        var copy = order
        copy.swapAt(index, target)
        return copy
    }
}
