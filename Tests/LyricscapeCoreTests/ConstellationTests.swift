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
    let bounds = CGRect(x: 100, y: 80, width: 1600, height: 900)
    let sizes = (0..<7).map { CGSize(width: 80 + $0 * 25, height: 50) }

    @Test func isDeterministic() {
        let a = ConstellationLayout.place(sizes: sizes, keywords: [3], bounds: bounds, seed: 42)
        let b = ConstellationLayout.place(sizes: sizes, keywords: [3], bounds: bounds, seed: 42)
        let c = ConstellationLayout.place(sizes: sizes, keywords: [3], bounds: bounds, seed: 43)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func staysInsideBoundsWithoutOverlaps() {
        for seed in 0..<50 as Range<UInt64> {
            let rects = ConstellationLayout.place(sizes: sizes, keywords: [2, 5], bounds: bounds, seed: seed)
            #expect(rects.count == sizes.count)
            for (i, r) in rects.enumerated() {
                #expect(bounds.contains(r))
                for other in rects[(i + 1)...] { #expect(!r.intersects(other)) }
            }
        }
    }

    @Test func keywordsSitNearerTheCentreThanOtherWords() {
        var keyDistance = 0.0, otherDistance = 0.0
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for seed in 0..<50 as Range<UInt64> {
            let rects = ConstellationLayout.place(sizes: sizes, keywords: [3], bounds: bounds, seed: seed)
            for (i, r) in rects.enumerated() {
                let d = Double(hypot(r.midX - center.x, r.midY - center.y))
                if i == 3 { keyDistance += d } else { otherDistance += d / 6 }
            }
        }
        #expect(keyDistance < otherDistance * 0.6)
    }

    @Test func avoidsObstaclesWhenThereIsRoom() {
        let obstacle = CGRect(x: 100, y: 80, width: 800, height: 900) // whole left half
        let rects = ConstellationLayout.place(sizes: Array(sizes.prefix(3)), keywords: [], bounds: bounds,
                                              obstacles: [obstacle], seed: 7)
        #expect(rects.allSatisfy { !$0.intersects(obstacle) })
    }

    @Test func seedsFromStringsAreStable() {
        var a = SeededRandom("spotify:track:abc#3"), b = SeededRandom("spotify:track:abc#3")
        #expect(a.next() == b.next())
    }
}
