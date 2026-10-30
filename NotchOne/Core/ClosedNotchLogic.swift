import CoreGraphics
import Foundation

/// What a click on an ear of the closed notch does.
enum EarClick: String, CaseIterable, Identifiable, Sendable {
    case open
    case openPlayer
    case playPause
    case nextTrack
    case keepAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: String(localized: "Open the notch")
        case .openPlayer: String(localized: "Open the player")
        case .playPause: String(localized: "Play or pause")
        case .nextTrack: String(localized: "Next track")
        case .keepAwake: String(localized: "Keep Awake")
        }
    }
}

/// Which part of the closed notch a click landed on.
enum ClosedNotchSide: Equatable, Sendable {
    case left, center, right
}

enum ClosedNotchClick: Equatable {
    case open
    case activateNotification(LiveActivity)
    case ear(EarClick)
}

/// Pure rules for the closed notch.
enum ClosedNotchLogic {
    /// `x` runs from 0 at the shape's left edge.
    static func side(x: CGFloat, width: CGFloat, notchWidth: CGFloat) -> ClosedNotchSide {
        let ear = (width - notchWidth) / 2
        if x < ear { return .left }
        return x > width - ear ? .right : .center
    }

    static func click(ears: EarContent?, side: ClosedNotchSide, left: EarClick, right: EarClick) -> ClosedNotchClick {
        if case .live(let item) = ears, item.source == .notification, item.appPID != nil {
            return .activateNotification(item)
        }
        if ears == .keepAwake, side != .center { return .ear(.keepAwake) }
        guard case .nowPlaying = ears else { return .open }
        switch side {
        case .left: return .ear(left)
        case .right: return .ear(right)
        case .center: return .open
        }
    }
}
