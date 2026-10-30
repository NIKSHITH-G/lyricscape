import Testing
@testable import LyricscapeCore

struct PlaybackClockTests {
    @Test func advancesWhilePlaying() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: true, at: 100)
        #expect(clock.position(at: 102.5) == 12.5)
    }

    @Test func freezesWhilePaused() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: false, at: 100)
        #expect(clock.position(at: 150) == 10)
    }

    @Test func smallDriftIsBlendedNotSnapped() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: true, at: 100)
        // Spotify says we're 0.1 s ahead of our prediction.
        let event = clock.sync(reportedPosition: 11.1, isPlaying: true, at: 101)
        guard case .drift(let error) = event else { Issue.record("expected drift"); return }
        #expect(abs(error - 0.1) < 1e-9)
        let pos = clock.position(at: 101)
        #expect(pos > 11.0 && pos < 11.1)
    }

    @Test func mediumDriftSnaps() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: true, at: 100)
        clock.sync(reportedPosition: 11.4, isPlaying: true, at: 101)
        #expect(clock.position(at: 101) == 11.4)
    }

    @Test func detectsSeekForwardAndBackward() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: true, at: 100)
        #expect(clock.sync(reportedPosition: 60, isPlaying: true, at: 101) == .seek(from: 11, to: 60))
        #expect(clock.position(at: 102) == 61)
        #expect(clock.sync(reportedPosition: 5, isPlaying: true, at: 102) == .seek(from: 61, to: 5))
    }

    @Test func pauseAndResumeReanchor() {
        var clock = PlaybackClock()
        clock.reset(position: 10, isPlaying: true, at: 100)
        #expect(clock.sync(reportedPosition: 12, isPlaying: false, at: 102) == .stateChange)
        #expect(clock.position(at: 200) == 12)
        #expect(clock.sync(reportedPosition: 12, isPlaying: true, at: 200) == .stateChange)
        #expect(clock.position(at: 201) == 13)
    }

    @Test func neverGoesNegative() {
        var clock = PlaybackClock()
        clock.reset(position: -3, isPlaying: false, at: 0)
        #expect(clock.position(at: 0) == 0)
    }
}

struct PlaybackModelTests {
    @Test func classifiesSpotifyURIs() {
        #expect(ContentKind(spotifyURI: "spotify:track:abc") == .music)
        #expect(ContentKind(spotifyURI: "spotify:episode:abc") == .podcast)
        #expect(ContentKind(spotifyURI: "spotify:ad:abc") == .ad)
        #expect(ContentKind(spotifyURI: "spotify:local:a:b:c:200") == .local)
        #expect(ContentKind(spotifyURI: "") == .unknown)
    }

    @Test func formatsTimes() {
        #expect(TimeFormat.string(83.4567) == "1:23")
        #expect(TimeFormat.string(83.4567, millis: true) == "1:23.457")
        #expect(TimeFormat.string(-5) == "0:00")
    }
}
