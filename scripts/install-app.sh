#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

source_app="$PWD/build/Video Size Limiter.app"
destination='/Applications/Video Size Limiter.app'
expected_id='tech.infiniter.video-size-limiter'

if [[ -L "$destination" ]]; then
    printf 'Refusing to replace a symlink: %s\n' "$destination" >&2
    exit 1
fi
if [[ -e "$destination" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    if [[ "$installed_id" != "$expected_id" ]]; then
        printf 'Refusing to replace an unrelated app: %s\n' "$destination" >&2
        exit 1
    fi
fi

# Stage on the destination volume and verify before replacing the existing app.
# Keep the previous bundle until the new installation has passed verification.
staging=$(mktemp -d '/Applications/.video-size-limiter.XXXXXX')
cleanup() {
    result=$?
    if [[ -d "$staging/previous.app" && ! -e "$destination" ]]; then
        mv "$staging/previous.app" "$destination"
    fi
    rm -rf "$staging"
    exit "$result"
}
trap cleanup EXIT

ditto "$source_app" "$staging/Video Size Limiter.app"
codesign --verify --strict "$staging/Video Size Limiter.app"
plutil -lint "$staging/Video Size Limiter.app/Contents/Info.plist"
if [[ -e "$destination" ]]; then
    mv "$destination" "$staging/previous.app"
fi
mv "$staging/Video Size Limiter.app" "$destination"
if ! codesign --verify --strict "$destination"; then
    mv "$destination" "$staging/failed.app"
    exit 1
fi
printf 'Installed %s\n' "$destination"
printf 'If the app was already running, quit and reopen it to use this build.\n'
