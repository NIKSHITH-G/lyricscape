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

    init(settings: AppSettings, lyrics: LyricsController, audio: AudioController, subtitles: SubtitleService) {
        self.settings = settings
        self.lyrics = lyrics
        self.audio = audio
        self.subtitles = subtitles
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Lyricscape Settings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(
                settings: settings, lyrics: lyrics, audio: audio, subtitles: subtitles, ui: SettingsUIModel()))
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
