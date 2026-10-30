import AppKit
import LyricscapeCore

/// Centred lines with a colour fill sweeping across each word as it's sung; the
/// previous line drifts up and the next waits faded below, scrolling smoothly.
@MainActor
final class KaraokeStyle: LyricStyle {
    static let id = "karaoke"
    static let displayName = "Karaoke"
    static let summary = "Colour sweeps across each word"

    private let root: CALayer
    private var lines: [Int: FillLineLayer] = [:]
    private var key = ""

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
        let doc = frame.document
        let area = frame.safeArea(margin: 0.07)
        let fontSize = min(frame.size.width, frame.size.height) * 0.058 * s.sizeScale
        let spacing = fontSize * 1.75 * s.spread

        // Scroll position: eases from one line to the next as each line starts.
        let last = frame.position.lastLineIndex ?? -1
        var scroll = Double(last)
        if last >= 0 {
            scroll = Double(last - 1) + Ease.outCubic((t - doc.lines[last].start) * s.speed / 0.45)
        } else if let next = frame.position.nextLineIndex {
            scroll = Double(next) - 1
        }

        let alignment: CATextLayerAlignmentMode = switch s.anchor {
        case .topLeft, .bottomLeft: .left
        case .topRight, .bottomRight: .right
        default: .center
        }
        let centerY: CGFloat = switch s.anchor {
        case .top, .topLeft, .topRight: area.minY + spacing * 1.2
        case .bottom, .bottomLeft, .bottomRight: area.maxY - spacing * 1.6
        default: area.midY
        }

        let visible = Set((Int(scroll.rounded(.down)) - 1...Int(scroll.rounded(.up)) + 2).filter(doc.lines.indices.contains))
        for (i, l) in lines where !visible.contains(i) {
            l.container.removeFromSuperlayer()
            lines[i] = nil
        }

        for i in visible.sorted() {
            let line = lines[i] ?? makeLine(doc.lines[i], fontSize: fontSize, area: area, alignment: alignment, frame: frame)
            lines[i] = line
            let d = Double(i) - scroll // 0 = current slot, <0 above, >0 below
            let distance = abs(d)
            line.container.opacity = Float(max(0, 1 - 0.62 * min(distance, 1) - 0.25 * max(0, distance - 1)))
            let scale = 1 - 0.2 * min(distance, 1)
            let x: CGFloat = switch alignment {
            case .left: area.minX + line.size.width * scale / 2
            case .right: area.maxX - line.size.width * scale / 2
            default: area.midX
            }
            line.container.position = CGPoint(x: x, y: centerY + CGFloat(d) * spacing)
            line.container.transform = CATransform3DMakeScale(scale, scale, 1)
            if i < last || (i == last && t >= doc.lines[i].end) {
                line.setFull(true)
            } else if i == last {
                line.setFill(time: t)
            } else {
                line.setFull(false)
            }
        }
    }

    private func makeLine(_ line: LyricLine, fontSize: CGFloat, area: CGRect, alignment: CATextLayerAlignmentMode,
                          frame: LyricFrame) -> FillLineLayer {
        let s = frame.settings
        var size = fontSize
        var font = s.font(size: size, weight: .bold)
        let width = StyleKit.measure(StyleKit.text(line.text, font: font, color: s.theme.text)).width
        if width > area.width { // shrink long lines to fit on one row
            size *= area.width / width
            font = s.font(size: size, weight: .bold)
        }
        let layer = FillLineLayer(line: line, font: font, baseColor: s.theme.text.withAlpha(0.42),
                                  fillColor: s.theme.accent, glow: s.theme.glow, glowRadius: size * 0.22 * s.glow,
                                  alignment: alignment, scale: frame.scale)
        root.addSublayer(layer.container)
        return layer
    }
}

extension StyleSettings {
    /// Changes whenever anything that affects text layout or colour changes.
    var hashKey: String {
        "\(theme.name)\(theme.glow)\(theme.text)\(fontName ?? "")\(sizeScale)\(glow)\(spread)\(anchor)\(showFrame)"
    }
}
