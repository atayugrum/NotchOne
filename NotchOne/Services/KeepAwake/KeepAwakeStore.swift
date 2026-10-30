import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac and its display awake with a power assertion, the same thing `caffeinate`
/// uses. macOS drops it when the app quits, so nothing can get stuck on.
@MainActor
@Observable
final class KeepAwakeStore {
    private(set) var isOn = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0

    func toggle() {
        isOn ? turnOff() : turnOn()
    }

    private func turnOn() {
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NotchOne: Keep Awake" as CFString,
            &assertion
        )
        isOn = status == kIOReturnSuccess
    }

    private func turnOff() {
        IOPMAssertionRelease(assertion)
        assertion = 0
        isOn = false
    }
}
