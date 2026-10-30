import Foundation

/// Something a clipboard card can do with its text.
enum ClipboardAction: Equatable, Sendable {
    case cleanLink
    case formatJSON
    case minifyJSON
    case colorHex
    case colorRGB
    case colorHSL
    case translate
    case addToNotes
}

/// Pure rules for clipboard actions: which ones a text gets, and what the text becomes.
enum ClipboardActions {
    /// Tracking parameters removed from any link.
    private static let trackers: Set<String> = [
        "fbclid", "gclid", "gbraid", "wbraid", "dclid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok",
    ]

    /// Sites where `si` is a share tracker; elsewhere it can mean anything.
    private static let shareTrackerHosts = ["youtube.com", "youtu.be", "spotify.com"]

    static func available(for text: String, smart: SmartText) -> [ClipboardAction] {
        let candidates: [ClipboardAction]
        switch smart {
        case .link: candidates = [.cleanLink]
        case .json: candidates = [.formatJSON, .minifyJSON]
        case .color: candidates = [.colorHex, .colorRGB, .colorHSL]
        case .code: candidates = []
        case .plain: return [.translate, .addToNotes]
        }
        return candidates.filter { apply($0, to: text) != nil } + [.addToNotes]
    }

    /// The new text, or nil if the action doesn't change this text. Translate and Add to
    /// Notes hand the text to another store, so they give nil too.
    static func apply(_ action: ClipboardAction, to text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .cleanLink: return cleanLink(trimmed)
        case .formatJSON: return changed(SmartText.json(trimmed), from: trimmed)
        case .minifyJSON: return changed(minifiedJSON(trimmed), from: trimmed)
        case .colorHex: return convertColor(trimmed, unlessPrefix: "#", hex)
        case .colorRGB: return convertColor(trimmed, unlessPrefix: "rgb", rgb)
        case .colorHSL: return convertColor(trimmed, unlessPrefix: "hsl", hsl)
        case .translate, .addToNotes: return nil
        }
    }

    private static func changed(_ result: String?, from text: String) -> String? {
        result == text ? nil : result
    }

    // MARK: - Links

    private static func cleanLink(_ text: String) -> String? {
        guard case .link = SmartText.link(text),
              var components = URLComponents(string: text),
              let query = components.percentEncodedQuery
        else { return nil }
        let host = components.host?.lowercased() ?? ""
        let removesShareTracker = shareTrackerHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        // Filtered as raw text so the parameters that stay keep their exact encoding.
        let kept = query.split(separator: "&").filter { pair in
            let name = pair.prefix { $0 != "=" }.lowercased()
            if name.hasPrefix("utm_") || trackers.contains(name) { return false }
            return !(removesShareTracker && name == "si")
        }
        components.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return changed(components.string, from: text)
    }

    // MARK: - JSON

    private static func minifiedJSON(_ text: String) -> String? {
        guard SmartText.json(text) != nil,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Colours

    private struct RGBA {
        let red, green, blue, alpha: Double
    }

    private static func convertColor(_ text: String, unlessPrefix prefix: String, _ format: (RGBA) -> String) -> String? {
        guard !text.lowercased().hasPrefix(prefix),
              case .color(let red, let green, let blue, let alpha) = SmartText.color(text)
        else { return nil }
        return format(RGBA(red: red, green: green, blue: blue, alpha: alpha))
    }

    private static func byte(_ component: Double) -> Int {
        Int((component * 255).rounded())
    }

    private static func alphaText(_ alpha: Double) -> String {
        "\((alpha * 100).rounded() / 100)"
    }

    private static func hex(_ color: RGBA) -> String {
        let channels = [color.red, color.green, color.blue] + (color.alpha < 1 ? [color.alpha] : [])
        return "#" + channels.map { String(format: "%02X", byte($0)) }.joined()
    }

    private static func rgb(_ color: RGBA) -> String {
        let channels = "\(byte(color.red)), \(byte(color.green)), \(byte(color.blue))"
        return color.alpha < 1 ? "rgba(\(channels), \(alphaText(color.alpha)))" : "rgb(\(channels))"
    }

    private static func hsl(_ color: RGBA) -> String {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let delta = high - low
        let lightness = (high + low) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if delta > 0 {
            switch high {
            case color.red: hue = ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
            case color.green: hue = (color.blue - color.red) / delta + 2
            default: hue = (color.red - color.green) / delta + 4
            }
        }
        let degrees = Int((hue * 60 + 360).rounded()) % 360
        let channels = "\(degrees), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%"
        return color.alpha < 1 ? "hsla(\(channels), \(alphaText(color.alpha)))" : "hsl(\(channels))"
    }
}
