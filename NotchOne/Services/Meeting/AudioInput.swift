import AppKit
import CoreAudio

/// The default input device: is anyone recording, who, and system-wide mute.
/// Public CoreAudio only; reading "running somewhere" needs no microphone permission.
enum AudioInput {
    static func defaultDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    /// Bundle IDs of processes currently recording audio (macOS 14+ process objects).
    static func recordingBundleIDs() -> [String] {
        var address = systemAddress(kAudioHardwarePropertyProcessObjectList)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        let own = Bundle.main.bundleIdentifier
        return objects.compactMap { process in
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = globalAddress(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { return nil }
            var bundleID: Unmanaged<CFString>?
            var idSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var idAddress = globalAddress(kAudioProcessPropertyBundleID)
            guard AudioObjectGetPropertyData(process, &idAddress, 0, nil, &idSize, &bundleID) == noErr,
                  let value = bundleID?.takeRetainedValue() as String?, !value.isEmpty, value != own
            else { return nil }
            return value
        }
    }

    // MARK: - Mute

    /// How a device can be silenced: its mute switch, or its input volume as a fallback.
    enum MuteMethod: Equatable, Sendable {
        case muteProperty
        case volume
        case none
    }

    static func muteMethod(_ device: AudioDeviceID) -> MuteMethod {
        if isSettable(device, muteAddress) { return .muteProperty }
        if isSettable(device, volumeAddress) { return .volume }
        return .none
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        switch muteMethod(device) {
        case .muteProperty:
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = muteAddress
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
        case .volume:
            return (volume(device) ?? 1) <= 0.001
        case .none:
            return false
        }
    }

    @discardableResult
    static func setMuteProperty(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var value = UInt32(muted ? 1 : 0)
        var address = muteAddress
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    static func volume(_ device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    static func setVolume(_ volume: Float, device: AudioDeviceID) -> Bool {
        var value = Float32(min(1, max(0, volume)))
        var address = volumeAddress
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    // MARK: - Addresses

    static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        systemAddress(selector)
    }

    private static func isSettable(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
