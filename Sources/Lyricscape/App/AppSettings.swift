import AppKit
import Observation
import OSLog
import ServiceManagement

/// A saved look: style plus all its settings.
struct StylePreset: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var styleID: String
    var settings: StyleSettings
}

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class AppSettings {
    var overlayVisible: Bool {
        didSet { save(overlayVisible, "overlayVisible") }
    }

    /// Solid black background instead of a transparent overlay.
    var stageMode: Bool {
        didSet { save(stageMode, "stageMode") }
    }

    /// Display to show the overlay on; nil = the main display (the one with the menu bar).
    var displayID: CGDirectDisplayID? {
        didSet { save(Int(displayID ?? 0), "displayID") }
    }

    var styleID: String {
        didSet { save(styleID, "styleID") }
    }

    /// Theme, font, size, glow, speed, spread, frame, opacity, position.
    var styleSettings: StyleSettings {
        didSet { saveJSON(styleSettings, "styleSettings") }
    }

    /// Drive visuals from Spotify's audio (needs Screen Recording permission).
    var audioReactive: Bool {
        didSet { save(audioReactive, "audioReactive") }
    }

    var subtitleMode: SubtitleMode {
        didSet { save(subtitleMode.rawValue, "subtitleMode") }
    }

    var hotKeys: [HotKeyAction: HotKey] {
        didSet { saveJSON(hotKeys, "hotKeys") }
    }

    var presets: [StylePreset] {
        didSet { saveJSON(presets, "presets") }
    }

    /// Called after any setting changes.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        func decode<T: Decodable>(_ key: String, as: T.Type) -> T? {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
        overlayVisible = defaults.bool(forKey: "overlayVisible")
        stageMode = defaults.bool(forKey: "stageMode")
        let id = defaults.integer(forKey: "displayID")
        displayID = id == 0 ? nil : CGDirectDisplayID(id)
        styleID = defaults.string(forKey: "styleID") ?? ConstellationStyle.id
        styleSettings = decode("styleSettings", as: StyleSettings.self) ?? StyleSettings()
        audioReactive = defaults.bool(forKey: "audioReactive")
        subtitleMode = defaults.string(forKey: "subtitleMode").flatMap(SubtitleMode.init) ?? .off
        hotKeys = HotKey.defaults.merging(decode("hotKeys", as: [HotKeyAction: HotKey].self) ?? [:]) { $1 }
        presets = decode("presets", as: [StylePreset].self) ?? []
    }

    // MARK: - Styles & presets

    func cycleStyle() {
        let ids = StyleRegistry.ids
        let index = ids.firstIndex(of: styleID) ?? 0
        styleID = ids[(index + 1) % ids.count]
    }

    func savePreset(named name: String) {
        presets.append(StylePreset(name: name, styleID: styleID, settings: styleSettings))
    }

    func apply(_ preset: StylePreset) {
        styleID = preset.styleID
        styleSettings = preset.settings
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Logger.app.error("Launch at login: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Persistence

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }

    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { save(data, key) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
