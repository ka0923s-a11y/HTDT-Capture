"""Deterministic reference ingestor for validated HTDT Capture Bundle v1.

This module defines the Phase 6 source-lineage handoff. It does not create
SemanticAcousticGeometry or solver authorities.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import unicodedata
import zipfile

if __package__ in (None, ""):
    repo_root = Path(__file__).resolve().parents[2]
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))

from tools.bundle_validator.validator import (
    PROVENANCE,
    DirectorySource,
    ValidationError,
    ZipSource,
    canonical_json_bytes,
    parse_json_bytes,
    validate_bundle,
    validate_relative_path,
    validate_uuid4,
)

INGESTOR_NAME = "htdt-capture-reference-ingestor"
INGESTOR_VERSION = "1.0.0"
PLAN_SCHEMA = "htdt.capture.ingestion-plan"
PLAN_SCHEMA_VERSION = "1.0.0"
CONFIGURATION = {
    "schema_version": PLAN_SCHEMA_VERSION,
    "strict": True,
}


class IngestionError(ValueError):
    pass


def _hash_parts(prefix: str, *parts: str) -> str:
    digest = hashlib.sha256(prefix.encode("utf-8"))
    for part in parts:
        digest.update(b"\x00")
        digest.update(part.encode("utf-8"))
    return digest.hexdigest()


def _validate_finite_json(value, path: str = "$") -> None:
    if value is None or isinstance(value, bool) or isinstance(value, int):
        return
    if isinstance(value, float):
        if not math.isfinite(value):
            raise IngestionError(f"non-finite number at {path}")
        return
    if isinstance(value, str):
        if unicodedata.normalize("NFC", value) != value:
            raise IngestionError(f"non-NFC string at {path}")
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            _validate_finite_json(child, f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise IngestionError(f"non-string object key at {path}")
            if unicodedata.normalize("NFC", key) != key:
                raise IngestionError(f"non-NFC key at {path}: {key!r}")
            _validate_finite_json(child, f"{path}.{key}")
        return
    raise IngestionError(f"unsupported JSON value at {path}: {type(value).__name__}")


def canonical_plan_bytes(value) -> bytes:
    _validate_finite_json(value)
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


class ValidatedBundleReader:
    """Serves bundle payloads from bytes frozen at the validation boundary.

    ``validate_bundle(path)`` proves the on-disk bundle matches its canonical
    manifest and yields the authoritative ``bundle_digest``. The reader then
    snapshots every bundle member once through the validator's own source
    abstraction and re-verifies the snapshot against the validated manifest:
    the frozen manifest must hash to ``bundle_digest``, the frozen file set
    must equal the declared payload set, and every frozen payload must match
    its manifest byte length and SHA-256. All ``read`` calls then serve only
    these frozen, hash-verified bytes, so the bytes parsed by ingestion are
    exactly the bytes hashed into ``bundle_digest`` even if the supplied path
    mutates after validation. A mutable input therefore fails closed instead
    of producing lineage bound to stale hashes.
    """

    def __init__(self, path: Path):
        self.path = path
        self.report = validate_bundle(path)
        self._payloads = self._freeze_verified_payloads()

    def _freeze_verified_payloads(self) -> dict[str, bytes]:
        source: DirectorySource | ZipSource
        archive: zipfile.ZipFile | None = None
        if self.path.is_dir():
            source = DirectorySource(self.path)
        else:
            source = ZipSource(self.path)
            archive = source.zf
        try:
            payloads = {
                name: source.read_bytes(name)
                for name in source.list_files()
            }
        finally:
            if archive is not None:
                archive.close()

        manifest_bytes = payloads.get("manifest.json")
        if manifest_bytes is None:
            raise IngestionError(
                "manifest.json missing from bundle after validation"
            )
        digest = hashlib.sha256(manifest_bytes).hexdigest()
        if digest != self.report["bundle_digest"]:
            raise IngestionError(
                "bundle manifest changed after validation: "
                "refusing to ingest bytes outside the validated digest"
            )

        manifest = parse_json_bytes(manifest_bytes)
        declared = {entry["path"]: entry for entry in manifest["files"]}
        expected = set(declared) | {"manifest.json"}
        if set(payloads) != expected:
            raise IngestionError(
                "bundle file set changed after validation: "
                "refusing to ingest a mutated bundle"
            )
        for entry_path, entry in declared.items():
            data = payloads[entry_path]
            if (
                len(data) != entry["bytes"]
                or hashlib.sha256(data).hexdigest() != entry["sha256"]
            ):
                raise IngestionError(
                    "bundle payload changed after validation: "
                    f"{entry_path}"
                )
        return payloads

    def close(self) -> None:
        self._payloads = None

    def read(self, logical_path: str) -> bytes:
        logical_path = validate_relative_path(logical_path)
        if self._payloads is None:
            raise IngestionError("bundle reader is closed")
        try:
            return self._payloads[logical_path]
        except KeyError as exc:
            raise IngestionError(
                f"validated bundle payload unexpectedly missing: {logical_path}"
            ) from exc


def _source_evidence_id(
    bundle_digest: str,
    path: str,
    payload_sha256: str,
) -> str:
    return _hash_parts(
        "htdt.capture.source-evidence.v1",
        bundle_digest,
        path,
        payload_sha256,
    )


def _raw_visual_mesh_handoff_id(
    bundle_digest: str,
    anchor_id: str,
    geometry_sha256: str,
) -> str:
    return _hash_parts(
        "htdt.capture.raw-visual-mesh-handoff.v1",
        bundle_digest,
        anchor_id,
        geometry_sha256,
    )


def _authority_record_handoff_id(
    bundle_digest: str,
    source_payload_sha256: str,
    record_kind: str,
    record_id: str,
) -> str:
    return _hash_parts(
        "htdt.capture.authority-record.v1",
        bundle_digest,
        source_payload_sha256,
        record_kind,
        record_id,
    )


def _require_schema(document: dict, schema: str) -> None:
    if not isinstance(document, dict):
        raise IngestionError(f"{schema} document root must be an object")
    if document.get("schema") != schema:
        raise IngestionError(
            f"unexpected document schema: expected {schema!r}, "
            f"got {document.get('schema')!r}"
        )
    if document.get("schema_version") != "1.0.0":
        raise IngestionError(
            f"unsupported {schema} schema version: "
            f"{document.get('schema_version')!r}"
        )


def _validate_transform(value, field: str) -> None:
    if not isinstance(value, dict):
        raise IngestionError(f"{field} must be an object")
    if value.get("representation") != "column_major_4x4_f32":
        raise IngestionError(f"unsupported {field} representation")
    values = value.get("values")
    if not isinstance(values, list) or len(values) != 16:
        raise IngestionError(f"{field}.values must contain 16 numbers")
    for index, component in enumerate(values):
        if (
            not isinstance(component, (int, float))
            or isinstance(component, bool)
            or not math.isfinite(component)
        ):
            raise IngestionError(
                f"{field}.values[{index}] must be finite"
            )


def _build_source_registry(
    manifest: dict,
    bundle_digest: str,
) -> tuple[list[dict], dict[str, dict]]:
    records: list[dict] = []
    by_path: dict[str, dict] = {}
    hashes = {entry["sha256"] for entry in manifest["files"]}
    paths = {entry["path"] for entry in manifest["files"]}
    raw_roomplan_hashes = {
        entry["sha256"]
        for entry in manifest["files"]
        if entry["provenance_class"] == "apple_roomplan_raw_scan"
    }

    for entry in manifest["files"]:
        path = entry["path"]
        refs = entry.get("source_refs", [])
        resolved_sha_refs: list[str] = []

        for source_ref in refs:
            if source_ref.startswith("sha256:"):
                target_hash = source_ref.removeprefix("sha256:")
                if target_hash not in hashes:
                    raise IngestionError(
                        f"unresolved SHA-256 source_ref for {path}: "
                        f"{source_ref}"
                    )
                resolved_sha_refs.append(target_hash)
            elif source_ref.startswith("path:"):
                target_path = source_ref.removeprefix("path:")
                if target_path not in paths:
                    raise IngestionError(
                        f"unresolved path source_ref for {path}: "
                        f"{source_ref}"
                    )
            else:
                raise IngestionError(
                    f"unsupported source_ref for {path}: {source_ref}"
                )

        if entry["provenance_class"] == "apple_roomplan_inference":
            raw_refs = [
                value
                for value in resolved_sha_refs
                if value in raw_roomplan_hashes
            ]
            if len(raw_refs) != 1:
                raise IngestionError(
                    "processed RoomPlan must reference exactly one raw "
                    "RoomPlan payload SHA-256"
                )

        record = {
            "source_evidence_id": _source_evidence_id(
                bundle_digest,
                path,
                entry["sha256"],
            ),
            "bundle_digest": bundle_digest,
            "capture_revision_id": manifest["capture_revision_id"],
            "path": path,
            "payload_sha256": entry["sha256"],
            "bytes": entry["bytes"],
            "media_type": entry["media_type"],
            "producer": entry["producer"],
            "provenance_class": entry["provenance_class"],
            "role": entry["role"],
            "source_refs": entry.get("source_refs", []),
        }
        records.append(record)
        by_path[path] = record

    records.sort(key=lambda item: item["path"].encode("utf-8"))
    return records, by_path


def _build_roomplan_records(
    manifest: dict,
    source_by_path: dict[str, dict],
) -> list[dict]:
    result: list[dict] = []
    for entry in manifest["files"]:
        provenance = entry["provenance_class"]
        if provenance not in {
            "apple_roomplan_raw_scan",
            "apple_roomplan_inference",
        }:
            continue
        result.append(
            {
                "kind": (
                    "raw_scan"
                    if provenance == "apple_roomplan_raw_scan"
                    else "postprocessed_inference"
                ),
                "source_evidence_id": source_by_path[entry["path"]][
                    "source_evidence_id"
                ],
                "path": entry["path"],
                "payload_sha256": entry["sha256"],
                "provenance_class": provenance,
                "source_refs": entry.get("source_refs", []),
            }
        )
    result.sort(key=lambda item: item["path"].encode("utf-8"))
    return result


def _build_raw_visual_mesh_handoffs(
    reader: ValidatedBundleReader,
    manifest: dict,
    bundle_digest: str,
    source_by_path: dict[str, dict],
) -> list[dict]:
    index_path = "mesh/anchors.json"
    if index_path not in source_by_path:
        return []

    index_source = source_by_path[index_path]
    if index_source["provenance_class"] != "arkit_mesh_reconstruction":
        raise IngestionError(
            "mesh/anchors.json must retain arkit_mesh_reconstruction provenance"
        )

    document = parse_json_bytes(reader.read(index_path))
    _require_schema(document, "htdt.capture.mesh-anchors")
    anchors = document.get("anchors")
    if not isinstance(anchors, list):
        raise IngestionError("mesh anchors must be an array")

    session_ids = set(manifest["capture_session_ids"])
    coordinate_ids = set(manifest["coordinate_space_ids"])
    result: list[dict] = []
    seen_anchors: set[str] = set()

    for index, anchor in enumerate(anchors):
        if not isinstance(anchor, dict):
            raise IngestionError(f"anchors[{index}] must be an object")
        anchor_id = anchor.get("anchor_id")
        validate_uuid4(anchor_id, f"anchors[{index}].anchor_id")
        if anchor_id in seen_anchors:
            raise IngestionError(f"duplicate mesh anchor ID: {anchor_id}")
        seen_anchors.add(anchor_id)

        capture_session_id = anchor.get("capture_session_id")
        coordinate_space_id = anchor.get("coordinate_space_id")
        validate_uuid4(
            capture_session_id,
            f"anchors[{index}].capture_session_id",
        )
        validate_uuid4(
            coordinate_space_id,
            f"anchors[{index}].coordinate_space_id",
        )
        if capture_session_id not in session_ids:
            raise IngestionError(
                f"mesh anchor references unknown capture_session_id: "
                f"{capture_session_id}"
            )
        if coordinate_space_id not in coordinate_ids:
            raise IngestionError(
                f"mesh anchor references unknown coordinate_space_id: "
                f"{coordinate_space_id}"
            )

        geometry_path = anchor.get("geometry_path")
        geometry_sha256 = anchor.get("geometry_sha256")
        if (
            not isinstance(geometry_path, str)
            or geometry_path not in source_by_path
        ):
            raise IngestionError(
                f"mesh anchor geometry payload missing: {geometry_path!r}"
            )
        geometry_source = source_by_path[geometry_path]
        if geometry_source["provenance_class"] != "arkit_mesh_reconstruction":
            raise IngestionError(
                f"mesh geometry provenance is not ARKit reconstruction: "
                f"{geometry_path}"
            )
        if geometry_source["payload_sha256"] != geometry_sha256:
            raise IngestionError(
                f"mesh anchor geometry hash mismatch: {geometry_path}"
            )

        _validate_transform(
            anchor.get("T_world_from_mesh_anchor"),
            f"anchors[{index}].T_world_from_mesh_anchor",
        )
        vertex_count = anchor.get("vertex_count")
        face_count = anchor.get("face_count")
        if (
            not isinstance(vertex_count, int)
            or isinstance(vertex_count, bool)
            or vertex_count < 0
            or not isinstance(face_count, int)
            or isinstance(face_count, bool)
            or face_count < 0
        ):
            raise IngestionError("mesh anchor counts must be non-negative integers")
        timestamp = anchor.get("session_timestamp_s")
        if timestamp is not None and (
            not isinstance(timestamp, (int, float))
            or isinstance(timestamp, bool)
            or not math.isfinite(timestamp)
        ):
            raise IngestionError("mesh anchor timestamp must be finite")

        result.append(
            {
                "raw_visual_mesh_handoff_id": _raw_visual_mesh_handoff_id(
                    bundle_digest,
                    anchor_id,
                    geometry_sha256,
                ),
                "bundle_digest": bundle_digest,
                "anchor_id": anchor_id,
                "anchor_record_locator": (
                    f"{index_path}#anchor:{anchor_id}"
                ),
                "anchor_index_source_evidence_id": index_source[
                    "source_evidence_id"
                ],
                "geometry_source_evidence_id": geometry_source[
                    "source_evidence_id"
                ],
                "geometry_path": geometry_path,
                "geometry_sha256": geometry_sha256,
                "capture_session_id": capture_session_id,
                "coordinate_space_id": coordinate_space_id,
                "T_world_from_mesh_anchor": anchor[
                    "T_world_from_mesh_anchor"
                ],
                "session_timestamp_s": timestamp,
                "vertex_count": vertex_count,
                "face_count": face_count,
            }
        )

    result.sort(key=lambda item: item["anchor_id"])
    return result


def _build_authority_records(
    reader: ValidatedBundleReader,
    manifest: dict,
    bundle_digest: str,
    source_by_path: dict[str, dict],
) -> list[dict]:
    coordinate_ids = set(manifest["coordinate_space_ids"])
    result: list[dict] = []

    definitions = [
        (
            "annotations/entities.json",
            "htdt.capture.entities",
            "entities",
            "entity_id",
            "annotation",
        ),
        (
            "annotations/measurements.json",
            "htdt.capture.measurements",
            "measurements",
            "measurement_id",
            "measurement",
        ),
    ]

    for (
        path,
        schema,
        array_key,
        id_key,
        record_kind,
    ) in definitions:
        if path not in source_by_path:
            continue

        source = source_by_path[path]
        document = parse_json_bytes(reader.read(path))
        _require_schema(document, schema)
        records = document.get(array_key)
        if not isinstance(records, list):
            raise IngestionError(f"{path}:{array_key} must be an array")

        seen: set[str] = set()
        for index, record in enumerate(records):
            if not isinstance(record, dict):
                raise IngestionError(
                    f"{path}:{array_key}[{index}] must be an object"
                )
            record_id = record.get(id_key)
            validate_uuid4(
                record_id,
                f"{path}:{array_key}[{index}].{id_key}",
            )
            if record_id in seen:
                raise IngestionError(
                    f"duplicate {record_kind} record ID: {record_id}"
                )
            seen.add(record_id)

            provenance = record.get("provenance_class")
            if provenance not in PROVENANCE:
                raise IngestionError(
                    f"invalid record provenance: {provenance!r}"
                )

            coordinate_space_id = record.get("coordinate_space_id")
            if coordinate_space_id is not None:
                validate_uuid4(
                    coordinate_space_id,
                    f"{path}:{array_key}[{index}].coordinate_space_id",
                )
                if coordinate_space_id not in coordinate_ids:
                    raise IngestionError(
                        f"{record_kind} references unknown coordinate space: "
                        f"{coordinate_space_id}"
                    )

            result.append(
                {
                    "authority_record_handoff_id":
                        _authority_record_handoff_id(
                            bundle_digest,
                            source["payload_sha256"],
                            record_kind,
                            record_id,
                        ),
                    "record_kind": record_kind,
                    "record_id": record_id,
                    "record_locator": (
                        f"{path}#{record_kind}:{record_id}"
                    ),
                    "provenance_class": provenance,
                    "coordinate_space_id": coordinate_space_id,
                    "source_evidence_id": source["source_evidence_id"],
                    "source_payload_sha256": source["payload_sha256"],
                }
            )

    result.sort(
        key=lambda item: (
            item["record_kind"],
            item["record_id"],
        )
    )
    return result


def build_ingestion_plan(bundle_path: Path) -> dict:
    reader = ValidatedBundleReader(bundle_path)
    try:
        manifest = parse_json_bytes(reader.read("manifest.json"))
        bundle_digest = reader.report["bundle_digest"]

        source_records, source_by_path = _build_source_registry(
            manifest,
            bundle_digest,
        )
        roomplan_records = _build_roomplan_records(
            manifest,
            source_by_path,
        )
        raw_mesh_handoffs = _build_raw_visual_mesh_handoffs(
            reader,
            manifest,
            bundle_digest,
            source_by_path,
        )
        authority_records = _build_authority_records(
            reader,
            manifest,
            bundle_digest,
            source_by_path,
        )

        configuration_digest = hashlib.sha256(
            canonical_json_bytes(CONFIGURATION)
        ).hexdigest()

        lineage_projection = {
            "bundle_digest": bundle_digest,
            "source_evidence_ids": sorted(
                record["source_evidence_id"]
                for record in source_records
            ),
            "raw_visual_mesh_ids": sorted(
                record["raw_visual_mesh_handoff_id"]
                for record in raw_mesh_handoffs
            ),
            "authority_record_ids": sorted(
                record["authority_record_handoff_id"]
                for record in authority_records
            ),
        }
        lineage_digest = hashlib.sha256(
            canonical_json_bytes(lineage_projection)
        ).hexdigest()

        plan = {
            "schema": PLAN_SCHEMA,
            "schema_version": PLAN_SCHEMA_VERSION,
            "ingestor": {
                "name": INGESTOR_NAME,
                "version": INGESTOR_VERSION,
                "configuration_digest": configuration_digest,
            },
            "bundle": {
                "bundle_digest": bundle_digest,
                "capture_schema": manifest["schema"],
                "capture_schema_version": manifest["schema_version"],
                "capture_series_id": manifest["capture_series_id"],
                "capture_revision_id": manifest["capture_revision_id"],
                "parent_revision_id": manifest["parent_revision_id"],
                "capture_session_ids": manifest["capture_session_ids"],
                "coordinate_space_ids": manifest["coordinate_space_ids"],
            },
            "source_evidence": source_records,
            "roomplan_records": roomplan_records,
            "raw_visual_mesh_handoffs": raw_mesh_handoffs,
            "authority_records": authority_records,
            "lineage_digest": lineage_digest,
        }
        canonical_plan_bytes(plan)
        return plan
    finally:
        reader.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build deterministic HTDT ingestion lineage from a "
        "validated .htdtcapture bundle."
    )
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    try:
        plan = build_ingestion_plan(args.bundle)
        encoded = json.dumps(
            plan,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
            allow_nan=False,
        ) + "\n"
        if args.output:
            args.output.write_text(encoded, encoding="utf-8")
        else:
            print(encoded, end="")
        return 0
    except (ValidationError, IngestionError, OSError, zipfile.BadZipFile) as exc:
        print(f"ingestion failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
