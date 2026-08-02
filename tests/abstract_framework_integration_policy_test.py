#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import subprocess
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
    def write_lock(self, root: Path, revision: str = "a" * 40) -> Path:
        path = root / "abstract-framework.lock"
        path.write_text(
            "repository=jdtoppin/AbstractFramework\n"
            f"revision={revision}\n"
            "version=r29\n",
            encoding="utf-8",
        )
        return path

    def write_contract(self, root: Path) -> tuple[Path, Path]:
        bfi = root / "bfi"
        af = root / "af"
        bfi.mkdir()
        af.mkdir()
        (bfi / "BFInfinite.toc").write_text(
            "## Dependencies: AbstractFramework\n", encoding="utf-8"
        )
        (bfi / "Init.lua").write_text("BFI.requiredAFVersion = 29\n", encoding="utf-8")
        (bfi / "Core.lua").write_text(
            "local REQUIRED_AF_VERSION = 29\nAF.RequireVersion(REQUIRED_AF_VERSION)\n",
            encoding="utf-8",
        )
        (af / "AbstractFramework.toc").write_text("## Version: r29\n", encoding="utf-8")
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
            bfi, af = self.write_contract(root)
            (bfi / "Init.lua").write_text("BFI.requiredAFVersion = 30\n", encoding="utf-8")
            (bfi / "Core.lua").write_text(
                "local REQUIRED_AF_VERSION = 30\nAF.RequireVersion(REQUIRED_AF_VERSION)\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(CHECKER.IntegrationError, "does not satisfy"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_af_toc_version_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = CHECKER.parse_lock(self.write_lock(root))
            bfi, af = self.write_contract(root)
            (af / "AbstractFramework.toc").write_text("## Version: r30\n", encoding="utf-8")
            with self.assertRaisesRegex(CHECKER.IntegrationError, "expected locked version"):
                CHECKER.validate_source_contract(bfi, af, lock, "a" * 40)

    def test_missing_texture_callback_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            texture = Path(directory) / "Texture.lua"
            texture.write_text("local AF = select(2, ...)\nAF.placeholder = true\n", encoding="utf-8")
            result = subprocess.run(
                [
                    CHECKER.find_lua(),
                    str(REPO_ROOT / "tests" / "abstract_framework_texture_contract.lua"),
                    str(texture),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("loaded aura texcoord callback", result.stderr)


if __name__ == "__main__":
    unittest.main()
