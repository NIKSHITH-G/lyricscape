import LyricscapeCore
import SwiftUI

struct MenuBarView: View {
    let spotify: SpotifyMonitor
    let lyrics: LyricsController
    @Bindable var settings: AppSettings
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lyricscape").font(.headline)
            status
            if let track = spotify.track, spotify.connection == .connected {
                nowPlaying(track)
                Divider()
                lyricsSection
            }
            Divider()
            overlaySection
            Divider()
            HStack {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit Lyricscape") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private var status: some View {
        switch spotify.connection {
        case .checking:
            Label("Looking for Spotify…", systemImage: "hourglass")
        case .notInstalled:
            Label("The Spotify desktop app isn't installed.", systemImage: "questionmark.circle")
        case .notRunning:
            Label("Open Spotify and play a song.", systemImage: "moon.zzz")
        case .permissionDenied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Lyricscape needs permission to read Spotify.", systemImage: "lock")
                Text("Open System Settings → Privacy & Security → Automation, expand Lyricscape and turn on Spotify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        case .connected:
            if spotify.track == nil {
                Label("Nothing playing in Spotify.", systemImage: "music.note")
            }
        }
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title).font(.body.bold()).lineLimit(1)
            Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            // Only redraw continuously while playing, to keep CPU usage low.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spotify.isPlaying)) { _ in
                let position = spotify.position()
                VStack(spacing: 2) {
                    ProgressView(value: min(position, max(track.duration, 1)), total: max(track.duration, 1))
                    HStack {
                        Text(TimeFormat.string(position, millis: true))
                        Spacer()
                        Image(systemName: spotify.isPlaying ? "play.fill" : "pause.fill")
                        Spacer()
                        Text(TimeFormat.string(track.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var lyricsSection: some View {
        switch lyrics.state {
        case .idle:
            EmptyView()
        case .notApplicable(let kind):
            Label(kind == .ad ? "Advertisement — no lyrics" : "Podcast — no lyrics", systemImage: "text.badge.xmark")
                .foregroundStyle(.secondary)
        case .loading:
            Label("Finding lyrics…", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .instrumental:
            Label("Instrumental", systemImage: "pianokeys")
                .foregroundStyle(.secondary)
        case .notFound:
            lyricsUnavailable("No lyrics found for this song")
        case .failed:
            lyricsUnavailable("Couldn't reach the lyrics service")
        case .loaded(let document):
            VStack(alignment: .leading, spacing: 8) {
                if document.isSynced {
                    currentLine(document)
                    offsetControl
                } else {
                    Label("Only unsynced lyrics available", systemImage: "text.alignleft")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func lyricsUnavailable(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "text.badge.xmark").foregroundStyle(.secondary)
            Spacer()
            Button("Retry") { lyrics.reload() }.controlSize(.small)
        }
    }

    private func currentLine(_ document: LyricsDocument) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spotify.isPlaying)) { _ in
            let p = lyrics.position(at: spotify.position())
            let current = p.lineIndex.map { document.lines[$0].text }
            let next = p.nextLineIndex.map { document.lines[$0].text }
            VStack(alignment: .leading, spacing: 3) {
                Text(current ?? "♪")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if let next {
                    Text(next).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.overlayVisible) {
                shortcutLabel("Show lyrics on screen", .toggleOverlay)
            }
            Toggle(isOn: $settings.stageMode) {
                shortcutLabel("Stage mode (black background)", .toggleStage)
            }
            .disabled(!settings.overlayVisible)
            HStack {
                Picker("Style", selection: $settings.styleID) {
                    ForEach(StyleRegistry.ids, id: \.self) { id in
                        Text(StyleRegistry.style(withID: id).displayName).tag(id)
                    }
                }
                Text(settings.hotKeys[.nextStyle]?.displayString ?? "")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if NSScreen.screens.count > 1 {
                Picker("Display", selection: $settings.displayID) {
                    Text("Main display").tag(CGDirectDisplayID?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
                .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func shortcutLabel(_ title: String, _ action: HotKeyAction) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(settings.hotKeys[action]?.displayString ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private var offsetControl: some View {
        HStack(spacing: 6) {
            Text("Timing").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { lyrics.adjustOffset(by: -0.1) } label: { Image(systemName: "minus") }
                .help("Show lyrics later")
            Text(offsetLabel)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 92)
            Button { lyrics.adjustOffset(by: 0.1) } label: { Image(systemName: "plus") }
                .help("Show lyrics earlier")
            Button { lyrics.offset = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset timing")
                .disabled(lyrics.offset == 0)
        }
        .controlSize(.small)
    }

    private var offsetLabel: String {
        if lyrics.offset == 0 { return "in sync" }
        return String(format: "%.1f s %@", abs(lyrics.offset), lyrics.offset > 0 ? "earlier" : "later")
    }
}
