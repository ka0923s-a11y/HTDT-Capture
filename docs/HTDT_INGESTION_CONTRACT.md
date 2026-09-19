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

HTDT stores raw `CapturedRoomData` and postprocessed `CapturedRoom` as distinct evidence records.

The postprocessed record retains its source raw RoomPlan payload hash and producing framework/runtime context.

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
