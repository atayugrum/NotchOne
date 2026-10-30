import SwiftUI

// MARK: - Card

/// Lighter glass inside the body: faint white fill, a 0.5 pt highlight along the top edge.
struct GlassCardModifier: ViewModifier {
    var isHighlighted = false
    var radius = Radius.m

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(isHighlighted ? Palette.cardHover : Palette.card, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }
}

extension View {
    func glassCard(highlighted: Bool = false, radius: CGFloat = Radius.m) -> some View {
        modifier(GlassCardModifier(isHighlighted: highlighted, radius: radius))
    }
}

// MARK: - Buttons

/// Capsule button with a label, e.g. "5 min", "Clear".
struct PillButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var tint: Color = .white
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol {
                    Image(systemName: symbol).font(Typo.icon(11))
                }
                Text(title).font(Typo.number(12))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Space.m)
            .frame(height: 28)
            .background(tint.opacity(isHovering ? 0.22 : 0.13), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
    }
}

/// Round, icon-only button (player controls, close badges).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 14
    var frame: CGFloat = 28
    let label: LocalizedStringKey
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typo.icon(size))
                .frame(width: frame, height: frame)
                .background(.white.opacity(isHovering ? 0.12 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Small "×" badge shown on hovered cards.
struct RemoveBadge: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.7))
        }
        .buttonStyle(.plain)
        .padding(3)
        .accessibilityLabel(label)
    }
}

// MARK: - Levels

/// Thin horizontal level indicator for volume and brightness.
struct LevelBar: View {
    let level: Float
    var width: CGFloat = 50
    var tint: Color = .white

    var body: some View {
        Capsule()
            .fill(Palette.track)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: width * CGFloat(min(1, max(0, level))))
            }
            .frame(width: width, height: 5)
            .animation(.easeOut(duration: 0.12), value: level)
    }
}

// MARK: - Tabs

/// Glass segmented control; the selection slides between tabs.
struct TabBar: View {
    let tabs: [NotchTab]
    @Binding var selection: NotchTab
    /// More tabs than this, and the rest go into a "More" menu at the end.
    var maxVisible = 6
    @Namespace private var namespace

    private var split: (shown: [NotchTab], more: [NotchTab]) {
        guard tabs.count > maxVisible else { return (tabs, []) }
        return (Array(tabs.prefix(maxVisible - 1)), Array(tabs.dropFirst(maxVisible - 1)))
    }

    var body: some View {
        let split = split
        HStack(spacing: 2) {
            ForEach(split.shown) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(Motion.tab) { selection = tab }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: tab.symbol)
                            .font(Typo.icon(12))
                        if isSelected {
                            Text(tab.title)
                                .font(Typo.captionStrong)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, isSelected ? Space.s + 2 : 0)
                    .frame(minWidth: 32, minHeight: 24)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : .secondary)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
            if !split.more.isEmpty {
                moreMenu(split.more)
            }
        }
        .padding(2)
        .glassCard(radius: 14)
    }

    /// Shows the selected tab's symbol when the selection is one of the extra tabs.
    private func moreMenu(_ more: [NotchTab]) -> some View {
        let selected = more.first { $0 == selection }
        return Menu {
            ForEach(more) { tab in
                Button {
                    withAnimation(Motion.tab) { selection = tab }
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }
        } label: {
            Image(systemName: selected?.symbol ?? "ellipsis")
                .font(Typo.icon(12))
                .frame(width: 32, height: 24)
                .background {
                    if selected != nil {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(selected != nil ? .white : .secondary)
        .help("More tabs")
        .accessibilityLabel("More tabs")
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    /// Soft coloured glow behind the artwork (album tint), or nil.
    var glow: Color?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.control)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: (glow ?? .clear).opacity(0.7), radius: size * 0.22)
    }
}
