# iOS Host Capture Workflow

Status: implemented as a GitHub-verifiable integration slice; physical-device behavior remains unverified.

Related issues: #2, #3, #4, #6, #9

## Purpose

The initial iOS host application only rendered `CaptureRootView` with a fixed
`.idle` state. The host now owns and drives the existing capture state machine,
camera permission boundary, runtime capability matrix, and shared
`RoomCaptureSession` / `ARSession` controller.

This slice intentionally does not claim that real RoomPlan, ARMesh, RGB/depth,
or final bundle evidence has been captured successfully on hardware.

## Host state flow

The implemented path is:

```text
idle
  -> capability_check
  -> permissions
  -> preparing
  -> scanning
       <-> paused
  -> reviewing
```

A capability, permission, state-machine, or RoomPlan startup failure moves the
host to `failed` with a typed `CaptureFailureCode`.

The failure reset path pauses the old AR session and creates a new
`SharedARSessionController`, which also creates a fresh
`CaptureSessionContext`.

## Coordinate-space behavior

Pause and transition-to-review call:

`stopRoomPlanPreservingARSession()`

which uses RoomPlan's `stop(pauseARSession: false)` path. The host therefore
does not intentionally destroy the shared AR world frame merely because scanning
is paused or the user moves into review.

A failed-session reset instead calls `stopAndPauseARSession()` and creates a
new controller/context. Evidence captured before and after such a reset must not
be silently presented as one coordinate-space authority.

## Camera permission

The platform package now exposes a typed `CameraPermissionStatus` and a bounded
camera-only permission request adapter. The host does not advance from
`permissions` to `preparing` unless camera access is authorized.

The existing `NSCameraUsageDescription` in the app target remains the user
facing privacy declaration.

## UI controls

The root view now exposes state-appropriate actions:

- start from idle;
- pause during scanning;
- resume from paused;
- stop scanning and enter review;
- reset after a failure.

Capabilities, current permission state, typed failure state, and the unresolved
combined RoomPlan/depth physical probe are visible instead of being silently
inferred.

## Explicitly not completed by this slice

The following still require implementation and/or real-device evidence:

- RoomPlan visual coaching / live camera presentation;
- capture delegates that persist canonical raw `CapturedRoomData`;
- active ARMeshAnchor collection and final anchor snapshot persistence;
- selected ARFrame RGB/depth evidence persistence;
- real sceneDepth behavior during RoomPlan and after same-session stop;
- live annotation placement and raycast provenance;
- capture working-set assembly;
- quality report generation from the live working set;
- review -> validation -> atomic finalization -> share/export wiring;
- interruption, thermal, storage, and persistence-pressure behavior;
- physical accuracy benchmark under Issue #9.

No capability or accuracy claim should be promoted from the successful CI build
of this workflow.
