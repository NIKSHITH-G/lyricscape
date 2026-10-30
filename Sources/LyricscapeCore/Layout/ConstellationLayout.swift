import CoreGraphics
import Foundation

/// Lays the words of one line out as a readable constellation: words run left to
/// right in reading order, zig-zagging above and below a gently tilted centre line
/// (keywords sit on it), long lines break into balanced rows, and the whole shape is
/// composed around the middle of the screen. Deterministic for a given seed.
public enum ConstellationLayout {
    public struct Placement: Equatable, Sendable {
        /// One box per word, in reading order.
        public var rects: [CGRect]
        /// Row number of each word (long lines wrap onto several rows).
        public var rows: [Int]
    }

    /// Convenience returning just the boxes.
    public static func place(
        sizes: [CGSize], keywords: Set<Int>, bounds: CGRect,
        seed: UInt64, spread: Double = 1, verticalBias: CGFloat = 0
    ) -> [CGRect] {
        placement(sizes: sizes, keywords: keywords, bounds: bounds, seed: seed, spread: spread,
                  verticalBias: verticalBias).rects
    }

    /// - Parameters:
    ///   - sizes: size of each word's box (star + label), in reading order.
    ///   - bounds: area to place into (y grows downwards).
    ///   - spread: 1 = default spacing between words and amount of zig-zag.
    ///   - verticalBias: -1…1, shifts the shape up/down so consecutive lines alternate.
    public static func placement(
        sizes: [CGSize], keywords: Set<Int>, bounds: CGRect,
        seed: UInt64, spread: Double = 1, verticalBias: CGFloat = 0
    ) -> Placement {
        guard !sizes.isEmpty else { return Placement(rects: [], rows: []) }
        var rng = SeededRandom(seed: seed)
        let spread = CGFloat(spread)
        let rowHeight = sizes.map(\.height).max() ?? 0
        let averageHeight = sizes.map(\.height).reduce(0, +) / CGFloat(sizes.count)

        // Horizontal gaps between consecutive words.
        let gapBase = averageHeight * 1.1 * spread
        let gaps: [CGFloat] = sizes.indices.map { $0 == 0 ? 0 : gapBase * CGFloat.random(in: 0.7...1.5, using: &rng) }

        // Break into balanced rows no wider than ~80% of the screen.
        let maxRowWidth = bounds.width * 0.8
        let total = zip(sizes, gaps).map { $0.width + $1 }.reduce(0, +)
        let rowCount = max(1, Int(ceil(total / maxRowWidth)))
        let target = min(maxRowWidth, total / CGFloat(rowCount) * 1.1)
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        for i in sizes.indices {
            let added = rows[rows.count - 1].isEmpty ? sizes[i].width : rowWidth + gaps[i] + sizes[i].width
            if added > target, !rows[rows.count - 1].isEmpty {
                rows.append([i])
                rowWidth = sizes[i].width
            } else {
                rows[rows.count - 1].append(i)
                rowWidth = added
            }
        }

        // Zig-zag: each word sits above or below its row's centre line, mostly
        // alternating; keywords sit right on it.
        let amplitude = rowHeight * 1.0 * spread
        let tiltLimit: CGFloat = rows.count == 1 ? 0.09 : 0.03
        let rowSpacing = rowHeight * 1.3 + amplitude * 2 + maxRowWidth * tiltLimit
        var centers = [CGPoint](repeating: .zero, count: sizes.count)
        var side: CGFloat = Bool.random(using: &rng) ? 1 : -1

        for (r, row) in rows.enumerated() {
            var x: CGFloat = 0
            var local: [(index: Int, point: CGPoint)] = []
            for (k, i) in row.enumerated() {
                if k > 0 { x += gaps[i] }
                let y: CGFloat
                if keywords.contains(i) {
                    y = 0
                } else {
                    if CGFloat.random(in: 0...1, using: &rng) < 0.75 { side = -side }
                    y = side * amplitude * CGFloat.random(in: 0.35...1, using: &rng)
                }
                local.append((i, CGPoint(x: x + sizes[i].width / 2, y: y)))
                x += sizes[i].width
            }
            let width = x
            let tilt = CGFloat.random(in: -tiltLimit...tiltLimit, using: &rng)
            let stagger = rows.count > 1 ? bounds.width * 0.04 * CGFloat.random(in: -1...1, using: &rng) : 0
            let rowY = (CGFloat(r) - CGFloat(rows.count - 1) / 2) * rowSpacing
            for (i, p) in local {
                let px = p.x - width / 2
                centers[i] = CGPoint(x: px * cos(tilt) - p.y * sin(tilt) + stagger,
                                     y: px * sin(tilt) + p.y * cos(tilt) + rowY)
            }
        }

        // Compose around the middle, nudged a little off-centre for life.
        let origin = CGPoint(
            x: bounds.midX + bounds.width * 0.04 * CGFloat.random(in: -1...1, using: &rng),
            y: bounds.midY + bounds.height * (0.17 * max(-1, min(1, verticalBias)) + 0.03 * CGFloat.random(in: -1...1, using: &rng))
        )
        var rects = sizes.indices.map { i in
            CGRect(x: origin.x + centers[i].x - sizes[i].width / 2, y: origin.y + centers[i].y - sizes[i].height / 2,
                   width: sizes[i].width, height: sizes[i].height)
        }

        // Keep everything on screen: shift back inside, and if the shape is simply
        // too big, pull the words towards its centre.
        var union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        if union.width > bounds.width || union.height > bounds.height {
            let factor = min(bounds.width / union.width, bounds.height / union.height)
            let c = CGPoint(x: union.midX, y: union.midY)
            rects = rects.map { r in
                CGRect(x: c.x + (r.midX - c.x) * factor - r.width / 2, y: c.y + (r.midY - c.y) * factor - r.height / 2,
                       width: r.width, height: r.height)
            }
            union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        }
        let dx = max(bounds.minX - union.minX, 0) + min(bounds.maxX - union.maxX, 0)
        let dy = max(bounds.minY - union.minY, 0) + min(bounds.maxY - union.maxY, 0)
        var rowOf = [Int](repeating: 0, count: sizes.count)
        for (r, row) in rows.enumerated() { for i in row { rowOf[i] = r } }
        return Placement(rects: rects.map { $0.offsetBy(dx: dx, dy: dy) }, rows: rowOf)
    }
}
