# RoomPlan completion zero-base correction — 2026-09-20

## Physical evidence that invalidated the previous diagnosis

The 22:42 JST device pass reached 100% directional guidance with normal tracking and active scene-depth fallback, then failed after End with:

- work-data stage: `RoomPlan の生データをエンコードできませんでした`
- terminal error: persistence failure
- device storage: about 79 GB free (176.82 GB used of 256 GB)

Therefore the failure is **not a storage-capacity failure** and is downstream of the pre-End frame/depth persistence work.

## Root cause

HTDT-Capture made serialization of Apple's opaque `CapturedRoomData` with `JSONEncoder` a mandatory prerequisite to RoomPlan post-processing.

That dependency is invalid. Apple's RoomPlan contract allows the opaque completion object to be processed directly by `RoomBuilder.capturedRoom(from:)`. In the field, `CapturedRoomData.encode(to:)` can reject otherwise processable completion data with an `EncodingError.invalidValue` at the root object. A public report of the same failure exists on iOS 17.3/17.4, while Apple's documentation still describes serialization and post-processing as separate capabilities.

The previous implementation stopped immediately on raw serialization failure, so it never attempted the independent processed-room path.

## New authority model

The completion pipeline now has two independent evidence branches:

1. **Raw Apple RoomPlan serialization**
   - retained when `CapturedRoomData` serialization succeeds;
   - hash-bound exactly as before;
   - if serialization is unavailable, a warning event records that fact. No fabricated raw payload is created.

2. **Processed RoomPlan result**
   - always attempted directly from the in-memory `CapturedRoomData` when RoomPlan itself did not report failure;
   - persisted as canonical `roomplan/captured-room.json`;
   - if raw bytes exist, the processed result remains SHA-bound to them;
   - if raw serialization is unavailable, the processed descriptor explicitly carries `sourceRawSerializationStatus = unavailable`, has no raw SHA, and the bundle manifest records `roomplan_raw_serialization:unavailable` plus the exact capture-session authority.

The store rejects mixed or ambiguous lineage. A processed-without-raw descriptor cannot be used when a raw descriptor is already present.

## Failure semantics

- Raw serialization failure alone is no longer terminal.
- Raw serialization success followed by a real filesystem write failure is still terminal/fail-closed.
- RoomPlan framework failure remains terminal.
- Failure to produce a processed `CapturedRoom` remains terminal.
- Processed RoomPlan persistence failure remains terminal.
- The generic persistence recovery text no longer tells operators to free storage unless the actual diagnostic is storage pressure / `storage_full`.

## Duplicate callbacks

Completion callback coalescing now occurs before raw serialization. This matters because raw serialization itself may fail; using a raw SHA as the only de-duplication key left the failure path exposed to duplicate completion pipelines.

## Scope

This change fixes the scan-end authority model exposed by the 22:42 device pass. It does **not** claim the round/curved/complex furniture observation pipeline is solved. The live shape preview remains a separate scene-depth/mesh-derived advisory subsystem and requires its own physical acceptance after capture finalization is reliable.

RDC calls: 0.
