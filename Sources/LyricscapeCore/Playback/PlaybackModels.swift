import Foundation

public enum PlayerState: String, Sendable, Equatable {
    case playing, paused, stopped
}

/// What kind of item Spotify is playing, derived from its URI.
public enum ContentKind: String, Sendable, Equatable {
    case music, podcast, ad, local, unknown

    public init(spotifyURI uri: String) {
        switch true {
        case uri.hasPrefix("spotify:track:"): self = .music
        case uri.hasPrefix("spotify:episode:"): self = .podcast
        case uri.hasPrefix("spotify:ad:"): self = .ad
        case uri.hasPrefix("spotify:local:"): self = .local
        default: self = .unknown
        }
    }

    /// Whether it makes sense to look up lyrics for this item.
    public var mayHaveLyrics: Bool { self == .music || self == .local }
}

public struct Track: Sendable, Equatable, Identifiable {
    /// Spotify URI, e.g. "spotify:track:4uLU6hMCjMI75M1A2tKUQC".
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let kind: ContentKind

    public init(id: String, title: String, artist: String, album: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.kind = ContentKind(spotifyURI: id)
    }
}

public enum TimeFormat {
    /// 83.4567 → "1:23" or, with `millis`, "1:23.457".
    public static func string(_ seconds: TimeInterval, millis: Bool = false) -> String {
        let s = max(0, seconds.isFinite ? seconds : 0)
        let minutes = Int(s) / 60
        if millis {
            let rest = s - Double(minutes * 60)
            return String(format: "%d:%06.3f", minutes, rest)
        }
        return String(format: "%d:%02d", minutes, Int(s) % 60)
    }
}
