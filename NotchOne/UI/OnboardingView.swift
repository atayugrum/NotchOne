import ApplicationServices
import AVFoundation
import CoreLocation
import SwiftUI

/// One step of the tour, shown under the header in place of the tab.
struct OnboardingCard: View {
    let model: NotchViewModel
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: step.symbol)
                    .font(Typo.icon(18))
                    .frame(width: 40, height: 40)
                    .glassCard(radius: 20)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(step.title).font(Typo.title)
                    Text(step.message)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(step)
            .transition(.blurReplace)

            Group {
                switch step {
                case .tabs: TourModeChoice()
                case .shortcuts: TourShortcuts()
                case .permissions: TourPermissions(weather: model.activity.weather)
                case .features: TourFeatures()
                case .welcome: TourOpeningChoice()
                case .drop, .done: EmptyView()
                }
            }
            .padding(.leading, 40 + Space.m)
            .id("\(step.id)-extra")
            .transition(.blurReplace)

            Spacer(minLength: 0)
            TourControls(model: model)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }
}

/// Dots, Skip, Back and Next.
private struct TourControls: View {
    let model: NotchViewModel

    var body: some View {
        let isLast = model.tourIndex == model.tourSteps.count - 1
        HStack(spacing: Space.s) {
            HStack(spacing: 5) {
                ForEach(model.tourSteps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == model.tourIndex ? Color.white : Color.white.opacity(0.25))
                        .frame(width: index == model.tourIndex ? 14 : 5, height: 5)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(model.tourIndex + 1) of \(model.tourSteps.count)"))
            Spacer()
            if !isLast {
                Button("Skip") { model.endTour() }
                    .buttonStyle(.plain)
                    .font(Typo.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.s)
            }
            if model.tourIndex > 0 {
                PillButton(title: "Back") { model.previousTourStep() }
            }
            PillButton(title: isLast ? "Done" : "Next", symbol: isLast ? "checkmark" : "arrow.right", tint: isLast ? .green : .white) {
                model.nextTourStep()
            }
        }
    }
}

private struct TourOpeningChoice: View {
    @AppStorage(SettingsKey.openOnHover) private var openOnHover = SettingsDefault.openOnHover

    var body: some View {
        HStack(spacing: Space.s) {
            Text("Open the notch").font(Typo.captionStrong)
            SegmentedChoice(options: [true, false], selection: $openOnHover) {
                $0 ? String(localized: "On hover") : String(localized: "On click")
            }
        }
    }
}

private struct TourModeChoice: View {
    @AppStorage(SettingsKey.notchMode) private var notchMode = SettingsDefault.notchMode

    var body: some View {
        HStack(spacing: Space.s) {
            Text("Mode").font(Typo.captionStrong)
            SegmentedChoice(options: NotchMode.allCases, selection: $notchMode) { $0.title }
        }
    }
}

private struct TourShortcuts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            row(HotKey.palette.display, "Search clipboard, shelf and tabs")
            if Translator.isSupported {
                row(HotKey.translate.display, "Translate the selected text")
            }
        }
    }

    private func row(_ keys: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: Space.s) {
            Text(keys)
                .font(Typo.number(11, weight: .medium))
                .padding(.horizontal, Space.s)
                .frame(minWidth: 44, minHeight: 20)
                .background(Palette.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title).font(Typo.captionStrong)
        }
    }
}

/// Everything that starts off. Macs ask for a permission only if its switch needs one.
private struct TourFeatures: View {
    @AppStorage(SettingsKey.notificationsEnabled) private var notifications = SettingsDefault.notificationsEnabled
    @AppStorage(SettingsKey.focusIndicatorEnabled) private var focus = SettingsDefault.focusIndicatorEnabled
    @AppStorage(SettingsKey.lockScreenWidget) private var lockScreen = SettingsDefault.lockScreenWidget
    @AppStorage(SettingsKey.hideFromCapture) private var hideFromCapture = SettingsDefault.hideFromCapture
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("arrow.up.right.square", "Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? LaunchAtLogin.set(enabled)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            row("bell", "Show notifications in the notch", isOn: $notifications)
                .onChange(of: notifications) { _, enabled in
                    guard enabled, !AXIsProcessTrusted() else { return }
                    SystemPromptWatcher.expectPrompt()
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            row("moon", "Show when a Focus is on", isOn: $focus)
            row("lock.rectangle", "Music and battery on the lock screen", isOn: $lockScreen)
            row("eye.slash", "Hide from screen sharing", isOn: $hideFromCapture)
        }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).font(Typo.icon(11)).frame(width: 16).foregroundStyle(.secondary)
            Text(title).font(Typo.captionStrong).lineLimit(1)
            Spacer(minLength: Space.s)
            Toggle(title, isOn: isOn)
                .toggleStyle(GlassSwitchStyle())
                .labelsHidden()
        }
        .frame(minHeight: 26)
    }
}

/// Each permission next to the feature it's for; macOS asks only when its button is pressed.
private struct TourPermissions: View {
    let weather: WeatherStore

    @AppStorage(SettingsKey.hiddenTabs) private var hiddenTabs = SettingsDefault.hiddenTabs
    @AppStorage(PermissionGate.key) private var requested = ""
    @State private var accessibility = AXIsProcessTrusted()
    @State private var location = CLLocationManager().authorizationStatus
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var bluetooth = PermissionGate.isGranted(.bluetooth)
    @State private var automation = PermissionGate.isGranted(.automation)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            row("location.fill", "Weather where you are", state: location == .authorizedAlways || location == .authorized ? .granted : .off) {
                weather.useCurrentLocation()
            }
            row("keyboard", "Volume keys, translating the selection", state: accessibility ? .granted : .off) {
                // The system prompt links to Privacy & Security → Accessibility.
                SystemPromptWatcher.expectPrompt()
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                accessibility = AXIsProcessTrustedWithOptions(options)
            }
            row("music.note", "Control Music and Spotify", state: automation ? .granted : isOn(.automation) ? .asked : .off) {
                PermissionGate.markRequested(.automation)
                // macOS can only ask while the player is running; otherwise it asks the first time one plays.
                let running = PlayerApp.scriptable.filter { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty == false }
                Task.detached {
                    for app in running { _ = PermissionGate.automationStatus(for: app.bundleID, ask: true) }
                }
            }
            row("headphones", "Headphone connect alerts", state: bluetooth ? .granted : isOn(.bluetooth) ? .asked : .off) {
                PermissionGate.markRequested(.bluetooth)
            }
            row("photo.on.rectangle", "Peek new screenshots and downloads", state: isOn(.folders) ? .asked : .off) {
                PermissionGate.markRequested(.folders)
            }
            row("person.crop.square", "Mirror tab, a camera check before calls", state: camera == .authorized ? .granted : .off) {
                hiddenTabs = AppearanceLogic.showing(.mirror, hidden: hiddenTabs)
                Task {
                    SystemPromptWatcher.expectPrompt()
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                    camera = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
        }
        .task {
            // Pick up answers to the prompts and permissions granted in System Settings.
            while !Task.isCancelled {
                accessibility = AXIsProcessTrusted()
                location = CLLocationManager().authorizationStatus
                bluetooth = PermissionGate.isGranted(.bluetooth)
                automation = PermissionGate.isGranted(.automation)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private enum RowState { case off, asked, granted }

    private func isOn(_ kind: PermissionKind) -> Bool {
        requested.split(separator: ",").contains(Substring(kind.rawValue))
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, state: RowState, allow: @escaping () -> Void) -> some View {
        let allow = { SystemPromptWatcher.expectPrompt(); allow() }
        return HStack(spacing: Space.s) {
            Image(systemName: symbol).font(Typo.icon(11)).frame(width: 16).foregroundStyle(.secondary)
            Text(title).font(Typo.captionStrong).lineLimit(1)
            Spacer(minLength: Space.s)
            switch state {
            case .granted: GrantedBadge()
            case .asked: GrantedBadge(text: "On")
            case .off: PillButton(title: "Allow…", action: allow)
            }
        }
        .frame(minHeight: 26)
    }
}

extension View {
    /// During the tour: a glowing ring on the item a step points at, and the rest of the
    /// header dimmed. No effect outside the tour.
    func spotlight(_ target: SpotlightTarget, in model: NotchViewModel) -> some View {
        modifier(SpotlightModifier(isTour: model.tourStep != nil, isLit: model.tourStep?.target == target))
    }
}

private struct SpotlightModifier: ViewModifier {
    let isTour: Bool
    let isLit: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(isTour && !isLit ? 0.3 : 1)
            .allowsHitTesting(!isTour)
            .overlay {
                if isLit {
                    Capsule()
                        .strokeBorder(.white.opacity(pulse ? 0.9 : 0.45), lineWidth: 1.5)
                        .shadow(color: .white.opacity(pulse ? 0.6 : 0.2), radius: pulse ? 8 : 3)
                        .padding(-4)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                        .transition(.opacity)
                }
            }
            .animation(Motion.tab, value: isLit)
    }
}
