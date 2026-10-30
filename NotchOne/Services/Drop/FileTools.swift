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

    /// Same pixels, different format (PNG ⟷ JPEG).
    static func convert(_ source: URL, to destination: URL) throws {
        let type: UTType = destination.pathExtension.lowercased() == "png" ? .png : .jpeg
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
