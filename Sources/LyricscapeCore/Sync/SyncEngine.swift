import Foundation

/// Where we are in the lyrics at a given moment. This is what styles draw from.
public struct LyricPosition: Sendable, Equatable {
    /// Lyrics time (playback position plus the user's offset).
    public var time: TimeInterval
    /// The line being sung, or nil before the first line and during instrumental gaps.
    public var lineIndex: Int?
    /// The most recent line that has started (still set during a gap).
    public var lastLineIndex: Int?
    /// The next line that hasn't started yet.
    public var nextLineIndex: Int?
    /// The word being sung in the current line (or the last one, once all are sung).
    public var wordIndex: Int?
    /// 0…1 through the current word.
    public var wordProgress: Double
    /// 0…1 through the current line's display time.
    public var lineProgress: Double

    public static func idle(at time: TimeInterval) -> LyricPosition {
        LyricPosition(time: time, lineIndex: nil, lastLineIndex: nil, nextLineIndex: nil,
                      wordIndex: nil, wordProgress: 0, lineProgress: 0)
    }
}

/// Maps a playback position to the current line and word. Stateless and cheap
/// (binary search), so it can be called every frame.
public struct SyncEngine: Sendable {
    public let document: LyricsDocument
    /// Seconds added to the playback position. Positive = lyrics appear earlier.
    public var offset: TimeInterval

    public init(document: LyricsDocument, offset: TimeInterval = 0) {
        self.document = document
        self.offset = offset
    }

    public func position(at playbackTime: TimeInterval) -> LyricPosition {
        let t = playbackTime + offset
        let lines = document.lines
        guard document.isSynced, !lines.isEmpty else { return .idle(at: t) }

        guard let last = Self.lastIndex(in: lines.count, startingBefore: t, start: { lines[$0].start }) else {
            var position = LyricPosition.idle(at: t)
            position.nextLineIndex = 0
            return position
        }

        let line = lines[last]
        let next = last + 1 < lines.count ? last + 1 : nil
        guard t < line.end else {
            var position = LyricPosition.idle(at: t)
            position.lastLineIndex = last
            position.nextLineIndex = next
            return position
        }

        let lineProgress = line.end > line.start ? (t - line.start) / (line.end - line.start) : 1
        var wordIndex: Int?
        var wordProgress = 0.0
        if let w = Self.lastIndex(in: line.words.count, startingBefore: t, start: { line.words[$0].start }) {
            let word = line.words[w]
            wordIndex = w
            wordProgress = word.duration > 0 ? min(1, max(0, (t - word.start) / word.duration)) : 1
        }

        return LyricPosition(time: t, lineIndex: last, lastLineIndex: last, nextLineIndex: next,
                             wordIndex: wordIndex, wordProgress: wordProgress,
                             lineProgress: min(1, max(0, lineProgress)))
    }

    /// Index of the last item whose start is ≤ t (items sorted by start).
    private static func lastIndex(in count: Int, startingBefore t: TimeInterval, start: (Int) -> TimeInterval) -> Int? {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if start(mid) <= t { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}
