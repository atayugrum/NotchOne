import Foundation
import Testing
@testable import NotchOne

struct NotchCommandTests {

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

struct LiveStyleTests {
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

struct NotificationBannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readsTheAppFromTheDescription() {
        let banner = NotificationBannerLogic.banner(id: "A", description: "Mail, Ada, Lunch?, See you at one", title: "Ada", subtitle: "Lunch?", body: "See you at one")
        #expect(banner == NotificationBanner(id: "A", app: "Mail", title: "Ada: Lunch?", body: "See you at one"))
    }

    @Test func keepsANotificationWithOnlyABody() {
        let banner = NotificationBannerLogic.banner(id: "B", description: "Reminders, Call back", title: nil, subtitle: nil, body: "Call back")
        #expect(banner?.title == "Reminders")
        #expect(NotificationBannerLogic.banner(id: "C", description: "Mail", title: "", subtitle: nil, body: nil) == nil)
        #expect(NotificationBannerLogic.banner(id: "", description: "Mail", title: "Hi", subtitle: nil, body: nil) == nil)
    }

    @Test func closeIsTheLastNamedAction() {
        let actions = ["AXPress", "Name:Show Details\nTarget:0x0", "Name:Show\nTarget:0x0", "Name:Close\nTarget:0x0"]
        #expect(NotificationBannerLogic.closeAction(in: actions) == actions[3])
        #expect(NotificationBannerLogic.closeAction(in: ["AXPress"]) == nil)
    }

    @Test func showsBrieflyAndOpensItsApp() throws {
        let banner = NotificationBanner(id: "A", app: "Mail", title: "Ada", body: "")
        let list = LiveActivityLogic.apply(banner, appPID: 42, appBundleID: "com.apple.mail", to: [], now: now)
        let item = try #require(list.first)
        #expect(item.source == .notification)
        #expect(item.detail == "Mail")
        #expect(item.appPID == 42)
        #expect(item.expiresAt == now + NotificationBannerLogic.lifetime)
        #expect(item.priority > ActivityState.nowPlayingPriority)
    }
}

struct EarTuckTests {
    private let notch = CGRect(x: 645, y: 924, width: 180, height: 32)

    @Test func theMenuBarBesideTheEarsTucksThem() {
        #expect(EarLayout.pointerNearEars(CGPoint(x: 885, y: 940), notchRect: notch, earWidth: 34))
        #expect(EarLayout.pointerNearEars(CGPoint(x: 580, y: 940), notchRect: notch, earWidth: 34))
    }

    @Test func thePointerIsOnAnEarBesideOrBelowTheNotch() {
        #expect(EarLayout.pointerOnEar(CGPoint(x: 850, y: 940), notchRect: notch))
        #expect(EarLayout.pointerOnEar(CGPoint(x: 735, y: 900), notchRect: notch))
        #expect(!EarLayout.pointerOnEar(CGPoint(x: 735, y: 940), notchRect: notch))
    }

    @Test func theNotchAndTheRestOfTheScreenDoNot() {
        #expect(!EarLayout.pointerNearEars(CGPoint(x: 735, y: 940), notchRect: notch, earWidth: 34))
        #expect(!EarLayout.pointerNearEars(CGPoint(x: 830, y: 940), notchRect: notch, earWidth: 34))
        // On the ear itself: it stays, so it can be clicked.
        #expect(!EarLayout.pointerNearEars(CGPoint(x: 850, y: 940), notchRect: notch, earWidth: 34))
        #expect(!EarLayout.pointerNearEars(CGPoint(x: 850, y: 800), notchRect: notch, earWidth: 34))
        #expect(!EarLayout.pointerNearEars(CGPoint(x: 1200, y: 940), notchRect: notch, earWidth: 34))
    }

    @Test func staysTuckedAlongTheMenuBar() {
        #expect(EarLayout.pointerOnMenuBar(CGPoint(x: 1200, y: 940), notchRect: notch))
        #expect(!EarLayout.pointerOnMenuBar(CGPoint(x: 850, y: 800), notchRect: notch))
    }

    @Test func onlyLongLastingEarsTuck() {
        #expect(EarLayout.canTuck(.nowPlaying))
        #expect(!EarLayout.canTuck(.peek(.focus(on: true))))
        #expect(!EarLayout.canTuck(nil))
        let note = LiveActivity(id: "n", source: .notification, title: "t", status: .info, startedAt: .now)
        #expect(!EarLayout.canTuck(.live(note)))
    }
}

struct NotificationHistoryTests {
    private func record(_ id: String) -> NotificationRecord {
        NotificationRecord(id: id, banner: NotificationBanner(id: id, app: "Mail", title: "T", body: ""), date: .now, appPID: nil, appBundleID: nil)
    }

    @Test func newestComesFirstAndRepeatsDont() {
        let history = NotificationBannerLogic.adding(record("b"), to: [record("a")])
        #expect(history.map(\.id) == ["b", "a"])
        #expect(NotificationBannerLogic.adding(record("a"), to: history).map(\.id) == ["a", "b"])
    }

    @Test func keepsALimit() {
        let full = (0..<NotificationBannerLogic.historyLimit).map { record("\($0)") }
        let history = NotificationBannerLogic.adding(record("new"), to: full)
        #expect(history.count == NotificationBannerLogic.historyLimit)
        #expect(history.first?.id == "new")
    }

    @Test func aNotificationReachesBelowTheNotchAndOthersDont() {
        let note = LiveActivity(id: "n", source: .notification, title: "t", status: .info, startedAt: .now)
        #expect(EarLayout.drop(for: .live(note)) == EarLayout.notificationDrop)
        #expect(EarLayout.drop(for: .nowPlaying) == 0)
        #expect(ScreenGeometry.hoverRect(notchRect: .init(x: 0, y: 100, width: 100, height: 32), isOpen: false, panelFrame: .zero, earDrop: 60).minY == 34)
    }
}

struct BannerHidingTests {
    @Test func onlyAFreshClickOnTheMenuBarKeepsTheBanner() {
        #expect(NotificationBannerLogic.openedNotificationCenter(secondsSinceClick: 0.3, pointerBelowTop: 10))
        #expect(!NotificationBannerLogic.openedNotificationCenter(secondsSinceClick: 0.3, pointerBelowTop: 300))
        #expect(!NotificationBannerLogic.openedNotificationCenter(secondsSinceClick: 5, pointerBelowTop: 10))
    }
}
