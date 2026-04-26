# 03 — input toggle + notification

The actual product. Replace the plan-02 stub `main.swift` with logic
that flips the macOS default audio input between two hardcoded UIDs
and pops a banner showing which device is now active. See `design.md`
for the broader design.

## Pre-conditions

- Plans 01–02 have landed.
- `main.swift` exists as the plan-02 stub; this plan overwrites it.
- `just build` produces a signed `build/micflip.app`.
- `just test` is green.

## Steps

1. Replace `main.swift` entirely with the real implementation.
   Imports: `CoreAudio`, `UserNotifications`, `Foundation`.

2. Two `let` constants near the top hold the device UIDs to toggle
   between. Use placeholder strings with a `TODO` pointing at
   `list-inputs.swift`:

   ```swift
   // TODO: replace with the UIDs from `swiftc -O list-inputs.swift -o /tmp/list-inputs && /tmp/list-inputs`.
   let DEVICE_A_UID = "REPLACE_ME_A"
   let DEVICE_B_UID = "REPLACE_ME_B"
   ```

   The binary will compile with placeholders; it just won't find a
   matching device at runtime until the user fills these in. That's
   intentional and verified below.

3. CoreAudio flow, in order:

   1. Read the current default input device:
      `AudioObjectGetPropertyData` on `kAudioObjectSystemObject` with
      selector `kAudioHardwarePropertyDefaultInputDevice`.
   2. Walk all devices (same enumeration pattern as
      `list-inputs.swift`) and resolve `DEVICE_A_UID` and
      `DEVICE_B_UID` to `AudioDeviceID`s by matching
      `kAudioDevicePropertyDeviceUID`.
   3. Decide the target: if current == A → target = B; otherwise
      (current == B, neither, unknown) → target = A.
   4. Read the target device's display name
      (`kAudioObjectPropertyName`, `CFString`) for the notification
      body.
   5. Set the default input via `AudioObjectSetPropertyData` with the
      target's `AudioDeviceID`.

4. Notification flow, after the switch lands:

   1. `let center = UNUserNotificationCenter.current()`.
   2. `requestAuthorization(options: [.alert])`, blocking on a
      `DispatchSemaphore` until the callback fires. If the user
      denied, write a one-line stderr note and skip step 4.3 — the
      toggle already succeeded, exit 0. If the callback returns a
      non-nil framework `error`, exit non-zero.
   3. Build a `UNNotificationRequest` (`identifier`: a fresh UUID
      string, `trigger: nil` for immediate delivery), content:
      - `title = "micflip"`
      - `body = "→ \(targetName)"`
   4. `center.add(request) { err in ... }`, blocking on another
      semaphore. If `err != nil`, exit non-zero with the message.
   5. Exit 0.

5. Use `kAudioObjectPropertyElementMain`, not the deprecated
   `kAudioObjectPropertyElementMaster`.

6. Errors throughout: any non-`noErr` CoreAudio status, or either UID
   missing from the live device list, or a non-nil notification
   framework error → write a one-line message to stderr and exit
   non-zero. No retries, no recovery.

## Verification

- `just test` passes (typechecks both `.swift` sources).
- `just build` produces a signed `build/micflip.app`.
- Running `build/micflip.app/Contents/MacOS/micflip` with the
  placeholder UIDs exits non-zero with a `micflip: device A not
  present` (or similar) message on stderr — proves the error path
  works before real UIDs are filled in.

## Out of scope

- Filling in the real UIDs — manual setup step, not part of any
  plan.
- Output-device flipping, distinct sounds per device, `--show` flag
  — see "Possible v1+" in `design.md`.

## Commit

`feat: implement input toggle with notification`
