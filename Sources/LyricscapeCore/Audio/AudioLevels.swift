import Foundation

/// What the music sounds like right now, for audio-reactive visuals. All 0…1.
public struct AudioLevels: Sendable, Equatable {
    /// Overall loudness.
    public var level: Double
    /// Low-frequency (kick / bass) energy.
    public var bass: Double
    /// 1 on a detected beat, decaying quickly to 0.
    public var beat: Double
    /// False when there's no audio analysis (feature off or no permission).
    public var isActive: Bool

    public init(level: Double, bass: Double, beat: Double, isActive: Bool) {
        self.level = level
        self.bass = bass
        self.beat = beat
        self.isActive = isActive
    }

    public static let silent = AudioLevels(level: 0, bass: 0, beat: 0, isActive: false)
}
