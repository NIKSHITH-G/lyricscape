import OSLog
import SwiftUI

@main
struct LyricscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Lyricscape", systemImage: "quote.bubble") {
            MenuBarView(spotify: appDelegate.spotify, lyrics: appDelegate.lyrics)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spotify = SpotifyMonitor()
    let lyrics = LyricsController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.notice("Lyricscape started")
        spotify.onTrackChange = { [lyrics] track in lyrics.trackDidChange(track) }
        spotify.start()
        lyrics.startLineLog(spotify: spotify)
    }
}
