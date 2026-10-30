import AppKit
import CoreAudio
import CoreMediaIO

/// Pure meeting-mode rules.
enum MeetingLogic {
    static let activityID = "meeting"
    /// Mic/camera must stay on this long before the ear appears (skips quick probes,
    /// dictation blips).
    static let showDelay: Duration = .milliseconds(1500)

    static func activity(
        mic: Bool,
        camera: Bool,
        muted: Bool,
        appBundleID: String?,
        appName: String?,
        since: Date
    ) -> LiveActivity? {
        guard mic || camera else { return nil }
        let title = appName ?? (camera ? String(localized: "Camera in use") : String(localized: "Microphone in use"))
        return LiveActivity(
            id: activityID,
            source: .meeting,
            title: title,
            detail: muted ? String(localized: "Microphone muted") : nil,
            status: .meeting(mic: mic, camera: camera, muted: muted),
            startedAt: since,
            appBundleID: appBundleID
        )
    }
}

/// Meeting mode: shows when a camera or microphone is in use, by which app, and offers a
/// system-wide microphone mute. CoreAudio and CoreMediaIO "running somewhere" properties
/// with listeners: no camera or microphone permission, no polling.
@MainActor
final class MeetingMonitor {
    private let activity: ActivityState
    private var inputDevice: AudioDeviceID?
    private var cameras: [CMIOObjectID] = []
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var pendingShow: Task<Void, Never>?
    private var since: Date?
    /// Input volume before a volume-based mute, to restore it.
    private var volumeBeforeMute: Float?
    private var isRunning = false

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        activity.onToggleMicMute = { [weak self] in self?.toggleMute() }
        addAudioListener(AudioObjectID(kAudioObjectSystemObject), AudioInput.systemAddress(kAudioHardwarePropertyDefaultInputDevice)) {
            $0.watchInput()
        }
        addCameraListener(CMIOObjectID(kCMIOObjectSystemObject), CameraUsage.devicesAddress) { $0.watchCameras() }
        watchInput()
        watchCameras()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        activity.onToggleMicMute = nil
        for (object, address, block) in audioListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        for (object, address, block) in cameraListeners {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        audioListeners.removeAll()
        cameraListeners.removeAll()
        pendingShow?.cancel()
        activity.live.dismiss(MeetingLogic.activityID)
    }

    // MARK: - Mute

    func toggleMute() {
        guard let device = inputDevice else { return }
        let muted = AudioInput.isMuted(device)
        switch AudioInput.muteMethod(device) {
        case .muteProperty:
            AudioInput.setMuteProperty(!muted, device: device)
        case .volume:
            if muted {
                AudioInput.setVolume(volumeBeforeMute ?? 0.75, device: device)
            } else {
                volumeBeforeMute = AudioInput.volume(device)
                AudioInput.setVolume(0, device: device)
            }
        case .none:
            activity.live.handle(.say(text: String(localized: "This microphone can't be muted")))
        }
        refresh()
    }

    // MARK: - Watching

    private func watchInput() {
        removeListeners(on: inputDevice.map { [$0] } ?? [])
        inputDevice = AudioInput.defaultDevice()
        if let device = inputDevice {
            let selectors = [kAudioDevicePropertyDeviceIsRunningSomewhere]
            for selector in selectors {
                addAudioListener(device, AudioInput.systemAddress(selector)) { $0.refresh() }
            }
            addAudioListener(device, AudioInput.muteAddress) { $0.refresh() }
            addAudioListener(device, AudioInput.volumeAddress) { $0.refresh() }
        }
        refresh()
    }

    private func watchCameras() {
        for camera in cameras {
            cameraListeners.removeAll { entry in
                guard entry.0 == camera else { return false }
                var address = entry.1
                CMIOObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2)
                return true
            }
        }
        cameras = CameraUsage.devices()
        for camera in cameras {
            addCameraListener(camera, CameraUsage.runningAddress) { $0.refresh() }
        }
        refresh()
    }

    /// Is the microphone in use, and by which app (if macOS says).
    private func micInUse() -> (inUse: Bool, app: String?) {
        guard let device = inputDevice, AudioInput.isRunningSomewhere(device) else { return (false, nil) }
        return (true, AudioInput.recordingBundleIDs().first)
    }

    private func refresh() {
        let (mic, app) = micInUse()
        // Our own Mirror tab uses the camera; that isn't a meeting.
        let camera = !activity.isUsingCamera && cameras.contains(where: CameraUsage.isRunningSomewhere)
        let muted = inputDevice.map(AudioInput.isMuted) ?? false

        guard mic || camera else {
            pendingShow?.cancel()
            pendingShow = nil
            since = nil
            activity.live.dismiss(MeetingLogic.activityID)
            return
        }
        let start = since ?? Date()
        since = start
        guard let item = MeetingLogic.activity(
            mic: mic, camera: camera, muted: muted, appBundleID: app, appName: AppInfo.name(for: app), since: start
        ) else { return }

        if activity.live.items.contains(where: { $0.id == MeetingLogic.activityID }) {
            activity.live.set(item)
        } else if pendingShow == nil {
            pendingShow = Task { [weak self] in
                try? await Task.sleep(for: MeetingLogic.showDelay)
                guard !Task.isCancelled, let self else { return }
                self.pendingShow = nil
                self.refreshShowingNow()
            }
        }
    }

    /// After the delay: show only if still in use.
    private func refreshShowingNow() {
        let (mic, app) = micInUse()
        let camera = !activity.isUsingCamera && cameras.contains(where: CameraUsage.isRunningSomewhere)
        if let item = MeetingLogic.activity(
            mic: mic,
            camera: camera,
            muted: inputDevice.map(AudioInput.isMuted) ?? false,
            appBundleID: app,
            appName: AppInfo.name(for: app),
            since: since ?? Date()
        ) {
            activity.live.set(item)
        }
    }

    // MARK: - Listener plumbing

    private func addAudioListener(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        action: @escaping @MainActor (MeetingMonitor) -> Void
    ) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        guard AudioObjectHasProperty(object, &address),
              AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return }
        audioListeners.append((object, address, block))
    }

    private func addCameraListener(
        _ object: CMIOObjectID,
        _ address: CMIOObjectPropertyAddress,
        action: @escaping @MainActor (MeetingMonitor) -> Void
    ) {
        var address = address
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        guard CMIOObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return }
        cameraListeners.append((object, address, block))
    }

    private func removeListeners(on objects: [AudioObjectID]) {
        audioListeners.removeAll { entry in
            guard objects.contains(entry.0) else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2)
            return true
        }
    }
}
