import Foundation
import Testing
@testable import LyricscapeCore

struct SyncEngineTests {
    let document = LRCParser.parse("""
    [00:10.00]<00:10.00>Neon <00:10.40>lights <00:11.20>hum <00:12.00>
    [00:13.00]Second line here
    [00:16.00]
    [00:30.00]After the gap
    """)

    @Test func beforeFirstLine() {
        let p = SyncEngine(document: document).position(at: 5)
        #expect(p.lineIndex == nil)
        #expect(p.lastLineIndex == nil)
        #expect(p.nextLineIndex == 0)
    }

    @Test func findsLineWordAndProgress() {
        let p = SyncEngine(document: document).position(at: 10.8)
        #expect(p.lineIndex == 0)
        #expect(p.wordIndex == 1) // "lights" 10.4–11.2
        #expect(abs(p.wordProgress - 0.5) < 1e-9)
        #expect(abs(p.lineProgress - 0.8 / 3) < 1e-9)
        #expect(p.nextLineIndex == 1)
    }

    @Test func holdsLastWordAfterItIsSung() {
        let p = SyncEngine(document: document).position(at: 12.5)
        #expect(p.lineIndex == 0)
        #expect(p.wordIndex == 2)
        #expect(p.wordProgress == 1)
    }

    @Test func reportsInstrumentalGap() {
        let p = SyncEngine(document: document).position(at: 20)
        #expect(p.lineIndex == nil)
        #expect(p.lastLineIndex == 1)
        #expect(p.nextLineIndex == 2)
    }

    @Test func exactLineBoundaryBelongsToNextLine() {
        let p = SyncEngine(document: document).position(at: 13)
        #expect(p.lineIndex == 1)
        #expect(p.wordIndex == 0)
        #expect(p.wordProgress == 0)
    }

    @Test func lastLineThenEnd() {
        let engine = SyncEngine(document: document)
        #expect(engine.position(at: 31).lineIndex == 2)
        #expect(engine.position(at: 31).nextLineIndex == nil)
        #expect(engine.position(at: 500).lineIndex == nil)
    }

    @Test func offsetShiftsLyricsEarlier() {
        let engine = SyncEngine(document: document, offset: 0.5)
        #expect(engine.position(at: 9.6).lineIndex == 0)
        #expect(SyncEngine(document: document).position(at: 9.6).lineIndex == nil)
    }

    @Test func unsyncedLyricsNeverHaveACurrentLine() {
        let engine = SyncEngine(document: LRCParser.plain("one\ntwo"))
        #expect(engine.position(at: 0).lineIndex == nil)
    }

    @Test func everyWordIsVisitedInOrderDuringPlayback() {
        // Simulate 60 fps playback over a line with estimated timings.
        let doc = LRCParser.parse("[00:01.00]one two three four five\n[00:06.00]next")
        let engine = SyncEngine(document: doc)
        var seen: [Int] = []
        var t = 0.0
        while t < 6 {
            if let w = engine.position(at: t).wordIndex, seen.last != w { seen.append(w) }
            t += 1.0 / 60
        }
        #expect(seen == [0, 1, 2, 3, 4])
    }
}
