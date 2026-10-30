import Foundation

/// Runs `SystemNowPlaying.js` in `/usr/bin/osascript` and reports each line it prints.
/// Restarts the helper if it dies, but gives up after repeated crashes so a broken
/// macOS update can't cause a restart loop.
@MainActor
final class SystemNowPlayingMonitor {
    var onLine: ((SystemLine) -> Void)?

    private var process: Process?
    private var isStopped = true
    private var recentRestarts: [Date] = []
    private static let maxRestartsPerMinute = 3

    func start() {
        isStopped = false
        launch()
    }

    func stop() {
        isStopped = true
        guard let process else { return }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
    }

    private func launch() {
        guard !isStopped, process == nil,
              let script = Bundle.main.url(forResource: "SystemNowPlaying", withExtension: "js") else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path, String(ProcessInfo.processInfo.processIdentifier)]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        let reader = LineReader { [weak self] line in
            Task { @MainActor in self?.onLine?(line) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.helperExited() }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func helperExited() {
        process = nil
        guard !isStopped else { return }
        onLine?(.nothingPlaying)

        let now = Date()
        recentRestarts = recentRestarts.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentRestarts.count <= Self.maxRestartsPerMinute else { return }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.launch()
        }
    }
}

/// Collects stdout bytes from the helper's pipe (on a background queue) into lines.
private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let deliver: @Sendable (SystemLine) -> Void

    init(deliver: @escaping @Sendable (SystemLine) -> Void) {
        self.deliver = deliver
    }

    func append(_ data: Data) {
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            let split = SystemNowPlayingParser.splitLines(buffer)
            buffer = split.rest
            return split.lines
        }
        for line in lines {
            if let parsed = SystemNowPlayingParser.parse(line: line) { deliver(parsed) }
        }
    }
}
