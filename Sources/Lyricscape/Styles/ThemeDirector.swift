import AppKit
import LyricscapeCore
import OSLog

/// Decides the colours for each play:
/// - `.newEachPlay`: a fresh neon hue, far from the last few plays.
/// - `.albumArt`: hues from the cover art, rotating through them (with a little
///   variation) on each play so a replay still looks different.
/// - `.fixed`: the user's chosen theme.
@MainActor
final class ThemeDirector {
    private var playKey: String?
    private var playTheme = LyricTheme.neonPink
    private var themeFromArtwork = false
    private var recentHues: [Double] = []
    private var rng = SystemRandomNumberGenerator()
    /// Dominant hues per cover image; empty array = black-and-white art.
    private var artworkHues: [URL: [Double]] = [:]
    private var loading: Set<URL> = []

    func settings(for track: Track, playID: Int, base: StyleSettings) -> StyleSettings {
        var s = base
        switch base.themeMode {
        case .fixed:
            return s
        case .newEachPlay, .albumArt:
            let key = "\(track.id)#\(playID)#\(base.themeMode.rawValue)"
            let artHues = base.themeMode == .albumArt ? hues(for: track) : nil
            // Re-pick when the play changes, or when the artwork finishes loading.
            if key != playKey || (artHues != nil && !(artHues!.isEmpty) && !themeFromArtwork) {
                playKey = key
                pickTheme(artHues: artHues, playID: playID)
            }
            s.theme = playTheme
            return s
        }
    }

    private func pickTheme(artHues: [Double]?, playID: Int) {
        let hue: Double
        if let artHues, !artHues.isEmpty {
            let base = artHues[playID % artHues.count]
            hue = (base + Double.random(in: -0.035...0.035, using: &rng) + 1).truncatingRemainder(dividingBy: 1)
            themeFromArtwork = true
        } else {
            hue = HuePicker.next(avoiding: recentHues, using: &rng)
            themeFromArtwork = false
        }
        recentHues = Array((recentHues + [hue]).suffix(HuePicker.memory))
        let lineHue: Double
        if let artHues, artHues.count > 1 {
            lineHue = artHues[(playID + 1) % artHues.count] // a second colour from the cover
        } else {
            let offset = Double.random(in: 0.06...0.14, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            lineHue = (hue + offset + 1).truncatingRemainder(dividingBy: 1)
        }
        playTheme = .neon(hue: hue, lineHue: lineHue)
        Logger.app.notice("🎨 Theme for this play: \(self.playTheme.name, privacy: .public)\(self.themeFromArtwork ? " (from album art)" : "", privacy: .public)")
    }

    /// Hues of the track's cover art, or nil while it's loading / unavailable.
    private func hues(for track: Track) -> [Double]? {
        guard let url = track.artworkURL else { return nil }
        if let hues = artworkHues[url] { return hues }
        if !loading.contains(url) {
            loading.insert(url)
            Task {
                let hues = await Self.loadHues(url)
                artworkHues[url] = hues
                loading.remove(url)
            }
        }
        return nil
    }

    private nonisolated static func loadHues(_ url: URL) async -> [Double] {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        // A 32×32 thumbnail is plenty to find the main colours.
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = stride(from: 0, to: bytes.count, by: 4).map {
            (r: Double(bytes[$0]) / 255, g: Double(bytes[$0 + 1]) / 255, b: Double(bytes[$0 + 2]) / 255)
        }
        return ArtworkPalette.dominantHues(pixels: pixels)
    }
}
