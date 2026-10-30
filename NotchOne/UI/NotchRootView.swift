import SwiftUI

struct NotchRootView: View {
    let model: NotchViewModel

    @AppStorage(SettingsKey.notchStyle) private var style = SettingsDefault.notchStyle
    @AppStorage(SettingsKey.glassStrength) private var glassStrength = SettingsDefault.glassStrength
    @AppStorage(SettingsKey.albumTint) private var albumTint = SettingsDefault.albumTint

    private enum NotchRadius {
        static let closedTop: CGFloat = 6
        static let closedBottom: CGFloat = 10
        static let openTop: CGFloat = 19
        static let openBottom: CGFloat = Radius.xl
    }

    var body: some View {
        let isOpen = model.isOpen
        let isPill = model.outline == .pill
        let ears = isOpen ? nil : model.activity.ears
        let earWidth = isOpen ? 0 : model.activity.earWidth
        let notch = model.notchSize
        let topRadius = isPill ? 0 : (isOpen ? NotchRadius.openTop : NotchRadius.closedTop)
        let bottomRadius = isPill
            ? (isOpen ? Radius.xl : notch.height / 2)
            : (isOpen ? NotchRadius.openBottom : NotchRadius.closedBottom)
        let shape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, isPill: isPill)
        let topGap = isPill ? NotchLayout.pillGap : 0

        let size: CGSize = isOpen
            ? CGSize(
                width: max(model.openSize.width, notch.width + topRadius * 2),
                height: model.openSize.height - topGap
            )
            : CGSize(
                width: notch.width + earWidth * 2 + topRadius * 2,
                height: notch.height + (earWidth > 0 ? model.activity.earDrop : 0)
            )
        let usesGlass = isOpen && style == .glass

        ZStack(alignment: .top) {
            // Closed: a plain black shape that blends with the hardware notch. No blur
            // while closed, so the closed notch costs nothing to draw.
            shape.fill(.black).opacity(usesGlass ? 0 : 1)

            if isOpen {
                GlassPanel(
                    shape: shape,
                    style: style,
                    strength: glassStrength,
                    neckHeight: isPill ? 0 : notch.height,
                    accent: accent
                )
                .transition(.opacity)

                OpenNotchContent(model: model, accent: accent)
                    .padding(.top, NotchLayout.contentTopInset(outline: model.outline, notchHeight: notch.height))
                    .padding(.horizontal, topRadius + 18)
                    .padding(.bottom, Space.l)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(.easeOut(duration: 0.18))
                    )
            } else if let ears, earWidth > 0 {
                EarsView(content: ears, activity: model.activity, notchSize: notch, earWidth: earWidth)
                    .padding(.horizontal, topRadius)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)).animation(Motion.quick))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            guard !isOpen else { return }
            // A notification: go straight to its app.
            if case .live(let item) = ears, item.source == .notification, item.appPID != nil {
                model.activity.live.activate(item)
            } else {
                // Click-to-open; also skips the hover delay.
                model.open()
            }
        }
        // Files dropped outside the drop zones go to the shelf.
        .dropDestination(for: URL.self) { urls, _ in
            model.activity.shelf.add(urls)
            model.show(.shelf)
            model.dragChanged([])
            return !urls.isEmpty
        }
        // A small bump while the cursor is on the closed notch.
        .scaleEffect(!isOpen && model.isHovering ? CGSize(width: 1.04, height: 1.1) : CGSize(width: 1, height: 1), anchor: .top)
        .shadow(color: .black.opacity(isOpen ? 0.45 : 0), radius: 14, y: 6)
        .padding(.top, topGap)
        .offset(x: model.horizontalOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Album colour while something is playing, graphite otherwise. Glass style only.
    private var accent: Color? {
        guard albumTint, style == .glass else { return nil }
        guard model.activity.nowPlaying != nil, let accent = model.activity.accent else {
            return AccentColor.graphite.color
        }
        return accent.color
    }
}
