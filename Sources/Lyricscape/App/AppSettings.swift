import AppKit
import Observation

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

    /// Theme, font, size, glow, speed, spread, frame.
    var styleSettings: StyleSettings {
        didSet {
            if let data = try? JSONEncoder().encode(styleSettings) { save(data, "styleSettings") }
        }
    }

    /// Called after any setting changes.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        overlayVisible = defaults.bool(forKey: "overlayVisible")
        stageMode = defaults.bool(forKey: "stageMode")
        let id = defaults.integer(forKey: "displayID")
        displayID = id == 0 ? nil : CGDirectDisplayID(id)
        styleID = defaults.string(forKey: "styleID") ?? ConstellationStyle.id
        styleSettings = defaults.data(forKey: "styleSettings")
            .flatMap { try? JSONDecoder().decode(StyleSettings.self, from: $0) } ?? StyleSettings()
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
