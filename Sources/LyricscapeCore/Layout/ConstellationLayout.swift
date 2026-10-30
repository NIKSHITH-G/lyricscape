import CoreGraphics
import Foundation

/// Scatters the words of one line across the screen as a chain of "stars": each word
/// lands a comfortable distance from the previous one, keywords gravitate towards the
/// middle, and nothing overlaps. Deterministic for a given seed.
public enum ConstellationLayout {
    /// - Parameters:
    ///   - sizes: size of each word's box (star + label), in reading order.
    ///   - bounds: area to place into (y grows downwards).
    ///   - obstacles: boxes already on screen (e.g. the previous line) to avoid.
    ///   - spread: 1 = default distance between consecutive words.
    /// - Returns: one box per word, same order as `sizes`.
    public static func place(
        sizes: [CGSize], keywords: Set<Int>, bounds: CGRect,
        obstacles: [CGRect] = [], seed: UInt64, spread: Double = 1
    ) -> [CGRect] {
        var rng = SeededRandom(seed: seed)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let diagonal = hypot(bounds.width, bounds.height)
        let idealStep = diagonal * 0.16 * spread
        var placed: [CGRect] = []

        for (i, size) in sizes.enumerated() {
            let isKey = keywords.contains(i)
            let previous = placed.last.map { CGPoint(x: $0.midX, y: $0.midY) }
            let padding = min(size.height * 0.35, 24)
            var best: (rect: CGRect, score: Double)?

            for attempt in 0..<120 {
                let candidate = candidatePoint(
                    attempt: attempt, isKey: isKey, previous: previous, center: center,
                    bounds: bounds, step: idealStep, rng: &rng
                )
                let rect = CGRect(x: candidate.x - size.width / 2, y: candidate.y - size.height / 2,
                                  width: size.width, height: size.height)
                guard bounds.contains(rect) else { continue }
                let padded = rect.insetBy(dx: -padding, dy: -padding)
                guard !placed.contains(where: { $0.intersects(padded) }) else { continue }
                let hitsObstacle = obstacles.contains { $0.intersects(padded) }

                var score = 0.0
                let toCenter = hypot(candidate.x - center.x, candidate.y - center.y) / diagonal
                if let previous {
                    let step = hypot(candidate.x - previous.x, candidate.y - previous.y)
                    score -= abs(step - idealStep) / idealStep
                    // Gentle left-to-right drift keeps the reading order natural.
                    score += Double((candidate.x - previous.x) / bounds.width) * 0.6
                }
                if isKey {
                    score -= toCenter * 4
                } else {
                    // Leave the middle free for keywords, but don't hug the edges.
                    score += min(toCenter, 0.22) * 2 - max(0, toCenter - 0.4) * 2
                }
                if hitsObstacle { score -= 3 }
                if best == nil || score > best!.score { best = (rect, score) }
            }

            if best == nil {
                // Too crowded to avoid overlaps: anywhere inside the bounds will do.
                let w = max(0, bounds.width - size.width), h = max(0, bounds.height - size.height)
                let origin = CGPoint(x: bounds.minX + w * CGFloat.random(in: 0...1, using: &rng),
                                     y: bounds.minY + h * CGFloat.random(in: 0...1, using: &rng))
                best = (CGRect(origin: origin, size: size), 0)
            }
            placed.append(best!.rect)
        }
        return placed
    }

    private static func candidatePoint(
        attempt: Int, isKey: Bool, previous: CGPoint?, center: CGPoint,
        bounds: CGRect, step: CGFloat, rng: inout SeededRandom
    ) -> CGPoint {
        if isKey && attempt % 2 == 0 {
            // Somewhere in the central region.
            return CGPoint(x: center.x + bounds.width * 0.2 * CGFloat.random(in: -1...1, using: &rng),
                           y: center.y + bounds.height * 0.18 * CGFloat.random(in: -1...1, using: &rng))
        }
        guard let previous else {
            return CGPoint(x: bounds.minX + bounds.width * CGFloat.random(in: 0.05...0.6, using: &rng),
                           y: bounds.minY + bounds.height * CGFloat.random(in: 0.1...0.9, using: &rng))
        }
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let distance = step * CGFloat.random(in: 0.6...1.5, using: &rng)
        return CGPoint(x: previous.x + cos(angle) * distance, y: previous.y + sin(angle) * distance)
    }
}
