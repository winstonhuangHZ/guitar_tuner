import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreAudio)
import CoreAudio
#endif

/// A capture device the user can choose from.
public struct AudioInputDevice: Sendable, Hashable, Identifiable {
    /// Stable identifier: a CoreAudio device UID on macOS, a port UID on iOS.
    public var id: String
    public var name: String
    /// True for the system default input.
    public var isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

/// Lists and selects the capture device.
///
/// macOS and iOS expose this very differently (CoreAudio device IDs versus audio session
/// ports), so the platform-specific parts live here and the rest of the app only deals
/// with `AudioInputDevice`.
public enum AudioInputDevices {
    /// The device currently in use, as far as the platform will say.
    public static var currentDeviceID: String? {
        #if os(macOS)
        guard let device = defaultInputDeviceID() else { return nil }
        return deviceUID(for: device)
        #elseif os(iOS)
        return AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        #else
        return nil
        #endif
    }

    public static func available() -> [AudioInputDevice] {
        #if os(macOS)
        return macInputDevices()
        #elseif os(iOS)
        let session = AVAudioSession.sharedInstance()
        let defaultID = session.currentRoute.inputs.first?.uid
        return (session.availableInputs ?? []).map {
            AudioInputDevice(id: $0.uid, name: $0.portName, isDefault: $0.uid == defaultID)
        }
        #else
        return []
        #endif
    }

    #if os(macOS)
    // MARK: - CoreAudio

    /// Applies a previously listed device to an input audio unit.
    @discardableResult
    public static func select(deviceID uid: String, on unit: AudioUnit?) -> Bool {
        guard let unit, let device = deviceID(forUID: uid) else { return false }
        var value = device
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &value,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    private static func macInputDevices() -> [AudioInputDevice] {
        let defaultDevice = defaultInputDeviceID()
        return allDeviceIDs().compactMap { device in
            guard inputChannelCount(of: device) > 0, let uid = deviceUID(for: device) else { return nil }
            return AudioInputDevice(
                id: uid,
                name: deviceName(for: device) ?? "Input \(device)",
                isDefault: device == defaultDevice
            )
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else {
            return []
        }
        return devices
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceUID(for device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid as String?
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { deviceUID(for: $0) == uid }
    }

    private static func deviceName(for device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name as String?
    }
    #elseif os(iOS)
    /// iOS picks inputs through the audio session instead of an audio unit.
    @discardableResult
    public static func select(deviceID: String) -> Bool {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.availableInputs?.first(where: { $0.uid == deviceID }) else { return false }
        return (try? session.setPreferredInput(port)) != nil
    }
    #endif
}
