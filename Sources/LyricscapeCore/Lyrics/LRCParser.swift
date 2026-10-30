import Foundation

/// Parses LRC lyrics, including the "enhanced" variant with per-word `<mm:ss.xx>` tags.
///
///     [ar:Artist]
///     [offset:+250]
///     [00:12.00]First line
///     [00:15.30][01:02.10]Repeated chorus line
///     [00:18.00]<00:18.00>Word <00:18.40>by <00:18.70>word <00:19.50>
///     [00:21.00]                      ← empty line: instrumental gap
public enum LRCParser {
    public static func parse(_ text: String, trackDuration: TimeInterval? = nil) -> LyricsDocument {
        var entries: [Entry] = []
        var untimedLines: [String] = []
        var offset: TimeInterval = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            var rest = Substring(line)
            var stamps: [TimeInterval] = []
            var isMetadata = false
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTimestamp(tag) {
                    stamps.append(time)
                } else if stamps.isEmpty, let colon = tag.firstIndex(of: ":"),
                          tag[..<colon].allSatisfy(\.isLetter) {
                    // [ar:…], [ti:…], [offset:…], etc.
                    isMetadata = true
                    if tag[..<colon].lowercased() == "offset",
                       let ms = Double(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)) {
                        offset = ms / 1000
                    }
                    break
                } else {
                    break // e.g. "[Chorus]" in plain lyrics
                }
                rest = rest[rest.index(after: close)...]
            }

            if isMetadata { continue }
            if stamps.isEmpty {
                untimedLines.append(line)
                continue
            }
            let segments = parseWordTags(rest)
            for stamp in stamps {
                // Repeated lines reuse the word tags of their first occurrence, shifted.
                let shift = stamp - stamps[0]
                entries.append(Entry(
                    start: stamp,
                    segments: segments.map { Segment(start: $0.start.map { $0 + shift }, text: $0.text) }
                ))
            }
        }

        if entries.isEmpty {
            return plain(untimedLines.joined(separator: "\n"))
        }

        // A positive [offset] means the lyrics should appear earlier.
        if offset != 0 {
            entries = entries.map { entry in
                Entry(start: entry.start - offset,
                      segments: entry.segments.map { Segment(start: $0.start.map { $0 - offset }, text: $0.text) })
            }
        }
        entries.sort { $0.start < $1.start } // stable in Swift 5+, keeps file order for equal times

        var lines: [LyricLine] = []
        var anyWordTiming = false
        for (i, entry) in entries.enumerated() {
            let text = entry.displayText
            if text.isEmpty { continue } // gap marker: only ends the previous line
            let end: TimeInterval
            if i + 1 < entries.count {
                end = entries[i + 1].start
            } else {
                let estimated = entry.start + max(4, sungDuration(wordCount: WordSplitter.words(in: text).count, available: .infinity))
                end = trackDuration.map { $0 > entry.start ? min($0, estimated) : estimated } ?? estimated
            }
            let start = max(0, entry.start)
            let (words, timed) = makeWords(for: entry, lineStart: start, lineEnd: max(end, start))
            anyWordTiming = anyWordTiming || timed
            lines.append(LyricLine(text: text, start: start, end: max(end, start), words: words, hasWordTiming: timed))
        }

        return LyricsDocument(lines: lines, timing: anyWordTiming ? .wordSynced : .lineSynced)
    }

    /// Unsynced plain-text lyrics.
    public static func plain(_ text: String) -> LyricsDocument {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                LyricLine(text: line, start: 0, end: 0,
                          words: WordSplitter.words(in: line).map { LyricWord(text: $0, start: 0, end: 0) },
                          hasWordTiming: false)
            }
        return LyricsDocument(lines: lines, timing: .unsynced)
    }

    // MARK: - Timestamps

    /// Accepts "mm:ss", "mm:ss.xx", "mm:ss.xxx" and "mm:ss:xx".
    static func parseTimestamp(_ s: Substring) -> TimeInterval? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } }),
              let minutes = Int(parts[0]) else { return nil }
        let seconds: Double?
        if parts.count == 2 {
            seconds = Double(parts[1])
        } else {
            seconds = Int(parts[1]).flatMap { whole in Double("0." + parts[2]).map { Double(whole) + $0 } }
        }
        guard let seconds else { return nil }
        return Double(minutes) * 60 + seconds
    }

    // MARK: - Words

    private struct Segment {
        var start: TimeInterval?
        var text: String
    }

    private struct Entry {
        var start: TimeInterval
        var segments: [Segment]

        var displayText: String {
            segments.map(\.text).joined()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
    }

    /// Splits "<00:01.00>Hello <00:01.50>world" into timed segments. Text without
    /// any word tags becomes a single untimed segment.
    private static func parseWordTags(_ content: Substring) -> [Segment] {
        var segments: [Segment] = []
        var current = Segment(start: nil, text: "")
        var i = content.startIndex
        while i < content.endIndex {
            if content[i] == "<", let close = content[i...].firstIndex(of: ">"),
               let time = parseTimestamp(content[content.index(after: i)..<close]) {
                segments.append(current)
                current = Segment(start: time, text: "")
                i = content.index(after: close)
                continue
            }
            current.text.append(content[i])
            i = content.index(after: i)
        }
        segments.append(current)
        return segments.filter { $0.start != nil || !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func makeWords(for entry: Entry, lineStart: TimeInterval, lineEnd: TimeInterval) -> ([LyricWord], Bool) {
        let segments = entry.segments
        guard segments.contains(where: { $0.start != nil }) else {
            let words = WordSplitter.words(in: entry.displayText)
            let duration = sungDuration(wordCount: words.count, available: lineEnd - lineStart)
            return (distribute(words, from: lineStart, over: duration), false)
        }

        var words: [LyricWord] = []
        for (k, segment) in segments.enumerated() {
            let pieces = segment.text.split(whereSeparator: \.isWhitespace).map(String.init)
            if pieces.isEmpty { continue }
            let start = max(lineStart, segment.start ?? lineStart)
            let end = k + 1 < segments.count
                ? (segments[k + 1].start ?? lineEnd)
                : min(lineEnd, start + sungDuration(wordCount: pieces.count, available: .infinity))
            words += distribute(pieces, from: start, over: max(0, min(end, lineEnd) - start))
        }
        return (words, true)
    }

    /// How long the words of a line are actually sung, out of the time available
    /// before the next line: roughly 0.75 s per word, but never the whole gap so a
    /// long pause after a line doesn't stretch its last word.
    static func sungDuration(wordCount: Int, available: TimeInterval) -> TimeInterval {
        min(available * 0.92, Double(wordCount) * 0.75 + 1.0)
    }

    /// Spreads words over a time span, longer words getting proportionally more time.
    static func distribute(_ words: [String], from start: TimeInterval, over duration: TimeInterval) -> [LyricWord] {
        let weights = words.map { Double($0.filter { $0.isLetter || $0.isNumber }.count) + 2 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }
        var t = start
        return zip(words, weights).map { word, weight in
            let length = duration * weight / total
            defer { t += length }
            return LyricWord(text: word, start: t, end: t + length)
        }
    }
}
