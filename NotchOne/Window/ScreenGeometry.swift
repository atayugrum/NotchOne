import AppKit

/// Where the notch is on a screen, in AppKit screen coordinates (origin bottom-left).
struct NotchMetrics: Equatable, Sendable {
    let notchRect: CGRect
    let hasHardwareNotch: Bool
}

/// Sizes used for the open state and the window that hosts it.
enum NotchLayout {
    /// Default open size (Settings → Appearance → Size: Regular).
    static let openSize = PanelSize.regular.openSize
    /// The window is sized for the largest open size (Settings), so switching tabs
    /// or changing the size needs no rebuild.
    static let maxOpenSize = CGSize(width: PanelSize.large.openSize.width, height: 420)

    /// Compact mode: one row, no tab bar.
    static let compactSize = CGSize(width: 460, height: 112)

    /// Settings: a list of pages on the left, the page on the right.
    static func settingsSize(base: CGSize) -> CGSize {
        CGSize(width: max(base.width, 680), height: maxOpenSize.height)
    }

    /// The tour: the tab bar it points at, and room for a step's text and buttons.
    static func tourSize(base: CGSize) -> CGSize {
        CGSize(width: max(base.width, 640), height: 380)
    }

    /// System: three gauges and a row of device batteries.
    static let systemHeight: CGFloat = 250

    /// Search and Translate: room for a list of results, or a text and its translation.
    static let typingHeight: CGFloat = 300

    /// The open size a tab asks for, at least the chosen size.
    static func size(for tab: NotchTab, base: CGSize) -> CGSize {
        switch tab {
        case .search, .translate, .notes: CGSize(width: base.width, height: max(base.height, typingHeight))
        case .system: CGSize(width: base.width, height: max(base.height, systemHeight))
        default: base
        }
    }
    /// Gap between the screen's top edge and a pill.
    static let pillGap: CGFloat = 3
    /// Space above the header: a plain margin on a pill, or below the black neck on a notch.
    static let pillTopInset = Space.m
    static let neckGap: CGFloat = 6

    /// Open sizes are measured for the pill. A notch spends its top on the black neck,
    /// so it grows by the difference: both outlines get the same content area, and
    /// tabs lay out the same way on either.
    static func openSize(_ size: CGSize, outline: NotchOutline, notchHeight: CGFloat) -> CGSize {
        guard outline == .notch else { return size }
        let extra = max(0, contentTopInset(outline: .notch, notchHeight: notchHeight) - pillGap - pillTopInset)
        return CGSize(width: size.width, height: size.height + extra)
    }

    /// Distance from the top of the shape to the header.
    static func contentTopInset(outline: NotchOutline, notchHeight: CGFloat) -> CGFloat {
        outline == .pill ? pillTopInset : notchHeight + neckGap
    }

    /// Room around the open shape so its shadow is not clipped by the window.
    static let shadowPadding: CGFloat = 24
    /// Size used to draw a notch on displays that have none.
    static let fallbackNotchWidth: CGFloat = 190
    static let fallbackNotchHeight: CGFloat = 24
}

/// Pure geometry math. Kept free of `NSScreen` so it can be unit tested.
enum ScreenGeometry {

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - safeTopInset: `NSScreen.safeAreaInsets.top` (0 when there is no notch).
    ///   - leftAuxWidth: width of `NSScreen.auxiliaryTopLeftArea`, if any.
    ///   - rightAuxWidth: width of `NSScreen.auxiliaryTopRightArea`, if any.
    ///   - menuBarHeight: height of the menu bar, used for the fallback notch.
    static func metrics(
        screenFrame: CGRect,
        safeTopInset: CGFloat,
        leftAuxWidth: CGFloat?,
        rightAuxWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        if safeTopInset > 0, let left = leftAuxWidth, let right = rightAuxWidth {
            let width = screenFrame.width - left - right
            if width > 0 {
                let rect = CGRect(
                    x: screenFrame.minX + left,
                    y: screenFrame.maxY - safeTopInset,
                    width: width,
                    height: safeTopInset
                )
                return NotchMetrics(notchRect: rect, hasHardwareNotch: true)
            }
        }

        let height = menuBarHeight > 0 ? menuBarHeight : NotchLayout.fallbackNotchHeight
        let width = NotchLayout.fallbackNotchWidth
        let rect = CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
        return NotchMetrics(notchRect: rect, hasHardwareNotch: false)
    }

    /// Window frame: centered on the notch, top edge on the screen's top edge,
    /// big enough for the open state plus shadow padding, clamped inside the screen.
    static func panelFrame(notchRect: CGRect, screenFrame: CGRect) -> CGRect {
        let padding = NotchLayout.shadowPadding
        let contentWidth = max(NotchLayout.maxOpenSize.width, notchRect.width)
        let width = min(contentWidth + padding * 2, screenFrame.width)
        // Tall enough for the largest size on either outline.
        let tallest = NotchLayout.openSize(NotchLayout.maxOpenSize, outline: .notch, notchHeight: notchRect.height)
        let height = tallest.height + padding

        var x = notchRect.midX - width / 2
        x = min(max(x, screenFrame.minX), screenFrame.maxX - width)

        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Area that counts as "on the notch" for hover purposes.
    /// Extends above the screen top so a cursor pinned to the top edge still counts.
    /// `earWidth` widens the closed area when side indicators are showing.
    static func hoverRect(
        notchRect: CGRect,
        isOpen: Bool,
        panelFrame: CGRect,
        earWidth: CGFloat = 0,
        openSize: CGSize = NotchLayout.openSize
    ) -> CGRect {
        if isOpen {
            let openWidth = max(openSize.width, notchRect.width)
            return CGRect(
                x: notchRect.midX - openWidth / 2,
                y: panelFrame.maxY - openSize.height,
                width: openWidth,
                height: openSize.height + 4
            )
        }
        let margin = 12 + max(0, earWidth)
        return CGRect(
            x: notchRect.minX - margin,
            y: notchRect.minY - 6,
            width: notchRect.width + margin * 2,
            height: notchRect.height + 6 + 4
        )
    }
}

extension NSScreen {
    var notchMetrics: NotchMetrics {
        ScreenGeometry.metrics(
            screenFrame: frame,
            safeTopInset: safeAreaInsets.top,
            leftAuxWidth: auxiliaryTopLeftArea?.width,
            rightAuxWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }

    var hasHardwareNotch: Bool { safeAreaInsets.top > 0 }
}
