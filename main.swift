import CoreAudio
import Foundation
import UserNotifications

// MARK: - Errors

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("micflip: \(message)\n".utf8))
    exit(1)
}

func dieCA(_ status: OSStatus, _ where_: String) -> Never {
    die("CoreAudio error \(status) at \(where_)")
}

// MARK: - Config
//
// Two roles, A and B, each a priority list of CoreAudio device UIDs.
// First UID present in the system wins for each role. So role B can be
// the in-ear AirPods or the AirPods Max — whichever is paired right now.

let CONFIG_PATH = ("~/.config/micflip/devices" as NSString).expandingTildeInPath

struct Config {
    var a: [String]
    var b: [String]
}

func loadConfig() -> Config? {
    guard let raw = try? String(contentsOfFile: CONFIG_PATH, encoding: .utf8) else {
        return nil
    }
    var a: [String] = []
    var b: [String] = []
    var section: String? = nil
    for line in raw.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            section = String(trimmed.dropFirst().dropLast()).lowercased()
            continue
        }
        switch section {
        case "a": a.append(trimmed)
        case "b": b.append(trimmed)
        default: break
        }
    }
    return Config(a: a, b: b)
}

func writeConfig(_ c: Config) {
    let dir = (CONFIG_PATH as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var s = "# micflip device config — UIDs in priority order; first present wins.\n"
    s += "# Edit by hand or with `micflip add`.\n"
    s += "\n[a]\n"
    for uid in c.a { s += "\(uid)\n" }
    s += "\n[b]\n"
    for uid in c.b { s += "\(uid)\n" }
    do {
        try s.write(toFile: CONFIG_PATH, atomically: true, encoding: .utf8)
    } catch {
        die("could not write \(CONFIG_PATH): \(error.localizedDescription)")
    }
}

// MARK: - CoreAudio

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

func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    if status != noErr { dieCA(status, "kAudioDevicePropertyStreams size") }
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
    if status != noErr { dieCA(status, label) }
    return value as String
}

struct InputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

func allInputDevices() -> [InputDevice] {
    var out: [InputDevice] = []
    for id in allDeviceIDs() {
        guard hasInputStreams(id) else { continue }
        let uid = cfStringProperty(id, selector: kAudioDevicePropertyDeviceUID, label: "kAudioDevicePropertyDeviceUID")
        let name = cfStringProperty(id, selector: kAudioObjectPropertyName, label: "kAudioObjectPropertyName")
        out.append(InputDevice(id: id, uid: uid, name: name))
    }
    return out
}

// MARK: - Notification

func notify(_ body: String) {
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
        return
    }

    let content = UNMutableNotificationContent()
    content.title = "micflip"
    content.body = body

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
}

// MARK: - Subcommands

func runToggle() {
    guard let config = loadConfig() else {
        notify("no config — run `micflip add`")
        return
    }
    let inputs = allInputDevices()
    let byUID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.uid, $0) })

    let aDev = config.a.lazy.compactMap({ byUID[$0] }).first
    let bDev = config.b.lazy.compactMap({ byUID[$0] }).first

    switch (aDev, bDev) {
    case (nil, nil):
        notify("no configured devices present")
    case (let a?, nil):
        notify("only \(a.name) — no flip target")
    case (nil, let b?):
        notify("only \(b.name) — no flip target")
    case (let a?, let b?):
        let current = currentDefaultInput()
        let target = (current == a.id) ? b : a
        setDefaultInput(target.id)
        notify("→ \(target.name)")
    }
}

func runList() {
    for d in allInputDevices() {
        print("\(d.uid)\t\(d.name)")
    }
}

func runShow() {
    let id = currentDefaultInput()
    let name = cfStringProperty(id, selector: kAudioObjectPropertyName, label: "kAudioObjectPropertyName")
    print(name)
}

// MARK: - `micflip add`

func promptLine(_ prompt: String) -> String {
    print(prompt, terminator: "")
    guard let line = readLine() else { exit(1) }
    return line.trimmingCharacters(in: .whitespaces)
}

func promptReorder(role: String, uids: [String], newUIDs: Set<String>, nameByUID: [String: String]) -> [String] {
    func label(_ uid: String) -> String {
        nameByUID[uid] ?? "\(uid) (not connected)"
    }

    print("")
    print("Role \(role.uppercased()) priority (first present wins):")
    for (i, uid) in uids.enumerated() {
        let marker = newUIDs.contains(uid) ? "  ← NEW" : ""
        print("  \(i+1). \(label(uid))\(marker)")
    }

    while true {
        let line = promptLine("Reorder? (space-separated indices, or empty to keep): ")
        if line.isEmpty { return uids }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard parts.count == uids.count else {
            print("expected \(uids.count) indices, got \(parts.count)")
            continue
        }
        var indices: [Int] = []
        var bad = false
        for p in parts {
            guard let n = Int(p), n >= 1, n <= uids.count else {
                print("invalid index: \(p)")
                bad = true
                break
            }
            indices.append(n)
        }
        if bad { continue }
        if Set(indices).count != indices.count {
            print("indices must be unique")
            continue
        }
        let reordered = indices.map { uids[$0 - 1] }
        print("")
        for (i, uid) in reordered.enumerated() {
            print("  \(i+1). \(label(uid))")
        }
        return reordered
    }
}

func runAdd() {
    var config = loadConfig() ?? Config(a: [], b: [])
    let configured = Set(config.a + config.b)
    let inputs = allInputDevices()
    let nameByUID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.uid, $0.name) })
    let unclassified = inputs.filter { !configured.contains($0.uid) }

    if unclassified.isEmpty {
        print("No new input devices.")
        if !config.a.isEmpty || !config.b.isEmpty {
            print("")
            print("Current config:")
            for (role, uids) in [("a", config.a), ("b", config.b)] where !uids.isEmpty {
                print("  [\(role)]")
                for uid in uids {
                    print("    \(nameByUID[uid] ?? "\(uid) (not connected)")")
                }
            }
        }
        return
    }

    print("Currently-visible inputs not in your config:")
    for (i, d) in unclassified.enumerated() {
        print("  \(i+1). \(d.name)")
    }
    print("")
    print("For each: [a]=desk, [b]=on-the-go, [-]=skip")

    var newA: [String] = []
    var newB: [String] = []
    for (i, d) in unclassified.enumerated() {
        loop: while true {
            let choice = promptLine("  \(i+1) \(d.name): ").lowercased()
            switch choice {
            case "a":
                config.a.append(d.uid)
                newA.append(d.uid)
                break loop
            case "b":
                config.b.append(d.uid)
                newB.append(d.uid)
                break loop
            case "-", "":
                break loop
            default:
                continue loop
            }
        }
    }

    if !newA.isEmpty {
        config.a = promptReorder(role: "a", uids: config.a, newUIDs: Set(newA), nameByUID: nameByUID)
    }
    if !newB.isEmpty {
        config.b = promptReorder(role: "b", uids: config.b, newUIDs: Set(newB), nameByUID: nameByUID)
    }

    writeConfig(config)
    print("")
    print("Wrote \(CONFIG_PATH).")
}

// MARK: - Main

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "toggle"
switch cmd {
case "toggle": runToggle()
case "add": runAdd()
case "list": runList()
case "show": runShow()
default: die("unknown command: \(cmd) — try toggle / add / list / show")
}
exit(0)
