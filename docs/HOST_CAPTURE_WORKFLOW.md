# iOS Host Capture Workflow

Status: implemented as a GitHub-verifiable integration slice; physical-device behavior remains unverified.

Related issues: #2, #3, #4, #6, #9

## Purpose

The iOS host owns and drives the capture state machine, camera permission
boundary, runtime capability matrix, shared `RoomCaptureSession` /
`ARSession`, and the mutable capture working set.

This does not claim that a physical LiDAR device has successfully produced the
evidence. It establishes the software execution path and fail-closed boundaries.

## Host state flow

The concrete host path is:

```text
idle
  -> capability_check
  -> permissions
  -> preparing
       create unique working revision
       bind RoomPlan completion handler
  -> scanning
  -> reviewing
       final active mesh snapshot persisted
       raw RoomPlan persisted on completion callback
       processed RoomPlan persisted only from exact raw evidence
```

Capability, permission, capture-start, tracking/snapshot, RoomPlan, or
persistence failures move the host to `failed` with a typed
`CaptureFailureCode`.

## Working revision

Each started capture receives a fresh `CaptureWorkingSetIdentity` and a unique
mutable directory under Application Support:

`HTDTCapture/working/<capture-revision-id>/`

The host retains failed working revisions rather than silently deleting source
evidence. Reset invalidates the old callback generation and creates a fresh
ARSession/context for the next capture.

## RoomPlan scan boundary

RoomPlan `stop(pauseARSession: false)` ends the current room-capture scan while
leaving the underlying ARSession running. It is treated as a scan boundary, not
as an in-place pause operation.

Immediately before that stop, the host copies the current active
`ARMeshAnchor` set into typed immutable snapshots. After the stop call, those
snapshots are packaged and persisted into the same working revision.

The RoomPlan completion delegate separately persists exact
`CapturedRoomData` bytes first. Only if RoomPlan did not report a framework
failure does the host run `RoomBuilder` and persist the postprocessed
`CapturedRoom`, hash-bound to the exact raw artifact.

## Coordinate-space behavior

The working-set store binds the first spatial evidence to one exact
`capture_session_id` and `coordinate_space_id`. RoomPlan and mesh evidence
with a different authority are rejected rather than combined.

The current production host has one RoomPlan scan per working revision. Future
multi-scan support must model scan-segment identity before additional
`run(configuration:)` calls are allowed.

## Camera permission

The platform package exposes a typed `CameraPermissionStatus` and a bounded
camera-only permission request adapter. The host does not advance from
`permissions` to `preparing` unless camera access is authorized.

## Still not completed

The following remain implementation and/or physical-device gates:

- RoomPlan visual coaching / live camera presentation;
- real LiDAR proof that the completion callback persists reopenable
  `CapturedRoomData`;
- real RoomPlan/ARMesh same-world alignment evidence;
- selected ARFrame RGB/depth persistence;
- real sceneDepth behavior during RoomPlan and after same-session stop;
- live annotation placement and raycast provenance;
- quality report generation from the complete live working set;
- review -> validation -> atomic finalization -> share/export wiring;
- interruption, thermal, storage, and persistence-pressure behavior;
- physical accuracy benchmark under Issue #9.

No capability or accuracy claim is promoted from a successful CI build.
