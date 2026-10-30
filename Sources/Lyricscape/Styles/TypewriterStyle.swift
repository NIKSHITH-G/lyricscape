import AppKit
import LyricscapeCore

/// A terminal: each line types out character by character in time with the words,
/// with a blinking block cursor; earlier lines scroll up and dim. Pair with the
/// "Terminal Green" theme for green-on-black.
@MainActor
final class TypewriterStyle: LyricStyle {
    static let id = "typewriter"
    static let displayName = "Typewriter"
    static let summary = "Monospace terminal, typed live"

    private let root: CALayer
    private let scanlines = CAReplicatorLayer()
    private var rows: [CATextLayer] = []
    private var rowStrings: [String] = []
    private var key = ""

    /// How many lines the terminal shows.
    private static let history = 7

    init(root: CALayer) {
        self.root = root
        root.addSublayer(scanlines)
    }

    func reset() {
        for r in rows { r.removeFromSuperlayer() }
        rows.removeAll()
        rowStrings.removeAll()
    }

    func update(_ frame: LyricFrame) {
        let s = frame.settings
        let layoutKey = "\(frame.trackKey)|\(frame.size)|\(s.hashKey)"
        if layoutKey != key {
            reset()
            key = layoutKey
            buildScanlines(frame)
        }
        scanlines.isHidden = !frame.opaqueBackground

        let t = frame.time
        let doc = frame.document
        let fontSize = min(frame.size.width, frame.size.height) * 0.034 * s.sizeScale
        let font = StyleKit.monoFont(size: fontSize, settings: s)
        let lineHeight = fontSize * 1.55 * s.spread.clamped(0.8, 1.4)
        let area = frame.safeArea(margin: 0.07)
        let blockSize = CGSize(width: area.width * 0.86, height: lineHeight * CGFloat(Self.history))
        let origin = frame.anchored(blockSize, in: area)

        // The terminal's contents: a prompt line, then every line started so far.
        var entries: [(text: String, active: Bool)] = []
        let header = "$ play \"\(frame.track.title)\" — \(frame.track.artist)"
        let headerTyped = Int(Double(header.count) * Ease.clamp01(t / 1.4))
        entries.append((String(header.prefix(headerTyped)), headerTyped < header.count))
        if let last = frame.position.lastLineIndex {
            for i in max(0, last - Self.history)...last {
                let (typed, done) = typedText(doc.lines[i], at: t)
                entries.append(("> " + typed, !done && i == last))
            }
        }
        let shown = Array(entries.suffix(Self.history))
        let cursorOn = shown.last?.active == true || t.truncatingRemainder(dividingBy: 1) < 0.55

        while rows.count < shown.count {
            let row = CATextLayer()
            row.contentsScale = frame.scale
            row.alignmentMode = .left
            row.isWrapped = true
            row.shadowColor = s.theme.glow.cgColor
            row.shadowOpacity = 1
            row.shadowOffset = .zero
            root.addSublayer(row)
            rows.append(row)
            rowStrings.append("")
        }
        // Bottom-aligned like a real terminal: stack upwards from the newest line,
        // letting long lines wrap onto extra rows.
        var bottom = origin.y + blockSize.height
        for k in rows.indices.reversed() {
            let row = rows[k]
            guard k < shown.count else {
                row.opacity = 0
                continue
            }
            let isLast = k == shown.count - 1
            let text = shown[k].text + (isLast && cursorOn ? "█" : "")
            if text != rowStrings[k] {
                rowStrings[k] = text
                row.string = StyleKit.text(text, font: font, color: isLast ? s.theme.accent : s.theme.text)
            }
            let width = StyleKit.measure(StyleKit.text(shown[k].text + "█", font: font, color: s.theme.text)).width
            let wraps = CGFloat(min(3, Int(ceil(width / blockSize.width))))
            let height = lineHeight * max(1, wraps)
            bottom -= height
            row.frame = CGRect(x: origin.x, y: bottom, width: blockSize.width, height: height)
            let age = shown.count - 1 - k
            row.opacity = Float(max(0.25, 1 - 0.13 * Double(age)))
            row.shadowRadius = fontSize * (isLast ? 0.35 : 0.15) * s.glow * (1 + 0.6 * frame.audio.beat)
        }
    }

    /// The part of the line typed by time `t`: each word's letters appear across the
    /// time it's sung.
    private func typedText(_ line: LyricLine, at t: TimeInterval) -> (String, done: Bool) {
        var out = ""
        for (k, word) in line.words.enumerated() {
            let prefix = k == 0 ? "" : " "
            if t >= word.end {
                out += prefix + word.text
            } else if t >= word.start {
                let p = (t - word.start) / max(word.duration, 0.01)
                out += prefix + String(word.text.prefix(max(1, Int(Double(word.text.count) * p))))
                return (out, false)
            } else {
                return (out, false)
            }
        }
        return (out, true)
    }

    /// Faint horizontal lines like an old CRT (Stage mode only).
    private func buildScanlines(_ frame: LyricFrame) {
        scanlines.sublayers?.forEach { $0.removeFromSuperlayer() }
        scanlines.frame = CGRect(origin: .zero, size: frame.size)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: 1)
        line.backgroundColor = frame.settings.theme.glow.withAlpha(0.05).cgColor
        scanlines.addSublayer(line)
        scanlines.instanceCount = Int(frame.size.height / 3)
        scanlines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
    }
}
