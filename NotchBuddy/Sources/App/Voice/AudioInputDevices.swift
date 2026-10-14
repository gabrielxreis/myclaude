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

    /// Points the engine's input unit at the chosen microphone, or at the Mac's default input
    /// ("Padrão do sistema"): the same engine is reused, so the default must be set explicitly,
    /// or it kept the last microphone chosen until the app was reopened.
    static func apply(to audioUnit: AudioUnit?) {
        guard let audioUnit else { return }
        let uid = selectedUID
        var dev: AudioDeviceID
        if !uid.isEmpty, let chosen = allDeviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) {
            dev = chosen
        } else {
            if !uid.isEmpty { appendAppLog("nb.log", "[Voice] microphone \(uid) not connected, using the Mac's default") }
            guard let def = defaultInputID() else { return }
            dev = def
        }
        let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &dev,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        appendAppLog("nb.log", "[Voice] microphone \(string(dev, kAudioObjectPropertyName) ?? "?") → \(status == noErr ? "ok" : "error \(status)")")
    }

    /// The chosen microphone is plugged in (or the default is used).
    static var selectedIsConnected: Bool {
        let uid = selectedUID
        return uid.isEmpty || allDeviceIDs().contains { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
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
