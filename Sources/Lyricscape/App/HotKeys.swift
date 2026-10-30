import Carbon
import OSLog

/// A global keyboard shortcut, e.g. ⌃⌥⌘L.
struct HotKey: Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32

    static let toggleOverlay = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let toggleStage = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey))

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keyNames[Int(keyCode)] ?? "?")
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_L: "L", kVK_ANSI_S: "S", kVK_ANSI_N: "N",
    ]
}

/// Registers system-wide shortcuts via Carbon's RegisterEventHotKey, which works
/// without Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ hotKey: HotKey, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers,
                                         EventHotKeyID(signature: OSType(0x4C59_5243), id: id), // 'LYRC'
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Logger.app.error("Couldn't register shortcut \(hotKey.displayString, privacy: .public) (OSStatus \(status, privacy: .public)) — another app may be using it")
            return
        }
        refs[id] = ref
        actions[id] = action
    }
}
