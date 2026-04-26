import CoreAudio
import Foundation

func die(_ status: OSStatus, _ where_: String) -> Never {
    FileHandle.standardError.write(Data("CoreAudio error \(status) at \(where_)\n".utf8))
    exit(1)
}

func deviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    )
    if sizeStatus != noErr { die(sizeStatus, "kAudioHardwarePropertyDevices size") }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
    )
    if status != noErr { die(status, "kAudioHardwarePropertyDevices data") }
    return ids
}

func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    if status != noErr { die(status, "kAudioDevicePropertyStreams size") }
    return size > 0
}

func cfStringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector, label: String) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<CFString>.size)
    var value: CFString = "" as CFString
    let status = withUnsafeMutablePointer(to: &value) { ptr in
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
    }
    if status != noErr { die(status, label) }
    return value as String
}

for id in deviceIDs() {
    guard hasInputStreams(id) else { continue }
    let uid = cfStringProperty(id, selector: kAudioDevicePropertyDeviceUID, label: "kAudioDevicePropertyDeviceUID")
    let name = cfStringProperty(id, selector: kAudioObjectPropertyName, label: "kAudioObjectPropertyName")
    print("\(uid)\t\(name)")
}
