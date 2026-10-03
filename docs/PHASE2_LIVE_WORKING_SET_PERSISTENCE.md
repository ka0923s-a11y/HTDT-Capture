# Phase 2 Live Working-Set Persistence

Status: core persistence authority and iOS host hookup implemented; physical-device verification remains open  
Issue: legacy bolph71656-ai/HTDT-Capture#3  
Related: legacy bolph71656-ai/HTDT-Capture#6

## Purpose

The capture pipeline already had exact RoomPlan and final-active-mesh artifact
builders, but those artifacts were not yet assembled into the mutable directory
that later becomes a finalized Capture Bundle revision.

This slice introduces a bounded working-set store:

```text
exact raw RoomPlan payload
  -> no-overwrite roomplan/captured-room-data.json

exact processed RoomPlan payload
  -> verify exact raw SHA/session/coordinate lineage
  -> no-overwrite roomplan/captured-room.json

typed final active mesh package
  -> validate typed index == exact index bytes
  -> validate every geometry digest/link
  -> no-overwrite mesh/geometry/*.meshbin
  -> no-overwrite mesh/anchors.json

all successful writes
  -> exact BundlePayloadDeclaration[]
  -> later quality/finalizer input
```

## Authority rules

`CaptureWorkingSetStore` does not recompute RoomPlan or mesh semantics. It only
accepts already-typed artifacts and verifies their byte/digest/lineage
relationships before publishing them into the mutable working directory.

Processed RoomPlan evidence cannot be persisted before the exact raw RoomPlan
artifact is present in the store. Its `sourceRawSHA256`, session ID, and
coordinate-space ID must match the raw descriptor exactly.

The mesh package is accepted only when:

- `mesh/anchors.json` bytes decode to the exact typed index;
- geometry paths are one-to-one with anchor records;
- each geometry digest matches its exact bytes;
- every anchor record references the matching geometry digest.

The store emits the same producer/provenance/role/source-ref vocabulary used by
the frozen Phase 6 fixture, so the result can be handed directly to
`BundleRevisionFinalizer` after the other required payloads and quality gates
exist.

## Failure semantics

Each payload write remains atomic and no-overwrite. The multi-file mesh package
is not claimed to be a filesystem transaction in this slice. If a mesh-package
write fails partway through, that mutable revision is considered failed and
should be abandoned rather than silently retried over partial evidence.

Finalized revisions remain protected by the separate atomic finalizer.

## Verification

Focused core tests verify:

- raw -> processed exact SHA lineage;
- deterministic manifest declarations;
- final active mesh geometry/index source refs;
- actual working-directory files;
- processed-before-raw rejection;
- rejection when typed mesh index and encoded index bytes disagree.


## Live host hookup

The concrete iOS host now creates one unique mutable working revision after
capability and camera-permission gates pass.

At scan end it:

1. copies the current active ARMeshAnchor set into immutable typed snapshots;
2. calls RoomPlan stop while preserving the shared ARSession;
3. enters review;
4. persists the copied final active mesh package.

The RoomPlan completion callback independently:

1. encodes exact CapturedRoomData;
2. persists raw RoomPlan evidence first;
3. retains that raw evidence even when RoomPlan reports a framework failure;
4. when successful, derives CapturedRoom through RoomBuilder;
5. persists the processed artifact only with exact raw SHA/session/coordinate
   lineage.

A generation token prevents a delayed callback from an abandoned failed capture
from mutating a later capture's UI/state.

The host exposes working-set persistence status but does not claim quality
readiness or finalization.
