"""Reference validator for HTDT Capture Bundle v1."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import unicodedata
from uuid import UUID
from datetime import datetime
import zipfile

SCHEMA = "htdt.capture.bundle"
SCHEMA_VERSION = "1.0.0"

MAX_ENTRIES = 10_000
MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_COMPRESSION_RATIO = 200.0

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PROVENANCE = {
    "arkit_frame_observation",
    "arkit_scene_depth_observation",
    "arkit_mesh_reconstruction",
    "apple_roomplan_raw_scan",
    "apple_roomplan_inference",
    "user_attested_measurement",
    "user_annotation",
    "imported_reference",
    "capture_app_derived",
    "backend_derived",
}
ROLES = {"canonical", "derived"}


class ValidationError(ValueError):
    pass


def _duplicate_checking_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError(f"duplicate JSON object key: {key!r}")
        result[key] = value
    return result


def parse_json_bytes(data: bytes):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValidationError(f"JSON is not valid UTF-8: {exc}") from exc
    if text.startswith("\ufeff"):
        raise ValidationError("UTF-8 BOM is not allowed")
    try:
        return json.loads(text, object_pairs_hook=_duplicate_checking_object)
    except ValidationError:
        raise
    except json.JSONDecodeError as exc:
        raise ValidationError(f"invalid JSON: {exc}") from exc


def _walk_json(value, *, reject_floats: bool, path: str = "$"):
    if isinstance(value, str):
        if unicodedata.normalize("NFC", value) != value:
            raise ValidationError(f"non-NFC string at {path}")
        return
    if value is None or isinstance(value, bool) or isinstance(value, int):
        return
    if isinstance(value, float):
        if reject_floats:
            raise ValidationError(f"floating-point value forbidden at {path}")
        if value != value or value in (float("inf"), float("-inf")):
            raise ValidationError(f"non-finite float at {path}")
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            _walk_json(child, reject_floats=reject_floats, path=f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ValidationError(f"non-string JSON key at {path}")
            if unicodedata.normalize("NFC", key) != key:
                raise ValidationError(f"non-NFC key at {path}: {key!r}")
            _walk_json(child, reject_floats=reject_floats, path=f"{path}.{key}")
        return
    raise ValidationError(f"unsupported JSON value at {path}: {type(value).__name__}")


def canonical_json_bytes(value) -> bytes:
    """Capture Bundle v1 canonical JSON for manifest-compatible values."""
    _walk_json(value, reject_floats=True)
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def validate_relative_path(path: str) -> str:
    if not isinstance(path, str) or not path:
        raise ValidationError("bundle path must be a non-empty string")
    if "\x00" in path:
        raise ValidationError(f"NUL in bundle path: {path!r}")
    if "\\" in path:
        raise ValidationError(f"backslash is forbidden in bundle path: {path!r}")
    pure = PurePosixPath(path)
    if pure.is_absolute():
        raise ValidationError(f"absolute bundle path forbidden: {path!r}")
    if any(part in ("", ".", "..") for part in pure.parts):
        raise ValidationError(f"unsafe bundle path: {path!r}")
    normalized = pure.as_posix()
    if normalized != path:
        raise ValidationError(f"non-normalized bundle path: {path!r}")
    return normalized


def validate_uuid4(text: str, field: str) -> None:
    if not isinstance(text, str) or text.lower() != text:
        raise ValidationError(f"{field} must be canonical lowercase UUID text")
    try:
        value = UUID(text)
    except (ValueError, AttributeError) as exc:
        raise ValidationError(f"{field} is not a UUID: {text!r}") from exc
    if str(value) != text or value.version != 4:
        raise ValidationError(f"{field} must be canonical UUIDv4 text: {text!r}")


def validate_manifest_shape(manifest: dict) -> None:
    if not isinstance(manifest, dict):
        raise ValidationError("manifest root must be an object")

    required = {
        "schema",
        "schema_version",
        "capture_series_id",
        "capture_revision_id",
        "parent_revision_id",
        "capture_session_ids",
        "coordinate_space_ids",
        "created_at",
        "finalized_at",
        "app",
        "files",
    }
    extra = set(manifest) - required
    missing = required - set(manifest)
    if extra or missing:
        raise ValidationError(f"manifest keys mismatch: missing={sorted(missing)} extra={sorted(extra)}")

    if manifest["schema"] != SCHEMA:
        raise ValidationError(f"unsupported manifest schema: {manifest['schema']!r}")
    if manifest["schema_version"] != SCHEMA_VERSION:
        raise ValidationError(f"unsupported schema version: {manifest['schema_version']!r}")

    validate_uuid4(manifest["capture_series_id"], "capture_series_id")
    validate_uuid4(manifest["capture_revision_id"], "capture_revision_id")
    if manifest["parent_revision_id"] is not None:
        validate_uuid4(manifest["parent_revision_id"], "parent_revision_id")

    for field in ("capture_session_ids", "coordinate_space_ids"):
        values = manifest[field]
        if not isinstance(values, list) or not values:
            raise ValidationError(f"{field} must be a non-empty array")
        if len(set(values)) != len(values):
            raise ValidationError(f"{field} contains duplicates")
        for index, value in enumerate(values):
            validate_uuid4(value, f"{field}[{index}]")

    for field in ("created_at", "finalized_at"):
        value = manifest[field]
        if (
            not isinstance(value, str)
            or not re.fullmatch(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z",
                value,
            )
        ):
            raise ValidationError(f"{field} must be UTC RFC3339 text ending in Z")
        try:
            datetime.fromisoformat(value[:-1] + "+00:00")
        except ValueError as exc:
            raise ValidationError(
                f"{field} must be a valid UTC RFC3339 date-time"
            ) from exc

    app = manifest["app"]
    if not isinstance(app, dict) or set(app) != {"name", "version", "build"}:
        raise ValidationError("app must contain exactly name/version/build")
    if app["name"] != "HTDT-Capture":
        raise ValidationError("app.name must be HTDT-Capture")
    if not all(isinstance(app[k], str) and app[k] for k in ("version", "build")):
        raise ValidationError("app version/build must be non-empty strings")

    file_entries = manifest["files"]
    if not isinstance(file_entries, list):
        raise ValidationError("files must be an array")

    allowed_entry = {
        "path",
        "bytes",
        "media_type",
        "sha256",
        "producer",
        "provenance_class",
        "role",
        "source_refs",
    }
    required_entry = allowed_entry - {"source_refs"}

    paths = []
    casefold_paths = {}
    for index, entry in enumerate(file_entries):
        if not isinstance(entry, dict):
            raise ValidationError(f"files[{index}] must be an object")
        extra = set(entry) - allowed_entry
        missing = required_entry - set(entry)
        if extra or missing:
            raise ValidationError(
                f"files[{index}] keys mismatch: missing={sorted(missing)} extra={sorted(extra)}"
            )

        path = validate_relative_path(entry["path"])
        if path == "manifest.json":
            raise ValidationError("manifest.json must not self-declare as a payload")
        if not isinstance(entry["bytes"], int) or entry["bytes"] < 0:
            raise ValidationError(f"invalid byte length for {path}")
        if not isinstance(entry["media_type"], str) or not entry["media_type"]:
            raise ValidationError(f"invalid media_type for {path}")
        if not isinstance(entry["producer"], str) or not entry["producer"]:
            raise ValidationError(f"invalid producer for {path}")
        if entry["provenance_class"] not in PROVENANCE:
            raise ValidationError(f"invalid provenance_class for {path}")
        if entry["role"] not in ROLES:
            raise ValidationError(f"invalid role for {path}")
        if not isinstance(entry["sha256"], str) or not SHA256_RE.fullmatch(entry["sha256"]):
            raise ValidationError(f"invalid SHA-256 for {path}")
        if "source_refs" in entry:
            refs = entry["source_refs"]
            if not isinstance(refs, list) or not all(isinstance(x, str) and x for x in refs):
                raise ValidationError(f"invalid source_refs for {path}")
            if len(set(refs)) != len(refs):
                raise ValidationError(f"duplicate source_refs for {path}")

        folded = unicodedata.normalize("NFC", path).casefold()
        if folded in casefold_paths:
            raise ValidationError(
                f"case/Unicode-colliding manifest paths: {casefold_paths[folded]!r} and {path!r}"
            )
        casefold_paths[folded] = path
        paths.append(path)

    if len(set(paths)) != len(paths):
        raise ValidationError("duplicate manifest payload paths")
    if paths != sorted(paths, key=lambda x: x.encode("utf-8")):
        raise ValidationError("manifest files array must be sorted by UTF-8 path bytes")


class DirectorySource:
    def __init__(self, root: Path):
        self.root = root.resolve()
        if not self.root.is_dir():
            raise ValidationError(f"not a directory: {root}")

    def list_files(self) -> list[str]:
        result = []
        total = 0
        casefold_paths = {}
        for current_root, dirnames, filenames in os.walk(self.root, followlinks=False):
            current = Path(current_root)
            for name in list(dirnames):
                candidate = current / name
                if candidate.is_symlink():
                    raise ValidationError(f"symlink directory forbidden: {candidate}")
            for name in filenames:
                candidate = current / name
                if candidate.is_symlink():
                    raise ValidationError(f"symlink file forbidden: {candidate}")
                rel = candidate.relative_to(self.root).as_posix()
                validate_relative_path(rel)
                size = candidate.stat().st_size
                if size > MAX_FILE_BYTES:
                    raise ValidationError(f"file exceeds limit: {rel}")
                total += size
                if total > MAX_TOTAL_BYTES:
                    raise ValidationError("bundle exceeds total expanded byte limit")
                folded = unicodedata.normalize("NFC", rel).casefold()
                if folded in casefold_paths:
                    raise ValidationError(
                        f"case/Unicode-colliding paths: {casefold_paths[folded]!r} and {rel!r}"
                    )
                casefold_paths[folded] = rel
                result.append(rel)
                if len(result) > MAX_ENTRIES:
                    raise ValidationError("bundle exceeds entry limit")
        return sorted(result, key=lambda x: x.encode("utf-8"))

    def read_bytes(self, path: str) -> bytes:
        path = validate_relative_path(path)
        target = self.root.joinpath(*PurePosixPath(path).parts)
        if target.is_symlink():
            raise ValidationError(f"symlink payload forbidden: {path}")
        resolved = target.resolve()
        try:
            resolved.relative_to(self.root)
        except ValueError as exc:
            raise ValidationError(f"payload escapes root: {path}") from exc
        if not resolved.is_file():
            raise ValidationError(f"missing payload: {path}")
        data = resolved.read_bytes()
        if len(data) > MAX_FILE_BYTES:
            raise ValidationError(f"file exceeds limit: {path}")
        return data


class ZipSource:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValidationError(f"not a file: {path}")
        try:
            self.zf = zipfile.ZipFile(path, "r")
        except zipfile.BadZipFile as exc:
            raise ValidationError(f"invalid ZIP archive: {exc}") from exc
        self._infos = {}

    def list_files(self) -> list[str]:
        infos = self.zf.infolist()
        if len(infos) > MAX_ENTRIES:
            raise ValidationError("archive exceeds entry limit")

        total = 0
        casefold_paths = {}
        result = []
        for info in infos:
            path = validate_relative_path(info.filename.rstrip("/") if info.is_dir() else info.filename)
            mode = (info.external_attr >> 16) & 0o170000
            if mode == stat.S_IFLNK:
                raise ValidationError(f"symlink archive entry forbidden: {path}")
            if mode not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValidationError(f"non-regular archive entry forbidden: {path}")
            if info.is_dir():
                continue
            if path in self._infos:
                raise ValidationError(f"duplicate archive entry: {path}")
            folded = unicodedata.normalize("NFC", path).casefold()
            if folded in casefold_paths:
                raise ValidationError(
                    f"case/Unicode-colliding archive paths: {casefold_paths[folded]!r} and {path!r}"
                )
            casefold_paths[folded] = path

            if info.file_size > MAX_FILE_BYTES:
                raise ValidationError(f"archive member exceeds file limit: {path}")
            total += info.file_size
            if total > MAX_TOTAL_BYTES:
                raise ValidationError("archive exceeds total expanded byte limit")
            if info.file_size and info.compress_size == 0:
                raise ValidationError(f"invalid zero compressed size for non-empty member: {path}")
            if info.compress_size:
                ratio = info.file_size / info.compress_size
                if ratio > MAX_COMPRESSION_RATIO:
                    raise ValidationError(
                        f"archive member compression ratio exceeds limit ({ratio:.1f}:1): {path}"
                    )
            self._infos[path] = info
            result.append(path)
        return sorted(result, key=lambda x: x.encode("utf-8"))

    def read_bytes(self, path: str) -> bytes:
        path = validate_relative_path(path)
        info = self._infos.get(path)
        if info is None:
            raise ValidationError(f"missing archive member: {path}")
        data = self.zf.read(info)
        if len(data) != info.file_size:
            raise ValidationError(f"expanded length mismatch: {path}")
        return data


def validate_bundle(path: Path) -> dict:
    source = DirectorySource(path) if path.is_dir() else ZipSource(path)
    actual_files = source.list_files()
    if "manifest.json" not in actual_files:
        raise ValidationError("manifest.json missing")

    manifest_bytes = source.read_bytes("manifest.json")
    manifest = parse_json_bytes(manifest_bytes)
    validate_manifest_shape(manifest)

    canonical = canonical_json_bytes(manifest)
    if canonical != manifest_bytes:
        raise ValidationError("manifest.json is not Capture Bundle v1 canonical JSON")

    declared_entries = {entry["path"]: entry for entry in manifest["files"]}
    declared = set(declared_entries)
    actual_payloads = set(actual_files) - {"manifest.json"}
    if declared != actual_payloads:
        missing = sorted(declared - actual_payloads)
        undeclared = sorted(actual_payloads - declared)
        raise ValidationError(
            f"declared/present payload mismatch: missing={missing} undeclared={undeclared}"
        )

    for path_text in sorted(declared, key=lambda x: x.encode("utf-8")):
        entry = declared_entries[path_text]
        data = source.read_bytes(path_text)
        if len(data) != entry["bytes"]:
            raise ValidationError(
                f"byte length mismatch for {path_text}: expected {entry['bytes']} got {len(data)}"
            )
        digest = hashlib.sha256(data).hexdigest()
        if digest != entry["sha256"]:
            raise ValidationError(
                f"SHA-256 mismatch for {path_text}: expected {entry['sha256']} got {digest}"
            )

    bundle_digest = hashlib.sha256(manifest_bytes).hexdigest()
    return {
        "valid": True,
        "schema": manifest["schema"],
        "schema_version": manifest["schema_version"],
        "capture_revision_id": manifest["capture_revision_id"],
        "bundle_digest": bundle_digest,
        "payload_count": len(declared_entries),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate HTDT Capture Bundle v1")
    parser.add_argument("bundle", type=Path, help="bundle directory or .htdtcapture ZIP")
    parser.add_argument("--expect-digest", help="fail unless bundle digest matches")
    args = parser.parse_args(argv)

    try:
        report = validate_bundle(args.bundle)
        if args.expect_digest and report["bundle_digest"] != args.expect_digest:
            raise ValidationError(
                f"bundle digest mismatch: expected {args.expect_digest} got {report['bundle_digest']}"
            )
    except ValidationError as exc:
        print(json.dumps({"valid": False, "error": str(exc)}, sort_keys=True))
        return 2

    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
