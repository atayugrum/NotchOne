import AppKit
import SwiftUI

/// Equalizer bars driven by Core Animation, so the render server animates them and the
/// app itself stays idle. (A SwiftUI timeline cost ~10–20% CPU; a symbol effect ~7%.)
struct AudioBarsView: NSViewRepresentable {
    let isPlaying: Bool
    /// The album colour; white without one.
    var tint: NSColor?

    func makeNSView(context: Context) -> AudioBarsNSView {
        AudioBarsNSView()
    }

    func updateNSView(_ view: AudioBarsNSView, context: Context) {
        view.isPlaying = isPlaying
        view.tint = tint
    }
}

final class AudioBarsNSView: NSView {
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2
    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.36, 0.48]
    private static let animationKey = "bounce"

    private let bars: [CALayer] = AudioBarsNSView.durations.map { _ in CALayer() }

    var tint: NSColor? {
        didSet {
            guard oldValue != tint else { return }
            let color = (tint ?? NSColor.white.withAlphaComponent(0.9)).cgColor
            bars.forEach { $0.backgroundColor = color }
        }
    }

    var isPlaying = false {
        didSet { if oldValue != isPlaying { updateAnimations() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.barWidth * 4 + Self.spacing * 3, height: 14)
    }

    override func layout() {
        super.layout()
        let total = Self.barWidth * CGFloat(bars.count) + Self.spacing * CGFloat(bars.count - 1)
        let startX = (bounds.width - total) / 2 + Self.barWidth / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(x: startX + CGFloat(index) * (Self.barWidth + Self.spacing), y: bounds.midY)
        }
        CATransaction.commit()
        updateAnimations()
    }

    private func updateAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            if isPlaying {
                bar.transform = CATransform3DIdentity
                guard bar.animation(forKey: Self.animationKey) == nil else { continue }
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = 0.3
                animation.toValue = 1.0
                animation.duration = Self.durations[index]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timeOffset = Double(index) * 0.13
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(animation, forKey: Self.animationKey)
            } else {
                bar.removeAnimation(forKey: Self.animationKey)
                bar.transform = CATransform3DMakeScale(1, 0.25, 1)
            }
        }
        CATransaction.commit()
    }
}
