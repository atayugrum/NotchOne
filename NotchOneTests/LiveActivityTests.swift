import Foundation
import Testing
@testable import NotchOne

struct NotchCommandTests {
    @Test func fieldsRoundTrip() {
        let commands: [NotchCommand] = [
            .progress(id: "build", label: "Building", fraction: 0.4),
            .progress(id: "x", label: "", fraction: nil),
            .finish(id: "build", label: "Built", success: false, seconds: 12),
            .say(text: "Deploy finished"),
            .claude(ClaudeEvent(kind: .needsYou, session: "abc", project: "NotchOne", message: "Allow Bash?", appPID: 42)),
        ]
        for command in commands {
            #expect(NotchCommand(fields: command.fields) == command)
        }
    }

    @Test func unknownOrIncompleteInputIsIgnored() {
        #expect(NotchCommand(fields: ["cmd": "rm -rf"]) == nil)
        #expect(NotchCommand(fields: ["cmd": "progress"]) == nil)            // no id
        #expect(NotchCommand(fields: ["cmd": "say", "text": "   "]) == nil)
        #expect(NotchCommand(fields: ["cmd": "claude", "event": "boom", "session": "a"]) == nil)
    }

    @Test func inputIsCleanedAndCapped() {
        let long = String(repeating: "a", count: 500)
        guard case .say(let text)? = NotchCommand(fields: ["cmd": "say", "text": "hi\u{7}\n" + long]) else {
            Issue.record("not decoded")
            return
        }
        #expect(text.count == NotchCommand.maxText)
        #expect(!text.contains("\n") && !text.contains("\u{7}"))

        guard case .progress(_, _, let fraction)? = NotchCommand(fields: ["cmd": "progress", "id": "a", "fraction": "7"]) else {
            Issue.record("not decoded")
            return
        }
        #expect(fraction == 1)
        #expect(NotchCommand(fields: ["cmd": "progress", "id": "a", "fraction": "nan"]) == .progress(id: "a", label: "", fraction: nil))
    }

    @Test func urlsDecode() throws {
        let url = try #require(URL(string: "notchone://progress?id=up&label=Uploading%20files&fraction=0.25"))
        #expect(NotchCommand(url: url) == .progress(id: "up", label: "Uploading files", fraction: 0.25))
        #expect(NotchCommand(url: try #require(URL(string: "https://say?text=hi"))) == nil)
        // The query can't override the command chosen by the host.
        #expect(NotchCommand(url: try #require(URL(string: "notchone://say?cmd=progress&text=hi"))) == .say(text: "hi"))
    }
}

struct LiveActivityLogicTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func jobRunsThenFinishesWithDurationAndExpires() {
        var list = LiveActivityLogic.apply(.progress(id: "b", label: "make", fraction: nil), to: [], now: t0)
        list = LiveActivityLogic.apply(.progress(id: "b", label: "", fraction: 0.5), to: list, now: t0 + 2)
        #expect(list.count == 1)
        #expect(list[0].title == "make")
        #expect(list[0].status == .running(fraction: 0.5))

        list = LiveActivityLogic.apply(.finish(id: "b", label: "", success: true, seconds: nil), to: list, now: t0 + 5)
        #expect(list[0].status == .succeeded)
        #expect(list[0].title == "make")
        #expect(list[0].duration == 5)
        #expect(LiveActivityLogic.prune(list, now: t0 + 5 + LiveActivityLogic.finishedLifetime + 1).isEmpty)
    }

    @Test func finishUsesReportedSeconds() {
        let list = LiveActivityLogic.apply(.finish(id: "r", label: "sleep 5", success: false, seconds: 5), to: [], now: t0)
        #expect(list[0].status == .failed)
        #expect(list[0].duration == 5)
    }

    @Test func claudeSessionMovesThroughStates() {
        func event(_ kind: ClaudeEventKind) -> NotchCommand {
            .claude(ClaudeEvent(kind: kind, session: "s1", project: "NotchOne", message: "Allow?", appPID: 9))
        }
        // Working shows nothing.
        var list = LiveActivityLogic.apply(event(.started), to: [], now: t0)
        #expect(list.isEmpty)

        list = LiveActivityLogic.apply(event(.needsYou), to: list, now: t0 + 10)
        #expect(list[0].status == .needsYou)
        #expect(list[0].title == "Claude needs you")
        #expect(list[0].detail == "NotchOne: Allow?")
        #expect(list[0].priority > ActivityState.nowPlayingPriority)

        // Answering it (Claude starts again) clears it.
        #expect(LiveActivityLogic.apply(event(.started), to: list, now: t0 + 20).isEmpty)

        list = LiveActivityLogic.apply(event(.finished), to: list, now: t0 + 30)
        #expect(list.count == 1)
        #expect(list[0].status == .succeeded)
        #expect(list[0].title == "Claude finished")
        #expect(list[0].detail == "NotchOne")
        #expect(list[0].appPID == 9)
    }

    @Test func topPicksHighestPriorityThenNewest() {
        var list = LiveActivityLogic.apply(.progress(id: "a", label: "a", fraction: nil), to: [], now: t0)
        list = LiveActivityLogic.apply(.progress(id: "b", label: "b", fraction: nil), to: list, now: t0 + 1)
        #expect(LiveActivityLogic.top(list)?.id == "job:b")
        list = LiveActivityLogic.apply(.claude(ClaudeEvent(kind: .needsYou, session: "s", project: "p")), to: list, now: t0 + 2)
        #expect(LiveActivityLogic.top(list)?.id == "claude:s")
    }

    @Test func listIsCapped() {
        var list: [LiveActivity] = []
        for index in 0..<20 {
            list = LiveActivityLogic.apply(.progress(id: "\(index)", label: "j", fraction: nil), to: list, now: t0 + Double(index))
        }
        #expect(list.count == LiveActivityLogic.maxCount)
        #expect(list.contains { $0.id == "job:19" })
        #expect(!list.contains { $0.id == "job:0" })
    }
}

struct ClaudeIntegrationTests {
    let cli = "/Users/me/.local/bin/notch"

    @Test func installAddsHooksAndKeepsEverythingElse() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let installed = ClaudeHooks.install(into: existing, cliPath: cli)
        #expect(installed["model"] as? String == "opus")
        #expect(ClaudeHooks.isInstalled(in: installed))
        let stop = (installed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2)

        // Installing twice doesn't duplicate.
        let twice = ClaudeHooks.install(into: installed, cliPath: cli)
        #expect(((twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 2)
    }

    @Test func removeTakesOnlyOurs() {
        let existing: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let removed = ClaudeHooks.remove(from: ClaudeHooks.install(into: existing, cliPath: cli))
        let hooks = removed["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == ["Stop"])
        #expect(!ClaudeHooks.isInstalled(in: removed))

        let clean = ClaudeHooks.remove(from: ClaudeHooks.install(into: [:], cliPath: cli))
        #expect(clean["hooks"] == nil)
    }

    @Test func durationFormatting() {
        #expect(LiveStyle.duration(5) == "5s")
        #expect(LiveStyle.duration(64) == "1m 4s")
    }
}

struct CommandLineToolTests {
    @Test func relinksOnlyToolsWhoseAppIsGone() {
        let other = "/Users/me/build/NotchOne.app/Contents/Helpers/notch"
        #expect(CommandLineTool.needsRelink(destination: other, destinationExists: false))
        #expect(!CommandLineTool.needsRelink(destination: other, destinationExists: true))
        // Someone else's tool that happens to be called notch.
        #expect(!CommandLineTool.needsRelink(destination: "/opt/homebrew/bin/notch", destinationExists: false))
    }

    @Test func onlyTheNotchOneSchemeIsAccepted() throws {
        #expect(NotchCommand(url: try #require(URL(string: "notchone://say?text=hi"))) == .say(text: "hi"))
        #expect(NotchCommand(url: try #require(URL(string: "notchy://say?text=hi"))) == nil)
    }
}
