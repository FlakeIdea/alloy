import Carbon.HIToolbox
import AlloyCore

/// A system-wide ⌥⌘M that shows or hides the running game's metrics. Carbon hot keys reach the app while the game
/// is in front and need no Accessibility permission.
@MainActor
final class MetricsHotKey {
    static let display = "⌥⌘M"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isEnabled = false {
        didSet { if isEnabled != oldValue { isEnabled ? register() : unregister() } }
    }

    private func register() {
        if handler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in MetricsHUD.toggle(); return noErr }, 1, &pressed, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4D47_4D54), id: 1)  // "MGMT"
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
