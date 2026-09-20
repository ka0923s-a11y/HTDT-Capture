# Phase 1 Session Foundation Implementation Record

Status: In progress  
Issue: #2

## Implemented

- Swift Package foundation with iOS 17 / macOS 14 baselines.
- Typed capture/session/coordinate identifiers with canonical lowercase UUID serialization.
- Explicit capture state machine and failure/reset semantics.
- Coordinate-space discontinuity lineage.
- Runtime capability model that does not infer support from device marketing names.
- Explicit capture mode/configuration profile model.
- Bounded evidence admission controller.
- Atomic no-overwrite capture file writer.
- Safe relative working-path type.
- ARKit/RoomPlan capability probe behind an iOS-only adapter.
- App-owned shared ARSession controller.
- Explicit `stop(pauseARSession: false)` path for RoomPlan completion while preserving the AR session.
- SwiftUI shell and concrete iOS host application.
- Camera privacy declaration and typed runtime camera-permission adapter.
- Host workflow wiring through:
  - capability check;
  - camera permission;
  - RoomPlan start;
  - pause/resume;
  - transition to review without intentionally pausing the shared ARSession;
  - typed failure state and reset.
- Exact active AR configuration snapshot authority read back from
  `ARSession.configuration` after RoomPlan starts.
- Live working-set persistence of:
  - `session/capture-session.json`;
  - `session/capabilities.json`;
  - `session/capture-configuration.json`.
- Session/configuration/capability files participate in the same re-read
  integrity preflight and finalization path as captured evidence.
- Core contract tests and GitHub Actions iOS archive/unsigned IPA build.

See `docs/HOST_CAPTURE_WORKFLOW.md` for the host integration boundary.

## Intentionally not claimed complete

The following require further implementation and/or real iOS hardware and
therefore remain open in Issue #2:

- prove RoomPlan + scene reconstruction behavior on the target LiDAR device;
- determine whether sceneDepth survives while RoomPlan is running;
- prove whether sceneDepth can be enabled/acquired after stopping RoomPlan while preserving the same ARSession/world frame;
- verify the persisted active AR configuration against a physical target
  LiDAR session and any RoomPlan-internal runtime changes;
- tracking interruption/recovery behavior;
- storage/thermal pressure behavior;
- verify camera permission/start/pause/resume/review behavior on device;
- prove coordinate-space continuity or explicitly record a discontinuity in real interruption/reconfiguration cases.

## Hardware probe authority

The physical probe must record:

- device and OS;
- app/build;
- exact AR configuration;
- capability matrix;
- whether RoomPlan + mesh is stable;
- whether scene depth is present during RoomPlan;
- whether same-session depth works after `stop(pauseARSession: false)`;
- whether any transition changes the coordinate-space authority.

A failed combined-mode probe produces an explicit degraded capture mode rather than silent configuration mutation.


## Active configuration authority

The production host no longer treats a requested/default configuration as proof
of what ARKit is actually running. After `RoomCaptureSession.run` starts, it
reads the app-owned `ARSession.configuration` and snapshots the active
`ARWorldTrackingConfiguration`.

The recorded profile includes:

- world alignment;
- plane-detection options;
- scene-reconstruction mode;
- enabled frame semantics;
- active video resolution/frame rate;
- autofocus state;
- capture mode.

Known option values receive stable tokens. Unknown future option bits are kept
as explicit `unknown_raw_<value>` tokens rather than discarded.

If the running configuration cannot be read or is not world tracking, the host
fails closed instead of writing a guessed configuration profile.


## Software resource and tracking diagnostics

The host now connects the existing quality-event authority to concrete runtime
signals without claiming physical-device acceptance.

During an active capture it records:

- the scan-end ARKit tracking state from the exact ARFrame also used for final
  mesh/camera/depth evidence;
- ProcessInfo thermal-state transitions;
- UIApplication memory warnings;
- application backgrounding as an explicit interruption;
- available storage for important usage at capture start, scan end and
  finalization.

Fair/serious thermal state, memory warnings and low-storage warning thresholds
remain quality warnings. Critical thermal state, critical storage pressure and
background interruption are typed capture failures.

The provisional storage thresholds are an engineering backpressure policy, not
a device-capacity claim:

- warning below 2 GiB available;
- critical below 512 MiB available.

The resource/tracking events flow into the quality report that becomes part of
the finalized bundle. Real-device thermal/storage/interruption behavior remains
a physical acceptance gate.
