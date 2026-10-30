import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut.
struct HotKey: Equatable, Sendable {
    let keyCode: UInt32
    /// Carbon modifier flags (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    let modifiers: UInt32
    let display: String

    static let translate = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥T")
    static let palette = HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥K")
}

/// Global shortcuts through Carbon's `RegisterEventHotKey`: public, works for a
/// background app, and needs no Accessibility permission. Only the registered combos
/// are seen; nothing else typed reaches the app.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4E_54_43_48   // "NTCH"

    /// Returns an id for `unregister`, or nil if the combo is taken by another app.
    @discardableResult
    func register(_ key: HotKey, action: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = action
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        refs.keys.forEach(unregister)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    private func fire(_ id: UInt32) {
        handlers[id]?()
    }
}
