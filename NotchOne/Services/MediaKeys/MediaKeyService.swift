import AppKit
import ApplicationServices
import CoreAudio

/// Catches volume, mute and brightness keys with a CGEvent tap, applies the change
/// itself and swallows the event so the system HUD doesn't appear.
///
/// Needs Accessibility permission. Without it the tap isn't installed and the keys
/// behave as normal. Keys we can't handle (e.g. an output with no volume control,
/// lid closed for brightness) are passed through to the system untouched.
@MainActor
final class MediaKeyService {
    private let activity: ActivityState
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustObserver: NSObjectProtocol?

    init(activity: ActivityState) {
        self.activity = activity
    }

    var isActive: Bool { tap != nil }

    func start() {
        guard trustObserver == nil else { return }
        // Posted whenever the Accessibility list changes; trust updates shortly after.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.installTapIfPossible()
            }
        }
        // No prompt here: the tour and Settings → Privacy ask for Accessibility from a button.
        installTapIfPossible()
    }

    func stop() {
        if let trustObserver { DistributedNotificationCenter.default().removeObserver(trustObserver) }
        trustObserver = nil
        removeTap()
    }

    // MARK: - Tap

    private func installTapIfPossible() {
        guard tap == nil, AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1) << CGEventMask(MediaKeyParser.systemDefinedEventType)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MediaKeyService>.fromOpaque(context).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { service.reenableTap() }
                    return Unmanaged.passUnretained(event)
                }

                guard type.rawValue == MediaKeyParser.systemDefinedEventType,
                      let nsEvent = NSEvent(cgEvent: event),
                      let key = MediaKeyParser.parse(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
                else { return Unmanaged.passUnretained(event) }

                let flags = event.flags
                let consumed = MainActor.assumeIsolated { service.handle(key, flags: flags) }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    private func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: - Handling

    /// Returns true when the event was handled and must not reach the system.
    private func handle(_ event: MediaKeyEvent, flags: CGEventFlags) -> Bool {
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        // ⌥ + key opens Sound/Displays settings: leave that to macOS.
        if option && !shift { return false }
        let fine = option && shift

        switch event.key {
        case .soundUp, .soundDown, .mute:
            return handleVolume(event, fine: fine)
        case .brightnessUp, .brightnessDown:
            return handleBrightness(event, fine: fine)
        case .illuminationUp, .illuminationDown, .illuminationToggle:
            return handleBacklight(event, fine: fine)
        }
    }

    private func handleBacklight(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        guard let keyboard = KeyboardBacklight.keyboard(),
              let current = KeyboardBacklight.level(of: keyboard) else { return false }
        if event.isDown {
            let next: Float
            switch event.key {
            case .illuminationToggle:
                guard !event.isRepeat else { return true }
                next = KeyboardBacklight.toggledLevel(current: current)
            default:
                next = LevelMath.step(current, up: event.key == .illuminationUp, fine: fine)
            }
            guard KeyboardBacklight.setLevel(next, of: keyboard) else { return false }
            activity.showPeek(.keyboardBacklight(level: next), seconds: 1.5)
        }
        return true
    }

    private func handleVolume(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        guard let device = AudioOutput.defaultDevice() else { return false }

        if event.key == .mute {
            guard AudioOutput.canMute(device) else { return false }
            if event.isDown && !event.isRepeat {
                AudioOutput.setMuted(!AudioOutput.isMuted(device), device: device)
                showVolume(device: device)
            }
            return true
        }

        guard AudioOutput.canSetVolume(device), let current = AudioOutput.volume(device) else { return false }
        if event.isDown {
            let up = event.key == .soundUp
            AudioOutput.setVolume(LevelMath.step(current, up: up, fine: fine), device: device)
            if up, AudioOutput.isMuted(device) { AudioOutput.setMuted(false, device: device) }
            showVolume(device: device)
        }
        return true
    }

    private func handleBrightness(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        guard DisplayBrightness.isAvailable,
              let display = DisplayBrightness.builtInDisplay(),
              let current = DisplayBrightness.brightness(of: display) else { return false }
        if event.isDown {
            let next = LevelMath.step(current, up: event.key == .brightnessUp, fine: fine)
            DisplayBrightness.setBrightness(next, of: display)
            activity.showPeek(.brightness(level: next), seconds: 1.5)
        }
        return true
    }

    private func showVolume(device: AudioDeviceID) {
        let level = AudioOutput.volume(device) ?? 0
        activity.showPeek(.volume(level: level, muted: AudioOutput.isMuted(device)), seconds: 1.5)
    }
}
