import AppKit
import SwiftUI

/// Short-lived event shown in the notch's "ears" for a couple of seconds.
enum Peek: Equatable, Sendable {
    case power(pluggedIn: Bool, percent: Int)
    case lowBattery(percent: Int)
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case keyboardBacklight(level: Float)
    case bluetooth(symbol: String, connected: Bool, battery: Int?)
    /// A Focus was turned on or off.
    case focus(on: Bool)
    /// A new screenshot or download; drag the thumbnail out of the notch.
    case newFile(URL, isScreenshot: Bool)
}

/// What the closed notch shows on its left/right sides.
enum EarContent: Equatable {
    case nowPlaying
    case peek(Peek)
    case live(LiveActivity)
}

enum EarLayout {
    static let nowPlayingWidth: CGFloat = 34
    static let peekWidth: CGFloat = 62
    /// Room for a level bar (volume, brightness).
    static let levelWidth: CGFloat = 76
    /// Room for a project name or "✓ 1m 4s".
    static let liveWidth: CGFloat = 84
    /// Room for a short message or a project name.
    static let liveTextWidth: CGFloat = 150

    /// Narrower than this, an ear can't show anything, so it isn't shown.
    static let minimumWidth: CGFloat = 20
    /// Space kept between an ear and macOS's own indicator.
    static let indicatorGap: CGFloat = 4

    /// The ear width, kept within `limit` (room left before macOS's mic or camera indicator).
    static func width(for content: EarContent?, limit: CGFloat?) -> CGFloat {
        let width = width(for: content)
        guard let limit, limit < width else { return width }
        return limit >= minimumWidth ? limit : 0
    }

    /// How wide an ear can be without covering an indicator next to the notch, or nil when
    /// none is close. `corner` is the notch's flared top corner, outside each ear.
    static func limit(notchRect: CGRect, indicators: [CGRect], corner: CGFloat) -> CGFloat? {
        let room = indicators
            .filter { $0.maxY > notchRect.minY && $0.minY < notchRect.maxY }
            .compactMap { rect -> CGFloat? in
                if rect.minX >= notchRect.maxX { return rect.minX - notchRect.maxX }
                if rect.maxX <= notchRect.minX { return notchRect.minX - rect.maxX }
                return 0
            }
            .min()
        return room.map { max(0, $0 - corner - indicatorGap) }
    }

    static func width(for content: EarContent?) -> CGFloat {
        switch content {
        case nil: 0
        case .nowPlaying: nowPlayingWidth
        case .peek(.volume), .peek(.brightness), .peek(.keyboardBacklight), .peek(.power(pluggedIn: true, _)): levelWidth
        case .peek(.newFile): liveTextWidth
        case .peek: peekWidth
        case .live(let item): item.status == .needsYou || item.status == .info ? liveTextWidth : liveWidth
        }
    }
}

/// Live data from services, shared by every notch view. Services write, views read.
@MainActor
@Observable
final class ActivityState {
    var nowPlaying: NowPlayingInfo?

    /// Brings the playing app forward (opens it if it has quit since).
    func openPlayingApp() {
        guard let id = nowPlaying?.playerBundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    var artwork: NSImage? {
        didSet { if artwork !== oldValue { accent = ArtworkColor.accent(for: artwork) } }
    }
    /// Tint taken from the artwork (album colour), nil without artwork.
    private(set) var accent: AccentColor?
    /// Set when the user denied Automation access for this player.
    var automationDenied: PlayerApp?
    /// Set when a control press for another app failed because Accessibility is off.
    var controlsNeedAccessibility = false
    var battery: BatteryStatus?
    private(set) var peek: Peek?
    /// Thumbnail for a `.newFile` peek.
    private(set) var peekThumbnail: NSImage?

    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let live = LiveActivityStore()
    let weather = WeatherStore()
    let translate = TranslateStore()
    let updates = UpdateStore()
    let devices = DeviceBatteryStore()
    let system = SystemMonitorStore()
    let notes = NotesStore()
    let drops: DropActionRunner
    /// Set by meeting mode while it runs.
    @ObservationIgnored var onToggleMicMute: (() -> Void)?
    /// True while the Mirror tab has the camera on (so it isn't taken for a meeting).
    var isUsingCamera = false
    /// A Focus mode is on (only when the Focus indicator is enabled and allowed).
    var isFocused = false

    @ObservationIgnored weak var player: (any PlayerControlling)?
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    init() {
        drops = DropActionRunner(shelf: shelf, live: live)
        devices.onLow = { [weak self] device in
            self?.live.handle(.say(text: String(localized: "\(device.name) battery is low: \(device.lowest ?? 0)%")))
        }
        updates.onFound = { [weak self] update in
            self?.live.handle(.say(text: String(localized: "NotchOne \(update.version) is available. Settings → About")))
        }
    }

    /// Priority: a peek, then live activities by their priority, with Now Playing at 10
    /// (see `LiveActivity.priority`).
    var ears: EarContent? {
        if let peek { return .peek(peek) }
        let top = live.top
        if let top, top.priority > Self.nowPlayingPriority { return .live(top) }
        if nowPlaying?.isPlaying == true { return .nowPlaying }
        if let top { return .live(top) }
        return nil
    }

    nonisolated static let nowPlayingPriority = 10

    /// Room left before macOS's mic, camera or screen-recording indicator, when it's next to
    /// the notch (see `StatusIndicatorWatcher`).
    var earLimit: CGFloat?

    var earWidth: CGFloat { EarLayout.width(for: ears, limit: earLimit) }

    /// While a new file peeks, hovering doesn't open the notch, so the thumbnail can be dragged.
    var isShowingFilePeek: Bool {
        if case .newFile = peek { return true }
        return false
    }

    static let filePeekSeconds: Double = 6

    func showFilePeek(url: URL, isScreenshot: Bool, thumbnail: NSImage?) {
        peekThumbnail = thumbnail
        showPeek(.newFile(url, isScreenshot: isScreenshot), seconds: Self.filePeekSeconds)
    }

    func showPeek(_ peek: Peek, seconds: Double = 2.5) {
        peekTask?.cancel()
        withAnimation(Motion.peekIn) { self.peek = peek }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.peekOut) { self?.peek = nil }
        }
    }
}
