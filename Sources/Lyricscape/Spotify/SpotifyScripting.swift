import Foundation
import ScriptingBridge

// Minimal ScriptingBridge interface for the parts of Spotify's AppleScript
// dictionary we read. ScriptingBridge resolves these names dynamically.

@objc enum SpotifyPlayerState: AEKeyword {
    case stopped = 0x6B50_5353 // 'kPSS'
    case playing = 0x6B50_5350 // 'kPSP'
    case paused = 0x6B50_5370 // 'kPSp'
}

@objc protocol SpotifyTrackScripting {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    /// Milliseconds.
    @objc optional var duration: Int { get }
    @objc(id) optional func id() -> String
}

@objc protocol SpotifyApplicationScripting {
    @objc optional var currentTrack: SpotifyTrackScripting { get }
    /// Seconds.
    @objc optional var playerPosition: Double { get }
    @objc optional var playerState: SpotifyPlayerState { get }
}

extension SBObject: SpotifyTrackScripting {}
extension SBApplication: SpotifyApplicationScripting {}
