#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline="$repo_root/.lint/policy-baseline.txt"
current="$(mktemp)"
additions="$(mktemp)"
trap 'rm -f "$current" "$additions"' EXIT

cd "$repo_root"

rg -n \
    --glob '*.lua' \
    --glob '!Libs/**' \
    --glob '!.unused/**' \
    '\bissecretvalue\b' \
    . | sed -E 's/^([^:]+):[0-9]+:/\1:/' | LC_ALL=C sort > "$current" || true

LC_ALL=C comm -13 "$baseline" "$current" > "$additions"

if [[ -s "$additions" ]]; then
    echo "New forbidden first-party Lua patterns were found:" >&2
    cat "$additions" >&2
    echo "Use F.isValueNonSecret and a single secret-safe path." >&2
    exit 1
fi
