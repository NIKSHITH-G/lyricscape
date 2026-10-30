import Foundation
import LyricscapeCore

/// Where the stage gets its song, lyrics and timing from: Spotify, or the built-in
/// demo song (Settings preview and `--demo`).
@MainActor
protocol LyricSource: AnyObject {
    var isPlaying: Bool { get }
    /// nil when nothing is playing.
    var track: Track? { get }
    /// Increases each time a song (re)starts.
    var playID: Int { get }
    /// nil while there are no lyrics to show.
    var document: LyricsDocument? { get }
    var audio: AudioLevels { get }
    func playbackPosition() -> TimeInterval
    func lyricPosition(at playback: TimeInterval) -> LyricPosition
}

/// The song playing in Spotify.
@MainActor
final class LiveLyricSource: LyricSource {
    private let spotify: SpotifyMonitor
    private let lyrics: LyricsController
    private let audioReactor: AudioReactor?

    init(spotify: SpotifyMonitor, lyrics: LyricsController, audioReactor: AudioReactor?) {
        self.spotify = spotify
        self.lyrics = lyrics
        self.audioReactor = audioReactor
    }

    var isPlaying: Bool { spotify.isPlaying }
    var track: Track? { spotify.connection == .connected ? spotify.track : nil }
    var playID: Int { spotify.playID }
    var document: LyricsDocument? { lyrics.document }
    var audio: AudioLevels { spotify.isPlaying ? audioReactor?.levels ?? .silent : .silent }
    func playbackPosition() -> TimeInterval { spotify.position() }
    func lyricPosition(at playback: TimeInterval) -> LyricPosition { lyrics.position(at: playback) }
}

/// A short built-in song that loops forever, so styles can be tried without Spotify.
@MainActor
final class DemoLyricSource: LyricSource {
    private let demoTrack = Track(id: "lyricscape:demo", title: "Neon Satellites", artist: "Lyricscape Demo",
                                  album: "Demo", duration: DemoSong.duration)
    private let demoDocument = LRCParser.parse(DemoSong.lrc, trackDuration: DemoSong.duration)
    private let engine: SyncEngine

    var track: Track? { demoTrack }
    var document: LyricsDocument? { demoDocument }
    private let start = ProcessInfo.processInfo.systemUptime

    init() {
        engine = SyncEngine(document: demoDocument)
    }

    var isPlaying: Bool { true }
    var playID: Int { Int(elapsed / DemoSong.duration) }
    var audio: AudioLevels {
        // A steady 112 BPM pulse so audio-reactive visuals can be previewed too.
        let period = 60.0 / 112
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        let beat = exp(-phase * 7)
        return AudioLevels(level: 0.5 + 0.3 * beat, bass: beat, beat: beat, isActive: true)
    }
    func playbackPosition() -> TimeInterval { elapsed.truncatingRemainder(dividingBy: DemoSong.duration) }
    func lyricPosition(at playback: TimeInterval) -> LyricPosition { engine.position(at: playback) }

    private var elapsed: TimeInterval { ProcessInfo.processInfo.systemUptime - start }
}

/// Original lyrics written for the demo, covering the cases styles must handle: a
/// title-card intro, an enhanced (word-timed) line, a long wrapping line, an
/// instrumental gap, and Korean and Japanese lines.
enum DemoSong {
    static let duration: TimeInterval = 46
    static let lrc = """
    [ti:Neon Satellites]
    [ar:Lyricscape Demo]
    [00:05.50]City lights are humming in the dark
    [00:09.00]<00:09.00>Every <00:09.40>signal <00:09.90>finds <00:10.30>its <00:10.55>way <00:11.20>home <00:12.20>
    [00:12.60]We are satellites in orbit, burning brighter than the summer sky tonight
    [00:17.40]Spinning slowly through the electric night
    [00:21.20]
    [00:23.50]별빛 아래서 우리는 춤을 춰
    [00:27.20]夜空に光る ふたりの声
    [00:31.00]Don't let the morning take the stars away
    [00:34.80]Hold on, hold on
    [00:37.00]Light it up again
    [00:40.50]
    """
}
