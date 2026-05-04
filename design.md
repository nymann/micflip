# micflip

A trivial macOS CLI that toggles the default audio input between two
hardcoded devices. Built so a single hotkey can swap from the desk mic
(Scarlett Solo) to a walk-around mic (AirPods) without opening System
Settings or fishing through a menu bar dropdown. Each swap fires a
banner notification so a glance at the corner of the screen confirms
which mic just went live.

## Scope

- Single binary with four subcommands:
  - `micflip` (no args) — toggle (the hot path).
  - `micflip add` — interactive: classify currently-visible input
    devices into role A or B, then optionally reorder priority within
    each role that gained an entry.
  - `micflip list` — print `<UID>\t<name>` for every input device.
  - `micflip show` — print the current input's display name (status
    bars).
- On toggle: read current default input device. If both roles
  resolve and current matches role A, switch to B; otherwise
  (including "current is neither"), switch to A.
- Two device *roles*, A and B, live in `~/.config/micflip/devices`,
  each as a priority list of UIDs. The first UID in each list that's
  currently present resolves to that role, so role B can be either
  the in-ear AirPods or the AirPods Max — whichever is paired. Source
  contains no hardcoded UIDs.
- All toggle outcomes notify, so a hotkey-triggered invocation is
  never silent — even when there's nothing to flip:
  - Both roles resolve: `→ <new device name>`.
  - Only one role resolves: `only <name> — no flip target`.
  - Neither resolves: `no configured devices present`.
  - Config file missing: `no config — run \`micflip add\``.
  Toggle exits 0 in all five cases; the hot path never blocks on
  stdin.
- Only the toggle subcommand notifies; `add`/`list`/`show` are
  terminal-only.
- Exit 0 on success, non-zero with a one-line stderr message on failure
  (device not present, CoreAudio error, notification framework error).
- Ships as a hand-rolled `.app` bundle. The bundle is the smallest
  thing `UNUserNotificationCenter` accepts — auth is keyed by bundle
  identifier and the framework refuses to deliver from a bare,
  un-bundled binary.

Explicitly still out of scope: output/system-output switching, mute,
menu bar UI, hotkey handling, removal/reclassification via `add`
(edit the config file by hand for now), distribution packaging
(Developer ID signing, notarization).

## How it gets used

The binary is dumb on purpose. The hotkey lives in whatever launcher is
already on the machine (macOS Shortcuts, Raycast, Karabiner) and points
at `micflip.app/Contents/MacOS/micflip` directly — no `open -a` round
trip, the launcher just execs the binary inside the bundle. Each press
flips the input and pops a banner.

## Tech approach

- Language: Swift. CoreAudio is a C API but Swift calls it directly
  with no bridging header, and `swiftc` ships with the Xcode
  command-line tools — no Xcode project, no SwiftPM manifest. The
  `.app` bundle is hand-assembled by the justfile (Info.plist + binary
  in the right directories + ad-hoc codesign).
- One source file, `main.swift`. Build with
  `swiftc -O main.swift -o micflip.app/Contents/MacOS/micflip`.
- The audio side is three CoreAudio calls:
  1. `AudioObjectGetPropertyData` with selector
     `kAudioHardwarePropertyDefaultInputDevice` to read the current
     input.
  2. Walk `kAudioHardwarePropertyDevices`, match each device's
     `kAudioDevicePropertyDeviceUID` against the UIDs in the
     config's role-A and role-B lists to resolve each role to an
     `AudioDeviceID`.
  3. `AudioObjectSetPropertyData` with the same selector to set the
     new default input.
- Identify devices by **UID**, not name. UIDs are stable across
  reboots and renames; human-readable names drift ("AirPods" vs
  "Kristian's AirPods Pro"). The display name is read fresh
  per-invocation just for the notification body.
- Config format: INI-style, two sections `[a]` and `[b]`, one UID per
  line, `#` comments, blank lines ignored. Order within each section
  is priority — first UID present in the system wins. Parser is
  hand-rolled in `main.swift`; no toml/yaml dependency.
- `micflip add` walks `allInputDevices()`, filters out UIDs already
  in the config, prompts `[a]`/`[b]`/`[-]` per device, then for each
  role that gained entries shows the full role list (with the new
  ones flagged ← NEW) and asks for an optional reorder as a
  space-separated permutation. Empty input keeps the just-shown
  order.
- Notifications: `UNUserNotificationCenter.current()`. First run
  calls `requestAuthorization(options: [.alert])` and blocks on a
  semaphore until the user grants or denies; subsequent runs skip the
  prompt. After the switch, build a `UNNotificationRequest` with `nil`
  trigger (immediate delivery) and `add(_:withCompletionHandler:)`,
  again blocking on the completion callback before exiting — `swiftc`
  CLIs exit too fast otherwise and the notification never reaches the
  system service.
- Bundle layout — the smallest `.app` UserNotifications will deliver
  from:
  ```
  micflip.app/
    Contents/
      Info.plist               # CFBundleIdentifier, CFBundleExecutable, LSUIElement=true
      MacOS/
        micflip                # the swiftc binary
  ```
  `LSUIElement=true` keeps the binary out of the Dock when invoked.
  After assembly, ad-hoc sign with `codesign --sign - micflip.app`.
  The notification framework keys auth by bundle ID + signing
  identity; ad-hoc is enough for personal use, and without *any*
  signature the grant won't persist across rebuilds.

## Layout

```
micflip/
  design.md            this file — design brief
  plans/               numbered, actionable plans consumed by `run-plans`
  main.swift           the binary: toggle / add / list / show
  Info.plist           template baked into micflip.app at build time
  micflip.icns         app icon, regenerated by `just icon`
  tools/make-icon.swift  one-shot generator for micflip.icns (mic.fill SF Symbol)
  justfile             `just build` assembles the .app, `just install` copies it
```

No tests in v0 — the logic is "three CoreAudio calls plus a
notification post"; the only failure modes are environmental (device
unplugged, permissions denied, bundle malformed) and those are easier
to reproduce by hand than to mock. `just test` runs `swiftc -typecheck`
over every `.swift` source as a syntax/type gate between `run-plans`
steps.

## Possible later directions

Pick zero or more later, only if the friction actually shows up:

- `micflip remove` / `micflip move <uid> <a|b>` to edit the config
  without opening it. Skipped until adding-only proves insufficient.
- Menu-bar app variant that displays the current input and lets you
  click to switch — a separate target, not a replacement for the CLI.
- Output-device toggle (separate binary, or `-t input|output` flag).
- Distinct notification sounds per device, so the swap is identifiable
  without looking at the screen.

## Open questions

- Whether to also flip the **output** when switching to AirPods, since
  the AirPods are a combined I/O device and you probably want both
  ears on Discord too. Decide after living with input-only for a few
  days.
- Whether ad-hoc signing keeps the notification authorization across
  binary rebuilds in practice, or whether each rebuild re-prompts —
  resolved by living with it.
