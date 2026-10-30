import AppKit
import LyricscapeCore
import Observation
import OSLog

enum SpotifyConnection: Equatable {
    case checking
    case notInstalled
    case notRunning
    case permissionDenied
    case connected
}

/// Tracks what Spotify is playing and exposes a smooth, interpolated playback position.
///
/// Sources of truth, fastest first:
/// 1. `com.spotify.client.PlaybackStateChanged` distributed notifications (track change, play/pause)
/// 2. Polling over Apple Events every 0.5 s while playing (position, seeks)
/// 3. `PlaybackClock` interpolation between polls (every frame)
@MainActor @Observable
final class SpotifyMonitor {
    private(set) var connection: SpotifyConnection = .checking
    private(set) var track: Track? {
        didSet {
            if track?.id != oldValue?.id { onTrackChange?(track) }
        }
    }

    /// Called whenever the playing item changes (nil when nothing is playing).
    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?
    private(set) var playerState: PlayerState = .stopped
    private(set) var clock = PlaybackClock()
    /// Increases every time a song starts playing: a new track, or the same track
    /// restarted from the beginning (repeat, "previous", or dragging back to 0:00).
    private(set) var playID = 0

    var isPlaying: Bool { connection == .connected && playerState == .playing }

    func position(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        clock.position(at: now)
    }

    @ObservationIgnored private let bridge = SpotifyBridge()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var hasAskedForPermission = false
    @ObservationIgnored private var permissionGranted = false
    @ObservationIgnored private var isPolling = false
    @ObservationIgnored private var repollRequested = false
    @ObservationIgnored private var lastPositionLog: TimeInterval = 0

    private var pollInterval: Duration { isPlaying ? .milliseconds(500) : .milliseconds(1500) }

    func start() {
        guard pollTask == nil else { return }
        observeNotifications()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    /// Reads Spotify now. Coalesces overlapping requests.
    func poll() async {
        if isPolling {
            repollRequested = true
            return
        }
        isPolling = true
        repeat {
            repollRequested = false
            await pollOnce()
        } while repollRequested
        isPolling = false
    }

    // MARK: - Polling

    private func pollOnce() async {
        guard SpotifyBridge.isRunning else {
            setConnection(SpotifyBridge.isInstalled ? .notRunning : .notInstalled)
            return
        }

        if !permissionGranted {
            // Show the macOS consent prompt once per launch; afterwards just re-check
            // quietly so we notice when the user flips the switch in System Settings.
            let ask = !hasAskedForPermission
            hasAskedForPermission = true
            switch await bridge.checkPermission(ask: ask) {
            case .granted:
                permissionGranted = true
            case .denied, .notDetermined:
                setConnection(.permissionDenied)
                return
            case .spotifyNotRunning:
                setConnection(.notRunning)
                return
            case .other(let status):
                Logger.spotify.error("Automation permission check failed: OSStatus \(status, privacy: .public)")
                return
            }
        }

        switch await bridge.read() {
        case .success(let reading):
            setConnection(.connected)
            apply(reading)
        case .failure(.notRunning):
            setConnection(.notRunning)
        case .failure(.permissionDenied):
            permissionGranted = false
            setConnection(.permissionDenied)
        case .failure(.failed(let code)):
            Logger.spotify.error("Reading Spotify failed: error \(code, privacy: .public)")
        }
    }

    private func apply(_ reading: SpotifyReading) {
        let playing = reading.state == .playing

        if reading.track?.id != track?.id {
            track = reading.track
            playID += 1
            playerState = reading.state
            clock.reset(position: reading.position, isPlaying: playing, at: reading.timestamp)
            logTrack()
            return
        }

        let event = clock.sync(reportedPosition: reading.position, isPlaying: playing, at: reading.timestamp)
        if reading.state != playerState {
            playerState = reading.state
            logState()
        }

        switch event {
        case .seek(let from, let to):
            if to < 2 && from > 10 {
                playID += 1
                Logger.spotify.notice("🔁 Song restarted")
            }
            Logger.spotify.notice("⏩ Seek \(TimeFormat.string(from, millis: true), privacy: .public) → \(TimeFormat.string(to, millis: true), privacy: .public)")
        case .drift(let error):
            #if DEBUG
            if playing, reading.timestamp - lastPositionLog >= 1 {
                lastPositionLog = reading.timestamp
                let shown = TimeFormat.string(position(at: reading.timestamp), millis: true)
                let total = TimeFormat.string(track?.duration ?? 0)
                let reported = TimeFormat.string(reading.position, millis: true)
                let driftMS = Int((error * 1000).rounded())
                Logger.spotify.notice("⏱ \(shown, privacy: .public) / \(total, privacy: .public)   (Spotify said \(reported, privacy: .public), drift \(driftMS >= 0 ? "+" : "", privacy: .public)\(driftMS, privacy: .public) ms)")
            }
            #endif
        case .stateChange:
            break
        }
    }

    private func setConnection(_ new: SpotifyConnection) {
        guard new != connection else { return }
        connection = new
        if new != .connected {
            track = nil
            playerState = .stopped
            clock.reset(position: 0, isPlaying: false, at: ProcessInfo.processInfo.systemUptime)
        }
        switch new {
        case .checking: break
        case .connected: Logger.spotify.notice("✅ Connected to Spotify")
        case .notRunning: Logger.spotify.notice("💤 Spotify isn't running — waiting for it to start")
        case .notInstalled: Logger.spotify.notice("❓ Spotify desktop app isn't installed")
        case .permissionDenied:
            Logger.spotify.notice("🔒 No permission to read Spotify. Allow it in System Settings → Privacy & Security → Automation → Lyricscape → Spotify")
        }
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let info = SpotifyNotificationInfo(note.userInfo)
            MainActor.assumeIsolated { self?.handle(info) }
        }
        observers.append((distributed, token))

        // React immediately when Spotify launches or quits.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == SpotifyBridge.bundleID else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.poll() }
                }
            }
            observers.append((workspace, token))
        }
    }

    private func handle(_ info: SpotifyNotificationInfo) {
        // Apply play/pause instantly so the lyrics freeze/resume without waiting for a poll…
        if connection == .connected, let state = info.state, info.trackID == track?.id {
            let now = ProcessInfo.processInfo.systemUptime
            clock.sync(reportedPosition: info.position ?? position(at: now), isPlaying: state == .playing, at: now)
            if state != playerState {
                playerState = state
                logState()
            }
        }
        // …then confirm everything (including track changes) with a fresh read.
        Task { await poll() }
    }

    // MARK: - Logging

    private func logTrack() {
        guard let track else {
            Logger.spotify.notice("⏹ Nothing playing")
            return
        }
        let note = switch track.kind {
        case .ad: "  [advertisement — no lyrics]"
        case .podcast: "  [podcast episode — no lyrics]"
        case .local: "  [local file]"
        case .music, .unknown: ""
        }
        Logger.spotify.notice("🎵 Now playing: “\(track.title, privacy: .public)” — \(track.artist, privacy: .public) · \(track.album, privacy: .public) (\(TimeFormat.string(track.duration), privacy: .public)) \(track.id, privacy: .public)\(note, privacy: .public)")
        logState()
    }

    private func logState() {
        let pos = TimeFormat.string(position(), millis: true)
        switch playerState {
        case .playing: Logger.spotify.notice("▶️ Playing from \(pos, privacy: .public)")
        case .paused: Logger.spotify.notice("⏸ Paused at \(pos, privacy: .public)")
        case .stopped: Logger.spotify.notice("⏹ Stopped")
        }
    }
}

/// The parts of Spotify's PlaybackStateChanged notification we use.
private struct SpotifyNotificationInfo: Sendable {
    var state: PlayerState?
    var trackID: String?
    var position: TimeInterval?

    init(_ userInfo: [AnyHashable: Any]?) {
        state = switch userInfo?["Player State"] as? String {
        case "Playing": .playing
        case "Paused": .paused
        case "Stopped": .stopped
        default: nil
        }
        trackID = userInfo?["Track ID"] as? String
        position = (userInfo?["Playback Position"] as? NSNumber)?.doubleValue
    }
}
