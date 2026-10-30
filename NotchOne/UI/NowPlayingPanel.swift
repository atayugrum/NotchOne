import CoreAudio
import SwiftUI

struct NowPlayingPanel: View {
    let activity: ActivityState
    /// Album tint for the glow behind the artwork, or nil.
    var glow: Color?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) { OutputPicker(activity: activity) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let info = activity.nowPlaying {
                HStack(spacing: Space.l) {
                    ArtworkView(image: activity.artwork, size: 80, cornerRadius: Radius.m, glow: glow)
                        .opensPlayer(activity)
                    VStack(alignment: .leading, spacing: 7) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.title)
                                .font(Typo.title)
                            Text(subtitle(for: info))
                                .font(Typo.caption)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)

                        PlaybackProgress(info: info)
                        PlayerControls(isPlaying: info.isPlaying) { command in
                            activity.player?.perform(command)
                        }
                    }
                }
            } else {
                HStack(spacing: Space.m) {
                    ArtworkView(image: nil, size: 48, cornerRadius: Radius.s + 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing playing")
                            .font(Typo.title)
                        Text("Play something in Music, Spotify or a browser")
                            .font(Typo.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }

            if let denied = activity.automationDenied {
                AutomationHint(app: denied)
            } else if activity.controlsNeedAccessibility, let info = activity.nowPlaying {
                AccessibilityHint(appName: AppInfo.name(for: info.appBundleID) ?? "this app")
            }
        }
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        let parts = [info.artist, info.album].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " — ") }
        // Web video often has no artist or album; show which app is playing instead.
        return AppInfo.name(for: info.appBundleID) ?? ""
    }
}

private struct PlaybackProgress: View {
    let info: NowPlayingInfo

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !info.isPlaying)) { context in
            let position = info.position(at: context.date)
            let fraction = info.duration.map { $0 > 0 ? position / $0 : 0 } ?? 0

            HStack(spacing: 8) {
                Text(TimeFormatting.clock(position))
                ProgressBar(fraction: fraction)
                Text(info.duration.map { "-" + TimeFormatting.clock($0 - position) } ?? "--:--")
            }
            .font(Typo.number(10, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Palette.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
        }
        .frame(height: 4)
    }
}

private struct PlayerControls: View {
    let isPlaying: Bool
    let action: (PlayerCommand) -> Void

    var body: some View {
        HStack(spacing: Space.l) {
            IconButton(symbol: "backward.fill", size: 14, frame: 30, label: "Previous track") { action(.previous) }
            IconButton(
                symbol: isPlaying ? "pause.fill" : "play.fill",
                size: 20,
                frame: 36,
                label: isPlaying ? "Pause" : "Play"
            ) { action(.playPause) }
            IconButton(symbol: "forward.fill", size: 14, frame: 30, label: "Next track") { action(.next) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccessibilityHint: View {
    let appName: String

    var body: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Allow NotchOne in Privacy & Security → Accessibility to control \(appName)", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
    }
}

private struct AutomationHint: View {
    let app: PlayerApp

    var body: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Allow NotchOne to control \(app.displayName) in Privacy & Security → Automation", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
    }
}

extension View {
    /// Clicking the album art opens the app that's playing.
    func opensPlayer(_ activity: ActivityState) -> some View {
        contentShape(Rectangle())
            .onTapGesture { activity.openPlayingApp() }
            .help(Text("Open \(AppInfo.name(for: activity.nowPlaying?.playerBundleID) ?? String(localized: "the player"))"))
            .accessibilityAddTraits(.isButton)
    }
}

/// Picks where sound plays.
struct OutputPicker: View {
    let activity: ActivityState
    @State private var devices: [AudioOutput.Device] = []
    @State private var current: AudioDeviceID?

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    AudioOutput.setDefault(device.id)
                    current = device.id
                    activity.showPeek(.output(name: device.name))
                } label: {
                    if device.id == current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker")
                .font(Typo.icon(12))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sound output")
        .accessibilityLabel("Sound output")
        .onAppear(perform: refresh)
        .onHover { if $0 { refresh() } }
    }

    private func refresh() {
        devices = AudioOutput.devices()
        current = AudioOutput.defaultDevice()
    }
}
