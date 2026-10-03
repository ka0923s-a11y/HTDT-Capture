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

if __package__ in (None, ""):
    # Allow `python tools/bundle_validator/validator.py <bundle>` direct
    # execution: put the repository root on sys.path so the sibling helper
    # modules resolve as package imports.
    repo_root = Path(__file__).resolve().parents[2]
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))

from tools.bundle_validator.binary_formats import (
    BinaryFormatError,
    validate_confidencebin,
    validate_depthbin,
    validate_meshbin,
    validate_pixelbin,
)
from tools.bundle_validator.schema_eval import (
    SchemaError,
    check_schema,
    validate as schema_validate,
)

SCHEMA = "htdt.capture.bundle"
SCHEMA_VERSION = "1.0.0"

MAX_ENTRIES = 10_000
MAX_FILE_BYTES = 512 * 1024 * 1024
# The manifest is metadata, not payload: it must stay far below the generic
# per-file bound so hostile bundles cannot force a multi-hundred-MiB
# allocation before semantic validation. 8 MiB comfortably covers
# MAX_ENTRIES entries with realistic path/reference sizes.
MAX_MANIFEST_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_COMPRESSION_RATIO = 200.0

# v1 source_ref budgets (legacy bolph71656-ai/HTDT-Capture#195). Lineage work must stay bounded
# independently of the manifest byte cap; identical limits are enforced
# by the Swift manifest validator and the reference ingestor.
MAX_SOURCE_REFS_PER_ENTRY = 32
MAX_SOURCE_REF_BYTES = 512
MAX_SOURCE_REFS_TOTAL = 65_536

# Minimum v1 foundation payload set (legacy bolph71656-ai/HTDT-Capture#194). The manifest's session and
# coordinate-space identity arrays are only meaningful with the documents
# that ground them, and legacy bolph71656-ai/HTDT-Capture#127 requires the persisted quality authority.
# session/device.json, session/capabilities.json and
# roomplan/captured-room-metadata.json are intentionally optional.
FOUNDATION_REQUIRED_PATHS = frozenset({
    "quality/capture-quality.json",
    "session/capture-configuration.json",
    "session/capture-session.json",
    "session/timing.json",
})
# Processed-only RoomPlan promotion is rejected (legacy bolph71656-ai/HTDT-Capture#194): whenever the
# canonical processed payload is declared, the canonical raw authority
# must be declared and bound in the processed entry's source_refs.
# Legacy bundles that carry RoomPlan payloads at non-reserved paths are
# handled by the ingestor's provenance-class fallback instead.

SCHEMA_DIR = (
    Path(__file__).resolve().parents[2] / "schemas" / "capture-bundle-v1"
)

# Path -> schema-family resolution is driven by
# support-matrix.json (legacy bolph71656-ai/HTDT-Capture#332): every schema-owned payload family lists
# its bundle paths, the published schema document per payload version,
# the emitted version, and the versions this validator can read.
# Opaque external authority payloads (roomplan/captured-room*.json)
# are declared as external families: no project-owned schema applies,
# they are governed by media type plus lineage binding.
FRAME_DESCRIPTOR_RE = re.compile(r"^evidence/frames/[^/]+\.json$")

_SUPPORT_MATRIX_PATH = SCHEMA_DIR / "support-matrix.json"
_support_matrix: dict | None = None


def _load_support_matrix() -> dict:
    global _support_matrix
    if _support_matrix is None:
        try:
            matrix = json.loads(
                _SUPPORT_MATRIX_PATH.read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError) as exc:
            raise ValidationError(
                f"payload support matrix unreadable: {exc}"
            ) from exc
        if matrix.get("schema") != "htdt.capture.bundle-support-matrix":
            raise ValidationError(
                "payload support matrix has wrong schema token"
            )
        _support_matrix = matrix
    return _support_matrix


def _family_for_path(path: str):
    """Return (family_name, contract) for a bundle path, else (None, None)."""
    for name, contract in _load_support_matrix()["families"].items():
        for declared in contract.get("paths", []):
            if declared == path:
                return name, contract
            if "<frame_id>" in declared and FRAME_DESCRIPTOR_RE.fullmatch(
                path
            ):
                return name, contract
    return None, None


def _version_gt(a: str, b: str) -> bool:
    pa = [int(x) if x.isdigit() else 0 for x in a.split(".")]
    pb = [int(x) if x.isdigit() else 0 for x in b.split(".")]
    width = max(len(pa), len(pb))
    for i in range(width):
        av = pa[i] if i < len(pa) else 0
        bv = pb[i] if i < len(pb) else 0
        if av != bv:
            return av > bv
    return False


def _schema_document_for_version(
    path: str, document: dict, family: str, contract: dict
) -> str:
    """Resolve the registry document key serving the declared version.

    One schema_version maps to exactly one immutable schema document
    (legacy bolph71656-ai/HTDT-Capture#332); unlisted versions fail with an explicit version diagnostic."""
    documents = contract.get("documents", {})
    if contract.get("unversioned"):
        key = documents.get("unversioned")
        if key is None:
            raise ValidationError(
                f"{path}: family {family} has no unversioned document"
            )
        return key
    version = document.get("schema_version")
    if not isinstance(version, str):
        raise ValidationError(
            f"{path}: versioned payload lacks a schema_version member"
        )
    key = documents.get(version)
    if key is None:
        read = contract.get("read", [])
        newest = max(read, key=lambda v: [int(x) if x.isdigit() else 0 for x in v.split(".")], default="0")
        status = (
            "unsupported_newer"
            if _version_gt(version, newest)
            else "unsupported_legacy"
        )
        raise ValidationError(
            f"{path}: family {family} does not support "
            f"schema_version {version!r} ({status}; "
            f"supported={sorted(read)})"
        )
    return key


# Canonical binary payload formats keyed by bundle path extension and by
# manifest media type. Both signals must agree when both are present.
_BINARY_BY_EXTENSION = {
    ".meshbin": "meshbin",
    ".pixelbin": "pixelbin",
    ".depthbin": "depthbin",
    ".confidencebin": "confidencebin",
}
_BINARY_MEDIA_TYPE = {
    "meshbin": "application/vnd.htdt.meshbin",
    "pixelbin": "application/vnd.htdt.pixelbin",
    "depthbin": "application/vnd.htdt.depthbin",
    "confidencebin": "application/vnd.htdt.confidencebin",
}
_BINARY_BY_MEDIA_TYPE = {v: k for k, v in _BINARY_MEDIA_TYPE.items()}
_BINARY_VALIDATORS = {
    "meshbin": validate_meshbin,
    "pixelbin": validate_pixelbin,
    "depthbin": validate_depthbin,
    "confidencebin": validate_confidencebin,
}

# Frozen v1 source_refs grammar namespaces plus enumerated sentinel refs.
SOURCE_REF_SENTINELS = {"roomplan_raw_serialization:unavailable"}

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


def _canonical_dumps(value) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_json_bytes(value) -> bytes:
    """Capture Bundle v1 canonical JSON for manifest-compatible values."""
    _walk_json(value, reject_floats=True)
    return _canonical_dumps(value)


def canonical_payload_json_bytes(value) -> bytes:
    """Canonical JSON bytes for schema-owned payload documents.

    The bundle canonical JSON profile (UTF-8, no BOM, no duplicate keys, NFC
    strings/keys, sorted object keys, no insignificant whitespace, standard
    escaping, no NaN/Infinity) applies to every HTDT-Capture-owned payload,
    not only manifest.json. Unlike the manifest, payload schemas legitimately
    contain finite IEEE-754 numbers, so floats are permitted here but must be
    finite.
    """
    _walk_json(value, reject_floats=False)
    return _canonical_dumps(value)


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
        # A correction produces another revision; a revision cannot be its
        # own parent. (Multi-revision ancestry cycles need repository
        # context and are out of scope for single-bundle validation.)
        if manifest["parent_revision_id"] == manifest["capture_revision_id"]:
            raise ValidationError(
                "parent_revision_id must differ from capture_revision_id"
            )

    for field in ("capture_session_ids", "coordinate_space_ids"):
        values = manifest[field]
        if not isinstance(values, list) or not values:
            raise ValidationError(f"{field} must be a non-empty array")
        if len(set(values)) != len(values):
            raise ValidationError(f"{field} contains duplicates")
        for index, value in enumerate(values):
            validate_uuid4(value, f"{field}[{index}]")

    instants = {}
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
            instants[field] = datetime.fromisoformat(value[:-1] + "+00:00")
        except ValueError as exc:
            raise ValidationError(
                f"{field} must be a valid UTC RFC3339 date-time"
            ) from exc
    # Lifecycle timestamps are audit chronology: compare parsed instants
    # (not raw strings) so fractional-second representations cannot
    # invert or mask the ordering.
    if instants["finalized_at"] < instants["created_at"]:
        raise ValidationError(
            "finalized_at must not precede created_at"
        )

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
    entries_by_path = {}
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
            if len(refs) > MAX_SOURCE_REFS_PER_ENTRY:
                raise ValidationError(
                    f"too many source_refs for {path} "
                    f"(max {MAX_SOURCE_REFS_PER_ENTRY})"
                )
            if any(
                len(ref.encode("utf-8")) > MAX_SOURCE_REF_BYTES
                for ref in refs
            ):
                raise ValidationError(f"oversized source_ref for {path}")
            if len(set(refs)) != len(refs):
                raise ValidationError(f"duplicate source_refs for {path}")
        # Swift parity: BundleManifest.validateSourceRefs rejects a
        # `derived`-role entry that carries no source_refs
        # (derivedEntryMissingSourceRefs).
        if entry["role"] == "derived" and not entry.get("source_refs"):
            raise ValidationError(f"derived entry missing source_refs for {path}")

        folded = unicodedata.normalize("NFC", path).casefold()
        if folded in casefold_paths:
            raise ValidationError(
                f"case/Unicode-colliding manifest paths: {casefold_paths[folded]!r} and {path!r}"
            )
        casefold_paths[folded] = path
        paths.append(path)
        entries_by_path[path] = entry

    if len(set(paths)) != len(paths):
        raise ValidationError("duplicate manifest payload paths")
    if paths != sorted(paths, key=lambda x: x.encode("utf-8")):
        raise ValidationError("manifest files array must be sorted by UTF-8 path bytes")

    _validate_source_refs(manifest, entries_by_path)


def _validate_source_refs(manifest: dict, entries_by_path: dict) -> None:
    """Validate the frozen v1 source_refs grammar and target integrity.

    Recognized forms:

    - ``path:<normalized-bundle-path>`` targeting another declared payload;
    - ``sha256:<lowercase-hex>`` targeting another declared payload digest;
    - ``capture_session:<uuidv4>`` naming a manifest ``capture_session_ids``
      member;
    - the enumerated sentinel ``roomplan_raw_serialization:unavailable``.

    Anything else fails closed. ``path:`` references additionally must not
    form lineage cycles.
    """
    declared_paths = set(entries_by_path)
    # A sha256 source_ref must name exactly one payload authority (legacy bolph71656-ai/HTDT-Capture#193):
    # identical bytes under different logical paths carry different
    # producer/provenance/lineage, so an ambiguous digest cannot stand in
    # for a source authority and must be expressed as a path: ref instead.
    digest_counts: dict[str, int] = {}
    for entry in entries_by_path.values():
        digest = entry["sha256"]
        digest_counts[digest] = digest_counts.get(digest, 0) + 1
    session_ids = set(manifest["capture_session_ids"])

    path_edges: dict[str, list[str]] = {}
    total_refs = 0
    for path, entry in entries_by_path.items():
        refs = entry.get("source_refs") or []
        total_refs += len(refs)
        if total_refs > MAX_SOURCE_REFS_TOTAL:
            raise ValidationError(
                f"manifest exceeds the aggregate source_ref budget "
                f"({MAX_SOURCE_REFS_TOTAL})"
            )
        for ref in refs:
            if ref in SOURCE_REF_SENTINELS:
                continue
            namespace, separator, target = ref.partition(":")
            if not separator or not target:
                raise ValidationError(
                    f"invalid source_ref grammar for {path}: {ref!r}"
                )
            if namespace == "path":
                try:
                    target = validate_relative_path(target)
                except ValidationError as exc:
                    raise ValidationError(
                        f"invalid path source_ref for {path}: {ref!r}"
                    ) from exc
                if target == path:
                    raise ValidationError(
                        f"self-referential path source_ref for {path}: {ref!r}"
                    )
                if target not in declared_paths:
                    raise ValidationError(
                        f"dangling path source_ref for {path}: {ref!r}"
                    )
                path_edges.setdefault(path, []).append(target)
            elif namespace == "sha256":
                if not SHA256_RE.fullmatch(target):
                    raise ValidationError(
                        f"malformed sha256 source_ref for {path}: {ref!r}"
                    )
                if target == entry["sha256"]:
                    raise ValidationError(
                        f"self-referential sha256 source_ref for {path}: {ref!r}"
                    )
                count = digest_counts.get(target, 0)
                if count == 0:
                    raise ValidationError(
                        f"dangling sha256 source_ref for {path}: {ref!r}"
                    )
                if count > 1:
                    raise ValidationError(
                        f"ambiguous sha256 source_ref for {path}: {ref!r} "
                        f"names {count} payload authorities; use a path: "
                        f"reference to bind exactly one"
                    )
            elif namespace == "capture_session":
                try:
                    validate_uuid4(target, "source_ref capture_session")
                except ValidationError as exc:
                    raise ValidationError(
                        f"malformed capture_session source_ref for {path}: "
                        f"{ref!r}"
                    ) from exc
                if target not in session_ids:
                    raise ValidationError(
                        f"capture_session source_ref names an unknown session "
                        f"for {path}: {ref!r}"
                    )
            else:
                raise ValidationError(
                    f"unknown source_ref namespace for {path}: {ref!r}"
                )

    # Lineage through path: references must be acyclic. A cycle would let a
    # payload claim derivation from itself transitively, which the v1
    # canonical/derived relationship does not permit.
    WHITE, GRAY, BLACK = 0, 1, 2
    color: dict[str, int] = {}
    for start in path_edges:
        if color.get(start, WHITE) != WHITE:
            continue
        stack = [(start, iter(path_edges.get(start, [])))]
        color[start] = GRAY
        while stack:
            node, children = stack[-1]
            advanced = False
            for child in children:
                child_color = color.get(child, WHITE)
                if child_color == GRAY:
                    raise ValidationError(
                        f"source_ref path lineage cycle involving {child!r}"
                    )
                if child_color == WHITE:
                    color[child] = GRAY
                    stack.append((child, iter(path_edges.get(child, []))))
                    advanced = True
                    break
            if not advanced:
                color[node] = BLACK
                stack.pop()


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
                info = candidate.stat()
                # A regular file with more than one hard link shares an
                # inode with an outside alias; writing through that alias
                # would mutate a finalized payload after hashing. Only
                # st_nlink > 1 indicates hard-link aliasing, so ordinary
                # clone/copy-on-write files (st_nlink == 1) still pass.
                if info.st_nlink > 1:
                    raise ValidationError(f"hard-linked file forbidden: {rel}")
                size = info.st_size
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
        bound = (
            MAX_MANIFEST_BYTES if path == "manifest.json" else MAX_FILE_BYTES
        )

        # TOCTOU discipline: the scan above is only a fast precheck. The
        # authoritative identity checks bind a path-level lstat to the same
        # opened descriptor that supplies the bytes:
        #
        # 1. lstat the path to snapshot the expected identity;
        # 2. open once (with O_NOFOLLOW where the platform supports it, so a
        #    path that is a symlink at open time fails immediately);
        # 3. fstat the descriptor and require (st_dev, st_ino) equality with
        #    the lstat result. If the path was swapped to a symlink between
        #    the calls, the descriptor refers to the symlink *target* whose
        #    inode differs, so replacement is detected even on platforms
        #    without O_NOFOLLOW. If the path was swapped to another regular
        #    file, the inode mismatch is detected the same way;
        # 4. enforce regular-file/link-count/size policy on the descriptor;
        # 5. read through the descriptor with a bound-checked stream.
        try:
            pre = os.stat(target, follow_symlinks=False)
        except FileNotFoundError as exc:
            raise ValidationError(f"missing payload: {path}") from exc
        except OSError as exc:
            raise ValidationError(f"unreadable payload: {path}") from exc
        if stat.S_ISLNK(pre.st_mode):
            raise ValidationError(f"symlink payload forbidden: {path}")

        flags = os.O_RDONLY
        flags |= getattr(os, "O_NOFOLLOW", 0)
        flags |= getattr(os, "O_BINARY", 0)
        try:
            descriptor = os.open(target, flags)
        except OSError as exc:
            raise ValidationError(f"unreadable payload: {path}") from exc
        try:
            info = os.fstat(descriptor)
            if (info.st_dev, info.st_ino) != (pre.st_dev, pre.st_ino):
                raise ValidationError(
                    f"payload replaced during validation: {path}"
                )
            if not stat.S_ISREG(info.st_mode):
                raise ValidationError(f"non-regular payload: {path}")
            if info.st_nlink > 1:
                raise ValidationError(f"hard-linked file forbidden: {path}")
            if info.st_size > bound:
                raise ValidationError(f"file exceeds limit: {path}")
            chunks = []
            remaining = bound + 1
            while remaining > 0:
                chunk = os.read(descriptor, min(1 << 20, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            data = b"".join(chunks)
            if len(data) > bound:
                raise ValidationError(f"file exceeds limit: {path}")
            if len(data) != info.st_size:
                raise ValidationError(
                    f"payload size changed during validation: {path}"
                )
            return data
        finally:
            os.close(descriptor)


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
            if path == "manifest.json" and info.file_size > MAX_MANIFEST_BYTES:
                # Reject an oversized manifest from the declared archive
                # header before any bytes are materialized.
                raise ValidationError("manifest.json exceeds manifest byte limit")
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
        bound = (
            MAX_MANIFEST_BYTES if path == "manifest.json" else MAX_FILE_BYTES
        )
        if info.file_size > bound:
            raise ValidationError(f"file exceeds limit: {path}")
        data = self.zf.read(info)
        if len(data) != info.file_size:
            raise ValidationError(f"expanded length mismatch: {path}")
        if len(data) > bound:
            raise ValidationError(f"file exceeds limit: {path}")
        return data


_schema_cache: dict[str, object] = {}



def _load_schema(name: str):
    schema = _schema_cache.get(name)
    if schema is None:
        schema_path = SCHEMA_DIR / name
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValidationError(
                f"published schema {name} unreadable: {exc}"
            ) from exc
        # Fail closed if the published schema uses constructs the reference
        # evaluator does not implement.
        check_schema(schema)
        _schema_cache[name] = schema
    return schema


def _binary_format_for(path: str, media_type: str) -> str | None:
    """Determine the canonical binary format a payload must satisfy."""
    extension = path.rsplit(".", 1)[-1] if "." in path else ""
    by_ext = _BINARY_BY_EXTENSION.get(f".{extension}") if extension else None
    by_media = _BINARY_BY_MEDIA_TYPE.get(media_type)
    if by_ext is not None and by_media is not None and by_ext != by_media:
        raise ValidationError(
            f"binary path/media-type mismatch for {path}: {media_type!r}"
        )
    fmt = by_ext or by_media
    if fmt is not None and media_type != _BINARY_MEDIA_TYPE[fmt]:
        raise ValidationError(
            f"binary payload {path} must declare media type "
            f"{_BINARY_MEDIA_TYPE[fmt]!r}"
        )
    return fmt


def _validate_schema_owned_payload(
    path: str, data: bytes, family: str, contract: dict
):
    """Enforce canonical JSON bytes + the versioned published schema."""
    document = parse_json_bytes(data)
    canonical = canonical_payload_json_bytes(document)
    if canonical != data:
        raise ValidationError(
            f"{path} is not Capture Bundle v1 canonical JSON"
        )
    document_key = _schema_document_for_version(
        path, document, family, contract
    )
    schema_name = f"{document_key}.schema.json"
    schema = _load_schema(schema_name)
    try:
        schema_validate(document, schema)
    except SchemaError as exc:
        raise ValidationError(
            f"{path} violates {schema_name}: {exc}"
        ) from exc
    return document


def _require_declared_payload(path: str, declared_entries: dict, field: str):
    entry = declared_entries.get(path)
    if entry is None:
        raise ValidationError(f"{field} does not name a declared payload: {path!r}")
    return entry


def _cross_check_mesh_anchors(
    document: dict,
    binary_facts: dict,
    declared_entries: dict,
    manifest: dict,
) -> None:
    """Bind mesh/anchors.json index records to validated mesh binaries."""
    session_ids = set(manifest["capture_session_ids"])
    coordinate_ids = set(manifest["coordinate_space_ids"])
    for index, anchor in enumerate(document["anchors"]):
        field = f"anchors[{index}]"
        anchor_id = anchor["anchor_id"]
        if anchor["capture_session_id"] not in session_ids:
            raise ValidationError(
                f"mesh anchor {field} references undeclared capture_session_id"
            )
        if anchor["coordinate_space_id"] not in coordinate_ids:
            raise ValidationError(
                f"mesh anchor {field} references undeclared coordinate_space_id"
            )
        geometry_path = anchor["geometry_path"]
        if geometry_path != f"mesh/geometry/{anchor_id}.meshbin":
            raise ValidationError(
                f"{field}.geometry_path must be "
                f"mesh/geometry/{anchor_id}.meshbin, got {geometry_path!r}"
            )
        entry = _require_declared_payload(
            geometry_path, declared_entries, f"{field}.geometry_path"
        )
        if anchor["geometry_sha256"] != entry["sha256"]:
            raise ValidationError(
                f"{field}.geometry_sha256 does not match manifest digest "
                f"for {geometry_path}"
            )
        facts = binary_facts.get(geometry_path)
        if facts is None:
            raise ValidationError(
                f"{field}.geometry_path is not a validated mesh binary: "
                f"{geometry_path}"
            )
        if facts.vertex_count != anchor["vertex_count"]:
            raise ValidationError(
                f"{field}.vertex_count {anchor['vertex_count']} does not "
                f"match mesh binary header {facts.vertex_count}"
            )
        if facts.face_count != anchor["face_count"]:
            raise ValidationError(
                f"{field}.face_count {anchor['face_count']} does not "
                f"match mesh binary header {facts.face_count}"
            )


def _check_descriptor_reference(
    descriptor_path: str,
    field: str,
    expected_path: str,
    declared_path: str,
    byte_count,
    sha256,
    declared_entries: dict,
) -> None:
    if declared_path != expected_path:
        raise ValidationError(
            f"{descriptor_path}: {field} must be {expected_path!r}, "
            f"got {declared_path!r}"
        )
    entry = _require_declared_payload(
        declared_path, declared_entries, f"{descriptor_path}:{field}"
    )
    if not isinstance(byte_count, int) or byte_count != entry["bytes"]:
        raise ValidationError(
            f"{descriptor_path}: {field} byte count does not match "
            f"manifest entry for {declared_path}"
        )
    if sha256 != entry["sha256"]:
        raise ValidationError(
            f"{descriptor_path}: {field} sha256 does not match manifest "
            f"digest for {declared_path}"
        )


def _cross_check_frame_descriptor(
    descriptor_path: str,
    document: dict,
    binary_facts: dict,
    declared_entries: dict,
    manifest: dict,
) -> None:
    """Bind an evidence/frames/<id>.json descriptor to validated binaries."""
    frame_id = document["frame_id"]
    stem = descriptor_path[len("evidence/frames/") : -len(".json")]
    if stem != frame_id:
        raise ValidationError(
            f"{descriptor_path}: filename must be the frame_id"
        )

    if document["capture_session_id"] not in set(
        manifest["capture_session_ids"]
    ):
        raise ValidationError(
            f"{descriptor_path}: undeclared capture_session_id"
        )
    if document["coordinate_space_id"] not in set(
        manifest["coordinate_space_ids"]
    ):
        raise ValidationError(
            f"{descriptor_path}: undeclared coordinate_space_id"
        )

    pixel_path = document["pixel_relative_path"]
    _check_descriptor_reference(
        descriptor_path,
        "pixel_relative_path",
        f"evidence/frames/{frame_id}.pixelbin",
        pixel_path,
        document["pixel_byte_count"],
        document["pixel_sha256"],
        declared_entries,
    )
    pixel_facts = binary_facts.get(pixel_path)
    if pixel_facts is None:
        raise ValidationError(
            f"{descriptor_path}: pixel payload is not a validated "
            f"pixelbin: {pixel_path}"
        )
    if (
        pixel_facts.width != document["image_width"]
        or pixel_facts.height != document["image_height"]
    ):
        raise ValidationError(
            f"{descriptor_path}: pixelbin dimensions "
            f"{pixel_facts.width}x{pixel_facts.height} do not match "
            f"descriptor {document['image_width']}x{document['image_height']}"
        )
    if pixel_facts.pixel_format_fourcc != document["pixel_format_fourcc"]:
        raise ValidationError(
            f"{descriptor_path}: pixelbin format does not match "
            f"pixel_format_fourcc"
        )

    depth = document.get("depth")
    depth_status = document["depth_status"]
    depth_kinds = {
        "captured_scene_depth": "scene_depth",
        "captured_smoothed_scene_depth": "smoothed_scene_depth",
    }
    if depth_status in ("not_requested", "unavailable"):
        if depth is not None:
            raise ValidationError(
                f"{descriptor_path}: depth payload inconsistent with "
                f"depth_status {depth_status!r}"
            )
    else:
        if not isinstance(depth, dict):
            raise ValidationError(
                f"{descriptor_path}: depth_status {depth_status!r} "
                f"requires a depth reference"
            )
        if depth["kind"] != depth_kinds[depth_status]:
            raise ValidationError(
                f"{descriptor_path}: depth kind {depth['kind']!r} "
                f"inconsistent with depth_status {depth_status!r}"
            )
        depth_path = depth["depth_relative_path"]
        _check_descriptor_reference(
            descriptor_path,
            "depth.depth_relative_path",
            f"evidence/depth/{frame_id}.depthbin",
            depth_path,
            depth["depth_byte_count"],
            depth["depth_sha256"],
            declared_entries,
        )
        depth_facts = binary_facts.get(depth_path)
        if depth_facts is None:
            raise ValidationError(
                f"{descriptor_path}: depth payload is not a validated "
                f"depthbin: {depth_path}"
            )

        confidence_values = (
            depth.get("confidence_relative_path"),
            depth.get("confidence_byte_count"),
            depth.get("confidence_sha256"),
        )
        if any(value is not None for value in confidence_values):
            if not all(value is not None for value in confidence_values):
                raise ValidationError(
                    f"{descriptor_path}: incomplete confidence reference"
                )
            confidence_path = confidence_values[0]
            _check_descriptor_reference(
                descriptor_path,
                "depth.confidence_relative_path",
                f"evidence/depth/{frame_id}.confidencebin",
                confidence_path,
                confidence_values[1],
                confidence_values[2],
                declared_entries,
            )
            confidence_facts = binary_facts.get(confidence_path)
            if confidence_facts is None:
                raise ValidationError(
                    f"{descriptor_path}: confidence payload is not a "
                    f"validated confidencebin: {confidence_path}"
                )
            if (
                confidence_facts.width != depth_facts.width
                or confidence_facts.height != depth_facts.height
            ):
                raise ValidationError(
                    f"{descriptor_path}: confidence dimensions do not "
                    f"match depth dimensions"
                )


def _cross_check_authority_dependencies(
    document: dict,
    entities_document,
    declared_entries: dict,
) -> None:
    """Bind derived/authority-dependencies.json to entities.json (legacy bolph71656-ai/HTDT-Capture#337).

    Rules:
    - (kind, authority_id, authority_version) tuples are unique — a
      manifest never declares the same authority twice.
    - every equipment_definition dependency's hash equals the
      equipment_ref hash entities carry for that tuple, and every
      entity equipment_ref is covered by exactly one dependency.
    - every entity role_binding's (profile_id, profile_version) is
      covered by a layout_profile dependency.
    - bound_entity_refs name entity_ids actually present in
      annotations/entities.json (when entities.json is declared).
    - every embedded_ref `path:` target is a declared bundle payload.
    """
    path = "derived/authority-dependencies.json"
    dependencies = document["dependencies"]

    seen = set()
    for index, dep in enumerate(dependencies):
        field = f"{path}:dependencies[{index}]"
        key = (dep["kind"], dep["authority_id"], dep["authority_version"])
        if key in seen:
            raise ValidationError(f"{field} duplicates dependency {key}")
        seen.add(key)

        embedded_ref = dep.get("embedded_ref")
        if embedded_ref is not None:
            if not embedded_ref.startswith("path:"):
                raise ValidationError(
                    f"{field}.embedded_ref must be a 'path:' ref, "
                    f"got {embedded_ref!r}"
                )
            _require_declared_payload(
                embedded_ref[len("path:"):], declared_entries,
                f"{field}.embedded_ref",
            )

    entity_ids = set()
    equipment_refs = {}
    role_bindings = set()
    if entities_document is not None:
        for entity in entities_document["entities"]:
            entity_ids.add(entity["entity_id"])
            ref = entity.get("equipment_ref")
            if ref is not None:
                equipment_refs[
                    (ref["equipment_id"], ref["equipment_version"])
                ] = ref
            binding = entity.get("role_binding")
            if binding is not None:
                role_bindings.add(
                    (binding["profile_id"], binding["profile_version"])
                )

    # Exact coverage: a manifest carrying no dependency for an
    # entity-carried equipment tuple leaves the ref unresolvable on
    # another instance — that is a bundle defect, not a soft warning.
    covered_equipment = {
        (dep["authority_id"], dep["authority_version"])
        for dep in dependencies
        if dep["kind"] == "equipment_definition"
    }
    covered_profiles = {
        (dep["authority_id"], dep["authority_version"])
        for dep in dependencies
        if dep["kind"] == "layout_profile"
    }
    uncovered = sorted(set(equipment_refs) - covered_equipment)
    if uncovered:
        raise ValidationError(
            f"{path}: entity equipment_refs lack "
            f"equipment_definition dependencies: {uncovered}"
        )
    uncovered_profiles = sorted(role_bindings - covered_profiles)
    if uncovered_profiles:
        raise ValidationError(
            f"{path}: entity role_bindings lack layout_profile "
            f"dependencies: {uncovered_profiles}"
        )

    # Hash pinning: the declared equipment hash must equal the hash
    # the entity carries — a same-ID/different-hash declaration would
    # be ambiguous authority, not an exact pin.
    entity_kinds = {"equipment_definition", "layout_profile"}
    for index, dep in enumerate(dependencies):
        field = f"{path}:dependencies[{index}]"
        if dep["kind"] == "equipment_definition":
            key = (dep["authority_id"], dep["authority_version"])
            ref = equipment_refs.get(key)
            if (
                ref is not None
                and dep["authority_sha256"] != ref["equipment_hash"]
            ):
                raise ValidationError(
                    f"{field}.authority_sha256 does not match the "
                    f"equipment_ref hash entities carry for {key}"
                )
        for ref_text in dep.get("bound_entity_refs", []):
            if dep["kind"] in entity_kinds and ref_text not in entity_ids:
                raise ValidationError(
                    f"{field}.bound_entity_refs names an entity_id "
                    f"absent from annotations/entities.json: {ref_text!r}"
                )


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

    # The manifest itself is a schema-owned document; run the published
    # manifest schema as an independent check alongside the dedicated
    # structural validation above. The version dispatch goes through
    # the support matrix like every other schema-owned payload (legacy bolph71656-ai/HTDT-Capture#332).
    m_family, m_contract = _family_for_path("manifest.json")
    if m_contract is None:
        raise ValidationError(
            "manifest.json is not covered by the support matrix"
        )
    m_doc = _schema_document_for_version(
        "manifest.json", manifest, m_family, m_contract
    )
    try:
        schema_validate(manifest, _load_schema(f"{m_doc}.schema.json"))
    except SchemaError as exc:
        raise ValidationError(
            f"manifest.json violates manifest.schema.json: {exc}"
        ) from exc

    declared_entries = {entry["path"]: entry for entry in manifest["files"]}
    declared = set(declared_entries)

    # Minimum foundation payload set (legacy bolph71656-ai/HTDT-Capture#194): a manifest whose identity
    # arrays have no grounding documents is not a finalized v1 bundle.
    missing_foundation = sorted(FOUNDATION_REQUIRED_PATHS - declared)
    if missing_foundation:
        raise ValidationError(
            "bundle is missing required foundation payloads: "
            f"{missing_foundation}"
        )

    actual_payloads = set(actual_files) - {"manifest.json"}
    if declared != actual_payloads:
        missing = sorted(declared - actual_payloads)
        undeclared = sorted(actual_payloads - declared)
        raise ValidationError(
            f"declared/present payload mismatch: missing={missing} undeclared={undeclared}"
        )

    schema_documents: dict[str, object] = {}
    payload_versions: dict[str, str] = {}
    binary_facts: dict[str, object] = {}
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

        family, contract = _family_for_path(path_text)
        if contract is not None and not contract.get("external"):
            schema_documents[path_text] = _validate_schema_owned_payload(
                path_text, data, family, contract
            )
            version = schema_documents[path_text].get("schema_version")
            if isinstance(version, str):
                payload_versions[family] = version
        elif (
            contract is None
            and path_text.endswith(".json")
            and entry["provenance_class"]
            not in {"apple_roomplan_raw_scan", "apple_roomplan_inference"}
        ):
            # legacy bolph71656-ai/HTDT-Capture#332: a declared .json payload must be schema-owned or a
            # registered external authority slot; anything else is a
            # generic supplemental persistence bypass. Legacy bundles
            # carrying RoomPlan payloads at non-reserved paths stay
            # valid and are resolved by the ingestor's provenance
            # fallback.
            raise ValidationError(
                f"{path_text} is a JSON payload owned by no published "
                "schema or external authority"
            )

        binary_format = _binary_format_for(path_text, entry["media_type"])
        if binary_format is not None:
            try:
                binary_facts[path_text] = _BINARY_VALIDATORS[
                    binary_format
                ](data)
            except BinaryFormatError as exc:
                raise ValidationError(
                    f"{path_text} is not a valid {binary_format} payload: "
                    f"{exc}"
                ) from exc

    # The session document is guaranteed present and schema-valid by the
    # foundation check above; it grounds the manifest's declared session
    # and coordinate-space identities (legacy bolph71656-ai/HTDT-Capture#194).
    session_document = schema_documents["session/capture-session.json"]
    if session_document["capture_session_id"] not in set(
        manifest["capture_session_ids"]
    ):
        raise ValidationError(
            "session/capture-session.json capture_session_id is not "
            "declared in manifest capture_session_ids"
        )
    if session_document["coordinate_space_id"] not in set(
        manifest["coordinate_space_ids"]
    ):
        raise ValidationError(
            "session/capture-session.json coordinate_space_id is not "
            "declared in manifest coordinate_space_ids"
        )
    # RoomPlan lineage (legacy bolph71656-ai/HTDT-Capture#194): the processed inference payload may never
    # be promoted without its raw authority. When the canonical processed
    # path is declared, the canonical raw payload must be declared and
    # bound by digest in the processed entry's source_refs. Legacy
    # bundles carrying RoomPlan payloads at non-reserved paths are left
    # to the ingestor's provenance-class handling.
    if "roomplan/captured-room.json" in declared:
        raw_path = "roomplan/captured-room-data.json"
        if raw_path not in declared:
            raise ValidationError(
                "processed RoomPlan payload roomplan/captured-room.json "
                "is missing its raw lineage payload "
                "roomplan/captured-room-data.json"
            )
        raw_digest = declared_entries[raw_path]["sha256"]
        processed_refs = declared_entries["roomplan/captured-room.json"][
            "source_refs"
        ]
        if (
            f"sha256:{raw_digest}" not in processed_refs
            and f"path:{raw_path}" not in processed_refs
        ):
            raise ValidationError(
                "roomplan/captured-room.json does not reference its raw "
                "authority roomplan/captured-room-data.json"
            )

    # Cross-document checks bind schema-owned indexes/descriptors to the
    # binary payloads they name.
    mesh_index = schema_documents.get("mesh/anchors.json")
    if mesh_index is not None:
        _cross_check_mesh_anchors(
            mesh_index, binary_facts, declared_entries, manifest
        )
    for path_text, document in schema_documents.items():
        if FRAME_DESCRIPTOR_RE.fullmatch(path_text):
            _cross_check_frame_descriptor(
                path_text, document, binary_facts, declared_entries, manifest
            )

    # External authority dependencies (legacy bolph71656-ai/HTDT-Capture#337): when the manifest is
    # declared, every entity-carried external reference must be covered
    # by an exact-pin dependency, embedded copies must name declared
    # payloads, and bound entity refs must resolve.
    deps_document = schema_documents.get("derived/authority-dependencies.json")
    if deps_document is not None:
        _cross_check_authority_dependencies(
            deps_document,
            schema_documents.get("annotations/entities.json"),
            declared_entries,
        )

    bundle_digest = hashlib.sha256(manifest_bytes).hexdigest()
    return {
        "valid": True,
        "schema": manifest["schema"],
        "schema_version": manifest["schema_version"],
        "capture_revision_id": manifest["capture_revision_id"],
        "bundle_digest": bundle_digest,
        "payload_count": len(declared_entries),
        "payload_versions": payload_versions,
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
