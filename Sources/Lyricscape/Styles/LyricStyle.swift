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
    /// Increases each time a song (re)starts; see `SpotifyMonitor.playID`.
    var playID: Int
    /// Size of the drawing area in points (y grows downwards).
    var size: CGSize
    /// Height at the top covered by the menu bar / camera notch; keep content below it.
    var topInset: CGFloat
    var scale: CGFloat
    var settings: StyleSettings
    /// Stage mode: drawing on solid black rather than over other windows.
    var opaqueBackground: Bool
    /// Live audio analysis (`.silent` when audio reactivity is off).
    var audio: AudioLevels

    /// Usable drawing area: below the menu bar / notch, with a margin all round.
    func safeArea(margin: CGFloat = 0.06) -> CGRect {
        let top = topInset + size.height * margin
        return CGRect(x: size.width * margin, y: top,
                      width: size.width * (1 - 2 * margin), height: size.height * (1 - margin) - top)
    }

    /// Where a block of `blockSize` sits for the user's position setting.
    func anchored(_ blockSize: CGSize, in area: CGRect) -> CGPoint {
        let a = settings.anchor
        let x: CGFloat = switch a {
        case .topLeft, .bottomLeft: area.minX
        case .topRight, .bottomRight: area.maxX - blockSize.width
        default: area.midX - blockSize.width / 2
        }
        let y: CGFloat = switch a {
        case .top, .topLeft, .topRight: area.minY
        case .bottom, .bottomLeft, .bottomRight: area.maxY - blockSize.height
        default: area.midY - blockSize.height / 2
        }
        return CGPoint(x: x, y: y)
    }

    /// Changes with every new play of a song (even a replay of the same one); styles
    /// drop their per-song state, and seed their layouts, with it.
    var trackKey: String { "\(track.id)#\(playID)" }

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
    /// One line for the style picker.
    static var summary: String { get }

    init(root: CALayer)

    /// Called every frame while playing (and occasionally while paused).
    func update(_ frame: LyricFrame)

    /// Remove all content, e.g. when the overlay is hidden.
    func reset()
}

enum StyleRegistry {
    @MainActor static let all: [any LyricStyle.Type] = [
        ConstellationStyle.self, KineticStyle.self, KaraokeStyle.self, RainStyle.self, OrbitStyle.self,
        TypewriterStyle.self, GlitchStyle.self, ParticleStyle.self, MinimalStyle.self,
    ]

    /// Style IDs in display order. (A closure rather than `\.id`: key paths on
    /// existential metatypes crash this compiler.)
    @MainActor static var ids: [String] { all.map { $0.id } }

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

    init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
            .usingColorSpace(.sRGB) ?? .white
        self.init(c.redComponent, c.greenComponent, c.blueComponent, alpha)
    }

    var hue: Double {
        var h: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return Double(h)
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

    /// A neon palette around `hue`: a white-hot text core, a saturated glow, and
    /// links in a neighbouring hue so it isn't flat.
    static func neon(hue: Double, lineHue: Double) -> LyricTheme {
        // Deep blues look dim at full saturation; ease off a little there.
        let blueness = max(0, 1 - abs(hue - 0.66) / 0.1)
        return LyricTheme(
            name: "Neon \(Int(hue * 360))°",
            text: RGBA(hue: hue, saturation: 0.16, brightness: 1),
            glow: RGBA(hue: hue, saturation: 0.88 - 0.18 * blueness, brightness: 1),
            accent: RGBA(hue: hue, saturation: 0.05, brightness: 1),
            line: RGBA(hue: lineHue, saturation: 0.72, brightness: 1)
        )
    }

    static let neonPink = LyricTheme(
        name: "Neon Pink",
        text: RGBA(hex: 0xFFD6E6),
        glow: RGBA(hex: 0xFF2A6D),
        accent: RGBA(hex: 0xFFF2F7),
        line: RGBA(hex: 0xFF4F8B)
    )

    static let terminal = LyricTheme(
        name: "Terminal Green",
        text: RGBA(hex: 0x7CFF9B),
        glow: RGBA(hex: 0x00FF66),
        accent: RGBA(hex: 0xD8FFE2),
        line: RGBA(hex: 0x2EE86A)
    )

    /// Presets for a fixed theme.
    static let presets: [LyricTheme] = [
        .neonPink,
        .neon(hue: 0.55, lineHue: 0.62).named("Cyber Blue"),
        .neon(hue: 0.78, lineHue: 0.86).named("Ultraviolet"),
        .neon(hue: 0.07, lineHue: 0.0).named("Sunset"),
        .neon(hue: 0.13, lineHue: 0.09).named("Gold"),
        .neon(hue: 0.33, lineHue: 0.45).named("Toxic"),
        .neon(hue: 0.48, lineHue: 0.55).named("Aqua"),
        LyricTheme(name: "Ice", text: RGBA(hex: 0xF4FAFF), glow: RGBA(hex: 0x9CC9FF),
                   accent: RGBA(hex: 0xFFFFFF), line: RGBA(hex: 0xBFDFFF)),
        .terminal,
    ]

    func named(_ name: String) -> LyricTheme {
        var copy = self
        copy.name = name
        return copy
    }
}

enum ThemeMode: String, Codable, CaseIterable, Sendable {
    /// A fresh palette for every play, never close to the last few.
    case newEachPlay
    /// Colours from the cover art, varied on every play.
    case albumArt
    /// Always use `StyleSettings.theme`.
    case fixed

    var title: String {
        switch self {
        case .newEachPlay: "New every play"
        case .albumArt: "From album art"
        case .fixed: "Fixed"
        }
    }
}

/// Where on screen line-based styles (Karaoke, Typewriter, Minimal…) sit.
enum ScreenAnchor: String, Codable, CaseIterable, Sendable {
    case center, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    var title: String {
        switch self {
        case .center: "Centre"
        case .top: "Top"
        case .bottom: "Bottom"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

struct StyleSettings: Codable, Equatable, Sendable {
    var themeMode: ThemeMode = .newEachPlay
    /// Used when `themeMode` is `.fixed`.
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
    /// Overall opacity of the lyrics, 0.2…1.
    var opacity: Double = 1
    /// Position for line-based styles.
    var anchor: ScreenAnchor = .center

    init() {}

    // Decode field by field so settings saved by older versions keep working.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StyleSettings()
        themeMode = (try? c.decode(ThemeMode.self, forKey: .themeMode)) ?? d.themeMode
        theme = (try? c.decode(LyricTheme.self, forKey: .theme)) ?? d.theme
        fontName = try? c.decode(String.self, forKey: .fontName)
        sizeScale = (try? c.decode(Double.self, forKey: .sizeScale)) ?? d.sizeScale
        glow = (try? c.decode(Double.self, forKey: .glow)) ?? d.glow
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        spread = (try? c.decode(Double.self, forKey: .spread)) ?? d.spread
        showFrame = (try? c.decode(Bool.self, forKey: .showFrame)) ?? d.showFrame
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? d.opacity
        anchor = (try? c.decode(ScreenAnchor.self, forKey: .anchor)) ?? d.anchor
    }

    /// `fontName` is a font family ("Avenir Next"); nil = SF Pro Rounded.
    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let fontName {
            let bold = weight >= .semibold
            // NSFontManager weights run 0…15; 5 is regular, 9 bold.
            let managerWeight = weight >= .heavy ? 11 : bold ? 9 : 5
            if let font = NSFontManager.shared.font(withFamily: fontName, traits: bold ? .boldFontMask : [],
                                                    weight: managerWeight, size: size) {
                return font
            }
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
