import AppKit
import SwiftUI

/// Tracks what's playing from three sources:
/// - Music and Spotify: their distributed notifications (no polling), with AppleScript
///   for exact position, artwork and controls.
/// - Everything else (browsers, video players): the system-wide Now Playing, read by a
///   small helper in `osascript` and controlled with media keys.
@MainActor
final class NowPlayingService: PlayerControlling {
    private let activity: ActivityState
    private let runner = AppleScriptRunner()
    private var infos: [PlayerApp: NowPlayingInfo] = [:]
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var systemMonitor: SystemNowPlayingMonitor?
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard distributedObservers.isEmpty else { return }

        let distributed = DistributedNotificationCenter.default()
        for app in PlayerApp.scriptable {
            distributedObservers.append(distributed.addObserver(
                forName: app.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] note in
                // Parse here so only a Sendable value crosses into main-actor code.
                let now = Date()
                let userInfo = note.userInfo as? [String: Any] ?? [:]
                let parsed = NowPlayingParser.parse(notification: userInfo, source: app, now: now)
                MainActor.assumeIsolated { self?.handleNotification(parsed, from: app, now: now) }
            })
        }

        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.appTerminated(bundleID: bundleID) }
        })

        activity.player = self
        PlayerApp.scriptable.forEach(refresh)
    }

    func stop() {
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        distributedObservers.removeAll()
        workspaceObservers.removeAll()
        setSystemSourceEnabled(false)
        artworkTask?.cancel()
        infos.removeAll()
        artworkKey = nil
        if activity.player === self { activity.player = nil }
        activity.nowPlaying = nil
        activity.artwork = nil
        activity.automationDenied = nil
        activity.controlsNeedAccessibility = false
    }

    /// Turns the "other apps" source on or off.
    func setSystemSourceEnabled(_ enabled: Bool) {
        if enabled, systemMonitor == nil {
            let monitor = SystemNowPlayingMonitor()
            monitor.onLine = { [weak self] line in self?.handleSystem(line) }
            monitor.start()
            systemMonitor = monitor
        } else if !enabled, let monitor = systemMonitor {
            monitor.stop()
            systemMonitor = nil
            if infos.removeValue(forKey: .system) != nil { publish() }
        }
    }

    // MARK: - PlayerControlling

    func perform(_ command: PlayerCommand) {
        if activity.nowPlaying?.source == .system {
            activity.controlsNeedAccessibility = !MediaKeyPoster.post(command)
            return
        }
        guard let app = activity.nowPlaying?.source ?? PlayerApp.scriptable.first(where: Self.isRunning),
              Self.isRunning(app) else { return }
        // You pressed a control: asking for Automation now is expected.
        PermissionGate.markRequested(.automation)
        Task {
            do {
                try await runner.run(PlayerScripts.command(command, for: app)) { _ in () }
            } catch AppleScriptRunner.ScriptError.notPermitted {
                activity.automationDenied = app
            } catch {
                // The player's own notification keeps state correct either way.
            }
        }
    }

    func refreshPosition() {
        if let app = activity.nowPlaying?.source { refresh(app) }
    }

    // MARK: - Sources

    private func handleNotification(_ parsed: NowPlayingInfo?, from app: PlayerApp, now: Date) {
        guard let parsed else {
            infos[app] = nil
            publish()
            return
        }
        infos[app] = NowPlayingParser.carryPosition(into: parsed, from: infos[app], now: now)
        publish()
        if !app.notificationIncludesPosition { refresh(app) }
    }

    private func handleSystem(_ line: SystemLine) {
        switch line {
        case .unavailable, .nothingPlaying:
            infos[.system] = nil
        case .snapshot(let snapshot):
            let info = SystemNowPlayingParser.info(from: snapshot, now: Date())
            // Music and Spotify already have a richer source (artwork, AppleScript controls).
            let isDuplicate = PlayerApp.scriptable.contains { $0.bundleID == info?.appBundleID }
            infos[.system] = isDuplicate ? nil : info
        }
        publish()
    }

    /// Asks Music or Spotify for its exact state. Never launches a player that isn't running.
    private func refresh(_ app: PlayerApp) {
        guard app != .system else { return }  // The helper reports on its own.
        // AppleScript makes macOS ask for Automation; until it's allowed, the player's own
        // notifications are enough to show what's playing.
        guard PermissionGate.allows(.automation) else { return }
        guard Self.isRunning(app) else {
            if infos.removeValue(forKey: app) != nil { publish() }
            return
        }
        Task {
            do {
                let fields = try await runner.run(PlayerScripts.state(for: app)) {
                    NowPlayingParser.fields(from: $0)
                }
                infos[app] = fields.flatMap { NowPlayingParser.parse(fields: $0, source: app, now: Date()) }
                if activity.automationDenied == app { activity.automationDenied = nil }
                publish()
            } catch AppleScriptRunner.ScriptError.notPermitted {
                activity.automationDenied = app
            } catch {
                // Keep whatever the notification told us.
            }
        }
    }

    private func appTerminated(bundleID: String?) {
        guard let app = PlayerApp.scriptable.first(where: { $0.bundleID == bundleID }) else { return }
        infos[app] = nil
        publish()
    }

    // MARK: - Publishing

    private func publish() {
        let current = NowPlayingParser.select(infos.values)
        if current?.trackKey != activity.nowPlaying?.trackKey || current?.isPlaying != activity.nowPlaying?.isPlaying {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { activity.nowPlaying = current }
        } else {
            activity.nowPlaying = current
        }
        if current?.source != .system { activity.controlsNeedAccessibility = false }
        updateArtwork(for: current)
    }

    private func updateArtwork(for info: NowPlayingInfo?) {
        let key = info?.trackKey
        guard key != artworkKey else { return }
        artworkKey = key
        artworkTask?.cancel()
        activity.artwork = nil
        guard let info, let key else { return }

        // No artwork is available for other apps; show the app's icon instead.
        if info.source == .system {
            activity.artwork = AppInfo.icon(for: info.appBundleID)
            return
        }

        artworkTask = Task {
            let data = await fetchArtwork(for: info.source)
            guard !Task.isCancelled, artworkKey == key, let data, let image = NSImage(data: data) else { return }
            activity.artwork = image
        }
    }

    private func fetchArtwork(for app: PlayerApp) async -> Data? {
        guard Self.isRunning(app), PermissionGate.allows(.automation),
              let script = PlayerScripts.artwork(for: app) else { return nil }
        switch app {
        case .music:
            let data = try? await runner.run(script) { $0.data }
            return data?.isEmpty == false ? data : nil
        case .spotify:
            let link = try? await runner.run(script) { $0.stringValue }
            guard let link = link ?? nil, let url = URL(string: link), url.scheme == "https" else { return nil }
            return try? await URLSession.shared.data(from: url).0
        case .system:
            return nil
        }
    }

    private static func isRunning(_ app: PlayerApp) -> Bool {
        guard app != .system else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }
}
