import SwiftUI

/// A titled glass card of setting rows, with an optional note under it.
struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Space.xs)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            if let footer {
                Text(footer)
                    .font(Typo.micro)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

/// One line: a title (and a short note) on the left, a control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.body)
                if let detail {
                    Text(detail)
                        .font(Typo.micro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: 34)
    }
}

/// A row with a switch.
struct ToggleRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(GlassSwitchStyle())
                .labelsHidden()
        }
    }
}

/// The system switch turns grey in the notch (the panel is never the active window), so
/// on and off would look alike. This one is green when on, dim when off.
struct GlassSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        Button {
            withAnimation(Motion.quick) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Color.green.opacity(0.85) : Color.white.opacity(0.16))
                .frame(width: 32, height: 19)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A small segmented control in the notch's style: capsules, the chosen one lit.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Motion.tab) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Typo.captionStrong)
                        .padding(.horizontal, Space.s + 2)
                        .frame(height: 22)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "choice", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : .secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.control, in: Capsule())
        .fixedSize()
    }
}

/// A row with a segmented choice.
struct ChoiceRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            SegmentedChoice(options: options, selection: $selection, title: label)
        }
    }
}

/// A row with a slider and its value.
struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    var body: some View {
        SettingsRow(title: title) {
            HStack(spacing: Space.s) {
                Group {
                    if let step {
                        Slider(value: $value, in: range, step: step)
                    } else {
                        Slider(value: $value, in: range)
                    }
                }
                .controlSize(.small)
                .frame(width: 160)
                Text(format(value))
                    .font(Typo.number(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
    }
}

/// A pill that opens a menu of choices: "To  Türkçe ⌄". For long lists like languages.
struct PillMenu: View {
    var title: LocalizedStringKey?
    let value: String
    let options: [(id: String, name: String)]
    var extra: (id: String, name: String)?
    let choose: (String) -> Void

    var body: some View {
        Menu {
            if let extra {
                Button(extra.name) { choose(extra.id) }
                Divider()
            }
            ForEach(options, id: \.id) { option in
                Button(option.name) { choose(option.id) }
            }
        } label: {
            HStack(spacing: Space.xs) {
                if let title { Text(title).foregroundStyle(.secondary) }
                Text(value)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .font(Typo.captionStrong)
            .padding(.horizontal, Space.s + 2)
            .frame(height: 26)
            .background(Palette.control, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title.map { Text($0) } ?? Text(verbatim: value))
        .accessibilityValue(value)
    }
}

/// "Granted ✓" in green.
struct GrantedBadge: View {
    var text: LocalizedStringKey = "Granted"

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(Typo.captionStrong)
            .foregroundStyle(.green)
    }
}

/// A thin line between rows in a group.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
    }
}

enum PrivacyPane {
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension LocalizedStringKey {
    /// Text that's already translated (a tab title) or a name: shown as it is.
    static func verbatim(_ text: String) -> LocalizedStringKey {
        "\(text)"
    }
}
