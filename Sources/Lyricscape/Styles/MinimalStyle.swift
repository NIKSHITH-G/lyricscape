import AppKit
import LyricscapeCore

/// One soft line at a time, low opacity, tucked in a corner — for when you're working.
/// Uses the Position setting (Centre counts as bottom-left here).
@MainActor
final class MinimalStyle: LyricStyle {
    static let id = "minimal"
    static let displayName = "Minimal"
    static let summary = "One soft line in a corner"

    private let root: CALayer
    private var lines: [Int: FillLineLayer] = [:]
    private var key = ""

    private static let fade = 0.6

    init(root: CALayer) {
        self.root = root
    }

    func reset() {
        for l in lines.values { l.container.removeFromSuperlayer() }
        lines.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let s = frame.settings
        let layoutKey = "\(frame.trackKey)|\(frame.size)|\(s.hashKey)"
        if layoutKey != key {
            reset()
            key = layoutKey
        }
        let t = frame.time
        let visible = StyleKit.visibleLines(frame, before: 0, lead: 0, tail: Self.fade + 0.6)
        for (i, l) in lines where !visible.contains(i) {
            l.container.removeFromSuperlayer()
            lines[i] = nil
        }
        let anchor = s.anchor == .center ? .bottomLeft : s.anchor
        let area = frame.safeArea(margin: 0.035)
        for i in visible {
            let line = frame.document.lines[i]
            let layer = lines[i] ?? {
                let fontSize = min(frame.size.width, frame.size.height) * 0.024 * s.sizeScale
                var font = s.font(size: fontSize, weight: .medium)
                let width = StyleKit.measure(StyleKit.text(line.text, font: font, color: s.theme.text)).width
                if width > area.width * 0.6 { font = s.font(size: fontSize * area.width * 0.6 / width, weight: .medium) }
                let made = FillLineLayer(line: line, font: font, baseColor: s.theme.text.withAlpha(0.45),
                                         fillColor: s.theme.text.withAlpha(0.9), glow: s.theme.glow,
                                         glowRadius: fontSize * 0.25 * s.glow, alignment: .left, scale: frame.scale)
                made.container.anchorPoint = .zero
                root.addSublayer(made.container)
                return made
            }()
            lines[i] = layer
            var settings = frame
            settings.settings.anchor = anchor
            let origin = settings.anchored(layer.size, in: area)
            // Drift up slightly on the way in and out.
            let fadeIn = Ease.outCubic((t - line.start) / Self.fade)
            let fadeOut = Ease.clamp01((t - line.end - 0.6) / Self.fade)
            layer.container.position = CGPoint(x: origin.x, y: origin.y + CGFloat(1 - fadeIn + fadeOut) * layer.size.height * 0.5)
            layer.container.opacity = Float(fadeIn * (1 - fadeOut) * 0.75)
            layer.setFill(time: t)
        }
    }
}
