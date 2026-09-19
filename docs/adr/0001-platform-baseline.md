# ADR-0001: iOS platform baseline

Status: Accepted  
Date: 2026-09-20

## Context

HTDT-Capture requires RoomPlan, a caller-owned ARSession, reconstructed scene geometry, LiDAR scene depth when available, and raw RoomPlan scan preservation.

The capture architecture also depends on explicitly stopping RoomPlan without necessarily pausing the underlying ARSession so same-world-frame evidence/annotation can continue.

## Decision

The first implementation baseline is:

- minimum deployment target: iOS 17.0;
- hardware gate: runtime `RoomCaptureSession.isSupported`, world tracking, scene reconstruction, and requested frame semantics;
- build SDK/Xcode: the latest stable toolchain used by the repository when Phase 1 is bootstrapped, recorded in the build provenance and this ADR via a superseding ADR if the minimum changes.

The app does not infer support from device model names.

Phase 1 must physically probe the intended RoomPlan + reconstruction + scene-depth workflow. Individual capability flags are not sufficient proof that all requested features remain available simultaneously.

## Consequences

- Older OS releases are intentionally outside the first supported matrix.
- LiDAR hardware without a required runtime capability enters an explicit unsupported/degraded mode.
- If RoomPlan suppresses scene depth while active, the preferred path is to stop RoomPlan while preserving the ARSession, then acquire depth evidence in the same coordinate space.
- If reconfiguration requires tracking reset, a new coordinate-space authority is created.

## Alternatives considered

### iOS 16 minimum
Rejected for the first implementation because the architecture intentionally depends on the newer RoomPlan workflow around caller-owned session/raw scan evolution and would require compatibility branches before the core contract is proven.

### Latest-OS-only
Rejected because it unnecessarily narrows the LiDAR device test matrix without a demonstrated API requirement.

## Validation

Phase 1 must record:

- actual SDK/Xcode version;
- tested device/OS pairs;
- exact combined AR configuration;
- RoomPlan stop/pause behavior;
- whether scene depth remains available during RoomPlan and after same-session transition.
