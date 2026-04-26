import CoreAudio
import Foundation
import UserNotifications

// "A" candidates in priority order: first one currently plugged in
// wins. Scarlett at the desk; MacBook built-in everywhere else (e.g.
// in bed). "B" is always the AirPods.
let DEVICE_A_UIDS = [
    "AppleUSBAudioEngine:Focusrite:Scarlett Solo 4th Gen:S1MWC4Y3A24BDE:1,2",
    "BuiltInMicrophoneDevice",
]
let DEVICE_B_UID = "74-77-86-79-96-3F:input"

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("micflip: \(message)\n".utf8))
    exit(1)
}

func dieCA(_ status: OSStatus, _ where_: String) -> Never {
    die("CoreAudio error \(status) at \(where_)")
}

func currentDefaultInput() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
    )
    if status != noErr { dieCA(status, "kAudioHardwarePropertyDefaultInputDevice get") }
    return id
}

func setDefaultInput(_ id: AudioDeviceID) {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &value
    )
    if status != noErr { dieCA(status, "kAudioHardwarePropertyDefaultInputDevice set") }
}

func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    )
    if sizeStatus != noErr { dieCA(sizeStatus, "kAudioHardwarePropertyDevices size") }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
    )
    if status != noErr { dieCA(status, "kAudioHardwarePropertyDevices data") }
    return ids
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
    if status != noErr { dieCA(status, label) }
    return value as String
}

func resolveUIDs() -> (a: AudioDeviceID, b: AudioDeviceID) {
    var idsByUID: [String: AudioDeviceID] = [:]
    for id in allDeviceIDs() {
        let uid = cfStringProperty(id, selector: kAudioDevicePropertyDeviceUID, label: "kAudioDevicePropertyDeviceUID")
        idsByUID[uid] = id
    }
    guard let aID = DEVICE_A_UIDS.lazy.compactMap({ idsByUID[$0] }).first else {
        die("no A device present (tried: \(DEVICE_A_UIDS.joined(separator: ", ")))")
    }
    guard let bID = idsByUID[DEVICE_B_UID] else { die("device B not present (UID \(DEVICE_B_UID))") }
    return (aID, bID)
}

let current = currentDefaultInput()
let (aID, bID) = resolveUIDs()
let targetID = (current == aID) ? bID : aID
let targetName = cfStringProperty(targetID, selector: kAudioObjectPropertyName, label: "kAudioObjectPropertyName")

setDefaultInput(targetID)

let center = UNUserNotificationCenter.current()

let authSem = DispatchSemaphore(value: 0)
var authGranted = false
var authError: Error? = nil
center.requestAuthorization(options: [.alert]) { granted, error in
    authGranted = granted
    authError = error
    authSem.signal()
}
authSem.wait()

if let err = authError {
    die("notification authorization error: \(err.localizedDescription)")
}
if !authGranted {
    FileHandle.standardError.write(Data("micflip: notification authorization denied; toggle succeeded\n".utf8))
    exit(0)
}

let content = UNMutableNotificationContent()
content.title = "micflip"
content.body = "→ \(targetName)"

let request = UNNotificationRequest(
    identifier: UUID().uuidString,
    content: content,
    trigger: nil
)

let addSem = DispatchSemaphore(value: 0)
var addError: Error? = nil
center.add(request) { err in
    addError = err
    addSem.signal()
}
addSem.wait()

if let err = addError {
    die("notification delivery error: \(err.localizedDescription)")
}

exit(0)
