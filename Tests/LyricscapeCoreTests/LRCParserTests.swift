import Foundation
import Testing
@testable import LyricscapeCore

struct LRCParserTests {
    @Test func parsesTimestampFormats() {
        #expect(LRCParser.parseTimestamp("01:02.50") == 62.5)
        #expect(LRCParser.parseTimestamp("01:02.500") == 62.5)
        #expect(LRCParser.parseTimestamp("01:02") == 62)
        #expect(LRCParser.parseTimestamp("01:02:50") == 62.5)
        #expect(LRCParser.parseTimestamp("ar:Someone") == nil)
        #expect(LRCParser.parseTimestamp("1e3:00") == nil)
        #expect(LRCParser.parseTimestamp("") == nil)
    }

    @Test func parsesBasicLRCAndSkipsMetadata() {
        let doc = LRCParser.parse("""
        [ar:Test Artist]
        [ti:Test Song]
        [00:10.00]Paper boats on a silver river
        [00:14.50]Drifting slowly home
        """)
        #expect(doc.timing == .lineSynced)
        #expect(doc.lines.map(\.text) == ["Paper boats on a silver river", "Drifting slowly home"])
        #expect(doc.lines[0].start == 10)
        #expect(doc.lines[0].end == 14.5)
        #expect(doc.lines[0].hasWordTiming == false)
    }

    @Test func emptyLineEndsPreviousLineAsGap() {
        let doc = LRCParser.parse("""
        [00:05.00]Hello there
        [00:08.00]
        [00:20.00]After the solo
        """)
        #expect(doc.lines.count == 2)
        #expect(doc.lines[0].end == 8)
        #expect(doc.lines[1].start == 20)
    }

    @Test func expandsRepeatedTimestampsAndSorts() {
        let doc = LRCParser.parse("""
        [00:30.00][00:10.00]Chorus line
        [00:20.00]Verse line
        """)
        #expect(doc.lines.map(\.text) == ["Chorus line", "Verse line", "Chorus line"])
        #expect(doc.lines.map(\.start) == [10, 20, 30])
    }

    @Test func appliesOffsetTag() {
        let doc = LRCParser.parse("""
        [offset:+500]
        [00:10.00]Earlier please
        """)
        #expect(doc.lines[0].start == 9.5)
    }

    @Test func lastLineEndIsClampedToTrackDuration() {
        let doc = LRCParser.parse("[03:58.00]Final words here", trackDuration: 240)
        #expect(doc.lines[0].end == 240)
    }

    @Test func estimatesWordTimingsWithinLine() {
        let doc = LRCParser.parse("""
        [00:10.00]I wandered extraordinarily far
        [00:20.00]Next
        """)
        let words = doc.lines[0].words
        #expect(words.map(\.text) == ["I", "wandered", "extraordinarily", "far"])
        #expect(words.first?.start == 10)
        // Words are contiguous, in order, and longer words get more time.
        for (a, b) in zip(words, words.dropFirst()) { #expect(abs(a.end - b.start) < 1e-9) }
        #expect(words[2].duration > words[1].duration)
        #expect(words[1].duration > words[0].duration)
        // 4 words ≈ 4 s of singing, not stretched over the whole 10 s gap.
        let sung = words.last!.end - words.first!.start
        #expect(abs(sung - 4.0) < 1e-9)
    }

    @Test func shortLinesDoNotOverrunNextLine() {
        let doc = LRCParser.parse("""
        [00:10.00]So many words squeezed into one quick line
        [00:11.00]Next
        """)
        #expect(doc.lines[0].words.last!.end <= 11)
    }

    @Test func parsesEnhancedWordTimings() {
        let doc = LRCParser.parse("""
        [00:10.00]<00:10.00>Neon <00:10.40>lights <00:11.20>hum <00:12.00>
        [00:15.00]Next
        """)
        #expect(doc.timing == .wordSynced)
        let line = doc.lines[0]
        #expect(line.text == "Neon lights hum")
        #expect(line.hasWordTiming)
        #expect(line.words.map(\.text) == ["Neon", "lights", "hum"])
        #expect(line.words.map(\.start) == [10, 10.4, 11.2])
        #expect(line.words.map(\.end) == [10.4, 11.2, 12])
    }

    @Test func fallsBackToPlainLyrics() {
        let doc = LRCParser.parse("""
        [Verse 1]
        Just some words

        With no timestamps
        """)
        #expect(doc.timing == .unsynced)
        #expect(doc.lines.map(\.text) == ["[Verse 1]", "Just some words", "With no timestamps"])
    }

    @Test func handlesWindowsLineEndingsAndBlankInput() {
        #expect(LRCParser.parse("[00:01.00]One\r\n[00:02.00]Two").lines.map(\.text) == ["One", "Two"])
        #expect(LRCParser.parse("").lines.isEmpty)
    }
}

struct SearchTermsTests {
    @Test func cleansTitles() {
        #expect(SearchTerms.cleanTitle("Song - Remastered 2011") == "Song")
        #expect(SearchTerms.cleanTitle("Song (feat. Someone)") == "Song")
        #expect(SearchTerms.cleanTitle("(Intro)") == "(Intro)")
    }

    @Test func picksPrimaryArtist() {
        #expect(SearchTerms.primaryArtist("A, B") == "A")
        #expect(SearchTerms.primaryArtist("A & B") == "A")
        #expect(SearchTerms.primaryArtist("A feat. B") == "A")
        #expect(SearchTerms.primaryArtist("Solo") == "Solo")
    }
}
