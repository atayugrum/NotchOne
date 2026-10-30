import AppKit
import CoreImage
import SwiftUI

/// Colour taken from album artwork, tuned so it works as a subtle tint on dark glass.
struct AccentColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Neutral graphite, used when there's no artwork or it has no real colour.
    static let graphite = AccentColor(red: 0.42, green: 0.44, blue: 0.48)

    /// Average artwork colour → tint. Greys become graphite; everything else gets enough
    /// saturation to read as a colour and a brightness that's visible but not loud.
    static func tint(fromAverage average: AccentColor) -> AccentColor {
        let ns = NSColor(srgbRed: average.red, green: average.green, blue: average.blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation >= 0.12, brightness >= 0.08 else { return .graphite }

        let tuned = NSColor(
            hue: hue,
            saturation: min(0.85, max(0.45, saturation)),
            brightness: min(0.9, max(0.6, brightness)),
            alpha: 1
        ).usingColorSpace(.sRGB) ?? ns
        return AccentColor(red: tuned.redComponent, green: tuned.greenComponent, blue: tuned.blueComponent)
    }
}

/// Average colour of an image with Core Image. Runs once per track change.
enum ArtworkColor {
    @MainActor private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])

    @MainActor
    static func accent(for image: NSImage?) -> AccentColor? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        let average = AccentColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
        return AccentColor.tint(fromAverage: average)
    }
}
