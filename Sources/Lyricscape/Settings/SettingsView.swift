import AppKit
import LyricscapeCore
import Observation
import SwiftUI

/// View-local state for Settings (SwiftUI's @State isn't available with the
/// Command Line Tools toolchain, so it lives in a small observable model).
@MainActor @Observable
final class SettingsUIModel {
    enum Tab: Hashable { case style, look, lyrics, general }
    var tab: Tab = .style
    var presetName = ""
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let lyrics: LyricsController
    let audio: AudioController
    let subtitles: SubtitleService
    @Bindable var ui: SettingsUIModel

    var body: some View {
        VStack(spacing: 0) {
            StylePreview(settings: settings, subtitles: subtitles)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    Text("Preview · demo song")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(10)
                }
                .padding([.horizontal, .top], 16)
                .padding(.top, 20)

            TabView(selection: $ui.tab) {
                StyleTab(settings: settings, ui: ui).tabItem { Text("Style") }.tag(SettingsUIModel.Tab.style)
                LookTab(settings: settings).tabItem { Text("Look") }.tag(SettingsUIModel.Tab.look)
                LyricsTab(settings: settings, lyrics: lyrics, audio: audio, subtitles: subtitles)
                    .tabItem { Text("Lyrics & Sound") }.tag(SettingsUIModel.Tab.lyrics)
                GeneralTab(settings: settings).tabItem { Text("General") }.tag(SettingsUIModel.Tab.general)
            }
            .padding(16)
        }
        .frame(width: 760, height: 820)
    }
}

// MARK: - Live preview

/// The real renderer, small, playing the looping demo song.
private struct StylePreview: NSViewRepresentable {
    let settings: AppSettings
    let subtitles: SubtitleService

    func makeNSView(context: Context) -> LyricsStageView {
        let view = LyricsStageView(frame: CGRect(x: 0, y: 0, width: 728, height: 300), source: DemoLyricSource(),
                                   settings: settings, themes: ThemeDirector(), subtitles: subtitles, isPreview: true)
        view.start()
        return view
    }

    func updateNSView(_ nsView: LyricsStageView, context: Context) {}

    static func dismantleNSView(_ nsView: LyricsStageView, coordinator: ()) {
        nsView.stop()
    }
}

// MARK: - Style

private struct StyleTab: View {
    @Bindable var settings: AppSettings
    @Bindable var ui: SettingsUIModel

    var body: some View {
        Form {
            Section("Style") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                    ForEach(StyleRegistry.ids, id: \.self) { id in
                        let style = StyleRegistry.style(withID: id)
                        Button {
                            settings.styleID = id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName).font(.body.weight(.semibold))
                                Text(style.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(settings.styleID == id ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tip: \(settings.hotKeys[.nextStyle]?.displayString ?? "") switches style from anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Presets") {
                HStack {
                    TextField("Name", text: $ui.presetName, prompt: Text("Save the current style and look as…"))
                    Button("Save") {
                        settings.savePreset(named: ui.presetName.trimmingCharacters(in: .whitespaces))
                        ui.presetName = ""
                    }
                    .disabled(ui.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if settings.presets.isEmpty {
                    Text("No saved presets yet.").foregroundStyle(.secondary)
                }
                ForEach(settings.presets) { preset in
                    HStack {
                        Text(preset.name)
                        Text(StyleRegistry.style(withID: preset.styleID).displayName).foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply") { settings.apply(preset) }
                        Button(role: .destructive) {
                            settings.presets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Look

private struct LookTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Colours") {
                Picker("Theme", selection: $settings.styleSettings.themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.styleSettings.themeMode {
                case .newEachPlay:
                    Text("Every song — and every replay — gets a fresh neon palette, never close to the last few.")
                        .font(.caption).foregroundStyle(.secondary)
                case .albumArt:
                    Text("Colours come from each song's cover art, varied slightly on every play.")
                        .font(.caption).foregroundStyle(.secondary)
                case .fixed:
                    Picker("Preset", selection: presetBinding) {
                        ForEach(LyricTheme.presets, id: \.name) { Text($0.name).tag($0.name) }
                        if !LyricTheme.presets.contains(where: { $0.name == settings.styleSettings.theme.name }) {
                            Text("Custom").tag(settings.styleSettings.theme.name)
                        }
                    }
                    HStack {
                        color("Text", \.text)
                        color("Glow", \.glow)
                        color("Accent", \.accent)
                        color("Lines", \.line)
                    }
                }
            }
            Section("Type") {
                Picker("Font", selection: $settings.styleSettings.fontName) {
                    Text("SF Pro Rounded").tag(String?.none)
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                slider("Size", $settings.styleSettings.sizeScale, 0.6...1.6)
            }
            Section("Feel") {
                slider("Glow", $settings.styleSettings.glow, 0...2)
                slider("Animation speed", $settings.styleSettings.speed, 0.5...2)
                slider("Spread / density", $settings.styleSettings.spread, 0.6...1.6)
                slider("Opacity", $settings.styleSettings.opacity, 0.2...1)
                Picker("Position", selection: $settings.styleSettings.anchor) {
                    ForEach(ScreenAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Neon frame around the screen", isOn: $settings.styleSettings.showFrame)
            }
            Section {
                Button("Reset look to defaults") {
                    let mode = settings.styleSettings.themeMode
                    settings.styleSettings = StyleSettings()
                    settings.styleSettings.themeMode = mode
                }
            }
        }
        .formStyle(.grouped)
    }

    private var presetBinding: Binding<String> {
        Binding(get: { settings.styleSettings.theme.name },
                set: { name in
                    if let theme = LyricTheme.presets.first(where: { $0.name == name }) { settings.styleSettings.theme = theme }
                })
    }

    private func color(_ title: String, _ keyPath: WritableKeyPath<LyricTheme, RGBA>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: settings.styleSettings.theme[keyPath: keyPath].nsColor) },
            set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                settings.styleSettings.theme[keyPath: keyPath] = RGBA(c.redComponent, c.greenComponent, c.blueComponent)
                settings.styleSettings.theme.name = "Custom"
            }), supportsOpacity: false)
    }
}

private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
    LabeledContent(title) {
        HStack {
            Slider(value: value, in: range)
            Text(String(format: "%.1f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
    }
}

// MARK: - Lyrics & sound

private struct LyricsTab: View {
    @Bindable var settings: AppSettings
    @Bindable var lyrics: LyricsController
    let audio: AudioController
    let subtitles: SubtitleService

    var body: some View {
        Form {
            Section("Timing") {
                LabeledContent("Lyrics offset") {
                    HStack {
                        Button { lyrics.adjustOffset(by: -0.1) } label: { Image(systemName: "minus") }
                        Text(offsetLabel).font(.body.monospacedDigit()).frame(minWidth: 110)
                        Button { lyrics.adjustOffset(by: 0.1) } label: { Image(systemName: "plus") }
                        Button("Reset") { lyrics.offset = 0 }.disabled(lyrics.offset == 0)
                    }
                }
                Text("If lyrics are consistently early or late, nudge them here in 0.1 s steps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Translation & romanization") {
                Picker("Show under the lyrics", selection: $settings.subtitleMode) {
                    ForEach(SubtitleMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Romanization spells Korean, Japanese, Chinese and other scripts in Latin letters. Translation uses Apple's on-device translation into \(Locale.current.localizedString(forLanguageCode: subtitles.targetLanguage.languageCode?.identifier ?? "en") ?? "your language").")
                    .font(.caption).foregroundStyle(.secondary)
                if let problem = subtitles.lastProblem, settings.subtitleMode != .off {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Sound") {
                Toggle("React to the music (beats, bass)", isOn: $settings.audioReactive)
                if settings.audioReactive {
                    LabeledContent("Status", value: audioStatus)
                    if audio.status == .needsPermission {
                        Button("Open Screen & System Audio Recording settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                        Text("Turn on Lyricscape there, then come back — it starts by itself. Lyricscape only listens to Spotify's audio and never records your screen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var offsetLabel: String {
        if lyrics.offset == 0 { return "in sync" }
        return String(format: "%.1f s %@", abs(lyrics.offset), lyrics.offset > 0 ? "earlier" : "later")
    }

    private var audioStatus: String {
        switch audio.status {
        case .off: "Off"
        case .needsPermission: "Needs permission"
        case .waitingForSpotify: "Waiting for Spotify"
        case .running: "Listening ✓"
        case .failed(let message): "Error: \(message)"
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Overlay") {
                Toggle("Show lyrics on screen", isOn: $settings.overlayVisible)
                Toggle("Stage mode (black background)", isOn: $settings.stageMode)
                Picker("Display", selection: $settings.displayID) {
                    Text("Main display").tag(CGDirectDisplayID?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
            }
            Section("Keyboard shortcuts") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(hotKey: Binding(
                            get: { settings.hotKeys[action] ?? HotKey.defaults[action]! },
                            set: { settings.hotKeys[action] = $0 }))
                        .frame(width: 140, height: 24)
                    }
                }
                Button("Restore default shortcuts") { settings.hotKeys = HotKey.defaults }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }
}

/// Click, then press a key combination (with ⌘, ⌥ or ⌃) to set a shortcut. Esc cancels.
private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { hotKey = $0 }
        button.hotKey = hotKey
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onRecord = { hotKey = $0 }
        nsView.hotKey = hotKey
    }

    final class RecorderButton: NSButton {
        var onRecord: ((HotKey) -> Void)?
        var hotKey: HotKey? { didSet { refresh() } }
        private var recording = false { didSet { refresh() } }

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            target = self
            action = #selector(startRecording)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        @objc private func startRecording() {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            if event.keyCode == 53 { recording = false; return } // Esc
            if let key = HotKey(event: event) {
                recording = false
                onRecord?(key)
            } else {
                NSSound.beep()
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // ⌘-combinations arrive here rather than in keyDown.
            guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return super.resignFirstResponder()
        }

        private func refresh() {
            title = recording ? "Press shortcut…" : hotKey?.displayString ?? "—"
        }
    }
}
