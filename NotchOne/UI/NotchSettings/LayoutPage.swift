import SwiftUI

/// Settings → Layout: what goes where, in every state of the notch.
struct LayoutPage: View {
    @AppStorage(SettingsKey.tabOrder) private var tabOrder = SettingsDefault.tabOrder
    @AppStorage(SettingsKey.hiddenTabs) private var hiddenTabs = SettingsDefault.hiddenTabs
    @AppStorage(SettingsKey.homeCardOrder) private var cardOrder = SettingsDefault.homeCardOrder
    @AppStorage(SettingsKey.wideHomeCards) private var wideCards = SettingsDefault.wideHomeCards
    @AppStorage(SettingsKey.hiddenHomeCards) private var hiddenCards = SettingsDefault.hiddenHomeCards
    @AppStorage(SettingsKey.hiddenHeaderItems) private var hiddenHeader = ""
    @AppStorage(SettingsKey.hiddenCompactItems) private var hiddenCompact = ""
    @AppStorage(SettingsKey.earPriority) private var earPriority = SettingsDefault.earPriority
    @AppStorage(SettingsKey.leftEarClick) private var leftEar = SettingsDefault.leftEarClick
    @AppStorage(SettingsKey.rightEarClick) private var rightEar = SettingsDefault.rightEarClick

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            homeGroup
            tabsGroup

            SettingsGroup(title: "Top bar") {
                ForEach(Array(HeaderItem.allCases.enumerated()), id: \.element) { index, item in
                    if index > 0 { RowDivider() }
                    ToggleRow(title: .verbatim(item.title), isOn: shown(item.rawValue, hiddenIn: $hiddenHeader))
                }
            }

            SettingsGroup(title: "Closed notch", footer: "Clicking the middle of the notch always opens it.") {
                ChoiceRow(title: "While music plays", options: EarPriority.allCases, selection: $earPriority) { $0.title }
                RowDivider()
                earRow("Left side click", value: leftEar) { leftEar = $0 }
                RowDivider()
                earRow("Right side click", value: rightEar) { rightEar = $0 }
            }

            SettingsGroup(title: "Compact row") {
                ForEach(Array(CompactItem.allCases.enumerated()), id: \.element) { index, item in
                    if index > 0 { RowDivider() }
                    ToggleRow(title: .verbatim(item.title), isOn: shown(item.rawValue, hiddenIn: $hiddenCompact))
                }
            }
        }
    }

    // MARK: - Home

    private var homeGroup: some View {
        SettingsGroup(title: "Home", footer: "A card shows only when it has something to show. Two rows fit; drag cards on Home with the edit button.") {
            SettingsRow(title: "Ready-made layout") {
                PillMenu(value: String(localized: "Choose"), options: HomePreset.allCases.map { ($0.rawValue, $0.title) }) { name in
                    if let preset = HomePreset(rawValue: name) { apply(preset) }
                }
            }
            ForEach(Array(HomeLogic.ordered(cardOrder).enumerated()), id: \.element) { index, card in
                RowDivider()
                homeRow(card, index: index)
            }
        }
    }

    private func homeRow(_ card: HomeCard, index: Int) -> some View {
        let cards = HomeLogic.ordered(cardOrder)
        let tabIsHidden = card.tab.map { LayoutLogic.contains($0.rawValue, in: hiddenTabs) } ?? false
        let isWide = LayoutLogic.contains(card.rawValue, in: wideCards)
        return HStack(spacing: Space.s) {
            Image(systemName: card.symbol).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title).font(Typo.body)
                if tabIsHidden {
                    Text("Its tab is hidden").font(Typo.micro).foregroundStyle(.secondary)
                }
            }
            Spacer()
            IconButton(symbol: isWide ? "rectangle.fill" : "rectangle", size: 11, frame: 22, label: "Wide card") {
                wideCards = LayoutLogic.setting(card.rawValue, in: wideCards, to: !isWide)
            }
            .help("Wide card")
            reorderButtons(index: index, count: cards.count, title: card.title) { offset in
                let target = cards[index + offset]
                let moved = offset < 0
                    ? LayoutLogic.move(card, before: target, in: cards)
                    : LayoutLogic.move(target, before: card, in: cards)
                cardOrder = HomeLogic.encode(moved)
            }
            Toggle(card.title, isOn: shown(card.rawValue, hiddenIn: $hiddenCards))
                .toggleStyle(GlassSwitchStyle())
                .labelsHidden()
                .disabled(tabIsHidden)
                .opacity(tabIsHidden ? 0.4 : 1)
        }
        .frame(minHeight: 32)
    }

    private func apply(_ preset: HomePreset) {
        cardOrder = HomeLogic.encode(preset.order)
        wideCards = HomeLogic.encode(preset.wide)
        hiddenCards = HomeLogic.encode(preset.hidden)
    }

    // MARK: - Tabs

    private var tabsGroup: some View {
        SettingsGroup(title: "Tabs", footer: "Drag to reorder. Hidden tabs stay out of the tab bar. With more than seven, the rest go into the … menu.") {
            let tabs = AppearanceLogic.allTabs(order: tabOrder).filter(\.inTabBar)
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                if index > 0 { RowDivider() }
                HStack(spacing: Space.s) {
                    Image(systemName: tab.symbol).frame(width: 18).foregroundStyle(.secondary)
                    Text(tab.title).font(Typo.body)
                    Spacer()
                    reorderButtons(index: index, count: tabs.count, title: tab.title) { offset in
                        tabOrder = AppearanceLogic.encode(AppearanceLogic.move(tab, by: offset, in: tabs))
                    }
                    Toggle(tab.title, isOn: visibility(of: tab))
                        .toggleStyle(GlassSwitchStyle())
                        .labelsHidden()
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .draggable(tab.rawValue)
                .dropDestination(for: String.self) { names, _ in
                    guard let moved = names.first.flatMap(NotchTab.init(rawValue:)) else { return false }
                    tabOrder = AppearanceLogic.encode(LayoutLogic.move(moved, before: tab, in: tabs))
                    return true
                }
            }
        }
    }

    private func visibility(of tab: NotchTab) -> Binding<Bool> {
        Binding {
            !LayoutLogic.contains(tab.rawValue, in: hiddenTabs)
        } set: { visible in
            let hidden = LayoutLogic.setting(tab.rawValue, in: hiddenTabs, to: !visible)
            // Keep at least one tab.
            let hiddenCount = hidden.split(separator: ",").count
            guard hiddenCount < NotchTab.allCases.filter({ $0.inTabBar && !AppearanceLogic.unavailableTabs.contains($0) }).count else { return }
            hiddenTabs = hidden
        }
    }

    // MARK: - Shared rows

    private func reorderButtons(index: Int, count: Int, title: String, move: @escaping (Int) -> Void) -> some View {
        Group {
            IconButton(symbol: "chevron.up", size: 10, frame: 22, label: "Move \(title) up") { move(-1) }
                .disabled(index == 0)
                .opacity(index == 0 ? 0.3 : 1)
            IconButton(symbol: "chevron.down", size: 10, frame: 22, label: "Move \(title) down") { move(1) }
                .disabled(index == count - 1)
                .opacity(index == count - 1 ? 0.3 : 1)
        }
    }

    private func earRow(_ title: LocalizedStringKey, value: EarClick, choose: @escaping (EarClick) -> Void) -> some View {
        SettingsRow(title: title) {
            PillMenu(value: value.title, options: EarClick.allCases.map { ($0.rawValue, $0.title) }) { name in
                if let click = EarClick(rawValue: name) { choose(click) }
            }
        }
    }

    private func shown(_ name: String, hiddenIn list: Binding<String>) -> Binding<Bool> {
        Binding {
            !LayoutLogic.contains(name, in: list.wrappedValue)
        } set: { visible in
            list.wrappedValue = LayoutLogic.setting(name, in: list.wrappedValue, to: !visible)
        }
    }
}
