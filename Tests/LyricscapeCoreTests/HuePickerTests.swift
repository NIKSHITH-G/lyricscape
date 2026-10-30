import Foundation
import Testing
@testable import LyricscapeCore

struct HuePickerTests {
    @Test func staysAwayFromRecentHues() {
        var rng = SeededRandom(seed: 1)
        var recent: [Double] = []
        for _ in 0..<200 {
            let hue = HuePicker.next(avoiding: recent, using: &rng)
            #expect(hue >= 0 && hue < 1)
            #expect(HuePicker.distance(hue, recent) >= HuePicker.minimumDistance)
            recent = Array((recent + [hue]).suffix(HuePicker.memory))
        }
    }

    @Test func distanceWrapsAroundTheWheel() {
        #expect(abs(HuePicker.distance(0.95, [0.05]) - 0.1) < 1e-9)
        #expect(HuePicker.distance(0.5, []) == 1)
    }

    @Test func consecutivePlaysOfTheSameSongDiffer() {
        var rng = SeededRandom(seed: 99)
        let first = HuePicker.next(avoiding: [], using: &rng)
        let second = HuePicker.next(avoiding: [first], using: &rng)
        #expect(HuePicker.distance(second, [first]) >= HuePicker.minimumDistance)
    }
}
