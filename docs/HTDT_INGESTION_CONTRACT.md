# HTDT Ingestion Contract

Status: Phase 0 interface contract

## 1. Boundary

HTDT-Capture packages evidence. HTDT validates and ingests it.

The capture app does not create final `SemanticAcousticGeometry`, repair canonical mesh evidence, or claim solver authority.

## 2. Import sequence

```text
.htdtcapture
 -> archive safety validation
 -> manifest/schema validation
 -> payload length/hash validation
 -> source evidence registry
 -> capture identity/coordinate registry
 -> source-specific adapters
 -> RawVisualMesh and other exact source authorities
 -> diagnostics / bounded repair
 -> SemanticAcousticGeometry
 -> SceneRevision
```

No source-derived object is promoted before bundle validation succeeds.

## 3. Required retained lineage

HTDT ingestion stores:

- bundle digest;
- capture schema version;
- capture-series/revision IDs;
- capture-session IDs;
- coordinate-space IDs;
- every source payload SHA-256;
- source provenance class;
- source path/record identity;
- adapter/software version producing each downstream authority.

## 4. Mesh mapping

ARMeshAnchor geometry remains traceable anchor-by-anchor.

A `RawVisualMesh` derived from capture evidence must retain exact source references sufficient to identify:

- bundle digest;
- mesh anchor record;
- `.meshbin` SHA-256;
- `coordinate_space_id`;
- `T_world_from_mesh_anchor`.

A fused mesh may be produced only as a derived authority with lineage to all contributing anchors.

## 5. RoomPlan mapping

When Apple raw serialization is available, HTDT stores raw `CapturedRoomData`
and postprocessed `CapturedRoom` as distinct evidence records. The
postprocessed record retains the exact source raw RoomPlan payload hash.

If `CapturedRoomData` cannot be serialized but the same in-memory completion
is successfully processed by `RoomBuilder`, Capture Bundle v1 may contain
only the postprocessed `CapturedRoom`. That record must carry both:

- `capture_session:<uuid>`, resolving to a manifest capture-session authority;
- `roomplan_raw_serialization:unavailable`.

No raw payload or raw hash is fabricated. Reference ingestion rejects an
unknown capture-session marker, a processed-only marker when raw RoomPlan is
also present, or unsupported source-ref prefixes.

User corrections do not mutate either Apple artifact.

## 6. User measurement mapping

A user-attested measurement remains a separate authority from RoomPlan, ARKit mesh, and backend derivation.

The backend may apply a versioned precedence/reconciliation policy, but disagreement remains queryable and auditable.

## 7. Coordinate behavior

HTDT never combines spatial records from two `coordinate_space_id` values without an explicit alignment authority.

A parent capture revision does not imply spatial alignment with its child revision.

## 8. Determinism

Given:

- identical finalized bundle bytes;
- identical supported capture schema version;
- identical ingestion software version/configuration;

identity and lineage outputs that are defined as deterministic must reproduce exactly.

Solver results and later heuristic algorithms are outside this narrow ingestion determinism guarantee unless separately versioned.

## 9. Failure behavior

Import fails closed for:

- unsupported schema version;
- unsafe archive structure;
- manifest non-canonicality;
- missing/undeclared payloads;
- byte-length mismatch;
- hash mismatch;
- duplicate/colliding logical paths;
- invalid identity/coordinate references.

No partial evidence promotion survives a failed import transaction.


## 10. Reference ingestion plan v1

The capture repository provides a deterministic reference implementation at
`tools/htdt_ingestion/reference_ingestor.py`.

It produces `htdt.capture.ingestion-plan` schema version `1.0.0` only
after the full Capture Bundle v1 validator succeeds.

The plan is a source-lineage handoff contract. It does not create
`SemanticAcousticGeometry`, choose solver boundaries, repair canonical
mesh evidence, or resolve conflicting measurements.

## 11. Deterministic lineage identifiers

For reference ingestor v1.0.0, deterministic IDs are SHA-256
domain-separated hashes over exact UTF-8 inputs:

```text
source_evidence_id =
  SHA256("htdt.capture.source-evidence.v1" || 0x00
         || bundle_digest || 0x00
         || logical_path || 0x00
         || payload_sha256)

raw_visual_mesh_handoff_id =
  SHA256("htdt.capture.raw-visual-mesh-handoff.v1" || 0x00
         || bundle_digest || 0x00
         || anchor_id || 0x00
         || geometry_payload_sha256)

authority_record_handoff_id =
  SHA256("htdt.capture.authority-record.v1" || 0x00
         || bundle_digest || 0x00
         || source_payload_sha256 || 0x00
         || record_kind || 0x00
         || record_id)
```

These IDs are content/lineage identities, not signatures.

Changing the ingestor version, ID domain string, or configuration requires
an explicit contract/version change.

## 12. Transaction boundary

Production HTDT ingestion should treat the generated plan as a transaction
input:

1. validate the Capture Bundle;
2. build/validate the ingestion plan;
3. stage source evidence and exact handoffs;
4. commit all source authorities atomically;
5. only then allow later backend derivation.

No partial source-evidence registry or RawVisualMesh promotion may survive a
failed import.

## 13. Frozen compatibility fixture

`samples/phase6-integration` is the pinned v1 integration fixture.

Expected logical bundle digest:

`925108a1b3c1b432182efe1b7e18ccb0f1d98f4f17c939ca66a6095b0cc28550`

Expected reference-ingestor v1.0.0 lineage digest:

`729a7590fb1d1e2142c196187ef11a9078522326daa1ef2fd2364b8fd1ef6bf1`

CI verifies that directory and `.htdtcapture` archive wrappers produce the
same canonical ingestion plan for this fixture.
