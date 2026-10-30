import AppKit
import LyricscapeCore

/// Everything a style needs to draw one frame.
struct LyricFrame {
    /// Lyrics time (playback position + user offset), seconds.
    var time: TimeInterval
    var document: LyricsDocument
    var position: LyricPosition
    var isPlaying: Bool
    var track: Track
    /// Size of the drawing area in points (y grows downwards).
    var size: CGSize
    /// Height at the top covered by the menu bar / camera notch; keep content below it.
    var topInset: CGFloat
    var scale: CGFloat
    var settings: StyleSettings
    /// Stage mode: drawing on solid black rather than over other windows.
    var opaqueBackground: Bool

    /// Changes whenever the song changes; styles drop their per-song state when it does.
    var trackKey: String { track.id }

    var currentLine: LyricLine? { position.lineIndex.map { document.lines[$0] } }
    var upcomingLines: ArraySlice<LyricLine> {
        guard let next = position.nextLineIndex else { return [] }
        return document.lines[next...]
    }
}

/// A visual style. Each style owns a tree of Core Animation layers under `root` and
/// updates their properties every frame from the `LyricFrame`. Everything should be
/// derived from `frame.time` (not from how much time passed since the last call) so
/// seeking, pausing and the timing offset just work.
@MainActor
protocol LyricStyle: AnyObject {
    static var id: String { get }
    static var displayName: String { get }

    init(root: CALayer)

    /// Called every frame while playing (and occasionally while paused).
    func update(_ frame: LyricFrame)

    /// Remove all content, e.g. when the overlay is hidden.
    func reset()
}

enum StyleRegistry {
    @MainActor static let all: [any LyricStyle.Type] = [ConstellationStyle.self]

    @MainActor static func style(withID id: String) -> any LyricStyle.Type {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Settings shared by every style

struct RGBA: Codable, Equatable, Sendable {
    var r, g, b: Double
    var a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
}

struct LyricTheme: Codable, Equatable, Sendable {
    var name: String
    /// Text colour: a light tint reads as the bright core of a neon tube.
    var text: RGBA
    /// Glow around text and stars.
    var glow: RGBA
    /// Keywords and the current word.
    var accent: RGBA
    /// Connecting lines and secondary details.
    var line: RGBA

    static let neonPink = LyricTheme(
        name: "Neon Pink",
        text: RGBA(hex: 0xFFD6E6),
        glow: RGBA(hex: 0xFF2A6D),
        accent: RGBA(hex: 0xFFF2F7),
        line: RGBA(hex: 0xFF4F8B)
    )
}

struct StyleSettings: Codable, Equatable, Sendable {
    var theme: LyricTheme = .neonPink
    /// nil = system font (SF Pro Rounded).
    var fontName: String?
    var sizeScale: Double = 1
    var glow: Double = 1
    var speed: Double = 1
    /// How far apart / spread out words are.
    var spread: Double = 1
    /// Glowing neon border around the screen edge.
    var showFrame: Bool = true

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let fontName, let font = NSFont(name: fontName, size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: weight >= .semibold ? .boldFontMask : [])
        }
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = system.fontDescriptor.withDesign(.rounded) else { return system }
        return NSFont(descriptor: rounded, size: size) ?? system
    }
}

// MARK: - Animation helpers

enum Ease {
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - clamp01(x), 3) }
    /// Overshoots slightly past 1 before settling: a "pop".
    static func outBack(_ x: Double) -> Double {
        let t = clamp01(x), c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
