# 01 — list-inputs helper

Standalone Swift program that prints every audio input device on the
system as `<UID>\t<name>`, one per line. This is the only "tooling" the
project needs: run it once, copy the two UIDs you care about into
`main.swift` (plan 02). See `design.md` for the broader design.

## Pre-conditions

- `list-inputs.swift` does not yet exist at the repo root.
- `just test` is green (it will be — there are no Swift sources yet, so
  the typecheck loop is a no-op).

## Steps

1. Create `list-inputs.swift` at the repo root. Single file, no
   dependencies beyond what ships with the Xcode command-line tools.

2. Imports: `CoreAudio` and `Foundation` (for `CFString` <-> `String`).

3. Behavior:

   - Enumerate device IDs via `AudioObjectGetPropertyData` with
     selector `kAudioHardwarePropertyDevices` on
     `kAudioObjectSystemObject`. Two-call pattern: first
     `AudioObjectGetPropertyDataSize` to learn how many bytes, then
     allocate `[AudioDeviceID]` of the right length and fetch.
   - For each device, skip it unless it has at least one **input**
     stream. Check by querying `kAudioDevicePropertyStreams` with
     `mScope = kAudioObjectPropertyScopeInput`; if the data size is 0,
     the device has no input streams — skip.
   - For surviving devices, read the UID
     (`kAudioDevicePropertyDeviceUID`, returns `CFString`) and the
     human-readable name (`kAudioObjectPropertyName`, also `CFString`).
   - Print each as `<UID>\t<name>` to stdout. Exit 0 on success.

4. Errors: if any CoreAudio call returns non-`noErr`, print a one-line
   diagnostic to stderr (`"CoreAudio error <status> at <where>"`) and
   exit non-zero. Don't try to recover.

5. Use `kAudioObjectPropertyElementMain` (not the deprecated
   `kAudioObjectPropertyElementMaster`) for `mElement`.

## Verification

- `just test` passes (this runs `swiftc -typecheck list-inputs.swift`).
- `swiftc -O list-inputs.swift -o /tmp/list-inputs && /tmp/list-inputs`
  prints at least one `<UID>\t<name>` line on a normal Mac. No need to
  keep the binary — typecheck is the durable gate.

## Out of scope

- `main.swift` (plan 02).
- Filtering by name, sorting, JSON output — keep it raw. Future-you
  greps the output anyway.

## Commit

`feat: add list-inputs helper for CoreAudio device discovery`
