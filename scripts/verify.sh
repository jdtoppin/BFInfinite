#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash ./scripts/lint.sh "$@"
bash ./scripts/run-tests.sh
bash ./scripts/check-manifest.sh
