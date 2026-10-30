import AppKit
import OSLog
import LyricscapeCore

/// Hosts the active `LyricStyle` in a tree of Core Animation layers and drives it
/// with a display link: 60 fps while playing, stopped while paused.
@MainActor
final class LyricsStageView: NSView {
    private let spotify: SpotifyMonitor
    private let lyrics: LyricsController
    private let settings: AppSettings

    private let backgroundLayer = CALayer()
    private let styleRoot = CALayer()
    private let ambientLayer = CATextLayer()
    private var style: any LyricStyle
    private var styleID: String
    private var displayLink: CADisplayLink?
    private var stateTask: Task<Void, Never>?
    private var ambientIndex: Int?
    private var stageMode: Bool?
    /// Theme chosen for the current play, and the hues of recent plays to avoid.
    private var themeKey: String?
    private var playTheme = LyricTheme.neonPink
    private var recentHues: [Double] = []
    private var rng = SystemRandomNumberGenerator()

    init(frame: CGRect, spotify: SpotifyMonitor, lyrics: LyricsController, settings: AppSettings) {
        self.spotify = spotify
        self.lyrics = lyrics
        self.settings = settings
        styleID = settings.styleID
        style = StyleRegistry.style(withID: styleID).init(root: styleRoot)
        super.init(frame: frame)

        // Layer-hosting view: we own the layer tree, AppKit doesn't touch it.
        let root = CALayer()
        root.isGeometryFlipped = true // y grows downwards, like the layout code expects
        layer = root
        wantsLayer = true
        for sublayer in [backgroundLayer, styleRoot, ambientLayer] { root.addSublayer(sublayer) }
        ambientLayer.alignmentMode = .center
        ambientLayer.isWrapped = true
        ambientLayer.opacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // AppKit keeps a hosted layer's geometry in sync with the view's own coordinate
    // system, so the view must be flipped too for the layer tree's y to grow downwards.
    override var isFlipped: Bool { true }

    func start() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link

        // While paused the display link is stopped; this cheap loop notices play,
        // offset and settings changes and redraws the frozen frame.
        stateTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.syncRunState()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        stateTask?.cancel()
        stateTask = nil
        style.reset()
    }

    @objc private func step(_ link: CADisplayLink) {
        render()
    }

    private func syncRunState() {
        if settings.styleID != styleID {
            style.reset()
            styleRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
            styleID = settings.styleID
            style = StyleRegistry.style(withID: styleID).init(root: styleRoot)
        }
        if settings.stageMode != stageMode {
            stageMode = settings.stageMode
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            backgroundLayer.backgroundColor = settings.stageMode ? CGColor.black : CGColor.clear
            CATransaction.commit()
        }
        displayLink?.isPaused = !spotify.isPlaying
        if !spotify.isPlaying { render() }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for sublayer in [backgroundLayer, styleRoot] where sublayer.frame != bounds { sublayer.frame = bounds }

        guard spotify.connection == .connected, let track = spotify.track,
              let document = lyrics.document, !document.lines.isEmpty else {
            styleRoot.isHidden = true
            showAmbient(nil, settings: settings.styleSettings)
            return
        }
        let playback = spotify.position()

        if !document.isSynced {
            // Plain lyrics: step slowly through the lines in proportion to the song.
            styleRoot.isHidden = true
            let progress = playback / max(track.duration, 1)
            let index = min(document.lines.count - 1, max(0, Int(progress * Double(document.lines.count))))
            showAmbient((index, document.lines[index].text),
                        settings: effectiveSettings(trackKey: "\(track.id)#\(spotify.playID)"))
            return
        }

        showAmbient(nil, settings: settings.styleSettings)
        styleRoot.isHidden = false
        let position = lyrics.position(at: playback)
        let styleSettings = effectiveSettings(trackKey: "\(track.id)#\(spotify.playID)")
        style.update(LyricFrame(
            time: position.time,
            document: document,
            position: position,
            isPlaying: spotify.isPlaying,
            track: track,
            playID: spotify.playID,
            size: bounds.size,
            topInset: topInset,
            scale: window?.backingScaleFactor ?? 2,
            settings: styleSettings,
            opaqueBackground: settings.stageMode
        ))
    }

    /// Space taken at the top of the screen by the menu bar or the camera notch
    /// (which stays black even over full-screen apps).
    private var topInset: CGFloat {
        guard let screen = window?.screen else { return 0 }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return max(screen.safeAreaInsets.top, menuBar)
    }

    /// Unsynced lyrics: one soft line at a time, cross-fading slowly.
    /// The user's style settings, with this play's generated theme when the theme
    /// changes on every play.
    private func effectiveSettings(trackKey: String) -> StyleSettings {
        var s = settings.styleSettings
        guard s.themeMode == .newEachPlay else { return s }
        if trackKey != themeKey {
            themeKey = trackKey
            let hue = HuePicker.next(avoiding: recentHues, using: &rng)
            recentHues = Array((recentHues + [hue]).suffix(HuePicker.memory))
            let lineHue = (hue + Double.random(in: 0.06...0.14, using: &rng) * (Bool.random(using: &rng) ? 1 : -1) + 1)
                .truncatingRemainder(dividingBy: 1)
            playTheme = .neon(hue: hue, lineHue: lineHue)
            Logger.app.notice("🎨 Theme for this play: \(self.playTheme.name, privacy: .public)")
        }
        s.theme = playTheme
        return s
    }

    private func showAmbient(_ line: (index: Int, text: String)?, settings s: StyleSettings) {
        guard let line else {
            ambientIndex = nil
            ambientLayer.opacity = 0
            return
        }
        guard line.index != ambientIndex else { return }
        ambientIndex = line.index

        let fontSize = min(bounds.width, bounds.height) * 0.035 * s.sizeScale
        ambientLayer.contentsScale = window?.backingScaleFactor ?? 2
        ambientLayer.frame = CGRect(x: bounds.width * 0.15, y: bounds.midY - fontSize * 1.5,
                                    width: bounds.width * 0.7, height: fontSize * 3.5)
        ambientLayer.shadowColor = s.theme.glow.cgColor
        ambientLayer.shadowOpacity = 0.6
        ambientLayer.shadowRadius = fontSize * 0.3 * s.glow
        ambientLayer.shadowOffset = .zero

        let fade = CATransition()
        fade.type = .fade
        fade.duration = 1.5
        ambientLayer.add(fade, forKey: "fade")
        ambientLayer.string = NSAttributedString(string: line.text, attributes: [
            .font: s.font(size: fontSize, weight: .medium),
            .foregroundColor: s.theme.text.withAlpha(0.7).nsColor,
        ])
        ambientLayer.opacity = 1
    }
}
