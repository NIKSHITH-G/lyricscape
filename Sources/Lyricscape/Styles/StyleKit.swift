import AppKit
import LyricscapeCore

/// Small building blocks shared by the styles.
@MainActor
enum StyleKit {
    static func text(_ string: String, font: NSFont, color: RGBA) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color.nsColor])
    }

    /// Size of a single line of text, rounded up (with a little slack for italics/glow).
    static func measure(_ text: NSAttributedString) -> CGSize {
        let size = text.size()
        return CGSize(width: ceil(size.width) + 4, height: ceil(size.height))
    }

    /// A centred text layer sized to its text. Optionally glowing.
    static func textLayer(_ text: NSAttributedString, scale: CGFloat, glow: RGBA? = nil, glowRadius: CGFloat = 0) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.contentsScale = scale
        layer.alignmentMode = .center
        layer.bounds = CGRect(origin: .zero, size: measure(text))
        if let glow {
            layer.shadowColor = glow.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = glowRadius
            layer.shadowOffset = .zero
        }
        return layer
    }

    static func monoFont(size: CGFloat, settings: StyleSettings) -> NSFont {
        if settings.fontName != nil { return settings.font(size: size, weight: .medium) }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    /// Lines worth drawing around now: up to `before` lines back and the next one,
    /// keeping only those within `lead` seconds before their start and `tail` after their end.
    static func visibleLines(_ frame: LyricFrame, before: Int = 1, lead: Double = 0, tail: Double = 0.6) -> [Int] {
        let lines = frame.document.lines
        let anchor = frame.position.lastLineIndex ?? -1
        let last = max(anchor, frame.position.nextLineIndex ?? anchor)
        guard last >= 0 else { return [] }
        return (max(0, anchor - before)...min(lines.count - 1, last)).filter { i in
            frame.time >= lines[i].start - lead && frame.time < lines[i].end + tail
        }
    }

    /// Wraps boxes into centred rows no wider than `maxWidth`. Returns each box's centre
    /// relative to the block's top-left, and the block's size.
    static func flow(_ sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> (centers: [CGPoint], size: CGSize) {
        var rows: [[Int]] = [[]]
        var widths: [CGFloat] = [0]
        for (i, size) in sizes.enumerated() {
            let added = rows[rows.count - 1].isEmpty ? size.width : widths[widths.count - 1] + spacing + size.width
            if added > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([i])
                widths.append(size.width)
            } else {
                rows[rows.count - 1].append(i)
                widths[widths.count - 1] = added
            }
        }
        let blockWidth = widths.max() ?? 0
        var centers = [CGPoint](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for (row, width) in zip(rows, widths) {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x = (blockWidth - width) / 2
            for i in row {
                centers[i] = CGPoint(x: x + sizes[i].width / 2, y: y + height / 2)
                x += sizes[i].width + spacing
            }
            y += height + lineSpacing
        }
        return (centers, CGSize(width: blockWidth, height: max(0, y - lineSpacing)))
    }

    /// Points inside the glyphs of `text` (relative to its top-left), for particles.
    static func glyphPoints(_ text: NSAttributedString, count: Int, seed: UInt64) -> [CGPoint] {
        let size = measure(text)
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = NSMutableAttributedString(attributedString: text)
        white.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: white.length))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        white.draw(at: CGPoint(x: 2, y: 0))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }

        var inside: [CGPoint] = []
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where data[y * width + x] > 128 {
                inside.append(CGPoint(x: x, y: y)) // bitmap rows run top-down here
            }
        }
        var rng = SeededRandom(seed: seed)
        inside.shuffle(using: &rng)
        return Array(inside.prefix(count))
    }
}

/// One lyric line drawn twice — dim, and bright with a glow — with the bright copy
/// revealed left to right as the words are sung (karaoke fill).
@MainActor
final class FillLineLayer {
    let container = CALayer()
    let size: CGSize
    private let base: CATextLayer
    private let fill: CATextLayer
    private let mask = CALayer()
    /// x range of each word within the line.
    private let wordSpans: [ClosedRange<CGFloat>]
    private let line: LyricLine

    init(line: LyricLine, font: NSFont, baseColor: RGBA, fillColor: RGBA, glow: RGBA, glowRadius: CGFloat,
         alignment: CATextLayerAlignmentMode, scale: CGFloat) {
        self.line = line
        let text = line.text
        let baseText = StyleKit.text(text, font: font, color: baseColor)
        size = StyleKit.measure(baseText)
        base = StyleKit.textLayer(baseText, scale: scale)
        fill = StyleKit.textLayer(StyleKit.text(text, font: font, color: fillColor), scale: scale, glow: glow, glowRadius: glowRadius)
        for layer in [base, fill] {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.alignmentMode = alignment
        }
        container.bounds = CGRect(origin: .zero, size: size)
        container.addSublayer(base)
        container.addSublayer(fill)
        mask.backgroundColor = CGColor.black
        mask.frame = CGRect(x: -20, y: -20, width: 0, height: size.height + 40)
        fill.mask = mask

        // Find each word in the line's text (in order) and measure where it sits.
        var spans: [ClosedRange<CGFloat>] = []
        var searchStart = text.startIndex
        for word in line.words {
            if let range = text.range(of: word.text, range: searchStart..<text.endIndex) {
                let before = StyleKit.text(String(text[..<range.lowerBound]), font: font, color: baseColor).size().width
                let through = StyleKit.text(String(text[..<range.upperBound]), font: font, color: baseColor).size().width
                spans.append((before + 2)...(through + 2))
                searchStart = range.upperBound
            } else {
                spans.append((spans.last?.upperBound ?? 0)...(spans.last?.upperBound ?? 0))
            }
        }
        wordSpans = spans
    }

    /// Reveal the bright copy up to time `t` (0 = nothing, everything once the line is done).
    func setFill(time t: TimeInterval) {
        var x: CGFloat = 0
        for (word, span) in zip(line.words, wordSpans) {
            if t >= word.end {
                x = span.upperBound
            } else if t > word.start {
                let p = (t - word.start) / max(word.duration, 0.01)
                x = span.lowerBound + (span.upperBound - span.lowerBound) * p
                break
            } else {
                break
            }
        }
        // The glow spills past the text, so the mask runs from well left of it.
        mask.frame = CGRect(x: -40, y: -40, width: x + 40, height: size.height + 80)
    }

    func setFull(_ full: Bool) {
        mask.frame = CGRect(x: -40, y: -40, width: full ? size.width + 80 : 0, height: size.height + 80)
    }
}
