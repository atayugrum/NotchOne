import SwiftUI

/// Home tab: one small card per thing going on. Each card opens its tab.
struct HomePanel: View {
    let model: NotchViewModel
    @AppStorage(SettingsKey.hiddenHomeCards) private var hiddenCards = SettingsDefault.hiddenHomeCards
    @AppStorage(SettingsKey.homeCardOrder) private var cardOrder = SettingsDefault.homeCardOrder
    @AppStorage(SettingsKey.wideHomeCards) private var wideCards = SettingsDefault.wideHomeCards

    private var activity: ActivityState { model.activity }

    var body: some View {
        Group {
            if model.isEditingHome {
                editor
            } else {
                cards
            }
        }
        .onDisappear { model.isEditingHome = false }
    }

    @ViewBuilder
    private var cards: some View {
        let cards = HomeLogic.cards(hasContent: available, hidden: hiddenCards, visibleTabs: model.tabs, order: cardOrder)
        if cards.isEmpty {
            Label("Nothing to show yet. Play music, copy something or drop a file on the notch.", systemImage: "square.grid.2x2")
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
        } else {
            GeometryReader { proxy in
                let column = HomeLogic.columnWidth(in: proxy.size.width, spacing: Space.s)
                VStack(spacing: Space.s) {
                    ForEach(Array(HomeLogic.rows(cards, wide: wideCards).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Space.s) {
                            ForEach(row) { slot in
                                HomeCardView(card: slot.card, isWide: slot.span > 1, model: model)
                                    .frame(width: column * CGFloat(slot.span) + Space.s * CGFloat(slot.span - 1))
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    /// Every card, shown or not, so each one can be reached however many there are.
    private var editor: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs + 2), count: HomeLogic.columns), spacing: Space.xs + 2) {
                ForEach(HomeLogic.ordered(cardOrder)) { card in
                    let isHidden = LayoutLogic.contains(card.rawValue, in: hiddenCards)
                    let isWide = LayoutLogic.contains(card.rawValue, in: wideCards)
                    HomeEditCard(card: card, isHidden: isHidden, isWide: isWide) {
                        wideCards = LayoutLogic.setting(card.rawValue, in: wideCards, to: !isWide)
                    } toggleHidden: {
                        hiddenCards = LayoutLogic.setting(card.rawValue, in: hiddenCards, to: !isHidden)
                    } drop: { moved in
                        cardOrder = HomeLogic.encode(LayoutLogic.move(moved, before: card, in: HomeLogic.ordered(cardOrder)))
                    }
                }
            }
        }
    }

    /// Cards with something to show right now.
    private var available: Set<HomeCard> {
        var cards: Set<HomeCard> = []
        if activity.nowPlaying != nil { cards.insert(.nowPlaying) }
        if activity.weather.badgeSnapshot() != nil { cards.insert(.weather) }
        if activity.battery != nil { cards.insert(.battery) }
        if !activity.live.items.isEmpty { cards.insert(.activity) }
        if !activity.devices.devices.isEmpty { cards.insert(.devices) }
        cards.insert(.system)
        if !activity.notes.isEmpty { cards.insert(.notes) }
        if !activity.clipboard.items.isEmpty { cards.insert(.clipboard) }
        if !activity.shelf.items.isEmpty { cards.insert(.shelf) }
        return cards
    }
}

/// A card while Home is being edited: drag it onto another to move it.
private struct HomeEditCard: View {
    let card: HomeCard
    let isHidden: Bool
    let isWide: Bool
    let toggleWide: () -> Void
    let toggleHidden: () -> Void
    let drop: (HomeCard) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: card.symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(card.title).font(Typo.captionStrong).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            IconButton(symbol: isWide ? "rectangle.fill" : "rectangle", size: 10, frame: 20, label: "Wide card", action: toggleWide)
                .help("Wide card")
                .disabled(isHidden)
                .opacity(isHidden ? 0.3 : 1)
            IconButton(symbol: isHidden ? "eye.slash" : "eye", size: 10, frame: 20, label: isHidden ? "Show card" : "Hide card", action: toggleHidden)
                .help(isHidden ? "Show card" : "Hide card")
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xs)
        .frame(height: 34)
        .glassCard(highlighted: isTargeted, radius: Radius.s + 2)
        .opacity(isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .draggable(card.rawValue)
        .dropDestination(for: String.self) { names, _ in
            guard let moved = names.first.flatMap(HomeCard.init(rawValue:)) else { return false }
            drop(moved)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct HomeCardView: View {
    let card: HomeCard
    let isWide: Bool
    let model: NotchViewModel
    @State private var isHovering = false

    private var activity: ActivityState { model.activity }

    var body: some View {
        content
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassCard(highlighted: isHovering && (card.tab != nil || card == .activity))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture {
                if let tab = card.tab {
                    withAnimation(Motion.tab) { model.show(tab) }
                } else if card == .activity, let top = activity.live.top, top.source != .meeting {
                    // A notification: go to its app. Anything else: clear it.
                    if top.appPID != nil {
                        activity.live.activate(top)
                    } else {
                        activity.live.dismiss(top.id)
                    }
                }
            }
            .help(card.tab.map { String(localized: "Open \($0.title)") } ?? card.title)
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .nowPlaying:
            if let info = activity.nowPlaying {
                HStack(spacing: Space.s) {
                    ArtworkView(image: activity.artwork, size: isWide ? 44 : 32, cornerRadius: isWide ? 9 : 7)
                        .opensPlayer(activity)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title).font(isWide ? Typo.title : Typo.body)
                        Text(info.artist.isEmpty ? (AppInfo.name(for: info.appBundleID) ?? "") : info.artist)
                            .font(Typo.micro)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if isWide {
                        IconButton(symbol: "backward.fill", size: 11, frame: 26, label: "Previous") {
                            activity.player?.perform(.previous)
                        }
                    }
                    IconButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 13, frame: 28,
                               label: info.isPlaying ? "Pause" : "Play") {
                        activity.player?.perform(.playPause)
                    }
                    if isWide {
                        IconButton(symbol: "forward.fill", size: 11, frame: 26, label: "Next") {
                            activity.player?.perform(.next)
                        }
                    }
                }
            }
        case .weather:
            if let snapshot = activity.weather.badgeSnapshot() {
                WeatherGlance(snapshot: snapshot)
            }
        case .battery:
            if let battery = activity.battery {
                HStack(spacing: Space.s) {
                    Image(systemName: battery.symbolName)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(battery.isPluggedIn ? .green : battery.isLow ? .red : .white)
                    lines("\(battery.percent)%", battery.isPluggedIn ? String(localized: "Charging") : String(localized: "On battery"), numeric: true)
                }
            }
        case .activity:
            HStack(spacing: Space.s) {
                if let top = activity.live.top {
                    LiveLeading(item: top).frame(width: 20)
                    lines(top.title, activity.live.items.count > 1 ? String(localized: "+\(activity.live.items.count - 1) more") : LiveStyle.subtitle(for: top))
                    if case .meeting(let mic, _, let muted) = top.status, mic || muted, let toggle = activity.onToggleMicMute {
                        Spacer(minLength: 0)
                        IconButton(symbol: muted ? "mic.slash.fill" : "mic.fill", size: 13, frame: 28,
                                   label: muted ? "Unmute" : "Mute", action: toggle)
                    }
                }
            }
        case .devices:
            HStack(spacing: Space.m) {
                ForEach(activity.devices.devices.prefix(2)) { device in
                    HStack(spacing: Space.xs + 2) {
                        Image(systemName: device.symbol).font(.system(size: 15)).foregroundStyle(.secondary)
                        lines(device.lowest.map { "\($0)%" } ?? "–", device.name, numeric: true)
                    }
                }
            }
        case .system:
            SystemGlance(system: activity.system)
        case .notes:
            HStack(spacing: Space.s) {
                Image(systemName: "note.text").font(.system(size: 16)).foregroundStyle(.yellow)
                lines(activity.notes.firstLine ?? "", String(localized: "\(activity.notes.text.count) characters"))
            }
        case .clipboard:
            if let item = activity.clipboard.items.first {
                HStack(spacing: Space.s) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 16)).foregroundStyle(.secondary)
                    lines(Self.preview(item), item.copiedAt.formatted(.relative(presentation: .named)))
                }
            }
        case .shelf:
            if let first = activity.shelf.items.first {
                let count = activity.shelf.items.count
                HStack(spacing: Space.s) {
                    Image(systemName: "tray.full").font(.system(size: 16)).foregroundStyle(.secondary)
                    lines(String(localized: "\(count) files"), first.lastPathComponent)
                }
            }
        }
    }

    private func lines(_ title: String, _ subtitle: String, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(numeric ? Typo.value : Typo.body)
            Text(subtitle).font(Typo.micro).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private static func preview(_ item: ClipboardItem) -> String {
        switch item.content {
        case .text(let text):
            text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        case .image: String(localized: "Image")
        case .files(let urls): urls.first?.lastPathComponent ?? String(localized: "Files")
        }
    }
}

/// Weather symbol, temperature and conditions, for Home and the compact row.
struct WeatherGlance: View {
    let snapshot: WeatherSnapshot
    @AppStorage(SettingsKey.weatherUnit) private var unit = SettingsDefault.weatherUnit

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 1) {
                Text(WeatherLogic.format(snapshot.temperature, unit: unit)).font(Typo.value)
                Text(snapshot.condition.title).font(Typo.micro).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

/// CPU and memory for the Home card; measures only while it shows.
private struct SystemGlance: View {
    let system: SystemMonitorStore

    var body: some View {
        HStack(spacing: Space.m) {
            stat("CPU", system.current?.cpu)
            stat("Memory", system.current?.memory)
        }
        .onAppear { system.startWatching() }
        .onDisappear { system.stopWatching() }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                .font(Typo.value)
                .contentTransition(.numericText())
            Text(title).font(Typo.micro).foregroundStyle(.secondary)
        }
        .animation(Motion.quick, value: value)
    }
}
