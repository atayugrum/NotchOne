import ApplicationServices
import SwiftUI

// MARK: - Integrations

struct IntegrationsPage: View {
    @AppStorage(SettingsKey.mediaKeysEnabled) private var mediaKeysEnabled = SettingsDefault.mediaKeysEnabled
    @AppStorage(SettingsKey.batteryAlertsEnabled) private var batteryAlertsEnabled = SettingsDefault.batteryAlertsEnabled
    @AppStorage(SettingsKey.bluetoothAlertsEnabled)
    private var bluetoothAlertsEnabled = SettingsDefault.bluetoothAlertsEnabled
    @AppStorage(SettingsKey.meetingModeEnabled) private var meetingModeEnabled = SettingsDefault.meetingModeEnabled
    @AppStorage(SettingsKey.focusIndicatorEnabled)
    private var focusIndicatorEnabled = SettingsDefault.focusIndicatorEnabled
    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = SettingsDefault.notificationsEnabled
    @AppStorage(SettingsKey.notificationsHideBanners) private var notificationsHideBanners = SettingsDefault.notificationsHideBanners
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(
                title: "Notifications",
                footer: "Reads notifications from their banners through Accessibility. They're shown for a few seconds, kept in the Notifications tab until NotchOne quits, and never written to disk. A notification that's hidden here may not stay in Notification Center."
            ) {
                ToggleRow(
                    title: "Show notifications in the notch",
                    detail: notificationsEnabled && !accessibilityTrusted ? "Needs Accessibility permission to see the banners" : nil,
                    isOn: $notificationsEnabled
                )
                if notificationsEnabled {
                    RowDivider()
                    if accessibilityTrusted {
                        ToggleRow(title: "Hide the macOS banner", isOn: $notificationsHideBanners)
                    } else {
                        SettingsRow(title: "Accessibility") {
                            PillButton(title: "Allow…") {
                                SystemPromptWatcher.expectPrompt()
                                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                                accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
                            }
                        }
                    }
                }
            }
            SettingsGroup(
                title: "Calls and Focus",
                footer: "Meeting mode needs no camera or microphone permission. The Focus moon asks for Focus Status access when turned on."
            ) {
                ToggleRow(
                    title: "Meeting mode",
                    detail: "Shows when the camera or microphone is in use, with a mute for every app",
                    isOn: $meetingModeEnabled
                )
                RowDivider()
                ToggleRow(title: "Show when a Focus is on", isOn: $focusIndicatorEnabled)
            }
            SettingsGroup(title: "System") {
                ToggleRow(
                    title: "Volume, brightness & keyboard light in the notch",
                    detail: mediaKeysEnabled && !accessibilityTrusted ? "Needs Accessibility permission to see the keys" : nil,
                    isOn: $mediaKeysEnabled
                )
                if mediaKeysEnabled && !accessibilityTrusted {
                    SettingsRow(title: "Accessibility") {
                        PillButton(title: "Allow…") {
                            SystemPromptWatcher.expectPrompt()
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }
                RowDivider()
                ToggleRow(title: "Battery alerts", isOn: $batteryAlertsEnabled)
                RowDivider()
                ToggleRow(title: "Bluetooth alerts", isOn: $bluetoothAlertsEnabled)
            }
            CommandLineGroup()
        }
        .task {
            // Picks up Accessibility once it's granted in System Settings.
            while !Task.isCancelled {
                accessibilityTrusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct CommandLineGroup: View {
    @State private var installed = CommandLineTool.isInstalled
    @State private var error: String?

    var body: some View {
        SettingsGroup(
            title: "Command line",
            footer: "Links `notch` into ~/.local/bin. Then `notch run <command>` shows any command's progress in the notch; `notch progress 0.4 \"Uploading\"`, `notch done` and `notch say \"…\"` work from scripts."
        ) {
            SettingsRow(title: "notch command", detail: error.map(LocalizedStringKey.verbatim)) {
                if installed {
                    PillButton(title: "Remove") { change { try CommandLineTool.uninstall() } }
                } else {
                    PillButton(title: "Install") { change { try CommandLineTool.install() } }
                }
            }
        }
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        installed = CommandLineTool.isInstalled
    }
}

// MARK: - Privacy

struct PrivacyPage: View {
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var automationGranted = PermissionGate.isGranted(.automation)
    @State private var bluetoothGranted = PermissionGate.isGranted(.bluetooth)
    @AppStorage(PermissionGate.key) private var requested = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "lock.shield").foregroundStyle(.green)
                    Text("NotchOne has no servers, no accounts, no analytics and no third-party code. This is everything it sends and keeps.")
                        .font(Typo.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Space.s)
            }
            SettingsGroup(title: "Leaves your Mac") {
                DataRow(symbol: "cloud.sun", title: "Weather", detail: "Your area, rounded to about 1 km, to Open-Meteo")
                RowDivider()
                DataRow(symbol: "music.note", title: "Spotify artwork", detail: "The cover image, fetched from Spotify's image server")
                RowDivider()
                DataRow(symbol: "arrow.down.circle", title: "Update check", detail: "Once a day to NotchOne's website, with no identifiers; can be turned off in About")
            }
            SettingsGroup(title: "Stays on your Mac") {
                DataRow(symbol: "doc.on.clipboard", title: "Clipboard history", detail: "In memory only, except text you pin; known password managers are skipped")
                RowDivider()
                DataRow(symbol: "tray.full", title: "Shelf", detail: "Links to your files, not copies")
                RowDivider()
                DataRow(symbol: "character.bubble", title: "Translation", detail: "Apple's on-device models")
                RowDivider()
                DataRow(symbol: "person.crop.square", title: "Mirror", detail: "A live preview; nothing is recorded")
                RowDivider()
                DataRow(symbol: "note.text", title: "Notes", detail: "A text file in NotchOne's folder in Application Support")
                RowDivider()
                DataRow(symbol: "gauge.with.dots.needle.33percent", title: "System and devices", detail: "CPU, memory, network and batteries, read from macOS only while shown")
                RowDivider()
                DataRow(symbol: "bell", title: "Notifications", detail: "Read from macOS's banners if you turn them on, and kept in memory until NotchOne quits")
            }
            SettingsGroup(title: "Permissions") {
                SettingsRow(title: "Accessibility", detail: "Volume and brightness keys, translating the selection, and controlling players other than Music and Spotify") {
                    if accessibilityTrusted {
                        GrantedBadge()
                    } else {
                        PillButton(title: "Grant…") {
                            // Shows the system prompt that links to Privacy & Security > Accessibility.
                            SystemPromptWatcher.expectPrompt()
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }
                RowDivider()
                SettingsRow(title: "Automation", detail: "Reading and controlling Music and Spotify") {
                    if automationGranted {
                        GrantedBadge()
                    } else if isRequested(.automation) {
                        PillButton(title: "Open…") { PrivacyPane.open("Privacy_Automation") }
                    } else {
                        PillButton(title: "Allow…") {
                            PermissionGate.markRequested(.automation)
                            let running = PlayerApp.scriptable.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
                            Task.detached { for app in running { _ = PermissionGate.automationStatus(for: app.bundleID, ask: true) } }
                        }
                    }
                }
                RowDivider()
                SettingsRow(title: "Bluetooth", detail: "Alerts when headphones and other devices connect") {
                    if bluetoothGranted {
                        GrantedBadge()
                    } else if isRequested(.bluetooth) {
                        PillButton(title: "Open…") { PrivacyPane.open("Privacy_Bluetooth") }
                    } else {
                        PillButton(title: "Allow…") { PermissionGate.markRequested(.bluetooth) }
                    }
                }
                RowDivider()
                SettingsRow(title: "Location", detail: "Only for the weather, and only after you choose “Use my location”") {
                    PillButton(title: "Open…") { PrivacyPane.open("Privacy_LocationServices") }
                }
                RowDivider()
                SettingsRow(title: "Files and Folders", detail: "Desktop and Downloads, only to show new screenshots and downloads; turn them off in Shelf & Drops") {
                    if isRequested(.folders) {
                        PillButton(title: "Open…") { PrivacyPane.open("Privacy_FilesAndFolders") }
                    } else {
                        PillButton(title: "Allow…") { PermissionGate.markRequested(.folders) }
                    }
                }
                RowDivider()
                SettingsRow(title: "Camera", detail: "Only for the Mirror tab; nothing is recorded") {
                    PillButton(title: "Open…") { PrivacyPane.open("Privacy_Camera") }
                }
            }
        }
        .task {
            // Only while this page is open: pick up the permission once granted.
            while !Task.isCancelled {
                accessibilityTrusted = AXIsProcessTrusted()
                automationGranted = PermissionGate.isGranted(.automation)
                bluetoothGranted = PermissionGate.isGranted(.bluetooth)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// One kind of data and where it goes.
private struct DataRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).font(Typo.icon(11)).frame(width: 18).foregroundStyle(.secondary)
            SettingsRow(title: title, detail: detail) { EmptyView() }
        }
    }
}

extension PrivacyPage {
    fileprivate func isRequested(_ kind: PermissionKind) -> Bool {
        requested.split(separator: ",").contains(Substring(kind.rawValue))
    }
}

// MARK: - About

struct AboutPage: View {
    let updates: UpdateStore
    let showTour: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup {
                HStack(spacing: Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotchOne").font(Typo.title)
                        Text(version).font(Typo.micro).foregroundStyle(.secondary)
                        Text("Free, with no accounts or tracking.").font(Typo.micro).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Space.s)
            }
            if updates.feedURL != nil {
                UpdatesGroup(updates: updates)
            }
            SettingsGroup(title: "Credits") {
                SettingsRow(title: .verbatim(OpenMeteo.attribution), detail: "CC BY 4.0") {
                    PillButton(title: "open-meteo.com") { NSWorkspace.shared.open(URL(string: "https://open-meteo.com/")!) }
                }
                RowDivider()
                SettingsRow(title: "Translation", detail: "Apple's on-device Translation framework") { EmptyView() }
            }
            SettingsGroup {
                SettingsRow(title: "Support NotchOne", detail: "Free to use. A coffee helps keep it going.") {
                    PillButton(title: "Support", symbol: "heart") { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/atayugrum")!) }
                }
                RowDivider()
                SettingsRow(title: "Tour", detail: "What the notch can do, step by step") {
                    PillButton(title: "Show the tour", symbol: "questionmark.circle") { showTour() }
                }
                RowDivider()
                SettingsRow(title: "Quit NotchOne") {
                    PillButton(title: "Quit", tint: .red) { NSApp.terminate(nil) }
                }
            }
        }
    }
}

private struct UpdatesGroup: View {
    let updates: UpdateStore
    @AppStorage(SettingsKey.updateChecksEnabled) private var automatic = SettingsDefault.updateChecksEnabled

    var body: some View {
        SettingsGroup(
            title: "Updates",
            footer: "Checks for a new version once a day. An update is installed only if it's signed by NotchOne's developer."
        ) {
            ToggleRow(title: "Check for updates automatically", isOn: $automatic)
            RowDivider()
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.status {
        case .idle:
            SettingsRow(title: "Version \(updates.currentVersion)") {
                PillButton(title: "Check now") { updates.check() }
            }
        case .checking:
            SettingsRow(title: "Checking…") { ProgressView().controlSize(.small) }
        case .upToDate:
            SettingsRow(title: "NotchOne is up to date") {
                PillButton(title: "Check now") { updates.check() }
            }
        case .available(let update):
            SettingsRow(title: "NotchOne \(update.version) is available", detail: update.notes.map(LocalizedStringKey.verbatim)) {
                HStack(spacing: Space.s) {
                    if let page = update.page {
                        PillButton(title: "What's new") { NSWorkspace.shared.open(page) }
                    }
                    PillButton(title: "Install", symbol: "arrow.down.circle", tint: .green) { updates.install(update) }
                }
            }
        case .installing:
            SettingsRow(title: "Installing the update…") { ProgressView().controlSize(.small) }
        case .failed(let message):
            SettingsRow(title: "Update failed", detail: .verbatim(message)) {
                PillButton(title: "Try again") { updates.check() }
            }
        }
    }
}
