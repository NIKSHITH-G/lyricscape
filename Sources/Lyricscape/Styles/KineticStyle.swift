import AppKit
import LyricscapeCore

/// Big bold words slam in one at a time — scale, spin, motion-blur trails and a
/// screen shake — with the line so far running small along the bottom.
@MainActor
final class KineticStyle: LyricStyle {
    static let id = "kinetic"
    static let displayName = "Kinetic"
    static let summary = "Words slam in, music-video style"

    private let root: CALayer
    private let stage = CALayer()
    private let context = CATextLayer()
    private var words: [String: KineticWord] = [:]
    private var contextKey = ""
    private var trackKey = ""

    /// Seconds a word takes to slam in; and to blow away when the next one lands.
    private static let entry = 0.22
    private static let exit = 0.2

    init(root: CALayer) {
        self.root = root
        root.addSublayer(stage)
        root.addSublayer(context)
        context.alignmentMode = .center
    }

    func reset() {
        for w in words.values { w.remove() }
        words.removeAll()
        context.string = nil
        contextKey = ""
    }

    func update(_ frame: LyricFrame) {
        if frame.trackKey != trackKey {
            reset()
            trackKey = frame.trackKey
        }
        let t = frame.time, s = frame.settings
        let bounds = CGRect(origin: .zero, size: frame.size)
        stage.frame = bounds
        let area = frame.safeArea(margin: 0.08)

        // Active word, plus the one before it while it blows away.
        var wanted: [(key: String, word: LyricWord, line: Int, index: Int, exitAt: Double?)] = []
        for i in StyleKit.visibleLines(frame, before: 1, lead: 0, tail: Self.exit) {
            let line = frame.document.lines[i]
            for (k, word) in line.words.enumerated() where t >= word.start {
                let next = k + 1 < line.words.count ? line.words[k + 1].start : line.end
                guard t < next + Self.exit / s.speed else { continue }
                wanted.append(("\(i)#\(k)", word, i, k, t >= next ? next : nil))
            }
        }
        let keys = Set(wanted.map(\.key))
        for (key, w) in words where !keys.contains(key) {
            w.remove()
            words[key] = nil
        }

        var shake = 0.0
        for item in wanted {
            let line = frame.document.lines[item.line]
            let w = words[item.key] ?? {
                let isKey = KeywordPicker.keywords(in: line.words.map(\.text)).contains(item.index)
                let made = KineticWord(text: item.word.text, isKeyword: isKey, frame: frame, area: area,
                                       seed: SeededRandom.seed("\(frame.trackKey)#\(item.key)"))
                stage.addSublayer(made.container)
                return made
            }()
            words[item.key] = w
            let age = (t - item.word.start) * s.speed
            let exitAge = item.exitAt.map { (t - $0) * s.speed }
            w.update(age: age, exitAge: exitAge, entry: Self.entry, exit: Self.exit, beat: frame.audio.beat, glow: s.glow)
            if exitAge == nil { shake = max(shake, exp(-age * 14)) }
        }

        // Screen shake on each hit (and on the beat, when listening to the music).
        let amount = (16 * shake + 6 * frame.audio.beat) * s.glow.clamped(0.5, 1.5)
        var rng = SeededRandom(seed: UInt64(max(0, t * 60)))
        stage.transform = CATransform3DMakeTranslation(CGFloat.random(in: -1...1, using: &rng) * amount,
                                                       CGFloat.random(in: -1...1, using: &rng) * amount, 0)

        updateContext(frame, area: area)
    }

    /// The current line, small along the bottom, sung words bright.
    private func updateContext(_ frame: LyricFrame, area: CGRect) {
        guard let i = frame.position.lineIndex else {
            context.opacity = 0
            contextKey = ""
            return
        }
        let line = frame.document.lines[i]
        let sung = frame.position.wordIndex ?? -1
        let key = "\(frame.trackKey)#\(i)#\(sung)"
        guard key != contextKey else { return }
        contextKey = key
        let s = frame.settings
        let font = s.font(size: min(frame.size.width, frame.size.height) * 0.028 * s.sizeScale, weight: .semibold)
        let text = NSMutableAttributedString()
        for (k, word) in line.words.enumerated() {
            let color = k <= sung ? s.theme.text : s.theme.text.withAlpha(0.35)
            text.append(StyleKit.text((k == 0 ? "" : " ") + word.text, font: font, color: color))
        }
        context.string = text
        context.contentsScale = frame.scale
        context.isWrapped = true
        let height = StyleKit.measure(text).height * 2.2
        context.frame = CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
        context.shadowColor = s.theme.glow.cgColor
        context.shadowOpacity = 0.8
        context.shadowRadius = 6 * s.glow
        context.shadowOffset = .zero
        context.opacity = 1
    }
}

/// One slammed-in word: the text plus three trailing copies that fake motion blur.
@MainActor
private final class KineticWord {
    let container = CALayer()
    private let main: CATextLayer
    private var trails: [CATextLayer] = []
    private let center: CGPoint
    private let startOffset: CGPoint
    private let startRotation: CGFloat
    private let drift: CGFloat

    init(text: String, isKeyword: Bool, frame: LyricFrame, area: CGRect, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let s = frame.settings
        var fontSize = min(frame.size.width, frame.size.height) * (isKeyword ? 0.2 : 0.15) * s.sizeScale
        var font = s.font(size: fontSize, weight: .heavy)
        let display = text.uppercased()
        var width = StyleKit.measure(StyleKit.text(display, font: font, color: s.theme.text)).width
        if width > area.width * 0.92 { // keep long words on screen
            fontSize *= area.width * 0.92 / width
            font = s.font(size: fontSize, weight: .heavy)
            width = area.width * 0.92
        }
        let color = isKeyword ? s.theme.glow : s.theme.accent
        let string = StyleKit.text(display, font: font, color: color)
        main = StyleKit.textLayer(string, scale: frame.scale, glow: s.theme.glow, glowRadius: fontSize * 0.12 * s.glow)
        for k in 0..<3 {
            let trail = StyleKit.textLayer(string, scale: frame.scale)
            trail.opacity = 0
            trails.append(trail)
            container.addSublayer(trail)
            _ = k
        }
        container.addSublayer(main)

        let spreadX = max(0, (area.width - width) / 2) * 0.5 * CGFloat(s.spread)
        let spreadY = area.height * 0.18 * CGFloat(s.spread)
        center = CGPoint(x: area.midX + CGFloat.random(in: -1...1, using: &rng) * spreadX,
                         y: area.midY - area.height * 0.05 + CGFloat.random(in: -1...1, using: &rng) * spreadY)
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        startOffset = CGPoint(x: cos(angle) * fontSize * 1.2, y: sin(angle) * fontSize * 0.8)
        startRotation = CGFloat.random(in: 0.12...0.35, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
        drift = CGFloat.random(in: -0.03...0.03, using: &rng)
        container.frame = CGRect(origin: .zero, size: frame.size)
    }

    func remove() {
        container.removeFromSuperlayer()
    }

    func update(age: Double, exitAge: Double?, entry: Double, exit: Double, beat: Double, glow: Double) {
        func pose(_ a: Double) -> CATransform3D {
            let p = Ease.outCubic(a / entry)
            let scale = 1 + 1.5 * (1 - p) + 0.06 * beat
            let offset = CGPoint(x: startOffset.x * (1 - p), y: startOffset.y * (1 - p))
            let rotation = startRotation * (1 - p) + drift * CGFloat(Ease.clamp01(a / 2))
            var m = CATransform3DMakeTranslation(center.x + offset.x, center.y + offset.y, 0)
            m = CATransform3DRotate(m, rotation, 0, 0, 1)
            return CATransform3DScale(m, scale, scale, 1)
        }

        main.transform = pose(age)
        var opacity = Ease.clamp01(age / 0.05)
        if let exitAge {
            // Blow away: grow and fade.
            let e = Ease.clamp01(exitAge / exit)
            main.transform = CATransform3DScale(pose(age), 1 + 0.4 * e, 1 + 0.4 * e, 1)
            opacity *= 1 - e
        }
        main.opacity = Float(opacity)
        main.shadowRadius = main.bounds.height * (0.1 + 0.25 * exp(-age * 6)) * glow

        // Motion blur: earlier poses, fading as the word settles.
        let blur = Ease.clamp01(1 - age / (entry * 0.9))
        for (k, trail) in trails.enumerated() {
            trail.transform = pose(age - 0.018 * Double(k + 1))
            trail.opacity = Float(blur * (0.35 - 0.1 * Double(k)) * opacity)
        }
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { min(high, max(low, self)) }
}
