import AppKit
import SwiftUI

/// Colours for live activities.
enum LiveStyle {
    /// Claude's coral.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)

    static func tint(for item: LiveActivity) -> Color {
        switch item.status {
        case .meeting(_, _, let muted): muted ? .red : .white
        case .needsYou: claude
        case .failed: .red
        case .succeeded: .green
        case .info: .white
        case .running: item.source == .claude ? claude : .white
        }
    }

    /// What's going on, in words (the second line on Home).
    static func subtitle(for item: LiveActivity) -> String {
        switch item.status {
        case .meeting(let mic, let camera, let muted):
            if muted {
                String(localized: "Microphone muted for every app")
            } else if mic && camera {
                String(localized: "Microphone and camera in use")
            } else if camera {
                String(localized: "Camera in use")
            } else {
                String(localized: "Microphone in use")
            }
        case .running: item.source == .claude ? String(localized: "Claude is working") : (item.detail ?? String(localized: "Running"))
        case .succeeded: item.detail ?? String(localized: "Finished")
        case .failed: item.detail ?? String(localized: "Failed")
        case .needsYou: item.detail ?? String(localized: "Claude needs your input")
        case .info: item.detail ?? String(localized: "Message")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }
}

/// Right side of the closed notch for a live activity.
struct LiveTrailing: View {
    let item: LiveActivity

    var body: some View {
        switch item.status {
        case .meeting(let mic, let camera, let muted):
            MeetingIndicators(mic: mic, camera: camera, muted: muted)
        case .running(let fraction):
            if let fraction {
                ProgressRing(fraction: fraction, tint: LiveStyle.tint(for: item))
                    .frame(width: 14, height: 14)
            } else {
                SpinnerView(tint: NSColor(LiveStyle.tint(for: item)))
                    .frame(width: 14, height: 14)
            }
        case .succeeded, .failed:
            Text(item.duration.map(LiveStyle.duration) ?? "")
                .font(Typo.number(12))
                .foregroundStyle(LiveStyle.tint(for: item))
        case .needsYou, .info:
            Text(item.title)
                .font(Typo.captionStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Space.xs)
        }
    }
}

/// Progress as a thin ring. Static; it only redraws when the fraction changes.
struct ProgressRing: View {
    let fraction: Double
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.2), value: fraction)
    }
}

/// Indeterminate spinner run by Core Animation, so the app itself stays idle.
struct SpinnerView: NSViewRepresentable {
    let tint: NSColor

    func makeNSView(context: Context) -> SpinnerNSView { SpinnerNSView() }

    func updateNSView(_ view: SpinnerNSView, context: Context) {
        view.tint = tint
    }
}

final class SpinnerNSView: NSView {
    private let arc = CAShapeLayer()
    private static let animationKey = "spin"

    var tint: NSColor = .white {
        didSet { arc.strokeColor = tint.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineWidth = 2.5
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.7
        arc.strokeColor = tint.cgColor
        layer?.addSublayer(arc)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            arc.removeAnimation(forKey: Self.animationKey)
        } else if arc.animation(forKey: Self.animationKey) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -Double.pi * 2
            spin.duration = 0.9
            spin.repeatCount = .infinity
            arc.add(spin, forKey: Self.animationKey)
        }
    }
}

/// Draggable thumbnail of a new screenshot or download.
struct FileThumbnail: View {
    let url: URL
    let image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            .help("Drag into another app")
    }
}

/// Left ear for a live activity: the app's icon when there is one (meeting mode),
/// otherwise the activity's symbol.
struct LiveLeading: View {
    let item: LiveActivity

    var body: some View {
        if let bundleID = item.appBundleID, let icon = AppInfo.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
        } else if case .meeting = item.status {
            Image(systemName: "record.circle")
                .font(Typo.icon(14))
                .foregroundStyle(.red)
        } else {
            Image(systemName: item.symbol)
                .font(Typo.icon(13))
                .foregroundStyle(LiveStyle.tint(for: item))
        }
    }
}

/// Mic (muted or not) and camera state for meeting mode.
struct MeetingIndicators: View {
    let mic: Bool
    let camera: Bool
    let muted: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            if camera {
                Image(systemName: "video.fill")
                    .foregroundStyle(.green)
            }
            if mic || muted {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(muted ? .red : .orange)
            }
        }
        .font(Typo.icon(12))
    }
}
