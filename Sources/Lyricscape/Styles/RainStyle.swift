import AppKit
import LyricscapeCore

/// Words fall from the top as they're sung, spinning a little, land with a squash
/// and pile up in columns; when the line is over the pile dissolves away.
@MainActor
final class RainStyle: LyricStyle {
    static let id = "rain"
    static let displayName = "Rain"
    static let summary = "Words fall and pile up"

    private let root: CALayer
    private var groups: [Int: RainLine] = [:]
    private var key = ""

    /// Seconds after a line ends that its pile dissolves over.
    private static let dissolve = 1.4

    init(root: CALayer) {
        self.root = root
    }

    func reset() {
        for g in groups.values { g.container.removeFromSuperlayer() }
        groups.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let layoutKey = "\(frame.trackKey)|\(frame.size)|\(frame.settings.hashKey)"
        if layoutKey != key {
            reset()
            key = layoutKey
        }
        let visible = StyleKit.visibleLines(frame, before: 1, lead: 0, tail: Self.dissolve / frame.settings.speed)
        for (i, g) in groups where !visible.contains(i) {
            g.container.removeFromSuperlayer()
            groups[i] = nil
        }
        for i in visible {
            let g = groups[i] ?? {
                let made = RainLine(line: frame.document.lines[i], lineIndex: i, frame: frame)
                root.addSublayer(made.container)
                return made
            }()
            groups[i] = g
            g.update(frame, dissolve: Self.dissolve)
        }
    }
}

@MainActor
private final class RainLine {
    struct Drop {
        let layer: CATextLayer
        let x: CGFloat
        let landY: CGFloat
        let spin: CGFloat
        let tilt: CGFloat
    }

    let container = CALayer()
    private let line: LyricLine
    private let lineIndex: Int
    private var drops: [Drop] = []
    private let top: CGFloat
    private let fallDistance: CGFloat

    init(line: LyricLine, lineIndex: Int, frame: LyricFrame) {
        self.line = line
        self.lineIndex = lineIndex
        let s = frame.settings
        let area = frame.safeArea(margin: 0.05)
        container.frame = CGRect(origin: .zero, size: frame.size)
        var rng = SeededRandom("\(frame.trackKey)#rain#\(lineIndex)")
        let keywords = KeywordPicker.keywords(in: line.words.map(\.text))
        let base = min(frame.size.width, frame.size.height) * 0.05 * s.sizeScale

        // Columns: fewer than the words so they stack, spread by the density setting.
        let columns = max(3, Int(Double(line.words.count) * 0.7 / s.spread.clamped(0.6, 1.6)))
        let columnWidth = area.width / CGFloat(columns)
        var order = Array(0..<columns)
        order.shuffle(using: &rng)
        // Everything that has landed so far: a word comes to rest on the highest
        // thing beneath it, so wide words stack rather than overlap.
        var landed: [CGRect] = []

        // Start fully on screen: a word is sung the moment it appears.
        top = area.minY + base
        fallDistance = area.maxY - top
        for (k, word) in line.words.enumerated() {
            let isKey = keywords.contains(k)
            let font = s.font(size: isKey ? base * 1.5 : base, weight: isKey ? .heavy : .bold)
            let text = StyleKit.text(word.text, font: font, color: isKey ? s.theme.accent : s.theme.text)
            let layer = StyleKit.textLayer(text, scale: frame.scale, glow: s.theme.glow, glowRadius: base * 0.25 * s.glow)
            layer.opacity = 0
            container.addSublayer(layer)
            let column = order[k % columns]
            let size = layer.bounds.size
            let jitter = CGFloat.random(in: -0.25...0.25, using: &rng) * max(0, columnWidth - size.width)
            let x = min(area.maxX - size.width / 2, max(area.minX + size.width / 2,
                                                         area.minX + columnWidth * (CGFloat(column) + 0.5) + jitter))
            let span = (x - size.width / 2)...(x + size.width / 2)
            let floor = landed.filter { span.overlaps($0.minX...$0.maxX) }.map(\.minY).min() ?? area.maxY
            let landY = max(top, floor - size.height / 2 + size.height * 0.08)
            landed.append(CGRect(x: span.lowerBound, y: landY - size.height / 2, width: size.width, height: size.height * 0.92))
            drops.append(Drop(layer: layer, x: x, landY: landY,
                              spin: CGFloat.random(in: -0.6...0.6, using: &rng),
                              tilt: CGFloat.random(in: -0.07...0.07, using: &rng)))
        }
    }

    func update(_ frame: LyricFrame, dissolve: Double) {
        let t = frame.time, s = frame.settings
        let fallTime = 1.25 / s.speed
        let gravity = 2 * Double(fallDistance) / (fallTime * fallTime)
        let gone = Ease.clamp01((t - line.end) * s.speed / dissolve)

        for (k, drop) in drops.enumerated() {
            let word = line.words[k]
            let age = t - word.start
            guard age >= 0 else {
                drop.layer.opacity = 0
                continue
            }
            let fallen = CGFloat(0.5 * gravity * age * age)
            let landed = top + fallen >= drop.landY
            var y = min(top + fallen, drop.landY)
            var rotation = drop.spin * CGFloat(1 - Ease.clamp01(age / fallTime)) + drop.tilt
            var scaleX: CGFloat = 1, scaleY: CGFloat = 1
            if landed {
                // Squash on impact, settling over a quarter second.
                let impact = age - sqrt(2 * Double(drop.landY - top) / gravity)
                let squash = CGFloat(exp(-impact * 14) * 0.22)
                scaleY = 1 - squash
                scaleX = 1 + squash * 0.6
                rotation = drop.tilt
            }
            // Dissolve: sink and fade once the line is done.
            y += CGFloat(gone * gone) * drop.layer.bounds.height * 1.5
            let isCurrent = frame.position.lineIndex == lineIndex && frame.position.wordIndex == k
            var m = CATransform3DMakeTranslation(drop.x, y, 0)
            m = CATransform3DRotate(m, rotation, 0, 0, 1)
            drop.layer.transform = CATransform3DScale(m, scaleX * (1 + 0.04 * frame.audio.beat), scaleY, 1)
            drop.layer.opacity = Float(Ease.clamp01(age / 0.1) * (1 - gone) * (isCurrent ? 1 : 0.85))
            drop.layer.shadowRadius = drop.layer.bounds.height * (isCurrent ? 0.45 : 0.2) * s.glow
        }
    }
}
