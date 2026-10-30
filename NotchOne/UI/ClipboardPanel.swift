import SwiftUI

struct ClipboardPanel: View {
    let clipboard: ClipboardStore

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
                            ClipboardCard(item: item, clipboard: clipboard)
                        }
                    }
                }
                PillButton(title: "Clear", symbol: "trash") { clipboard.clear() }
            }
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let clipboard: ClipboardStore
    @State private var isHovering = false

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
                Text(item.copiedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
