import Foundation

/// NX_KEYTYPE_* codes carried by system-defined key events.
enum MediaKey: Int, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
    case illuminationToggle = 23
}

struct MediaKeyEvent: Equatable, Sendable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
}

/// Decodes the `data1` field of an `NSEvent` of type `.systemDefined`.
enum MediaKeyParser {
    /// `NX_SYSDEFINED` CGEvent type.
    static let systemDefinedEventType: UInt32 = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    static let auxControlSubtype: Int16 = 8

    static func parse(subtype: Int16, data1: Int) -> MediaKeyEvent? {
        guard subtype == auxControlSubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code), state == 0xA || state == 0xB else { return nil }
        return MediaKeyEvent(key: key, isDown: state == 0xA, isRepeat: flags & 0x1 != 0)
    }
}

/// Volume and brightness stepping, matching the system's 16 steps (64 with ⇧⌥).
enum LevelMath {
    static let coarseStep: Float = 1.0 / 16.0
    static let fineStep: Float = 1.0 / 64.0

    static func step(_ current: Float, up: Bool, fine: Bool) -> Float {
        let step = fine ? fineStep : coarseStep
        let clamped = min(1, max(0, current.isFinite ? current : 0))
        let snapped = (clamped / step).rounded() * step
        let next = up ? snapped + step : snapped - step
        return min(1, max(0, (next * 10_000).rounded() / 10_000))
    }
}

enum LevelSymbols {
    static func volume(level: Float, muted: Bool) -> String {
        if muted || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func brightness(level: Float) -> String {
        level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }
}
