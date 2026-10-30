import AVFoundation
import LyricscapeCore
import Observation
import os
import ScreenCaptureKit

/// Captures Spotify's audio (only Spotify's) with ScreenCaptureKit and analyses it
/// for beats. Requires Screen & System Audio Recording permission.
final class AudioReactor: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    enum StartResult: Sendable, Equatable {
        case running, needsPermission, spotifyNotRunning, failed(String)
    }

    private let queue = DispatchQueue(label: "app.lyricscape.audio", qos: .userInteractive)
    private let latest = OSAllocatedUnfairLock(initialState: AudioLevels.silent)
    /// Only touched on `queue`.
    private var detector: BeatDetector?
    private var stream: SCStream?
    var onStop: (@Sendable () -> Void)?

    /// Latest analysis; safe to read from any thread, every frame.
    var levels: AudioLevels { latest.withLock { $0 } }
    var isRunning: Bool { stream != nil }

    @MainActor
    func start() async -> StartResult {
        if stream != nil { return .running }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess() // shows the system prompt the first time
            return .needsPermission
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let spotify = content.applications.first(where: { $0.bundleIdentifier == SpotifyBridge.bundleID }),
                  let display = content.displays.first else { return .spotifyNotRunning }

            let filter = SCContentFilter(display: display, including: [spotify], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            config.excludesCurrentProcessAudio = true
            // Video is required but unused: keep it tiny and slow.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            queue.sync { detector = BeatDetector(sampleRate: 48_000) }
            try await stream.startCapture()
            self.stream = stream
            return .running
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    func stop() async {
        let stream = self.stream
        self.stream = nil
        try? await stream?.stopCapture()
        latest.withLock { $0 = .silent }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let detector, let samples = Self.monoSamples(sampleBuffer) else { return }
        detector.process(samples)
        let levels = detector.levels
        latest.withLock { $0 = levels }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        latest.withLock { $0 = .silent }
        onStop?()
    }

    /// Float32 mono samples from an audio sample buffer.
    private static func monoSamples(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        var bufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return nil }
        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
    }
}

/// Turns audio reactivity on/off and keeps retrying (Spotify not open yet, permission
/// just granted, Spotify restarted…) while it's on.
@MainActor @Observable
final class AudioController {
    enum Status: Equatable {
        case off
        case needsPermission
        case waitingForSpotify
        case running
        case failed(String)
    }

    private(set) var status: Status = .off
    @ObservationIgnored let reactor = AudioReactor()
    @ObservationIgnored private var task: Task<Void, Never>?

    func setEnabled(_ enabled: Bool) {
        task?.cancel()
        task = nil
        guard enabled else {
            Task { await reactor.stop() }
            status = .off
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.reactor.isRunning {
                    let result = await self.reactor.start()
                    let new: Status = switch result {
                    case .running: .running
                    case .needsPermission: .needsPermission
                    case .spotifyNotRunning: .waitingForSpotify
                    case .failed(let message): .failed(message)
                    }
                    if new != self.status {
                        self.status = new
                        Logger.app.notice("🔊 Audio reactivity: \(String(describing: new), privacy: .public)")
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        reactor.onStop = { [weak self] in
            Task { @MainActor in
                await self?.reactor.stop()
                self?.status = .waitingForSpotify
            }
        }
    }
}
