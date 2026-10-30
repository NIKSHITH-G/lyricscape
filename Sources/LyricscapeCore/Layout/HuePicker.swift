import Foundation

/// Picks a colour hue (0…1 around the colour wheel) for a new play that's clearly
/// different from the hues used recently.
public enum HuePicker {
    /// Minimum distance from each recent hue, as a fraction of the wheel (0.15 ≈ 54°).
    public static let minimumDistance = 0.15
    /// How many recent hues to avoid. With 3, the widest gap between them is at least
    /// a third of the wheel, so a hue ≥ 0.15 from all of them always exists.
    public static let memory = 3

    public static func next<R: RandomNumberGenerator>(avoiding recent: [Double], using rng: inout R) -> Double {
        let hues = recent.suffix(memory).map { $0 - floor($0) }.sorted()
        guard !hues.isEmpty else { return Double.random(in: 0..<1, using: &rng) }

        // The free arcs: each gap between neighbouring recent hues, minus the margin
        // at both ends. Pick uniformly across all of them.
        var arcs: [(start: Double, length: Double)] = []
        for (i, hue) in hues.enumerated() {
            let next = i + 1 < hues.count ? hues[i + 1] : hues[0] + 1
            let length = next - hue - 2 * minimumDistance
            if length > 0 { arcs.append((hue + minimumDistance, length)) }
        }
        let total = arcs.map(\.length).reduce(0, +)
        guard total > 0 else {
            // Can't happen with `memory` ≤ 3; fall back to the middle of the widest gap.
            let gaps = hues.indices.map { i in (hues[i], (i + 1 < hues.count ? hues[i + 1] : hues[0] + 1) - hues[i]) }
            let widest = gaps.max { $0.1 < $1.1 }!
            return (widest.0 + widest.1 / 2).truncatingRemainder(dividingBy: 1)
        }
        var pick = Double.random(in: 0..<total, using: &rng)
        for arc in arcs {
            if pick < arc.length { return (arc.start + pick).truncatingRemainder(dividingBy: 1) }
            pick -= arc.length
        }
        return (arcs[arcs.count - 1].start + arcs[arcs.count - 1].length / 2).truncatingRemainder(dividingBy: 1)
    }

    /// Shortest distance around the wheel to the nearest of `hues` (1 if none).
    static func distance(_ hue: Double, _ hues: [Double]) -> Double {
        hues.map { h in
            let d = abs(hue - h).truncatingRemainder(dividingBy: 1)
            return min(d, 1 - d)
        }.min() ?? 1
    }
}
