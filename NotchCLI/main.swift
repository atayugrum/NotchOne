import AppKit
import Darwin
import Foundation

// `notch`: shows progress and messages in NotchOne's notch.
// Talks to the app through a distributed notification; does nothing if the app isn't running.

let usage = """
usage: notch run [--label <text>] <command> [args…]   run a command and show its progress
       notch progress <0…1|-> [label]   report progress for a script ("-" = unknown)
       notch done [label]               mark the script's job as finished
       notch fail [label]               mark it as failed
       notch say <text>                 show a short message
options: --id <name>                    job id for progress/done/fail (default: per shell)
"""

func post(_ command: NotchCommand) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(NotchCommand.notificationName),
        object: nil,
        userInfo: command.fields,
        deliverImmediately: true
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

/// Pulls `--id <name>` out of the arguments.
func takeID(_ args: inout [String]) -> String? {
    guard let index = args.firstIndex(of: "--id") else { return nil }
    guard args.indices.contains(index + 1) else { fail("--id needs a value") }
    let id = args[index + 1]
    args.removeSubrange(index...index + 1)
    return id
}

/// Default job id: the calling shell, so `progress` and `done` from one script match.
func defaultID() -> String { "sh-\(getppid())" }

// MARK: - run

func run(_ arguments: [String]) -> Never {
    // Only the program's name shows, unless you pick a label: the full command can hold secrets.
    var arguments = arguments
    var chosen: String?
    if arguments.first == "--label", arguments.count >= 2 {
        chosen = arguments[1]
        arguments.removeFirst(2)
    }
    guard let program = arguments.first else { fail(usage) }
    let id = "run-\(getpid())"
    let label = NotchCommand.clean(chosen ?? URL(fileURLWithPath: program).lastPathComponent, max: NotchCommand.maxText)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let start = Date()
    do {
        try process.run()
    } catch {
        fail("notch: couldn't run \(arguments[0]): \(error.localizedDescription)")
    }
    post(.progress(id: id, label: label, fraction: nil))

    // Ctrl-C: let the child handle it, then report how it ended.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let child = process.processIdentifier
    let sources = [SIGINT, SIGTERM].map { sig in
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { kill(child, sig) }
        source.resume()
        return source
    }

    process.waitUntilExit()
    sources.forEach { $0.cancel() }
    let seconds = Date().timeIntervalSince(start)
    let code: Int32 = process.terminationReason == .uncaughtSignal
        ? 128 + process.terminationStatus
        : process.terminationStatus
    post(.finish(id: id, label: label, success: code == 0, seconds: seconds))
    exit(code)
}

// MARK: - main

var args = Array(CommandLine.arguments.dropFirst())
guard let verb = args.first else { fail(usage) }
args.removeFirst()

switch verb {
case "run":
    run(args)
case "progress":
    let id = takeID(&args) ?? defaultID()
    guard let value = args.first else { fail("usage: notch progress <0…1|-> [label]") }
    let fraction: Double?
    if value == "-" {
        fraction = nil
    } else if let number = Double(value) {
        fraction = number
    } else {
        fail("notch: progress must be a number from 0 to 1, or -")
    }
    post(.progress(id: id, label: args.dropFirst().joined(separator: " "), fraction: fraction))
case "done", "fail":
    let id = takeID(&args) ?? defaultID()
    post(.finish(id: id, label: args.joined(separator: " "), success: verb == "done", seconds: nil))
case "say":
    guard !args.isEmpty else { fail("usage: notch say <text>") }
    post(.say(text: args.joined(separator: " ")))
case "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
