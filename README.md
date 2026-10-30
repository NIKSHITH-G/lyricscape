# Lyricscape

A macOS menu bar app that shows the lyrics of whatever is playing in the Spotify desktop app as full-screen animated typography, synced to the song.

## Build & run

No Xcode needed. The Command Line Tools are enough.

```sh
scripts/run.sh          # build (debug), launch, and stream the app's log here
swift test              # unit tests
scripts/build-app.sh release   # optimized build → build/Lyricscape.app
```

The app is in `build/Lyricscape.app`. You can drag it into /Applications.

### Permissions
- **Automation (Spotify)**: on first launch, macOS asks "Lyricscape wants to control Spotify". Click **OK**. If you clicked Don't Allow, go to System Settings → Privacy & Security → Automation → Lyricscape and turn on Spotify.
- Builds are signed ad-hoc (no Apple developer certificate), so macOS may ask again after a rebuild. If it gets stuck as denied, run `tccutil reset AppleEvents app.lyricscape.Lyricscape` and relaunch.

## Architecture

```
Sources/
  LyricscapeCore/            pure logic, no UI, unit tested
    Playback/                PlaybackClock (interpolation + seek detection), Track, PlayerState
    Lyrics/                  LRCParser, LyricsDocument, word-timing estimation          (stage 2)
    Sync/                    SyncEngine: position → current line/word/progress           (stage 2)
  Lyricscape/                the app
    App/                     entry point, AppDelegate, logging, settings store
    Spotify/                 SpotifyBridge (ScriptingBridge, own queue), SpotifyMonitor
    Lyrics/                  LyricsProvider (LRCLIB API + disk cache)                    (stage 2)
    Overlay/                 OverlayWindowController (click-through panel per display)   (stage 3)
    Styles/                  LyricStyle protocol + one file per style                    (stages 4, 6)
    Settings/                settings window, live preview, demo song, hotkeys           (stage 5)
    MenuBar/                 menu bar popover
Tests/LyricscapeCoreTests/   PlaybackClock, LRC parser, SyncEngine tests
Resources/Info.plist         LSUIElement (no Dock icon), Apple Events usage description
scripts/                     build-app.sh, run.sh
```

How the timing works:
1. Spotify's `PlaybackStateChanged` distributed notification reports track changes and play/pause immediately.
2. Polling over Apple Events every 0.5 s while playing (1.5 s otherwise) gives the exact position. Each reading is timestamped at the midpoint of the round trip.
3. `PlaybackClock` interpolates between readings on a monotonic clock. Small drift is blended in gradually, larger errors snap, and jumps over 1 s count as seeks.

## Stages
1. ✅ Spotify reading + console log
2. Lyrics fetch (LRCLIB) + cache + LRC parser + sync engine
3. Overlay window with simple text
4. Constellation style
5. Settings window
6. Remaining styles
