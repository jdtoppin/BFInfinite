#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for candidate in lua5.1 lua-5.1 lua51 luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then
        "$candidate" ./scripts/generate-changelog.lua --check
        release_version="$(sed -n 's/^# BFInfinite \(r[^[:space:]]*\)$/\1/p' RELEASE_NOTES.md)"
        if [[ -z "$release_version" ]]; then
            echo "RELEASE_NOTES.md does not contain one exact release heading." >&2
            exit 1
        fi
        "$candidate" ./scripts/generate-changelog.lua \
            --check \
            --version "$release_version" \
            --release-notes RELEASE_NOTES.md
        if "$candidate" ./scripts/generate-changelog.lua \
            --version __missing__ \
            --release-notes /dev/null \
            >/dev/null 2>&1
        then
            echo "Missing changelog releases must be rejected." >&2
            exit 1
        fi
        echo "Generated changelog files are current."
        exit 0
    fi
done

echo "Lua 5.1 or LuaJIT is required to verify generated changelog files." >&2
exit 127
