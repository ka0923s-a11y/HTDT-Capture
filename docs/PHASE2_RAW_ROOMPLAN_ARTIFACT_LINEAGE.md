# Phase 2 Raw RoomPlan Artifact Lineage

Status: implemented in software; physical-device persistence/reopen remains open  
Issue: #3

## Purpose

This slice establishes the authority path from RoomPlan scan completion to
raw and postprocessed evidence without fabricating evidence when Apple's raw
Codable serialization is unavailable.

Preferred path:

```text
RoomCaptureViewDelegate completion(CapturedRoomData)
  -> exact Codable raw bytes
  -> raw evidence digest/descriptor
  -> RoomBuilder.capturedRoom(from: same CapturedRoomData)
  -> exact Codable processed bytes
  -> processed descriptor bound to raw SHA-256
```

Bounded fallback:

```text
RoomCaptureViewDelegate completion(CapturedRoomData)
  -> raw Codable serialization unavailable
  -> RoomBuilder.capturedRoom(from: same in-memory CapturedRoomData)
  -> exact Codable processed bytes
  -> processed descriptor with sourceRawSerializationStatus=unavailable
  -> manifest source_refs bind the exact capture-session authority
```

## Session completion boundary

`SharedARSessionController` now owns a strongly retained
`RoomCaptureSessionDelegate` bridge. The controller exposes a bounded
completion handler while keeping ownership of the underlying RoomCaptureSession.

The callback returns the exact `CapturedRoomData` supplied by RoomPlan together
with any framework error. It does not reinterpret an error as successful
evidence.

## Raw authority when serializable

`RoomPlanArtifactProcessor.encodeRaw` serializes the exact
`CapturedRoomData` through the RoomPlan Codable encoder and creates a
`RoomPlanRawArtifactPayload` when that serialization succeeds.

The raw artifact is a complete authority on its own. It has:

- exact `capture_session_id`;
- exact `coordinate_space_id`;
- canonical logical path `roomplan/captured-room-data.json`;
- byte count;
- SHA-256 of the exact encoded bytes;
- runtime provenance.

A later `RoomBuilder` failure does not invalidate or overwrite this raw
artifact. Conversely, a raw serialization failure does not imply that the
in-memory `CapturedRoomData` is unusable by `RoomBuilder`.

## Postprocessed lineage

`RoomPlanArtifactProcessor.deriveProcessed` invokes
`RoomBuilder.capturedRoom(from:)` on the same raw RoomPlan value. If successful,
the encoded `CapturedRoom` is represented by
`RoomPlanProcessedArtifactPayload`.

When raw serialization succeeded, its descriptor contains `sourceRawSHA256`
equal to the exact raw artifact hash, plus the same capture-session and
coordinate-space identities.

When raw serialization was unavailable, the processed descriptor instead has
`sourceRawSerializationStatus=unavailable` and no raw hash. The final manifest
records `capture_session:<uuid>` and
`roomplan_raw_serialization:unavailable`. This is an explicit loss of one
evidence representation, not a synthetic raw authority.

## Verification

Core and ingestion tests verify:

- raw evidence can be constructed independently of postprocessing;
- exact raw bytes determine the raw SHA-256;
- raw-backed processed evidence is hash-bound to the raw evidence;
- processed-only fallback carries an explicit raw-unavailable marker and exact
  capture-session authority;
- unknown or inconsistent fallback source refs fail closed;
- session and coordinate-space identities are preserved across derivation.

The iOS CI compile validates the RoomPlan delegate and RoomBuilder API surface.

## Remaining hardware/integration gates

- invoke the completion handler from a physical LiDAR RoomPlan scan;
- persist the raw artifact immediately into the live working set;
- persist the processed artifact without replacing raw evidence;
- reopen real encoded `CapturedRoomData` and re-run RoomBuilder;
- compare regenerated postprocessed identity/semantics under a pinned
  OS/framework context;
- bind final mesh evidence from the same coordinate space;
- execute Issue #9 physical RoomPlan/mesh accuracy validation.

No physical capture or accuracy claim is made by this slice.
