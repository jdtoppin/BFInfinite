#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check-af-integration.py"
SPEC = importlib.util.spec_from_file_location("check_af_integration", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECKER
SPEC.loader.exec_module(CHECKER)


class AbstractFrameworkIntegrationPolicyTest(unittest.TestCase):
    def write_lock(
        self,
        root: Path,
        revision: str = "a" * 40,
        version: str = "r43",
        repository: str = "jdtoppin/AbstractFramework",
    ) -> Path:
        path = root / "abstract-framework.lock"
        path.write_text(
            f"repository={repository}\n"
            f"revision={revision}\n"
            f"version={version}\n",
            encoding="utf-8",
        )
        return path

    def write_contract(
        self,
        root: Path,
        bootstrap_version: int = 43,
        runtime_version: int = 43,
        af_version: str = "r43",
        dependencies: str = "AbstractFramework",
        enforce_runtime_version: bool = True,
    ) -> tuple[Path, Path]:
        bfi = root / "bfi"
        af = root / "af"
        bfi.mkdir()
        af.mkdir()
        (bfi / "BFInfinite.toc").write_text(
            f"## Dependencies: {dependencies}\n", encoding="utf-8"
        )
        (bfi / "Init.lua").write_text(
            f"BFI.requiredAFVersion = {bootstrap_version}\n",
            encoding="utf-8",
        )
        enforcement = (
            "AF.RequireVersion(REQUIRED_AF_VERSION)\n"
            if enforce_runtime_version
            else ""
        )
        (bfi / "Core.lua").write_text(
            f"local REQUIRED_AF_VERSION = {runtime_version}\n{enforcement}",
            encoding="utf-8",
        )
        (af / "AbstractFramework.toc").write_text(
            f"## Version: {af_version}\n",
            encoding="utf-8",
        )
        return bfi, af

    def test_repository_lock_is_valid(self) -> None:
        lock = CHECKER.parse_lock(REPO_ROOT / ".github" / "abstract-framework.lock")
        self.assertEqual(lock.repository, "jdtoppin/AbstractFramework")
        self.assertRegex(lock.revision, r"^[0-9a-f]{40}$")
        self.assertRegex(lock.version, r"^r[1-9][0-9]*$")

    def test_valid_lock_and_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root)
            CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_floating_revision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_lock(Path(directory), revision="main")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "full lowercase"):
                CHECKER.parse_lock(path)

    def test_wrong_repository_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_lock(Path(directory), repository="example/AbstractFramework")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "repository must be"):
                CHECKER.parse_lock(path)

    def test_wrong_checkout_revision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root)
            with self.assertRaisesRegex(CHECKER.IntegrationError, "expected locked revision"):
                CHECKER.validate_source_contract(bfi, af, lock, "b" * 40)

    def test_optional_dependency_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root)
            (bfi / "BFInfinite.toc").write_text(
                "## OptionalDeps: AbstractFramework\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "Dependencies"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_additional_dependency_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(
                root, dependencies="AbstractFramework, SomeOtherAddon"
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "exactly"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_unsatisfied_required_version_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(
                root,
                bootstrap_version=44,
                runtime_version=44,
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "does not satisfy"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_af_toc_version_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root, af_version="r44")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "expected locked version"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_bootstrap_requirement_may_be_lower_than_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root, bootstrap_version=42)
            CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_bootstrap_requirement_cannot_exceed_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(
                root,
                bootstrap_version=44,
                runtime_version=43,
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "cannot exceed"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_missing_runtime_enforcement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root, enforce_runtime_version=False)
            with self.assertRaisesRegex(CHECKER.IntegrationError, "must enforce"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_commented_or_quoted_runtime_enforcement_is_rejected(self) -> None:
        decoys = {
            "line comment": "-- AF.RequireVersion(REQUIRED_AF_VERSION)\n",
            "block comment": "--[[\nAF.RequireVersion(REQUIRED_AF_VERSION)\n]]\n",
            "long string": "local message = [[\nAF.RequireVersion(REQUIRED_AF_VERSION)\n]]\n",
            "quoted string": 'local message = "AF.RequireVersion(REQUIRED_AF_VERSION)"\n',
        }
        for label, decoy in decoys.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                lock = CHECKER.parse_lock(self.write_lock(root))
                bfi, af = self.write_contract(root)
                (bfi / "Core.lua").write_text(
                    f"local REQUIRED_AF_VERSION = 43\n{decoy}",
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(CHECKER.IntegrationError, "must enforce"):
                    CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)


if __name__ == "__main__":
    unittest.main()
