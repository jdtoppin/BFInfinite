#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addon_root="${1:-$repo_root}"

command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to validate the addon load graph." >&2
    exit 127
}

python3 - "$addon_root" <<'PY'
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath

root = Path(sys.argv[1]).resolve()
toc = root / "BFInfinite.toc"
errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def normalize(raw: str, parent: PurePosixPath = PurePosixPath(".")) -> PurePosixPath | None:
    value = raw.strip().replace("\\", "/")
    value = re.sub(r"\s+\[[^]]+\]\s*$", "", value)
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts:
        fail(f"unsafe manifest path: {raw!r}")
        return None
    combined = parent / path
    if any(part in ("", ".") for part in combined.parts):
        combined = PurePosixPath(*(part for part in combined.parts if part not in ("", ".")))
    return combined


def exact_file(relative: PurePosixPath) -> Path | None:
    current = root
    for part in relative.parts:
        if not current.is_dir():
            fail(f"missing manifest path: {relative}")
            return None
        names = {entry.name for entry in current.iterdir()}
        if part not in names:
            case_matches = sorted(name for name in names if name.casefold() == part.casefold())
            if case_matches:
                fail(f"manifest path has incorrect case: {relative} (found {case_matches[0]!r})")
            else:
                fail(f"missing manifest path: {relative}")
            return None
        current = current / part
    if not current.is_file():
        fail(f"manifest path is not a file: {relative}")
        return None
    return current


if not toc.is_file():
    fail("missing BFInfinite.toc")
else:
    for xml in sorted(root.rglob("*.xml")):
        relative = xml.relative_to(root)
        if any(part in {".git", ".unused"} for part in relative.parts):
            continue
        try:
            ET.parse(xml)
        except (ET.ParseError, OSError) as exc:
            fail(f"invalid XML {relative}: {exc}")

queue: list[PurePosixPath] = []
if toc.is_file():
    for line_number, line in enumerate(toc.read_text(encoding="utf-8-sig").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        path = normalize(stripped)
        if path is None:
            fail(f"BFInfinite.toc:{line_number}: invalid entry")
        else:
            queue.append(path)

visited: set[PurePosixPath] = set()
while queue:
    relative = queue.pop(0)
    if relative in visited:
        continue
    visited.add(relative)
    source = exact_file(relative)
    if source is None or source.suffix.lower() != ".xml":
        continue
    try:
        document = ET.parse(source)
    except (ET.ParseError, OSError):
        continue
    parent = relative.parent
    for element in document.iter():
        kind = element.tag.rsplit("}", 1)[-1]
        if kind not in {"Include", "Script"}:
            continue
        raw = element.attrib.get("file")
        if not raw:
            fail(f"{relative}: <{kind}> is missing its file attribute")
            continue
        child = normalize(raw, parent)
        if child is not None:
            queue.append(child)

if errors:
    print("Manifest validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

lua_count = sum(path.suffix.lower() == ".lua" for path in visited)
xml_count = sum(path.suffix.lower() == ".xml" for path in visited)
print(f"Manifest validation passed: {lua_count} Lua and {xml_count} XML load-graph entries")
PY
