import Darwin
import Foundation
import ObjectiveC

/// Keyboard backlight through the private CoreBrightness `KeyboardBrightnessClient`.
/// Loaded at runtime; if the class or a method is missing, or there's no backlit
/// keyboard (lid closed, external keyboard), `isAvailable` is false and the keys go to
/// macOS as before.
@MainActor
enum KeyboardBacklight {
    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private struct Client {
        let object: NSObject
        let copyIDs: CopyIDs
        let get: GetLevel
        let set: SetLevel
    }

    private static let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    private static let client: Client? = {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let object = type.init()
        guard object.responds(to: copySelector), object.responds(to: getSelector), object.responds(to: setSelector),
              let copy = object.method(for: copySelector),
              let get = object.method(for: getSelector),
              let set = object.method(for: setSelector)
        else { return nil }
        return Client(
            object: object,
            copyIDs: unsafeBitCast(copy, to: CopyIDs.self),
            get: unsafeBitCast(get, to: GetLevel.self),
            set: unsafeBitCast(set, to: SetLevel.self)
        )
    }()

    /// Level before the toggle key turned the light off.
    private static var levelBeforeOff: Float = 0.5

    /// The first backlit keyboard, if any.
    static func keyboard() -> UInt64? {
        guard let client,
              let ids = client.copyIDs(client.object, copySelector)?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.first?.uint64Value
    }

    static func level(of keyboard: UInt64) -> Float? {
        guard let client else { return nil }
        let value = client.get(client.object, getSelector, keyboard)
        return value.isFinite ? min(1, max(0, value)) : nil
    }

    @discardableResult
    static func setLevel(_ value: Float, of keyboard: UInt64) -> Bool {
        guard let client else { return false }
        return client.set(client.object, setSelector, min(1, max(0, value)), keyboard)
    }

    /// Toggle key: off, or back to the previous level.
    static func toggledLevel(current: Float) -> Float {
        if current > 0 {
            levelBeforeOff = current
            return 0
        }
        return levelBeforeOff > 0 ? levelBeforeOff : 0.5
    }
}
