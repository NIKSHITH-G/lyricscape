import AppKit
import Carbon
import LyricscapeCore
import ScriptingBridge

/// Result of asking whether we may send Apple Events to Spotify.
enum AutomationPermission: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
    case spotifyNotRunning
    case other(OSStatus)

    init(status: OSStatus) {
        switch status {
        case noErr: self = .granted
        case OSStatus(errAEEventNotPermitted): self = .denied
        case OSStatus(errAEEventWouldRequireUserConsent): self = .notDetermined
        case OSStatus(procNotFound): self = .spotifyNotRunning
        default: self = .other(status)
        }
    }
}

/// One read of Spotify's player.
struct SpotifyReading: Sendable {
    var state: PlayerState
    var position: TimeInterval
    /// Monotonic time the position was valid at (midpoint of the Apple Event round trip).
    var timestamp: TimeInterval
    var track: Track?
}

enum SpotifyReadError: Error, Sendable {
    case notRunning
    case permissionDenied
    case failed(Int)
}

/// Talks to Spotify over Apple Events. All ScriptingBridge objects are confined to
/// one serial queue so a slow Spotify never blocks the UI.
final class SpotifyBridge: NSObject, @unchecked Sendable, SBApplicationDelegate {
    static let bundleID = "com.spotify.client"

    private let queue = DispatchQueue(label: "app.lyricscape.spotify-bridge", qos: .userInteractive)
    private var app: SBApplication?
    private var lastEventError: Int?
    private var cachedTrack: Track?

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Checks Automation permission. With `ask`, macOS shows its consent prompt the
    /// first time; this call blocks until the user answers, hence the background queue.
    func checkPermission(ask: Bool) async -> AutomationPermission {
        await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
                let status = target.aeDesc.map {
                    AEDeterminePermissionToAutomateTarget($0, typeWildCard, typeWildCard, ask)
                } ?? OSStatus(procNotFound)
                continuation.resume(returning: AutomationPermission(status: status))
            }
        }
    }

    func read() async -> Result<SpotifyReading, SpotifyReadError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readOnQueue())
            }
        }
    }

    private func readOnQueue() -> Result<SpotifyReading, SpotifyReadError> {
        // Never send events unless Spotify is already running: that would launch it.
        guard Self.isRunning else {
            cachedTrack = nil
            return .failure(.notRunning)
        }
        if app == nil {
            app = SBApplication(bundleIdentifier: Self.bundleID)
            app?.delegate = self
        }
        guard let app, app.isRunning else { return .failure(.notRunning) }
        let spotify = app as SpotifyApplicationScripting
        lastEventError = nil

        let state: PlayerState = switch spotify.playerState {
        case .playing: .playing
        case .paused: .paused
        default: .stopped
        }

        let t0 = ProcessInfo.processInfo.systemUptime
        let position = spotify.playerPosition ?? 0
        let t1 = ProcessInfo.processInfo.systemUptime

        // Only fetch full metadata when the track changes; the ID alone is cheap.
        let trackRef = spotify.currentTrack
        let trackID = trackRef?.id?() ?? ""
        if trackID.isEmpty {
            cachedTrack = nil
        } else if trackID != cachedTrack?.id, let trackRef {
            cachedTrack = Track(
                id: trackID,
                title: trackRef.name ?? "",
                artist: trackRef.artist ?? "",
                album: trackRef.album ?? "",
                duration: Double(trackRef.duration ?? 0) / 1000
            )
        }

        if let code = lastEventError {
            if code == Int(errAEEventNotPermitted) { return .failure(.permissionDenied) }
            if code == Int(procNotFound) || code == Int(connectionInvalid) { return .failure(.notRunning) }
            return .failure(.failed(code))
        }
        return .success(SpotifyReading(state: state, position: position, timestamp: (t0 + t1) / 2, track: cachedTrack))
    }

    // Called by ScriptingBridge (on our queue) when an Apple Event fails.
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: any Error) -> Any? {
        lastEventError = (error as NSError).code
        return nil
    }
}
