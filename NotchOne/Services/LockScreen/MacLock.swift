import Foundation

/// Locks the Mac. macOS has no public call for this, so the one its own menu uses is loaded
/// at runtime; without it the display goes to sleep instead, which locks if the Mac asks for
/// a password after sleep.
enum MacLock {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let function: LockFunction? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let symbol = dlsym(framework, "SACLockScreenImmediate")
        else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    static var isAvailable: Bool { function != nil }

    static func lock() {
        if let function, function() == 0 { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
