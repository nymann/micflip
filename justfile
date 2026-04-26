default:
    @just --list

# Type-check every .swift in the repo. v0 has no real test suite
# (see plans/1.md); this is the baseline `run-plans` calls between
# plans, and it catches syntax/type errors as the binary grows.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    sources=(*.swift)
    if (( ${#sources[@]} == 0 )); then
        echo "no .swift sources yet — nothing to type-check"
        exit 0
    fi
    for f in "${sources[@]}"; do
        echo "==> swiftc -typecheck $f"
        swiftc -typecheck "$f"
    done

# Assemble build/micflip.app/ and ad-hoc sign it.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf build/micflip.app
    mkdir -p build/micflip.app/Contents/MacOS
    cp Info.plist build/micflip.app/Contents/Info.plist
    swiftc -O main.swift -o build/micflip.app/Contents/MacOS/micflip
    codesign --sign - build/micflip.app

# Install the bundle to ~/Applications/micflip.app.
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    install -d ~/Applications
    rm -rf ~/Applications/micflip.app
    cp -R build/micflip.app ~/Applications/micflip.app
