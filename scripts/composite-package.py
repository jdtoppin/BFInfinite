#!/usr/bin/env python3
"""Assemble and verify a deterministic BFInfinite + AbstractFramework package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, FrozenSet, Iterable, List, Mapping, Optional, Sequence, Set, Tuple


FORMAT_NAME = "bfinfinite-abstractframework-composite"
SCHEMA_VERSION = 1
ROOTS = ("AbstractFramework", "BFInfinite")
TOCS = {
    "AbstractFramework": "AbstractFramework/AbstractFramework.toc",
    "BFInfinite": "BFInfinite/BFInfinite.toc",
}
FIXED_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
CHUNK_SIZE = 1024 * 1024
HEX_64 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
TOC_VERSION = re.compile(r"^##[ \t]*Version:[ \t]*(.*?)[ \t]*$")
BFI_DEPENDENCY_DECLARATION = re.compile(
    r"^##[ \t]*(?:Dependencies|RequiredDeps):"
)
BFI_DEPENDENCY_CONTRACT = re.compile(
    r"^##[ \t]*Dependencies:[ \t]*AbstractFramework[ \t]*$"
)

DEVELOPER_TOP_LEVEL = {
    "AbstractFramework": {
        "AGENTS.md",
        "CONTRIBUTING.md",
        "scripts",
        "tests",
    },
    "BFInfinite": {
        "AGENTS.md",
        "CONTRIBUTING.md",
        "RELEASE_NOTES.md",
        "docs",
        "scripts",
        "tests",
    },
}

DEVELOPER_PREFIXES = {
    "AbstractFramework": (
        "Libs/LibStub/tests",
        "Libs/LibDeflate/docs",
        "Libs/LibDeflate/examples",
    ),
    "BFInfinite": (),
}

DEVELOPER_EXACT_PATHS = {
    "AbstractFramework": {
        "Libs/LibStub/LibStub.toc",
        "Libs/LibDeflate/CONTRIBUTING.md",
        "Libs/LibDeflate/changelog.md",
        "Libs/LibDeflate/LibDeflate.toc",
        "Libs/LibDeflate/README.md",
        "Libs/LibCustomGlow-1.0/cspell.json",
        "Libs/LibCustomGlow-1.0/LibCustomGlow-1.0.toc",
        "Libs/LibCustomGlow-1.0/README.md",
        "Libs/LibDataBroker-1.1/README.textile",
    },
    "BFInfinite": {
        "Modules/Blizzard/Style/WorldMapFrame_Test.lua",
    },
}


class PackageError(Exception):
    """A composite package failed validation."""


@dataclass(frozen=True)
class FileFingerprint:
    size: int
    sha256: str


@dataclass(frozen=True)
class ArchiveInspection:
    path: Path
    roots: FrozenSet[str]
    directories: FrozenSet[str]
    files: Mapping[str, FileFingerprint]
    versions: Mapping[str, str]
    archive_sha256: str
    content_manifest_sha256: str


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _require_regular_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise PackageError(f"{label} is not a file: {path}")


def _validate_af_identity(repository: str, sha: str, version: str) -> Tuple[str, str, str]:
    if not repository or repository != repository.strip():
        raise PackageError("AF repository must be a non-empty value without surrounding whitespace")
    normalized_sha = sha.lower()
    if not GIT_SHA.fullmatch(normalized_sha):
        raise PackageError("AF SHA must be a full 40- or 64-character hexadecimal commit SHA")
    if not version or version != version.strip():
        raise PackageError("AF version must be a non-empty value without surrounding whitespace")
    return repository, normalized_sha, version


def _validate_member_path(name: str, allowed_roots: Set[str]) -> Tuple[str, Tuple[str, ...], bool]:
    if not name:
        raise PackageError("archive contains an empty ZIP path")
    if any(ord(character) < 32 or ord(character) == 127 for character in name):
        raise PackageError(f"unsafe ZIP path contains a control character: {name!r}")
    if "\\" in name:
        raise PackageError(f"unsafe ZIP path contains a backslash: {name}")
    if name.startswith("/"):
        raise PackageError(f"unsafe absolute ZIP path: {name}")

    is_directory = name.endswith("/")
    untrailed = name[:-1] if is_directory else name
    parts = tuple(untrailed.split("/"))
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise PackageError(f"unsafe non-canonical ZIP path: {name}")

    root = parts[0]
    if root not in allowed_roots:
        raise PackageError(f"ZIP entry is outside the allowed roots: {name}")
    if len(parts) == 1 and not is_directory:
        raise PackageError(f"top-level addon root is not a directory: {name}")

    relative_parts = parts[1:]
    if any(part.startswith(".") or part == "__pycache__" for part in relative_parts):
        raise PackageError(f"developer-only hidden path is present: {name}")
    if relative_parts and relative_parts[0] in DEVELOPER_TOP_LEVEL[root]:
        raise PackageError(f"developer-only path is present: {name}")
    if relative_parts and relative_parts[-1] in {"AGENTS.md", "CONTRIBUTING.md"}:
        raise PackageError(f"developer-only file is present: {name}")

    relative = "/".join(relative_parts)
    if relative in DEVELOPER_EXACT_PATHS[root]:
        raise PackageError(f"developer-only file is present: {name}")
    for prefix in DEVELOPER_PREFIXES[root]:
        if relative == prefix or relative.startswith(prefix + "/"):
            raise PackageError(f"developer-only path is present: {name}")

    return root, parts, is_directory


def _validate_member_type(info: zipfile.ZipInfo, is_directory: bool) -> None:
    if info.flag_bits & 0x1:
        raise PackageError(f"encrypted ZIP entries are not supported: {info.filename}")
    if is_directory and info.file_size != 0:
        raise PackageError(f"ZIP directory contains data: {info.filename}")

    file_type = stat.S_IFMT(info.external_attr >> 16)
    if file_type == stat.S_IFLNK:
        raise PackageError(f"symbolic links are not allowed: {info.filename}")
    if file_type not in (0, stat.S_IFREG, stat.S_IFDIR):
        raise PackageError(f"unsupported ZIP entry type: {info.filename}")
    if is_directory and file_type == stat.S_IFREG:
        raise PackageError(f"ZIP directory has regular-file attributes: {info.filename}")
    if not is_directory and file_type == stat.S_IFDIR:
        raise PackageError(f"ZIP file has directory attributes: {info.filename}")


def _parent_directories(name: str) -> Iterable[str]:
    parts = name.split("/")
    for index in range(1, len(parts)):
        yield "/".join(parts[:index]) + "/"


def _content_manifest_sha256(
    directories: Iterable[str], files: Mapping[str, FileFingerprint]
) -> str:
    digest = hashlib.sha256()
    for name in sorted(directories):
        digest.update(b"directory\0")
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
    for name in sorted(files):
        fingerprint = files[name]
        digest.update(b"file\0")
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(fingerprint.size).encode("ascii"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(fingerprint.sha256))
        digest.update(b"\0")
    return digest.hexdigest()


def _read_member_fingerprint(package: zipfile.ZipFile, info: zipfile.ZipInfo) -> FileFingerprint:
    digest = hashlib.sha256()
    size = 0
    with package.open(info, "r") as stream:
        while True:
            chunk = stream.read(CHUNK_SIZE)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
    if size != info.file_size:
        raise PackageError(
            f"ZIP member size changed while reading {info.filename}: expected {info.file_size}, got {size}"
        )
    return FileFingerprint(size=size, sha256=digest.hexdigest())


def _read_toc_version(package: zipfile.ZipFile, info: zipfile.ZipInfo) -> str:
    try:
        contents = package.read(info).decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise PackageError(f"TOC is not valid UTF-8: {info.filename}") from error
    versions = []
    for line in contents.splitlines():
        match = TOC_VERSION.fullmatch(line)
        if match is not None:
            versions.append(match.group(1))
    if len(versions) != 1 or not versions[0]:
        raise PackageError(f"TOC must contain exactly one non-empty Version field: {info.filename}")
    return versions[0]


def _validate_bfi_dependency_contract(
    package: zipfile.ZipFile, info: zipfile.ZipInfo
) -> None:
    try:
        contents = package.read(info).decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise PackageError(f"TOC is not valid UTF-8: {info.filename}") from error
    declarations = [
        line
        for line in contents.splitlines()
        if BFI_DEPENDENCY_DECLARATION.match(line) is not None
    ]
    if (
        len(declarations) != 1
        or BFI_DEPENDENCY_CONTRACT.fullmatch(declarations[0]) is None
    ):
        raise PackageError(
            "BFInfinite/BFInfinite.toc must contain exactly one "
            "'## Dependencies: AbstractFramework' declaration"
        )


def inspect_archive(path: Path, expected_roots: Iterable[str]) -> ArchiveInspection:
    expected = set(expected_roots)
    if not expected or not expected.issubset(set(ROOTS)):
        raise ValueError("expected roots must be a non-empty subset of the supported roots")
    _require_regular_file(path, "Package")

    archive_sha256 = _sha256_file(path)
    directories: Set[str] = set()
    file_infos: Dict[str, zipfile.ZipInfo] = {}
    roots: Set[str] = set()
    exact_names: Set[str] = set()
    canonical_paths: Dict[str, Tuple[str, bool]] = {}

    try:
        with zipfile.ZipFile(path, "r") as package:
            for info in package.infolist():
                name = info.filename
                if name in exact_names:
                    raise PackageError(f"duplicate ZIP path: {name}")
                exact_names.add(name)

                root, parts, is_directory = _validate_member_path(name, expected)
                _validate_member_type(info, is_directory)
                roots.add(root)

                for depth in range(1, len(parts) + 1):
                    canonical = "/".join(parts[:depth])
                    path_is_directory = depth < len(parts) or is_directory
                    folded = unicodedata.normalize("NFC", canonical).casefold()
                    previous = canonical_paths.get(folded)
                    if previous is not None and previous != (
                        canonical,
                        path_is_directory,
                    ):
                        raise PackageError(
                            "case-colliding, Unicode-colliding, or file/directory "
                            f"ZIP paths: {previous[0]} and {canonical}"
                        )
                    canonical_paths[folded] = (canonical, path_is_directory)

                if is_directory:
                    directories.add(canonical + "/")
                else:
                    file_infos[name] = info
                    directories.update(_parent_directories(name))

            if roots != expected:
                raise PackageError(
                    f"archive roots are {sorted(roots)}; expected exactly {sorted(expected)}"
                )

            file_names = set(file_infos)
            for file_name in sorted(file_names):
                parent = file_name.rsplit("/", 1)[0]
                while "/" in parent:
                    if parent in file_names:
                        raise PackageError(
                            f"ZIP file is also the parent of another entry: {parent}"
                        )
                    parent = parent.rsplit("/", 1)[0]

            for root in expected:
                toc = TOCS[root]
                if toc not in file_infos:
                    raise PackageError(f"required TOC is missing: {toc}")

            files = {
                name: _read_member_fingerprint(package, file_infos[name])
                for name in sorted(file_infos)
            }
            versions = {
                root: _read_toc_version(package, file_infos[TOCS[root]])
                for root in sorted(expected)
            }
            if "BFInfinite" in expected:
                _validate_bfi_dependency_contract(
                    package, file_infos[TOCS["BFInfinite"]]
                )
    except (zipfile.BadZipFile, NotImplementedError, RuntimeError) as error:
        if isinstance(error, PackageError):
            raise
        raise PackageError(f"invalid or unsupported ZIP archive {path}: {error}") from error

    manifest = _content_manifest_sha256(directories, files)
    return ArchiveInspection(
        path=path,
        roots=frozenset(roots),
        directories=frozenset(directories),
        files=files,
        versions=versions,
        archive_sha256=archive_sha256,
        content_manifest_sha256=manifest,
    )


def _canonical_zip_info(name: str, is_directory: bool) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(filename=name, date_time=FIXED_ZIP_TIMESTAMP)
    info.create_system = 3
    info.extra = b""
    info.comment = b""
    if is_directory:
        info.compress_type = zipfile.ZIP_STORED
        info.external_attr = ((stat.S_IFDIR | 0o755) << 16) | 0x10
    else:
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (stat.S_IFREG | 0o644) << 16
    return info


def _copy_member(
    source: zipfile.ZipFile,
    source_info: zipfile.ZipInfo,
    target: zipfile.ZipFile,
    target_info: zipfile.ZipInfo,
    expected: FileFingerprint,
) -> None:
    digest = hashlib.sha256()
    size = 0
    with source.open(source_info, "r") as reader:
        with target.open(target_info, "w", force_zip64=True) as writer:
            while True:
                chunk = reader.read(CHUNK_SIZE)
                if not chunk:
                    break
                writer.write(chunk)
                digest.update(chunk)
                size += len(chunk)
    actual = FileFingerprint(size=size, sha256=digest.hexdigest())
    if actual != expected:
        raise PackageError(f"input member changed while assembling: {source_info.filename}")


def _build_composite_zip(
    output: Path, bfi: ArchiveInspection, af: ArchiveInspection
) -> None:
    inspections = {
        "BFInfinite": bfi,
        "AbstractFramework": af,
    }
    directories = set(bfi.directories) | set(af.directories)
    files: Dict[str, Tuple[ArchiveInspection, FileFingerprint]] = {}
    for inspection in (bfi, af):
        for name, fingerprint in inspection.files.items():
            if name in files:
                raise PackageError(f"duplicate path across source packages: {name}")
            files[name] = (inspection, fingerprint)

    with zipfile.ZipFile(
        output,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        strict_timestamps=True,
    ) as target:
        sources = {
            root: zipfile.ZipFile(inspection.path, "r")
            for root, inspection in inspections.items()
        }
        try:
            entries = sorted(directories | set(files))
            for name in entries:
                if name in directories:
                    target.writestr(_canonical_zip_info(name, True), b"")
                    continue
                inspection, fingerprint = files[name]
                root = name.split("/", 1)[0]
                source = sources[root]
                _copy_member(
                    source,
                    source.getinfo(name),
                    target,
                    _canonical_zip_info(name, False),
                    fingerprint,
                )
        finally:
            for source in sources.values():
                source.close()


def _describe_content_difference(
    expected_directories: Set[str],
    expected_files: Mapping[str, FileFingerprint],
    actual: ArchiveInspection,
) -> str:
    actual_directories = set(actual.directories)
    missing_directories = sorted(expected_directories - actual_directories)
    extra_directories = sorted(actual_directories - expected_directories)
    missing_files = sorted(set(expected_files) - set(actual.files))
    extra_files = sorted(set(actual.files) - set(expected_files))
    changed_files = sorted(
        name
        for name in set(expected_files) & set(actual.files)
        if expected_files[name] != actual.files[name]
    )
    details = []
    for label, values in (
        ("missing directories", missing_directories),
        ("extra directories", extra_directories),
        ("missing files", missing_files),
        ("extra files", extra_files),
        ("changed files", changed_files),
    ):
        if values:
            suffix = " ..." if len(values) > 5 else ""
            details.append(f"{label}: {', '.join(values[:5])}{suffix}")
    return "; ".join(details) or "content differs"


def _verify_exact_union(
    composite: ArchiveInspection, bfi: ArchiveInspection, af: ArchiveInspection
) -> None:
    expected_directories = set(bfi.directories) | set(af.directories)
    expected_files: Dict[str, FileFingerprint] = dict(bfi.files)
    overlap = set(expected_files) & set(af.files)
    if overlap:
        raise PackageError(f"source packages overlap: {sorted(overlap)[0]}")
    expected_files.update(af.files)
    if (
        set(composite.directories) != expected_directories
        or dict(composite.files) != expected_files
    ):
        difference = _describe_content_difference(
            expected_directories, expected_files, composite
        )
        raise PackageError(f"composite archive is not the exact union of its inputs: {difference}")


def _reject_duplicate_json_keys(pairs: List[Tuple[str, object]]) -> Dict[str, object]:
    result: Dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise PackageError(f"provenance JSON contains a duplicate key: {key}")
        result[key] = value
    return result


def _load_provenance(path: Path) -> Mapping[str, object]:
    _require_regular_file(path, "Provenance")
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream, object_pairs_hook=_reject_duplicate_json_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PackageError(f"invalid provenance JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise PackageError("provenance JSON root must be an object")
    return value


def _expect_keys(value: object, keys: Set[str], label: str) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise PackageError(f"provenance {label} must be an object")
    actual = set(value)
    if actual != keys:
        raise PackageError(
            f"provenance {label} keys are {sorted(actual)}; expected exactly {sorted(keys)}"
        )
    return value


def _provenance_document(
    composite: ArchiveInspection,
    bfi: ArchiveInspection,
    af: ArchiveInspection,
    repository: str,
    sha: str,
    version: str,
) -> Mapping[str, object]:
    return {
        "artifact": {
            "content_manifest_sha256": composite.content_manifest_sha256,
            "sha256": composite.archive_sha256,
            "top_level_roots": list(ROOTS),
        },
        "format": FORMAT_NAME,
        "inputs": {
            "AbstractFramework": {
                "archive_sha256": af.archive_sha256,
                "content_manifest_sha256": af.content_manifest_sha256,
                "repository": repository,
                "root": "AbstractFramework",
                "sha": sha,
                "version": version,
            },
            "BFInfinite": {
                "archive_sha256": bfi.archive_sha256,
                "content_manifest_sha256": bfi.content_manifest_sha256,
                "root": "BFInfinite",
                "version": bfi.versions["BFInfinite"],
            },
        },
        "schema_version": SCHEMA_VERSION,
    }


def _validate_hex_digest(value: object, label: str) -> str:
    if not isinstance(value, str) or not HEX_64.fullmatch(value):
        raise PackageError(f"provenance {label} must be a lowercase SHA-256 digest")
    return value


def _validate_provenance(
    document: Mapping[str, object],
    composite: ArchiveInspection,
    bfi: ArchiveInspection,
    af: ArchiveInspection,
    repository: str,
    sha: str,
    version: str,
) -> None:
    top = _expect_keys(
        document, {"artifact", "format", "inputs", "schema_version"}, "root"
    )
    if top["format"] != FORMAT_NAME or top["schema_version"] != SCHEMA_VERSION:
        raise PackageError("provenance format or schema version is unsupported")

    artifact = _expect_keys(
        top["artifact"],
        {"content_manifest_sha256", "sha256", "top_level_roots"},
        "artifact",
    )
    if artifact["top_level_roots"] != list(ROOTS):
        raise PackageError("provenance artifact roots are not the canonical two roots")
    if _validate_hex_digest(artifact["sha256"], "artifact.sha256") != composite.archive_sha256:
        raise PackageError("provenance artifact SHA-256 does not match the composite archive")
    if (
        _validate_hex_digest(
            artifact["content_manifest_sha256"], "artifact.content_manifest_sha256"
        )
        != composite.content_manifest_sha256
    ):
        raise PackageError("provenance artifact content manifest does not match")

    inputs = _expect_keys(top["inputs"], set(ROOTS), "inputs")
    af_data = _expect_keys(
        inputs["AbstractFramework"],
        {
            "archive_sha256",
            "content_manifest_sha256",
            "repository",
            "root",
            "sha",
            "version",
        },
        "inputs.AbstractFramework",
    )
    bfi_data = _expect_keys(
        inputs["BFInfinite"],
        {"archive_sha256", "content_manifest_sha256", "root", "version"},
        "inputs.BFInfinite",
    )

    if af_data["root"] != "AbstractFramework" or bfi_data["root"] != "BFInfinite":
        raise PackageError("provenance input roots are incorrect")
    if af_data["repository"] != repository:
        raise PackageError("provenance AF repository does not match the expected repository")
    if af_data["sha"] != sha:
        raise PackageError("provenance AF SHA does not match the expected commit")
    if af_data["version"] != version:
        raise PackageError("provenance AF version does not match the expected version")
    if bfi_data["version"] != bfi.versions["BFInfinite"]:
        raise PackageError("provenance BFInfinite version does not match its TOC")

    comparisons = (
        (af_data["archive_sha256"], af.archive_sha256, "AF archive SHA-256"),
        (
            af_data["content_manifest_sha256"],
            af.content_manifest_sha256,
            "AF content manifest",
        ),
        (bfi_data["archive_sha256"], bfi.archive_sha256, "BFInfinite archive SHA-256"),
        (
            bfi_data["content_manifest_sha256"],
            bfi.content_manifest_sha256,
            "BFInfinite content manifest",
        ),
    )
    for recorded, actual, label in comparisons:
        if _validate_hex_digest(recorded, label) != actual:
            raise PackageError(f"provenance {label} does not match its input package")


def _assert_af_version(af: ArchiveInspection, version: str) -> None:
    packaged_version = af.versions["AbstractFramework"]
    if packaged_version != version:
        raise PackageError(
            f"AF version {version!r} does not match packaged TOC version {packaged_version!r}"
        )


def _ensure_paths_do_not_alias(paths: Sequence[Tuple[str, Path]]) -> None:
    resolved: Dict[Path, str] = {}
    for label, path in paths:
        canonical = path.resolve()
        previous = resolved.get(canonical)
        if previous is not None:
            raise PackageError(f"{label} aliases {previous}: {path}")
        for other, other_label in resolved.items():
            if canonical in other.parents or other in canonical.parents:
                raise PackageError(
                    f"{label} is nested with {other_label}: {path} and {other}"
                )
        resolved[canonical] = label


def _require_output_absent(path: Path, label: str) -> None:
    if path.exists() or path.is_symlink():
        raise PackageError(f"refusing to overwrite existing {label}: {path}")


def _temporary_path(destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=str(destination.parent)
    )
    os.close(descriptor)
    return Path(name)


def _write_json(path: Path, document: Mapping[str, object]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(document, stream, indent=2, sort_keys=True, ensure_ascii=False)
        stream.write("\n")


def _inspect_sources(
    bfi_path: Path, af_path: Path, af_version: str
) -> Tuple[ArchiveInspection, ArchiveInspection]:
    bfi = inspect_archive(bfi_path, {"BFInfinite"})
    af = inspect_archive(af_path, {"AbstractFramework"})
    _assert_af_version(af, af_version)
    return bfi, af


def assemble_composite(
    bfi_path: Path,
    af_path: Path,
    output_path: Path,
    provenance_path: Path,
    repository: str,
    sha: str,
    version: str,
) -> None:
    repository, sha, version = _validate_af_identity(repository, sha, version)
    _ensure_paths_do_not_alias(
        (
            ("BFInfinite input", bfi_path),
            ("AbstractFramework input", af_path),
            ("composite output", output_path),
            ("provenance output", provenance_path),
        )
    )
    _require_output_absent(output_path, "composite output")
    _require_output_absent(provenance_path, "provenance output")
    bfi, af = _inspect_sources(bfi_path, af_path, version)

    archive_temp = _temporary_path(output_path)
    provenance_temp = _temporary_path(provenance_path)
    try:
        _build_composite_zip(archive_temp, bfi, af)
        composite = inspect_archive(archive_temp, set(ROOTS))
        _verify_exact_union(composite, bfi, af)
        if _sha256_file(bfi_path) != bfi.archive_sha256:
            raise PackageError("BFInfinite input changed while assembling")
        if _sha256_file(af_path) != af.archive_sha256:
            raise PackageError("AbstractFramework input changed while assembling")

        document = _provenance_document(
            composite, bfi, af, repository, sha, version
        )
        _write_json(provenance_temp, document)
        _validate_provenance(
            _load_provenance(provenance_temp),
            composite,
            bfi,
            af,
            repository,
            sha,
            version,
        )

        os.replace(archive_temp, output_path)
        try:
            os.replace(provenance_temp, provenance_path)
        except OSError:
            output_path.unlink(missing_ok=True)
            raise
    finally:
        archive_temp.unlink(missing_ok=True)
        provenance_temp.unlink(missing_ok=True)


def check_composite(
    bfi_path: Path,
    af_path: Path,
    archive_path: Path,
    provenance_path: Path,
    repository: str,
    sha: str,
    version: str,
) -> None:
    repository, sha, version = _validate_af_identity(repository, sha, version)
    _ensure_paths_do_not_alias(
        (
            ("BFInfinite input", bfi_path),
            ("AbstractFramework input", af_path),
            ("composite archive", archive_path),
            ("provenance", provenance_path),
        )
    )
    bfi, af = _inspect_sources(bfi_path, af_path, version)
    composite = inspect_archive(archive_path, set(ROOTS))
    _verify_exact_union(composite, bfi, af)
    document = _load_provenance(provenance_path)
    _validate_provenance(
        document, composite, bfi, af, repository, sha, version
    )


def _add_source_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--bfinfinite-package", required=True, type=Path)
    parser.add_argument("--abstract-framework-package", required=True, type=Path)
    parser.add_argument("--af-repository", required=True)
    parser.add_argument("--af-sha", required=True)
    parser.add_argument("--af-version", required=True)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    assemble = subparsers.add_parser(
        "assemble", help="build a deterministic composite ZIP and provenance JSON"
    )
    _add_source_arguments(assemble)
    assemble.add_argument("--output", required=True, type=Path)
    assemble.add_argument("--provenance", required=True, type=Path)

    check = subparsers.add_parser(
        "check", help="validate a composite ZIP against both immutable inputs"
    )
    _add_source_arguments(check)
    check.add_argument("--archive", required=True, type=Path)
    check.add_argument("--provenance", required=True, type=Path)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "assemble":
            assemble_composite(
                args.bfinfinite_package,
                args.abstract_framework_package,
                args.output,
                args.provenance,
                args.af_repository,
                args.af_sha,
                args.af_version,
            )
            print(f"Composite package assembled: {args.output}")
            print(f"Provenance written: {args.provenance}")
        else:
            check_composite(
                args.bfinfinite_package,
                args.abstract_framework_package,
                args.archive,
                args.provenance,
                args.af_repository,
                args.af_sha,
                args.af_version,
            )
            print(f"Composite package validation passed: {args.archive}")
    except (PackageError, OSError) as error:
        print(f"composite package error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
