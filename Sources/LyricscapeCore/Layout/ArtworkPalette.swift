import Foundation

/// Finds the dominant vivid hues in cover art. Greys, near-blacks and near-whites
/// are ignored; pixels count more the more saturated and bright they are.
public enum ArtworkPalette {
    /// - Parameter pixels: RGB values in 0…1 (a small thumbnail is plenty).
    /// - Returns: up to `count` hues (0…1), strongest first, at least ~40° apart.
    ///   Empty for black-and-white artwork.
    public static func dominantHues(pixels: [(r: Double, g: Double, b: Double)], count: Int = 3) -> [Double] {
        let bins = 36
        var histogram = [Double](repeating: 0, count: bins)
        for p in pixels {
            let (h, s, v) = hsv(p.r, p.g, p.b)
            guard s > 0.25, v > 0.2 else { continue }
            histogram[min(bins - 1, Int(h * Double(bins)))] += s * v
        }
        // Smooth around the wheel so a hue split across two bins still wins.
        let smoothed = histogram.indices.map { i in
            histogram[(i + bins - 1) % bins] * 0.5 + histogram[i] + histogram[(i + 1) % bins] * 0.5
        }
        let total = histogram.reduce(0, +)
        guard total > 0 else { return [] }

        var hues: [Double] = []
        for i in smoothed.indices.sorted(by: { smoothed[$0] > smoothed[$1] }) {
            guard smoothed[i] > total * 0.04 else { break } // ignore specks
            let hue = (Double(i) + 0.5) / Double(bins)
            let farEnough = hues.allSatisfy { h in
                let d = abs(h - hue)
                return min(d, 1 - d) >= 0.11
            }
            if farEnough { hues.append(hue) }
            if hues.count == count { break }
        }
        return hues
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        guard delta > 0 else { return (0, 0, maxC) }
        var h: Double
        if maxC == r { h = (g - b) / delta } else if maxC == g { h = (b - r) / delta + 2 } else { h = (r - g) / delta + 4 }
        h /= 6
        if h < 0 { h += 1 }
        return (h, delta / maxC, maxC)
    }
}
