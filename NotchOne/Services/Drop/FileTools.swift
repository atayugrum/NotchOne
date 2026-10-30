import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum FileToolError: LocalizedError {
    case unreadable
    case noSubject
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Couldn't read the file")
        case .noSubject: String(localized: "No subject found")
        case .writeFailed: String(localized: "Couldn't save the result")
        }
    }
}

/// On-device file conversions. All synchronous; call them off the main thread.
enum ImageTools {
    /// Cuts out the foreground subject(s) with Vision and saves a transparent PNG.
    static func removeBackground(from source: URL, to destination: URL) throws {
        guard let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else {
            throw FileToolError.unreadable
        }
        let handler = VNImageRequestHandler(ciImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw FileToolError.noSubject
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let output = CIImage(cvPixelBuffer: buffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw FileToolError.writeFailed }
        try CIContext().writePNGRepresentation(of: output, to: destination, format: .RGBA8, colorSpace: colorSpace)
    }

    /// Re-encodes as JPEG (quality 0.7), scaled down to at most 2560 px on the long side.
    static func compress(_ source: URL, to destination: URL) throws {
        try write(source, to: destination, type: .jpeg, maxPixels: 2560, quality: 0.7)
    }

    /// Same pixels, in the format of `destination`'s extension.
    static func convert(_ source: URL, to destination: URL) throws {
        if destination.pathExtension.lowercased() == "pdf" {
            guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
                throw FileToolError.unreadable
            }
            let document = PDFDocument()
            document.insert(page, at: 0)
            guard document.write(to: destination) else { throw FileToolError.writeFailed }
            return
        }
        guard let type = UTType(filenameExtension: destination.pathExtension) else { throw FileToolError.writeFailed }
        try write(source, to: destination, type: type, maxPixels: nil, quality: 0.9)
    }

    private static func write(_ source: URL, to destination: URL, type: UTType, maxPixels: Int?, quality: Double) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw FileToolError.unreadable }

        let longSide = max(width, height)
        // A "thumbnail" at full size is the simplest way to get the EXIF rotation applied.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longSide, maxPixels ?? longSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw FileToolError.unreadable }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw FileToolError.writeFailed }
    }
}

enum PDFTools {
    /// Pixels per PDF point: about 200 dpi.
    private static let renderScale: CGFloat = 200.0 / 72.0

    /// Saves one page as an image, in the format of `destination`'s extension.
    static func render(_ page: PDFPage, to destination: URL) throws {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * renderScale), height = Int(bounds.height * renderScale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let type = UTType(filenameExtension: destination.pathExtension),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw FileToolError.writeFailed }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw FileToolError.writeFailed }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw FileToolError.writeFailed }
    }

    /// Re-saves with images as screen-resolution JPEGs.
    static func compress(_ source: URL, to destination: URL) throws {
        guard let document = PDFDocument(url: source) else { throw FileToolError.unreadable }
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true,
        ]
        guard document.write(to: destination, withOptions: options) else { throw FileToolError.writeFailed }
    }

    /// Pages of every PDF, in the order given.
    static func merge(_ sources: [URL], to destination: URL) throws {
        let merged = PDFDocument()
        for source in sources {
            guard let document = PDFDocument(url: source) else { throw FileToolError.unreadable }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        guard merged.write(to: destination) else { throw FileToolError.writeFailed }
    }
}
