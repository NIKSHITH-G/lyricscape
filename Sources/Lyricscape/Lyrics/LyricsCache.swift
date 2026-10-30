import CryptoKit
import Foundation

/// On-disk lyrics cache in ~/Library/Application Support/Lyricscape/Lyrics, one JSON
/// file per Spotify track. "Not found" results are cached too, but expire so newly
/// added lyrics on LRCLIB get picked up.
struct LyricsCache: Sendable {
    struct Entry: Codable, Sendable {
        var trackID: String
        var fetchedAt: Date
        /// nil = LRCLIB had nothing for this track.
        var record: LRCLIBRecord?
    }

    static let notFoundLifetime: TimeInterval = 3 * 24 * 3600

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "Lyricscape/Lyrics", directoryHint: .isDirectory)
    }

    func entry(for trackID: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: trackID)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        if entry.record == nil, Date().timeIntervalSince(entry.fetchedAt) > Self.notFoundLifetime { return nil }
        return entry
    }

    func store(_ record: LRCLIBRecord?, for trackID: String) {
        let entry = Entry(trackID: trackID, fetchedAt: Date(), record: record)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: fileURL(for: trackID), options: .atomic)
        } catch {
            // A failed cache write only costs a re-download next time.
        }
    }

    func remove(_ trackID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: trackID))
    }

    private func fileURL(for trackID: String) -> URL {
        // Hash the ID: local-file URIs can be long and contain any characters.
        let hash = SHA256.hash(data: Data(trackID.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).json")
    }
}
