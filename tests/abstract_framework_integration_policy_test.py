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
        version: str = "r29",
    ) -> Path:
        path = root / "abstract-framework.lock"
        path.write_text(
            "repository=jdtoppin/AbstractFramework\n"
            f"revision={revision}\n"
            f"version={version}\n",
            encoding="utf-8",
        )
        return path

    def write_contract(
        self,
        root: Path,
        bootstrap_version: int = 29,
        runtime_version: int = 29,
        af_version: str = "r29",
    ) -> tuple[Path, Path]:
        bfi = root / "bfi"
        af = root / "af"
        bfi.mkdir()
        af.mkdir()
        (bfi / "BFInfinite.toc").write_text(
            "## Dependencies: AbstractFramework\n", encoding="utf-8"
        )
        (bfi / "Init.lua").write_text(
            f"BFI.requiredAFVersion = {bootstrap_version}\n",
            encoding="utf-8",
        )
        (bfi / "Core.lua").write_text(
            f"local REQUIRED_AF_VERSION = {runtime_version}\n"
            "AF.RequireVersion(REQUIRED_AF_VERSION)\n",
            encoding="utf-8",
        )
        (af / "AbstractFramework.toc").write_text(
            f"## Version: {af_version}\n",
            encoding="utf-8",
        )
        return bfi, af

    def test_valid_lock_and_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root)
            CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_floating_revision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_lock(Path(directory), "main")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "full lowercase"):
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

    def test_unsatisfied_required_version_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root, bootstrap_version=30, runtime_version=30)
            with self.assertRaisesRegex(CHECKER.IntegrationError, "does not satisfy"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_af_toc_version_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root, af_version="r30")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "expected locked version"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_bootstrap_requirement_may_be_lower_than_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root, version="r36"))
            bfi, af = self.write_contract(
                root,
                bootstrap_version=29,
                runtime_version=36,
                af_version="r36",
            )
            CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_bootstrap_requirement_cannot_exceed_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root, version="r36"))
            bfi, af = self.write_contract(
                root,
                bootstrap_version=36,
                runtime_version=29,
                af_version="r36",
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "cannot exceed"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)


if __name__ == "__main__":
    unittest.main()
