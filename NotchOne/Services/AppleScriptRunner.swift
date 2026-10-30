import Foundation

/// Runs AppleScript off the main thread. `NSAppleScript` is not thread-safe, so every
/// script runs on one serial queue, and results are parsed into `Sendable` values there.
final class AppleScriptRunner: @unchecked Sendable {
    enum ScriptError: Error, Equatable {
        /// The user denied Automation access (errAEEventNotPermitted).
        case notPermitted
        case appNotRunning
        case compileFailed
        case failed(code: Int, message: String)
    }

    private let queue = DispatchQueue(label: "com.atayug.notchone.applescript", qos: .userInitiated)
    /// Compiled scripts by source. Only touched on `queue`.
    private var cache: [String: NSAppleScript] = [:]

    func run<T: Sendable>(
        _ source: String,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let script = self.script(for: source) else {
                    continuation.resume(throwing: ScriptError.compileFailed)
                    return
                }
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
                    continuation.resume(throwing: Self.error(code: code, message: message))
                    return
                }
                continuation.resume(returning: parse(result))
            }
        }
    }

    static func error(code: Int, message: String) -> ScriptError {
        switch code {
        case -1743: .notPermitted
        case -600, -609: .appNotRunning
        default: .failed(code: code, message: message)
        }
    }

    private func script(for source: String) -> NSAppleScript? {
        if let cached = cache[source] { return cached }
        guard let script = NSAppleScript(source: source) else { return nil }
        cache[source] = script
        return script
    }
}
