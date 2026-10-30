import SwiftUI

struct ClipboardPanel: View {
    let clipboard: ClipboardStore
    let notes: NotesStore
    let translate: TranslateStore
    let model: NotchViewModel

    var body: some View {
        if !clipboard.isRunning {
            Label("Clipboard history is turned off in Settings.", systemImage: "doc.on.clipboard")
                .font(Typo.body)
                .foregroundStyle(.secondary)
        } else if clipboard.items.isEmpty {
            Label("Copy something and it shows up here. Click an item to copy it again.", systemImage: "doc.on.clipboard")
                .font(Typo.body)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(clipboard.items) { item in
                            ClipboardCard(item: item, clipboard: clipboard, notes: notes, translate: translate, model: model)
                        }
                    }
                }
                VStack(spacing: Space.xs) {
                    PillButton(title: "Clear", symbol: "trash") { clipboard.clear() }
                    PillButton(title: "Search", symbol: "magnifyingglass") {
                        if let openSearch = model.openSearch { openSearch() } else { model.show(.search) }
                    }
                }
            }
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let clipboard: ClipboardStore
    let notes: NotesStore
    let translate: TranslateStore
    let model: NotchViewModel
    @State private var isHovering = false

    /// The card's text and what can be done with it. Translate needs its tab to show the result.
    private var actions: (text: String, list: [ClipboardAction])? {
        guard case .text(let text) = item.content, let smart = item.smart else { return nil }
        let list = ClipboardActions.available(for: text, smart: smart)
        return (text, list.filter { $0 != .translate || model.tabs.contains(.translate) })
    }

    private func perform(_ action: ClipboardAction, on text: String) {
        switch action {
        case .translate:
            translate.translate(text)
            model.show(.translate)
        case .composeEmail:
            if let url = ClipboardActions.mailto(text) { NSWorkspace.shared.open(url) }
        case .addToNotes:
            notes.append(text)
            clipboard.showCopied(item.id)
        default:
            guard let result = ClipboardActions.apply(action, to: text) else { return }
            withAnimation(.easeOut(duration: 0.15)) { clipboard.copy(text: result, from: item.sourceBundleID) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 4) {
                if let icon = AppInfo.icon(for: item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                if isHovering, let actions, !actions.list.isEmpty {
                    ForEach(actions.list, id: \.self) { action in
                        ClipboardActionButton(action: action) { perform(action, on: actions.text) }
                    }
                } else {
                    Text(item.copiedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if clipboard.lastCopiedID == item.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(Space.s)
        .frame(width: 128, height: 88)
        .glassCard(highlighted: isHovering, radius: Radius.s + 2)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                RemoveBadge(label: "Remove from history") { clipboard.remove(item) }
            }
        }
        .overlay(alignment: .topLeading) {
            if case .text = item.content, isHovering || item.isPinned {
                PinBadge(isPinned: item.isPinned) { clipboard.togglePin(item) }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { clipboard.copy(item) } }
        .help("Click to copy")
        .animation(.easeOut(duration: 0.15), value: clipboard.lastCopiedID)
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .text(let text):
            SmartTextPreview(text: text, smart: item.smart ?? .plain(words: 0))
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case .files(let urls):
            HStack(spacing: 6) {
                if let first = urls.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                    .font(.system(size: 11))
                    .lineLimit(3)
            }
        }
    }
}

/// Keeps a card through Clear and restarts.
private struct PinBadge: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(35))
                .foregroundStyle(isPinned ? .yellow : .white)
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin" : "Pin")
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
    }
}

/// A small button in a card's footer: the format's name for colours, a symbol otherwise.
private struct ClipboardActionButton: View {
    let action: ClipboardAction
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Group {
                if let format {
                    Text(verbatim: format).font(.system(size: 8, weight: .semibold))
                } else {
                    Image(systemName: symbol).font(.system(size: 10))
                }
            }
            .frame(minWidth: 18, minHeight: 16)
            .padding(.horizontal, format == nil ? 0 : 2)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var format: String? {
        switch action {
        case .colorHex: "HEX"
        case .colorRGB: "RGB"
        case .colorHSL: "HSL"
        default: nil
        }
    }

    private var symbol: String {
        switch action {
        case .cleanLink: "wand.and.stars"
        case .composeEmail: "envelope"
        case .formatJSON: "text.alignleft"
        case .minifyJSON: "arrow.down.right.and.arrow.up.left"
        case .translate: "character.bubble"
        default: "note.text"
        }
    }

    private var title: LocalizedStringKey {
        switch action {
        case .cleanLink: "Clean link and copy"
        case .composeEmail: "New email"
        case .formatJSON: "Format and copy"
        case .minifyJSON: "Minify and copy"
        case .colorHex: "Copy as HEX"
        case .colorRGB: "Copy as RGB"
        case .colorHSL: "Copy as HSL"
        case .translate: "Translate"
        case .addToNotes: "Add to Notes"
        }
    }
}

/// Text card body by kind: a swatch for colours, the domain for links, monospaced JSON
/// and code, a word count for long text.
private struct SmartTextPreview: View {
    let text: String
    let smart: SmartText

    var body: some View {
        switch smart {
        case .color(let red, let green, let blue, let alpha):
            VStack(alignment: .leading, spacing: Space.xs) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: red, green: green, blue: blue, opacity: alpha))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    }
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        case .email(let address):
            VStack(alignment: .leading, spacing: 2) {
                Label("Email", systemImage: "envelope").font(Typo.micro).foregroundStyle(.secondary)
                Text(address).font(Typo.captionStrong).lineLimit(2).truncationMode(.middle)
            }
        case .link(let host, let path):
            VStack(alignment: .leading, spacing: 2) {
                Label("Link", systemImage: "link").font(Typo.micro).foregroundStyle(.secondary)
                Text(host).font(Typo.title).lineLimit(1)
                if !path.isEmpty {
                    Text(path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
            }
        case .json(let pretty):
            VStack(alignment: .leading, spacing: 2) {
                Label("JSON", systemImage: "curlybraces").font(Typo.micro).foregroundStyle(.secondary)
                Text(pretty).font(.system(size: 9, design: .monospaced)).lineLimit(4)
            }
        case .code:
            VStack(alignment: .leading, spacing: 2) {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right").font(Typo.micro).foregroundStyle(.secondary)
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(4)
            }
        case .plain(let words):
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipboardLogic.preview(text)).font(.system(size: 11)).lineLimit(words > 30 ? 3 : 4)
                if words > 30 {
                    Text("\(words) words").font(Typo.micro).foregroundStyle(.secondary)
                }
            }
        }
    }
}
