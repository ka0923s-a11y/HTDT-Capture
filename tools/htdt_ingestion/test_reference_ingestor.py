from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.bundle_validator.archive_bundle import create_archive
from tools.bundle_validator.validator import (
    ValidationError,
    canonical_json_bytes,
    validate_bundle,
)
from tools.htdt_ingestion.reference_ingestor import (
    IngestionError,
    build_ingestion_plan,
    canonical_plan_bytes,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "samples" / "phase6-integration"

EXPECTED_BUNDLE_DIGEST = (
    "925108a1b3c1b432182efe1b7e18ccb0f1d98f4f17c939ca66a6095b0cc28550"
)
EXPECTED_LINEAGE_DIGEST = (
    "729a7590fb1d1e2142c196187ef11a9078522326daa1ef2fd2364b8fd1ef6bf1"
)
EXPECTED_RAW_VISUAL_MESH_HANDOFF_ID = (
    "ed9ef39706c130b44db85939f0f429e46ec24ef0d09590f24776ad39b8871794"
)
EXPECTED_ANNOTATION_HANDOFF_ID = (
    "3f53e7ddc86450ac457835ef9b4a152d525369a83c61c8e67eeb00568af47987"
)
EXPECTED_MEASUREMENT_HANDOFF_ID = (
    "05c2d8d741341a6fff2c2ee1a858bef4c71570d4cb40f00920c61d9942ee0f21"
)
ANCHOR_ID = "10000000-0000-4000-8000-000000000005"
COORDINATE_SPACE_ID = "10000000-0000-4000-8000-000000000004"
MESH_PATH = f"mesh/geometry/{ANCHOR_ID}.meshbin"
MESH_SHA256 = (
    "9cf9198c431c6a803ecef625cfa96f1ea1b535b536782f4cb272b42e143d9276"
)


class ReferenceIngestorTests(unittest.TestCase):
    def test_frozen_fixture_validates_with_expected_bundle_digest(self):
        report = validate_bundle(FIXTURE)
        self.assertTrue(report["valid"])
        self.assertEqual(report["bundle_digest"], EXPECTED_BUNDLE_DIGEST)
        self.assertEqual(report["payload_count"], 6)

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


if __name__ == "__main__":
    unittest.main()
