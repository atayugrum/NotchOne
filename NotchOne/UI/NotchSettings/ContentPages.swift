import SwiftUI

// MARK: - Now Playing

struct NowPlayingPage: View {
    @AppStorage(SettingsKey.nowPlayingEnabled) private var nowPlayingEnabled = SettingsDefault.nowPlayingEnabled
    @AppStorage(SettingsKey.systemNowPlayingEnabled)
    private var systemNowPlayingEnabled = SettingsDefault.systemNowPlayingEnabled

    var body: some View {
        SettingsGroup(footer: "Music and Spotify are read directly. Other apps are read from the system's Now Playing info.") {
            ToggleRow(title: "Show what's playing", isOn: $nowPlayingEnabled)
            RowDivider()
            ToggleRow(title: "Include other apps", detail: "Browsers, video players", isOn: $systemNowPlayingEnabled)
                .disabled(!nowPlayingEnabled)
        }
    }
}

// MARK: - Weather

struct WeatherPage: View {
    let weather: WeatherStore
    @AppStorage(SettingsKey.weatherEnabled) private var enabled = SettingsDefault.weatherEnabled
    @AppStorage(SettingsKey.weatherLocationSource) private var source = SettingsDefault.weatherLocationSource
    @AppStorage(SettingsKey.weatherUnit) private var unit = SettingsDefault.weatherUnit
    @AppStorage(SettingsKey.weatherCityName) private var cityName = ""

    @State private var query = ""
    @State private var results: [CityResult] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(footer: "Fetched when you open the notch, at most every 30 minutes.") {
                ToggleRow(title: "Show the weather", detail: "In the Weather tab, on Home and next to the battery", isOn: $enabled)
                RowDivider()
                ChoiceRow(title: "Temperature", options: WeatherUnit.allCases, selection: $unit) { $0.title }
                    .disabled(!enabled)
            }

            SettingsGroup(title: "Place") {
                ChoiceRow(title: "Weather for", options: WeatherLocationSource.allCases, selection: $source) {
                    $0 == .current ? String(localized: "Where I am") : String(localized: "A city")
                }
                if source == .current {
                    RowDivider()
                    SettingsRow(title: "Location access", detail: "Asked only when you choose it") {
                        PillButton(title: "Use my location", symbol: "location.fill") { weather.useCurrentLocation() }
                    }
                } else {
                    RowDivider()
                    SettingsRow(title: "City") {
                        Text(cityName.isEmpty ? String(localized: "None chosen") : cityName)
                            .font(Typo.body)
                            .foregroundStyle(cityName.isEmpty ? .secondary : .primary)
                    }
                    RowDivider()
                    HStack(spacing: Space.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search for a city", text: $query)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .onSubmit(search)
                        if isSearching {
                            SpinnerView(tint: .white).frame(width: 12, height: 12)
                        } else {
                            PillButton(title: "Search", isEnabled: query.trimmingCharacters(in: .whitespaces).count >= 2, action: search)
                        }
                    }
                    .frame(minHeight: 34)
                    if searched && results.isEmpty && !isSearching {
                        Text("No places found.").font(Typo.micro).foregroundStyle(.secondary).padding(.bottom, Space.s)
                    }
                    ForEach(results) { result in
                        RowDivider()
                        Button {
                            choose(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name).font(Typo.body)
                                if !result.detail.isEmpty {
                                    Text(result.detail).font(Typo.micro).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, Space.xs + 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(!enabled)

            SettingsGroup(footer: "Only your area, rounded to about 1 km, is sent to Open-Meteo, a free weather service. No account, no tracking.") {
                SettingsRow(title: .verbatim(OpenMeteo.attribution)) {
                    PillButton(title: "open-meteo.com") { NSWorkspace.shared.open(URL(string: "https://open-meteo.com/")!) }
                }
            }
        }
    }

    private func search() {
        let text = query
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        isSearching = true
        Task {
            results = await CitySearch.search(text)
            isSearching = false
            searched = true
        }
    }

    private func choose(_ result: CityResult) {
        let defaults = UserDefaults.standard
        defaults.set(result.coordinate.latitude, forKey: SettingsKey.weatherCityLatitude)
        defaults.set(result.coordinate.longitude, forKey: SettingsKey.weatherCityLongitude)
        cityName = result.name
        results = []
        query = ""
        searched = false
    }
}

// MARK: - Translate

struct TranslatePage: View {
    let store: TranslateStore
    @AppStorage(SettingsKey.translateFrom) private var from = SettingsDefault.translateFrom
    @AppStorage(SettingsKey.translateTo) private var to = SettingsDefault.translateTo
    @AppStorage(SettingsKey.translateOtherwise) private var otherwise = SettingsDefault.translateOtherwise
    @State private var status: LanguageStatus?

    /// The pair to have on this Mac: From → To, or with Detect, Otherwise ⟷ To.
    private var pair: TranslationPair {
        TranslationPair(
            source: Locale.Language(identifier: from == TranslateLogic.auto ? otherwise : from),
            target: Locale.Language(identifier: to)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(
                footer: from == TranslateLogic.auto
                    ? "Text in \(TranslateLogic.displayName(to)) goes into \(TranslateLogic.displayName(otherwise)); everything else into \(TranslateLogic.displayName(to))."
                    : nil
            ) {
                SettingsRow(title: "From") {
                    PillMenu(value: TranslateLogic.displayName(from), options: store.languages,
                             extra: (TranslateLogic.auto, String(localized: "Detect language"))) { from = $0 }
                }
                RowDivider()
                SettingsRow(title: "To") {
                    PillMenu(value: TranslateLogic.displayName(to), options: store.languages) { to = $0 }
                }
                if from == TranslateLogic.auto {
                    RowDivider()
                    SettingsRow(title: "Already in that language? Into") {
                        PillMenu(value: TranslateLogic.displayName(otherwise), options: store.languages) { otherwise = $0 }
                    }
                }
            }

            SettingsGroup(
                title: "Languages on this Mac",
                footer: "Translation runs on this Mac with Apple's models; nothing is sent anywhere. macOS downloads each language once."
            ) {
                SettingsRow(title: "\(TranslateLogic.displayName(pair.source)) ⟷ \(TranslateLogic.displayName(pair.target))") {
                    switch status {
                    case .installed:
                        GrantedBadge(text: "Ready")
                    case .downloadable:
                        PillButton(title: "Download…", symbol: "arrow.down.circle") {
                            LanguageDownloader.download(pair) { Task { await refresh() } }
                        }
                    case .unsupported:
                        Text("Not available").font(Typo.caption).foregroundStyle(.secondary)
                    case nil:
                        SpinnerView(tint: .white).frame(width: 12, height: 12)
                    }
                }
            }
        }
        .task { await store.loadLanguages() }
        .task(id: "\(from)|\(to)|\(otherwise)") { await refresh() }
    }

    private func refresh() async {
        status = nil
        status = await LanguageDownloader.status(pair)
    }
}

// MARK: - Shelf

struct ShelfPage: View {
    @AppStorage(SettingsKey.openOnFileDrag) private var openOnFileDrag = SettingsDefault.openOnFileDrag
    @AppStorage(SettingsKey.catchScreenshots) private var catchScreenshots = SettingsDefault.catchScreenshots
    @AppStorage(SettingsKey.catchDownloads) private var catchDownloads = SettingsDefault.catchDownloads

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsGroup(footer: "Dragged files split the notch into zones: Shelf and AirDrop, plus remove background, compress and convert for images, compress and merge for PDFs, or copy path. Results are saved next to the original. The shelf keeps links to your files, not copies.") {
                ToggleRow(title: "Open the notch when files are dragged over it", isOn: $openOnFileDrag)
            }
            SettingsGroup(footer: "A new file shows a thumbnail in the notch for a few seconds; drag it straight into another app.") {
                ToggleRow(title: "Peek new screenshots", isOn: $catchScreenshots)
                RowDivider()
                ToggleRow(title: "Peek new downloads", isOn: $catchDownloads)
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardPage: View {
    @AppStorage(SettingsKey.clipboardEnabled) private var clipboardEnabled = SettingsDefault.clipboardEnabled

    var body: some View {
        SettingsGroup(footer: "Kept in memory only and cleared when NotchOne quits. Copies marked private and copies from known password managers are skipped.") {
            ToggleRow(title: "Keep clipboard history", isOn: $clipboardEnabled)
        }
    }
}
