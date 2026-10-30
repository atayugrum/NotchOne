import SwiftUI

// MARK: - General

struct GeneralPage: View {
    @AppStorage(SettingsKey.openOnHover) private var openOnHover = SettingsDefault.openOnHover
    @AppStorage(SettingsKey.openDelayMs) private var openDelayMs = SettingsDefault.openDelayMs
    @AppStorage(SettingsKey.closeDelayMs) private var closeDelayMs = SettingsDefault.closeDelayMs
    @AppStorage(SettingsKey.showOnDisplaysWithoutNotch)
    private var showOnDisplaysWithoutNotch = SettingsDefault.showOnDisplaysWithoutNotch
    @AppStorage(SettingsKey.gesturesEnabled) private var gesturesEnabled = SettingsDefault.gesturesEnabled
    @AppStorage(SettingsKey.earPreview) private var earPreview = SettingsDefault.earPreview
    @AppStorage(SettingsKey.hideFromCapture) private var hideFromCapture = SettingsDefault.hideFromCapture
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
                RowDivider()
                ToggleRow(
                    title: "Hide from screen sharing",
                    detail: "Asks screenshots and screen sharing to leave the notch out. Some apps may still capture it.",
                    isOn: $hideFromCapture
                )
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
                    detail: "Sideways on the tabs switches tabs, on Now Playing or the closed notch skips tracks; down on the closed notch opens it.",
                    isOn: $gesturesEnabled
                )
                RowDivider()
                ToggleRow(
                    title: "Song name on hover",
                    detail: "Pointing at the sides of the closed notch shows what's playing.",
                    isOn: $earPreview
                )
            }

            SettingsGroup(
                title: "Shortcuts",
                footer: "Search looks through clipboard history, shelf files and tabs."
            ) {
                if Translator.isSupported {
                    shortcut("Translate the selection", HotKey.translate.display)
                }
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
        }
    }
}
