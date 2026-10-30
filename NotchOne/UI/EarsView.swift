import SwiftUI

/// Small indicators either side of the closed notch.
struct EarsView: View {
    let content: EarContent
    let activity: ActivityState
    let notchSize: CGSize
    let earWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if case .live(let item) = content, item.source == .notification {
                // Opens downward: nothing beside the notch, everything under it.
                Color.clear.frame(height: notchSize.height)
                NotificationText(item: item)
            } else if let island = EarIsland.make(for: content, devices: activity.devices.devices) {
                Color.clear.frame(height: notchSize.height)
                EarIslandView(island: island)
            } else if case .nowPlaying = content, activity.earPreview, let info = activity.nowPlaying {
                sides
                TrackPreview(info: info, activity: activity)
            } else {
                sides
            }
        }
        .foregroundStyle(.white)
    }

    /// A second activity, small, beside the main one.
    @ViewBuilder
    private var extra: some View {
        switch activity.earExtra {
        case .music:
            ArtworkView(image: activity.artwork, size: 14, cornerRadius: 3)
        case .live(let item):
            Image(systemName: item.symbol)
                .font(Typo.icon(10))
                .foregroundStyle(LiveStyle.tint(for: item))
        case .keepAwake:
            Image(systemName: "cup.and.saucer.fill")
                .font(Typo.icon(10))
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private var sides: some View {
        HStack(spacing: 0) {
            left.frame(width: earWidth, height: notchSize.height)
            Color.clear.frame(width: notchSize.width)
            HStack(spacing: Space.xs) {
                right
                extra
            }
            .frame(width: earWidth, height: notchSize.height)
        }
    }

    @ViewBuilder
    private var left: some View {
        switch content {
        case .nowPlaying:
            ArtworkView(image: activity.artwork, size: 20, cornerRadius: 5)
                .opacity(activity.nowPlaying?.isPlaying == true ? 1 : 0.5)
        case .peek(.newFile(let url, _)):
            FileThumbnail(url: url, image: activity.peekThumbnail)
        case .live(let item):
            LiveLeading(item: item)
        case .keepAwake:
            Image(systemName: "cup.and.saucer.fill")
                .font(Typo.icon(11))
                .foregroundStyle(.secondary)
        case .peek(.volume(let level, let muted)):
            Image(systemName: LevelSymbols.volume(level: level, muted: muted))
                .font(Typo.icon(13))
                .contentTransition(.symbolEffect(.replace))
        case .peek(.keyboardBacklight(let level)):
            Image(systemName: level <= 0 ? "light.min" : "light.max")
                .font(Typo.icon(13))
        case .peek(.brightness(let level)):
            Image(systemName: LevelSymbols.brightness(level: level))
                .font(Typo.icon(13))
                .contentTransition(.symbolEffect(.replace))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var right: some View {
        switch content {
        case .nowPlaying:
            if activity.nowPlaying?.isPlaying == true {
                AudioBarsView(isPlaying: true, tint: activity.accent.map { NSColor($0.color) })
                    .frame(width: 16, height: 14)
            } else {
                Image(systemName: "play.fill")
                    .font(Typo.icon(11))
                    .foregroundStyle(.secondary)
            }
        case .peek(.newFile(let url, let isScreenshot)):
            Text(isScreenshot ? String(localized: "Screenshot") : url.lastPathComponent)
                .font(Typo.captionStrong)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Space.xs)
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help("Drag into another app")
        case .live(let item):
            LiveTrailing(item: item)
        case .peek(.volume(let level, let muted)):
            LevelBar(level: muted ? 0 : level)
        case .peek(.brightness(let level)):
            LevelBar(level: level)
        case .peek(.keyboardBacklight(let level)):
            LevelBar(level: level)
        default:
            EmptyView()
        }
    }
}

/// A mini player below the closed notch while an ear is hovered.
private struct TrackPreview: View {
    let info: NowPlayingInfo
    let activity: ActivityState

    var body: some View {
        HStack(spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title).font(Typo.captionStrong)
                if !info.artist.isEmpty {
                    Text(info.artist).font(Typo.micro).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: Space.xs)
            IconButton(symbol: "backward.fill", size: 10, frame: 24, label: "Previous") {
                activity.player?.perform(.previous)
            }
            IconButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 12, frame: 24,
                       label: info.isPlaying ? "Pause" : "Play") {
                activity.player?.perform(.playPause)
            }
            IconButton(symbol: "forward.fill", size: 10, frame: 24, label: "Next") {
                activity.player?.perform(.next)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: EarLayout.previewDrop)
        .padding(.horizontal, Space.m)
    }
}

/// A short event under the closed notch, in the same rings the System tab's language uses.
private struct EarIslandView: View {
    let island: EarIsland

    private var tint: Color {
        switch island.tint {
        case .neutral: .white
        case .green: .green
        case .red: .red
        case .indigo: .indigo
        }
    }

    var body: some View {
        HStack(spacing: Space.s + 2) {
            Image(systemName: island.symbol)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(island.title)
                    .font(Typo.body)
                    .lineLimit(1)
                if let detail = island.detail {
                    Text(detail)
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            ForEach(island.gauges) { gauge in
                VStack(spacing: 2) {
                    ZStack {
                        ProgressRing(fraction: Double(gauge.value) / 100, tint: gaugeTint(gauge), lineWidth: 2)
                        Text("\(gauge.value)")
                            .font(Typo.number(9, weight: .semibold))
                    }
                    .frame(width: 26, height: 26)
                    Text(gauge.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Space.m + 2)
        .frame(maxWidth: .infinity, maxHeight: EarLayout.islandDrop)
    }

    private func gaugeTint(_ gauge: EarIsland.Gauge) -> Color {
        gauge.value <= DeviceBatteryLogic.lowLevel ? .red : .white
    }
}
