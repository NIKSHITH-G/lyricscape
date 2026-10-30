import Foundation

/// Turns occasional position reports from Spotify (every ~0.5 s) into a smooth,
/// continuous playback position that can be read every frame.
///
/// All times are on a monotonic clock in seconds (e.g. `ProcessInfo.systemUptime`),
/// passed in explicitly so the logic is deterministic and testable.
public struct PlaybackClock: Sendable, Equatable {
    public enum SyncEvent: Sendable, Equatable {
        /// Report matched the prediction closely; the clock was nudged towards it.
        case drift(TimeInterval)
        /// Report was far from the prediction: the user seeked (or playback stalled).
        case seek(from: TimeInterval, to: TimeInterval)
        /// Play/pause state changed; the clock was re-anchored.
        case stateChange
    }

    /// Differences larger than this are treated as a seek.
    public var seekThreshold: TimeInterval = 1.0
    /// Differences larger than this (but below the seek threshold) snap immediately;
    /// smaller ones are blended in gradually to avoid visible jitter.
    public var snapThreshold: TimeInterval = 0.15
    /// Fraction of a small error corrected per report.
    public var blendFactor: Double = 0.35

    public private(set) var isPlaying = false
    private var anchorPosition: TimeInterval = 0
    private var anchorTime: TimeInterval = 0

    public init() {}

    public func position(at now: TimeInterval) -> TimeInterval {
        guard isPlaying else { return anchorPosition }
        return anchorPosition + max(0, now - anchorTime)
    }

    /// Hard reset, e.g. on a track change.
    public mutating func reset(position: TimeInterval, isPlaying: Bool, at time: TimeInterval) {
        anchorPosition = max(0, position)
        anchorTime = time
        self.isPlaying = isPlaying
    }

    /// Feeds in a position reported by Spotify, measured at `time`.
    @discardableResult
    public mutating func sync(reportedPosition reported: TimeInterval, isPlaying playing: Bool, at time: TimeInterval) -> SyncEvent {
        let predicted = position(at: time)
        let error = reported - predicted

        if abs(error) >= seekThreshold {
            reset(position: reported, isPlaying: playing, at: time)
            return .seek(from: predicted, to: reported)
        }
        if playing != isPlaying {
            reset(position: reported, isPlaying: playing, at: time)
            return .stateChange
        }
        if !playing || abs(error) > snapThreshold {
            reset(position: reported, isPlaying: playing, at: time)
        } else {
            // Small drift: correct part of it now, the rest on following reports.
            anchorPosition = max(0, predicted + error * blendFactor)
            anchorTime = time
        }
        return .drift(error)
    }
}
