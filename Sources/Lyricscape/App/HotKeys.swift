import AppKit
import Carbon
import OSLog

enum HotKeyAction: String, Codable, CaseIterable, Sendable {
    case toggleOverlay, toggleStage, nextStyle

    var title: String {
        switch self {
        case .toggleOverlay: "Show / hide lyrics"
        case .toggleStage: "Stage mode"
        case .nextStyle: "Next style"
        }
    }
}

/// A global keyboard shortcut, e.g. ⌃⌥⌘L.
struct HotKey: Codable, Equatable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32
    /// The key's label, e.g. "L".
    var keyName: String

    static let defaults: [HotKeyAction: HotKey] = [
        .toggleOverlay: HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | cmdKey), keyName: "L"),
        .toggleStage: HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), keyName: "S"),
        .nextStyle: HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey | cmdKey), keyName: "N"),
    ]

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    /// From a key press in the shortcut recorder. Needs at least one of ⌘ ⌥ ⌃.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        let name = Self.specialKeys[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespaces)
        guard let name, !name.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, keyName: name)
    }

    init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
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

    /// Replaces all registered shortcuts.
    func registerAll(_ hotKeys: [HotKeyAction: HotKey], handler: @escaping (HotKeyAction) -> Void) {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        for (action, hotKey) in hotKeys {
            register(hotKey) { handler(action) }
        }
    }

    private func register(_ hotKey: HotKey, action: @escaping () -> Void) {
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
