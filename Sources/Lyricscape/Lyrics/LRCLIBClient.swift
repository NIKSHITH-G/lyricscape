import Foundation
import LyricscapeCore

/// A lyrics record as returned by https://lrclib.net.
struct LRCLIBRecord: Codable, Sendable, Equatable {
    var id: Int
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?

    var hasSyncedLyrics: Bool { !(syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPlainLyrics: Bool { !(plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Free, keyless LRCLIB API.
struct LRCLIBClient: Sendable {
    private let base = URL(string: "https://lrclib.net/api")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "Lyricscape/0.1.0 (macOS menu bar lyrics visualizer)"]
        return URLSession(configuration: config)
    }()

    /// Exact lookup first, then progressively fuzzier searches. A failing step (LRCLIB's
    /// /get answers 503 rather than 404 for some near-misses) falls through to the next;
    /// it only throws if nothing was found and some step failed, so a flaky network
    /// is never cached as "no lyrics".
    func lookup(_ track: Track) async throws -> LRCLIBRecord? {
        var lastError: (any Error)?
        do {
            if let exact = try await get(track) { return exact }
        } catch {
            try Task.checkCancellation()
            lastError = error
        }

        let title = SearchTerms.cleanTitle(track.title)
        let artist = SearchTerms.primaryArtist(track.artist)
        let searches: [[URLQueryItem]] = [
            [.init(name: "track_name", value: track.title), .init(name: "artist_name", value: track.artist)],
            [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)],
            [.init(name: "q", value: "\(title) \(artist)")],
        ]
        for query in searches {
            do {
                if let match = Self.bestMatch(in: try await search(query), for: track) { return match }
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func get(_ track: Track) async throws -> LRCLIBRecord? {
        let query: [URLQueryItem] = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        return try await request("get", query: query, as: LRCLIBRecord.self)
    }

    private func search(_ query: [URLQueryItem]) async throws -> [LRCLIBRecord] {
        try await request("search", query: query, as: [LRCLIBRecord].self) ?? []
    }

    /// Prefers synced lyrics, then the closest duration. Rejects results whose length
    /// is way off (likely a different recording with different timing).
    static func bestMatch(in records: [LRCLIBRecord], for track: Track) -> LRCLIBRecord? {
        let tolerance: TimeInterval = 5
        let title = track.title.lowercased()
        let usable = records.filter { record in
            guard record.hasSyncedLyrics || record.hasPlainLyrics || record.instrumental == true else { return false }
            // Skip "Song - Instrumental" / "Song (Karaoke)" unless that's what's playing.
            let name = (record.trackName ?? "").lowercased()
            for variant in ["instrumental", "karaoke", "inst."] where name.contains(variant) && !title.contains(variant) {
                return false
            }
            guard track.duration > 0, let d = record.duration else { return true }
            return abs(d - track.duration) <= tolerance
        }
        return usable.min { a, b in
            if a.hasSyncedLyrics != b.hasSyncedLyrics { return a.hasSyncedLyrics }
            return abs((a.duration ?? 0) - track.duration) < abs((b.duration ?? 0) - track.duration)
        }
    }

    /// Returns nil on 404.
    private func request<T: Decodable>(_ endpoint: String, query: [URLQueryItem], as: T.Type) async throws -> T? {
        var components = URLComponents(url: base.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let (data, response) = try await session.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
