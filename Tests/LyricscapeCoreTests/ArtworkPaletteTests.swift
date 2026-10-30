import Foundation
import Testing
@testable import LyricscapeCore

struct ArtworkPaletteTests {
    @Test func findsTheDominantColour() {
        // Mostly blue, some red, lots of grey background.
        let pixels = Array(repeating: (r: 0.1, g: 0.2, b: 0.9), count: 300)
            + Array(repeating: (r: 0.9, g: 0.1, b: 0.1), count: 100)
            + Array(repeating: (r: 0.5, g: 0.5, b: 0.5), count: 600)
        let hues = ArtworkPalette.dominantHues(pixels: pixels)
        #expect(hues.count == 2)
        #expect(abs(hues[0] - 0.63) < 0.04) // blue first
        #expect(min(hues[1], 1 - hues[1]) < 0.04) // then red
    }

    @Test func ignoresBlackAndWhiteArt() {
        var pixels: [(r: Double, g: Double, b: Double)] = []
        for i in 0..<500 {
            let grey = Double(i % 10) / 10
            pixels.append((r: grey, g: grey, b: grey))
        }
        #expect(ArtworkPalette.dominantHues(pixels: pixels).isEmpty)
    }

    @Test func convertsRGBToHSV() {
        let green = ArtworkPalette.hsv(0, 1, 0)
        #expect(abs(green.h - 1.0 / 3) < 1e-9 && green.s == 1 && green.v == 1)
    }
}
