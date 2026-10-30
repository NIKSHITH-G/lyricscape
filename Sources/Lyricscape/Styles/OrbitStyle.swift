import AppKit
import LyricscapeCore

/// Words circle the centre of the screen: each line forms a slowly rotating ring,
/// and older rings drift outward and fade, around a glowing core that pulses.
@MainActor
final class OrbitStyle: LyricStyle {
    static let id = "orbit"
    static let displayName = "Orbit"
    static let summary = "Rings of words circle the centre"

    private let root: CALayer
    private let core = CALayer()
    private var rings: [Int: OrbitRing] = [:]
    private var key = ""

    /// Seconds a ring keeps drifting outward after its line ends.
    private static let tail = 3.5

    init(root: CALayer) {
        self.root = root
        root.addSublayer(core)
    }

    func reset() {
        for r in rings.values { r.container.removeFromSuperlayer() }
        rings.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let s = frame.settings
        let layoutKey = "\(frame.trackKey)|\(frame.size)|\(s.hashKey)"
        if layoutKey != key {
            reset()
            key = layoutKey
            core.backgroundColor = s.theme.accent.cgColor
            core.shadowColor = s.theme.glow.cgColor
            core.shadowOpacity = 1
            core.shadowOffset = .zero
        }
        let t = frame.time
        let area = frame.safeArea(margin: 0.04)
        let center = CGPoint(x: area.midX, y: area.midY)
        let unit = min(area.width, area.height)

        let visible = StyleKit.visibleLines(frame, before: 3, lead: 0.3, tail: Self.tail)
        for (i, r) in rings where !visible.contains(i) {
            r.container.removeFromSuperlayer()
            rings[i] = nil
        }
        var hit = 0.0
        for i in visible {
            let ring = rings[i] ?? {
                let made = OrbitRing(line: frame.document.lines[i], lineIndex: i, frame: frame, unit: unit)
                root.insertSublayer(made.container, below: core)
                return made
            }()
            rings[i] = ring
            hit = max(hit, ring.update(frame, center: center, unit: unit, tail: Self.tail))
        }

        // The core: breathes slowly, flares on each word and with the bass.
        let d = unit * 0.035 * (1 + 0.5 * hit + 0.35 * frame.audio.bass) * (1 + 0.05 * sin(t * 1.7))
        core.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        core.cornerRadius = d / 2
        core.position = center
        core.shadowRadius = d * (1.2 + 1.5 * hit) * s.glow
        core.shadowPath = CGPath(ellipseIn: core.bounds, transform: nil)
    }
}

@MainActor
private final class OrbitRing {
    let container = CALayer()
    private let orbit = CAShapeLayer()
    private let line: LyricLine
    private let lineIndex: Int
    private var labels: [CATextLayer] = []
    /// Angle of each word around the ring, relative to the ring's rotation.
    private var angles: [CGFloat] = []
    private let startAngle: CGFloat
    private let direction: CGFloat
    private let baseRadius: CGFloat

    init(line: LyricLine, lineIndex: Int, frame: LyricFrame, unit: CGFloat) {
        self.line = line
        self.lineIndex = lineIndex
        let s = frame.settings
        container.frame = CGRect(origin: .zero, size: frame.size)
        orbit.frame = container.bounds
        orbit.fillColor = nil
        orbit.strokeColor = s.theme.line.withAlpha(0.25).cgColor
        orbit.lineWidth = 1
        container.addSublayer(orbit)

        var rng = SeededRandom("\(frame.trackKey)#orbit#\(lineIndex)")
        let keywords = KeywordPicker.keywords(in: line.words.map(\.text))
        let base = unit * 0.042 * s.sizeScale
        var widths: [CGFloat] = []
        for (k, word) in line.words.enumerated() {
            let isKey = keywords.contains(k)
            let font = s.font(size: isKey ? base * 1.45 : base, weight: isKey ? .heavy : .semibold)
            let label = StyleKit.textLayer(StyleKit.text(word.text, font: font, color: isKey ? s.theme.accent : s.theme.text),
                                           scale: frame.scale, glow: s.theme.glow, glowRadius: base * 0.3 * s.glow)
            label.opacity = 0
            container.addSublayer(label)
            labels.append(label)
            widths.append(label.bounds.width + base * 0.6)
        }
        // Spread words round the ring in reading order (clockwise from the top left),
        // taking an arc proportional to their width. Long lines get a bigger ring so
        // they never wrap past three-quarters of the way round.
        let total = widths.reduce(0, +)
        baseRadius = min(unit * 0.42, max(unit * 0.2 * CGFloat(s.spread), total / (1.5 * .pi)))
        let arc = min(1.9 * .pi, max(.pi * 0.7, total / baseRadius))
        var angle: CGFloat = 0
        for w in widths {
            angles.append(angle + w / total * arc / 2)
            angle += w / total * arc
        }
        startAngle = -.pi / 2 - arc / 2 + CGFloat.random(in: -0.4...0.4, using: &rng)
        direction = lineIndex.isMultiple(of: 2) ? 1 : -1
    }

    /// Returns how hard the current word is hitting (for the core's flare).
    func update(_ frame: LyricFrame, center: CGPoint, unit: CGFloat, tail: Double) -> Double {
        let t = frame.time, s = frame.settings
        let life = (t - line.start) * s.speed
        // Drift outward over time, faster once the line is over, clearing room for the next ring.
        let over = max(0, (t - line.end) * s.speed)
        // New rings bloom out from inside; finished rings jump clear, then keep drifting.
        let bloom = CGFloat(0.72 + 0.28 * Ease.outCubic(life / 0.8))
        let clear = CGFloat(0.16 * Ease.outCubic(over / 0.6) + 0.05 * over)
        let radius = baseRadius * bloom + unit * (0.02 * CGFloat(max(0, life)) + clear)
        let fade = 1 - Ease.clamp01((t - line.end) / tail)
        container.opacity = Float(fade * fade)
        let rotation = startAngle + direction * CGFloat(0.1 * max(0, life))

        orbit.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius),
                            transform: nil)
        var hit = 0.0
        for (k, label) in labels.enumerated() {
            let word = line.words[k]
            let age = (t - word.start) * s.speed
            let a = rotation + angles[k]
            label.position = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            guard age >= 0 else {
                label.opacity = 0
                continue
            }
            let isCurrent = frame.position.lineIndex == lineIndex && frame.position.wordIndex == k
            let flash = exp(-age * 4)
            if isCurrent { hit = max(hit, flash) }
            let pop = Ease.outBack(age / 0.3)
            label.transform = CATransform3DMakeScale(pop * (1 + 0.15 * flash), pop * (1 + 0.15 * flash), 1)
            label.opacity = Float(Ease.clamp01(age / 0.12) * (isCurrent ? 1 : 0.8))
            label.shadowRadius = label.bounds.height * (0.25 + 0.5 * flash) * s.glow
        }
        return hit
    }
}
