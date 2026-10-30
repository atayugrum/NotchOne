import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case appearance
    case layout
    case nowPlaying
    case weather
    case translate
    case shelf
    case clipboard
    case integrations
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .layout: String(localized: "Layout")
        case .nowPlaying: String(localized: "Now Playing")
        case .weather: String(localized: "Weather")
        case .translate: String(localized: "Translate")
        case .shelf: String(localized: "Shelf & Drops")
        case .clipboard: String(localized: "Clipboard")
        case .integrations: String(localized: "Integrations")
        case .privacy: String(localized: "Privacy")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .layout: "rectangle.3.group"
        case .nowPlaying: "music.note"
        case .weather: "cloud.sun"
        case .translate: "character.bubble"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .integrations: "puzzlepiece.extension"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

/// Settings inside the notch: pages on the left, the chosen page on the right.
struct NotchSettingsView: View {
    let model: NotchViewModel
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s + 2) {
            HStack(spacing: Space.s) {
                Button {
                    model.closeSettings()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(Typo.captionStrong)
                        .padding(.horizontal, Space.s + 2)
                        .frame(height: 28)
                        .glassCard(radius: 14)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Back to the tabs")
                Text("Settings").font(Typo.title)
                Spacer()
            }

            HStack(alignment: .top, spacing: Space.m) {
                rail
                    .frame(width: 156)
                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .padding(.bottom, Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(page)
                .transition(.blurReplace)
                // Content fades out at the bottom edge instead of being cut off.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Space.m)
                    }
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 1) {
            ForEach(SettingsPage.allCases.filter { $0 != .translate || Translator.isSupported }) { item in
                let isSelected = item == page
                Button {
                    model.showSettingsPage(item)
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(Typo.body)
                        .labelStyle(RailLabelStyle())
                        .padding(.horizontal, Space.s)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .background(
                            isSelected ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : .secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Space.xs)
        .glassCard()
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: GeneralPage()
        case .appearance: AppearancePage()
        case .layout: LayoutPage {
            model.closeSettings()
            model.show(.home)
            model.isEditingHome = true
        }
        case .nowPlaying: NowPlayingPage()
        case .weather: WeatherPage(weather: model.activity.weather)
        case .translate: TranslatePage(store: model.activity.translate)
        case .shelf: ShelfPage()
        case .clipboard: ClipboardPage()
        case .integrations: IntegrationsPage()
        case .privacy: PrivacyPage()
        case .about: AboutPage(updates: model.activity.updates, showTour: { model.startTour() })
        }
    }
}

private struct RailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon.frame(width: 16)
            configuration.title.lineLimit(1)
        }
    }
}
