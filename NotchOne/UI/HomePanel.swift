import SwiftUI

/// Home tab: boxes laid out by a template, each holding the card chosen for it.
struct HomePanel: View {
    let model: NotchViewModel
    @AppStorage(SettingsKey.homeTemplate) private var template = SettingsDefault.homeTemplate
    @AppStorage(SettingsKey.homeSlots) private var savedSlots = SettingsDefault.homeSlots

    var body: some View {
        VStack(spacing: Space.s) {
            if model.isEditingHome {
                TemplatePicker(selection: $template)
            }
            boxes
        }
        .onDisappear { model.isEditingHome = false }
    }

    private var boxes: some View {
        let slots = HomeLogic.slots(savedSlots)
        return GeometryReader { proxy in
            VStack(spacing: Space.s) {
                ForEach(Array(template.rows.enumerated()), id: \.offset) { rowIndex, spans in
                    let first = HomeLogic.firstSlot(ofRow: rowIndex, in: template)
                    HStack(spacing: Space.s) {
                        ForEach(Array(spans.enumerated()), id: \.offset) { offset, span in
                            box(first + offset, span: span, card: slots[first + offset])
                                .frame(width: HomeLogic.width(span: span, count: spans.count, in: proxy.size.width, spacing: Space.s))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func box(_ index: Int, span: Int, card: HomeCard?) -> some View {
        if model.isEditingHome {
            HomeBoxPicker(
                card: card,
                options: HomeLogic.options(forSlot: index, in: HomeLogic.slots(savedSlots), template: template)
            ) { chosen in
                savedSlots = HomeLogic.encode(HomeLogic.assign(chosen, to: index, in: HomeLogic.slots(savedSlots)))
            }
        } else if let card {
            HomeCardView(card: card, isWide: span >= 3, model: model)
        } else {
            Color.clear
        }
    }
}

/// Small drawings of the templates.
private struct TemplatePicker: View {
    @Binding var selection: HomeTemplate

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(HomeTemplate.allCases) { template in
                Button {
                    withAnimation(Motion.tab) { selection = template }
                } label: {
                    VStack(spacing: 2) {
                        ForEach(Array(template.rows.enumerated()), id: \.offset) { _, spans in
                            HStack(spacing: 2) {
                                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(.white.opacity(selection == template ? 0.9 : 0.4))
                                        .frame(width: CGFloat(span) * 5.5 + CGFloat(span / 2 - 1) * 2, height: 7)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Space.s)
                    .frame(height: 26)
                    .background(.white.opacity(selection == template ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(template.title)
                .accessibilityLabel(template.title)
            }
            Spacer(minLength: 0)
            Text("Click a box to choose what goes in it")
                .font(Typo.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// A box while Home is being edited: a menu of what can go in it.
private struct HomeBoxPicker: View {
    let card: HomeCard?
    let options: [HomeCard]
    let choose: (HomeCard?) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    choose(option)
                } label: {
                    Label(option.title, systemImage: option.symbol)
                }
            }
            Divider()
            Button("Empty") { choose(nil) }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: card?.symbol ?? "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(card?.title ?? String(localized: "Empty"))
                    .font(Typo.captionStrong)
                    .foregroundStyle(card == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

private struct HomeCardView: View {
    let card: HomeCard
    let isWide: Bool
    let model: NotchViewModel
    @State private var isHovering = false

    private var activity: ActivityState { model.activity }

    /// False when there's nothing to show right now; the box keeps its place.
    private var hasContent: Bool {
        switch card {
        case .nowPlaying: activity.nowPlaying != nil
        case .weather: activity.weather.badgeSnapshot() != nil
        case .battery: activity.battery != nil
        case .activity: !activity.live.items.isEmpty
        case .devices: !activity.devices.devices.isEmpty
        case .system: true
        case .notes: !activity.notes.isEmpty
        case .clipboard: !activity.clipboard.items.isEmpty
        case .shelf: !activity.shelf.items.isEmpty
        case .keepAwake: true
        }
    }

    @ViewBuilder
    private var boxContent: some View {
        if hasContent {
            content
        } else {
            HStack(spacing: Space.s) {
                Image(systemName: card.symbol).font(.system(size: 16))
                Text(card.title).font(Typo.body).lineLimit(1)
            }
            .foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        boxContent
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassCard(highlighted: isHovering && (card.tab != nil || card == .activity || card == .keepAwake))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture {
                if let tab = card.tab {
                    withAnimation(Motion.tab) { model.show(tab) }
                } else if card == .keepAwake {
                    activity.toggleKeepAwake()
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
        case .keepAwake:
            HStack(spacing: Space.s) {
                Image(systemName: activity.keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 16))
                    .foregroundStyle(activity.keepAwake.isOn ? .green : .secondary)
                lines(String(localized: "Keep Awake"), activity.keepAwake.isOn ? String(localized: "On") : String(localized: "Off"))
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
