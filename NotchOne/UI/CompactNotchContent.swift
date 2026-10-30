import SwiftUI

/// Compact mode: one row of glanceable things. Clicking anything opens the full notch
/// on that tab; the chevron opens it on the last tab.
struct CompactNotchContent: View {
    let model: NotchViewModel

    @AppStorage(SettingsKey.hiddenCompactItems) private var hidden = ""

    private var activity: ActivityState { model.activity }

    private typealias Chip = CompactItem

    var body: some View {
        HStack(spacing: Space.s) {
            lead
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, Space.m)
                .glassCard()
                .contentShape(Rectangle())
                .onTapGesture { model.expand(to: activity.nowPlaying == nil ? .home : .nowPlaying) }

            ForEach(chips, id: \.self) { chip in
                chipView(chip)
            }

            IconButton(symbol: "chevron.down", size: 12, frame: 28, label: "Show everything") { model.expand() }
                .help("Show everything")
        }
    }

    /// What's going on, most important first; fewer when a wide live item takes room.
    private var chips: [Chip] {
        var chips: [Chip] = []
        if activity.live.top != nil { chips.append(.live) }
        if activity.weather.badgeSnapshot() != nil { chips.append(.weather) }
        if activity.battery != nil { chips.append(.battery) }
        chips.removeAll { LayoutLogic.contains($0.rawValue, in: hidden) }
        return Array(chips.prefix(chips.first == .live ? 2 : 3))
    }

    /// Now Playing, or the time and date when nothing plays.
    @ViewBuilder
    private var lead: some View {
        if let info = activity.nowPlaying {
            HStack(spacing: Space.s) {
                ArtworkView(image: activity.artwork, size: 34, cornerRadius: 7)
                    .opensPlayer(activity)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title).font(Typo.body)
                    Text(info.artist.isEmpty ? (AppInfo.name(for: info.appBundleID) ?? "") : info.artist)
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                IconButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 13, frame: 28,
                           label: info.isPlaying ? "Pause" : "Play") {
                    activity.player?.perform(.playPause)
                }
            }
        } else {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date, format: .dateTime.hour().minute()).font(Typo.number(18))
                    Text(context.date, format: .dateTime.weekday(.wide).day().month())
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        Group {
            switch chip {
            case .live:
                if let top = activity.live.top {
                    HStack(spacing: Space.xs) {
                        LiveLeading(item: top).frame(width: 16)
                        Text(top.title).font(Typo.micro).lineLimit(1)
                    }
                    .frame(width: 98)
                }
            case .weather:
                if let snapshot = activity.weather.badgeSnapshot() {
                    WeatherBadge(snapshot: snapshot) { model.expand(to: .weather) }
                }
            case .battery:
                if let battery = activity.battery {
                    BatteryBadge(status: battery)
                }
            }
        }
        .fixedSize()
        .frame(maxHeight: .infinity)
        .padding(.horizontal, Space.s + 2)
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture {
            switch chip {
            case .live:
                if let top = activity.live.top, top.appPID != nil {
                    activity.live.activate(top)
                } else {
                    model.expand(to: .home)
                }
            case .weather: model.expand(to: .weather)
            case .battery: model.expand(to: .home)
            }
        }
    }
}
