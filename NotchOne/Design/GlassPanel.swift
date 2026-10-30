import SwiftUI

/// Background of the open notch: a solid black "neck" exactly the notch's height that
/// fades into a Liquid Glass body, so the panel looks like it pours out of the notch.
///
/// With Reduce Transparency or the Classic style it is a solid surface instead.
struct GlassPanel<S: Shape>: View {
    let shape: S
    let style: NotchStyle
    /// 0...1, see `AppearanceLogic.glassDarkness`.
    let strength: Double
    /// Height of the solid band at the top. 0 for none.
    let neckHeight: CGFloat
    /// Light colour wash over the glass (album colour), or nil.
    let accent: Color?

    /// How far the neck fades into the glass.
    static var neckFade: CGFloat { 28 }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if style == .classic {
                    shape.fill(.black)
                } else if reduceTransparency {
                    shape.fill(Palette.solid)
                    accentWash
                } else {
                    Color.clear
                        .notchGlass(darkness: AppearanceLogic.glassDarkness(strength: strength), in: shape)
                    accentWash
                }
                if style == .glass, neckHeight > 0 {
                    shape.fill(neckGradient(height: proxy.size.height))
                }
            }
        }
    }

    @ViewBuilder
    private var accentWash: some View {
        if let accent {
            shape.fill(
                LinearGradient(
                    colors: [accent.opacity(0.18), accent.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func neckGradient(height: CGFloat) -> LinearGradient {
        let solidEnd = min(1, neckHeight / max(height, 1))
        let fadeEnd = min(1, (neckHeight + Self.neckFade) / max(height, 1))
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: solidEnd),
                .init(color: .black.opacity(0), location: fadeEnd),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Liquid Glass on macOS 26; a blur of what's behind the window before that.
    @ViewBuilder
    func notchGlass<S: Shape>(darkness: Double, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(.black.opacity(darkness)), in: shape)
        } else {
            background {
                BehindWindowBlur()
                    .overlay(Color.black.opacity(darkness))
                    .clipShape(shape)
            }
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
