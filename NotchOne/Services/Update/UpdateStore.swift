import AppKit
import Security

/// Checks the release feed (at most daily, never when turned off) and installs an update
/// only when the download is signed by NotchOne's Developer ID team.
@MainActor
@Observable
final class UpdateStore {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case installing
        case failed(String)
    }

    private(set) var status: Status = .idle
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Told once per new version, so the notch can mention it.
    @ObservationIgnored var onFound: ((AvailableUpdate) -> Void)?

    /// GitHub's "latest release" API for the repository in Info.plist; nil until one is set.
    let feedURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "NotchOneUpdateFeed") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        .flatMap { $0.scheme == "https" ? $0 : nil }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isEnabled: Bool {
        defaults.bool(forKey: SettingsKey.updateChecksEnabled, default: SettingsDefault.updateChecksEnabled)
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On launch and when the notch opens: checks if a day has passed and it's turned on.
    func checkIfDue(now: Date = Date()) {
        let last = defaults.object(forKey: SettingsKey.updateLastCheck) as? Date
        guard isEnabled, feedURL != nil, task == nil, UpdateLogic.isDue(lastCheck: last, now: now) else { return }
        check()
    }

    func check() {
        guard let feedURL, task == nil else { return }
        status = .checking
        task = Task { [weak self] in
            await self?.fetch(feedURL)
            self?.task = nil
        }
    }

    private func fetch(_ url: URL) async {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // A failing feed is tried again tomorrow, not on every open.
        defaults.set(Date(), forKey: SettingsKey.updateLastCheck)
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, data.count <= UpdateLogic.maxFeedBytes else {
                status = .failed(String(localized: "The update server answered with an error (\(code))."))
                return
            }
            if let update = UpdateLogic.update(fromRelease: data, current: currentVersion) {
                status = .available(update)
                if defaults.string(forKey: SettingsKey.updateAnnounced) != update.version {
                    defaults.set(update.version, forKey: SettingsKey.updateAnnounced)
                    onFound?(update)
                }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(String(localized: "Couldn't check for updates: \(error.localizedDescription)"))
        }
    }

    /// Downloads, checks the signature, swaps the app in place and starts the new one.
    func install(_ update: AvailableUpdate) {
        guard task == nil else { return }
        status = .installing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let app = try await Self.download(update, session: session)
                try Self.verify(app)
                try Self.replace(Bundle.main.bundleURL, with: app)
                AppLanguage.relaunch()
            } catch {
                status = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
            }
            task = nil
        }
    }

    // MARK: - Install steps

    enum UpdateError: Error {
        case download, noApp, signature, cantReplace

        var message: String {
            switch self {
            case .download: String(localized: "The update couldn't be downloaded.")
            case .noApp: String(localized: "The download doesn't contain NotchOne.")
            case .signature: String(localized: "The update isn't signed by NotchOne's developer, so it wasn't installed.")
            case .cantReplace: String(localized: "NotchOne couldn't replace itself. Download the update from the website instead.")
            }
        }
    }

    private nonisolated static func download(_ update: AvailableUpdate, session: URLSession) async throws -> URL {
        let (file, response) = try await session.download(from: update.download)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= UpdateLogic.maxDownloadBytes
        else { throw UpdateError.download }
        return try unpack(movingZip: file)
    }

    /// Unzips into a fresh temporary folder and returns the NotchOne.app inside.
    private nonisolated static func unpack(movingZip file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NotchOne-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appending(path: "update.zip")
        try FileManager.default.moveItem(at: file, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = folder.appending(path: "NotchOne.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else { throw UpdateError.noApp }
        return app
    }

    /// The whole bundle must be intact and signed by our team as our app.
    private nonisolated static func verify(_ app: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(UpdateLogic.requirement as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { throw UpdateError.signature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw UpdateError.signature }
    }

    #if DEBUG
    /// The install steps after the download (unzip, signature check, replace) on a local zip and a
    /// throwaway target, so an update can be tried without a release: `-debugUpdateZip <zip>
    /// -debugUpdateTarget <copy of an app>`. Prints the result.
    nonisolated static func debugInstall(zip: URL, target: URL) {
        do {
            let copy = FileManager.default.temporaryDirectory.appending(path: "debug-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: zip, to: copy)
            let app = try unpack(movingZip: copy)
            try verify(app)
            try replace(target, with: app)
            print("debugUpdate: installed into \(target.path)")
        } catch {
            print("debugUpdate: refused: \((error as? UpdateError)?.message ?? error.localizedDescription)")
        }
    }
    #endif

    private nonisolated static func replace(_ current: URL, with new: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: new)
        } catch {
            throw UpdateError.cantReplace
        }
    }
}
