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

# Build the toggle binary.
build:
    swiftc -O main.swift -o micflip

# Install to ~/bin (matches the layout in plans/1.md).
install: build
    install -d ~/bin
    install -m 0755 micflip ~/bin/micflip
