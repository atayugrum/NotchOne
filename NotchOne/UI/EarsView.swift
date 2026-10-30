import SwiftUI

/// Small indicators either side of the closed notch.
struct EarsView: View {
    let content: EarContent
    let activity: ActivityState
    let notchSize: CGSize
    let earWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: earWidth, height: notchSize.height)
            Color.clear.frame(width: notchSize.width)
            right.frame(width: earWidth, height: notchSize.height)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var left: some View {
        switch content {
        case .nowPlaying:
            ArtworkView(image: activity.artwork, size: 20, cornerRadius: 5)
        case .peek(.newFile(let url, _)):
            FileThumbnail(url: url, image: activity.peekThumbnail)
        case .live(let item):
            LiveLeading(item: item)
        case .peek(.power(let pluggedIn, _)):
            if pluggedIn {
                ChargingBolt()
            } else {
                Image(systemName: "powerplug")
                    .font(Typo.icon(13))
            }
        case .peek(.lowBattery):
            Image(systemName: "battery.25percent")
                .font(Typo.icon(14))
                .foregroundStyle(.red)
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
        case .peek(.bluetooth(let symbol, let connected, _)):
            Image(systemName: symbol)
                .font(Typo.icon(13))
                .foregroundStyle(connected ? .white : .secondary)
        case .peek(.focus(let on)):
            Image(systemName: on ? "moon.fill" : "moon")
                .font(Typo.icon(13))
                .foregroundStyle(on ? .indigo : .secondary)
        }
    }

    @ViewBuilder
    private var right: some View {
        switch content {
        case .nowPlaying:
            AudioBarsView(isPlaying: activity.nowPlaying?.isPlaying == true)
                .frame(width: 16, height: 14)
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
        case .peek(.power(let pluggedIn, let percent)):
            if pluggedIn {
                ChargingLevel(percent: percent)
            } else {
                percentText(percent, color: .white)
            }
        case .peek(.lowBattery(let percent)):
            percentText(percent, color: .red)
        case .peek(.volume(let level, let muted)):
            LevelBar(level: muted ? 0 : level)
        case .peek(.brightness(let level)):
            LevelBar(level: level)
        case .peek(.keyboardBacklight(let level)):
            LevelBar(level: level)
        case .peek(.bluetooth(_, let connected, let battery)):
            if let battery {
                percentText(battery, color: battery <= 20 ? .red : .white)
            } else {
                Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(Typo.icon(13))
                    .foregroundStyle(connected ? .green : .secondary)
            }
        case .peek(.focus(let on)):
            Text(on ? "On" : "Off")
                .font(Typo.number(12))
                .foregroundStyle(on ? .white : .secondary)
        }
    }

    private func percentText(_ percent: Int, color: Color) -> some View {
        Text("\(percent)%")
            .font(Typo.number(12))
            .foregroundStyle(color)
    }
}

/// Bolt that bounces once when power is connected (a one-shot effect, not a loop).
private struct ChargingBolt: View {
    @State private var trigger = 0

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(Typo.icon(14))
            .foregroundStyle(.green)
            .symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            .onAppear { trigger += 1 }
    }
}

/// Battery outline that fills up to the charge once, with the percentage.
private struct ChargingLevel: View {
    let percent: Int
    @State private var shown: CGFloat = 0

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("\(percent)%")
                .font(Typo.number(12))
                .foregroundStyle(.green)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 22, height: 11)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.green)
                        .frame(width: 18 * shown, height: 7)
                        .padding(.leading, 2)
                }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { shown = CGFloat(min(100, max(0, percent))) / 100 }
        }
    }
}
