from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from tools.bundle_validator.archive_bundle import create_archive
from tools.bundle_validator.validator import (
    ValidationError,
    canonical_json_bytes,
    validate_bundle,
)
import tools.htdt_ingestion.reference_ingestor as reference_ingestor
from tools.htdt_ingestion.reference_ingestor import (
    IngestionError,
    build_ingestion_plan,
    canonical_plan_bytes,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "samples" / "phase6-integration"
MINIMAL_FIXTURE = REPO_ROOT / "samples" / "minimal-capture"

EXPECTED_BUNDLE_DIGEST = (
    "3823f3a70e4272db64bd02252d61cc1f15729550f41e927f5eb4e8afa2b5583b"
)
EXPECTED_LINEAGE_DIGEST = (
    "bb8da496704d33a93d82683ce3ca47ac0cf5760f99a1b20d86a1812b39e6a43e"
)
EXPECTED_RAW_VISUAL_MESH_HANDOFF_ID = (
    "0f779b6dbcd872f4c22bf2e975778831f299f020d74306f99da9b3c124065feb"
)
EXPECTED_ANNOTATION_HANDOFF_ID = (
    "ff2d190abf30109811df4b62771655b751910e95534fbfce0d735dbd4fa7f4b9"
)
EXPECTED_MEASUREMENT_HANDOFF_ID = (
    "26a130ae8dc8935a5072f04517d179af576429aa9352e6c4aa9b7c4f7ba2bf51"
)
ANCHOR_ID = "10000000-0000-4000-8000-000000000005"
COORDINATE_SPACE_ID = "10000000-0000-4000-8000-000000000004"
SESSION_ID = "10000000-0000-4000-8000-000000000003"
MESH_PATH = f"mesh/geometry/{ANCHOR_ID}.meshbin"
MESH_SHA256 = (
    "9cf9198c431c6a803ecef625cfa96f1ea1b535b536782f4cb272b42e143d9276"
)
QUALITY_PATH = "quality/capture-quality.json"


def _rewrite_payload(copy_root: Path, rel_path: str, mutate) -> None:
    """Rewrite a bundle payload and re-commit its manifest entry."""
    payload_path = copy_root / rel_path
    document = json.loads(payload_path.read_text(encoding="utf-8"))
    mutated = mutate(document)
    encoded = json.dumps(
        mutated if mutated is not None else document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    payload_path.write_bytes(encoded)

    manifest_path = copy_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for entry in manifest["files"]:
        if entry["path"] == rel_path:
            entry["bytes"] = len(encoded)
            entry["sha256"] = hashlib.sha256(encoded).hexdigest()
    manifest_path.write_bytes(canonical_json_bytes(manifest))


def _drop_payload(copy_root: Path, rel_path: str) -> None:
    """Remove a bundle payload and its manifest declaration."""
    (copy_root / rel_path).unlink()
    manifest_path = copy_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"] = [
        entry
        for entry in manifest["files"]
        if entry["path"] != rel_path
    ]
    manifest_path.write_bytes(canonical_json_bytes(manifest))


class ReferenceIngestorTests(unittest.TestCase):
    def test_frozen_fixture_validates_with_expected_bundle_digest(self):
        report = validate_bundle(FIXTURE)
        self.assertTrue(report["valid"])
        self.assertEqual(report["bundle_digest"], EXPECTED_BUNDLE_DIGEST)
        self.assertEqual(report["payload_count"], 7)

    def test_reingestion_is_deterministic_for_pinned_version(self):
        first = build_ingestion_plan(FIXTURE)
        second = build_ingestion_plan(FIXTURE)

        self.assertEqual(first, second)
        self.assertEqual(canonical_plan_bytes(first), canonical_plan_bytes(second))
        self.assertEqual(
            first["bundle"]["bundle_digest"],
            EXPECTED_BUNDLE_DIGEST,
        )
        self.assertEqual(first["lineage_digest"], EXPECTED_LINEAGE_DIGEST)

    def test_raw_visual_mesh_handoff_retains_exact_anchor_lineage(self):
        plan = build_ingestion_plan(FIXTURE)
        self.assertEqual(len(plan["raw_visual_mesh_handoffs"]), 1)

        handoff = plan["raw_visual_mesh_handoffs"][0]
        self.assertEqual(
            handoff["raw_visual_mesh_handoff_id"],
            EXPECTED_RAW_VISUAL_MESH_HANDOFF_ID,
        )
        self.assertEqual(handoff["anchor_id"], ANCHOR_ID)
        self.assertEqual(handoff["geometry_path"], MESH_PATH)
        self.assertEqual(handoff["geometry_sha256"], MESH_SHA256)
        self.assertEqual(
            handoff["coordinate_space_id"],
            COORDINATE_SPACE_ID,
        )
        self.assertEqual(
            handoff["T_world_from_mesh_anchor"]["representation"],
            "column_major_4x4_f32",
        )
        self.assertTrue(handoff["geometry_source_evidence_id"])
        self.assertTrue(handoff["anchor_index_source_evidence_id"])

    def test_provenance_classes_remain_distinct(self):
        plan = build_ingestion_plan(FIXTURE)
        by_path = {
            record["path"]: record
            for record in plan["source_evidence"]
        }

        self.assertEqual(
            by_path["roomplan/captured-room-data.json"]["provenance_class"],
            "apple_roomplan_raw_scan",
        )
        self.assertEqual(
            by_path["roomplan/captured-room.json"]["provenance_class"],
            "apple_roomplan_inference",
        )
        self.assertEqual(
            by_path[MESH_PATH]["provenance_class"],
            "arkit_mesh_reconstruction",
        )
        self.assertEqual(
            by_path["annotations/entities.json"]["provenance_class"],
            "user_annotation",
        )
        self.assertEqual(
            by_path["annotations/measurements.json"]["provenance_class"],
            "user_attested_measurement",
        )

        self.assertEqual(
            [record["kind"] for record in plan["roomplan_records"]],
            ["raw_scan", "postprocessed_inference"],
        )

    def test_processed_roomplan_requires_raw_payload_lineage(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            _drop_payload(copy_root, "roomplan/captured-room-data.json")
            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            processed = next(
                entry
                for entry in manifest["files"]
                if entry["path"] == "roomplan/captured-room.json"
            )
            processed["source_refs"] = []
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_processed_roomplan_rejects_non_raw_sha_lineage(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            processed = next(
                entry
                for entry in manifest["files"]
                if entry["path"] == "roomplan/captured-room.json"
            )
            processed["source_refs"] = [f"sha256:{MESH_SHA256}"]
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_missing_quality_payload_blocks_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _drop_payload(copy_root, QUALITY_PATH)

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("quality", str(ctx.exception))

    def test_not_ready_quality_report_blocks_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def not_ready(document):
                document["ready_for_htdt_ingestion"] = False
                document["diagnostics"] = [
                    {
                        "code": "insufficient_mesh_anchors",
                        "severity": "error",
                        "message": "Active mesh anchor count is low.",
                        "evidence_refs": [],
                    }
                ]

            _rewrite_payload(copy_root, QUALITY_PATH, not_ready)
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("ready_for_htdt_ingestion", str(ctx.exception))

    def test_unsupported_quality_ruleset_blocks_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def wrong_ruleset(document):
                document["ruleset_version"] = "9.9.9"

            _rewrite_payload(copy_root, QUALITY_PATH, wrong_ruleset)
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("ruleset", str(ctx.exception))

    def test_malformed_quality_payload_blocks_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def malformed(document):
                del document["integrity_status"]

            _rewrite_payload(copy_root, QUALITY_PATH, malformed)
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_ready_report_with_error_diagnostic_is_contradictory(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def contradictory(document):
                document["diagnostics"] = [
                    {
                        "code": "insufficient_mesh_anchors",
                        "severity": "error",
                        "message": "Active mesh anchor count is low.",
                        "evidence_refs": [],
                    }
                ]

            _rewrite_payload(copy_root, QUALITY_PATH, contradictory)
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("contradictory", str(ctx.exception))

    def test_ready_report_requires_integrity_pass_assertion(self):
        for status in ("not_checked", "fail"):
            with self.subTest(integrity_status=status):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)

                    def inconsistent(document, status=status):
                        document["integrity_status"] = status

                    _rewrite_payload(copy_root, QUALITY_PATH, inconsistent)
                    validate_bundle(copy_root)
                    with self.assertRaises(IngestionError) as ctx:
                        build_ingestion_plan(copy_root)
                    self.assertIn("integrity_status", str(ctx.exception))

    def test_quality_gate_does_not_replace_payload_hash_verification(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            # The frozen fixture's report asserts integrity_status=pass;
            # a tampered payload must still fail at manifest verification.
            with (copy_root / MESH_PATH).open("ab") as handle:
                handle.write(b"x")

            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_reference_ingestor_rejects_unknown_source_ref_prefix(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            mesh_entry = next(
                entry
                for entry in manifest["files"]
                if entry["path"] == "mesh/anchors.json"
            )
            mesh_entry["source_refs"] = ["opaque:unsupported"]
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_annotation_and_measurement_records_keep_source_authority(self):
        plan = build_ingestion_plan(FIXTURE)
        records = {
            record["record_kind"]: record
            for record in plan["authority_records"]
        }

        self.assertEqual(
            records["annotation"]["authority_record_handoff_id"],
            EXPECTED_ANNOTATION_HANDOFF_ID,
        )
        self.assertEqual(
            records["annotation"]["provenance_class"],
            "user_annotation",
        )
        self.assertEqual(
            records["measurement"]["authority_record_handoff_id"],
            EXPECTED_MEASUREMENT_HANDOFF_ID,
        )
        self.assertEqual(
            records["measurement"]["provenance_class"],
            "user_attested_measurement",
        )

    def test_direct_cli_execution_builds_expected_plan(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "plan.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(
                        REPO_ROOT
                        / "tools"
                        / "htdt_ingestion"
                        / "reference_ingestor.py"
                    ),
                    str(FIXTURE),
                    "--output",
                    str(output),
                ],
                cwd=REPO_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            plan = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(
                plan["lineage_digest"],
                EXPECTED_LINEAGE_DIGEST,
            )

    def test_archive_and_directory_produce_identical_ingestion_plan(self):
        directory_plan = build_ingestion_plan(FIXTURE)

        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "phase6.htdtcapture"
            create_archive(FIXTURE, archive)
            archive_plan = build_ingestion_plan(archive)

        self.assertEqual(
            canonical_plan_bytes(directory_plan),
            canonical_plan_bytes(archive_plan),
        )

    def test_unknown_coordinate_reference_fails_after_integrity_validation(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            anchors_path = copy_root / "mesh" / "anchors.json"
            anchors = json.loads(anchors_path.read_text(encoding="utf-8"))
            anchors["anchors"][0]["coordinate_space_id"] = (
                "20000000-0000-4000-8000-000000000008"
            )
            anchors_bytes = json.dumps(
                anchors,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
            anchors_path.write_bytes(anchors_bytes)

            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for entry in manifest["files"]:
                if entry["path"] == "mesh/anchors.json":
                    entry["bytes"] = len(anchors_bytes)
                    entry["sha256"] = hashlib.sha256(
                        anchors_bytes
                    ).hexdigest()
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_tampered_payload_fails_before_ingestion_plan_is_built(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            with (copy_root / MESH_PATH).open("ab") as handle:
                handle.write(b"x")

            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_directory_payload_mutation_after_validation_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            real_validate = reference_ingestor.validate_bundle

            def mutate_after_validate(path):
                report = real_validate(path)
                # Same length, different bytes: only the SHA-256 binding
                # can catch this mutation.
                (copy_root / MESH_PATH).write_bytes(b"\x00" * 80)
                return report

            with mock.patch.object(
                reference_ingestor, "validate_bundle", mutate_after_validate
            ):
                with self.assertRaises(IngestionError) as ctx:
                    build_ingestion_plan(copy_root)
            self.assertIn("changed after validation", str(ctx.exception))

    def test_directory_payload_deleted_after_validation_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            real_validate = reference_ingestor.validate_bundle

            def delete_after_validate(path):
                report = real_validate(path)
                (copy_root / MESH_PATH).unlink()
                return report

            with mock.patch.object(
                reference_ingestor, "validate_bundle", delete_after_validate
            ):
                with self.assertRaises(IngestionError) as ctx:
                    build_ingestion_plan(copy_root)
            self.assertIn("file set changed", str(ctx.exception))

    def test_undeclared_file_added_after_validation_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            real_validate = reference_ingestor.validate_bundle

            def inject_after_validate(path):
                report = real_validate(path)
                (copy_root / "injected.json").write_bytes(b"{}")
                return report

            with mock.patch.object(
                reference_ingestor, "validate_bundle", inject_after_validate
            ):
                with self.assertRaises(IngestionError) as ctx:
                    build_ingestion_plan(copy_root)
            self.assertIn("file set changed", str(ctx.exception))

    def test_manifest_replaced_after_validation_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            foreign_manifest = (MINIMAL_FIXTURE / "manifest.json").read_bytes()

            real_validate = reference_ingestor.validate_bundle

            def swap_manifest_after_validate(path):
                report = real_validate(path)
                (copy_root / "manifest.json").write_bytes(foreign_manifest)
                return report

            with mock.patch.object(
                reference_ingestor,
                "validate_bundle",
                swap_manifest_after_validate,
            ):
                with self.assertRaises(IngestionError) as ctx:
                    build_ingestion_plan(copy_root)
            self.assertIn("manifest changed", str(ctx.exception))

    def test_archive_replaced_after_validation_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "phase6.htdtcapture"
            create_archive(FIXTURE, archive)
            replacement = Path(td) / "replacement.htdtcapture"
            create_archive(MINIMAL_FIXTURE, replacement)

            real_validate = reference_ingestor.validate_bundle

            def replace_after_validate(path):
                report = real_validate(path)
                os.replace(replacement, archive)
                return report

            with mock.patch.object(
                reference_ingestor, "validate_bundle", replace_after_validate
            ):
                with self.assertRaises(IngestionError) as ctx:
                    build_ingestion_plan(archive)
            self.assertIn("manifest changed", str(ctx.exception))

    def test_archive_replaced_with_corrupt_file_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "phase6.htdtcapture"
            create_archive(FIXTURE, archive)

            real_validate = reference_ingestor.validate_bundle

            def corrupt_after_validate(path):
                report = real_validate(path)
                archive.write_bytes(b"not a zip archive")
                return report

            with mock.patch.object(
                reference_ingestor, "validate_bundle", corrupt_after_validate
            ):
                with self.assertRaises(ValidationError):
                    build_ingestion_plan(archive)

    def test_reads_serve_bytes_frozen_at_validation_boundary(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            reader = reference_ingestor.ValidatedBundleReader(copy_root)
            try:
                # Mutations after the reader froze the validated bytes must
                # not leak into what ingestion parses.
                (copy_root / MESH_PATH).write_bytes(b"\xff" * 80)
                self.assertEqual(
                    hashlib.sha256(reader.read(MESH_PATH)).hexdigest(),
                    MESH_SHA256,
                )
                self.assertEqual(
                    hashlib.sha256(
                        reader.read("manifest.json")
                    ).hexdigest(),
                    EXPECTED_BUNDLE_DIGEST,
                )
                with self.assertRaises(IngestionError):
                    reader.read("does/not/exist.json")
            finally:
                reader.close()
            with self.assertRaises(IngestionError):
                reader.read("manifest.json")

    def test_mutation_during_ingestion_keeps_plan_byte_identical(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            expected = canonical_plan_bytes(build_ingestion_plan(FIXTURE))

            real_parse = reference_ingestor.parse_json_bytes

            def mutate_then_parse(data):
                # Fires after the reader froze payloads but before the
                # ingestion builders consume them.
                (copy_root / MESH_PATH).write_bytes(b"\x01" * 80)
                (copy_root / "manifest.json").write_bytes(b"{}")
                return real_parse(data)

            with mock.patch.object(
                reference_ingestor, "parse_json_bytes", mutate_then_parse
            ):
                plan = build_ingestion_plan(copy_root)

            self.assertEqual(canonical_plan_bytes(plan), expected)
            self.assertEqual(
                plan["lineage_digest"], EXPECTED_LINEAGE_DIGEST
            )


if __name__ == "__main__":
    unittest.main()
