import Foundation

/// Links the bundled `notch` tool into `~/.local/bin` (no sudo needed).
enum CommandLineTool {
    /// The tool inside the app bundle.
    static var bundledURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/notch")
    }

    static var linkURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/notch")
    }

    /// True when the link exists and points at this app's tool.
    static var isInstalled: Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return false
        }
        return URL(fileURLWithPath: destination).standardizedFileURL == bundledURL.standardizedFileURL
    }

    static func install() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Replace only a previous link, never a real file someone else put there.
        if (try? manager.destinationOfSymbolicLink(atPath: linkURL.path)) != nil {
            try manager.removeItem(at: linkURL)
        }
        try manager.createSymbolicLink(at: linkURL, withDestinationURL: bundledURL)
    }

    /// A link whose app is gone (moved or deleted) is pointed at this copy. A link to another
    /// working copy (say, a debug build) is left alone.
    static func needsRelink(destination: String, destinationExists: Bool) -> Bool {
        destination.hasSuffix(".app/Contents/Helpers/notch") && !destinationExists
    }

    static func relinkIfStale() {
        guard !isInstalled,
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path),
              needsRelink(destination: destination, destinationExists: FileManager.default.fileExists(atPath: destination))
        else { return }
        try? install()
    }

    static func uninstall() throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) != nil else { return }
        try FileManager.default.removeItem(at: linkURL)
    }
}
