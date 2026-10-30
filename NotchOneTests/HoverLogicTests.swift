import Testing
@testable import NotchOne

struct HoverLogicTests {
    @Test func enteringClosedNotchSchedulesOpen() {
        #expect(HoverLogic.decide(state: .closed, isInside: true, pending: nil) == .scheduleOpen)
    }

    @Test func openIsNotRescheduledWhileAlreadyPending() {
        #expect(HoverLogic.decide(state: .closed, isInside: true, pending: .scheduleOpen) == HoverDecision.none)
    }

    @Test func leavingBeforeOpenDelayCancelsIt() {
        #expect(HoverLogic.decide(state: .closed, isInside: false, pending: .scheduleOpen) == .cancelPending)
    }

    @Test func leavingOpenNotchSchedulesClose() {
        #expect(HoverLogic.decide(state: .open, isInside: false, pending: nil) == .scheduleClose)
    }

    @Test func comingBackCancelsClose() {
        #expect(HoverLogic.decide(state: .open, isInside: true, pending: .scheduleClose) == .cancelPending)
    }

    @Test func steadyStatesDoNothing() {
        #expect(HoverLogic.decide(state: .open, isInside: true, pending: nil) == HoverDecision.none)
        #expect(HoverLogic.decide(state: .closed, isInside: false, pending: nil) == HoverDecision.none)
    }
}
