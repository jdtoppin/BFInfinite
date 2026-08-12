#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v unzip >/dev/null 2>&1 || {
    echo "unzip is required to validate the package." >&2
    exit 127
}
command -v rg >/dev/null 2>&1 || {
    echo "ripgrep is required to validate the package." >&2
    exit 127
}

lua_compiler=""
for candidate in luac5.1 luac-5.1 luac; do
    if command -v "$candidate" >/dev/null 2>&1; then
        lua_compiler="$(command -v "$candidate")"
        break
    fi
done
if [[ -z "$lua_compiler" ]] && ! command -v luajit >/dev/null 2>&1; then
    echo "A Lua 5.1 compiler or LuaJIT is required to validate packaged Lua." >&2
    exit 127
fi

if (( $# > 1 )); then
    echo "Usage: $0 [package.zip]" >&2
    exit 2
fi

if (( $# == 1 )); then
    archive="$1"
else
    shopt -s nullglob
    archives=(.release/*.zip)
    shopt -u nullglob
    if (( ${#archives[@]} != 1 )); then
        echo "Expected exactly one package in .release, found ${#archives[@]}." >&2
        exit 1
    fi
    archive="${archives[0]}"
fi

if [[ ! -f "$archive" ]]; then
    echo "Package not found: $archive" >&2
    exit 1
fi

unzip -tq "$archive" >/dev/null

entries="$(mktemp)"
extract_root="$(mktemp -d)"
trap 'rm -f "$entries"; rm -rf "$extract_root"' EXIT
unzip -Z1 "$archive" > "$entries"

failed=false
has_toc=false
while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    case "$entry" in
        /*|..|../*|*/..|*/../*|*\\*)
            echo "Unsafe ZIP entry: $entry" >&2
            failed=true
            ;;
    esac
    case "$entry" in
        BFInfinite|BFInfinite/*) ;;
        *)
            echo "ZIP entry is outside the BFInfinite root: $entry" >&2
            failed=true
            ;;
    esac
    case "$entry" in
        BFInfinite/BFInfinite.toc) has_toc=true ;;
        BFInfinite/.*|BFInfinite/tests|BFInfinite/tests/*|BFInfinite/scripts|BFInfinite/scripts/*|BFInfinite/AGENTS.md|BFInfinite/CONTRIBUTING.md|BFInfinite/Modules/Blizzard/Style/WorldMapFrame_Test.lua)
            echo "Developer-only file is present in the package: $entry" >&2
            failed=true
            ;;
    esac
done < "$entries"

if [[ "$has_toc" == false ]]; then
    echo "Package does not contain BFInfinite/BFInfinite.toc." >&2
    failed=true
fi

if [[ "$failed" == true ]]; then
    exit 1
fi

unzip -qq "$archive" -d "$extract_root"
bash "$repo_root/scripts/check-manifest.sh" "$extract_root/BFInfinite"

while IFS= read -r -d '' lua_file; do
    if [[ -n "$lua_compiler" ]]; then
        "$lua_compiler" -p "$lua_file"
    else
        luajit -b "$lua_file" /dev/null
    fi
done < <(find "$extract_root/BFInfinite" -type f -name '*.lua' -print0)

if rg -n '@(project-version|localization)@|#@(debug|end-debug|do-not-package|end-do-not-package)@' \
    "$extract_root/BFInfinite"
then
    echo "Unresolved packager tokens are present in the package." >&2
    exit 1
fi

echo "Package validation passed: $archive"
