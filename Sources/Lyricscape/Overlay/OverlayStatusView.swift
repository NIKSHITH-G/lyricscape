import LyricscapeCore
import SwiftUI

/// Small note at the bottom of the overlay explaining why there are no lyrics on screen.
struct OverlayStatusView: View {
    let spotify: SpotifyMonitor
    let lyrics: LyricsController

    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.5), value: message)
    }

    private var message: String? {
        switch spotify.connection {
        case .checking, .notInstalled:
            return nil
        case .notRunning:
            return "Spotify isn't running"
        case .permissionDenied:
            return "Lyricscape can't read Spotify — allow it in System Settings › Privacy & Security › Automation"
        case .connected:
            break
        }
        guard let track = spotify.track else { return nil }
        switch lyrics.state {
        case .notFound: return "No lyrics found · \(track.title) — \(track.artist)"
        case .instrumental: return "♪ Instrumental"
        case .notApplicable(let kind): return kind == .ad ? "Advertisement" : "Podcast — no lyrics"
        case .failed: return "Couldn't reach the lyrics service"
        case .loaded(let document) where !document.isSynced: return "These lyrics aren't time-synced"
        case .idle, .loading, .loaded: return nil
        }
    }
}
