#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

export LC_ALL=C

interpreters=()
for candidate in lua5.1 lua-5.1 lua51 luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then
        path="$(command -v "$candidate")"
        duplicate=false
        for existing in "${interpreters[@]:-}"; do
            if [[ "$existing" == "$path" ]]; then
                duplicate=true
                break
            fi
        done
        if [[ "$duplicate" == false ]]; then
            interpreters+=("$path")
        fi
    fi
done

if (( ${#interpreters[@]} == 0 )); then
    echo "Lua 5.1 or LuaJIT is required to run the tests." >&2
    exit 127
fi

shopt -s nullglob
tests=(tests/*_test.lua)
shopt -u nullglob

if (( ${#tests[@]} == 0 )); then
    echo "No tests matching tests/*_test.lua were found." >&2
    exit 1
fi

for interpreter in "${interpreters[@]}"; do
    echo "Running ${#tests[@]} tests with $interpreter"
    for test_file in "${tests[@]}"; do
        echo "  $test_file"
        "$interpreter" "$test_file"
    done
done
