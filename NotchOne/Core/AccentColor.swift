import AppKit
import SwiftUI

/// Colour taken from album artwork, tuned so it reads clearly on dark glass.
struct AccentColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Neutral graphite, used when there's no artwork or it has no real colour.
    static let graphite = AccentColor(red: 0.42, green: 0.44, blue: 0.48)

    /// Artwork colour → tint. Greys become graphite; everything else gets enough saturation
    /// to read as the album's colour and a brightness that's strong without hurting the text.
    static func tint(fromAverage average: AccentColor) -> AccentColor {
        let ns = NSColor(srgbRed: average.red, green: average.green, blue: average.blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation >= 0.12, brightness >= 0.08 else { return .graphite }

        let tuned = NSColor(
            hue: hue,
            saturation: min(0.95, max(0.6, saturation)),
            brightness: min(0.9, max(0.7, brightness)),
            alpha: 1
        ).usingColorSpace(.sRGB) ?? ns
        return AccentColor(red: tuned.redComponent, green: tuned.greenComponent, blue: tuned.blueComponent)
    }
}

/// Finds the colour an album cover is known for: the most vivid hue that covers a good part of
/// it, rather than the average, which turns most covers into brown or grey.
enum DominantColor {
    private static let hueBuckets = 24
    /// Below this share of vivid pixels the cover counts as having no real colour.
    private static let minimumVividShare = 0.03

    /// `pixels` are sRGB colours from a small copy of the cover.
    static func dominant(in pixels: [AccentColor]) -> AccentColor? {
        guard !pixels.isEmpty else { return nil }
        var weights = [Double](repeating: 0, count: hueBuckets)
        var sums = [AccentColor](repeating: AccentColor(red: 0, green: 0, blue: 0), count: hueBuckets)
        for pixel in pixels {
            let top = max(pixel.red, pixel.green, pixel.blue)
            let low = min(pixel.red, pixel.green, pixel.blue)
            let saturation = top > 0 ? (top - low) / top : 0
            guard saturation > 0.2, top > 0.15 else { continue }
            let weight = saturation * saturation * top
            let bucket = min(Int(hue(of: pixel, top: top, low: low) * Double(hueBuckets)), hueBuckets - 1)
            weights[bucket] += weight
            sums[bucket].red += pixel.red * weight
            sums[bucket].green += pixel.green * weight
            sums[bucket].blue += pixel.blue * weight
        }
        guard let bucket = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[bucket] / Double(pixels.count) >= minimumVividShare
        else { return nil }
        let sum = sums[bucket], weight = weights[bucket]
        return AccentColor(red: sum.red / weight, green: sum.green / weight, blue: sum.blue / weight)
    }

    private static func hue(of pixel: AccentColor, top: Double, low: Double) -> Double {
        let range = top - low
        guard range > 0 else { return 0 }
        let sixth: Double = if top == pixel.red {
            (pixel.green - pixel.blue) / range
        } else if top == pixel.green {
            (pixel.blue - pixel.red) / range + 2
        } else {
            (pixel.red - pixel.green) / range + 4
        }
        return (sixth / 6 + 1).truncatingRemainder(dividingBy: 1)
    }
}

/// The album colour of an image. Runs once per track change.
enum ArtworkColor {
    private static let sampleSize = 32

    static func accent(for image: NSImage?) -> AccentColor? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: sampleSize, height: sampleSize, bitsPerComponent: 8, bytesPerRow: sampleSize * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let pixels = (0..<sampleSize * sampleSize).map { index in
            AccentColor(
                red: Double(bytes[index * 4]) / 255,
                green: Double(bytes[index * 4 + 1]) / 255,
                blue: Double(bytes[index * 4 + 2]) / 255
            )
        }
        guard let dominant = DominantColor.dominant(in: pixels) else { return .graphite }
        return AccentColor.tint(fromAverage: dominant)
    }
}
