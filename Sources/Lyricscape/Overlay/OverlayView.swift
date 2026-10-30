import LyricscapeCore
import SwiftUI

/// What the simple text overlay shows. It only changes when a word or line
/// changes (a few times a second); the fade within a word is a GPU animation.
enum SimpleOverlayContent: Equatable {
    case none
    case synced(SyncedLineState)
    case unsynced(index: Int, text: String)
}

struct SyncedLineState: Equatable {
    var lineIndex: Int?
    var line: LyricLine?
    var nextIndex: Int?
    var nextText: String?
    var wordIndex: Int
}

/// Samples the playback position ~30×/s while playing (4×/s while paused) and
/// publishes `content` only when something visible changed, so SwiftUI re-renders
/// a handful of times a second instead of every frame.
@MainActor @Observable
final class SimpleOverlayTicker {
    private(set) var content: SimpleOverlayContent = .none

    @ObservationIgnored private let spotify: SpotifyMonitor
    @ObservationIgnored private let lyrics: LyricsController
    @ObservationIgnored private var task: Task<Void, Never>?

    init(spotify: SpotifyMonitor, lyrics: LyricsController) {
        self.spotify = spotify
        self.lyrics = lyrics
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let next = self.currentContent()
                if next != self.content { self.content = next }
                try? await Task.sleep(for: .milliseconds(self.spotify.isPlaying ? 33 : 250))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func currentContent() -> SimpleOverlayContent {
        guard spotify.connection == .connected, let document = lyrics.document, !document.lines.isEmpty else {
            return .none
        }
        let playback = spotify.position()
        if !document.isSynced {
            // Step through the lines slowly, in proportion to the song.
            let duration = max(spotify.track?.duration ?? 0, 1)
            let index = min(document.lines.count - 1, max(0, Int(playback / duration * Double(document.lines.count))))
            return .unsynced(index: index, text: document.lines[index].text)
        }
        let p = lyrics.position(at: playback)
        return .synced(SyncedLineState(
            lineIndex: p.lineIndex,
            line: p.lineIndex.map { document.lines[$0] },
            nextIndex: p.nextLineIndex,
            nextText: p.nextLineIndex.map { document.lines[$0].text },
            wordIndex: p.wordIndex ?? -1
        ))
    }
}

/// Root view of the overlay window. Stage 3 draws simple text; stage 4 swaps the
/// middle for the pluggable LyricStyle renderers.
struct OverlayView: View {
    let spotify: SpotifyMonitor
    let lyrics: LyricsController
    let settings: AppSettings
    let ticker: SimpleOverlayTicker


    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(settings.stageMode ? Color.black : Color.clear)
                    .animation(.easeInOut(duration: 0.4), value: settings.stageMode)

                lyricsContent(size: geo.size)

                VStack {
                    Spacer()
                    if let message = statusMessage {
                        Text(message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.35), in: Capsule())
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, geo.size.height * 0.06)
                .animation(.easeInOut(duration: 0.5), value: statusMessage)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func lyricsContent(size: CGSize) -> some View {
        let fontSize = min(size.width / 16, size.height / 9, 96)
        switch ticker.content {
        case .none:
            EmptyView()
        case .synced(let state):
            SimpleSyncedLyrics(state: state, fontSize: fontSize)
                .frame(width: size.width * 0.8)
        case .unsynced(let index, let text):
            Text(text)
                .font(.system(size: fontSize * 0.6, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 8)
                .frame(width: size.width * 0.7)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 1.5), value: index)
        }
    }

    /// Small note at the bottom explaining why there are no lyrics on screen.
    private var statusMessage: String? {
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

/// The current line with sung words lit up, and the next line faded below.
///
/// Each word is its own view, so lighting one up only animates that layer's
/// opacity on the GPU; the glyphs (and their glow) are rasterized once per line.
private struct SimpleSyncedLyrics: View {
    let state: SyncedLineState
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: fontSize * 0.45) {
            ZStack {
                if let lineIndex = state.lineIndex, let line = state.line {
                    CenteredFlowLayout(spacing: fontSize * 0.26, lineSpacing: fontSize * 0.1) {
                        ForEach(Array(line.words.enumerated()), id: \.offset) { i, word in
                            let lit = i <= state.wordIndex
                            Text(word.text)
                                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.55), radius: 10)
                                .shadow(color: .white.opacity(0.25), radius: 18) // soft glow
                                .opacity(lit ? 1 : 0.4)
                                // Fade in over the time the word is sung.
                                .animation(lit ? .linear(duration: max(0.05, word.duration)) : nil, value: lit)
                        }
                    }
                    .id(lineIndex)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                            removal: .opacity.combined(with: .offset(y: -fontSize * 0.4))))
                }
            }
            ZStack {
                if let nextIndex = state.nextIndex, let nextText = state.nextText {
                    Text(nextText)
                        .font(.system(size: fontSize * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.55), radius: 8)
                        .id(nextIndex)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: state.lineIndex)
        .animation(.easeOut(duration: 0.3), value: state.nextIndex)
    }
}

/// Lays subviews out left to right, wrapping onto new rows, each row centered.
struct CenteredFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            // Small tolerance: when placing, the bounds can be a hair narrower than the
            // width we measured (pixel rounding), which must not wrap the last word.
            if added > maxWidth + 1, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
