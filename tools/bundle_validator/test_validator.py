from __future__ import annotations

import copy
import hashlib
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
from tools.bundle_validator.schema_eval import (
    SchemaError,
    check_schema,
    validate as schema_validate,
)
from tools.bundle_validator.binary_formats import (
    BinaryFormatError,
    validate_confidencebin,
    validate_depthbin,
    validate_meshbin,
    validate_pixelbin,
)
from tools.bundle_validator.validator import (
    SCHEMA_DIR,
    DirectorySource,
    ValidationError,
    canonical_json_bytes,
    canonical_payload_json_bytes,
    validate_bundle,
    validate_relative_path,
    validate_uuid4,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "samples" / "minimal-capture"
EXPECTED_DIGEST = "85bb8e7b2f5b4ba4245f2c8fa89efbac0ad97e72cc0043b057d4ea5b7cd7e185"


def _rewrite_manifest(dest: Path, mutate):
    """Apply ``mutate`` to the manifest document and re-store canonical bytes."""
    manifest_path = dest / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    mutate(manifest)
    manifest_path.write_bytes(canonical_json_bytes(manifest))


def _rewrite_payload(dest: Path, rel_path: str, data: bytes):
    """Replace a payload and repair its manifest length/SHA-256 commitment."""
    (dest / rel_path).write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()

    def fix(manifest):
        for entry in manifest["files"]:
            if entry["path"] == rel_path:
                entry["bytes"] = len(data)
                entry["sha256"] = digest

    _rewrite_manifest(dest, fix)


def _meshbin(vertices, face_indices, normals=None, classifications=None):
    """Encode a v1 HTDTMSH1 payload mirroring MeshBinaryCodec.encode."""
    import struct as _struct

    flags = (1 if normals is not None else 0) | (
        2 if classifications is not None else 0
    )
    out = bytearray(b"HTDTMSH1")
    out += _struct.pack("<HHI", 1, 0, 32)
    out += _struct.pack("<II", len(vertices), len(face_indices) // 3)
    out += bytes([4, flags]) + b"\x00\x00" + b"\x00" * 4
    for vertex in vertices:
        out += _struct.pack("<fff", *vertex)
    if normals is not None:
        for normal in normals:
            out += _struct.pack("<fff", *normal)
    for index in face_indices:
        out += _struct.pack("<I", index)
    if classifications is not None:
        out += bytes(classifications)
    return bytes(out)


def _depthbin(width, height, values, validity=None):
    import struct as _struct

    flags = 1 if validity is not None else 0
    out = bytearray(b"HTDTDPT1")
    out += _struct.pack("<HHI", 1, 0, 32)
    out += _struct.pack("<II", width, height)
    out += bytes([1, flags]) + b"\x00\x00" + b"\x00" * 4
    for value in values:
        out += _struct.pack("<f", value)
    if validity is not None:
        out += bytes(validity)
    return bytes(out)


def _confidencebin(width, height, values):
    import struct as _struct

    out = bytearray(b"HTDTCNF1")
    out += _struct.pack("<HHI", 1, 0, 32)
    out += _struct.pack("<II", width, height)
    out += bytes([1, 0]) + b"\x00\x00" + b"\x00" * 4
    out += bytes(values)
    return bytes(out)


def _pixelbin(width, height, fourcc, planes):
    """planes: list of (width, height, source_bpr, packed_bpr, bytes)."""
    import struct as _struct

    header = 32 + len(planes) * 24
    out = bytearray(b"HTDTPXL1")
    out += _struct.pack("<HHI", 1, 0, header)
    out += _struct.pack("<III", width, height, fourcc)
    out += _struct.pack("<HH", len(planes), 0)
    offset = header
    for pw, ph, sbpr, pbpr, payload in planes:
        out += _struct.pack("<IIIIII", pw, ph, sbpr, pbpr, offset, len(payload))
        offset += len(payload)
    for _, _, _, _, payload in planes:
        out += payload
    return bytes(out)


class ValidatorTests(unittest.TestCase):
    def test_minimal_fixture_validates(self):
        report = validate_bundle(FIXTURE)
        self.assertTrue(report["valid"])
        self.assertEqual(report["bundle_digest"], EXPECTED_DIGEST)
        self.assertEqual(report["payload_count"], 8)

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


class ManifestBoundTests(unittest.TestCase):
    """Issue #141: manifest.json has a dedicated sub-file byte bound."""

    def test_oversized_manifest_directory_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            manifest = json.loads(
                (dest / "manifest.json").read_text(encoding="utf-8")
            )
            # Padding cannot be smuggled through a manifest key (the key
            # contract forbids extras), so grow the files array beyond the
            # declared bound instead of appending raw bytes.
            filler = {
                "path": "filler/pad.bin",
                "bytes": 0,
                "media_type": "application/octet-stream",
                "sha256": "0" * 64,
                "producer": "x",
                "provenance_class": "capture_app_derived",
                "role": "derived",
            }
            entry_size = len(canonical_json_bytes(filler)) + 1
            needed = (8 * 1024 * 1024) // entry_size + 10
            manifest["files"].extend(dict(filler) for _ in range(needed))
            manifest_bytes = canonical_json_bytes(manifest)
            self.assertGreater(len(manifest_bytes), 8 * 1024 * 1024)
            (dest / "manifest.json").write_bytes(manifest_bytes)
            with self.assertRaisesRegex(ValidationError, "exceeds"):
                validate_bundle(dest)

    def test_oversized_manifest_archive_rejected_from_header(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "big.htdtcapture"
            big_manifest = b'{"files": "' + b"0" * (9 * 1024 * 1024) + b'"}'
            with zipfile.ZipFile(
                archive, "w", compression=zipfile.ZIP_STORED
            ) as zf:
                zf.writestr("manifest.json", big_manifest)
            with self.assertRaisesRegex(
                ValidationError, "manifest.*exceeds|exceeds.*manifest"
            ):
                validate_bundle(archive)

    def test_manifest_bound_far_below_file_bound(self):
        from tools.bundle_validator.validator import (
            MAX_FILE_BYTES,
            MAX_MANIFEST_BYTES,
        )

        self.assertLessEqual(MAX_MANIFEST_BYTES, 16 * 1024 * 1024)
        self.assertLess(MAX_MANIFEST_BYTES, MAX_FILE_BYTES // 8)


class RevisionAncestryTests(unittest.TestCase):
    """Issue #144: a revision cannot be its own parent."""

    def test_self_parent_revision_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)

            def mutate(manifest):
                manifest["parent_revision_id"] = manifest[
                    "capture_revision_id"
                ]

            _rewrite_manifest(dest, mutate)
            with self.assertRaisesRegex(
                ValidationError, "parent_revision_id must differ"
            ):
                validate_bundle(dest)

    def test_distinct_parent_revision_passes(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)

            def mutate(manifest):
                manifest["parent_revision_id"] = (
                    "00000000-0000-4000-8000-00000000000a"
                )

            _rewrite_manifest(dest, mutate)
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_shared_revision_vectors(self):
        vector_path = (
            REPO_ROOT
            / "schemas"
            / "capture-bundle-v1"
            / "manifest-revision-vectors.json"
        )
        document = json.loads(vector_path.read_text(encoding="utf-8"))
        self.assertTrue(document["vectors"])
        for vector in document["vectors"]:
            with self.subTest(vector=vector["name"]):
                with tempfile.TemporaryDirectory() as td:
                    dest = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, dest)

                    def mutate(manifest, vector=vector):
                        manifest["capture_revision_id"] = vector[
                            "capture_revision_id"
                        ]
                        manifest["parent_revision_id"] = vector[
                            "parent_revision_id"
                        ]

                    _rewrite_manifest(dest, mutate)
                    if vector["valid"]:
                        self.assertTrue(validate_bundle(dest)["valid"])
                    else:
                        with self.assertRaisesRegex(
                            ValidationError, "parent_revision_id"
                        ):
                            validate_bundle(dest)

    def test_shared_identifier_vectors(self):
        vector_path = (
            REPO_ROOT
            / "schemas"
            / "capture-bundle-v1"
            / "identifier-vectors.json"
        )
        document = json.loads(vector_path.read_text(encoding="utf-8"))
        self.assertTrue(document["vectors"])
        for vector in document["vectors"]:
            with self.subTest(vector=vector["name"]):
                if vector["valid"]:
                    validate_uuid4(vector["text"], "vector")
                else:
                    with self.assertRaises(ValidationError):
                        validate_uuid4(vector["text"], "vector")


class SourceRefTests(unittest.TestCase):
    """Issue #151: frozen source_refs grammar and target integrity."""

    def _manifest_with_refs(self, td, target_path, refs):
        dest = Path(td) / "bundle"
        shutil.copytree(FIXTURE, dest)

        def mutate(manifest):
            for entry in manifest["files"]:
                if entry["path"] == target_path:
                    entry["source_refs"] = refs

        _rewrite_manifest(dest, mutate)
        return dest

    def test_unknown_namespace_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td, "annotations/entities.json", ["opaque:whatever"]
            )
            with self.assertRaisesRegex(
                ValidationError, "unknown source_ref namespace"
            ):
                validate_bundle(dest)

    def test_dangling_path_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td, "annotations/entities.json", ["path:does/not/exist.json"]
            )
            with self.assertRaisesRegex(
                ValidationError, "dangling path source_ref"
            ):
                validate_bundle(dest)

    def test_self_path_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td,
                "annotations/entities.json",
                ["path:annotations/entities.json"],
            )
            with self.assertRaisesRegex(
                ValidationError, "self-referential path source_ref"
            ):
                validate_bundle(dest)

    def test_malformed_sha256_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td, "annotations/entities.json", ["sha256:xyz"]
            )
            with self.assertRaisesRegex(
                ValidationError, "malformed sha256 source_ref"
            ):
                validate_bundle(dest)

    def test_dangling_sha256_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td,
                "annotations/entities.json",
                ["sha256:" + "1" * 64],
            )
            with self.assertRaisesRegex(
                ValidationError, "dangling sha256 source_ref"
            ):
                validate_bundle(dest)

    def test_unknown_capture_session_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td,
                "annotations/entities.json",
                ["capture_session:99999999-9999-4999-8999-999999999999"],
            )
            with self.assertRaisesRegex(
                ValidationError, "unknown session"
            ):
                validate_bundle(dest)

    def test_valid_capture_session_ref_passes(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td,
                "annotations/entities.json",
                [
                    "capture_session:00000000-0000-4000-8000-000000000003"
                ],
            )
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_sentinel_ref_passes(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td,
                "annotations/entities.json",
                ["roomplan_raw_serialization:unavailable"],
            )
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_prefixless_ref_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._manifest_with_refs(
                td, "annotations/entities.json", ["barestring"]
            )
            with self.assertRaisesRegex(
                ValidationError, "source_ref grammar"
            ):
                validate_bundle(dest)

    def test_path_ref_cycle_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)

            def mutate(manifest):
                for entry in manifest["files"]:
                    if entry["path"] == "annotations/entities.json":
                        entry["source_refs"] = [
                            "path:annotations/measurements.json"
                        ]
                    elif entry["path"] == "annotations/measurements.json":
                        entry["source_refs"] = [
                            "path:annotations/entities.json"
                        ]

            _rewrite_manifest(dest, mutate)
            with self.assertRaisesRegex(ValidationError, "cycle"):
                validate_bundle(dest)


class SchemaOwnedPayloadTests(unittest.TestCase):
    """Issues #135/#188: schema-owned payloads must satisfy the published
    schema and use canonical JSON bytes."""

    def test_schema_invalid_session_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "session" / "capture-session.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            del doc["capture_mode"]
            _rewrite_payload(
                dest,
                "session/capture-session.json",
                canonical_payload_json_bytes(doc),
            )
            with self.assertRaisesRegex(
                ValidationError, "violates session.schema.json"
            ):
                validate_bundle(dest)

    def test_schema_invalid_quality_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            _rewrite_payload(
                dest,
                "quality/capture-quality.json",
                canonical_payload_json_bytes(
                    {
                        "schema": "htdt.capture.quality",
                        "schema_version": "1.0.0",
                        "ruleset_version": "1.0.0",
                        "ready_for_htdt_ingestion": False,
                    }
                ),
            )
            with self.assertRaisesRegex(
                ValidationError, "violates quality.schema.json"
            ):
                validate_bundle(dest)

    def test_whitespace_expanded_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "annotations" / "entities.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            _rewrite_payload(
                dest,
                "annotations/entities.json",
                json.dumps(doc, indent=2).encode("utf-8"),
            )
            with self.assertRaisesRegex(
                ValidationError, "not Capture Bundle v1 canonical JSON"
            ):
                validate_bundle(dest)

    def test_unsorted_payload_keys_fail(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            # Canonical ordering puts "entities" first; emitting it last is
            # schema-valid JSON but not canonical bytes.
            raw = (
                b'{"schema":"htdt.capture.entities",'
                b'"schema_version":"1.0.0","entities":[]}'
            )
            _rewrite_payload(dest, "annotations/entities.json", raw)
            with self.assertRaisesRegex(
                ValidationError, "not Capture Bundle v1 canonical JSON"
            ):
                validate_bundle(dest)

    def test_non_nfc_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            # "e" + combining acute is valid UTF-8 JSON but not NFC.
            raw = (
                '{"entities":[],"schema":"htdt.capture.entities",'
                '"schema_version":"1.0.0","cafe\u0301":"x"}'
            )
            _rewrite_payload(
                dest, "annotations/entities.json", raw.encode("utf-8")
            )
            with self.assertRaisesRegex(ValidationError, "non-NFC"):
                validate_bundle(dest)

    def test_duplicate_key_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            raw = (
                b'{"entities":[],"entities":[],"schema":'
                b'"htdt.capture.entities","schema_version":"1.0.0"}'
            )
            _rewrite_payload(
                dest, "annotations/entities.json", raw
            )
            with self.assertRaisesRegex(
                ValidationError, "duplicate JSON object key"
            ):
                validate_bundle(dest)

    def test_nonfinite_float_payload_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            path = dest / "annotations" / "entities.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            doc["entities"] = [
                {"label": "x", "value": float("inf")}
            ]
            # json.dumps would emit Infinity; feed the literal bytes.
            raw = (
                b'{"entities":[{"label":"x","value":Infinity}],'
                b'"schema":"htdt.capture.entities",'
                b'"schema_version":"1.0.0"}'
            )
            _rewrite_payload(dest, "annotations/entities.json", raw)
            with self.assertRaisesRegex(
                ValidationError, "non-finite|not Capture Bundle v1 canonical"
            ):
                validate_bundle(dest)

    def test_opaque_roomplan_payload_not_schema_checked(self):
        # roomplan/* payloads are opaque Apple artifacts: arbitrary JSON
        # (or non-JSON) bytes with a correct manifest entry remain valid.
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            blob = b'{"schema":"fixture.roomplan.raw", "not": "canonical"}'
            (dest / "roomplan").mkdir()
            (dest / "roomplan" / "captured-room-data.json").write_bytes(blob)
            digest = hashlib.sha256(blob).hexdigest()

            def mutate(manifest):
                manifest["files"].append(
                    {
                        "path": "roomplan/captured-room-data.json",
                        "bytes": len(blob),
                        "media_type": "application/json",
                        "sha256": digest,
                        "producer": "roomplan_capture",
                        "provenance_class": "apple_roomplan_raw_scan",
                        "role": "canonical",
                    }
                )
                manifest["files"].sort(
                    key=lambda e: e["path"].encode("utf-8")
                )

            _rewrite_manifest(dest, mutate)
            self.assertTrue(validate_bundle(dest)["valid"])


class BinaryPayloadTests(unittest.TestCase):
    """Issue #142: structural validation of canonical binary payloads."""

    def _bundle_with_meshbin(self, td, mesh_bytes, anchor_overrides=None):
        dest = Path(td) / "bundle"
        shutil.copytree(FIXTURE, dest)
        mesh_path = "mesh/geometry/10000000-0000-4000-8000-000000000005.meshbin"
        (dest / "mesh" / "geometry").mkdir(parents=True)
        (dest / "mesh" / "geometry" / (
            "10000000-0000-4000-8000-000000000005.meshbin"
        )).write_bytes(mesh_bytes)

        anchor = {
            "anchor_id": "10000000-0000-4000-8000-000000000005",
            "capture_session_id": "00000000-0000-4000-8000-000000000003",
            "coordinate_space_id": "00000000-0000-4000-8000-000000000004",
            "T_world_from_mesh_anchor": {
                "representation": "column_major_4x4_f32",
                "values": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            },
            "session_timestamp_s": 1.5,
            "vertex_count": 3,
            "face_count": 1,
            "geometry_path": mesh_path,
            "geometry_sha256": hashlib.sha256(mesh_bytes).hexdigest(),
        }
        anchor.update(anchor_overrides or {})
        anchors_doc = {
            "schema": "htdt.capture.mesh-anchors",
            "schema_version": "1.0.0",
            "anchors": [anchor],
        }
        anchors_bytes = canonical_payload_json_bytes(anchors_doc)
        (dest / "mesh").mkdir(exist_ok=True)
        (dest / "mesh" / "anchors.json").write_bytes(anchors_bytes)

        mesh_digest = hashlib.sha256(mesh_bytes).hexdigest()
        anchors_digest = hashlib.sha256(anchors_bytes).hexdigest()

        def mutate(manifest):
            manifest["files"] += [
                {
                    "path": "mesh/anchors.json",
                    "bytes": len(anchors_bytes),
                    "media_type": "application/json",
                    "sha256": anchors_digest,
                    "producer": "mesh_capture",
                    "provenance_class": "arkit_mesh_reconstruction",
                    "role": "canonical",
                    "source_refs": [f"path:{mesh_path}"],
                },
                {
                    "path": mesh_path,
                    "bytes": len(mesh_bytes),
                    "media_type": "application/vnd.htdt.meshbin",
                    "sha256": mesh_digest,
                    "producer": "mesh_capture",
                    "provenance_class": "arkit_mesh_reconstruction",
                    "role": "canonical",
                },
            ]
            manifest["files"].sort(
                key=lambda e: e["path"].encode("utf-8")
            )

        _rewrite_manifest(dest, mutate)
        return dest

    def test_valid_meshbin_bundle_passes(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        )
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(td, mesh)
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_random_bytes_meshbin_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(
                td, os.urandom(80), anchor_overrides={}
            )
            # Header counts in anchors.json will not matter: the binary
            # itself must parse as HTDTMSH1 first.
            with self.assertRaisesRegex(
                ValidationError, "not a valid meshbin|invalid_magic"
            ):
                validate_bundle(dest)

    def test_meshbin_count_mismatch_rejected(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        )
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(
                td, mesh, anchor_overrides={"vertex_count": 4}
            )
            with self.assertRaisesRegex(
                ValidationError, "vertex_count"
            ):
                validate_bundle(dest)

    def test_meshbin_nonfinite_vertex_rejected(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (float("nan"), 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        )
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(td, mesh)
            with self.assertRaisesRegex(
                ValidationError, "not a valid meshbin"
            ):
                validate_bundle(dest)

    def test_meshbin_out_of_bounds_index_rejected(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 7],
        )
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(td, mesh)
            with self.assertRaisesRegex(
                ValidationError, "not a valid meshbin"
            ):
                validate_bundle(dest)

    def test_meshbin_trailing_bytes_rejected(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        ) + b"junk"
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(td, mesh)
            with self.assertRaisesRegex(
                ValidationError, "trailing_bytes"
            ):
                validate_bundle(dest)

    def test_meshbin_wrong_media_type_rejected(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        )
        with tempfile.TemporaryDirectory() as td:
            dest = self._bundle_with_meshbin(td, mesh)

            def mutate(manifest):
                for entry in manifest["files"]:
                    if entry["path"].endswith(".meshbin"):
                        entry["media_type"] = "application/octet-stream"

            _rewrite_manifest(dest, mutate)
            with self.assertRaisesRegex(ValidationError, "media type"):
                validate_bundle(dest)

    def test_binary_codec_unit_vectors(self):
        mesh = _meshbin(
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            [0, 1, 2],
        )
        header = validate_meshbin(mesh)
        self.assertEqual((header.vertex_count, header.face_count), (3, 1))
        with self.assertRaises(BinaryFormatError):
            validate_meshbin(mesh[:-1])
        with self.assertRaises(BinaryFormatError):
            validate_meshbin(b"X" + mesh[1:])
        bad_version = bytearray(mesh)
        bad_version[8] = 2
        with self.assertRaises(BinaryFormatError):
            validate_meshbin(bytes(bad_version))

        depth = _depthbin(2, 2, [0.5, 1.0, 1.5, 2.0], validity=[1, 1, 0, 1])
        header = validate_depthbin(depth)
        self.assertEqual((header.width, header.height), (2, 2))
        bad = _depthbin(2, 2, [0.5, 1.0, 1.5, 2.0], validity=[1, 2, 0, 1])
        with self.assertRaises(BinaryFormatError):
            validate_depthbin(bad)
        bad = _depthbin(2, 2, [float("inf"), 1.0, 1.5, 2.0])
        with self.assertRaises(BinaryFormatError):
            validate_depthbin(bad)

        conf = _confidencebin(2, 2, [0, 1, 2, 2])
        header = validate_confidencebin(conf)
        self.assertEqual((header.width, header.height), (2, 2))
        with self.assertRaises(BinaryFormatError):
            validate_confidencebin(conf + b"x")

        pixel = _pixelbin(
            4,
            4,
            0x34323066,  # '420f'
            [(4, 4, 4, 4, bytes(range(16))), (2, 2, 4, 4, bytes(8))],
        )
        header = validate_pixelbin(pixel)
        self.assertEqual((header.width, header.height), (4, 4))
        with self.assertRaises(BinaryFormatError):
            validate_pixelbin(pixel + b"x")
        bad = _pixelbin(4, 4, 0x34323066, [])
        with self.assertRaises(BinaryFormatError):
            validate_pixelbin(bad)


class DescriptorCrossCheckTests(unittest.TestCase):
    """Issue #142: frame descriptors bind to validated binaries."""

    FRAME_ID = "20000000-0000-4000-8000-000000000009"

    def _frame_bundle(self, td, descriptor_mutate=None, payloads=None):
        import struct as _struct

        dest = Path(td) / "bundle"
        shutil.copytree(FIXTURE, dest)
        frame_dir = dest / "evidence" / "frames"
        depth_dir = dest / "evidence" / "depth"
        frame_dir.mkdir(parents=True)
        depth_dir.mkdir(parents=True)

        pixel = _pixelbin(
            4, 4, 0x34323066, [(4, 4, 4, 4, bytes(range(16)))]
        )
        depth = _depthbin(2, 2, [0.5, 1.0, 1.5, 2.0])
        confidence = _confidencebin(2, 2, [2, 2, 1, 0])

        blob_map = {
            f"evidence/frames/{self.FRAME_ID}.pixelbin": (
                pixel, "application/vnd.htdt.pixelbin",
                "frame_capture", "arkit_frame_observation",
            ),
            f"evidence/depth/{self.FRAME_ID}.depthbin": (
                depth, "application/vnd.htdt.depthbin",
                "depth_capture", "arkit_scene_depth_observation",
            ),
            f"evidence/depth/{self.FRAME_ID}.confidencebin": (
                confidence, "application/vnd.htdt.confidencebin",
                "depth_capture", "arkit_scene_depth_observation",
            ),
        }
        if payloads is not None:
            blob_map.update(payloads)

        descriptor = {
            "frame_id": self.FRAME_ID,
            "capture_session_id": "00000000-0000-4000-8000-000000000003",
            "coordinate_space_id": "00000000-0000-4000-8000-000000000004",
            "session_timestamp_s": 2.5,
            "T_world_from_camera": {
                "representation": "column_major_4x4_f32",
                "values": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            },
            "intrinsics": {
                "representation": "column_major_3x3_f32",
                "values": [1000, 0, 0, 0, 1000, 0, 2, 1.5, 1],
            },
            "image_width": 4,
            "image_height": 4,
            "pixel_format_fourcc": 0x34323066,
            "pixel_relative_path": (
                f"evidence/frames/{self.FRAME_ID}.pixelbin"
            ),
            "pixel_byte_count": len(blob_map[
                f"evidence/frames/{self.FRAME_ID}.pixelbin"
            ][0]),
            "pixel_sha256": hashlib.sha256(
                blob_map[f"evidence/frames/{self.FRAME_ID}.pixelbin"][0]
            ).hexdigest(),
            "exif_allowlisted": {},
            "depth_status": "captured_scene_depth",
            "depth": {
                "kind": "scene_depth",
                "depth_relative_path": (
                    f"evidence/depth/{self.FRAME_ID}.depthbin"
                ),
                "depth_byte_count": len(
                    blob_map[f"evidence/depth/{self.FRAME_ID}.depthbin"][0]
                ),
                "depth_sha256": hashlib.sha256(
                    blob_map[f"evidence/depth/{self.FRAME_ID}.depthbin"][0]
                ).hexdigest(),
                "confidence_relative_path": (
                    f"evidence/depth/{self.FRAME_ID}.confidencebin"
                ),
                "confidence_byte_count": len(
                    blob_map[
                        f"evidence/depth/{self.FRAME_ID}.confidencebin"
                    ][0]
                ),
                "confidence_sha256": hashlib.sha256(
                    blob_map[
                        f"evidence/depth/{self.FRAME_ID}.confidencebin"
                    ][0]
                ).hexdigest(),
            },
        }
        if descriptor_mutate:
            descriptor_mutate(descriptor)

        descriptor_bytes = canonical_payload_json_bytes(descriptor)
        descriptor_path = f"evidence/frames/{self.FRAME_ID}.json"
        (frame_dir / f"{self.FRAME_ID}.json").write_bytes(descriptor_bytes)

        for rel, (blob, _, _, _) in blob_map.items():
            (dest / rel).write_bytes(blob)

        def mutate(manifest):
            for rel, (blob, media, producer, provenance) in blob_map.items():
                manifest["files"].append(
                    {
                        "path": rel,
                        "bytes": len(blob),
                        "media_type": media,
                        "sha256": hashlib.sha256(blob).hexdigest(),
                        "producer": producer,
                        "provenance_class": provenance,
                        "role": "canonical",
                    }
                )
            manifest["files"].append(
                {
                    "path": descriptor_path,
                    "bytes": len(descriptor_bytes),
                    "media_type": "application/json",
                    "sha256": hashlib.sha256(descriptor_bytes).hexdigest(),
                    "producer": "frame_capture",
                    "provenance_class": "arkit_frame_observation",
                    "role": "canonical",
                    "source_refs": sorted(
                        f"path:{p}"
                        for p in (
                            f"evidence/depth/{self.FRAME_ID}.confidencebin",
                            f"evidence/depth/{self.FRAME_ID}.depthbin",
                            f"evidence/frames/{self.FRAME_ID}.pixelbin",
                        )
                    ),
                }
            )
            manifest["files"].sort(
                key=lambda e: e["path"].encode("utf-8")
            )

        _rewrite_manifest(dest, mutate)
        return dest

    def test_valid_frame_descriptor_bundle_passes(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._frame_bundle(td)
            self.assertTrue(validate_bundle(dest)["valid"])

    def test_descriptor_dimension_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._frame_bundle(
                td, descriptor_mutate=lambda d: d.update(image_width=8)
            )
            with self.assertRaisesRegex(ValidationError, "dimensions"):
                validate_bundle(dest)

    def test_descriptor_bad_pixel_path_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._frame_bundle(
                td,
                descriptor_mutate=lambda d: d.update(
                    pixel_relative_path="evidence/frames/other.pixelbin"
                ),
            )
            with self.assertRaisesRegex(ValidationError, "pixel"):
                validate_bundle(dest)

    def test_descriptor_status_without_depth_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._frame_bundle(
                td, descriptor_mutate=lambda d: d.update(depth=None)
            )
            with self.assertRaisesRegex(ValidationError, "depth"):
                validate_bundle(dest)

    def test_descriptor_incomplete_confidence_fails(self):
        with tempfile.TemporaryDirectory() as td:
            def mutate(d):
                d["depth"]["confidence_sha256"] = None
            dest = self._frame_bundle(td, descriptor_mutate=mutate)
            with self.assertRaisesRegex(
                ValidationError, "incomplete confidence"
            ):
                validate_bundle(dest)

    def test_descriptor_wrong_filename_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = self._frame_bundle(
                td,
                descriptor_mutate=lambda d: d.update(
                    frame_id="20000000-0000-4000-8000-0000000000aa"
                ),
            )
            with self.assertRaisesRegex(ValidationError, "frame_id"):
                validate_bundle(dest)


class ToctouTests(unittest.TestCase):
    """Issue #189: reads bind the identity checked at open time."""

    def test_symlink_swap_after_scan_fails(self):
        if not hasattr(os, "symlink"):
            self.skipTest("platform lacks symlink support")
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            outside = Path(td) / "outside.json"
            outside.write_bytes(b'{"entities":[]}')
            source = DirectorySource(dest)
            source.list_files()
            try:
                target.unlink()
                os.symlink(outside, target)
            except OSError as exc:
                self.skipTest(f"cannot create symlink: {exc}")
            with self.assertRaises(ValidationError):
                source.read_bytes("annotations/entities.json")

    def test_regular_swap_between_lstat_and_open_detected(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            source = DirectorySource(dest)
            source.list_files()

            # Swap the file for a different regular file between the
            # pre-open lstat and the open: the descriptor's inode must
            # differ from the lstat snapshot and fail closed.
            original_stat = os.stat(target, follow_symlinks=False)
            replacement = Path(td) / "replacement.json"
            replacement.write_bytes(target.read_bytes())
            real_stat = os.stat

            def racing_stat(path, *args, **kwargs):
                result = real_stat(path, *args, **kwargs)
                if Path(path) == target:
                    os.replace(replacement, target)
                    return original_stat
                return result

            import unittest.mock as mock

            with mock.patch(
                "tools.bundle_validator.validator.os.stat",
                side_effect=racing_stat,
            ):
                with self.assertRaisesRegex(
                    ValidationError, "replaced during validation"
                ):
                    source.read_bytes("annotations/entities.json")

    def test_same_size_swap_still_fails_hash(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            source = DirectorySource(dest)
            source.list_files()
            original = target.read_bytes()
            mutated = original.replace(b"entities", b"entitiez")
            assert len(mutated) == len(original)
            target.write_bytes(mutated)
            with self.assertRaisesRegex(
                ValidationError, "SHA-256 mismatch|byte length mismatch"
            ):
                validate_bundle(dest)

    def test_mid_read_size_change_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "bundle"
            shutil.copytree(FIXTURE, dest)
            target = dest / "annotations" / "entities.json"
            source = DirectorySource(dest)
            source.list_files()

            # Extend the file after fstat so the bound-checked stream
            # observes a size change through the same descriptor.
            real_fstat = os.fstat
            original_size = target.stat().st_size

            class _FakeStat:
                pass

            def fake_fstat(fd):
                result = real_fstat(fd)
                target.write_bytes(target.read_bytes() + b" ")
                return result

            import unittest.mock as mock

            with mock.patch(
                "tools.bundle_validator.validator.os.fstat",
                side_effect=fake_fstat,
            ):
                with self.assertRaisesRegex(
                    ValidationError, "size changed|SHA-256|exceeds"
                ):
                    # Same inode, mutated content: read through the
                    # descriptor sees the new length.
                    source.read_bytes("annotations/entities.json")


class SchemaEvalTests(unittest.TestCase):
    def _load(self, name):
        return json.loads((SCHEMA_DIR / name).read_text(encoding="utf-8"))

    def test_foundation_positive_vectors(self):
        doc = json.loads(
            (
                SCHEMA_DIR / "foundation-document-vectors.json"
            ).read_text(encoding="utf-8")
        )
        for vector in doc["positive"]:
            with self.subTest(vector=vector["name"]):
                schema_validate(
                    vector["document"], self._load(vector["schema_file"])
                )

    def test_foundation_negative_vectors(self):
        doc = json.loads(
            (
                SCHEMA_DIR / "foundation-document-vectors.json"
            ).read_text(encoding="utf-8")
        )
        for vector in doc["negative"]:
            with self.subTest(vector=vector["name"]):
                with self.assertRaises(SchemaError):
                    schema_validate(
                        vector["document"],
                        self._load(vector["schema_file"]),
                    )

    def test_repo_fixtures_validate_against_schemas(self):
        for rel, schema_name in (
            ("session/capture-session.json", "session.schema.json"),
            ("session/device.json", "device.schema.json"),
            ("session/capabilities.json", "capabilities.schema.json"),
            (
                "session/capture-configuration.json",
                "capture-configuration.schema.json",
            ),
            ("session/timing.json", "timing.schema.json"),
            ("annotations/entities.json", "entities.schema.json"),
            ("annotations/measurements.json", "measurements.schema.json"),
            ("quality/capture-quality.json", "quality.schema.json"),
        ):
            with self.subTest(path=rel):
                document = json.loads(
                    (FIXTURE / rel).read_text(encoding="utf-8")
                )
                schema_validate(document, self._load(schema_name))

    def test_unsupported_keyword_fails_closed(self):
        with self.assertRaisesRegex(SchemaError, "unsupported"):
            check_schema({"type": "object", "patternProperties": {}})
        with self.assertRaises(SchemaError):
            schema_validate(
                {},
                {"type": "object", "patternProperties": {"x": {}}},
            )

    def test_remote_ref_fails_closed(self):
        with self.assertRaises(SchemaError):
            schema_validate(
                {}, {"$ref": "other.schema.json#/defs/x"}
            )

    def test_evaluator_constructs(self):
        schema = {
            "type": "object",
            "required": ["a"],
            "properties": {
                "a": {"oneOf": [{"type": "null"}, {"type": "integer"}]},
                "b": {"type": "string", "format": "uuid"},
            },
            "allOf": [
                {
                    "if": {"properties": {"c": {"const": 1}},
                          "required": ["c"]},
                    "then": {"required": ["d"]},
                }
            ],
        }
        schema_validate({"a": None}, schema)
        schema_validate({"a": 4, "b": "9f5e0f1d-0000-4abc-8000-000000000000".replace("9f5e0f1d-0000-4abc", "00000000-0000-4000"), "c": 1, "d": 2}, schema)
        with self.assertRaises(SchemaError):
            schema_validate({"a": True}, schema)
        with self.assertRaises(SchemaError):
            schema_validate({"a": 1, "c": 1}, schema)
        with self.assertRaises(SchemaError):
            schema_validate({"a": 1.5}, schema)

    def test_unique_items_and_type_equality(self):
        schema = {"type": "array", "uniqueItems": True}
        schema_validate([1, 2, 3], schema)
        with self.assertRaises(SchemaError):
            schema_validate([1, 1], schema)
        # JSON Schema equality is type-sensitive: true != 1.
        schema_validate([True, 1], schema)
        with self.assertRaises(SchemaError):
            schema_validate([[1], [1]], schema)


if __name__ == "__main__":
    unittest.main()
