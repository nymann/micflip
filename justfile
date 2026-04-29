default:
    @just --list

# Type-check every .swift in the repo. v0 has no real test suite
# (see design.md); this is the baseline `run-plans` calls between
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
    mkdir -p build/micflip.app/Contents/MacOS build/micflip.app/Contents/Resources
    cp Info.plist build/micflip.app/Contents/Info.plist
    xcrun actool micflip.xcassets \
        --compile build/micflip.app/Contents/Resources \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --app-icon AppIcon \
        --include-all-app-icons \
        --output-partial-info-plist /tmp/micflip-actool.plist >/dev/null
    swiftc -O main.swift -o build/micflip.app/Contents/MacOS/micflip
    codesign --sign - build/micflip.app

# Regenerate AppIcon PNGs (xcassets) and the legacy micflip.icns from tools/make-icon.swift.
icon:
    #!/usr/bin/env bash
    set -euo pipefail
    swiftc -O tools/make-icon.swift -o /tmp/micflip-make-icon
    /tmp/micflip-make-icon micflip.xcassets/AppIcon.appiconset
    rm -rf /tmp/micflip.iconset && mkdir /tmp/micflip.iconset
    cp micflip.xcassets/AppIcon.appiconset/*.png /tmp/micflip.iconset/
    iconutil -c icns /tmp/micflip.iconset -o micflip.icns

# Install the bundle to ~/Applications/micflip.app.
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    install -d ~/Applications
    rm -rf ~/Applications/micflip.app
    cp -R build/micflip.app ~/Applications/micflip.app

# Tag, build, zip and publish a GitHub release. Triggers the
# bump-cask workflow which opens a PR against nymann/homebrew-tap.
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "working tree dirty — commit or stash before releasing" >&2
        exit 1
    fi
    just build
    rm -f build/micflip-*.zip
    ditto -c -k --sequesterRsrc --keepParent build/micflip.app build/micflip-{{VERSION}}.zip
    git tag -a v{{VERSION}} -m "v{{VERSION}}"
    git push origin v{{VERSION}}
    gh release create v{{VERSION}} build/micflip-{{VERSION}}.zip \
        --title "v{{VERSION}}" --generate-notes
