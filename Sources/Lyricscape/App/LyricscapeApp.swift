import OSLog
import SwiftUI

@main
struct LyricscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Lyricscape", systemImage: "quote.bubble") {
            MenuBarView(spotify: appDelegate.spotify, lyrics: appDelegate.lyrics, settings: appDelegate.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spotify = SpotifyMonitor()
    let lyrics = LyricsController()
    let settings = AppSettings()
    private lazy var overlay = OverlayWindowController(settings: settings, spotify: spotify, lyrics: lyrics)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.notice("Lyricscape started")
        spotify.onTrackChange = { [lyrics] track in lyrics.trackDidChange(track) }
        spotify.start()
        lyrics.startLineLog(spotify: spotify)

        settings.onChange = { [weak self] in self?.overlay.update() }
        overlay.update()

        HotKeyCenter.shared.register(.toggleOverlay) { [settings] in settings.overlayVisible.toggle() }
        HotKeyCenter.shared.register(.toggleStage) { [settings] in
            settings.stageMode.toggle()
            // Stage mode is only visible with the overlay on.
            if settings.stageMode { settings.overlayVisible = true }
        }
    }
}
