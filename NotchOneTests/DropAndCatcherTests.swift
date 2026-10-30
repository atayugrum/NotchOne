import AppKit
import PDFKit
import Testing
@testable import NotchOne

struct DropLogicTests {
    let folder = URL(fileURLWithPath: "/tmp/x")

    @Test func classifiesDrags() {
        #expect(DropKind.classify([folder.appending(path: "a.PNG"), folder.appending(path: "b.heic")]) == .image)
        #expect(DropKind.classify([folder.appending(path: "a.pdf")]) == .pdf)
        #expect(DropKind.classify([folder.appending(path: "a.pdf"), folder.appending(path: "b.png")]) == .other)
        #expect(DropKind.classify([folder.appending(path: "notes.txt")]) == .other)
        #expect(DropKind.classify([]) == .other)
    }

    @Test func zonesDependOnKind() {
        #expect(DropAction.actions(for: .image, count: 1).contains(.removeBackground))
        #expect(!DropAction.actions(for: .pdf, count: 1).contains(.merge))
        #expect(DropAction.actions(for: .pdf, count: 2).contains(.merge))
        #expect(DropAction.actions(for: .other, count: 3) == [.shelf, .airDrop, .copyPath])
        for kind in [DropKind.image, .pdf, .other] {
            #expect(Array(DropAction.actions(for: kind, count: 2).prefix(2)) == [.shelf, .airDrop])
        }
    }

    @Test func outputIsNamedNextToOriginalAndNumbered() {
        let source = URL(fileURLWithPath: "/Users/me/Desktop/cat.jpg")
        let downloads = URL(fileURLWithPath: "/Users/me/Downloads")
        let taken: Set<String> = ["/Users/me/Desktop/cat-nobg.png", "/Users/me/Desktop/cat-nobg 2.png"]
        let url = OutputNaming.url(
            for: source, suffix: "nobg", ext: "png", fallbackFolder: downloads,
            isWritable: { _ in true }, exists: { taken.contains($0.path) }
        )
        #expect(url.path == "/Users/me/Desktop/cat-nobg 3.png")

        let fallback = OutputNaming.url(
            for: source, suffix: "small", ext: "jpg", fallbackFolder: downloads,
            isWritable: { _ in false }, exists: { _ in false }
        )
        #expect(fallback.path == "/Users/me/Downloads/cat-small.jpg")
    }
}

/// Runs the real ImageIO and PDFKit code on generated files.
struct FileToolsTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notchone-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(to url: URL, size: Int) throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size / 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: size, height: size / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    @Test func compressScalesDownToJPEG() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "big.png")
        try writePNG(to: source, size: 4000)
        let target = folder.appending(path: "big-small.jpg")
        try ImageTools.compress(source, to: target)
        let image = try #require(NSImageRep(contentsOf: target))
        #expect(image.pixelsWide == 2560)
        #expect(image.pixelsHigh == 1280)
    }

    @Test func convertKeepsSize() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "a.png")
        try writePNG(to: source, size: 300)
        let target = folder.appending(path: "a.jpg")
        try ImageTools.convert(source, to: target)
        let image = try #require(NSImageRep(contentsOf: target))
        #expect(image.pixelsWide == 300)
        #expect(Array(try Data(contentsOf: target).prefix(3)) == [0xFF, 0xD8, 0xFF])   // JPEG magic
    }

    @Test func mergeAppendsPages() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var sources: [URL] = []
        for (index, pages) in [2, 3].enumerated() {
            let document = PDFDocument()
            for page in 0..<pages {
                let image = try #require(NSImage(size: NSSize(width: 100, height: 100), flipped: false) { _ in
                    NSColor(white: CGFloat(page) / 4, alpha: 1).setFill()
                    NSRect(x: 0, y: 0, width: 100, height: 100).fill()
                    return true
                } as NSImage?)
                document.insert(try #require(PDFPage(image: image)), at: document.pageCount)
            }
            let url = folder.appending(path: "\(index).pdf")
            #expect(document.write(to: url))
            sources.append(url)
        }
        let merged = folder.appending(path: "merged.pdf")
        try PDFTools.merge(sources, to: merged)
        #expect(PDFDocument(url: merged)?.pageCount == 5)

        let small = folder.appending(path: "small.pdf")
        try PDFTools.compress(merged, to: small)
        #expect(PDFDocument(url: small)?.pageCount == 5)
    }

    @Test func unreadableInputThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
        #expect(throws: FileToolError.self) {
            try ImageTools.compress(missing, to: URL(fileURLWithPath: "/tmp/never.jpg"))
        }
    }
}

struct FileCatchLogicTests {
    @Test func skipsHiddenAndPartialFiles() {
        #expect(FileCatchLogic.isCandidate(name: "report.pdf"))
        #expect(!FileCatchLogic.isCandidate(name: ".Screenshot 2026.png"))
        #expect(!FileCatchLogic.isCandidate(name: "movie.mp4.crdownload"))
        #expect(!FileCatchLogic.isCandidate(name: "file.zip.download"))
        #expect(FileCatchLogic.newNames(previous: ["a.png"], current: ["a.png", "b.png", ".c.png"]) == ["b.png"])
    }

    @Test func screenshotsAreImagesOrMovies() {
        #expect(FileCatchLogic.isScreenshot(name: "Ekran Resmi 2026-10-29 15.00.00.png"))
        #expect(FileCatchLogic.isScreenshot(name: "Recording.mov"))
        #expect(!FileCatchLogic.isScreenshot(name: "notes.txt"))
    }

    @Test func screenshotFolderSetting() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(FileCatchLogic.screenshotFolder(setting: nil, home: home).path == "/Users/me/Desktop")
        #expect(FileCatchLogic.screenshotFolder(setting: "/Volumes/Shots", home: home).path == "/Volumes/Shots")
    }
}

struct SmartTextTests {
    @Test func colors() {
        #expect(SmartText.classify("#fff") == .color(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(SmartText.classify(" #FF000080 ") == .color(red: 1, green: 0, blue: 0, alpha: 128.0 / 255))
        #expect(SmartText.classify("rgb(0, 255, 0)") == .color(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(SmartText.classify("rgba(0 0 255 / 50%)") == .color(red: 0, green: 0, blue: 1, alpha: 0.5))
        #expect(SmartText.color("#ggg") == nil)
        #expect(SmartText.color("rgb(300, 0, 0)") == nil)
        #expect(SmartText.color("fff") == nil)
    }

    @Test func links() {
        #expect(SmartText.classify("https://www.apple.com/macos/") == .link(host: "apple.com", path: "/macos/"))
        #expect(SmartText.classify("http://example.com") == .link(host: "example.com", path: ""))
        #expect(SmartText.link("ftp://x.com") == nil)
        #expect(SmartText.link("see https://x.com") == nil)
    }

    @Test func json() {
        guard case .json(let pretty) = SmartText.classify(#"{"b":1,"a":[true]}"#) else {
            Issue.record("not JSON")
            return
        }
        #expect(pretty.contains("\n"))
        #expect(SmartText.json("{not json") == nil)
    }

    @Test func codeAndPlainText() {
        #expect(SmartText.classify("func hello() {\n    print(1)\n}") == .code)
        #expect(SmartText.classify("const a = 1;\nconst b = 2;") == .code)
        #expect(SmartText.classify("Meet at five tomorrow, bring the slides.") == .plain(words: 7))
        #expect(SmartText.classify("Dear team,\nThanks for today.\nSee you soon.") == .plain(words: 8))
    }

    @Test func itemComputesItOnce() {
        let item = ClipboardItem(content: .text("#000"), sourceBundleID: nil, copiedAt: Date())
        #expect(item.smart == .color(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(ClipboardItem(content: .files([]), sourceBundleID: nil, copiedAt: Date()).smart == nil)
    }
}

struct ConvertFormatTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test func anImageIsNotOfferedItsOwnFormat() {
        let options = ConvertFormat.options(for: [url("a.jpeg")])
        #expect(!options.contains(.jpeg))
        #expect(options.contains(.png))
        #expect(options.contains(.heic))
        #expect(options.contains(.pdf))
    }

    @Test func mixedImagesCanBecomeEitherFormat() {
        let options = ConvertFormat.options(for: [url("a.png"), url("b.jpg")])
        #expect(options.contains(.png))
        #expect(options.contains(.jpeg))
    }

    @Test func aPDFBecomesImages() {
        #expect(ConvertFormat.options(for: [url("a.pdf")]) == [.png, .jpeg, .tiff])
        #expect(DropAction.actions(for: .pdf, count: 1).contains(.convert))
    }

    @Test func otherFilesHaveNoFormats() {
        #expect(ConvertFormat.options(for: [url("a.zip")]).isEmpty)
    }

    @Test func everyImageFormatIsWritten() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "source.png")
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: source)
        for format in ConvertFormat.allCases {
            let target = dir.appending(path: "out").appendingPathExtension(format.fileExtension)
            try ImageTools.convert(source, to: target)
            #expect(FileManager.default.fileExists(atPath: target.path), "\(format.title)")
        }
    }

    @Test func aPDFPageBecomesAnImage() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let page = try #require(PDFPage(image: NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in true }))
        let target = dir.appending(path: "page.png")
        try PDFTools.render(page, to: target)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
}
