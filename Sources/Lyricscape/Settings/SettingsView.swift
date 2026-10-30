import AppKit
import LyricscapeCore
import Observation
import SwiftUI

// MARK: - Look & feel

/// Brand colours shared by the Settings window (and the website).
enum Brand {
    static let background = Color(red: 0.043, green: 0.035, blue: 0.067)
    static let sidebar = Color(red: 0.06, green: 0.05, blue: 0.09)
    static let panel = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.08)
    static let pink = Color(red: 1, green: 0.165, blue: 0.427)
    static let violet = Color(red: 0.545, green: 0.36, blue: 0.965)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let gradient = LinearGradient(colors: [pink, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let website = URL(string: "https://getlyricscape.vercel.app")!
    static let github = URL(string: "https://github.com/NIKSHITH-G/lyricscape")!
    static let releases = URL(string: "https://github.com/NIKSHITH-G/lyricscape/releases")!
}

/// View-local state for Settings (SwiftUI's @State isn't available with the
/// Command Line Tools toolchain, so it lives in a small observable model).
@MainActor @Observable
final class SettingsUIModel {
    enum Section: String, CaseIterable, Identifiable {
        case styles, look, lyrics, general, about
        var id: Self { self }

        var title: String {
            switch self {
            case .styles: "Styles"
            case .look: "Look"
            case .lyrics: "Lyrics & Sound"
            case .general: "General"
            case .about: "About"
            }
        }

        var subtitle: String {
            switch self {
            case .styles: "Pick how the lyrics move. Save the looks you love as presets."
            case .look: "Colours, type and feel — every change shows up live."
            case .lyrics: "Timing, translations and reacting to the beat."
            case .general: "Where the lyrics appear, and how you summon them."
            case .about: "Lyricscape — your music, written across the sky."
            }
        }

        var icon: String {
            switch self {
            case .styles: "sparkles"
            case .look: "paintpalette"
            case .lyrics: "music.note"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }

        var showsPreview: Bool { self == .styles || self == .look || self == .lyrics }
    }

    var section: Section = .styles
    var presetName = ""
    var hoveredStyle: String?
}

/// Rendered thumbnails of every style (made offscreen with the demo song).
@MainActor @Observable
final class StyleThumbnails {
    private(set) var images: [String: NSImage] = [:]

    func load() {
        guard images.isEmpty else { return }
        Task {
            for id in StyleRegistry.ids {
                await Task.yield() // keep the window responsive while rendering
                var settings = StyleSettings()
                settings.theme = Snapshot.showcaseTheme(for: id)
                let size = CGSize(width: 400, height: 250)
                if let image = Snapshot.still(styleID: id, size: size, time: Snapshot.showcaseTime[id] ?? 12,
                                              settings: settings, scale: 2) {
                    images[id] = NSImage(cgImage: image, size: size)
                }
            }
        }
    }
}

// MARK: - Window content

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let lyrics: LyricsController
    let audio: AudioController
    let subtitles: SubtitleService
    @Bindable var ui: SettingsUIModel
    let thumbnails: StyleThumbnails

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(ui: ui)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ui.section.title).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(ui.section.subtitle).font(.callout).foregroundStyle(Brand.secondary)
                    }
                    if ui.section.showsPreview {
                        PreviewCard(settings: settings, subtitles: subtitles)
                    }
                    switch ui.section {
                    case .styles: StylesSection(settings: settings, ui: ui, thumbnails: thumbnails)
                    case .look: LookSection(settings: settings)
                    case .lyrics: LyricsSection(settings: settings, lyrics: lyrics, audio: audio, subtitles: subtitles)
                    case .general: GeneralSection(settings: settings)
                    case .about: AboutSection()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 44)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 960, height: 760)
        .background(Brand.background)
        .foregroundStyle(Brand.text)
        .tint(Brand.pink)
        .preferredColorScheme(.dark)
        .onAppear { thumbnails.load() }
    }
}

private struct Sidebar: View {
    @Bindable var ui: SettingsUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Lyricscape").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("v\(AboutSection.version)").font(.caption2).foregroundStyle(Brand.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 46)
            .padding(.bottom, 18)

            ForEach(SettingsUIModel.Section.allCases) { section in
                let selected = ui.section == section
                Button {
                    ui.section = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18)
                        Text(section.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? Color.white : Brand.secondary)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8).fill(Brand.gradient.opacity(0.85))
                                .shadow(color: Brand.pink.opacity(0.35), radius: 10)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Made with ♪ for Spotify on macOS")
                .font(.caption2)
                .foregroundStyle(Brand.secondary.opacity(0.7))
                .padding(10)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Brand.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.stroke).frame(width: 1) }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.gradient)
                    }
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Brand.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.stroke))
    }
}

private struct Row<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(Brand.secondary) }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

private struct SliderRow: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(Brand.secondary)
            Text(title).font(.system(size: 13, weight: .medium)).frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.1f×", value))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// A pill-style button group, used instead of the default segmented control.
private struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let selected = selection == value
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.white : Brand.secondary)
                        .background(Capsule().fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Live preview

private struct PreviewCard: View {
    let settings: AppSettings
    let subtitles: SubtitleService

    var body: some View {
        StylePreview(settings: settings, subtitles: subtitles)
            .frame(height: 290)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gradient.opacity(0.6), lineWidth: 1))
            .shadow(color: Brand.pink.opacity(0.18), radius: 24, y: 8)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Circle().fill(Brand.pink).frame(width: 6, height: 6).shadow(color: Brand.pink, radius: 4)
                    Text("LIVE PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1)
                    Text("· demo song").font(.system(size: 10)).foregroundStyle(Brand.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(StyleRegistry.style(withID: settings.styleID).displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(12)
            }
    }
}

/// The real renderer, small, playing the looping demo song.
private struct StylePreview: NSViewRepresentable {
    let settings: AppSettings
    let subtitles: SubtitleService

    func makeNSView(context: Context) -> LyricsStageView {
        let view = LyricsStageView(frame: CGRect(x: 0, y: 0, width: 690, height: 290), source: DemoLyricSource(),
                                   settings: settings, themes: ThemeDirector(), subtitles: subtitles, isPreview: true)
        view.start()
        return view
    }

    func updateNSView(_ nsView: LyricsStageView, context: Context) {}

    static func dismantleNSView(_ nsView: LyricsStageView, coordinator: ()) {
        nsView.stop()
    }
}

// MARK: - Styles

private struct StylesSection: View {
    @Bindable var settings: AppSettings
    @Bindable var ui: SettingsUIModel
    let thumbnails: StyleThumbnails

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(StyleRegistry.ids, id: \.self) { id in
                    styleCard(id)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "keyboard").foregroundStyle(Brand.secondary)
                Text("Press \(settings.hotKeys[.nextStyle]?.displayString ?? "") anywhere to flip to the next style.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }

            Card(title: "Presets", icon: "bookmark.fill") {
                HStack(spacing: 10) {
                    TextField("Name this look…", text: $ui.presetName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                    Button {
                        settings.savePreset(named: ui.presetName.trimmingCharacters(in: .whitespaces))
                        ui.presetName = ""
                    } label: {
                        Label("Save", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Brand.gradient))
                    }
                    .buttonStyle(.plain)
                    .disabled(ui.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(ui.presetName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                if settings.presets.isEmpty {
                    Text("Your saved looks will appear here — style, colours, font and feel, one click away.")
                        .font(.caption).foregroundStyle(Brand.secondary)
                }
                ForEach(settings.presets) { preset in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(LinearGradient(colors: [Color(nsColor: preset.settings.theme.glow.nsColor),
                                                          Color(nsColor: preset.settings.theme.line.nsColor)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name).font(.system(size: 13, weight: .semibold))
                            Text(StyleRegistry.style(withID: preset.styleID).displayName)
                                .font(.caption).foregroundStyle(Brand.secondary)
                        }
                        Spacer()
                        Button("Apply") { settings.apply(preset) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.pink)
                        Button {
                            settings.presets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "trash").foregroundStyle(Brand.secondary) }
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func styleCard(_ id: String) -> some View {
        let style = StyleRegistry.style(withID: id)
        let selected = settings.styleID == id
        let hovered = ui.hoveredStyle == id
        return Button {
            settings.styleID = id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Rectangle().fill(Color.black)
                    if let image = thumbnails.images[id] {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 112)
                .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(style.displayName).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.gradient)
                        }
                    }
                    Text(style.summary).font(.caption).foregroundStyle(Brand.secondary).lineLimit(1)
                }
                .padding(10)
            }
            .background(Brand.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.stroke), lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Brand.pink.opacity(0.3) : .clear, radius: 12)
            .scaleEffect(hovered ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { ui.hoveredStyle = $0 ? id : (ui.hoveredStyle == id ? nil : ui.hoveredStyle) }
    }
}

// MARK: - Look

private struct LookSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Colours", icon: "drop.fill") {
                HStack(spacing: 12) {
                    modeCard(.newEachPlay, icon: "sparkles", caption: "A fresh neon palette every song — and every replay.")
                    modeCard(.albumArt, icon: "photo", caption: "Colours pulled from the cover, varied each play.")
                    modeCard(.fixed, icon: "lock", caption: "Your pick, every time.")
                }
                if settings.styleSettings.themeMode == .fixed {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 9), alignment: .leading, spacing: 10) {
                        ForEach(LyricTheme.presets, id: \.name) { theme in swatch(theme) }
                    }
                    HStack(spacing: 18) {
                        color("Text", \.text)
                        color("Glow", \.glow)
                        color("Accent", \.accent)
                        color("Lines", \.line)
                    }
                    .font(.caption)
                }
            }

            Card(title: "Type", icon: "textformat") {
                Row(title: "Font", detail: "Every style uses it; Typewriter stays monospaced by default.") {
                    Picker("", selection: $settings.styleSettings.fontName) {
                        Text("SF Pro Rounded").tag(String?.none)
                        Divider()
                        ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                SliderRow(title: "Size", icon: "textformat.size", value: $settings.styleSettings.sizeScale, range: 0.6...1.6)
            }

            Card(title: "Feel", icon: "wand.and.stars") {
                SliderRow(title: "Glow", icon: "sun.max", value: $settings.styleSettings.glow, range: 0...2)
                SliderRow(title: "Speed", icon: "hare", value: $settings.styleSettings.speed, range: 0.5...2)
                SliderRow(title: "Spread", icon: "arrow.up.left.and.arrow.down.right", value: $settings.styleSettings.spread, range: 0.6...1.6)
                SliderRow(title: "Opacity", icon: "circle.lefthalf.filled", value: $settings.styleSettings.opacity, range: 0.2...1)
                Divider().overlay(Brand.stroke)
                Row(title: "Neon frame", detail: "A glowing border round the screen that flashes on the big words.") {
                    Toggle("", isOn: $settings.styleSettings.showFrame).toggleStyle(.switch).labelsHidden()
                }
            }

            Card(title: "Position", icon: "rectangle.dashed") {
                HStack(alignment: .top, spacing: 20) {
                    PositionPicker(anchor: $settings.styleSettings.anchor)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.styleSettings.anchor.title).font(.system(size: 15, weight: .semibold))
                        Text("Where Karaoke, Typewriter, Glitch, Particles and Minimal sit on screen. Minimal treats Centre as bottom-left.")
                            .font(.caption).foregroundStyle(Brand.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    let mode = settings.styleSettings.themeMode
                    settings.styleSettings = StyleSettings()
                    settings.styleSettings.themeMode = mode
                } label: {
                    Label("Reset look", systemImage: "arrow.counterclockwise").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.secondary)
            }
        }
    }

    private func modeCard(_ mode: ThemeMode, icon: String, caption: String) -> some View {
        let selected = settings.styleSettings.themeMode == mode
        return Button { settings.styleSettings.themeMode = mode } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.secondary))
                Text(mode.title).font(.system(size: 13, weight: .semibold))
                Text(caption).font(.caption).foregroundStyle(Brand.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.07 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.stroke), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ theme: LyricTheme) -> some View {
        let selected = settings.styleSettings.theme.name == theme.name
        return Button { settings.styleSettings.theme = theme } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(RadialGradient(colors: [Color(nsColor: theme.accent.nsColor), Color(nsColor: theme.glow.nsColor)],
                                         center: .center, startRadius: 2, endRadius: 18))
                    .frame(width: 34, height: 34)
                    .shadow(color: Color(nsColor: theme.glow.nsColor).opacity(0.7), radius: selected ? 10 : 4)
                    .overlay(Circle().stroke(Color.white, lineWidth: selected ? 2 : 0))
                Text(theme.name).font(.system(size: 10)).foregroundStyle(selected ? Brand.text : Brand.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
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

/// A miniature screen with clickable spots for each position.
private struct PositionPicker: View {
    @Binding var anchor: ScreenAnchor

    private let grid: [[ScreenAnchor?]] = [
        [.topLeft, .top, .topRight],
        [nil, .center, nil],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { c in
                        if let spot = grid[r][c] {
                            Button { anchor = spot } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(anchor == spot ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                                    .frame(width: 38, height: 22)
                                    .shadow(color: anchor == spot ? Brand.pink.opacity(0.6) : .clear, radius: 6)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 38, height: 22)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.stroke))
    }
}

// MARK: - Lyrics & sound

private struct LyricsSection: View {
    @Bindable var settings: AppSettings
    @Bindable var lyrics: LyricsController
    let audio: AudioController
    let subtitles: SubtitleService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Timing", icon: "metronome") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offsetLabel).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Nudge if lyrics are consistently early or late.").font(.caption).foregroundStyle(Brand.secondary)
                    }
                    Spacer()
                    stepButton("minus", help: "Show lyrics later") { lyrics.adjustOffset(by: -0.1) }
                    stepButton("plus", help: "Show lyrics earlier") { lyrics.adjustOffset(by: 0.1) }
                    stepButton("arrow.counterclockwise", help: "Reset") { lyrics.offset = 0 }
                        .disabled(lyrics.offset == 0)
                        .opacity(lyrics.offset == 0 ? 0.4 : 1)
                }
            }

            Card(title: "Translation & romanization", icon: "character.bubble") {
                PillPicker(selection: $settings.subtitleMode,
                           options: SubtitleMode.allCases.map { ($0, $0.title) })
                VStack(alignment: .leading, spacing: 6) {
                    example("별빛 아래서 우리는 춤을 춰")
                    example("夜空に光る ふたりの声")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
                Text("Romanization works offline for Korean, Japanese, Chinese and more. Translation uses Apple's on-device translation into \(Locale.current.localizedString(forLanguageCode: subtitles.targetLanguage.languageCode?.identifier ?? "en") ?? "your language") — download languages in System Settings › General › Language & Region › Translation Languages.")
                    .font(.caption).foregroundStyle(Brand.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = subtitles.lastProblem, settings.subtitleMode == .translation || settings.subtitleMode == .both {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }

            Card(title: "React to the music", icon: "waveform") {
                Row(title: "Beat & bass reactivity",
                    detail: "Glows, stars and particles pulse with the music. Listens to Spotify only — never your screen.") {
                    Toggle("", isOn: $settings.audioReactive).toggleStyle(.switch).labelsHidden()
                }
                if settings.audioReactive {
                    HStack(spacing: 10) {
                        statusPill
                        Spacer()
                        if audio.status == .running { AudioMeter(reactor: audio.reactor) }
                    }
                    if audio.status == .needsPermission {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        } label: {
                            Label("Open Screen & System Audio Recording settings", systemImage: "lock.open")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Brand.gradient))
                        }
                        .buttonStyle(.plain)
                        Text("Turn on Lyricscape there, then come back — it starts listening by itself.")
                            .font(.caption).foregroundStyle(Brand.secondary)
                    }
                }
            }
        }
    }

    private func example(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text).font(.system(size: 13, weight: .semibold))
            Text(subtitles.romanization(of: text) ?? "").font(.caption).foregroundStyle(Brand.pink.opacity(0.9))
        }
    }

    private func stepButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().stroke(Brand.stroke))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var offsetLabel: String {
        if lyrics.offset == 0 { return "In sync" }
        return String(format: "%.1f s %@", abs(lyrics.offset), lyrics.offset > 0 ? "earlier" : "later")
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = switch audio.status {
        case .off: ("Off", Brand.secondary)
        case .needsPermission: ("Needs permission", .orange)
        case .waitingForSpotify: ("Waiting for Spotify", .yellow)
        case .running: ("Listening", .green)
        case .failed(let message): ("Error: \(message)", .red)
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Live bars for loudness, bass and beat.
private struct AudioMeter: View {
    let reactor: AudioReactor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let levels = reactor.levels
            HStack(alignment: .bottom, spacing: 10) {
                bar("Level", levels.level)
                bar("Bass", levels.bass)
                bar("Beat", levels.beat)
            }
        }
    }

    private func bar(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.08)).frame(width: 8, height: 30)
                Capsule().fill(Brand.gradient).frame(width: 8, height: max(3, 30 * value))
            }
            Text(title).font(.system(size: 9)).foregroundStyle(Brand.secondary)
        }
    }
}

// MARK: - General

private struct GeneralSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Overlay", icon: "rectangle.on.rectangle") {
                Row(title: "Show lyrics on screen", detail: "Floats over everything; clicks pass straight through.") {
                    Toggle("", isOn: $settings.overlayVisible).toggleStyle(.switch).labelsHidden()
                }
                Row(title: "Stage mode", detail: "A black stage behind your windows, like a live wallpaper.") {
                    Toggle("", isOn: $settings.stageMode).toggleStyle(.switch).labelsHidden()
                }
            }

            Card(title: "Screen", icon: "display") {
                HStack(spacing: 12) {
                    screenCard(nil, name: "Main display", icon: "menubar.rectangle")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        screenCard(screen.displayID, name: screen.localizedName,
                                   icon: screen.localizedName.localizedCaseInsensitiveContains("built-in") ? "laptopcomputer" : "display")
                    }
                }
            }

            Card(title: "Keyboard shortcuts", icon: "command") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    Row(title: action.title) {
                        ShortcutRecorder(hotKey: Binding(
                            get: { settings.hotKeys[action] ?? HotKey.defaults[action]! },
                            set: { settings.hotKeys[action] = $0 }))
                        .frame(width: 150, height: 26)
                    }
                }
                HStack {
                    Text("Click a shortcut, then press the new keys (with ⌘, ⌥ or ⌃).").font(.caption).foregroundStyle(Brand.secondary)
                    Spacer()
                    Button("Restore defaults") { settings.hotKeys = HotKey.defaults }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Brand.pink)
                }
            }

            Card(title: "Startup", icon: "power") {
                Row(title: "Launch at login", detail: "Start Lyricscape quietly in the menu bar when you log in.") {
                    Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    private func screenCard(_ id: CGDirectDisplayID?, name: String, icon: String) -> some View {
        let selected = settings.displayID == id
        return Button { settings.displayID = id } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 24, weight: .light))
                    .foregroundStyle(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.secondary))
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.07 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.stroke), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About

private struct AboutSection: View {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: Brand.pink.opacity(0.45), radius: 30)
                Text("Lyricscape").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Version \(Self.version)").font(.callout).foregroundStyle(Brand.secondary)
                Text("Live, animated lyrics for whatever's playing in Spotify — written across your screen in time with the music.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.secondary)
                    .frame(maxWidth: 440)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.stroke))

            HStack(spacing: 12) {
                link("Website", icon: "globe", url: Brand.website)
                link("Source on GitHub", icon: "chevron.left.forwardslash.chevron.right", url: Brand.github)
                link("Check for updates", icon: "arrow.down.circle", url: Brand.releases)
            }
            Text("Lyrics from LRCLIB · Made by NIKSHITH G · MIT licence")
                .font(.caption).foregroundStyle(Brand.secondary)
        }
    }

    private func link(_ title: String, icon: String, url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.stroke))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shortcut recorder

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
