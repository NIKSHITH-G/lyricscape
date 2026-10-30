import AppKit
import SwiftUI

/// Owns the Settings window. The SwiftUI content (and its live preview) is torn down
/// whenever the window closes so nothing animates in the background.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let lyrics: LyricsController
    private let audio: AudioController
    private let subtitles: SubtitleService
    private var window: NSWindow?
    /// Kept across openings so the style thumbnails only render once.
    private let thumbnails = StyleThumbnails()

    init(settings: AppSettings, lyrics: LyricsController, audio: AudioController, subtitles: SubtitleService) {
        self.settings = settings
        self.lyrics = lyrics
        self.audio = audio
        self.subtitles = subtitles
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Lyricscape Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0.043, green: 0.035, blue: 0.067, alpha: 1)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(
                settings: settings, lyrics: lyrics, audio: audio, subtitles: subtitles, ui: SettingsUIModel(),
                thumbnails: thumbnails))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
