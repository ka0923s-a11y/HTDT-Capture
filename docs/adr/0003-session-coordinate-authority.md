# ADR-0003: ARSession owns capture coordinate authority

Status: Accepted  
Date: 2026-09-20

## Context

RoomPlan, mesh evidence, camera/depth evidence, and equipment annotations only compose safely when their coordinate relationship is explicit.

UI lifecycle and capture-framework stop/restart behavior can accidentally reset tracking.

## Decision

The app-owned ARSession is the coordinate-space authority for one sensor capture session.

- Same-frame workflows keep that ARSession alive.
- RoomPlan completion is not equivalent to ARSession termination.
- A world-origin reset or incompatible ARSession restart produces a new `coordinate_space_id`.
- Cross-coordinate-space composition requires a future explicit alignment authority.

## Consequences

The UI cannot freely recreate session-owning views.

State ownership lives above SwiftUI presentation views.

Multi-session/resume workflows are intentionally constrained until alignment is implemented.

## Alternatives considered

### Treat capture revision as one coordinate system
Rejected because a revision may contain multiple sessions or a reset.

### Infer continuity from timestamps/device identity
Rejected because temporal/device continuity does not prove spatial-frame continuity.

## Validation

Phase 1 state-machine tests simulate reset transitions; physical-device tests verify RoomPlan stop/pause/session continuity.
