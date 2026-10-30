import SwiftUI

/// Content of the expanded notch: a tab bar and the selected tab.
struct OpenNotchContent: View {
    @Bindable var model: NotchViewModel
    /// Album tint for the artwork glow, or nil.
    let accent: Color?

    var body: some View {
        Group {
            if let page = model.settingsPage {
                NotchSettingsView(model: model, page: page)
                    .transition(.blurReplace)
            } else if model.showsCompact {
                CompactNotchContent(model: model)
                    .transition(.blurReplace)
            } else {
                tabs
            }
        }
        .foregroundStyle(.white)
    }

    private var tabs: some View {
        let activity = model.activity
        return VStack(alignment: .leading, spacing: Space.s + 2) {
            if model.isDropTargeted {
                DragHeader(urls: model.dragURLs)
                    .transition(.opacity)
            } else {
                HStack(spacing: Space.s) {
                    TabBar(tabs: model.barTabs, selection: $model.selectedTab)
                        .fixedSize()
                        .layoutPriority(1)
                        .spotlight(.tabBar, in: model)
                    HeaderActions(model: model)
                        .spotlight(.actions, in: model)
                    // The status on the right gets shorter before anything overlaps.
                    ViewThatFits(in: .horizontal) {
                        HeaderStatus(model: model, clock: .full)
                        HeaderStatus(model: model, clock: .time)
                        HeaderStatus(model: model, clock: .none)
                    }
                    .spotlight(.status, in: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            ZStack(alignment: .topLeading) {
                if model.isDropTargeted {
                    DropZonesView(model: model)
                        .transition(.blurReplace)
                } else if !model.convertURLs.isEmpty {
                    ConvertPicker(model: model)
                        .transition(.blurReplace)
                } else if let step = model.tourStep {
                    OnboardingCard(model: model, step: step)
                        .transition(.blurReplace)
                } else {
                    Group {
                        switch model.selectedTab {
                        case .home: HomePanel(model: model)
                        case .nowPlaying: NowPlayingPanel(activity: activity, glow: accent)
                        case .weather: WeatherPanel(weather: activity.weather)
                        case .shelf: ShelfView(shelf: activity.shelf, isDropTargeted: model.isDropTargeted)
                        case .clipboard: ClipboardPanel(clipboard: activity.clipboard, notes: activity.notes, translate: activity.translate, model: model)
                        case .search: SearchPanel(model: model)
                        case .translate: TranslatePanel(store: activity.translate, model: model)
                        case .system: SystemPanel(system: activity.system, devices: activity.devices)
                        case .notes: NotesPanel(notes: activity.notes, model: model)
                        case .notifications: NotificationsPanel(live: activity.live)
                        case .mirror: MirrorPanel(activity: activity)
                        }
                    }
                    .id(model.selectedTab)
                    // Tabs morph into each other instead of a plain cross-fade.
                    .transition(.blurReplace.combined(with: .scale(0.97, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // A tab taller than the notch spills off the bottom (clipped) instead of pushing
        // the header up into the neck.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Back to compact, Search, the tour and Settings, next to the tab bar.
private struct HeaderActions: View {
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            if model.mode == .compact {
                IconButton(symbol: "rectangle.compress.vertical", size: 12, frame: 24, label: "Back to compact") {
                    model.collapse()
                }
                .help("Back to compact")
            }
            IconButton(symbol: "magnifyingglass", size: 12, frame: 24, label: "Search") {
                if let openSearch = model.openSearch { openSearch() } else { model.show(.search) }
            }
            .foregroundStyle(model.selectedTab == .search ? .primary : .secondary)
            .background(model.selectedTab == .search ? Color.white.opacity(0.14) : .clear, in: Circle())
            .help("Search (\(HotKey.palette.display))")
            IconButton(symbol: model.activity.keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer", size: 12, frame: 24, label: "Keep Awake") {
                model.activity.toggleKeepAwake()
            }
            .foregroundStyle(model.activity.keepAwake.isOn ? Color.green : .secondary)
            .help("Keep Awake")
            OutputPicker(activity: model.activity)
            IconButton(symbol: "lock", size: 12, frame: 24, label: "Lock this Mac") {
                model.close()
                MacLock.lock()
            }
            .help("Lock this Mac")
            if model.selectedTab == .home {
                IconButton(symbol: "slider.horizontal.3", size: 12, frame: 24, label: "Edit Home") {
                    withAnimation(Motion.tab) { model.isEditingHome.toggle() }
                }
                .foregroundStyle(model.isEditingHome ? .primary : .secondary)
                .background(model.isEditingHome ? Color.white.opacity(0.14) : .clear, in: Circle())
                .help("Edit Home")
            }
            IconButton(symbol: "gearshape", size: 12, frame: 24, label: "Settings") {
                model.openSettings(.general)
            }
            .help("Settings")
        }
        .foregroundStyle(.secondary)
    }
}

/// Focus, weather, battery and the clock, on the right of the header.
private struct HeaderStatus: View {
    enum Clock { case full, time, none }

    let model: NotchViewModel
    let clock: Clock
    @AppStorage(SettingsKey.hiddenHeaderItems) private var hidden = ""

    private func shows(_ item: HeaderItem) -> Bool {
        !LayoutLogic.contains(item.rawValue, in: hidden)
    }

    var body: some View {
        let activity = model.activity
        HStack(spacing: Space.m) {
            if activity.isFocused, shows(.focus) {
                Image(systemName: "moon.fill")
                    .font(Typo.icon(12))
                    .foregroundStyle(.indigo)
                    .help("A Focus is on")
                    .accessibilityLabel("Focus is on")
            }
            if shows(.weather), model.selectedTab != .weather, model.selectedTab != .home, model.tabs.contains(.weather),
               let snapshot = activity.weather.badgeSnapshot() {
                WeatherBadge(snapshot: snapshot) {
                    withAnimation(Motion.tab) { model.show(.weather) }
                }
            }
            if let battery = activity.battery, shows(.battery) {
                BatteryBadge(status: battery)
            }
            if clock != .none, shows(.clock) {
                TimelineView(.everyMinute) { context in
                    Group {
                        if clock == .full {
                            Text(context.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                        } else {
                            Text(context.date, format: .dateTime.hour().minute())
                        }
                    }
                    .font(Typo.number(12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize()
    }
}

struct BatteryBadge: View {
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("\(status.percent)%")
                .font(Typo.number(12, weight: .medium))
            Image(systemName: status.symbolName)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        if status.isPluggedIn { return .green }
        if status.isLow { return .red }
        return .secondary
    }
}
