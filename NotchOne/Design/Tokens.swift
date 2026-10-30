import SwiftUI

/// Spacing scale. Use these instead of literal paddings.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner radii, all drawn with continuous corners.
enum Radius {
    static let s: CGFloat = 8
    static let m: CGFloat = 14
    static let l: CGFloat = 22
    static let xl: CGFloat = 26
}

/// Type ramp. SF Pro for text, SF Pro Rounded for numbers (timers, levels, percentages).
enum Typo {
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .medium)
    static let micro = Font.system(size: 10, weight: .medium)

    /// The main value on a card: a temperature, a percentage.
    static let value = number(18)

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func icon(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// The only springs used in the notch, so everything moves alike.
enum Motion {
    static let open = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let close = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let peekIn = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let peekOut = Animation.spring(response: 0.35, dampingFraction: 0.9)
    static let tab = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let hover = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let quick = Animation.easeOut(duration: 0.15)
}

/// Fixed colours of the notch surfaces.
enum Palette {
    /// Card fill on glass.
    static let card = Color.white.opacity(0.07)
    static let cardHover = Color.white.opacity(0.12)
    /// Solid surface used for Classic and for Reduce Transparency.
    static let solid = Color(white: 0.07)
    static let control = Color.white.opacity(0.1)
    static let track = Color.white.opacity(0.18)
}
