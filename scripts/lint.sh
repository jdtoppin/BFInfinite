#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v luacheck >/dev/null 2>&1 || {
    echo "luacheck is required (https://github.com/lunarmodules/luacheck)." >&2
    exit 127
}
lua_compiler="${LUA_COMPILER:-}"
if [[ -n "$lua_compiler" && ! -x "$lua_compiler" ]] \
    && ! command -v "$lua_compiler" >/dev/null 2>&1
then
    echo "LUA_COMPILER does not name an executable: $lua_compiler" >&2
    exit 127
fi
if [[ -z "$lua_compiler" ]]; then
    for candidate in luac5.1 luac-5.1 luac5.4 luac-5.4 luac; do
        if command -v "$candidate" >/dev/null 2>&1; then
            lua_compiler="$candidate"
            break
        fi
    done
fi
if [[ -z "$lua_compiler" ]]; then
    echo "A stock Lua compiler is required to enforce WoW's compiler limits." >&2
    exit 127
fi

# Parse every maintained Lua file. Warnings are applied only to explicitly
# supplied changed files so legacy warnings do not hide new regressions.
luacheck . --only E

# Luacheck parses chunks without enforcing Lua 5.1's 200-local function limit.
# Byte-compiling catches that load-time failure before the addon reaches WoW.
while IFS= read -r -d '' file; do
    "$lua_compiler" -p "$file"
done < <(
    find . -type f -name '*.lua' \
        -not -path './.git/*' \
        -not -path './Libs/*' \
        -not -path './.unused/*' \
        -print0
)

./scripts/check-policy.sh
bash ./scripts/check-cooldown-manager-boundary.sh
bash ./scripts/check-cooldown-manager-presentation.sh

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
