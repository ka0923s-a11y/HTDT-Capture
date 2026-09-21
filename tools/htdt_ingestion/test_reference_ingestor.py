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
from tools.htdt_ingestion import plan_schema
from tools.htdt_ingestion.reference_ingestor import (
    IngestionError,
    build_ingestion_plan,
    canonical_plan_bytes,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "samples" / "phase6-integration"
MINIMAL_FIXTURE = REPO_ROOT / "samples" / "minimal-capture"

EXPECTED_BUNDLE_DIGEST = (
    "e12b3e9c43fe8b26b151cde32acbbf19e56447750447955ead65e1477c9fcb8a"
)
EXPECTED_LINEAGE_DIGEST = (
    "92e81abef2304f4f8bdecbacff394af0ac0e34ed6a33d2321e711fc6b433b69f"
)
EXPECTED_RAW_VISUAL_MESH_HANDOFF_ID = (
    "34724a36fe89ade1c0613bde2f358c723dc187c15b5c01bc8b39d134a6dade50"
)
EXPECTED_ANNOTATION_HANDOFF_ID = (
    "74672397c79a9bc6865a73ba565f5167e7929bd59878bc3e41ead2420930efb0"
)
EXPECTED_MEASUREMENT_HANDOFF_ID = (
    "0e32a92497a6f950a32dd1cfd129e7e597c6ff47a976f8618a8e667ffcffab52"
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


def _add_payload(
    copy_root: Path,
    rel_path: str,
    payload: bytes,
    *,
    media_type: str = "application/json",
    producer: str = "frame_capture",
    provenance_class: str = "arkit_frame_observation",
    role: str = "canonical",
    source_refs: list[str] | None = None,
) -> None:
    """Write a new bundle payload and declare it in the manifest."""
    target = copy_root / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)

    entry = {
        "bytes": len(payload),
        "media_type": media_type,
        "path": rel_path,
        "producer": producer,
        "provenance_class": provenance_class,
        "role": role,
        "sha256": hashlib.sha256(payload).hexdigest(),
    }
    if source_refs is not None:
        entry["source_refs"] = source_refs

    manifest_path = copy_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"] = [
        existing
        for existing in manifest["files"]
        if existing["path"] != rel_path
    ]
    manifest["files"].append(entry)
    manifest["files"].sort(key=lambda item: item["path"].encode("utf-8"))
    manifest_path.write_bytes(canonical_json_bytes(manifest))


def _pixelbin_payload(width: int = 2, height: int = 2) -> bytes:
    """Structurally valid HTDTPXL1 v1.0 payload (one 4-byte/px plane)."""
    import struct

    plane_count = 1
    header_length = 32 + plane_count * 24
    packed = width * 4
    payload_bytes = packed * height
    header = (
        b"HTDTPXL1"
        + struct.pack("<HHI", 1, 0, header_length)
        + struct.pack("<IIIH H", width, height, 875704438, plane_count, 0)
        + struct.pack(
            "<IIIIII",
            width,
            height,
            packed,
            packed,
            header_length,
            payload_bytes,
        )
    )
    return header + b"\x10" * payload_bytes


def _depthbin_payload(width: int = 2, height: int = 2) -> bytes:
    """Structurally valid HTDTDPT1 v1.0 payload (f32 depths)."""
    import struct

    header = (
        b"HTDTDPT1"
        + struct.pack("<HHI", 1, 0, 32)
        + struct.pack("<IIBBH I", width, height, 1, 0, 0, 0)
    )
    return header + struct.pack("<" + "f" * width * height, *([1.0] * width * height))


def _confidencebin_payload(width: int = 2, height: int = 2) -> bytes:
    """Structurally valid HTDTCNF1 v1.0 payload."""
    import struct

    header = (
        b"HTDTCNF1"
        + struct.pack("<HHI", 1, 0, 32)
        + struct.pack("<IIBBH I", width, height, 1, 0, 0, 0)
    )
    return header + bytes([2] * (width * height))


def _frame_descriptor(
    pixel_path: str,
    pixel_payload: bytes,
    *,
    frame_id: str = "10000000-0000-4000-8000-000000000010",
    capture_session_id: str = SESSION_ID,
    coordinate_space_id: str = COORDINATE_SPACE_ID,
    image_width: int = 2,
    image_height: int = 2,
    depth_status: str = "not_requested",
    depth=None,
) -> dict:
    return {
        "frame_id": frame_id,
        "capture_session_id": capture_session_id,
        "coordinate_space_id": coordinate_space_id,
        "session_timestamp_s": 1.25,
        "T_world_from_camera": {
            "representation": "column_major_4x4_f32",
            "values": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        },
        "intrinsics": {
            "representation": "column_major_3x3_f32",
            "values": [1, 0, 0, 0, 1, 0, 0, 0, 1],
        },
        "image_width": image_width,
        "image_height": image_height,
        "pixel_format_fourcc": 875704438,
        "pixel_relative_path": pixel_path,
        "pixel_byte_count": len(pixel_payload),
        "pixel_sha256": hashlib.sha256(pixel_payload).hexdigest(),
        "exif_allowlisted": {},
        "depth_status": depth_status,
        "depth": depth,
    }


def _stage_frame(copy_root: Path, **overrides) -> None:
    """Add a consistent pixelbin + frame descriptor pair to a bundle."""
    frame_id = overrides.get("frame_id", "10000000-0000-4000-8000-000000000010")
    pixel_path = overrides.pop(
        "pixel_path", f"evidence/frames/{frame_id}.pixelbin"
    )
    width = overrides.pop("image_width", 2)
    height = overrides.pop("image_height", 2)
    pixel_payload = overrides.pop(
        "pixel_payload", _pixelbin_payload(width, height)
    )
    descriptor_path = f"evidence/frames/{frame_id}.json"
    descriptor = _frame_descriptor(
        pixel_path,
        pixel_payload,
        image_width=width,
        image_height=height,
        **overrides,
    )

    _add_payload(
        copy_root,
        pixel_path,
        pixel_payload,
        media_type="application/vnd.htdt.pixelbin",
    )
    _add_payload(
        copy_root,
        descriptor_path,
        json.dumps(
            descriptor,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        source_refs=[f"path:{pixel_path}"],
    )


class ReferenceIngestorTests(unittest.TestCase):
    def test_frozen_fixture_validates_with_expected_bundle_digest(self):
        report = validate_bundle(FIXTURE)
        self.assertTrue(report["valid"])
        self.assertEqual(report["bundle_digest"], EXPECTED_BUNDLE_DIGEST)
        self.assertEqual(report["payload_count"], 10)

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

            # #194: processed-only RoomPlan promotion is rejected at the
            # validator boundary before ingestion.
            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("raw lineage", str(ctx.exception))
            with self.assertRaises(ValidationError):
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

            # #194: a processed RoomPlan payload that fails to name its
            # raw authority is rejected at the validator boundary.
            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("raw authority", str(ctx.exception))
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_missing_quality_payload_blocks_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _drop_payload(copy_root, QUALITY_PATH)

            # #194: capture-quality.json is a required foundation
            # payload; the validator fails closed first.
            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("quality", str(ctx.exception))
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

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
            # Malformed schema-owned JSON is rejected at the bundle
            # validation boundary before the ingestor's own gate runs.
            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("integrity_status", str(ctx.exception))
            with self.assertRaises(ValidationError):
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

    def test_session_document_identity_mismatch_fails_ingestion(self):
        for field, value in (
            ("capture_session_id", "20000000-0000-4000-8000-0000000000aa"),
            ("coordinate_space_id", "20000000-0000-4000-8000-0000000000bb"),
        ):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)

                    def mutate(document, field=field, value=value):
                        document[field] = value

                    _rewrite_payload(
                        copy_root,
                        "session/capture-session.json",
                        mutate,
                    )
                    # #194: the validator now grounds manifest identity
                    # arrays in the session authority, so this fails
                    # closed at validation before ingestion.
                    with self.assertRaises(ValidationError) as ctx:
                        validate_bundle(copy_root)
                    self.assertIn(field, str(ctx.exception))
                    with self.assertRaises(ValidationError):
                        build_ingestion_plan(copy_root)

    def test_session_document_dangling_timing_ref_fails_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _drop_payload(copy_root, "session/timing.json")

            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            session_entry = next(
                entry
                for entry in manifest["files"]
                if entry["path"] == "session/capture-session.json"
            )
            session_entry["source_refs"] = [
                "path:session/capture-configuration.json"
            ]
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            # #194: session/timing.json is a required foundation
            # payload, so the hardened validator fails closed before
            # the ingestor's timing_ref check is reached.
            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("foundation", str(ctx.exception))
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_session_document_wrong_configuration_ref_fails(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                document["configuration_ref"] = "session/other.json"

            _rewrite_payload(
                copy_root, "session/capture-session.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("configuration_ref", str(ctx.exception))

    def test_frame_descriptor_with_valid_pixel_link_ingests(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _stage_frame(copy_root)

            validate_bundle(copy_root)
            plan = build_ingestion_plan(copy_root)
            self.assertIn(
                "evidence/frames/10000000-0000-4000-8000-000000000010.json",
                {record["path"] for record in plan["source_evidence"]},
            )

    def test_frame_with_undeclared_session_or_coordinate_fails(self):
        for field in ("capture_session_id", "coordinate_space_id"):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)
                    _stage_frame(
                        copy_root,
                        **{field: "20000000-0000-4000-8000-0000000000cc"},
                    )

                    # The hardened bundle boundary fails closed before
                    # the ingestor ever sees the descriptor.
                    with self.assertRaises(ValidationError) as ctx:
                        validate_bundle(copy_root)
                    self.assertIn(field, str(ctx.exception))
                    with self.assertRaises(ValidationError):
                        build_ingestion_plan(copy_root)

    def test_frame_pixel_reference_must_resolve_to_declared_payload(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            pixel_payload = b"\x10" * 32
            descriptor = _frame_descriptor(
                "evidence/frames/missing.pixelbin", pixel_payload
            )
            _add_payload(
                copy_root,
                "evidence/frames/10000000-0000-4000-8000-000000000010.json",
                json.dumps(
                    descriptor, ensure_ascii=False, sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8"),
                source_refs=["path:evidence/frames/missing.pixelbin"],
            )

            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("missing.pixelbin", str(ctx.exception))
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_frame_pixel_hash_mismatch_fails_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            pixel_payload = _pixelbin_payload()
            descriptor = _frame_descriptor(
                "evidence/frames/10000000-0000-4000-8000-000000000010.pixelbin",
                pixel_payload,
            )
            descriptor["pixel_sha256"] = hashlib.sha256(
                b"different"
            ).hexdigest()

            _add_payload(
                copy_root,
                descriptor["pixel_relative_path"],
                pixel_payload,
                media_type="application/vnd.htdt.pixelbin",
            )
            _add_payload(
                copy_root,
                "evidence/frames/10000000-0000-4000-8000-000000000010.json",
                json.dumps(
                    descriptor, ensure_ascii=False, sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8"),
                source_refs=[f"path:{descriptor['pixel_relative_path']}"],
            )

            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("pixel", str(ctx.exception).lower())
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_frame_depth_status_contradicts_missing_depth_reference(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _stage_frame(copy_root, depth_status="captured_scene_depth")

            with self.assertRaises(ValidationError) as ctx:
                validate_bundle(copy_root)
            self.assertIn("depth_status", str(ctx.exception))
            with self.assertRaises(ValidationError):
                build_ingestion_plan(copy_root)

    def test_annotation_evidence_refs_resolve_to_mesh_handoff(self):
        plan = build_ingestion_plan(FIXTURE)
        annotation = next(
            record
            for record in plan["authority_records"]
            if record["record_kind"] == "annotation"
        )
        self.assertEqual(
            annotation["resolved_evidence"],
            [
                {
                    "ref": f"mesh_anchor:{ANCHOR_ID}",
                    "kind": "raw_visual_mesh_handoff",
                    "target": EXPECTED_RAW_VISUAL_MESH_HANDOFF_ID,
                }
            ],
        )
        measurement = next(
            record
            for record in plan["authority_records"]
            if record["record_kind"] == "measurement"
        )
        self.assertEqual(
            measurement["resolved_evidence"],
            [
                {
                    "ref": "user:tape_measure",
                    "kind": "annotation_authored",
                    "target": None,
                }
            ],
        )

    def test_dangling_path_evidence_ref_fails_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                document["entities"][0]["evidence_refs"] = [
                    "path:evidence/frames/missing.json"
                ]

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("undeclared bundle path", str(ctx.exception))

    def test_nonexistent_mesh_anchor_ref_fails_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                document["entities"][0]["placement"][
                    "source_mesh_anchor_id"
                ] = "20000000-0000-4000-8000-0000000000dd"

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("unknown mesh anchor", str(ctx.exception))

    def test_wrong_kind_evidence_ref_fails_ingestion(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                # The anchor UUID exists but is not a frame identity.
                document["entities"][0]["evidence_refs"] = [
                    f"frame:{ANCHOR_ID}"
                ]

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("unknown frame", str(ctx.exception))

    def test_raycast_placement_provenance_ingests(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                placement = document["entities"][0]["placement"]
                placement["method"] = "raycast"
                placement["raycast"] = {
                    "target_type": "wall_surface",
                    "hit_distance_m": 2.4,
                    "hit_anchor_id": ANCHOR_ID,
                    "T_world_from_hit": {
                        "representation": "column_major_4x4_f32",
                        "values": [
                            1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, 0,
                            1.0, 0.0, 2.0, 1,
                        ],
                    },
                }

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            build_ingestion_plan(copy_root)

    def test_raycast_placement_rejects_empty_hit_anchor_id(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                placement = document["entities"][0]["placement"]
                placement["method"] = "raycast"
                placement["raycast"] = {
                    "target_type": "wall_surface",
                    "hit_anchor_id": "",
                }

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("hit_anchor_id", str(ctx.exception))

    def test_unsupported_evidence_ref_grammar_fails_ingestion(self):
        for ref in ("opaque-token", "sha256:" + "0" * 64, "bogus:x"):
            with self.subTest(ref=ref):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)

                    def mutate(document, ref=ref):
                        document["measurements"][0]["evidence_refs"] = [ref]

                    _rewrite_payload(
                        copy_root, "annotations/measurements.json", mutate
                    )
                    validate_bundle(copy_root)
                    with self.assertRaises(IngestionError) as ctx:
                        build_ingestion_plan(copy_root)
                    self.assertIn("reference grammar", str(ctx.exception))

    def test_frame_evidence_ref_resolves_to_frame_source_evidence(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            frame_id = "10000000-0000-4000-8000-000000000010"
            _stage_frame(copy_root, frame_id=frame_id)

            def mutate(document):
                document["entities"][0]["evidence_refs"] = [
                    f"frame:{frame_id}",
                    "path:evidence/frames/"
                    f"{frame_id}.json",
                ]

            _rewrite_payload(
                copy_root, "annotations/entities.json", mutate
            )
            validate_bundle(copy_root)
            plan = build_ingestion_plan(copy_root)
            annotation = next(
                record
                for record in plan["authority_records"]
                if record["record_kind"] == "annotation"
            )
            descriptor_evidence_id = next(
                record["source_evidence_id"]
                for record in plan["source_evidence"]
                if record["path"] == f"evidence/frames/{frame_id}.json"
            )
            mesh_handoff_id = plan["raw_visual_mesh_handoffs"][0][
                "raw_visual_mesh_handoff_id"
            ]
            self.assertEqual(
                annotation["resolved_evidence"],
                [
                    {
                        "ref": f"frame:{frame_id}",
                        "kind": "source_evidence",
                        "target": descriptor_evidence_id,
                    },
                    {
                        "ref": f"mesh_anchor:{ANCHOR_ID}",
                        "kind": "raw_visual_mesh_handoff",
                        "target": mesh_handoff_id,
                    },
                    {
                        "ref": f"path:evidence/frames/{frame_id}.json",
                        "kind": "source_evidence",
                        "target": descriptor_evidence_id,
                    },
                ],
            )

    def test_measurement_endpoint_refs_resolve_and_stay_spatial(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                measurement = document["measurements"][0]
                measurement["endpoint_refs"] = [
                    "entity:10000000-0000-4000-8000-000000000006"
                ]

            _rewrite_payload(
                copy_root, "annotations/measurements.json", mutate
            )
            validate_bundle(copy_root)
            plan = build_ingestion_plan(copy_root)
            measurement = next(
                record
                for record in plan["authority_records"]
                if record["record_kind"] == "measurement"
            )
            annotation_handoff_id = next(
                record["authority_record_handoff_id"]
                for record in plan["authority_records"]
                if record["record_kind"] == "annotation"
            )
            self.assertEqual(
                measurement["resolved_endpoints"],
                [
                    {
                        "ref": (
                            "entity:"
                            "10000000-0000-4000-8000-000000000006"
                        ),
                        "kind": "authority_record",
                        "target": annotation_handoff_id,
                    }
                ],
            )

    def test_measurement_spatial_endpoints_require_coordinate_space(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            def mutate(document):
                measurement = document["measurements"][0]
                measurement["coordinate_space_id"] = None
                measurement["endpoint_refs"] = [
                    "entity:10000000-0000-4000-8000-000000000006"
                ]

            _rewrite_payload(
                copy_root, "annotations/measurements.json", mutate
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("endpoint_refs", str(ctx.exception))

    def test_roomplan_provenance_at_noncanonical_path_fails(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            _add_payload(
                copy_root,
                "evidence/arbitrary.json",
                b"{}",
                producer="annotation",
                provenance_class="apple_roomplan_raw_scan",
            )

            validate_bundle(copy_root)
            with self.assertRaises(IngestionError) as ctx:
                build_ingestion_plan(copy_root)
            self.assertIn("canonical", str(ctx.exception))

    def test_canonical_roomplan_path_with_wrong_metadata_fails(self):
        mutations = [
            ("provenance_class", "user_annotation"),
            ("media_type", "application/octet-stream"),
            ("producer", "annotation"),
            ("role", "derived"),
        ]
        for field, value in mutations:
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)

                    manifest_path = copy_root / "manifest.json"
                    manifest = json.loads(
                        manifest_path.read_text(encoding="utf-8")
                    )
                    entry = next(
                        item
                        for item in manifest["files"]
                        if item["path"]
                        == "roomplan/captured-room-data.json"
                    )
                    entry[field] = value
                    manifest_path.write_bytes(
                        canonical_json_bytes(manifest)
                    )

                    validate_bundle(copy_root)
                    with self.assertRaises(IngestionError):
                        build_ingestion_plan(copy_root)

    def test_legacy_bundle_without_canonical_paths_uses_provenance(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)

            # A legacy bundle carries RoomPlan payloads at non-reserved
            # paths; selection falls back to provenance-class membership.
            renames = {
                "roomplan/captured-room-data.json": (
                    "legacy/roomplan-raw.json"
                ),
                "roomplan/captured-room.json": (
                    "legacy/roomplan-processed.json"
                ),
            }
            manifest_path = copy_root / "manifest.json"
            manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            for old_path, new_path in renames.items():
                payload = (copy_root / old_path).read_bytes()
                (copy_root / old_path).unlink()
                target = copy_root / new_path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
                for entry in manifest["files"]:
                    if entry["path"] == old_path:
                        entry["path"] = new_path
            manifest["files"].sort(
                key=lambda item: item["path"].encode("utf-8")
            )
            manifest_path.write_bytes(canonical_json_bytes(manifest))

            validate_bundle(copy_root)
            plan = build_ingestion_plan(copy_root)
            self.assertEqual(
                [
                    (record["kind"], record["path"])
                    for record in plan["roomplan_records"]
                ],
                [
                    (
                        "postprocessed_inference",
                        "legacy/roomplan-processed.json",
                    ),
                    ("raw_scan", "legacy/roomplan-raw.json"),
                ],
            )

    def test_absent_roomplan_metadata_yields_no_metadata(self):
        plan = build_ingestion_plan(FIXTURE)
        self.assertIsNone(plan["roomplan_capture_metadata"])
        self.assertTrue(
            all(
                record["roomplan_capture_metadata"] is None
                for record in plan["roomplan_records"]
            )
        )

    def _stage_roomplan_metadata(self, copy_root: Path, **overrides):
        manifest = json.loads(
            (copy_root / "manifest.json").read_text(encoding="utf-8")
        )
        by_path = {entry["path"]: entry for entry in manifest["files"]}
        document = {
            "schema": "htdt.captured-room-metadata",
            "schema_version": "1.0.0",
            "capture_revision_id": manifest["capture_revision_id"],
            "capture_session_id": SESSION_ID,
            "coordinate_space_id": COORDINATE_SPACE_ID,
            "raw_payload_path": "roomplan/captured-room-data.json",
            "raw_sha256": by_path["roomplan/captured-room-data.json"][
                "sha256"
            ],
            "processed_payload_path": "roomplan/captured-room.json",
            "processed_sha256": by_path["roomplan/captured-room.json"][
                "sha256"
            ],
            "surface_count": 4,
            "object_count": 1,
            "dimensions": {
                "width_m": 3.4,
                "depth_m": 4.0,
                "height_m": 2.5,
            },
        }
        document.update(overrides)
        _add_payload(
            copy_root,
            "roomplan/captured-room-metadata.json",
            json.dumps(
                document,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8"),
            producer="roomplan_capture",
            provenance_class="capture_app_derived",
        )

    def test_roomplan_capture_metadata_binds_records_and_plan(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            self._stage_roomplan_metadata(copy_root)

            validate_bundle(copy_root)
            plan = build_ingestion_plan(copy_root)
            metadata = plan["roomplan_capture_metadata"]
            self.assertEqual(
                metadata["schema"], "htdt.captured-room-metadata"
            )
            self.assertEqual(metadata["surface_count"], 4)

            by_path = {
                record["path"]: record
                for record in plan["roomplan_records"]
            }
            self.assertIs(
                by_path["roomplan/captured-room-data.json"][
                    "roomplan_capture_metadata"
                ],
                metadata,
            )
            self.assertIs(
                by_path["roomplan/captured-room.json"][
                    "roomplan_capture_metadata"
                ],
                metadata,
            )

    def test_roomplan_metadata_identity_conflict_fails(self):
        for field, value in (
            ("capture_revision_id", "20000000-0000-4000-8000-0000000000ee"),
            ("capture_session_id", "20000000-0000-4000-8000-0000000000ee"),
            ("coordinate_space_id", "20000000-0000-4000-8000-0000000000ee"),
        ):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)
                    self._stage_roomplan_metadata(
                        copy_root, **{field: value}
                    )
                    validate_bundle(copy_root)
                    with self.assertRaises(IngestionError):
                        build_ingestion_plan(copy_root)

    def test_roomplan_metadata_wrong_raw_path_or_hash_fails(self):
        for field, value in (
            ("raw_payload_path", "roomplan/captured-room.json"),
            ("raw_sha256", "0" * 64),
            ("processed_sha256", "0" * 64),
        ):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as td:
                    copy_root = Path(td) / "bundle"
                    shutil.copytree(FIXTURE, copy_root)
                    self._stage_roomplan_metadata(
                        copy_root, **{field: value}
                    )
                    validate_bundle(copy_root)
                    with self.assertRaises(IngestionError):
                        build_ingestion_plan(copy_root)

    def test_roomplan_metadata_incomplete_processed_pair_fails(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            self._stage_roomplan_metadata(
                copy_root, processed_sha256=None
            )
            validate_bundle(copy_root)
            with self.assertRaises(IngestionError):
                build_ingestion_plan(copy_root)

    def test_generated_plan_conforms_to_published_schema(self):
        plan = build_ingestion_plan(FIXTURE)
        self.assertEqual(
            plan_schema.validate_plan_document(plan),
            [],
        )

    def test_plan_with_roomplan_metadata_conforms_to_schema(self):
        with tempfile.TemporaryDirectory() as td:
            copy_root = Path(td) / "bundle"
            shutil.copytree(FIXTURE, copy_root)
            self._stage_roomplan_metadata(copy_root)
            plan = build_ingestion_plan(copy_root)
            self.assertEqual(
                plan_schema.validate_plan_document(plan),
                [],
            )

    def test_schema_rejects_malformed_plan_variants(self):
        plan = build_ingestion_plan(FIXTURE)

        def extra_source_field(variant):
            variant["source_evidence"][0]["unexpected"] = True

        def wrong_roomplan_provenance(variant):
            record = next(
                item
                for item in variant["roomplan_records"]
                if item["kind"] == "raw_scan"
            )
            record["provenance_class"] = "apple_roomplan_inference"

        def bad_uuid(variant):
            variant["bundle"]["capture_series_id"] = "not-a-uuid"

        def short_transform(variant):
            variant["raw_visual_mesh_handoffs"][0][
                "T_world_from_mesh_anchor"
            ]["values"] = [0.0] * 15

        def missing_required(variant):
            del variant["roomplan_capture_metadata"]

        def bad_provenance_enum(variant):
            variant["source_evidence"][0]["provenance_class"] = "unknown"

        def bad_resolution_kind(variant):
            variant["authority_records"][0]["resolved_evidence"] = [
                {"ref": "user:x", "kind": "bogus", "target": None}
            ]

        def locator_kind_mismatch(variant):
            variant["authority_records"][0]["record_locator"] = (
                "annotations/measurements.json#measurement:"
                "10000000-0000-4000-8000-000000000006"
            )

        def bad_source_ref(variant):
            variant["source_evidence"][0]["source_refs"] = ["opaque:x"]

        def bad_evidence_ref(variant):
            variant["authority_records"][0]["evidence_refs"] = [
                "unsupported:thing"
            ]

        for mutate in (
            extra_source_field,
            wrong_roomplan_provenance,
            bad_uuid,
            short_transform,
            missing_required,
            bad_provenance_enum,
            bad_resolution_kind,
            locator_kind_mismatch,
            bad_source_ref,
            bad_evidence_ref,
        ):
            with self.subTest(mutate=mutate.__name__):
                variant = copy.deepcopy(plan)
                mutate(variant)
                self.assertNotEqual(
                    plan_schema.validate_plan_document(variant),
                    [],
                )

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

            # The bundle validator now enforces the frozen source_refs
            # grammar itself, so the unknown namespace fails closed at the
            # validation boundary before ingestion is ever attempted.
            with self.assertRaises(ValidationError):
                validate_bundle(copy_root)
            with self.assertRaises(ValidationError):
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

            # The validator now cross-checks mesh anchor
            # coordinate_space_id values against the manifest, so the
            # rewritten reference fails at the bundle boundary.
            with self.assertRaises(ValidationError):
                validate_bundle(copy_root)
            with self.assertRaises(ValidationError):
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
