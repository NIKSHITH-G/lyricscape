import AppKit
import LyricscapeCore

/// Hosts the active `LyricStyle` in a tree of Core Animation layers and drives it
/// with a display link: 60 fps while playing, stopped while paused. Used full-screen
/// for the overlay and small for the Settings preview.
@MainActor
final class LyricsStageView: NSView {
    private let source: any LyricSource
    private let settings: AppSettings
    private let themes: ThemeDirector
    private let subtitles: SubtitleService
    /// Preview: always on black, no menu-bar inset.
    private let isPreview: Bool

    private let backgroundLayer = CALayer()
    private let styleRoot = CALayer()
    private let ambientLayer = CATextLayer()
    private let subtitleLayer = CATextLayer()
    private var style: any LyricStyle
    private var styleID: String
    private var displayLink: CADisplayLink?
    private var stateTask: Task<Void, Never>?
    private var ambientIndex: Int?
    private var subtitleText: String?
    private var backgroundIsOpaque: Bool?

    init(frame: CGRect, source: any LyricSource, settings: AppSettings, themes: ThemeDirector,
         subtitles: SubtitleService, isPreview: Bool = false) {
        self.source = source
        self.settings = settings
        self.themes = themes
        self.subtitles = subtitles
        self.isPreview = isPreview
        styleID = settings.styleID
        style = StyleRegistry.style(withID: styleID).init(root: styleRoot)
        super.init(frame: frame)

        // Layer-hosting view: we own the layer tree, AppKit doesn't touch it.
        let root = CALayer()
        root.isGeometryFlipped = true // y grows downwards, like the layout code expects
        root.masksToBounds = true
        layer = root
        wantsLayer = true
        for sublayer in [backgroundLayer, styleRoot, ambientLayer, subtitleLayer] { root.addSublayer(sublayer) }
        for text in [ambientLayer, subtitleLayer] {
            text.alignmentMode = .center
            text.isWrapped = true
            text.opacity = 0
        }
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
            styleRoot.transform = CATransform3DIdentity
            styleID = settings.styleID
            style = StyleRegistry.style(withID: styleID).init(root: styleRoot)
        }
        let wantsOpaque = isPreview || settings.stageMode
        if wantsOpaque != backgroundIsOpaque {
            backgroundIsOpaque = wantsOpaque
            CATransaction.begin()
            CATransaction.setAnimationDuration(isPreview ? 0 : 0.4)
            backgroundLayer.backgroundColor = wantsOpaque ? CGColor.black : CGColor.clear
            CATransaction.commit()
        }
        displayLink?.isPaused = !source.isPlaying
        if !source.isPlaying { render() }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for sublayer in [backgroundLayer, styleRoot] where sublayer.frame != bounds { sublayer.frame = bounds }
        styleRoot.opacity = Float(settings.styleSettings.opacity)

        guard let track = source.track, let document = source.document, !document.lines.isEmpty else {
            styleRoot.isHidden = true
            showAmbient(nil, settings: settings.styleSettings)
            showSubtitle(nil, settings: settings.styleSettings)
            return
        }
        let playback = source.playbackPosition()
        let styleSettings = themes.settings(for: track, playID: source.playID, base: settings.styleSettings)

        if !document.isSynced {
            // Plain lyrics: step slowly through the lines in proportion to the song.
            styleRoot.isHidden = true
            let progress = playback / max(track.duration, 1)
            let index = min(document.lines.count - 1, max(0, Int(progress * Double(document.lines.count))))
            showAmbient((index, document.lines[index].text), settings: styleSettings)
            showSubtitle(subtitles.subtitle(for: document.lines[index].text, mode: settings.subtitleMode), settings: styleSettings)
            return
        }

        showAmbient(nil, settings: styleSettings)
        styleRoot.isHidden = false
        let position = source.lyricPosition(at: playback)
        style.update(LyricFrame(
            time: position.time,
            document: document,
            position: position,
            isPlaying: source.isPlaying,
            track: track,
            playID: source.playID,
            size: bounds.size,
            topInset: isPreview ? 0 : topInset,
            scale: window?.backingScaleFactor ?? 2,
            settings: styleSettings,
            opaqueBackground: isPreview || settings.stageMode,
            audio: settings.audioReactive ? source.audio : .silent
        ))

        let lineIndex = position.lineIndex ?? position.lastLineIndex
        let text = lineIndex.flatMap { subtitles.subtitle(for: document.lines[$0].text, mode: settings.subtitleMode) }
        showSubtitle(text, settings: styleSettings)
    }

    /// Space taken at the top of the screen by the menu bar or the camera notch
    /// (which stays black even over full-screen apps).
    private var topInset: CGFloat {
        guard let screen = window?.screen else { return 0 }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return max(screen.safeAreaInsets.top, menuBar)
    }

    /// Unsynced lyrics: one soft line at a time, cross-fading slowly.
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

    /// Translation / romanization under the visuals, shared by every style.
    private func showSubtitle(_ text: String?, settings s: StyleSettings) {
        guard text != subtitleText else { return }
        subtitleText = text
        guard let text, !text.isEmpty else {
            subtitleLayer.opacity = 0
            return
        }
        let fontSize = max(11, min(bounds.width, bounds.height) * 0.024)
        subtitleLayer.contentsScale = window?.backingScaleFactor ?? 2
        subtitleLayer.frame = CGRect(x: bounds.width * 0.1, y: bounds.height * 0.86 - fontSize * 2.6,
                                     width: bounds.width * 0.8, height: fontSize * 2.8)
        subtitleLayer.shadowColor = CGColor.black
        subtitleLayer.shadowOpacity = 0.9
        subtitleLayer.shadowRadius = 6
        subtitleLayer.shadowOffset = .zero
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.35
        subtitleLayer.add(fade, forKey: "fade")
        subtitleLayer.string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: s.theme.text.withAlpha(0.8).nsColor,
        ])
        subtitleLayer.opacity = 1
    }
}
