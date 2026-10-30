import Foundation
import UniformTypeIdentifiers

/// What's being dragged, which decides the drop zones.
enum DropKind: Equatable, Sendable {
    case image
    case pdf
    case other

    /// "photo.png", "3 images", "2 PDFs", "4 files".
    static func summary(_ urls: [URL]) -> String {
        guard urls.count != 1 else { return urls.first?.lastPathComponent ?? "" }
        switch classify(urls) {
        case .image: return "\(urls.count) images"
        case .pdf: return "\(urls.count) PDFs"
        case .other: return "\(urls.count) files"
        }
    }

    static func classify(_ urls: [URL]) -> DropKind {
        let types = urls.map { UTType(filenameExtension: $0.pathExtension) }
        guard !types.isEmpty else { return .other }
        if types.allSatisfy({ $0?.conforms(to: .pdf) == true }) { return .pdf }
        if types.allSatisfy({ $0?.conforms(to: .image) == true && $0?.conforms(to: .pdf) == false }) { return .image }
        return .other
    }
}

/// One drop zone.
enum DropAction: String, CaseIterable, Identifiable, Sendable {
    case shelf
    case airDrop
    case removeBackground
    case compress
    case convert
    case merge
    case copyPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: String(localized: "Shelf")
        case .airDrop: String(localized: "AirDrop")
        case .removeBackground: String(localized: "Remove background")
        case .compress: String(localized: "Compress")
        case .convert: String(localized: "Convert")
        case .merge: String(localized: "Merge")
        case .copyPath: String(localized: "Copy path")
        }
    }

    var symbol: String {
        switch self {
        case .shelf: "tray.and.arrow.down"
        case .airDrop: "airplayaudio"
        case .removeBackground: "person.crop.rectangle"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .convert: "arrow.triangle.2.circlepath"
        case .merge: "doc.on.doc"
        case .copyPath: "link"
        }
    }

    /// What the action produces, shown under its title.
    func subtitle(kind: DropKind, urls: [URL]) -> String {
        switch self {
        case .shelf: String(localized: "Keep it handy")
        case .airDrop: String(localized: "Send nearby")
        case .removeBackground: String(localized: "Transparent PNG")
        case .compress: kind == .pdf ? String(localized: "Smaller PDF") : String(localized: "Smaller JPEG")
        case .convert: urls.allSatisfy { OutputNaming.convertExtension(for: $0) == "jpg" } ? String(localized: "To JPEG") : String(localized: "To PNG")
        case .merge: String(localized: "Into one PDF")
        case .copyPath: urls.count == 1 ? String(localized: "To clipboard") : String(localized: "\(urls.count) paths")
        }
    }

    /// Shelf and AirDrop sit in a small column; the rest are the main tiles.
    var isBasic: Bool { self == .shelf || self == .airDrop }

    /// Zones for a drag, in display order.
    static func actions(for kind: DropKind, count: Int) -> [DropAction] {
        switch kind {
        case .image: [.shelf, .airDrop, .removeBackground, .compress, .convert]
        case .pdf: count > 1 ? [.shelf, .airDrop, .compress, .merge] : [.shelf, .airDrop, .compress]
        case .other: [.shelf, .airDrop, .copyPath]
        }
    }
}

/// Where results are saved: next to the original as `name-suffix.ext`, numbered if that
/// name is taken, and in Downloads when the original's folder can't be written.
enum OutputNaming {
    static func url(
        for source: URL,
        suffix: String,
        ext: String,
        fallbackFolder: URL,
        isWritable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) },
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let sourceFolder = source.deletingLastPathComponent()
        let folder = isWritable(sourceFolder) ? sourceFolder : fallbackFolder
        let base = source.deletingPathExtension().lastPathComponent + (suffix.isEmpty ? "" : "-" + suffix)
        var candidate = folder.appending(path: base).appendingPathExtension(ext)
        var number = 2
        while exists(candidate), number < 1000 {
            candidate = folder.appending(path: "\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    /// Convert target: PNG for anything that isn't PNG, JPEG for PNGs.
    static func convertExtension(for source: URL) -> String {
        source.pathExtension.lowercased() == "png" ? "jpg" : "png"
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
