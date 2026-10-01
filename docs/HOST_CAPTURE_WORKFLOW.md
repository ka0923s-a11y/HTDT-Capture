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
  -> setup                     // pre-capture room-prep / readiness screen
  -> capability_check          // only after the operator taps Begin scanning
  -> permissions
  -> preparing
       create unique working revision
       bind RoomPlan completion handler
  -> scanning
       present the exact shared RoomCaptureView
       sample advisory direction/pitch coverage at ~4 Hz
       keep evidence-frame and finish controls over the camera
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

## Scanner-first live view

The `scanning` state presents the framework-provided `RoomCaptureView`
created with the exact app-owned `ARSession`. The host runs RoomPlan through
that view's own `captureSession`; it does not create a second competing
RoomPlan session.

The live view therefore provides the camera image, RoomPlan structural
overlays/coaching, and miniature model while the existing evidence pipeline
continues to bind to the same ARSession coordinate authority.

In parallel, the host samples bounded advisory coverage telemetry at
approximately 4 Hz. The deterministic tracker bins normal-tracking camera
headings into 12 relative azimuth sectors and low/level/high pitch bands.
This drives the on-screen gap HUD only. It is not persisted as measurement
truth and does not change bundle/finalization authority.

See [GUIDED_SCANNING_UX_PLAN.md](GUIDED_SCANNING_UX_PLAN.md).

## RoomPlan scan boundary

RoomPlan `stop(pauseARSession: false)` ends the current room-capture scan while
leaving the underlying ARSession running. It is treated as a scan boundary, not
as an in-place pause operation.

Immediately before that stop, the host reads one exact `ARFrame`. From that
same frame it copies:

- the active `ARMeshAnchor` set;
- the canonical packed camera image;
- camera pose/intrinsics/timestamp metadata;
- discrete `sceneDepth` and confidence only when they are actually present.

The mesh and frame descriptor therefore refer to the same frame timestamp/world
authority. Missing sceneDepth is recorded as `unavailable`; it is not inferred
from device capability.

The RoomPlan completion delegate separately persists exact
`CapturedRoomData` bytes first. Only if RoomPlan did not report a framework
failure does the host run `RoomBuilder` and persist the postprocessed
`CapturedRoom`, hash-bound to the exact raw artifact.

## Coordinate-space behavior

The working-set store binds the first spatial evidence to one exact
`capture_session_id` and `coordinate_space_id`. RoomPlan and mesh evidence
with a different authority are rejected rather than combined.

Each `run(configuration:)` builds a fresh room model, so a re-run on the same
revision (Continue scanning from Review, or an End-attempt retry) is a new
scanning segment: the next accepted `CapturedRoomData` covers only the final
segment while mesh anchors and evidence frames keep accumulating across all
segments. The host records every re-run as a `roomplan_rescan` advisory note
with the segment ordinal so downstream review can see the room-model
replacement; it never merges room models across segments.

## Camera permission

The platform package exposes a typed `CameraPermissionStatus` and a bounded
camera-only permission request adapter. The host does not advance from
`permissions` to `preparing` unless camera access is authorized.

## Terminal interruption behavior

A terminal capture failure cancels advisory coverage sampling, stops resource
monitoring, invalidates the active callback generation, and then stops/pauses
the shared RoomPlan / AR session. Late RoomPlan/evidence callbacks from the
failed generation are ignored rather than being admitted into a failed
coordinate authority. The host does not silently resume a failed scan.

When the application enters the background during active capture, the working
status is replaced with an explicit interruption reason. The failure UI explains
that HTDT no longer assumes the same AR coordinate space remains valid and
requires the operator to discard the failed working revision before beginning a
fresh capture.

This is deliberately fail-closed. Same-session resume or relocalization must
only be added after a concrete mechanism (for example an independently verified
ARWorldMap/relocalization workflow) demonstrates coordinate continuity.

## Still not completed

The following remain implementation and/or physical-device gates:

- physical-device acceptance of RoomPlan camera/overlay/coaching presentation
  and the advisory coverage HUD;
- real LiDAR proof that the completion callback persists reopenable
  `CapturedRoomData`;
- real RoomPlan/ARMesh same-world alignment evidence;
- additional evidence-frame selection policy beyond the scan-end frame;
- real sceneDepth behavior during RoomPlan and after same-session stop;
- live annotation placement and raycast provenance;
- quality report generation from the complete live working set;
- review -> validation -> atomic finalization -> share/export wiring;
- physical-device interruption/background acceptance and future proven
  relocalization/resume behavior;
- thermal/storage/persistence-pressure acceptance on physical devices;
- physical accuracy benchmark under Issue #9.

No capability or accuracy claim is promoted from a successful CI build.


## End-scan evidence failure domains

Physical testing showed that the former scan-end path placed frame/depth capture,
mesh snapshot conversion, timing preparation, and persistence into one generic
failure domain. Any mesh snapshot/conversion error was therefore surfaced as
`persistence_failure`, even when the current ARFrame and scene-depth evidence
could still be retained.

The corrected scan-end sequence separates those authorities:

1. preflight — snapshot the selected ARFrame/depth, the tracking event, and
   the active mesh anchors in one review-evidence snapshot, plus the end
   timing correlation, and prove the frame/depth/timing packages build;
2. persist the selected frame/depth package (one bounded retry) while
   RoomPlan and the shared ARSession are still live;
3. mark the committed End-boundary frame;
4. re-read the end timing correlation fresh, then build the persisted
   timing package;
5. persist the mesh package only when the preflight snapshot/build produced
   valid mesh evidence;
6. record the tracking event;
7. stop RoomPlan while preserving the shared ARSession and wait — under a
   bounded timeout — for the completion callback that supplies the final
   `CapturedRoomData`.

The second timing snapshot is deliberate: the preflight build is a validation
probe only and is discarded, while the committed package reflects a
session-end correlation taken as close to the RoomPlan stop as the
recoverable steps allow.

A genuinely empty active-mesh set is represented by the valid empty
`mesh/anchors.json` package. A mesh snapshot conversion failure does not erase
already valid frame/depth evidence; review can continue and the quality gate
remains responsible for declaring missing normative evidence.

Actual writer/package persistence errors still fail closed. The working status
now names the stage that failed so a physical-device defect can distinguish
timing, frame/depth, and mesh persistence.

This does **not** relax finalization authority. Retaining partial valid evidence
for review is different from declaring the capture ready for HTDT ingestion.
