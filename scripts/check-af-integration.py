#!/usr/bin/env python3
"""Validate BFInfinite against its exact AbstractFramework checkout."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


EXPECTED_REPOSITORY = "jdtoppin/AbstractFramework"
LOCK_KEYS = frozenset({"repository", "revision", "version"})
REVISION_PATTERN = re.compile(r"[0-9a-f]{40}")
VERSION_PATTERN = re.compile(r"r([1-9][0-9]*)")


class IntegrationError(RuntimeError):
    """A reviewed dependency contract was not satisfied."""


@dataclass(frozen=True)
class FrameworkLock:
    repository: str
    revision: str
    version: str

    @property
    def version_number(self) -> int:
        match = VERSION_PATTERN.fullmatch(self.version)
        if match is None:  # guarded by parse_lock; retained for direct construction
            raise IntegrationError(f"invalid AbstractFramework version: {self.version!r}")
        return int(match.group(1))


def parse_lock(path: Path) -> FrameworkLock:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise IntegrationError(f"{path}:{line_number}: expected key=value")
        key, value = line.split("=", 1)
        if key not in LOCK_KEYS:
            raise IntegrationError(f"{path}:{line_number}: unknown key {key!r}")
        if key in values:
            raise IntegrationError(f"{path}:{line_number}: duplicate key {key!r}")
        if not value or value != value.strip():
            raise IntegrationError(f"{path}:{line_number}: invalid value for {key!r}")
        values[key] = value

    missing = sorted(LOCK_KEYS.difference(values))
    if missing:
        raise IntegrationError(f"{path}: missing keys: {', '.join(missing)}")
    if values["repository"] != EXPECTED_REPOSITORY:
        raise IntegrationError(
            f"{path}: repository must be {EXPECTED_REPOSITORY!r}, got {values['repository']!r}"
        )
    if REVISION_PATTERN.fullmatch(values["revision"]) is None:
        raise IntegrationError(f"{path}: revision must be a full lowercase 40-character commit SHA")
    if VERSION_PATTERN.fullmatch(values["version"]) is None:
        raise IntegrationError(f"{path}: version must match r<positive integer>")

    return FrameworkLock(**values)


def toc_value(path: Path, field: str) -> str:
    pattern = re.compile(rf"^##\s+{re.escape(field)}:\s*(.*?)\s*$")
    matches = [
        match.group(1)
        for line in path.read_text(encoding="utf-8-sig").splitlines()
        if (match := pattern.match(line)) is not None
    ]
    if len(matches) != 1:
        raise IntegrationError(f"{path}: expected exactly one ## {field} field, found {len(matches)}")
    return matches[0]


def one_numeric_assignment(path: Path, pattern: re.Pattern[str], label: str) -> int:
    matches = [
        int(match.group(1))
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := pattern.match(line)) is not None
    ]
    if len(matches) != 1:
        raise IntegrationError(f"{path}: expected exactly one {label} assignment, found {len(matches)}")
    return matches[0]


def validate_source_contract(
    bfi_root: Path,
    af_root: Path,
    lock: FrameworkLock,
    actual_revision: str,
) -> None:
    if actual_revision != lock.revision:
        raise IntegrationError(
            f"AbstractFramework checkout is {actual_revision}, expected locked revision {lock.revision}"
        )

    dependencies = toc_value(bfi_root / "BFInfinite.toc", "Dependencies")
    if dependencies != "AbstractFramework":
        raise IntegrationError(
            "BFInfinite.toc must hard-depend on exactly AbstractFramework; "
            f"got {dependencies!r}"
        )

    assignment = re.compile(r"^\s*BFI\.requiredAFVersion\s*=\s*([0-9]+)\s*(?:--.*)?$")
    core_constant = re.compile(r"^\s*local\s+REQUIRED_AF_VERSION\s*=\s*([0-9]+)\s*(?:--.*)?$")
    init_requirement = one_numeric_assignment(
        bfi_root / "Init.lua", assignment, "BFI.requiredAFVersion"
    )
    core_requirement = one_numeric_assignment(
        bfi_root / "Core.lua", core_constant, "REQUIRED_AF_VERSION"
    )
    if init_requirement > core_requirement:
        raise IntegrationError(
            "Init.lua's bootstrap AbstractFramework requirement cannot exceed Core.lua's "
            f"runtime requirement: r{init_requirement} > r{core_requirement}"
        )

    core_source = (bfi_root / "Core.lua").read_text(encoding="utf-8")
    if re.search(r"\bAF\.RequireVersion\s*\(\s*REQUIRED_AF_VERSION\s*\)", core_source) is None:
        raise IntegrationError("Core.lua must enforce AF.RequireVersion(REQUIRED_AF_VERSION)")

    af_version = toc_value(af_root / "AbstractFramework.toc", "Version")
    if af_version != lock.version:
        raise IntegrationError(
            f"AbstractFramework.toc declares {af_version!r}, expected locked version {lock.version!r}"
        )
    if lock.version_number < core_requirement:
        raise IntegrationError(
            f"locked AbstractFramework {lock.version} does not satisfy BFI runtime "
            f"requirement r{core_requirement}"
        )


def git_head(path: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "not a Git checkout"
        raise IntegrationError(f"cannot inspect AbstractFramework checkout at {path}: {detail}")
    return result.stdout.strip()


def export_github_output(path: Path, lock: FrameworkLock) -> None:
    with path.open("a", encoding="utf-8") as output:
        output.write(f"repository={lock.repository}\n")
        output.write(f"revision={lock.revision}\n")
        output.write(f"version={lock.version}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lock",
        type=Path,
        help="lock file (defaults to .github/abstract-framework.lock)",
    )
    parser.add_argument("--af-root", type=Path, help="checked-out AbstractFramework root")
    parser.add_argument(
        "--export-github-output",
        type=Path,
        help="validate the lock and append checkout values to this GitHub output file",
    )
    args = parser.parse_args()

    bfi_root = Path(__file__).resolve().parent.parent
    lock_path = args.lock or bfi_root / ".github" / "abstract-framework.lock"
    try:
        lock = parse_lock(lock_path)
        if args.export_github_output is not None:
            export_github_output(args.export_github_output, lock)
            print(f"AbstractFramework lock passed: {lock.repository}@{lock.revision} ({lock.version})")
            return 0
        if args.af_root is None:
            parser.error("--af-root is required unless --export-github-output is used")

        af_root = args.af_root.resolve()
        validate_source_contract(bfi_root, af_root, lock, git_head(af_root))
    except (IntegrationError, OSError) as exc:
        print(f"AbstractFramework integration check failed: {exc}", file=sys.stderr)
        return 1

    print(f"AbstractFramework integration passed: {lock.repository}@{lock.revision} ({lock.version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
