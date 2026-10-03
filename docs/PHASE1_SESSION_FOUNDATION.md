# Phase 1 Session Foundation Implementation Record

Status: In progress  
Issue: legacy bolph71656-ai/HTDT-Capture#2

## Implemented

- Swift Package foundation with iOS 27 / macOS 14 baselines (iOS floor raised by ADR-0005).
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
- Core contract tests and the iOS archive/unsigned IPA build (now manual-only;
  no CI).

See `docs/HOST_CAPTURE_WORKFLOW.md` for the host integration boundary.

## Intentionally not claimed complete

The following require further implementation and/or real iOS hardware and
therefore remain open in Issue bolph71656-ai/HTDT-Capture#2:

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


## Failed working-revision cleanup

Resetting from the typed `failed` state now attempts to discard only the
currently owned incomplete working revision.

The store refuses deletion unless the resolved path has the exact shape:

`.../HTDTCapture/working/<capture_revision_id>`

and the final path component exactly matches the store's immutable
`capture_revision_id`.

The discard authority never targets finalized or exported revisions. Resetting
from `exported` therefore performs no working-set deletion.

A cleanup failure does not silently broaden deletion scope; the app returns to
idle and reports that the prior incomplete revision could not be cleaned up.


## Device and session-time authorities

The live host now persists the Bundle v1 metadata that was previously only
specified by contract:

- `session/device.json` records OS/app provenance and the Darwin hardware model
  identifier reported by the running device;
- `session/timing.json` records two monotonic-to-UTC correlation samples in
  the exact ARKit `ARFrame.timestamp` clock domain.

A timing sample brackets the current ARFrame read with two UTC wall-clock
samples. The midpoint becomes the correlation UTC value and half of the bracket
duration is retained as estimated uncertainty. The first usable sample is
required immediately after the RoomPlan session starts; the second is taken at
the scan boundary. Reverse monotonic order fails closed.

`capture-session.json` references `session/timing.json`, and working-set
integrity cannot pass while the timing authority is absent or modified.

The iOS app bundle now also contains `PrivacyInfo.xcprivacy` for the existing
available-disk-space API used by capture resource backpressure. The declaration
uses the approved reason for checking whether sufficient storage remains for
writes; no tracking declaration is enabled.
