import CoreGraphics
import Foundation
import Testing
@testable import LyricscapeCore

struct KeywordPickerTests {
    @Test func picksLongMeaningfulWord() {
        let words = ["I", "will", "remember", "you"]
        #expect(KeywordPicker.keywords(in: words) == [2])
    }

    @Test func ignoresFillerAndShortWords() {
        #expect(KeywordPicker.keywords(in: ["oh", "yeah", "la", "na"]).isEmpty)
    }

    @Test func longLinesGetTwoKeywords() {
        let words = ["Dancing", "alone", "under", "electric", "midnight", "skies", "tonight"]
        #expect(KeywordPicker.keywords(in: words).count == 2)
    }

    @Test func handlesKorean() {
        #expect(KeywordPicker.keywords(in: ["나의", "두", "눈을", "감으면"]) == [3])
    }
}

struct ConstellationLayoutTests {
    // Roughly a 1800×1169 pt screen with 50 pt words, like the real app.
    let bounds = CGRect(x: 108, y: 94, width: 1584, height: 935)
    let short = (0..<5).map { CGSize(width: 90 + $0 * 30, height: 56) }
    let long = (0..<14).map { CGSize(width: 70 + ($0 % 5) * 35, height: 44) }

    @Test func isDeterministic() {
        let a = ConstellationLayout.place(sizes: short, keywords: [3], bounds: bounds, seed: 42)
        let b = ConstellationLayout.place(sizes: short, keywords: [3], bounds: bounds, seed: 42)
        let c = ConstellationLayout.place(sizes: short, keywords: [3], bounds: bounds, seed: 43)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func staysInsideBoundsWithoutOverlaps() {
        for sizes in [short, long] {
            for seed in 0..<100 as Range<UInt64> {
                let rects = ConstellationLayout.place(sizes: sizes, keywords: [2], bounds: bounds, seed: seed,
                                                      verticalBias: seed.isMultiple(of: 2) ? -1 : 1)
                #expect(rects.count == sizes.count)
                for (i, r) in rects.enumerated() {
                    #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(r))
                    for other in rects[(i + 1)...] { #expect(!r.intersects(other)) }
                }
            }
        }
    }

    @Test func readsLeftToRightWithinARow() {
        for seed in 0..<50 as Range<UInt64> {
            let rects = ConstellationLayout.place(sizes: short, keywords: [], bounds: bounds, seed: seed)
            for (a, b) in zip(rects, rects.dropFirst()) { #expect(a.midX < b.midX) }
        }
    }

    @Test func longLinesWrapIntoRowsTopToBottom() {
        let rects = ConstellationLayout.place(sizes: long, keywords: [], bounds: bounds, seed: 1)
        let rows = Set(rects.map { ($0.midY / 150).rounded() })
        #expect(rows.count >= 2)
        #expect(rects.first!.midY < rects.last!.midY)
    }

    @Test func keywordsSitOnTheCentreLine() {
        var keyOffset = 0.0, otherOffset = 0.0
        for seed in 0..<50 as Range<UInt64> {
            let rects = ConstellationLayout.place(sizes: short, keywords: [2], bounds: bounds, seed: seed)
            let centreY = rects.map(\.midY).reduce(0, +) / CGFloat(rects.count)
            for (i, r) in rects.enumerated() {
                let d = Double(abs(r.midY - centreY))
                if i == 2 { keyOffset += d } else { otherOffset += d / 4 }
            }
        }
        #expect(keyOffset < otherOffset)
    }

    @Test func reportsRowsInReadingOrder() {
        let placement = ConstellationLayout.placement(sizes: long, keywords: [], bounds: bounds, seed: 1)
        #expect(placement.rows.first == 0)
        #expect(placement.rows == placement.rows.sorted())
        #expect(Set(placement.rows).count >= 2)
    }

    @Test func isComposedAroundTheMiddle() {
        let rects = ConstellationLayout.place(sizes: short, keywords: [], bounds: bounds, seed: 9)
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        #expect(abs(union.midX - bounds.midX) < bounds.width * 0.1)
        #expect(abs(union.midY - bounds.midY) < bounds.height * 0.2)
    }

    @Test func seedsFromStringsAreStable() {
        var a = SeededRandom("spotify:track:abc#3"), b = SeededRandom("spotify:track:abc#3")
        #expect(a.next() == b.next())
    }
}
