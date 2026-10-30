import SwiftUI

/// Settings → Layout: what goes where, in every state of the notch.
struct LayoutPage: View {
    let editHome: () -> Void
    @AppStorage(SettingsKey.tabOrder) private var tabOrder = SettingsDefault.tabOrder
    @AppStorage(SettingsKey.hiddenTabs) private var hiddenTabs = SettingsDefault.hiddenTabs
    @AppStorage(SettingsKey.hiddenHeaderItems) private var hiddenHeader = ""
    @AppStorage(SettingsKey.hiddenCompactItems) private var hiddenCompact = ""
    @AppStorage(SettingsKey.earPriority) private var earPriority = SettingsDefault.earPriority
    @AppStorage(SettingsKey.leftEarClick) private var leftEar = SettingsDefault.leftEarClick
    @AppStorage(SettingsKey.rightEarClick) private var rightEar = SettingsDefault.rightEarClick

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(title: "Home") {
                SettingsRow(title: "Template and boxes", detail: "Choose them on Home itself.") {
                    PillButton(title: "Edit Home", symbol: "slider.horizontal.3") { editHome() }
                }
            }
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
