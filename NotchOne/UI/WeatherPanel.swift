import SwiftUI

/// Weather tab: now on the left, the next hours and days on the right.
struct WeatherPanel: View {
    let weather: WeatherStore
    @AppStorage(SettingsKey.weatherUnit) private var unit = SettingsDefault.weatherUnit
    @AppStorage(SettingsKey.weatherEnabled) private var enabled = SettingsDefault.weatherEnabled

    var body: some View {
        if !enabled {
            message("Weather is turned off.", symbol: "cloud.sun") {
                PillButton(title: "Turn on") { enabled = true }
            }
        } else if let snapshot = weather.snapshot, weather.status != .needsLocation, weather.status != .locationDenied {
            HStack(alignment: .top, spacing: Space.m) {
                NowCard(snapshot: snapshot, place: weather.placeName, isLoading: weather.status == .loading, unit: unit) {
                    weather.openWeatherApp()
                }
                .frame(width: 184)
                VStack(spacing: Space.s) {
                    HoursCard(snapshot: snapshot, unit: unit)
                    DaysCard(snapshot: snapshot, unit: unit)
                }
            }
        } else {
            switch weather.status {
            case .needsLocation:
                message("See the weather where you are.", symbol: "location") {
                    PillButton(title: "Use my location", symbol: "location.fill") { weather.useCurrentLocation() }
                    PillButton(title: "Choose a city…") { SettingsOpener.open(page: .weather) }
                }
            case .locationDenied:
                message("Location is off for NotchOne.", symbol: "location.slash") {
                    PillButton(title: "Open Privacy Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    PillButton(title: "Choose a city…") { SettingsOpener.open(page: .weather) }
                }
            case .failed(let text):
                message("\(text)", symbol: "exclamationmark.triangle") {
                    PillButton(title: "Try again", symbol: "arrow.clockwise") { weather.refreshNow() }
                }
            case .idle, .loading:
                HStack(spacing: Space.s) {
                    SpinnerView(tint: .white).frame(width: 14, height: 14)
                    Text("Loading the weather…").font(Typo.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
                .onAppear { weather.refreshIfNeeded() }
            }
        }
    }

    private func message(_ text: LocalizedStringKey, symbol: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(text, systemImage: symbol)
                .font(Typo.body)
                .foregroundStyle(.secondary)
            HStack(spacing: Space.s) { actions() }
            Spacer(minLength: 0)
            Text(OpenMeteo.attribution).font(Typo.micro).foregroundStyle(.tertiary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }
}

/// Times and days in the forecast place's own time zone.
private extension WeatherSnapshot {
    var timeZone: TimeZone { TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current }
}

private struct NowCard: View {
    let snapshot: WeatherSnapshot
    let place: String?
    let isLoading: Bool
    let unit: WeatherUnit
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                Text(WeatherLogic.format(snapshot.temperature, unit: unit))
                    .font(Typo.number(30))
            }
            Text("\(snapshot.condition.title) · feels \(WeatherLogic.format(snapshot.feelsLike, unit: unit))")
                .font(Typo.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: Space.xs) {
                Text(place ?? String(localized: "Current location"))
                Text("·")
                if isLoading {
                    SpinnerView(tint: .white).frame(width: 9, height: 9)
                } else {
                    Text(snapshot.fetchedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                }
            }
            .font(Typo.micro)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(OpenMeteo.attribution)
                .font(Typo.micro)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(highlighted: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: open)
        .help("Open Weather")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct HoursCard: View {
    let snapshot: WeatherSnapshot
    let unit: WeatherUnit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.hours.prefix(8).enumerated()), id: \.offset) { index, hour in
                VStack(spacing: 3) {
                    Text(index == 0 ? String(localized: "weather.now", defaultValue: "Now") : label(hour.time))
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                    Image(systemName: hour.condition.symbol(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                        .frame(height: 16)
                    Text(WeatherLogic.format(hour.temperature, unit: unit))
                        .font(Typo.number(12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private func label(_ time: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = snapshot.timeZone
        return time.formatted(style)
    }
}

private struct DaysCard: View {
    let snapshot: WeatherSnapshot
    let unit: WeatherUnit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text(index == 0 ? String(localized: "weather.today", defaultValue: "Today") : weekday(day.date))
                            .font(Typo.micro)
                            .foregroundStyle(.secondary)
                        Image(systemName: day.condition.symbol(isDay: true))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                    }
                    HStack(spacing: 3) {
                        Text(WeatherLogic.format(day.high, unit: unit))
                        Text(WeatherLogic.format(day.low, unit: unit)).foregroundStyle(.secondary)
                    }
                    .font(Typo.number(11, weight: .medium))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Space.xs)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func weekday(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = snapshot.timeZone
        return date.formatted(style)
    }
}

/// Small forecast next to the battery in the header; clicking it shows the Weather tab.
struct WeatherBadge: View {
    let snapshot: WeatherSnapshot
    let action: () -> Void
    @AppStorage(SettingsKey.weatherUnit) private var unit = SettingsDefault.weatherUnit

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: snapshot.condition.symbol(isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                Text(WeatherLogic.format(snapshot.temperature, unit: unit))
                    .font(Typo.number(12, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(snapshot.condition.title)
        .accessibilityLabel("\(snapshot.condition.title), \(WeatherLogic.format(snapshot.temperature, unit: unit))")
    }
}
