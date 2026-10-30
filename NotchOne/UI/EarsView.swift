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
                TrackPreview(info: info)
            } else {
                sides
            }
        }
        .foregroundStyle(.white)
    }

    private var sides: some View {
        HStack(spacing: 0) {
            left.frame(width: earWidth, height: notchSize.height)
            Color.clear.frame(width: notchSize.width)
            right.frame(width: earWidth, height: notchSize.height)
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

/// The track's name below the closed notch while an ear is hovered.
private struct TrackPreview: View {
    let info: NowPlayingInfo

    var body: some View {
        VStack(spacing: 1) {
            Text(info.title).font(Typo.captionStrong)
            if !info.artist.isEmpty {
                Text(info.artist).font(Typo.micro).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: EarLayout.previewDrop, alignment: .top)
        .padding(.horizontal, Space.m)
    }
}

/// A short event as a card under the closed notch.
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
        HStack(spacing: Space.m) {
            Image(systemName: island.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(island.title)
                    .font(Typo.title)
                    .lineLimit(1)
                if !island.chips.isEmpty {
                    HStack(spacing: Space.xs) {
                        ForEach(island.chips) { chip in
                            HStack(spacing: 3) {
                                Text(chip.label).foregroundStyle(.secondary)
                                Text(chip.value)
                            }
                            .font(Typo.number(10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                    .lineLimit(1)
                } else if let detail = island.detail {
                    Text(detail)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, maxHeight: EarLayout.islandDrop)
    }

    @ViewBuilder
    private var trailing: some View {
        switch island.trailing {
        case .none:
            EmptyView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, .green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, Color(white: 0.35))
        case .text(let text):
            Text(text)
                .font(Typo.number(15))
                .foregroundStyle(island.tint == .neutral ? .white : tint)
        }
    }
}
