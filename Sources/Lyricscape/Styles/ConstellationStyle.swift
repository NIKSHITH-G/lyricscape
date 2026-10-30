import AppKit
import LyricscapeCore

/// Each sung word lights up as a star with its label, linked to the previous word, so
/// every line draws a constellation that reads left to right. Keywords are bigger and
/// sit on the centre line with a shockwave when sung; the current word's star glints.
/// Lines slowly dolly in while sung, retract and drift away when done, and leave
/// faint stardust behind so the sky fills up over the song.
@MainActor
final class ConstellationStyle: LyricStyle {
    static let id = "constellation"
    static let displayName = "Constellation"
    static let summary = "Words become linked neon stars"

    private let root: CALayer
    private let starfield = CALayer()
    /// Everything that moves with the slow camera sway.
    private let sky = CALayer()
    private let dustLayer = CALayer()
    private let linesLayer = CALayer()
    /// Neon border: a plain bordered layer (not a path) so it's positioned in the same
    /// top-left coordinates as everything else.
    private let frameLayer = CALayer()
    private var groups: [Int: ConstellationGroup] = [:]
    private var dust: [(layer: CALayer, expires: CFTimeInterval)] = []
    private var trackKey = ""
    private var layoutKey: LayoutKey?

    private struct LayoutKey: Equatable {
        var size: CGSize
        var topInset: CGFloat
        var scale: CGFloat
        var settings: StyleSettings
    }

    /// Group key for the intro title card.
    private static let introKey = -1
    /// Seconds a finished line takes to retract and fade.
    private static let fadeOut = 0.9
    /// Seconds before a line starts that its ghost stars appear.
    private static let lead = 0.45
    /// Seconds stardust from a finished line lingers.
    private static let dustLife: CFTimeInterval = 12

    init(root: CALayer) {
        self.root = root
        for layer in [starfield, sky, frameLayer] { root.addSublayer(layer) }
        sky.addSublayer(dustLayer)
        sky.addSublayer(linesLayer)
    }

    func reset() {
        for group in groups.values { group.container.removeFromSuperlayer() }
        groups.removeAll()
        for d in dust { d.layer.removeFromSuperlayer() }
        dust.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let key = LayoutKey(size: frame.size, topInset: frame.topInset, scale: frame.scale, settings: frame.settings)
        if frame.trackKey != trackKey || key != layoutKey {
            reset()
            trackKey = frame.trackKey
            layoutKey = key
            rebuildChrome(frame)
        }
        starfield.isHidden = !frame.opaqueBackground

        let now = CACurrentMediaTime()
        dust.removeAll { d in
            if d.expires < now { d.layer.removeFromSuperlayer(); return true }
            return false
        }

        let t = frame.time
        let fadeOut = Self.fadeOut / frame.settings.speed
        let lines = frame.document.lines

        // Lines on screen: the one just sung (fading), the current one, and the next
        // once its ghost stars appear. Plus the title card during a long intro.
        var wanted: [Int: LyricLine] = [:]
        let candidates = [frame.position.lastLineIndex.map { $0 - 1 }, frame.position.lastLineIndex, frame.position.nextLineIndex]
        for case let i? in candidates where lines.indices.contains(i) {
            if t >= lines[i].start - Self.lead && t < lines[i].end + fadeOut { wanted[i] = lines[i] }
        }
        if let intro = introLine(frame), t < intro.end + fadeOut {
            wanted[Self.introKey] = intro
        }

        for (i, group) in groups where wanted[i] == nil {
            if t >= group.line.end { leaveDust(from: group) } // finished naturally, not a seek
            group.container.removeFromSuperlayer()
            groups[i] = nil
        }

        // Slow camera sway: the sky is never perfectly still.
        let sway = CATransform3DMakeRotation(0.012 * sin(t * 0.19), 0, 0, 1)
        sky.transform = CATransform3DTranslate(sway, 10 * sin(t * 0.13), 7 * sin(t * 0.17), 0)

        var hit = 0.0
        for (i, line) in wanted.sorted(by: { $0.key < $1.key }) {
            let group = groups[i] ?? makeGroup(key: i, line: line, frame: frame)
            groups[i] = group
            hit = max(hit, group.update(time: t, position: frame.position, settings: frame.settings, fadeOut: fadeOut,
                                        beat: frame.audio.beat))
        }

        hit = max(hit, frame.audio.beat * 0.7) // the border also pulses on the music's beat
        frameLayer.isHidden = !frame.settings.showFrame
        frameLayer.opacity = Float(0.4 + 0.6 * hit)
        frameLayer.shadowRadius = (8 + 18 * hit) * frame.settings.glow
    }

    /// Song title and artist as a small constellation while waiting for the first lyric.
    private func introLine(_ frame: LyricFrame) -> LyricLine? {
        guard let first = frame.document.lines.first, first.start >= 5, !frame.track.title.isEmpty else { return nil }
        let words = [LyricWord(text: frame.track.title, start: 0.4, end: 1.2),
                     LyricWord(text: frame.track.artist, start: 1.1, end: 2)]
        return LyricLine(text: "", start: 0, end: first.start - 0.8, words: words, hasWordTiming: true)
    }

    private func makeGroup(key: Int, line: LyricLine, frame: LyricFrame) -> ConstellationGroup {
        let size = frame.size
        // Clear of the menu bar / notch at the top and the status note at the bottom.
        let top = frame.topInset + size.height * 0.07
        let bounds = CGRect(x: size.width * 0.07, y: top,
                            width: size.width * 0.86, height: size.height * 0.88 - top)
        var rng = SeededRandom("\(trackKey)#\(key)")
        let isIntro = key == Self.introKey
        let group = ConstellationGroup(
            line: line, lineIndex: key, bounds: bounds, size: size, scale: frame.scale,
            settings: frame.settings,
            keywords: isIntro ? [0] : nil,
            typeScale: isIntro ? 0.75 : 1,
            seed: rng.next(),
            verticalBias: key.isMultiple(of: 2) ? -1 : 1
        )
        linesLayer.addSublayer(group.container)
        return group
    }

    /// Leaves the stars of a finished line behind as faint dust that fades slowly.
    private func leaveDust(from group: ConstellationGroup) {
        guard let theme = layoutKey?.settings.theme else { return }
        let layer = CALayer()
        layer.frame = group.container.frame
        layer.transform = group.container.transform
        for center in group.starCenters {
            let d: CGFloat = 2.4
            let mote = CALayer()
            mote.frame = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            mote.cornerRadius = d / 2
            mote.backgroundColor = theme.text.cgColor
            mote.shadowColor = theme.glow.cgColor
            mote.shadowOpacity = 1
            mote.shadowRadius = 3
            mote.shadowOffset = .zero
            layer.addSublayer(mote)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.5
        fade.toValue = 0
        fade.duration = Self.dustLife
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        dustLayer.addSublayer(layer)
        dust.append((layer, CACurrentMediaTime() + Self.dustLife))
    }

    /// Screen frame and starfield, rebuilt when size or settings change.
    private func rebuildChrome(_ frame: LyricFrame) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let theme = frame.settings.theme
        for layer in [starfield, sky, dustLayer, linesLayer] { layer.frame = bounds }

        // Below the menu bar / notch, where it's actually visible.
        frameLayer.frame = CGRect(x: 7, y: frame.topInset + 5, width: bounds.width - 14,
                                  height: bounds.height - frame.topInset - 12)
        frameLayer.cornerRadius = 16
        frameLayer.borderColor = theme.glow.cgColor
        frameLayer.borderWidth = 2.5
        frameLayer.shadowColor = theme.glow.cgColor
        frameLayer.shadowOpacity = 1
        frameLayer.shadowOffset = .zero

        // Faint twinkling background stars (Stage mode only). The twinkle runs in
        // the window server, so it costs this app nothing per frame.
        starfield.sublayers?.forEach { $0.removeFromSuperlayer() }
        var rng = SeededRandom(seed: 7)
        for _ in 0..<140 {
            let star = CALayer()
            let d = CGFloat.random(in: 0.8...2.4, using: &rng)
            star.frame = CGRect(x: CGFloat.random(in: 0...bounds.width, using: &rng),
                                y: CGFloat.random(in: frame.topInset...bounds.height, using: &rng), width: d, height: d)
            star.cornerRadius = d / 2
            star.backgroundColor = (Bool.random(using: &rng) ? RGBA(1, 1, 1) : theme.text).cgColor
            star.opacity = Float.random(in: 0.12...0.5, using: &rng)
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = star.opacity
            twinkle.toValue = star.opacity * 0.15
            twinkle.duration = Double.random(in: 1.5...5, using: &rng)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timeOffset = Double.random(in: 0...5, using: &rng)
            star.add(twinkle, forKey: "twinkle")
            starfield.addSublayer(star)
        }
    }
}

/// The layers for one lyric line.
@MainActor
private final class ConstellationGroup {
    struct Node {
        let dot: CALayer
        /// Four-point lens-flare glint over the star.
        let glint: CAShapeLayer
        let label: CATextLayer
        /// Same word in the saturated glow colour with a wide blur, behind the label:
        /// the coloured light around a neon tube's bright core.
        let halo: CATextLayer
        /// Incoming link from the previous star, and the comet that draws it.
        let link: CAShapeLayer?
        let comet: CALayer?
        let linkEnds: (from: CGPoint, to: CGPoint)?
        /// Shockwave ring for keywords.
        let ring: CAShapeLayer?
        let center: CGPoint
        let dotSize: CGFloat
        let fontSize: CGFloat
        let phase: Double
    }

    let container = CALayer()
    let line: LyricLine
    private let lineIndex: Int
    private var nodes: [Node] = []
    var starCenters: [CGPoint] { nodes.map(\.center) }

    init(line: LyricLine, lineIndex: Int, bounds: CGRect, size: CGSize, scale: CGFloat, settings: StyleSettings,
         keywords keywordOverride: Set<Int>?, typeScale: CGFloat, seed: UInt64, verticalBias: CGFloat) {
        self.line = line
        self.lineIndex = lineIndex
        let theme = settings.theme
        let glow = settings.glow
        let words = line.words.map(\.text)
        let keywords = keywordOverride ?? KeywordPicker.keywords(in: words)
        // Long lines get a slightly smaller type size so they still breathe.
        let crowding = min(1, sqrt(10 / Double(max(words.count, 1))))
        let base = min(size.width, size.height) * 0.042 * settings.sizeScale * crowding * typeScale

        struct Measured {
            var text: NSAttributedString
            var haloText: NSAttributedString
            var textSize: CGSize
            var fontSize: CGFloat
            var dot: CGFloat
        }
        let measured: [Measured] = words.enumerated().map { i, word in
            let isKey = keywords.contains(i)
            var fontSize = isKey ? base * 1.75 : base
            var font = settings.font(size: fontSize, weight: isKey ? .heavy : .semibold)
            var textSize = NSAttributedString(string: word, attributes: [.font: font]).size()
            let maxWidth = bounds.width * 0.8
            if textSize.width > maxWidth { // e.g. a whole unspaced CJK line
                fontSize *= maxWidth / textSize.width
                font = settings.font(size: fontSize, weight: isKey ? .heavy : .semibold)
                textSize = NSAttributedString(string: word, attributes: [.font: font]).size()
            }
            let color = (isKey ? theme.accent : theme.text).nsColor
            return Measured(
                text: NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: color]),
                haloText: NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: theme.glow.nsColor]),
                textSize: CGSize(width: ceil(textSize.width) + 4, height: ceil(textSize.height)),
                fontSize: fontSize,
                dot: max(5, base * (isKey ? 0.26 : 0.18))
            )
        }

        // Each box is the label plus its star, stacked vertically.
        let gap = base * 0.22
        let boxSizes = measured.map { CGSize(width: $0.textSize.width, height: $0.textSize.height + gap + $0.dot) }
        let placement = ConstellationLayout.placement(sizes: boxSizes, keywords: keywords, bounds: bounds, seed: seed,
                                                      spread: settings.spread, verticalBias: verticalBias)
        let boxes = placement.rects

        // Stars go on the side of their label that faces the zig-zag's middle, so the
        // links run between the words rather than through them.
        let starBelow: [Bool] = boxes.indices.map { i in
            let neighbours = [i - 1, i + 1].filter { boxes.indices.contains($0) && placement.rows[$0] == placement.rows[i] }
            guard !neighbours.isEmpty else { return true }
            let meanY = neighbours.map { boxes[$0].midY }.reduce(0, +) / CGFloat(neighbours.count)
            return boxes[i].midY <= meanY
        }

        container.frame = CGRect(origin: .zero, size: size)
        let linkLayer = CALayer()
        linkLayer.frame = container.bounds
        container.addSublayer(linkLayer)

        var rng = SeededRandom(seed: seed ^ 0x5EED)
        var previous: (center: CGPoint, radius: CGFloat)?
        for (i, (m, box)) in zip(measured, boxes).enumerated() {
            let center = CGPoint(x: box.midX, y: starBelow[i] ? box.maxY - m.dot / 2 : box.minY + m.dot / 2)
            let labelFrame = CGRect(x: box.minX, y: starBelow[i] ? box.minY : box.minY + m.dot + gap,
                                    width: m.textSize.width, height: m.textSize.height)

            var link: CAShapeLayer?, comet: CALayer?, ends: (CGPoint, CGPoint)?
            // A wrapped line becomes one constellation per row: no link across the break.
            if let previous, i > 0, placement.rows[i] == placement.rows[i - 1] {
                // Stop the line just short of both stars so it reads as joining them.
                let dx = center.x - previous.center.x, dy = center.y - previous.center.y
                let length = max(hypot(dx, dy), 1)
                let from = CGPoint(x: previous.center.x + dx / length * previous.radius * 2.2,
                                   y: previous.center.y + dy / length * previous.radius * 2.2)
                let to = CGPoint(x: center.x - dx / length * m.dot * 1.1, y: center.y - dy / length * m.dot * 1.1)
                let path = CGMutablePath()
                path.move(to: from)
                path.addLine(to: to)
                let shape = CAShapeLayer()
                shape.frame = container.bounds
                shape.path = path
                shape.strokeColor = theme.line.withAlpha(0.8).cgColor
                shape.fillColor = nil
                shape.lineWidth = max(1, base * 0.028)
                shape.lineCap = .round
                shape.strokeEnd = 0
                shape.shadowColor = theme.glow.cgColor
                shape.shadowOpacity = 0.9
                shape.shadowRadius = 4 * glow
                shape.shadowOffset = .zero
                linkLayer.addSublayer(shape)
                link = shape

                let head = CALayer()
                let d = max(4, base * 0.12)
                head.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                head.cornerRadius = d / 2
                head.backgroundColor = theme.accent.cgColor
                head.shadowColor = theme.glow.cgColor
                head.shadowOpacity = 1
                head.shadowRadius = d * 2.5 * glow
                head.shadowOffset = .zero
                head.shadowPath = CGPath(ellipseIn: head.bounds, transform: nil)
                head.opacity = 0
                linkLayer.addSublayer(head)
                comet = head
                ends = (from, to)
            }

            var ring: CAShapeLayer?
            if keywords.contains(i) {
                let shape = CAShapeLayer()
                shape.frame = container.bounds
                shape.fillColor = nil
                shape.strokeColor = theme.glow.cgColor
                shape.shadowColor = theme.glow.cgColor
                shape.shadowOpacity = 1
                shape.shadowRadius = 6 * glow
                shape.shadowOffset = .zero
                shape.opacity = 0
                container.addSublayer(shape)
                ring = shape
            }

            // Glint sits behind the text so a flare never covers a word.
            let glint = CAShapeLayer()
            let r = m.dot * 2.6
            glint.bounds = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
            glint.position = center
            glint.path = Self.sparkle(radius: r)
            glint.fillColor = theme.accent.cgColor
            glint.shadowColor = theme.glow.cgColor
            glint.shadowOpacity = 1
            glint.shadowRadius = 4 * glow
            glint.shadowOffset = .zero
            glint.opacity = 0
            container.addSublayer(glint)

            func textLayer(_ string: NSAttributedString) -> CATextLayer {
                let layer = CATextLayer()
                layer.string = string
                layer.contentsScale = scale
                layer.alignmentMode = .center
                layer.frame = labelFrame
                layer.shadowColor = theme.glow.cgColor
                layer.shadowOffset = .zero
                layer.shadowOpacity = 1
                layer.opacity = 0
                return layer
            }
            let halo = textLayer(m.haloText)
            halo.shadowRadius = m.fontSize * 0.5 * glow
            container.addSublayer(halo)
            let label = textLayer(m.text)
            container.addSublayer(label)

            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: m.dot, height: m.dot)
            dot.position = center
            dot.cornerRadius = m.dot / 2
            dot.backgroundColor = theme.accent.cgColor
            dot.shadowColor = theme.glow.cgColor
            dot.shadowOpacity = 1
            dot.shadowOffset = .zero
            dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
            dot.opacity = 0
            container.addSublayer(dot)

            nodes.append(Node(dot: dot, glint: glint, label: label, halo: halo, link: link, comet: comet,
                              linkEnds: ends, ring: ring, center: center, dotSize: m.dot, fontSize: m.fontSize,
                              phase: Double.random(in: 0..<(2 * .pi), using: &rng)))
            previous = (center, m.dot / 2)
        }
    }

    /// A thin four-pointed star centred on the origin.
    private static func sparkle(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inner = r * 0.09
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4 - .pi / 2
            let radius = k.isMultiple(of: 2) ? r : inner
            let p = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Sets every layer for time `t`. Returns how strongly a word is "hitting" right
    /// now (1 at a keyword's onset, decaying), to pulse the screen frame.
    func update(time t: TimeInterval, position: LyricPosition, settings: StyleSettings, fadeOut: Double,
                beat: Double = 0) -> Double {
        let speed = settings.speed, glow = settings.glow

        // Slow dolly-in while the line is sung; when it's over, the links retract into
        // the stars and the constellation drifts outward as it fades.
        let life = Ease.clamp01((t - line.start) / max(line.end - line.start, 0.5))
        let out = Ease.clamp01((t - line.end) / fadeOut)
        container.opacity = Float(1 - Ease.outCubic(out))
        let zoom = 1 + 0.035 * life + 0.08 * Ease.outCubic(out)
        container.transform = CATransform3DMakeScale(zoom, zoom, 1)
        let retract = Ease.outCubic(out * 1.5)
        // Words leave quickly; stars and links take the full fade.
        let textOut = Ease.clamp01(out * 2.5)

        var hit = 0.0
        for (i, node) in nodes.enumerated() {
            let word = line.words[i]
            let age = (t - word.start) * speed
            let isKey = node.ring != nil

            // The link to this word draws itself just before the word lands, with a
            // bright comet at its tip.
            if let link = node.link, let comet = node.comet, let ends = node.linkEnds {
                let draw = Ease.outCubic((age + 0.15) / 0.35)
                link.strokeEnd = draw
                link.strokeStart = min(retract, draw)
                link.opacity = draw > 0 ? 1 : 0
                if draw > 0 && draw < 1 {
                    comet.position = CGPoint(x: ends.from.x + (ends.to.x - ends.from.x) * draw,
                                             y: ends.from.y + (ends.to.y - ends.from.y) * draw)
                    comet.opacity = Float(sin(draw * .pi))
                } else {
                    comet.opacity = 0
                }
            }

            guard age >= 0 else {
                // Not sung yet: a faint ghost star hints at the shape to come.
                node.dot.opacity = 0.2
                node.dot.transform = CATransform3DMakeScale(0.55, 0.55, 1)
                node.dot.shadowRadius = node.dotSize * 0.8 * glow
                node.glint.opacity = 0
                node.label.opacity = 0
                node.halo.opacity = 0
                node.ring?.opacity = 0
                continue
            }

            let isCurrent = position.lineIndex == lineIndex && position.wordIndex == i
            let flash = exp(-age * 3.5)
            let pop = Ease.outBack(age / 0.35)
            hit = max(hit, isKey ? flash : flash * 0.5)

            let dotScale = pop * (1 + 0.8 * flash + 0.25 * beat)
            node.dot.opacity = 1
            node.dot.transform = CATransform3DMakeScale(dotScale, dotScale, 1)
            node.dot.shadowRadius = node.dotSize * (1.2 + 2.5 * flash) * glow

            // Glint: flares as the word lands, keeps slowly turning on the current word.
            let glintScale = 0.45 + 0.6 * flash + (isCurrent ? 0.25 : 0)
            node.glint.opacity = Float(isCurrent ? 0.55 + 0.45 * flash : 0.9 * flash)
            node.glint.transform = CATransform3DScale(CATransform3DMakeRotation(t * 0.6 + node.phase, 0, 0, 1),
                                                      glintScale, glintScale, 1)

            let fadeIn = Ease.clamp01(age / 0.12)
            let labelScale = 0.88 + 0.12 * pop
            let rise = (1 - min(pop, 1)) * node.fontSize * 0.25
            let transform = CATransform3DTranslate(CATransform3DMakeScale(labelScale, labelScale, 1), 0, rise, 0)
            node.label.opacity = Float(fadeIn * (isCurrent ? 1 : 0.88) * (1 - textOut))
            node.label.transform = transform
            node.label.shadowRadius = node.fontSize * (0.1 + 0.2 * flash) * glow
            // The halo flares on the hit, breathes while current, then settles low.
            let breathe = isCurrent ? 0.1 * sin(t * 2.4 + node.phase) : 0
            node.halo.opacity = Float(fadeIn * min(1, (isCurrent ? 0.55 : 0.3) + 0.6 * flash + breathe + 0.25 * beat) * (1 - textOut))
            node.halo.transform = transform

            // Keyword shockwave: a ring bursting out from the star.
            if let ring = node.ring {
                let r = age / 1.1
                if r < 1 {
                    let radius = node.dotSize * (1 + 14 * Ease.outCubic(r))
                    ring.path = CGPath(ellipseIn: CGRect(x: node.center.x - radius, y: node.center.y - radius,
                                                         width: 2 * radius, height: 2 * radius), transform: nil)
                    ring.lineWidth = 2.5 * (1 - r)
                    ring.opacity = Float(0.9 * (1 - r) * (1 - r))
                } else {
                    ring.opacity = 0
                }
            }
        }
        return hit
    }
}
