# Phase 2 Raw RoomPlan Artifact Lineage

Status: implemented in software; physical-device persistence/reopen remains open  
Issue: legacy bolph71656-ai/HTDT-Capture#3

## Purpose

This slice establishes the exact authority path from RoomPlan scan completion to
raw and postprocessed evidence without allowing postprocessing failure to erase
the raw scan authority.

```text
RoomCaptureSessionDelegate.didEndWith(CapturedRoomData)
  -> exact Codable raw bytes
  -> raw evidence digest/descriptor
  -> RoomBuilder.capturedRoom(from: same CapturedRoomData)
  -> exact Codable processed bytes
  -> processed descriptor bound to raw SHA-256
```

## Session completion boundary

`SharedARSessionController` now owns a strongly retained
`RoomCaptureSessionDelegate` bridge. The controller exposes a bounded
completion handler while keeping ownership of the underlying RoomCaptureSession.

The callback returns the exact `CapturedRoomData` supplied by RoomPlan together
with any framework error. It does not reinterpret an error as successful
evidence.

## Raw-first authority

`RoomPlanArtifactProcessor.encodeRaw` serializes the exact
`CapturedRoomData` through the existing RoomPlan Codable encoder and creates a
`RoomPlanRawArtifactPayload`.

The raw artifact is a complete authority on its own. It has:

- exact `capture_session_id`;
- exact `coordinate_space_id`;
- canonical logical path `roomplan/captured-room-data.json`;
- byte count;
- SHA-256 of the exact encoded bytes;
- runtime provenance.

A later `RoomBuilder` failure does not invalidate or overwrite this raw
artifact.

## Postprocessed lineage

`RoomPlanArtifactProcessor.deriveProcessed` invokes
`RoomBuilder.capturedRoom(from:)` on the same raw RoomPlan value. If successful,
the encoded `CapturedRoom` is represented by
`RoomPlanProcessedArtifactPayload`.

Its descriptor contains `sourceRawSHA256` equal to the exact raw artifact hash,
plus the same capture-session and coordinate-space identities.

## Verification

Core tests verify:

- raw evidence can be constructed independently of postprocessing;
- exact raw bytes determine the raw SHA-256;
- processed evidence is hash-bound to the raw evidence;
- session and coordinate-space identities are preserved across derivation.

The local iOS compile validates the RoomPlan delegate and RoomBuilder API surface.

## Remaining hardware/integration gates

- invoke the completion handler from a physical LiDAR RoomPlan scan;
- persist the raw artifact immediately into the live working set;
- persist the processed artifact without replacing raw evidence;
- reopen real encoded `CapturedRoomData` and re-run RoomBuilder;
- compare regenerated postprocessed identity/semantics under a pinned
  OS/framework context;
- bind final mesh evidence from the same coordinate space;
- execute Issue bolph71656-ai/HTDT-Capture#9 physical RoomPlan/mesh accuracy validation.

No physical capture or accuracy claim is made by this slice.
