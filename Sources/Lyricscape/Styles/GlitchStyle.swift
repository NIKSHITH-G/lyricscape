import AppKit
import LyricscapeCore

/// Each word hits with chromatic aberration (red/cyan copies splitting apart), jitter,
/// a displaced slice and flicker; scanlines flash on every hit.
@MainActor
final class GlitchStyle: LyricStyle {
    static let id = "glitch"
    static let displayName = "Glitch"
    static let summary = "RGB split, jitter and scanlines"

    private let root: CALayer
    private let scanlines = CAReplicatorLayer()
    private var groups: [Int: GlitchLine] = [:]
    private var key = ""

    init(root: CALayer) {
        self.root = root
        root.addSublayer(scanlines)
    }

    func reset() {
        for g in groups.values { g.container.removeFromSuperlayer() }
        groups.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let s = frame.settings
        let layoutKey = "\(frame.trackKey)|\(frame.size)|\(s.hashKey)"
        if layoutKey != key {
            reset()
            key = layoutKey
            buildScanlines(frame)
        }
        let visible = StyleKit.visibleLines(frame, before: 0, lead: 0, tail: 0.3)
        for (i, g) in groups where !visible.contains(i) {
            g.container.removeFromSuperlayer()
            groups[i] = nil
        }
        var hit = 0.0
        for i in visible {
            let g = groups[i] ?? {
                let made = GlitchLine(line: frame.document.lines[i], lineIndex: i, frame: frame)
                root.insertSublayer(made.container, below: scanlines)
                return made
            }()
            groups[i] = g
            hit = max(hit, g.update(frame))
        }
        scanlines.opacity = Float(0.25 + 0.75 * max(hit, frame.audio.beat * 0.7))
    }

    private func buildScanlines(_ frame: LyricFrame) {
        scanlines.sublayers?.forEach { $0.removeFromSuperlayer() }
        scanlines.frame = CGRect(origin: .zero, size: frame.size)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: 1)
        line.backgroundColor = frame.opaqueBackground ? CGColor(gray: 0, alpha: 0.45)
            : frame.settings.theme.glow.withAlpha(0.06).cgColor
        scanlines.addSublayer(line)
        scanlines.instanceCount = Int(frame.size.height / 3)
        scanlines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
    }
}

@MainActor
private final class GlitchLine {
    struct Word {
        let main: CATextLayer
        let red: CATextLayer
        let cyan: CATextLayer
        let slice: CATextLayer
        let sliceMask: CALayer
        let center: CGPoint
    }

    let container = CALayer()
    private let line: LyricLine
    private let lineIndex: Int
    private var words: [Word] = []

    init(line: LyricLine, lineIndex: Int, frame: LyricFrame) {
        self.line = line
        self.lineIndex = lineIndex
        let s = frame.settings
        container.frame = CGRect(origin: .zero, size: frame.size)
        let area = frame.safeArea(margin: 0.08)
        let fontSize = min(frame.size.width, frame.size.height) * 0.075 * s.sizeScale
        let font = s.font(size: fontSize, weight: .black)

        let texts = line.words.map { StyleKit.text($0.text.uppercased(), font: font, color: s.theme.accent) }
        let sizes = texts.map(StyleKit.measure)
        let flow = StyleKit.flow(sizes, maxWidth: area.width * 0.9, spacing: fontSize * 0.35, lineSpacing: fontSize * 0.15)
        let origin = frame.anchored(flow.size, in: area)

        for (k, word) in line.words.enumerated() {
            let display = word.text.uppercased()
            func copy(_ color: RGBA) -> CATextLayer {
                let layer = StyleKit.textLayer(StyleKit.text(display, font: font, color: color), scale: frame.scale)
                layer.compositingFilter = "screenBlendMode"
                layer.opacity = 0
                container.addSublayer(layer)
                return layer
            }
            let red = copy(RGBA(1, 0.1, 0.25))
            let cyan = copy(RGBA(0.1, 0.9, 1))
            let main = StyleKit.textLayer(texts[k], scale: frame.scale, glow: s.theme.glow, glowRadius: fontSize * 0.15 * s.glow)
            main.opacity = 0
            container.addSublayer(main)
            let slice = StyleKit.textLayer(texts[k], scale: frame.scale)
            let sliceMask = CALayer()
            sliceMask.backgroundColor = CGColor.black
            slice.mask = sliceMask
            slice.opacity = 0
            container.addSublayer(slice)
            let center = CGPoint(x: origin.x + flow.centers[k].x, y: origin.y + flow.centers[k].y)
            words.append(Word(main: main, red: red, cyan: cyan, slice: slice, sliceMask: sliceMask, center: center))
        }
    }

    /// Returns the strongest current hit (for the scanline flash).
    func update(_ frame: LyricFrame) -> Double {
        let t = frame.time, s = frame.settings
        // Glitches change 15×/s — a choppy, digital rhythm rather than smooth motion.
        let tick = UInt64(max(0, t * 15))
        let out = Ease.clamp01((t - line.end) / 0.3)
        var hit = 0.0

        for (k, w) in words.enumerated() {
            let word = line.words[k]
            let age = (t - word.start) * s.speed
            var rng = SeededRandom(seed: tick &* 31 &+ UInt64(k) &* 7919 &+ UInt64(lineIndex))
            guard age >= 0 else {
                // Unsung words wait as faint ghosts so the line can be read ahead.
                w.main.position = w.center
                w.main.opacity = Float(0.12 * (1 - out))
                for layer in [w.red, w.cyan, w.slice] { layer.opacity = 0 }
                continue
            }
            let flash = exp(-age * 7) + 0.6 * frame.audio.beat * exp(-age * 0.5)
            hit = max(hit, exp(-age * 7))
            // Flicker in on the hit, flicker out at the end of the line.
            let flickerIn = age < 0.12 && Bool.random(using: &rng) ? 0.3 : 1.0
            let flickerOut = out > 0 && Bool.random(using: &rng) ? 0.0 : 1 - out
            let visible = flickerIn * flickerOut

            let jitter = CGPoint(x: CGFloat.random(in: -1...1, using: &rng) * 6 * flash,
                                 y: CGFloat.random(in: -1...1, using: &rng) * 3 * flash)
            let split = 1.5 + 18 * flash
            let pos = CGPoint(x: w.center.x + jitter.x, y: w.center.y + jitter.y)
            w.main.position = pos
            w.red.position = CGPoint(x: pos.x - split, y: pos.y + CGFloat.random(in: -2...2, using: &rng) * flash)
            w.cyan.position = CGPoint(x: pos.x + split, y: pos.y - CGFloat.random(in: -2...2, using: &rng) * flash)
            w.main.opacity = Float(visible)
            w.red.opacity = Float(visible * min(1, 0.35 + flash))
            w.cyan.opacity = Float(visible * min(1, 0.35 + flash))

            // A horizontal slice of the word, knocked sideways on hits.
            let bounds = w.main.bounds
            // Only in the first instant of a hit, so it reads as a glitch, not a strike-through.
            if age < 0.16 {
                let bandY = CGFloat.random(in: 0...0.6, using: &rng) * bounds.height
                w.sliceMask.frame = CGRect(x: -50, y: bandY, width: bounds.width + 100, height: bounds.height * 0.38)
                let shove = CGFloat.random(in: 0.5...1, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                w.slice.position = CGPoint(x: pos.x + shove * bounds.height * 0.6, y: pos.y)
                w.slice.opacity = Float(visible)
            } else {
                w.slice.opacity = 0
            }
        }
        return hit
    }
}
