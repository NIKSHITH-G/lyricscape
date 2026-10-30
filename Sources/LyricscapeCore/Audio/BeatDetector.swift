import Accelerate
import Foundation

/// Turns a stream of mono audio samples into `AudioLevels`: loudness, bass energy and
/// beats. Beats are onsets found with spectral flux (how much the spectrum grew since
/// the previous frame) against an adaptive threshold from the last second of audio.
/// Levels are auto-gained so quiet and loud songs both use the full 0…1 range.
///
/// Not thread-safe: feed it from one queue.
public final class BeatDetector {
    public let sampleRate: Double
    public private(set) var levels = AudioLevels.silent

    private let size = 1024
    private let hop = 512
    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let window: [Float]
    private var pending: [Float] = []
    private var previousMagnitudes: [Float]
    private var fluxHistory: [Float] = []
    private var time: Double = 0
    private var lastBeat: Double = -10
    private var peakBass: Float = 1e-6
    private var peakLevel: Float = 1e-6

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        dft = try? vDSP.DiscreteFourierTransform(count: size, direction: .forward,
                                                 transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        previousMagnitudes = [Float](repeating: 0, count: size / 2)
    }

    /// Feed any number of samples; analysis runs every `hop` samples.
    public func process(_ samples: [Float]) {
        pending.append(contentsOf: samples)
        while pending.count >= size {
            analyze(Array(pending[0..<size]))
            pending.removeFirst(hop)
            time += Double(hop) / sampleRate
        }
        // The beat value decays continuously, not just when a beat lands.
        levels.beat = exp(-(time - lastBeat) * 8)
    }

    private func analyze(_ frame: [Float]) {
        guard let dft else { return }
        let windowed = vDSP.multiply(frame, window)
        let (real, imaginary) = dft.transform(real: windowed, imaginary: [Float](repeating: 0, count: size))
        var magnitudes = [Float](repeating: 0, count: size / 2)
        for i in 0..<size / 2 {
            magnitudes[i] = sqrt(real[i] * real[i] + imaginary[i] * imaginary[i]) / Float(size)
        }

        let binWidth = sampleRate / Double(size)
        func bin(_ hz: Double) -> Int { min(size / 2 - 1, max(1, Int(hz / binWidth))) }
        let bassRange = bin(30)...bin(160)
        let bass = magnitudes[bassRange].reduce(0, +) / Float(bassRange.count)
        let rms = sqrt(vDSP.meanSquare(frame))

        // Spectral flux up to ~5 kHz, with the low end weighted up (kicks drive beats).
        var flux: Float = 0
        for i in 1..<bin(5000) {
            let rise = magnitudes[i] - previousMagnitudes[i]
            if rise > 0 { flux += rise * (i <= bassRange.upperBound ? 4 : 1) }
        }
        previousMagnitudes = magnitudes

        let historyLength = Int(sampleRate / Double(hop)) // ≈ 1 s
        fluxHistory.append(flux)
        if fluxHistory.count > historyLength { fluxHistory.removeFirst() }
        let mean = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        let variance = fluxHistory.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(fluxHistory.count)
        // A beat must stand out statistically *and* be well above the recent average;
        // steady noise jitters past the first test but never the second.
        let threshold = max(mean + 1.5 * sqrt(variance), mean * 2)
        if fluxHistory.count > 8, flux > threshold, flux > 1e-4, time - lastBeat > 0.25 {
            lastBeat = time
        }

        // Auto-gain: normalise against a slowly decaying peak.
        peakBass = max(bass, peakBass * 0.9995)
        peakLevel = max(rms, peakLevel * 0.9995)
        levels.bass = Double(min(1, bass / peakBass))
        levels.level = Double(min(1, rms / peakLevel))
        levels.isActive = true
    }

    /// Seconds of audio processed so far.
    public var elapsed: Double { time }
    /// Time of the most recent beat, in `elapsed` seconds.
    public var lastBeatTime: Double { lastBeat }
}
