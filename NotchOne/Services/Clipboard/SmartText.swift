import Foundation

/// What a copied text looks like, for a richer clipboard card. Pure parsing, on-device.
enum SmartText: Equatable, Sendable {
    /// Components 0…1.
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case link(host: String, path: String)
    /// Pretty-printed preview.
    case json(String)
    case code
    case plain(words: Int)

    /// Longer texts are only counted, never parsed.
    static let maxParsedLength = 20_000

    static func classify(_ text: String) -> SmartText {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40, let color = color(trimmed) { return color }
        if trimmed.count <= 2048, let link = link(trimmed) { return link }
        if trimmed.count <= maxParsedLength, let json = json(trimmed) { return .json(json) }
        if trimmed.count <= maxParsedLength, looksLikeCode(trimmed) { return .code }
        return .plain(words: trimmed.split(whereSeparator: \.isWhitespace).count)
    }

    // MARK: - Colors

    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(…)` / `rgba(…)`, `hsl(…)` / `hsla(…)`.
    static func color(_ text: String) -> SmartText? {
        let lower = text.lowercased()
        if lower.hasPrefix("#") {
            let hex = Array(lower.dropFirst())
            guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
            let expanded = hex.count == 3 ? hex.flatMap { [$0, $0] } : hex
            var values: [Double] = []
            for index in stride(from: 0, to: expanded.count, by: 2) {
                guard let byte = UInt8(String(expanded[index...index + 1]), radix: 16) else { return nil }
                values.append(Double(byte) / 255)
            }
            return .color(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
        }
        for prefix in ["rgba(", "rgb("] where lower.hasPrefix(prefix) && lower.hasSuffix(")") {
            let inner = lower.dropFirst(prefix.count).dropLast()
            let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count == 3 || parts.count == 4 else { return nil }
            let rgb = parts.prefix(3).compactMap(Double.init)
            guard rgb.count == 3, rgb.allSatisfy({ (0...255).contains($0) }) else { return nil }
            guard let alpha = alpha(parts) else { return nil }
            return .color(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: alpha)
        }
        for prefix in ["hsla(", "hsl("] where lower.hasPrefix(prefix) && lower.hasSuffix(")") {
            let inner = lower.dropFirst(prefix.count).dropLast()
            let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count == 3 || parts.count == 4,
                  let hue = Double(parts[0]), (0...360).contains(hue),
                  parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
                  let saturation = Double(parts[1].dropLast()), (0...100).contains(saturation),
                  let lightness = Double(parts[2].dropLast()), (0...100).contains(lightness),
                  let alpha = alpha(parts)
            else { return nil }
            let (red, green, blue) = rgb(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
            return .color(red: red, green: green, blue: blue, alpha: alpha)
        }
        return nil
    }

    /// The fourth part of `rgba(…)` or `hsla(…)`, 1 if there isn't one, nil if it's invalid.
    private static func alpha(_ parts: [String]) -> Double? {
        guard parts.count == 4 else { return 1 }
        guard let value = Double(parts[3].replacingOccurrences(of: "%", with: "")) else { return nil }
        let alpha = parts[3].hasSuffix("%") ? value / 100 : value
        return (0...1).contains(alpha) ? alpha : nil
    }

    private static func rgb(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue.truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) = switch sector {
        case ..<1: (chroma, second, 0)
        case ..<2: (second, chroma, 0)
        case ..<3: (0, chroma, second)
        case ..<4: (0, second, chroma)
        case ..<5: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        return (red + match, green + match, blue + match)
    }

    // MARK: - Links

    static func link(_ text: String) -> SmartText? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        let display = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path() == "/" ? "" : url.path()
        return .link(host: display, path: path)
    }

    // MARK: - JSON

    static func json(_ text: String) -> String? {
        guard let first = text.first, first == "{" || first == "[",
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(decoding: pretty, as: UTF8.self)
    }

    // MARK: - Code

    private static let codeStarts = [
        "func ", "def ", "class ", "struct ", "enum ", "import ", "from ", "const ", "let ", "var ",
        "#include", "package ", "public ", "private ", "fn ", "select ", "if (", "for (", "<?php", "#!/",
    ]

    /// A rough heuristic: code-like first line, or several lines with code punctuation.
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let firstLine = lines.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if codeStarts.contains(where: firstLine.hasPrefix), lines.count >= 1, text.contains(where: { "({=;:".contains($0) }) {
            return true
        }
        guard lines.count >= 2 else { return false }
        let codeLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
                || trimmed.hasSuffix(")") || trimmed.contains(" = ") || trimmed.contains("=>")
                || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") && !trimmed.hasPrefix("# ")
        }
        let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        return Double(codeLines.count) / Double(lines.count) >= 0.5 || (indented.count >= 2 && codeLines.count >= 1)
    }
}
