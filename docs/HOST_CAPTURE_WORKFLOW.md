# iOS Host Capture Workflow

Status: implemented as a GitHub-verifiable integration slice; physical-device behavior remains unverified.

Related issues: #2, #3, #4, #6, #9

## Purpose

The iOS host owns and drives the existing capture state machine, camera
permission boundary, runtime capability matrix, and shared
`RoomCaptureSession` / `ARSession` controller.

This slice does not claim that real RoomPlan, ARMesh, RGB/depth, or final bundle
evidence has been captured successfully on hardware.

## Host state flow

The concrete host path is:

```text
idle
  -> capability_check
  -> permissions
  -> preparing
  -> scanning
  -> reviewing
```

A capability, permission, state-machine, or RoomPlan startup failure moves the
host to `failed` with a typed `CaptureFailureCode`.

The core state machine still has a generic `paused` state, but the production
host does not map RoomPlan stop/run calls onto that state.

## RoomPlan scan boundary

RoomPlan `stop(pauseARSession: false)` ends the current room-capture scan while
leaving the underlying ARSession running. It is therefore treated as a scan
boundary, not as an in-place pause operation.

The host exposes one explicit `End scan and review` action. It does not expose
a pseudo `Pause/Resume` pair that would silently turn one logical scan into
multiple RoomPlan scans.

Future multi-scan support must model scan-segment identity and preserve every
raw `CapturedRoomData` result before a subsequent `run(configuration:)`.

## Coordinate-space behavior

Transition-to-review calls:

`stopRoomPlanPreservingARSession()`

which uses RoomPlan's `stop(pauseARSession: false)` path. The host therefore
does not intentionally destroy the shared AR world frame merely because one
RoomPlan scan ends.

A failed-session reset instead calls `stopAndPauseARSession()` and creates a
new controller/context. Evidence captured before and after such a reset must not
be silently presented as one coordinate-space authority.

## Camera permission

The platform package exposes a typed `CameraPermissionStatus` and a bounded
camera-only permission request adapter. The host does not advance from
`permissions` to `preparing` unless camera access is authorized.

The existing `NSCameraUsageDescription` in the app target remains the
user-facing privacy declaration.

## UI controls

The root view exposes state-appropriate actions:

- start from idle;
- end the current RoomPlan scan and enter review;
- reset after a failure.

Capabilities, current permission state, typed failure state, and the unresolved
combined RoomPlan/depth physical probe are visible instead of being silently
inferred.

## Explicitly not completed by this slice

The following still require implementation and/or real-device evidence:

- RoomPlan visual coaching / live camera presentation;
- capture delegates that persist canonical raw `CapturedRoomData`;
- real active ARMeshAnchor collection and live evidence persistence;
- selected ARFrame RGB/depth evidence persistence;
- real sceneDepth behavior during RoomPlan and after same-session RoomPlan stop;
- live annotation placement and raycast provenance;
- capture working-set assembly;
- quality report generation from the live working set;
- review -> validation -> atomic finalization -> share/export wiring;
- interruption, thermal, storage, and persistence-pressure behavior;
- physical accuracy benchmark under Issue #9.

No capability or accuracy claim should be promoted from the successful CI build
of this workflow.
