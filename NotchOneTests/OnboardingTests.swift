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

    @Test func tourOpensButCanBeClosed() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.startTour()
        #expect(model.isOpen)
        #expect(model.tourStep == .welcome)
        #expect(model.isPinnedOpen)
        model.release()
        #expect(!model.isPinnedOpen)
        model.close()
        #expect(model.tourStep == .welcome)
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

    @Test func closingKeepsTheTourForNextTime() {
        let (model, defaults, name) = makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.startTour()
        model.nextTourStep()
        let step = model.tourStep
        model.close()
        model.open()
        #expect(model.tourStep == step)
        #expect(defaults.integer(forKey: SettingsKey.onboardingVersion) == 0)
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
    private func stepsAside(prompt: Int? = nil, settings: Bool = false, flow: Bool = false, open: Bool = true) -> Bool {
        SystemPromptWatcher.stepsAside(promptLevel: prompt, settingsInFront: settings, inPermissionFlow: flow, notchOpen: open)
    }

    @Test func theNotchStaysAboveAppsAtEveryPromptLevel() {
        #expect(SystemPromptWatcher.level(promptLevel: nil) == SystemPromptWatcher.normalLevel)
        #expect(SystemPromptWatcher.level(promptLevel: 0) == SystemPromptWatcher.normalLevel)
        #expect(SystemPromptWatcher.level(promptLevel: 8) == SystemPromptWatcher.belowPrompts)
        #expect(SystemPromptWatcher.level(promptLevel: 25) == SystemPromptWatcher.belowPrompts)
    }

    @Test func theOpenNotchStepsAsideForTheAccessibilityPrompt() {
        #expect(stepsAside(prompt: 0, flow: true))
        #expect(!stepsAside(prompt: 0, flow: true, open: false))
        #expect(!stepsAside(prompt: 8, flow: true))
    }

    @Test func aWindowAlreadyOnScreenNeverHidesTheNotch() {
        #expect(!stepsAside(prompt: 0))
    }

    @Test func settingsOnlyMoveTheNotchDuringAPermissionFlow() {
        #expect(stepsAside(settings: true, flow: true))
        #expect(!stepsAside(settings: true))
        #expect(!stepsAside(settings: true, flow: true, open: false))
    }
}

@MainActor
struct PromptDetectionTests {
    @Test func theLocationPromptCounts() {
        #expect(SystemPromptWatcher.isPrompt(owner: "CoreLocationAgent", level: 25))
        #expect(SystemPromptWatcher.isPrompt(owner: "UserNotificationCenter", level: 8))
        #expect(SystemPromptWatcher.isPrompt(owner: "universalAccessAuthWarn", level: 0))
        #expect(!SystemPromptWatcher.isPrompt(owner: "Dock", level: 8))
    }

    @Test func ordinaryWindowsFromSystemAgentsArentPrompts() {
        #expect(!SystemPromptWatcher.isPrompt(owner: "CoreServicesUIAgent", level: 0))
        #expect(!SystemPromptWatcher.isPrompt(owner: "SecurityAgent", level: 0))
    }

    @Test func promptsBeatTheLoweredNotch() {
        // Levels measured on macOS 27: 8 for most prompts, 25 for location.
        #expect(SystemPromptWatcher.belowPrompts.rawValue < 8)
        #expect(SystemPromptWatcher.normalLevel.rawValue > 25)
    }
}
