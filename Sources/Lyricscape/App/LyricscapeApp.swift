import OSLog
import SwiftUI

@main
struct LyricscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Lyricscape", systemImage: "quote.bubble") {
            MenuBarView(spotify: appDelegate.spotify, lyrics: appDelegate.lyrics, settings: appDelegate.settings,
                        openSettings: { appDelegate.showSettings() })
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spotify = SpotifyMonitor()
    let lyrics = LyricsController()
    let settings = AppSettings()
    let audio = AudioController()
    let subtitles = SubtitleService()
    /// `--demo`: the overlay plays the built-in demo song instead of following Spotify.
    private let demoMode = CommandLine.arguments.contains("--demo")
    private lazy var overlay = OverlayWindowController(
        settings: settings, spotify: spotify, lyrics: lyrics,
        source: demoMode ? DemoLyricSource() : LiveLyricSource(spotify: spotify, lyrics: lyrics, audioReactor: audio.reactor),
        subtitles: subtitles)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, lyrics: lyrics, audio: audio, subtitles: subtitles)
    private var registeredHotKeys: [HotKeyAction: HotKey] = [:]
    private var audioEnabled: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        Logger.app.notice("Lyricscape started\(self.demoMode ? " (demo mode)" : "", privacy: .public)")
        spotify.onTrackChange = { [lyrics] track in lyrics.trackDidChange(track) }
        spotify.start()
        lyrics.startLineLog(spotify: spotify)

        settings.onChange = { [weak self] in self?.settingsChanged() }
        settingsChanged()
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func settingsChanged() {
        overlay.update()
        if settings.audioReactive != audioEnabled {
            audioEnabled = settings.audioReactive
            audio.setEnabled(settings.audioReactive && !demoMode)
        }
        if settings.hotKeys != registeredHotKeys {
            registeredHotKeys = settings.hotKeys
            HotKeyCenter.shared.registerAll(settings.hotKeys) { [weak self] action in self?.perform(action) }
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .toggleOverlay:
            settings.overlayVisible.toggle()
        case .toggleStage:
            settings.stageMode.toggle()
            // Stage mode is only visible with the overlay on.
            if settings.stageMode { settings.overlayVisible = true }
        case .nextStyle:
            settings.cycleStyle()
            settings.overlayVisible = true
            Logger.app.notice("🎭 Style: \(StyleRegistry.style(withID: self.settings.styleID).displayName, privacy: .public)")
        }
    }
}
