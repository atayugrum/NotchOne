import Foundation
import Testing
@testable import NotchOne

struct OnboardingLogicTests {
    @Test func firstLaunchShowsEveryStep() {
        #expect(OnboardingLogic.steps(seenVersion: 0) == OnboardingStep.allCases)
    }

    @Test func seenTourShowsNothing() {
        #expect(OnboardingLogic.steps(seenVersion: OnboardingLogic.currentVersion).isEmpty)
    }

    @Test func everyStepBelongsToAShippedVersion() {
        #expect(OnboardingStep.allCases.allSatisfy { (1...OnboardingLogic.currentVersion).contains($0.since) })
    }

    @Test func pendingStepsReadTheSavedVersion() {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(OnboardingLogic.pendingSteps(defaults).count == OnboardingStep.allCases.count)
        OnboardingLogic.markSeen(defaults)
        #expect(OnboardingLogic.pendingSteps(defaults).isEmpty)
    }

    @Test func turningOnMirrorUnhidesOnlyMirror() {
        #expect(AppearanceLogic.showing(.mirror, hidden: "mirror") == "")
        #expect(AppearanceLogic.showing(.mirror, hidden: "clipboard,mirror,timer") == "clipboard,timer")
        #expect(AppearanceLogic.showing(.mirror, hidden: "timer") == "timer")
    }
}

@MainActor
struct TourInNotchTests {
    private func makeModel(mode: NotchMode = .full) -> (NotchViewModel, UserDefaults, String) {
        let metrics = NotchMetrics(notchRect: CGRect(x: 865, y: 1050, width: 190, height: 30), hasHardwareNotch: false)
        let model = NotchViewModel(activity: ActivityState(), metrics: metrics, panelFrame: CGRect(x: 576, y: 600, width: 768, height: 480))
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(NotchOutline.pill.rawValue, forKey: SettingsKey.notchOutline)
        defaults.set(mode.rawValue, forKey: SettingsKey.notchMode)
        model.applySettings(defaults)
        model.tourDefaults = defaults
        return (model, defaults, name)
    }

    @Test func tourOpensAndStaysOpen() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.startTour()
        #expect(model.isOpen)
        #expect(model.tourStep == .welcome)
        #expect(model.isPinnedOpen)
        model.release()
        #expect(model.isPinnedOpen)
    }

    @Test func tourUsesTheFullNotchInCompactMode() {
        let (model, defaults, name) = makeModel(mode: .compact)
        defer { defaults.removePersistentDomain(forName: name) }
        model.open()
        #expect(model.showsCompact)
        model.startTour()
        #expect(!model.showsCompact)
        #expect(model.openSize == NotchLayout.tourSize(base: model.baseOpenSize))
    }

    @Test func stepsMoveAndTheLastOneFinishes() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.startTour([.welcome, .done])
        model.previousTourStep()
        #expect(model.tourStep == .welcome)
        model.nextTourStep()
        #expect(model.tourStep == .done)
        #expect(defaults.integer(forKey: SettingsKey.onboardingVersion) == 0)
        model.nextTourStep()
        #expect(model.tourStep == nil)
        #expect(defaults.integer(forKey: SettingsKey.onboardingVersion) == OnboardingLogic.currentVersion)
    }

    @Test func closingSkipsTheTour() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.startTour()
        model.close()
        #expect(model.tourStep == nil)
        #expect(defaults.integer(forKey: SettingsKey.onboardingVersion) == OnboardingLogic.currentVersion)
    }

    @Test func tourReplacesSettings() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.openSettings(.about)
        model.startTour()
        #expect(model.settingsPage == nil)
        #expect(model.tourStep == .welcome)
    }
}

struct PermissionGateTests {
    @Test func nothingIsRequestedOnAFreshInstall() {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(PermissionGate.requested(defaults).isEmpty)
        // Folders can't be checked without touching them, so they wait for the button.
        #expect(!PermissionGate.allows(.folders, defaults))
    }

    @Test func aButtonPressIsRemembered() {
        let name = "notchone-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        PermissionGate.markRequested(.folders, defaults)
        PermissionGate.markRequested(.bluetooth, defaults)
        PermissionGate.markRequested(.folders, defaults)
        #expect(PermissionGate.requested(defaults) == [.folders, .bluetooth])
        #expect(defaults.string(forKey: PermissionGate.key) == "bluetooth,folders")
        #expect(PermissionGate.allows(.folders, defaults))
    }

    @Test func earlierUsersSeeOnlyTheNewPermissionsStep() {
        #expect(OnboardingLogic.steps(seenVersion: 1) == [.permissions])
    }
}

@MainActor
struct NotchLevelTests {
    @Test func theOpenNotchStaysBehindSystemSettings() {
        #expect(SystemPromptWatcher.level(promptShowing: false, settingsInFront: true, notchOpen: true) == .normal)
        #expect(SystemPromptWatcher.level(promptShowing: true, settingsInFront: true, notchOpen: true) == .normal)
    }

    @Test func theClosedNotchKeepsItsPlaceAboveSystemSettings() {
        #expect(SystemPromptWatcher.level(promptShowing: false, settingsInFront: true, notchOpen: false) == SystemPromptWatcher.normalLevel)
    }

    @Test func promptsStillComeFirstEverywhereElse() {
        #expect(SystemPromptWatcher.level(promptShowing: true, settingsInFront: false, notchOpen: true) == SystemPromptWatcher.belowPrompts)
        #expect(SystemPromptWatcher.level(promptShowing: false, settingsInFront: false, notchOpen: true) == SystemPromptWatcher.normalLevel)
    }
}

@MainActor
struct PromptDetectionTests {
    @Test func theLocationPromptCounts() {
        #expect(SystemPromptWatcher.isPrompt(owner: "CoreLocationAgent"))
        #expect(SystemPromptWatcher.isPrompt(owner: "UserNotificationCenter"))
        #expect(!SystemPromptWatcher.isPrompt(owner: "Dock"))
    }

    @Test func promptsBeatTheLoweredNotch() {
        // Levels measured on macOS 26: 8 for most prompts, 25 for location.
        #expect(SystemPromptWatcher.belowPrompts.rawValue < 8)
        #expect(SystemPromptWatcher.normalLevel.rawValue > 25)
    }
}
