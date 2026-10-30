import Foundation
import Testing
@testable import NotchOne

struct LinkCommandTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func linksCantFakeClaude() {
        let url = URL(string: "notchone://claude?event=needsYou&session=x&project=Bank&message=Enter%20your%20password&pid=1")!
        let command = try! #require(NotchCommand(url: url))
        #expect(LiveActivityLogic.apply(command, to: [], now: now, fromLink: true).isEmpty)
    }

    @Test func theNotchToolCanStillReportClaude() {
        let command = NotchCommand.claude(ClaudeEvent(kind: .needsYou, session: "x", project: "app"))
        #expect(LiveActivityLogic.apply(command, to: [], now: now).first?.status == .needsYou)
    }

    @Test func linkMessagesAreMarked() {
        let items = LiveActivityLogic.apply(.say(text: "Hello"), to: [], now: now, fromLink: true)
        #expect(items.first?.source == .link)
        #expect(items.first?.symbol == "link")
        #expect(items.first?.detail != nil)
    }

    @Test func linksCantTouchTheToolsJobs() {
        let job = LiveActivityLogic.apply(.progress(id: "build", label: "Building", fraction: 0.5), to: [], now: now)
        let after = LiveActivityLogic.apply(.finish(id: "build", label: "Done", success: true, seconds: nil), to: job, now: now, fromLink: true)
        #expect(after.first { $0.id == "job:build" }?.status == .running(fraction: 0.5))
        #expect(after.contains { $0.id == "job:link.build" && $0.source == .link })
    }

    @Test func toolMessagesStayPlain() {
        let items = LiveActivityLogic.apply(.say(text: "Hello"), to: [], now: now)
        #expect(items.first?.source == .message)
        #expect(items.first?.detail == nil)
    }
}

struct UpdateLogicTests {
    @Test func versionsCompareByNumber() {
        #expect(UpdateLogic.isNewer("v2.1.0", than: "2.0.0"))
        #expect(UpdateLogic.isNewer("2.0.10", than: "2.0.9"))
        #expect(UpdateLogic.isNewer("3", than: "2.9.9"))
        #expect(!UpdateLogic.isNewer("2.1", than: "2.1.0"))
        #expect(!UpdateLogic.isNewer("2.0.0", than: "2.1.0"))
        #expect(!UpdateLogic.isNewer("2.1.0-beta", than: "2.0.0"))
        #expect(!UpdateLogic.isNewer("", than: "2.0.0"))
    }

    private func release(tag: String = "v2.1.0", asset: String = "NotchOne-2.1.0.zip",
                         url: String = "https://github.com/a/b/releases/download/v2.1.0/NotchOne-2.1.0.zip",
                         prerelease: Bool = false) -> Data {
        let json: [String: Any] = [
            "tag_name": tag, "draft": false, "prerelease": prerelease,
            "html_url": "https://github.com/a/b/releases/tag/v2.1.0", "body": "Fixes.\nMore fixes.",
            "assets": [["name": "notes.txt", "browser_download_url": "https://x/notes.txt"],
                       ["name": asset, "browser_download_url": url]],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func readsANewerRelease() throws {
        let update = try #require(UpdateLogic.update(fromRelease: release(), current: "2.0.0"))
        #expect(update.version == "2.1.0")
        #expect(update.download.lastPathComponent == "NotchOne-2.1.0.zip")
        #expect(update.notes == "Fixes.More fixes.")
    }

    @Test func skipsOldPreAndInsecureReleases() {
        #expect(UpdateLogic.update(fromRelease: release(), current: "2.1.0") == nil)
        #expect(UpdateLogic.update(fromRelease: release(prerelease: true), current: "2.0.0") == nil)
        #expect(UpdateLogic.update(fromRelease: release(url: "http://evil.example/NotchOne.zip"), current: "2.0.0") == nil)
        #expect(UpdateLogic.update(fromRelease: release(asset: "Other.zip"), current: "2.0.0") == nil)
        #expect(UpdateLogic.update(fromRelease: Data("nope".utf8), current: "2.0.0") == nil)
    }

    @Test func checksAtMostDaily() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateLogic.isDue(lastCheck: nil, now: now))
        #expect(!UpdateLogic.isDue(lastCheck: now - 3600, now: now))
        #expect(UpdateLogic.isDue(lastCheck: now - 25 * 3600, now: now))
        // A clock set back doesn't stop checks for good.
        #expect(UpdateLogic.isDue(lastCheck: now + 3600, now: now))
    }

    @Test func requirementPinsTeamAndApp() {
        #expect(UpdateLogic.requirement.contains("anchor apple generic"))
        #expect(UpdateLogic.requirement.contains(UpdateLogic.teamID))
        #expect(UpdateLogic.requirement.contains("com.atayug.notchone"))
        // Developer ID only: a development-signed build is refused.
        #expect(UpdateLogic.requirement.contains("1.2.840.113635.100.6.1.13"))
    }
}
