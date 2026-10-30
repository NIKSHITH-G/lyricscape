import Foundation
import LyricscapeCore

enum LyricsResult: Sendable, Equatable {
    case found(LyricsDocument)
    case instrumental
    case notFound
}

enum LyricsSource: String, Sendable {
    case cache, network
}

/// Fetches, caches and parses lyrics for a track.
actor LyricsProvider {
    private let client = LRCLIBClient()
    private let cache = LyricsCache()

    /// Throws only on network failure with nothing cached.
    func lyrics(for track: Track) async throws -> (LyricsResult, LyricsSource) {
        if let entry = cache.entry(for: track.id) {
            return (Self.result(from: entry.record, track: track), .cache)
        }
        let record = try await client.lookup(track)
        cache.store(record, for: track.id)
        return (Self.result(from: record, track: track), .network)
    }

    /// Drops the cached copy so the next lookup goes to the network.
    func forget(_ track: Track) {
        cache.remove(track.id)
    }

    private static func result(from record: LRCLIBRecord?, track: Track) -> LyricsResult {
        guard let record else { return .notFound }
        if let synced = record.syncedLyrics, record.hasSyncedLyrics {
            let document = LRCParser.parse(synced, trackDuration: track.duration)
            if !document.lines.isEmpty { return .found(document) }
        }
        if let plain = record.plainLyrics, record.hasPlainLyrics {
            return .found(LRCParser.plain(plain))
        }
        return record.instrumental == true ? .instrumental : .notFound
    }
}
