#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash ./scripts/lint.sh "$@"
python3 ./tests/abstract_framework_integration_policy_test.py
bash ./scripts/run-tests.sh
bash ./scripts/check-manifest.sh
bash ./scripts/check-changelog.sh
