import AppKit
import Darwin

/// A private window space that macOS draws above the lock screen, through the SkyLight
/// framework. Loaded at runtime: if a symbol is missing, `make()` returns nil and the
/// lock screen widget stays off. Experimental.
@MainActor
final class SkyLightSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceDestroy = @convention(c) (Int32, Int32) -> Int32
    private typealias SetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias HideSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private struct Symbols {
        let connection: MainConnection
        let create: SpaceCreate
        let destroy: SpaceDestroy
        let setLevel: SetAbsoluteLevel
        let show: ShowSpaces
        let hide: HideSpaces
        let addWindows: AddWindows
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let connection = load("SLSMainConnectionID", as: MainConnection.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let destroy = load("SLSSpaceDestroy", as: SpaceDestroy.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", as: SetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", as: ShowSpaces.self),
              let hide = load("SLSHideSpaces", as: HideSpaces.self),
              let addWindows = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self)
        else { return nil }
        return Symbols(
            connection: connection, create: create, destroy: destroy, setLevel: setLevel,
            show: show, hide: hide, addWindows: addWindows
        )
    }()

    static var isAvailable: Bool { symbols != nil }

    /// The level macOS keeps for what shows over the lock screen.
    private static let lockScreenLevel: Int32 = 400

    private let symbols: Symbols
    private let connection: Int32
    private let space: Int32

    private init?(symbols: Symbols) {
        self.symbols = symbols
        connection = symbols.connection()
        space = symbols.create(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = symbols.setLevel(connection, space, Self.lockScreenLevel)
        _ = symbols.show(connection, [space] as CFArray)
    }

    static func make() -> SkyLightSpace? {
        symbols.flatMap { SkyLightSpace(symbols: $0) }
    }

    /// Moves a window into this space (out of its normal spaces).
    func add(_ window: NSWindow) {
        _ = symbols.addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }

    /// Hides and destroys the space. The windows in it should be closed first.
    func destroy() {
        _ = symbols.hide(connection, [space] as CFArray)
        _ = symbols.destroy(connection, space)
    }
}
