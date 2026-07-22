#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v luacheck >/dev/null 2>&1 || {
    echo "luacheck is required (https://github.com/lunarmodules/luacheck)." >&2
    exit 127
}

# Parse every maintained Lua file. Warnings are applied only to explicitly
# supplied changed files so legacy warnings do not hide new regressions.
luacheck . --only E
./scripts/check-policy.sh

changed=()
for file in "$@"; do
    case "$file" in
        *.lua)
            if [[ -f "$file" && "$file" != Libs/* && "$file" != .unused/* ]]; then
                changed+=("$file")
            fi
            ;;
    esac
done

if (( ${#changed[@]} > 0 )); then
    luacheck "${changed[@]}"
fi
