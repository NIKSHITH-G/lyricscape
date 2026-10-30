import Foundation

public struct LyricWord: Sendable, Equatable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

public struct LyricLine: Sendable, Equatable {
    public var text: String
    /// When the line starts being sung.
    public var start: TimeInterval
    /// When the line should stop being shown: the next line's start, or the start of
    /// an instrumental gap. Words may finish earlier than this.
    public var end: TimeInterval
    public var words: [LyricWord]
    /// True when word times come from the lyrics file (enhanced LRC) rather than being estimated.
    public var hasWordTiming: Bool

    public init(text: String, start: TimeInterval, end: TimeInterval, words: [LyricWord], hasWordTiming: Bool) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
        self.hasWordTiming = hasWordTiming
    }
}

public struct LyricsDocument: Sendable, Equatable {
    public enum Timing: String, Sendable {
        /// Every word has its own timestamp (enhanced LRC).
        case wordSynced
        /// Lines have timestamps; word timings are estimated.
        case lineSynced
        /// Plain text only. Line times are all zero.
        case unsynced
    }

    public var lines: [LyricLine]
    public var timing: Timing

    public init(lines: [LyricLine], timing: Timing) {
        self.lines = lines
        self.timing = timing
    }

    public var isSynced: Bool { timing != .unsynced }
}
