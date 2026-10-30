import AppKit
import LyricscapeCore

/// Words assemble out of a swarm of particles as they're sung, then burst back into
/// particles that drift away when the line ends.
@MainActor
final class ParticleStyle: LyricStyle {
    static let id = "particles"
    static let displayName = "Particles"
    static let summary = "Words form from, and burst into, particles"

    private let root: CALayer
    private var groups: [Int: ParticleLine] = [:]
    private var key = ""

    /// Seconds before a word is sung that its particles start flying in.
    static let form = 0.45
    /// Seconds the burst lasts after the line ends.
    static let burst = 1.6

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
        let visible = StyleKit.visibleLines(frame, before: 1, lead: Self.form, tail: Self.burst)
        for (i, g) in groups where !visible.contains(i) {
            g.container.removeFromSuperlayer()
            groups[i] = nil
        }
        for i in visible {
            let g = groups[i] ?? {
                let made = ParticleLine(line: frame.document.lines[i], lineIndex: i, frame: frame)
                root.addSublayer(made.container)
                return made
            }()
            groups[i] = g
            g.update(frame)
        }
    }
}

@MainActor
private final class ParticleLine {
    struct Particle {
        let layer: CALayer
        let target: CGPoint
        let from: CGPoint
        let velocity: CGVector
    }
    struct Word {
        let label: CATextLayer
        let particles: [Particle]
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
        let fontSize = min(frame.size.width, frame.size.height) * 0.07 * s.sizeScale
        let font = s.font(size: fontSize, weight: .heavy)
        var rng = SeededRandom("\(frame.trackKey)#particles#\(lineIndex)")

        let texts = line.words.map { StyleKit.text($0.text, font: font, color: s.theme.accent) }
        let sizes = texts.map(StyleKit.measure)
        let flow = StyleKit.flow(sizes, maxWidth: area.width * 0.85, spacing: fontSize * 0.32, lineSpacing: fontSize * 0.25)
        let origin = frame.anchored(flow.size, in: area)
        // Fewer particles per word on long lines keeps the layer count sensible.
        let perWord = max(28, min(80, 520 / max(1, line.words.count)))
        let dot = max(2.5, fontSize * 0.07)

        for (k, text) in texts.enumerated() {
            let center = CGPoint(x: origin.x + flow.centers[k].x, y: origin.y + flow.centers[k].y)
            let label = StyleKit.textLayer(text, scale: frame.scale, glow: s.theme.glow, glowRadius: fontSize * 0.2 * s.glow)
            label.position = center
            label.opacity = 0
            container.addSublayer(label)

            let topLeft = CGPoint(x: center.x - sizes[k].width / 2, y: center.y - sizes[k].height / 2)
            var particles: [Particle] = []
            for point in StyleKit.glyphPoints(text, count: perWord, seed: rng.next()) {
                let target = CGPoint(x: topLeft.x + point.x, y: topLeft.y + point.y)
                // Fly in from a swirl around the word…
                let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                let distance = fontSize * CGFloat.random(in: 1.5...4.5, using: &rng)
                let from = CGPoint(x: target.x + cos(angle) * distance, y: target.y + sin(angle) * distance)
                // …and burst outward from the word's centre.
                let dx = target.x - center.x + CGFloat.random(in: -10...10, using: &rng)
                let dy = target.y - center.y + CGFloat.random(in: -10...10, using: &rng)
                let length = max(hypot(dx, dy), 1)
                let speed = fontSize * CGFloat.random(in: 1.2...5, using: &rng)
                let layer = CALayer()
                let d = dot * CGFloat.random(in: 0.7...1.3, using: &rng)
                layer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                layer.cornerRadius = d / 2
                layer.backgroundColor = (Bool.random(using: &rng) ? s.theme.accent : s.theme.glow).cgColor
                layer.opacity = 0
                container.addSublayer(layer)
                particles.append(Particle(layer: layer, target: target, from: from,
                                          velocity: CGVector(dx: dx / length * speed, dy: dy / length * speed - fontSize * 0.6)))
            }
            words.append(Word(label: label, particles: particles))
        }
    }

    func update(_ frame: LyricFrame) {
        let t = frame.time, s = frame.settings
        let burstAge = t - line.end
        for (k, w) in words.enumerated() {
            let word = line.words[k]
            let age = (t - word.start) * s.speed
            let formAge = age + ParticleStyle.form

            if burstAge >= 0 {
                // Burst: the word shatters into particles that drift off and fade.
                let e = burstAge * s.speed
                let travel = CGFloat((1 - exp(-e * 2.2)) / 2.2)
                let fade = Ease.clamp01(1 - e / ParticleStyle.burst)
                w.label.opacity = Float(max(0, 1 - e / 0.12))
                for p in w.particles {
                    p.layer.position = CGPoint(x: p.target.x + p.velocity.dx * travel,
                                               y: p.target.y + p.velocity.dy * travel + CGFloat(18 * e * e))
                    p.layer.opacity = Float(fade * (age >= 0 ? 1 : 0.4))
                }
                continue
            }
            guard formAge >= 0 else {
                w.label.opacity = 0
                for p in w.particles { p.layer.opacity = 0 }
                continue
            }
            // Forming: particles converge on the letters; the crisp text fades in as
            // the word is sung and the particles melt into it.
            let p = Ease.outCubic(formAge / ParticleStyle.form)
            let settle = Ease.clamp01(age / 0.35)
            for particle in w.particles {
                particle.layer.position = CGPoint(x: particle.from.x + (particle.target.x - particle.from.x) * p,
                                                  y: particle.from.y + (particle.target.y - particle.from.y) * p)
                particle.layer.opacity = Float(min(1, formAge * 6) * (1 - settle) * 0.9)
            }
            let isCurrent = frame.position.lineIndex == lineIndex && frame.position.wordIndex == k
            w.label.opacity = Float(Ease.clamp01(age / 0.15) * (isCurrent ? 1 : 0.85))
            w.label.shadowRadius = w.label.bounds.height * (0.2 + 0.4 * exp(-max(0, age) * 4) + 0.2 * frame.audio.beat) * s.glow
        }
    }
}
