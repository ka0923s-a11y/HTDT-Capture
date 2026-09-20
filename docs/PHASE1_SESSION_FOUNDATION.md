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
- Core contract tests and GitHub Actions iOS archive/unsigned IPA build.

See `docs/HOST_CAPTURE_WORKFLOW.md` for the host integration boundary.

## Intentionally not claimed complete

The following require further implementation and/or real iOS hardware and
therefore remain open in Issue #2:

- prove RoomPlan + scene reconstruction behavior on the target LiDAR device;
- determine whether sceneDepth survives while RoomPlan is running;
- prove whether sceneDepth can be enabled/acquired after stopping RoomPlan while preserving the same ARSession/world frame;
- bind real capture delegates and persistence to the host workflow;
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
