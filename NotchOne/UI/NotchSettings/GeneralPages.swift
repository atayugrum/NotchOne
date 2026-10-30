import SwiftUI

// MARK: - General

struct GeneralPage: View {
    @AppStorage(SettingsKey.openOnHover) private var openOnHover = SettingsDefault.openOnHover
    @AppStorage(SettingsKey.openDelayMs) private var openDelayMs = SettingsDefault.openDelayMs
    @AppStorage(SettingsKey.closeDelayMs) private var closeDelayMs = SettingsDefault.closeDelayMs
    @AppStorage(SettingsKey.showOnDisplaysWithoutNotch)
    private var showOnDisplaysWithoutNotch = SettingsDefault.showOnDisplaysWithoutNotch
    @AppStorage(SettingsKey.gesturesEnabled) private var gesturesEnabled = SettingsDefault.gesturesEnabled
    @AppStorage(SettingsKey.lockScreenWidget) private var lockScreenWidget = SettingsDefault.lockScreenWidget

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var language = AppLanguage.current()
    /// The language that's on screen now; a different choice needs a restart.
    @State private var runningLanguage = AppLanguage.current()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup {
                ChoiceRow(title: "Language", options: AppLanguage.allCases, selection: $language) { $0.title }
                    .onChange(of: language) { _, newValue in AppLanguage.set(newValue) }
                if language != runningLanguage {
                    SettingsRow(title: "Restart NotchOne to switch the language") {
                        PillButton(title: "Restart", symbol: "arrow.clockwise") { AppLanguage.relaunch() }
                    }
                }
            }

            SettingsGroup {
                ToggleRow(title: "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in updateLaunchAtLogin(newValue) }
                if LaunchAtLogin.needsApproval {
                    SettingsRow(title: "Needs your approval") {
                        PillButton(title: "Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let launchError {
                    Text(launchError).font(Typo.micro).foregroundStyle(.red).padding(.bottom, Space.s)
                }
                RowDivider()
                ToggleRow(title: "Show a notch on displays without one", isOn: $showOnDisplaysWithoutNotch)
            }

            SettingsGroup(title: "Opening") {
                ChoiceRow(title: "Open the notch", options: [true, false], selection: $openOnHover) {
                    $0 ? String(localized: "On hover") : String(localized: "On click")
                }
                if openOnHover {
                    RowDivider()
                    SliderRow(title: "Open delay", value: $openDelayMs, range: 0...600, step: 10) { "\(Int($0)) ms" }
                }
                RowDivider()
                SliderRow(title: "Close delay", value: $closeDelayMs, range: 0...1000, step: 50) { "\(Int($0)) ms" }
                RowDivider()
                ToggleRow(
                    title: "Trackpad swipes",
                    detail: "Sideways on the tabs switches tabs, on Now Playing skips tracks; down on the closed notch opens it.",
                    isOn: $gesturesEnabled
                )
            }

            SettingsGroup(
                title: "Shortcuts",
                footer: "Search looks through clipboard history, shelf files and tabs."
            ) {
                shortcut("Translate the selection", HotKey.translate.display)
                RowDivider()
                shortcut("Search", HotKey.palette.display)
            }

            SettingsGroup(
                footer: SkyLightSpace.isAvailable
                    ? "A small Now Playing and battery card under the notch while your Mac is locked. Uses a private macOS feature; turn it off if anything looks wrong."
                    : "Not available on this version of macOS."
            ) {
                ToggleRow(title: "Now Playing on the lock screen", detail: "Experimental", isOn: $lockScreenWidget)
                    .disabled(!SkyLightSpace.isAvailable)
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, _ keys: String) -> some View {
        SettingsRow(title: title) {
            Text(keys)
                .font(Typo.number(12, weight: .medium))
                .padding(.horizontal, Space.s)
                .frame(height: 22)
                .background(Palette.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @AppStorage(SettingsKey.notchMode) private var notchMode = SettingsDefault.notchMode
    @AppStorage(SettingsKey.notchStyle) private var style = SettingsDefault.notchStyle
    @AppStorage(SettingsKey.glassStrength) private var glassStrength = SettingsDefault.glassStrength
    @AppStorage(SettingsKey.albumTint) private var albumTint = SettingsDefault.albumTint
    @AppStorage(SettingsKey.notchOutline) private var outline = SettingsDefault.notchOutline
    @AppStorage(SettingsKey.panelSize) private var panelSize = SettingsDefault.panelSize
    @AppStorage(SettingsKey.tabOrder) private var tabOrder = SettingsDefault.tabOrder
    @AppStorage(SettingsKey.hiddenTabs) private var hiddenTabs = SettingsDefault.hiddenTabs
    @AppStorage(SettingsKey.hiddenHomeCards) private var hiddenHomeCards = SettingsDefault.hiddenHomeCards
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(
                footer: "Compact opens a small notch with one row: what's playing, the weather, jobs and the battery. Click anything to see everything."
            ) {
                ChoiceRow(title: "Mode", options: NotchMode.allCases, selection: $notchMode) { $0.title }
                RowDivider()
                ChoiceRow(title: "Size", options: PanelSize.allCases, selection: $panelSize) { $0.title }
                RowDivider()
                ChoiceRow(
                    title: "Shape without a notch",
                    detail: "Displays with a real notch always use the notch shape.",
                    options: NotchOutline.allCases,
                    selection: $outline
                ) { $0.title }
            }

            SettingsGroup(
                title: "Style",
                footer: reduceTransparency ? "Reduce Transparency is on in Accessibility settings, so the glass is shown as a solid surface." : nil
            ) {
                ChoiceRow(title: "Look", options: NotchStyle.allCases, selection: $style) { $0.title }
                if style == .glass {
                    RowDivider()
                    SliderRow(title: "Glass", value: $glassStrength, range: 0...1) { $0 < 0.34 ? String(localized: "Darker") : $0 > 0.66 ? String(localized: "Clearer") : String(localized: "Balanced") }
                    RowDivider()
                    ToggleRow(title: "Tint with the album colour", isOn: $albumTint)
                }
            }

            SettingsGroup(title: "Tabs", footer: "Hidden tabs stay out of the tab bar. With more than ten, the rest go into the … menu.") {
                let tabs = AppearanceLogic.allTabs(order: tabOrder).filter(\.inTabBar)
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    if index > 0 { RowDivider() }
                    HStack(spacing: Space.s) {
                        Image(systemName: tab.symbol).frame(width: 18).foregroundStyle(.secondary)
                        Text(tab.title).font(Typo.body)
                        Spacer()
                        IconButton(symbol: "chevron.up", size: 10, frame: 22, label: "Move \(tab.title) up") {
                            move(tab, by: -1, in: tabs)
                        }
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.3 : 1)
                        IconButton(symbol: "chevron.down", size: 10, frame: 22, label: "Move \(tab.title) down") {
                            move(tab, by: 1, in: tabs)
                        }
                        .disabled(index == tabs.count - 1)
                        .opacity(index == tabs.count - 1 ? 0.3 : 1)
                        Toggle(tab.title, isOn: visibility(of: tab))
                            .toggleStyle(GlassSwitchStyle())
                            .labelsHidden()
                    }
                    .frame(minHeight: 32)
                }
            }

            SettingsGroup(title: "Home", footer: "A card shows only when it has something to show, and at most six at a time.") {
                ForEach(Array(HomeCard.allCases.enumerated()), id: \.element) { index, card in
                    if index > 0 { RowDivider() }
                    ToggleRow(title: .verbatim(card.title), isOn: homeCardVisibility(card))
                }
            }
        }
    }

    private func visibility(of tab: NotchTab) -> Binding<Bool> {
        Binding {
            !hiddenTabs.split(separator: ",").contains(Substring(tab.rawValue))
        } set: { visible in
            var hidden = Set(hiddenTabs.split(separator: ",").map(String.init))
            if visible { hidden.remove(tab.rawValue) } else { hidden.insert(tab.rawValue) }
            // Keep at least one tab.
            guard hidden.count < NotchTab.allCases.filter(\.inTabBar).count else { return }
            hiddenTabs = hidden.sorted().joined(separator: ",")
        }
    }

    private func homeCardVisibility(_ card: HomeCard) -> Binding<Bool> {
        Binding {
            !hiddenHomeCards.split(separator: ",").contains(Substring(card.rawValue))
        } set: { visible in
            var hidden = Set(hiddenHomeCards.split(separator: ",").map(String.init))
            if visible { hidden.remove(card.rawValue) } else { hidden.insert(card.rawValue) }
            hiddenHomeCards = hidden.sorted().joined(separator: ",")
        }
    }

    private func move(_ tab: NotchTab, by offset: Int, in tabs: [NotchTab]) {
        tabOrder = AppearanceLogic.encode(AppearanceLogic.move(tab, by: offset, in: tabs))
    }
}
