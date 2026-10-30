import AppKit
import LyricscapeCore

/// Each sung word lights up as a glowing star with its label, scattered across the
/// screen and linked to the previous word, so every line draws a constellation.
/// Keywords are bigger and gravitate to the middle; the current word pulses.
@MainActor
final class ConstellationStyle: LyricStyle {
    static let id = "constellation"
    static let displayName = "Constellation"

    private let root: CALayer
    private let starfield = CALayer()
    private let linesLayer = CALayer()
    private let frameLayer = CAShapeLayer()
    private var groups: [Int: ConstellationGroup] = [:]
    private var trackKey = ""
    private var layoutKey: LayoutKey?

    private struct LayoutKey: Equatable {
        var size: CGSize
        var scale: CGFloat
        var settings: StyleSettings
    }

    /// Seconds a finished line takes to fade away.
    private static let fadeOut = 0.6
    /// Seconds before a line starts that its ghost stars appear.
    private static let lead = 0.45

    init(root: CALayer) {
        self.root = root
        for layer in [starfield, linesLayer, frameLayer] { root.addSublayer(layer) }
    }

    func reset() {
        for group in groups.values { group.container.removeFromSuperlayer() }
        groups.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let key = LayoutKey(size: frame.size, scale: frame.scale, settings: frame.settings)
        if frame.trackKey != trackKey || key != layoutKey {
            reset()
            trackKey = frame.trackKey
            layoutKey = key
            rebuildChrome(frame)
        }
        starfield.isHidden = !frame.opaqueBackground

        // Lines on screen: the one just sung (fading out), the current one, and the
        // next one once its ghost stars appear.
        let t = frame.time
        let fadeOut = Self.fadeOut / frame.settings.speed
        let lines = frame.document.lines
        let candidates = [frame.position.lastLineIndex.map { $0 - 1 }, frame.position.lastLineIndex, frame.position.nextLineIndex]
        var wanted = Set<Int>()
        for case let i? in candidates where lines.indices.contains(i) {
            if t >= lines[i].start - Self.lead && t < lines[i].end + fadeOut { wanted.insert(i) }
        }
        for (i, group) in groups where !wanted.contains(i) {
            group.container.removeFromSuperlayer()
            groups[i] = nil
        }

        var flash = 0.0
        for i in wanted.sorted() {
            let group = groups[i] ?? makeGroup(lineIndex: i, frame: frame)
            groups[i] = group
            flash = max(flash, group.update(time: t, position: frame.position, settings: frame.settings, fadeOut: fadeOut))
        }

        frameLayer.isHidden = !frame.settings.showFrame
        frameLayer.opacity = Float(0.4 + 0.6 * flash)
        frameLayer.shadowRadius = (8 + 16 * flash) * frame.settings.glow
    }

    private func makeGroup(lineIndex: Int, frame: LyricFrame) -> ConstellationGroup {
        // Keep clear of the menu bar at the top and the status note at the bottom.
        let area = CGRect(origin: .zero, size: frame.size)
        let bounds = CGRect(x: area.width * 0.06, y: max(area.height * 0.08, 48),
                            width: area.width * 0.88, height: area.height * 0.8)
        var rng = SeededRandom("\(trackKey)#\(lineIndex)")
        let group = ConstellationGroup(
            line: frame.document.lines[lineIndex], lineIndex: lineIndex, bounds: bounds, size: frame.size,
            scale: frame.scale, settings: frame.settings,
            obstacles: groups.values.flatMap(\.boxes),
            seed: rng.next()
        )
        linesLayer.addSublayer(group.container)
        return group
    }

    /// Screen frame and starfield, rebuilt when size or settings change.
    private func rebuildChrome(_ frame: LyricFrame) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let theme = frame.settings.theme
        for layer in [starfield, linesLayer, frameLayer] { layer.frame = bounds }

        frameLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 7, dy: 7), cornerWidth: 16, cornerHeight: 16, transform: nil)
        frameLayer.fillColor = nil
        frameLayer.strokeColor = theme.glow.cgColor
        frameLayer.lineWidth = 2.5
        frameLayer.shadowColor = theme.glow.cgColor
        frameLayer.shadowOpacity = 1
        frameLayer.shadowOffset = .zero

        // Faint twinkling background stars (Stage mode only). The twinkle runs in
        // the window server, so it costs this app nothing per frame.
        starfield.sublayers?.forEach { $0.removeFromSuperlayer() }
        var rng = SeededRandom(seed: 7)
        for _ in 0..<110 {
            let star = CALayer()
            let d = CGFloat.random(in: 1...2.6, using: &rng)
            star.frame = CGRect(x: CGFloat.random(in: 0...bounds.width, using: &rng),
                                y: CGFloat.random(in: 0...bounds.height, using: &rng), width: d, height: d)
            star.cornerRadius = d / 2
            star.backgroundColor = (Bool.random(using: &rng) ? RGBA(1, 1, 1) : theme.text).cgColor
            star.opacity = Float.random(in: 0.15...0.55, using: &rng)
            star.contentsScale = frame.scale
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = star.opacity
            twinkle.toValue = star.opacity * 0.2
            twinkle.duration = Double.random(in: 1.5...4.5, using: &rng)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timeOffset = Double.random(in: 0...4, using: &rng)
            star.add(twinkle, forKey: "twinkle")
            starfield.addSublayer(star)
        }
    }
}

/// The layers for one lyric line: a star, a label and an incoming link per word.
@MainActor
private final class ConstellationGroup {
    struct Node {
        let dot: CALayer
        let label: CATextLayer
        /// Same word in the saturated glow colour with a wide blur, behind the label:
        /// the coloured light around a neon tube's bright core.
        let halo: CATextLayer
        let link: CAShapeLayer?
        let dotSize: CGFloat
        let fontSize: CGFloat
    }

    let container = CALayer()
    let boxes: [CGRect]
    private let line: LyricLine
    private let lineIndex: Int
    private var nodes: [Node] = []

    init(line: LyricLine, lineIndex: Int, bounds: CGRect, size: CGSize, scale: CGFloat,
         settings: StyleSettings, obstacles: [CGRect], seed: UInt64) {
        self.line = line
        self.lineIndex = lineIndex
        let theme = settings.theme
        let words = line.words.map(\.text)
        let keywords = KeywordPicker.keywords(in: words)
        // Long lines get a smaller type size so they still fit comfortably.
        let crowding = min(1, sqrt(8 / Double(max(words.count, 1))))
        let base = min(size.width, size.height) * 0.04 * settings.sizeScale * crowding

        struct Measured {
            var text: NSAttributedString
            var haloText: NSAttributedString
            var textSize: CGSize
            var fontSize: CGFloat
            var dot: CGFloat
        }
        let measured: [Measured] = words.enumerated().map { i, word in
            let isKey = keywords.contains(i)
            var fontSize = isKey ? base * 1.8 : base
            var font = settings.font(size: fontSize, weight: isKey ? .heavy : .semibold)
            var textSize = NSAttributedString(string: word, attributes: [.font: font]).size()
            let maxWidth = bounds.width * 0.8
            if textSize.width > maxWidth { // e.g. a whole unspaced CJK line
                fontSize *= maxWidth / textSize.width
                font = settings.font(size: fontSize, weight: isKey ? .heavy : .semibold)
                textSize = NSAttributedString(string: word, attributes: [.font: font]).size()
            }
            let color = (isKey ? theme.accent : theme.text).nsColor
            let text = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: color])
            let haloText = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: theme.glow.nsColor])
            return Measured(text: text, haloText: haloText, textSize: CGSize(width: ceil(textSize.width) + 4, height: ceil(textSize.height)),
                            fontSize: fontSize, dot: max(5, base * (isKey ? 0.3 : 0.2)))
        }

        let gap = base * 0.3
        let boxSizes = measured.map { CGSize(width: $0.dot + gap + $0.textSize.width, height: max($0.textSize.height, $0.dot)) }
        boxes = ConstellationLayout.place(sizes: boxSizes, keywords: keywords, bounds: bounds,
                                          obstacles: obstacles, seed: seed, spread: settings.spread)

        container.frame = CGRect(origin: .zero, size: size)
        let linkLayer = CALayer()
        linkLayer.frame = container.bounds
        container.addSublayer(linkLayer)

        // Put each star on the side of its word that faces its neighbours, so the
        // connecting lines don't run through the text.
        let starOnRight: [Bool] = boxes.indices.map { i in
            let neighbours = [i - 1, i + 1].filter(boxes.indices.contains)
            return neighbours.map { boxes[$0].midX - boxes[i].midX }.reduce(0, +) > 0
        }

        var previousDot: (center: CGPoint, radius: CGFloat)?
        for (i, (m, box)) in zip(measured, boxes).enumerated() {
            let center = CGPoint(x: starOnRight[i] ? box.maxX - m.dot / 2 : box.minX + m.dot / 2, y: box.midY)

            var link: CAShapeLayer?
            if let previousDot {
                // Stop the line short of both stars so it reads as joining them.
                let dx = center.x - previousDot.center.x, dy = center.y - previousDot.center.y
                let length = max(hypot(dx, dy), 1)
                let start = CGPoint(x: previousDot.center.x + dx / length * previousDot.radius * 2,
                                    y: previousDot.center.y + dy / length * previousDot.radius * 2)
                let end = CGPoint(x: center.x - dx / length * m.dot, y: center.y - dy / length * m.dot)
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                let shape = CAShapeLayer()
                shape.frame = container.bounds
                shape.path = path
                shape.strokeColor = theme.line.withAlpha(0.75).cgColor
                shape.fillColor = nil
                shape.lineWidth = max(1, base * 0.03)
                shape.lineCap = .round
                shape.strokeEnd = 0
                shape.shadowColor = theme.glow.cgColor
                shape.shadowOpacity = 0.9
                shape.shadowRadius = 4 * settings.glow
                shape.shadowOffset = .zero
                linkLayer.addSublayer(shape)
                link = shape
            }

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

            let labelFrame = CGRect(x: starOnRight[i] ? box.minX : box.minX + m.dot + gap,
                                    y: box.midY - m.textSize.height / 2,
                                    width: m.textSize.width, height: m.textSize.height)
            func textLayer(_ string: NSAttributedString) -> CATextLayer {
                let layer = CATextLayer()
                layer.string = string
                layer.contentsScale = scale
                layer.alignmentMode = .left
                layer.frame = labelFrame
                layer.shadowColor = theme.glow.cgColor
                layer.shadowOffset = .zero
                layer.opacity = 0
                return layer
            }
            let halo = textLayer(m.haloText)
            halo.shadowOpacity = 1
            halo.shadowRadius = m.fontSize * 0.5 * settings.glow
            container.addSublayer(halo)
            let label = textLayer(m.text)
            label.shadowOpacity = 1
            container.addSublayer(label)

            nodes.append(Node(dot: dot, label: label, halo: halo, link: link, dotSize: m.dot, fontSize: m.fontSize))
            previousDot = (center, m.dot / 2)
        }
    }

    /// Sets every layer for time `t`. Returns how strongly the current word is
    /// "hitting" right now (1 at its onset, decaying), to pulse the screen frame.
    func update(time t: TimeInterval, position: LyricPosition, settings: StyleSettings, fadeOut: Double) -> Double {
        let speed = settings.speed, glow = settings.glow

        let out = Ease.clamp01((t - line.end) / fadeOut)
        container.opacity = Float(1 - out)
        let zoom = 1 + 0.07 * Ease.outCubic(out) // drift outward as it fades
        container.transform = CATransform3DMakeScale(zoom, zoom, 1)

        var hit = 0.0
        for (i, node) in nodes.enumerated() {
            let word = line.words[i]
            let age = (t - word.start) * speed

            // The link to this word draws itself just before the word lands.
            if let link = node.link {
                let progress = Ease.outCubic((age + 0.12) / 0.3)
                link.strokeEnd = progress
                link.opacity = progress > 0 ? 1 : 0
            }

            guard age >= 0 else {
                // Not sung yet: a faint ghost star hints at the shape to come.
                node.dot.opacity = 0.22
                node.dot.transform = CATransform3DMakeScale(0.55, 0.55, 1)
                node.dot.shadowRadius = node.dotSize * 0.8 * glow
                node.label.opacity = 0
                node.halo.opacity = 0
                continue
            }

            let isCurrent = position.lineIndex == lineIndex && position.wordIndex == i
            let pop = Ease.outBack(age / 0.35)
            let flash = exp(-age * 4)
            let pulse = isCurrent ? 0.5 + 0.5 * sin(t * 2 * .pi * 1.6) : 0
            if isCurrent { hit = max(hit, flash) }

            let dotScale = pop * (1 + 0.9 * flash + 0.35 * pulse)
            node.dot.opacity = 1
            node.dot.transform = CATransform3DMakeScale(dotScale, dotScale, 1)
            node.dot.shadowRadius = node.dotSize * (1.2 + 2.5 * flash + pulse) * glow

            let labelScale = 0.88 + 0.12 * pop + 0.05 * pulse
            let rise = (1 - min(pop, 1)) * node.fontSize * 0.25
            let fadeIn = Ease.clamp01(age / 0.12)
            let transform = CATransform3DTranslate(CATransform3DMakeScale(labelScale, labelScale, 1), 0, rise, 0)
            node.label.opacity = Float(fadeIn * (isCurrent ? 1 : 0.88))
            node.label.transform = transform
            node.label.shadowRadius = node.fontSize * (0.1 + 0.2 * flash + 0.08 * pulse) * glow
            // The halo flares on the hit, breathes while current, then settles low.
            node.halo.opacity = Float(fadeIn * min(1, (isCurrent ? 0.55 + 0.25 * pulse : 0.3) + 0.6 * flash))
            node.halo.transform = transform
        }
        return hit
    }
}
