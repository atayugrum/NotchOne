import QuickLookThumbnailing
import SwiftUI

/// While files are dragged over the open notch, the body splits into drop zones that fit
/// the file type. Shelf and AirDrop sit in a small column; the file actions get big tiles
/// that say what they'll make.
struct DropZonesView: View {
    let model: NotchViewModel
    @State private var targeted: DropAction?

    var body: some View {
        let urls = model.dragURLs
        let kind = DropKind.classify(urls)
        let actions = DropAction.actions(for: kind, count: urls.count)
        let basic = actions.filter(\.isBasic)
        let main = actions.filter { !$0.isBasic }

        HStack(spacing: Space.s) {
            VStack(spacing: Space.s) {
                ForEach(basic) { action in
                    zone(action, kind: kind, urls: urls, style: .compact)
                }
            }
            .frame(width: main.isEmpty ? nil : 132)
            .frame(maxWidth: main.isEmpty ? .infinity : nil)

            ForEach(main) { action in
                zone(action, kind: kind, urls: urls, style: .large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func zone(_ action: DropAction, kind: DropKind, urls: [URL], style: DropZone.Style) -> some View {
        DropZone(
            action: action,
            subtitle: action.subtitle(kind: kind, urls: urls),
            style: style,
            isTargeted: targeted == action,
            isDimmed: targeted != nil && targeted != action
        ) { isOver in
            if isOver {
                targeted = action
            } else if targeted == action {
                targeted = nil
            }
        } onDrop: { dropped in
            if action == .convert {
                model.convertURLs = dropped.filter(\.isFileURL)
            } else {
                model.activity.drops.perform(action, on: dropped)
                model.show(.shelf)
            }
            model.dragChanged([])
        }
    }
}

private struct DropZone: View {
    enum Style {
        case compact
        case large
    }

    let action: DropAction
    let subtitle: String
    let style: Style
    let isTargeted: Bool
    let isDimmed: Bool
    let onTarget: (Bool) -> Void
    let onDrop: ([URL]) -> Void

    var body: some View {
        content
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(highlighted: isTargeted)
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .fill(.white.opacity(0.12))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(.white.opacity(isTargeted ? 0.8 : 0), lineWidth: 1.5)
            }
            .scaleEffect(isTargeted ? 1.04 : 1)
            .opacity(isDimmed ? 0.55 : 1)
            .animation(Motion.hover, value: isTargeted)
            .animation(Motion.quick, value: isDimmed)
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return !urls.isEmpty
            } isTargeted: { onTarget($0) }
            .accessibilityLabel("\(action.title): \(subtitle)")
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .compact:
            HStack(spacing: Space.s) {
                Image(systemName: action.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(action.title).font(Typo.captionStrong)
                    Text(subtitle).font(Typo.micro).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
        case .large:
            VStack(spacing: Space.xs + 2) {
                Image(systemName: action.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 30)
                Text(action.title)
                    .font(Typo.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Typo.micro)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xs)
        }
    }
}

/// After dropping on Convert: what the files can become.
struct ConvertPicker: View {
    let model: NotchViewModel

    var body: some View {
        let urls = model.convertURLs
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(DropKind.summary(urls))
                    .font(Typo.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.right").font(Typo.icon(10)).foregroundStyle(.secondary)
                Text("Choose a format").font(Typo.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                PillButton(title: "Cancel", symbol: "xmark") { model.convertURLs = [] }
            }
            HStack(spacing: Space.s) {
                ForEach(ConvertFormat.options(for: urls)) { format in
                    FormatTile(format: format) {
                        model.activity.drops.convert(urls, to: format)
                        model.convertURLs = []
                        model.show(.shelf)
                    }
                }
            }
        }
    }
}

private struct FormatTile: View {
    let format: ConvertFormat
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(format.title).font(Typo.number(15))
                Text(format.note)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, Space.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(highlighted: isHovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(format.title): \(format.note)")
    }
}

/// Replaces the tab bar while dragging: what's being dragged, and where to drop it.
struct DragHeader: View {
    let urls: [URL]
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: Space.s) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: urls.first?.path ?? "/"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if urls.count > 1 {
                        Text("\(urls.count)")
                            .font(Typo.number(9))
                            .padding(.horizontal, 4)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                            .offset(x: 6, y: -5)
                    }
                }
            Text(DropKind.summary(urls))
                .font(Typo.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Drop on an action")
                .font(Typo.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 28)
        .task(id: urls.first) {
            guard let url = urls.first else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 24, height: 24),
                scale: 2,
                representationTypes: .thumbnail
            )
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}
