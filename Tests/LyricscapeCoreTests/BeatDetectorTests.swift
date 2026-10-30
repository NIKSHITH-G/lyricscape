import Foundation
import Testing
@testable import LyricscapeCore

struct BeatDetectorTests {
    let rate = 44_100.0

    /// `seconds` of audio with a 60 Hz kick drum every `interval` seconds over light noise.
    func kicks(every interval: Double, seconds: Double) -> [Float] {
        var rng = SeededRandom(seed: 3)
        return (0..<Int(seconds * rate)).map { n in
            let t = Double(n) / rate
            let sinceKick = t.truncatingRemainder(dividingBy: interval)
            let kick = sin(2 * .pi * 60 * sinceKick) * exp(-sinceKick * 18)
            let noise = Double.random(in: -0.02...0.02, using: &rng)
            return Float(0.8 * kick + noise)
        }
    }

    /// Runs the detector in 10 ms chunks (like a live stream) and returns beat times.
    func beatTimes(_ samples: [Float]) -> [Double] {
        let detector = BeatDetector(sampleRate: rate)
        var times: [Double] = []
        var lastSeen = -1.0
        var i = 0
        while i < samples.count {
            detector.process(Array(samples[i..<min(i + 441, samples.count)]))
            if detector.lastBeatTime > lastSeen, detector.lastBeatTime >= 0 {
                lastSeen = detector.lastBeatTime
                times.append(lastSeen)
            }
            i += 441
        }
        return times
    }

    @Test func findsKicksAt120BPM() {
        let times = beatTimes(kicks(every: 0.5, seconds: 6))
        // The first kick or two train the adaptive threshold.
        #expect(times.count >= 9 && times.count <= 12)
        let intervals = zip(times, times.dropFirst()).map { $1 - $0 }
        let steady = intervals.filter { abs($0 - 0.5) < 0.05 }
        #expect(Double(steady.count) >= Double(intervals.count) * 0.8)
    }

    @Test func noBeatsInSteadyNoise() {
        var rng = SeededRandom(seed: 5)
        let noise = (0..<Int(4 * rate)).map { _ in Float.random(in: -0.02...0.02, using: &rng) }
        #expect(beatTimes(noise).count <= 2)
    }

    @Test func bassAndBeatTrackTheKick() {
        let detector = BeatDetector(sampleRate: rate)
        let samples = kicks(every: 0.5, seconds: 3)
        detector.process(Array(samples[0..<Int(2.53 * rate)])) // just after a kick
        let onKick = detector.levels
        detector.process(Array(samples[Int(2.53 * rate)..<Int(2.9 * rate)])) // between kicks
        let between = detector.levels
        #expect(onKick.isActive)
        #expect(onKick.bass > between.bass)
        #expect(onKick.beat > 0.5)
        #expect(between.beat < 0.2)
    }
}
