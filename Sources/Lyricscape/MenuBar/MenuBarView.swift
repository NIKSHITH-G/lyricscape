import LyricscapeCore
import SwiftUI

struct MenuBarView: View {
    let spotify: SpotifyMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lyricscape").font(.headline)
            status
            if let track = spotify.track, spotify.connection == .connected {
                nowPlaying(track)
            }
            Divider()
            Button("Quit Lyricscape") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
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
            if track.kind == .ad || track.kind == .podcast {
                Text(track.kind == .ad ? "Advertisement" : "Podcast")
                    .font(.caption2).foregroundStyle(.secondary)
            }
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
}
