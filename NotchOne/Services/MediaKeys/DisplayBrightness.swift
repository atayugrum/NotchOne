import CoreGraphics
import Darwin

/// Built-in display brightness through the private DisplayServices framework.
/// Symbols are looked up at runtime; if they're missing, `isAvailable` is false and
/// brightness keys are left to the system.
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols: @unchecked Sendable {
        let get: GetBrightness
        let set: SetBrightness
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Symbols(
            get: unsafeBitCast(get, to: GetBrightness.self),
            set: unsafeBitCast(set, to: SetBrightness.self)
        )
    }()

    static var isAvailable: Bool { symbols != nil }

    /// The built-in panel, if the lid is open.
    static func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func brightness(of display: CGDirectDisplayID) -> Float? {
        guard let symbols else { return nil }
        var value: Float = 0
        return symbols.get(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func setBrightness(_ value: Float, of display: CGDirectDisplayID) -> Bool {
        guard let symbols else { return false }
        return symbols.set(display, min(1, max(0, value))) == 0
    }
}
