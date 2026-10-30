import AppKit
import SwiftUI

/// Experimental lock screen widget: while the Mac is locked, a small Now Playing and
/// battery card sits under the notch. Off by default (Settings → General). The private space
/// is made once, because macOS may not accept a new one after the screen has locked; the
/// window only exists while the Mac is locked.
@MainActor
final class LockScreenController {
    private let activity: ActivityState
    private var observers: [NSObjectProtocol] = []
    private var panel: NSPanel?
    private var space: SkyLightSpace?
    private var screenObserver: NSObjectProtocol?
    private var repositionTask: Task<Void, Never>?
    /// How far down the screen the card starts.
    private nonisolated static let topFraction: CGFloat = 0.34
    private nonisolated static let cardSize = CGSize(width: 360, height: 92)
    private static let settleDelays: [Duration] = [.milliseconds(500), .seconds(2)]

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard observers.isEmpty, let space = SkyLightSpace.make() else { return }
        self.space = space
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlocked() }
        })
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
        unlocked()
        space?.destroy()
        space = nil
    }

    private func locked() {
        guard panel == nil, let space, let frame = Self.cardFrame() else { return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: LockScreenWidget(activity: activity))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        space.add(panel)
        self.panel = panel

        // macOS can rearrange displays around the lock, so the card is placed again afterwards.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        repositionTask = Task { [weak self] in
            for delay in Self.settleDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.reposition()
            }
        }
    }

    private func reposition() {
        guard let panel, let frame = Self.cardFrame(), frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Centred on the screen with the notch, below the clock.
    private static func cardFrame() -> CGRect? {
        guard let screen = NSScreen.screens.first(where: \.hasHardwareNotch) ?? NSScreen.main else { return nil }
        return cardFrame(screen: screen.frame, notchRect: screen.notchMetrics.notchRect)
    }

    nonisolated static func cardFrame(screen: CGRect, notchRect: CGRect) -> CGRect {
        CGRect(
            x: notchRect.midX - cardSize.width / 2,
            y: screen.maxY - screen.height * topFraction - cardSize.height,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private func unlocked() {
        repositionTask?.cancel()
        repositionTask = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

/// The card shown on the lock screen.
private struct LockScreenWidget: View {
    let activity: ActivityState

    var body: some View {
        HStack(spacing: Space.m) {
            if let info = activity.nowPlaying {
                ArtworkView(image: activity.artwork, size: 56, cornerRadius: Radius.s + 2, glow: activity.accent?.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(Typo.title).lineLimit(1)
                    Text(info.artist.isEmpty ? (AppInfo.name(for: info.appBundleID) ?? "") : info.artist)
                        .font(Typo.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                IconButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 16, frame: 32, label: info.isPlaying ? "Pause" : "Play") {
                    activity.player?.perform(.playPause)
                }
            } else {
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary)
                Text("Nothing playing").font(Typo.body).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if let battery = activity.battery {
                BatteryBadge(status: battery)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
