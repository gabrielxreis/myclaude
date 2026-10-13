#if !APPSTORE
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Microphone choice (Settings → Voz → Microfone)
//
// "" = the Mac's default input. Otherwise the device UID, which survives reboots and
// reconnections (the numeric AudioDeviceID does not).

enum AudioInputDevices {
    struct Device: Identifiable, Hashable { let id: String; let name: String }   // id = UID

    static let settingKey = "voiceInputDeviceUID"
    static var selectedUID: String {
        get { UserDefaults.standard.string(forKey: settingKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: settingKey) }
    }

    /// Every device with at least one input channel.
    static func list() -> [Device] {
        allDeviceIDs().compactMap { id in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: uid, name: name)
        }
    }

    /// Points the engine's input unit at the chosen microphone. No-op for the default.
    static func apply(to audioUnit: AudioUnit?) {
        let uid = selectedUID
        guard !uid.isEmpty, let audioUnit,
              var dev = allDeviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) else { return }
        let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &dev,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        appendAppLog("nb.log", "[Voice] microphone \(uid) → \(status == noErr ? "ok" : "error \(status)")")
    }

    // MARK: CoreAudio

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let s = value?.takeRetainedValue() else { return nil }
        return s as String
    }
}
#endif
