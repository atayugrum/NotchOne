import AudioToolbox
import CoreAudio

/// Volume and mute of the default output device, via public CoreAudio APIs.
enum AudioOutput {
    static func defaultDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    // MARK: Volume

    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        isSettable(device, address: volumeAddress)
    }

    static func volume(_ device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        return get(device, address: volumeAddress, into: &value) ? value : nil
    }

    @discardableResult
    static func setVolume(_ volume: Float, device: AudioDeviceID) -> Bool {
        var value = Float32(min(1, max(0, volume)))
        return set(device, address: volumeAddress, value: &value)
    }

    // MARK: Mute

    static func canMute(_ device: AudioDeviceID) -> Bool {
        isSettable(device, address: muteAddress)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var value = UInt32(0)
        return get(device, address: muteAddress, into: &value) && value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var value = UInt32(muted ? 1 : 0)
        return set(device, address: muteAddress, value: &value)
    }

    // MARK: - Private

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func isSettable(_ device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func get<T: BitwiseCopyable>(
        _ device: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        into value: inout T
    ) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr
    }

    private static func set<T: BitwiseCopyable>(
        _ device: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        value: inout T
    ) -> Bool {
        var address = address
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(buffer.count), buffer.baseAddress!)
        }
        return status == noErr
    }
}
