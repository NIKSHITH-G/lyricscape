import AppKit
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
            showAmbient(nil)
            return
        }
        let playback = spotify.position()

        if !document.isSynced {
            // Plain lyrics: step slowly through the lines in proportion to the song.
            styleRoot.isHidden = true
            let progress = playback / max(track.duration, 1)
            let index = min(document.lines.count - 1, max(0, Int(progress * Double(document.lines.count))))
            showAmbient((index, document.lines[index].text))
            return
        }

        showAmbient(nil)
        styleRoot.isHidden = false
        let position = lyrics.position(at: playback)
        style.update(LyricFrame(
            time: position.time,
            document: document,
            position: position,
            isPlaying: spotify.isPlaying,
            trackKey: track.id,
            size: bounds.size,
            scale: window?.backingScaleFactor ?? 2,
            settings: settings.styleSettings,
            opaqueBackground: settings.stageMode
        ))
    }

    /// Unsynced lyrics: one soft line at a time, cross-fading slowly.
    private func showAmbient(_ line: (index: Int, text: String)?) {
        guard let line else {
            ambientIndex = nil
            ambientLayer.opacity = 0
            return
        }
        guard line.index != ambientIndex else { return }
        ambientIndex = line.index

        let s = settings.styleSettings
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
