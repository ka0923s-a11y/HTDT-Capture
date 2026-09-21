from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import unicodedata
import warnings
import zipfile

from tools.bundle_validator.archive_bundle import create_archive
from tools.bundle_validator.validator import (
    ValidationError,
    canonical_json_bytes,
    validate_bundle,
    validate_relative_path,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "samples" / "minimal-capture"
EXPECTED_DIGEST = "1e29f755ce8f3557de60fa45f2c01a81936d3eca8db510cae795ba58170f035f"


class ValidatorTests(unittest.TestCase):
    def test_minimal_fixture_validates(self):
        report = validate_bundle(FIXTURE)
        self.assertTrue(report["valid"])
        self.assertEqual(report["bundle_digest"], EXPECTED_DIGEST)
        self.assertEqual(report["payload_count"], 4)

    def test_canonical_json_vector(self):
        value = {"z": None, "é": True, "a": 1}
        self.assertEqual(
            canonical_json_bytes(value),
            '{"a":1,"z":null,"é":true}'.encode("utf-8"),
        )

    def test_canonical_json_rejects_float_and_non_nfc(self):
        with self.assertRaises(ValidationError):
            canonical_json_bytes({"a": 1.5})
        with self.assertRaises(ValidationError):
            canonical_json_bytes({"name": "e\u0301"})

    def test_unsafe_paths_rejected(self):
        for path in ("../x", "/abs", "a/../b", "a\\b", "a//b", "./x"):
            with self.subTest(path=path):
                with self.assertRaises(ValidationError):
                    validate_relative_path(path)

    def test_shared_path_collision_vectors(self):
        vector_path = (
            REPO_ROOT
            / "schemas"
            / "capture-bundle-v1"
            / "path-collision-vectors.json"
        )
        document = json.loads(vector_path.read_text(encoding="utf-8"))
        for vector in document["vectors"]:
            with self.subTest(vector=vector):
                left = unicodedata.normalize("NFC", vector["left"]).casefold()
                right = unicodedata.normalize("NFC", vector["right"]).casefold()
                self.assertEqual(left, vector["collision_key"])
                self.assertEqual(right, vector["collision_key"])

    def test_tampered_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            target.write_bytes(target.read_bytes() + b" ")
            with self.assertRaisesRegex(ValidationError, "byte length mismatch|SHA-256 mismatch"):
                validate_bundle(dest)

    def test_undeclared_file_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            (dest / "extra.txt").write_text("undeclared", encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "declared/present payload mismatch"):
                validate_bundle(dest)

    def test_noncanonical_manifest_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "manifest.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            path.write_text(json.dumps(value, indent=2), encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "not Capture Bundle v1 canonical JSON"):
                validate_bundle(dest)

    def test_unknown_schema_version_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "manifest.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["schema_version"] = "2.0.0"
            path.write_bytes(canonical_json_bytes(value))
            with self.assertRaisesRegex(ValidationError, "unsupported schema version"):
                validate_bundle(dest)

    def test_malformed_manifest_timestamp_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "manifest.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["created_at"] = "not-a-dateTgarbageZ"
            path.write_bytes(canonical_json_bytes(value))
            with self.assertRaisesRegex(
                ValidationError,
                "UTC RFC3339",
            ):
                validate_bundle(dest)

    def test_fractional_utc_manifest_timestamp_validates(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "manifest.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            # Fixture created_at is 2026-09-20T00:00:00Z; keep the
            # fractional timestamp on finalized_at so the lifecycle
            # ordering invariant (finalized_at >= created_at) holds.
            value["finalized_at"] = "2026-09-20T12:34:56.123Z"
            path.write_bytes(canonical_json_bytes(value))

            # Manifest bytes changed, but no payload declaration/digest
            # depends on manifest bytes themselves.
            report = validate_bundle(dest)
            self.assertTrue(report["valid"])

    def test_shared_manifest_lifecycle_vectors(self):
        vector_path = (
            REPO_ROOT
            / "schemas"
            / "capture-bundle-v1"
            / "manifest-lifecycle-vectors.json"
        )
        document = json.loads(vector_path.read_text(encoding="utf-8"))
        self.assertTrue(document["vectors"])
        for vector in document["vectors"]:
            with self.subTest(vector=vector["name"]):
                with tempfile.TemporaryDirectory() as td:
                    dest = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, dest)
                    path = dest / "manifest.json"
                    value = json.loads(path.read_text(encoding="utf-8"))
                    value["created_at"] = vector["created_at"]
                    value["finalized_at"] = vector["finalized_at"]
                    path.write_bytes(canonical_json_bytes(value))
                    if vector["valid"]:
                        self.assertTrue(validate_bundle(dest)["valid"])
                    else:
                        with self.assertRaisesRegex(
                            ValidationError,
                            "finalized_at must not precede created_at",
                        ):
                            validate_bundle(dest)

    def test_finalized_before_created_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "manifest.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["created_at"] = "2026-09-20T00:00:01Z"
            value["finalized_at"] = "2026-09-20T00:00:00Z"
            path.write_bytes(canonical_json_bytes(value))
            with self.assertRaisesRegex(
                ValidationError,
                "finalized_at must not precede created_at",
            ):
                validate_bundle(dest)

    def test_hard_linked_payload_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            # Alias lives outside the bundle root: writing through it
            # would mutate the finalized inode from off-bundle.
            os.link(
                dest / "annotations" / "entities.json",
                Path(td) / "external-alias.bin",
            )
            with self.assertRaisesRegex(ValidationError, "hard-linked"):
                validate_bundle(dest)

    def test_hard_linked_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            os.link(
                dest / "manifest.json",
                Path(td) / "manifest-alias.json",
            )
            with self.assertRaisesRegex(ValidationError, "hard-linked"):
                validate_bundle(dest)

    def test_link_count_rejection_not_content_based(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            alias = Path(td) / "external-alias.bin"
            os.link(target, alias)
            with self.assertRaisesRegex(ValidationError, "hard-linked"):
                validate_bundle(dest)
            # Removing the extra directory entry restores st_nlink == 1;
            # unchanged bytes validate again, proving the check is the
            # inode link count rather than file content.
            alias.unlink()
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_zip_path_traversal_fails(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "bad.htdtcapture"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("../escape", b"x")
                zf.writestr("manifest.json", b"{}")
            with self.assertRaisesRegex(ValidationError, "unsafe bundle path"):
                validate_bundle(archive)

    def test_zip_case_collision_fails(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "bad.htdtcapture"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as zf:
                zf.writestr("A.txt", b"a")
                zf.writestr("a.txt", b"b")
                zf.writestr("manifest.json", b"{}")
            with self.assertRaisesRegex(ValidationError, "case/Unicode-colliding"):
                validate_bundle(archive)

    def test_zip_duplicate_entry_fails(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "bad.htdtcapture"
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as zf:
                    zf.writestr("x.txt", b"a")
                    zf.writestr("x.txt", b"b")
                    zf.writestr("manifest.json", b"{}")
            with self.assertRaisesRegex(ValidationError, "duplicate archive entry"):
                validate_bundle(archive)

    def test_archive_wrapper_preserves_logical_bundle_digest(self):
        source_report = validate_bundle(FIXTURE)
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "fixture.htdtcapture"
            archive_report = create_archive(FIXTURE, archive)
            self.assertTrue(archive.exists())
            self.assertEqual(
                archive_report["bundle_digest"],
                source_report["bundle_digest"],
            )
            self.assertEqual(
                validate_bundle(archive)["bundle_digest"],
                source_report["bundle_digest"],
            )

    def test_zip_high_compression_ratio_fails(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "bad.htdtcapture"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("bomb.bin", b"0" * (1024 * 1024))
                zf.writestr("manifest.json", b"{}")
            with self.assertRaisesRegex(ValidationError, "compression ratio exceeds"):
                validate_bundle(archive)


if __name__ == "__main__":
    unittest.main()
