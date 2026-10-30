import Foundation
import LyricscapeCore
import Observation
import OSLog

enum LyricsState: Equatable {
    /// Nothing is playing.
    case idle
    /// An ad or podcast: not something we look up lyrics for.
    case notApplicable(ContentKind)
    case loading
    case loaded(LyricsDocument)
    case instrumental
    case notFound
    case failed(String)
}

/// Loads lyrics for the current track and maps playback time to lyric positions.
@MainActor @Observable
final class LyricsController {
    private(set) var state: LyricsState = .idle
    private(set) var track: Track?
    private(set) var engine: SyncEngine?

    /// Seconds; positive shows lyrics earlier. Persisted.
    var offset: TimeInterval {
        didSet {
            engine?.offset = offset
            UserDefaults.standard.set(offset, forKey: Self.offsetKey)
        }
    }

    var document: LyricsDocument? {
        if case .loaded(let document) = state { document } else { nil }
    }

    @ObservationIgnored private let provider = LyricsProvider()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var logTask: Task<Void, Never>?
    private static let offsetKey = "lyricsOffset"

    init() {
        offset = UserDefaults.standard.double(forKey: Self.offsetKey)
    }

    func position(at playbackTime: TimeInterval) -> LyricPosition {
        engine?.position(at: playbackTime) ?? .idle(at: playbackTime + offset)
    }

    func adjustOffset(by delta: TimeInterval) {
        offset = ((offset + delta) * 10).rounded() / 10
    }

    // MARK: - Loading

    func trackDidChange(_ newTrack: Track?) {
        guard newTrack?.id != track?.id else { return }
        track = newTrack
        engine = nil
        loadTask?.cancel()

        guard let newTrack else {
            state = .idle
            return
        }
        guard newTrack.kind.mayHaveLyrics else {
            state = .notApplicable(newTrack.kind)
            Logger.lyrics.notice("🔇 No lyrics for \(newTrack.kind == .ad ? "ads" : "podcasts", privacy: .public)")
            return
        }
        load(newTrack)
    }

    /// Ignores the cached copy and downloads again.
    func reload() {
        guard let track, track.kind.mayHaveLyrics else { return }
        loadTask?.cancel()
        loadTask = Task {
            await provider.forget(track)
            load(track)
        }
    }

    private func load(_ track: Track) {
        state = .loading
        loadTask = Task {
            // Retry network failures a few times (e.g. Wi-Fi just reconnected).
            for attempt in 0..<3 {
                do {
                    let (result, source) = try await provider.lyrics(for: track)
                    guard !Task.isCancelled, self.track?.id == track.id else { return }
                    apply(result, source: source, for: track)
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    Logger.lyrics.error("⚠️ Couldn't reach LRCLIB (attempt \(attempt + 1, privacy: .public)/3): \(error.localizedDescription, privacy: .public)")
                    state = .failed(error.localizedDescription)
                    try? await Task.sleep(for: .seconds(5 * (attempt + 1)))
                }
            }
        }
    }

    private func apply(_ result: LyricsResult, source: LyricsSource, for track: Track) {
        let from = source == .cache ? "💾 from cache" : "📥 from LRCLIB"
        switch result {
        case .found(let document):
            state = .loaded(document)
            engine = SyncEngine(document: document, offset: offset)
            let kind = switch document.timing {
            case .wordSynced: "word-synced"
            case .lineSynced: "line-synced, word timing estimated"
            case .unsynced: "NOT synced — plain text only"
            }
            Logger.lyrics.notice("\(from, privacy: .public): \(document.lines.count, privacy: .public) lines (\(kind, privacy: .public)) for “\(track.title, privacy: .public)”")
        case .instrumental:
            state = .instrumental
            Logger.lyrics.notice("\(from, privacy: .public): “\(track.title, privacy: .public)” is instrumental")
        case .notFound:
            state = .notFound
            Logger.lyrics.notice("\(from, privacy: .public): no lyrics found for “\(track.title, privacy: .public)” — \(track.artist, privacy: .public)")
        }
    }

    // MARK: - Debug log of lines as they're sung

    func startLineLog(spotify: SpotifyMonitor) {
        #if DEBUG
        guard logTask == nil else { return }
        logTask = Task { [weak self] in
            var lastTrackID: String?
            var lastLine: Int?
            while !Task.isCancelled {
                guard let self else { return }
                if self.track?.id != lastTrackID {
                    lastTrackID = self.track?.id
                    lastLine = nil
                }
                if let document = self.document, document.isSynced, spotify.isPlaying {
                    let p = self.position(at: spotify.position())
                    if p.lineIndex != lastLine {
                        if let i = p.lineIndex {
                            let line = document.lines[i]
                            Logger.lyrics.notice("🎤 \(TimeFormat.string(line.start, millis: true), privacy: .public)  \(line.text, privacy: .public)")
                        } else if lastLine != nil, p.nextLineIndex != nil {
                            Logger.lyrics.notice("🎶 (instrumental)")
                        }
                        lastLine = p.lineIndex
                    }
                }
                try? await Task.sleep(for: .milliseconds(spotify.isPlaying ? 30 : 300))
            }
        }
        #endif
    }
}
