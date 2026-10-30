import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    let shelf: ShelfStore
    let isDropTargeted: Bool

    var body: some View {
        if shelf.items.isEmpty && shelf.pending.isEmpty {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isDropTargeted ? .white : .white.opacity(0.3))
                .background(isDropTargeted ? Palette.cardHover : Palette.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .overlay {
                    Label("Drop files here to keep them handy", systemImage: "tray.and.arrow.down")
                        .font(Typo.body)
                        .foregroundStyle(.secondary)
                }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url, shelf: shelf)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        ForEach(shelf.pending) { item in
                            PendingShelfItemView(item: item)
                        }
                    }
                    .animation(Motion.tab, value: shelf.items)
                    .animation(Motion.tab, value: shelf.pending)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    PillButton(title: "AirDrop", symbol: "airplayaudio", isEnabled: shelf.canAirDrop) { shelf.airDropAll() }
                    PillButton(title: "Clear", symbol: "trash") { shelf.clear() }
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
    }
}

private struct ShelfItemView: View {
    let url: URL
    let shelf: ShelfStore
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .frame(width: 72, height: 84, alignment: .top)
        .padding(.top, Space.xs)
        .glassCard(highlighted: isHovering, radius: Radius.s + 2)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                RemoveBadge(label: "Remove \(url.lastPathComponent)") { shelf.remove(url) }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.revealInFinder(url) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}

/// Placeholder while a drop action makes its file: the source's icon, dimmed, with a spinner.
private struct PendingShelfItemView: View {
    let item: PendingShelfItem

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.source.path))
                .resizable()
                .frame(width: 40, height: 40)
                .opacity(0.35)
                .overlay {
                    SpinnerView(tint: .white).frame(width: 18, height: 18)
                }
            Text(item.title + "…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 72, height: 84, alignment: .top)
        .padding(.top, Space.xs)
        .glassCard(radius: Radius.s + 2)
    }
}
