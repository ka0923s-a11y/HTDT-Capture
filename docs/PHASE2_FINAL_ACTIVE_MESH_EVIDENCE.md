# Phase 2 Final Active Mesh Evidence Slice

Status: implemented in software; physical-device verification remains open  
Issue: legacy bolph71656-ai/HTDT-Capture#3

## Purpose

This slice connects the existing shared ARSession and ARMesh adapter to the
Capture Bundle v1 mesh evidence layout without taking ownership of
`ARSession.delegate` away from RoomPlan.

It establishes:

```text
shared ARSession current frame
  -> active ARMeshAnchor set
  -> typed MeshAnchorSnapshot[]
  -> deterministic HTDTMSH1 geometry payloads
  -> mesh/anchors.json + mesh/geometry/*.meshbin
```

## Active-anchor snapshot authority

`SharedARSessionController.snapshotActiveMeshAnchors()` reads the current
`ARFrame`, selects the active `ARMeshAnchor` instances and converts each
through the existing `ARMeshSnapshotAdapter`.

Every snapshot is bound to the controller's exact:

- `capture_session_id`;
- `coordinate_space_id`;
- current AR frame timestamp;
- `T_world_from_mesh_anchor`;
- ARMesh anchor UUID.

The method does not install an ARSession delegate and therefore does not create a
second lifecycle authority competing with RoomPlan.

If no current frame exists, the operation fails explicitly rather than producing
an empty snapshot that could be mistaken for a measured empty room.

## Canonical package authority

`MeshEvidencePackageBuilder` converts typed snapshots to the existing Capture
Bundle v1 mesh contract.

For each anchor it:

- requires a schema-compatible UUIDv4;
- requires a finite, non-negative session timestamp;
- rejects duplicate anchor identities;
- encodes geometry with `HTDTMSH1` v1;
- hashes the exact geometry bytes with SHA-256;
- uses deterministic lowercase
  `mesh/geometry/<anchor-id>.meshbin` paths;
- emits a sorted `mesh/anchors.json` index matching
  `schemas/capture-bundle-v1/mesh-anchors.schema.json`.

The package can be persisted through the existing
`AtomicCaptureFileWriter`. Geometry files are written before the index, so the
index is never intentionally published first in the mutable working set.

## Verification

Core tests cover:

- deterministic anchor/path ordering;
- exact geometry digest linkage;
- `HTDTMSH1` decode round-trip of emitted geometry;
- index encode/decode consistency;
- fail-closed missing timestamp behavior;
- duplicate anchor rejection.

The iOS platform target is also compiled locally, exercising the real ARKit
adapter surface at build time.

## Explicit non-claims

This slice does not establish that a physical LiDAR iPhone actually returns the
expected active mesh set during or after RoomPlan. It also does not establish
RoomPlan-to-mesh alignment accuracy.

The remaining Issue bolph71656-ai/HTDT-Capture#3 hardware gates include:

- capture a real RoomPlan + ARMesh session;
- preserve and reopen real `CapturedRoomData`;
- regenerate a real postprocessed `CapturedRoom`;
- persist this final active-anchor package from the live host working set;
- verify the anchors and RoomPlan are in the declared same coordinate space;
- execute the physical alignment/accuracy benchmark under Issue bolph71656-ai/HTDT-Capture#9.
