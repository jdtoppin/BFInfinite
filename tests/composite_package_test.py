#!/usr/bin/env python3
"""Focused tests for the deterministic composite package assembler."""

from __future__ import annotations

import hashlib
import json
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "scripts" / "composite-package.py"
AF_REPOSITORY = "https://github.com/jdtoppin/AbstractFramework"
AF_SHA = "0123456789abcdef0123456789abcdef01234567"
AF_VERSION = "r43"

Entry = Tuple[str, bytes, Optional[int]]


def write_zip(path: Path, entries: Iterable[Entry]) -> None:
    members: List[Entry] = list(entries)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for index, (name, contents, mode) in enumerate(members):
                info = zipfile.ZipInfo(name, (2026, 8, 25, 12, 0, index * 2))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                if mode is None:
                    mode = stat.S_IFREG | 0o644
                info.external_attr = mode << 16
                archive.writestr(info, contents)


def standard_bfi_entries() -> List[Entry]:
    return [
        (
            "BFInfinite/BFInfinite.toc",
            b"## Version: r6-alpha\r\n## Dependencies: AbstractFramework\r\nInit.lua\r\n",
            None,
        ),
        ("BFInfinite/Init.lua", b"local addonName = ...\n", None),
        ("BFInfinite/Media/icon.tga", b"BFI media\x00", None),
    ]


def standard_af_entries() -> List[Entry]:
    return [
        (
            "AbstractFramework/AbstractFramework.toc",
            f"## Version: {AF_VERSION}\r\nInit.lua\r\n".encode("utf-8"),
            None,
        ),
        ("AbstractFramework/Init.lua", b"local addonName = ...\n", None),
        ("AbstractFramework/README.md", b"AbstractFramework\n", None),
    ]


class CompositePackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.bfi = self.directory / "BFInfinite.zip"
        self.af = self.directory / "AbstractFramework.zip"
        self.output = self.directory / "BFInfinite-Complete.zip"
        self.provenance = self.directory / "BFInfinite-Complete.provenance.json"
        write_zip(self.bfi, standard_bfi_entries())
        write_zip(self.af, standard_af_entries())

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_tool(self, command: str, **overrides: object) -> subprocess.CompletedProcess[str]:
        values = {
            "bfinfinite_package": self.bfi,
            "abstract_framework_package": self.af,
            "af_repository": AF_REPOSITORY,
            "af_sha": AF_SHA,
            "af_version": AF_VERSION,
            "output": self.output,
            "archive": self.output,
            "provenance": self.provenance,
        }
        values.update(overrides)
        arguments = [
            sys.executable,
            str(TOOL),
            command,
            "--bfinfinite-package",
            str(values["bfinfinite_package"]),
            "--abstract-framework-package",
            str(values["abstract_framework_package"]),
            "--af-repository",
            str(values["af_repository"]),
            "--af-sha",
            str(values["af_sha"]),
            "--af-version",
            str(values["af_version"]),
        ]
        if command == "assemble":
            arguments.extend(["--output", str(values["output"])])
        else:
            arguments.extend(["--archive", str(values["archive"])])
        arguments.extend(["--provenance", str(values["provenance"])])
        return subprocess.run(arguments, check=False, capture_output=True, text=True)

    def assemble_successfully(self, **overrides: object) -> None:
        result = self.run_tool("assemble", **overrides)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_assembles_exact_union_and_preserves_inputs(self) -> None:
        bfi_before = self.bfi.read_bytes()
        af_before = self.af.read_bytes()

        self.assemble_successfully()

        self.assertEqual(self.bfi.read_bytes(), bfi_before)
        self.assertEqual(self.af.read_bytes(), af_before)
        with zipfile.ZipFile(self.output) as archive:
            names = archive.namelist()
            roots = {name.rstrip("/").split("/", 1)[0] for name in names}
            self.assertEqual(roots, {"BFInfinite", "AbstractFramework"})
            files = {info.filename for info in archive.infolist() if not info.is_dir()}
            expected_files = {
                name for name, _, _ in standard_bfi_entries() + standard_af_entries()
            }
            self.assertEqual(files, expected_files)
            self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))
            self.assertEqual(archive.read("BFInfinite/Init.lua"), b"local addonName = ...\n")
            self.assertEqual(archive.read("AbstractFramework/README.md"), b"AbstractFramework\n")

        document = json.loads(self.provenance.read_text(encoding="utf-8"))
        af_data = document["inputs"]["AbstractFramework"]
        self.assertEqual(af_data["repository"], AF_REPOSITORY)
        self.assertEqual(af_data["sha"], AF_SHA)
        self.assertEqual(af_data["version"], AF_VERSION)
        self.assertEqual(
            document["artifact"]["sha256"],
            hashlib.sha256(self.output.read_bytes()).hexdigest(),
        )

        check = self.run_tool("check")
        self.assertEqual(check.returncode, 0, check.stderr)

    def test_output_and_provenance_are_deterministic(self) -> None:
        first_output = self.directory / "first.zip"
        first_provenance = self.directory / "first.json"
        second_output = self.directory / "second.zip"
        second_provenance = self.directory / "second.json"

        self.assemble_successfully(output=first_output, provenance=first_provenance)
        self.assemble_successfully(output=second_output, provenance=second_provenance)

        self.assertEqual(first_output.read_bytes(), second_output.read_bytes())
        self.assertEqual(first_provenance.read_bytes(), second_provenance.read_bytes())

    def test_rejects_duplicate_unsafe_and_wrong_root_paths(self) -> None:
        cases = {
            "duplicate": standard_bfi_entries()
            + [("BFInfinite/Init.lua", b"duplicate\n", None)],
            "traversal": standard_bfi_entries()
            + [("BFInfinite/../escape.lua", b"escape\n", None)],
            "backslash": standard_bfi_entries()
            + [("BFInfinite\\escape.lua", b"escape\n", None)],
            "wrong root": standard_bfi_entries()
            + [("Unexpected/file.lua", b"extra\n", None)],
        }
        for label, entries in cases.items():
            with self.subTest(label=label):
                write_zip(self.bfi, entries)
                before = self.bfi.read_bytes()
                result = self.run_tool("assemble")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("composite package error", result.stderr)
                self.assertEqual(self.bfi.read_bytes(), before)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.provenance.exists())

    def test_rejects_missing_toc_and_developer_only_files(self) -> None:
        cases = {
            "missing TOC": [
                ("BFInfinite/Init.lua", b"local addonName = ...\n", None)
            ],
            "developer tests": standard_bfi_entries()
            + [("BFInfinite/tests/fixture.lua", b"return true\n", None)],
            "developer hidden path": standard_bfi_entries()
            + [("BFInfinite/.github/workflows/package.yml", b"name: Package\n", None)],
        }
        for label, entries in cases.items():
            with self.subTest(label=label):
                write_zip(self.bfi, entries)
                result = self.run_tool("assemble")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.provenance.exists())

    def test_bfi_toc_requires_exactly_one_abstract_framework_dependency(self) -> None:
        invalid_tocs = {
            "missing": b"## Version: r6-alpha\r\nInit.lua\r\n",
            "wrong dependency": (
                b"## Version: r6-alpha\r\n"
                b"## Dependencies: AbstractFramework, AnotherAddon\r\n"
            ),
            "alias": (
                b"## Version: r6-alpha\r\n"
                b"## RequiredDeps: AbstractFramework\r\n"
            ),
            "duplicate": (
                b"## Version: r6-alpha\r\n"
                b"## Dependencies: AbstractFramework\r\n"
                b"## Dependencies: AbstractFramework\r\n"
            ),
        }
        for label, toc in invalid_tocs.items():
            with self.subTest(label=label):
                entries = standard_bfi_entries()
                entries[0] = ("BFInfinite/BFInfinite.toc", toc, None)
                write_zip(self.bfi, entries)
                result = self.run_tool("assemble")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "exactly one '## Dependencies: AbstractFramework'",
                    result.stderr,
                )
                self.assertFalse(self.output.exists())
                self.assertFalse(self.provenance.exists())

    def test_rejects_case_collisions_and_symbolic_links(self) -> None:
        write_zip(
            self.af,
            standard_af_entries()
            + [("AbstractFramework/init.lua", b"case collision\n", None)],
        )
        collision = self.run_tool("assemble")
        self.assertNotEqual(collision.returncode, 0)
        self.assertIn("case-colliding", collision.stderr)

        write_zip(
            self.af,
            standard_af_entries()
            + [
                (
                    "AbstractFramework/link.lua",
                    b"Init.lua",
                    stat.S_IFLNK | 0o777,
                )
            ],
        )
        symlink = self.run_tool("assemble")
        self.assertNotEqual(symlink.returncode, 0)
        self.assertIn("symbolic links", symlink.stderr)

    def test_rejects_colliding_inferred_parent_directories(self) -> None:
        cases = {
            "parent case collision": standard_bfi_entries()
            + [("BFInfinite/media/other.tga", b"other media\x00", None)],
            "file used as parent": standard_bfi_entries()
            + [("BFInfinite/Media", b"not a directory\n", None)],
            "parent Unicode collision": standard_bfi_entries()
            + [
                ("BFInfinite/Me\u0301dia/first.tga", b"first\x00", None),
                ("BFInfinite/M\u00e9dia/second.tga", b"second\x00", None),
            ],
        }
        for label, entries in cases.items():
            with self.subTest(label=label):
                write_zip(self.bfi, entries)
                result = self.run_tool("assemble")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("colliding", result.stderr)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.provenance.exists())

    def test_af_version_and_sha_must_match_provenance_inputs(self) -> None:
        wrong_version = self.run_tool("assemble", af_version="r42")
        self.assertNotEqual(wrong_version.returncode, 0)
        self.assertIn("does not match packaged TOC version", wrong_version.stderr)

        short_sha = self.run_tool("assemble", af_sha="abc1234")
        self.assertNotEqual(short_sha.returncode, 0)
        self.assertIn("full 40- or 64-character", short_sha.stderr)

    def test_checker_rejects_tampered_archive_and_provenance(self) -> None:
        self.assemble_successfully()
        with zipfile.ZipFile(self.output, "a") as archive:
            archive.writestr("Unexpected/file.lua", b"extra\n")
        tampered_archive = self.run_tool("check")
        self.assertNotEqual(tampered_archive.returncode, 0)
        self.assertIn("outside the allowed roots", tampered_archive.stderr)

        self.output.unlink()
        self.provenance.unlink()
        self.assemble_successfully()
        document = json.loads(self.provenance.read_text(encoding="utf-8"))
        document["inputs"]["AbstractFramework"]["sha"] = "f" * 40
        self.provenance.write_text(
            json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        tampered_provenance = self.run_tool("check")
        self.assertNotEqual(tampered_provenance.returncode, 0)
        self.assertIn("AF SHA does not match", tampered_provenance.stderr)

    def test_refuses_to_overwrite_an_input_archive(self) -> None:
        before = self.bfi.read_bytes()
        result = self.run_tool("assemble", output=self.bfi)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("aliases", result.stderr)
        self.assertEqual(self.bfi.read_bytes(), before)

    def test_rejects_existing_destination_without_partial_publish(self) -> None:
        self.provenance.mkdir()
        result = self.run_tool("assemble")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite existing provenance output", result.stderr)
        self.assertFalse(self.output.exists())
        self.assertTrue(self.provenance.is_dir())


if __name__ == "__main__":
    unittest.main()
