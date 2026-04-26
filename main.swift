import CoreAudio
import Foundation
import UserNotifications

// TODO: replace with the UIDs from `swiftc -O list-inputs.swift -o /tmp/list-inputs && /tmp/list-inputs`.
let DEVICE_A_UID = "REPLACE_ME_A"
let DEVICE_B_UID = "REPLACE_ME_B"

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
    var a: AudioDeviceID? = nil
    var b: AudioDeviceID? = nil
    for id in allDeviceIDs() {
        let uid = cfStringProperty(id, selector: kAudioDevicePropertyDeviceUID, label: "kAudioDevicePropertyDeviceUID")
        if uid == DEVICE_A_UID { a = id }
        if uid == DEVICE_B_UID { b = id }
    }
    guard let aID = a else { die("device A not present (UID \(DEVICE_A_UID))") }
    guard let bID = b else { die("device B not present (UID \(DEVICE_B_UID))") }
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
