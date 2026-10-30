import Foundation

/// Deterministic random numbers (SplitMix64), so a lyric line always gets the same layout.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// Seed from a string. Swift's `hashValue` changes on every launch; FNV-1a doesn't.
    public init(_ key: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash
    }

    /// A stable 64-bit seed derived from a string.
    public static func seed(_ key: String) -> UInt64 {
        var rng = SeededRandom(key)
        return rng.next()
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
