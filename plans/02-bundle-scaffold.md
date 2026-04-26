# 02 — .app bundle scaffold

Stand up the minimum hand-rolled `.app` bundle that the v0 binary will
live inside. `UNUserNotificationCenter` (used in plan 03) refuses to
deliver from an un-bundled binary, so every later plan depends on this
scaffold being in place. See `design.md` for the broader rationale.

This plan deliberately *doesn't* implement the toggle or the
notification — it just proves the build/sign/install pipeline works
end-to-end with a stub. Plan 03 replaces the stub with the real logic.

## Pre-conditions

- Plan 01 has landed (`list-inputs.swift` exists at the repo root).
- No `Info.plist`, no `main.swift`, no `.gitignore` at the repo root.
- `just test` is green.

## Steps

1. Create `.gitignore` at the repo root with at least:

   ```
   build/
   *.swiftmodule
   .DS_Store
   ```

2. Create `Info.plist` at the repo root. Plain XML plist, required
   keys:

   - `CFBundleIdentifier` = `dev.nymann.micflip`
   - `CFBundleExecutable` = `micflip`
   - `CFBundleName` = `micflip`
   - `CFBundlePackageType` = `APPL`
   - `CFBundleShortVersionString` = `0.1.0`
   - `CFBundleVersion` = `1`
   - `LSUIElement` = `true` (keeps the binary out of the Dock when
     run)

3. Create `main.swift` at the repo root as a stub:

   ```swift
   import Foundation
   FileHandle.standardError.write(Data("micflip stub — replaced in plan 03\n".utf8))
   ```

   Pure stub. Plan 03 will replace it entirely. `swiftc -typecheck`
   must pass on it.

4. Rewrite the justfile so:

   - `build` produces `build/micflip.app/` with this layout:

     ```
     build/micflip.app/
       Contents/
         Info.plist                # copied from repo root
         MacOS/
           micflip                 # swiftc -O main.swift -o ...
     ```

     Then `codesign --sign - build/micflip.app` to ad-hoc sign.

   - `install` depends on `build` and copies the bundle to
     `~/Applications/micflip.app` (`rm -rf` the destination first
     since `cp -R` into an existing directory misbehaves).

   - `test` is unchanged — still typechecks every `.swift` source.

   Use bash recipes (`#!/usr/bin/env bash` + `set -euo pipefail`)
   wherever a step needs more than one line so failures abort the
   recipe.

## Verification

- `just test` passes.
- `just build` produces `build/micflip.app/` containing
  `Contents/Info.plist` and `Contents/MacOS/micflip`.
- `codesign -dv build/micflip.app` reports `Signature=adhoc` (or
  similar) without error.
- `build/micflip.app/Contents/MacOS/micflip` runs, prints the stub
  message to stderr, exits 0.

## Out of scope

- Toggle logic, CoreAudio, notifications — plan 03.
- Universal binary, hardened runtime, notarization — see "Possible
  v1+" in `design.md`.

## Commit

`feat: scaffold .app bundle assembly`
