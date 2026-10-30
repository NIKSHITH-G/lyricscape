import AppKit
import OSLog
import SwiftUI

/// A borderless, transparent, click-through panel covering one display.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // Above normal windows and the Dock, just below the menu bar so the
        // Lyricscape menu stays reachable even in Stage mode.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        // Every Space, including over full-screen apps, and not moved by Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows/hides the overlay on the chosen display and keeps it there when displays change.
@MainActor
final class OverlayWindowController {
    private let settings: AppSettings
    private let spotify: SpotifyMonitor
    private let lyrics: LyricsController
    private let source: any LyricSource
    private let subtitles: SubtitleService
    private let themes = ThemeDirector()
    private var panel: OverlayPanel?
    private var stage: LyricsStageView?

    init(settings: AppSettings, spotify: SpotifyMonitor, lyrics: LyricsController,
         source: any LyricSource, subtitles: SubtitleService) {
        self.settings = settings
        self.spotify = spotify
        self.lyrics = lyrics
        self.source = source
        self.subtitles = subtitles
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Screen the overlay should be on: the chosen one if connected, else the main display.
    var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == settings.displayID } ?? NSScreen.screens.first
    }

    func update() {
        guard settings.overlayVisible, let screen = targetScreen else {
            hide()
            return
        }
        if panel == nil {
            let panel = OverlayPanel(screen: screen)
            let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))

            let stage = LyricsStageView(frame: container.bounds, source: source, settings: settings,
                                        themes: themes, subtitles: subtitles)
            stage.autoresizingMask = [.width, .height]
            container.addSubview(stage)

            if !(source is DemoLyricSource) {
                let status = NSHostingView(rootView: OverlayStatusView(spotify: spotify, lyrics: lyrics))
                status.sizingOptions = [] // the window sizes the view, never the other way round
                status.frame = container.bounds
                status.autoresizingMask = [.width, .height]
                container.addSubview(status)
            }

            panel.contentView = container
            stage.start()
            self.stage = stage
            self.panel = panel
            Logger.app.notice("🖥 Overlay shown on “\(screen.localizedName, privacy: .public)”")
        }
        if panel?.frame != screen.frame {
            panel?.setFrame(screen.frame, display: true)
        }
        panel?.orderFrontRegardless()
    }

    private func hide() {
        guard let panel else { return }
        // Tear the view down entirely so nothing keeps animating while hidden.
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        stage?.stop()
        stage = nil
        Logger.app.notice("🖥 Overlay hidden")
    }
}
