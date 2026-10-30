import AppKit
import SwiftUI

/// Experimental lock screen widget: while the Mac is locked, a small Now Playing and
/// battery card sits under the notch. Off by default (Settings → General). Nothing exists
/// while the Mac is unlocked; the window and its private space are made on lock and
/// destroyed on unlock, so a problem can't outlive one lock.
@MainActor
final class LockScreenController {
    private let activity: ActivityState
    private var observers: [NSObjectProtocol] = []
    private var panel: NSPanel?
    private var space: SkyLightSpace?

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard observers.isEmpty, SkyLightSpace.isAvailable else { return }
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
    }

    private func locked() {
        guard panel == nil, let screen = NSScreen.screens.first else { return }
        let size = CGSize(width: 360, height: 92)
        let notch = screen.notchMetrics.notchRect
        let frame = CGRect(
            x: notch.midX - size.width / 2,
            y: screen.frame.maxY - notch.height - size.height - 60,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: LockScreenWidget(activity: activity))
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()

        guard let space = SkyLightSpace.make() else {
            panel.close()
            return
        }
        space.add(panel)
        self.panel = panel
        self.space = space
    }

    private func unlocked() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        space?.destroy()
        space = nil
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
