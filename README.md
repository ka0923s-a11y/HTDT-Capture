# HTDT-Capture

HTDT-Capture is the iPhone/iPad capture frontend for **Home Theater Digital Twin (HTDT)**.

The project is designed to preserve real-room capture evidence and provenance rather than merely generate a visually attractive 3D model.

## Current status

Planning / foundation.

The implementation baseline is documented in:

- [Detailed implementation plan](docs/IMPLEMENTATION_PLAN.md)

## Core concept

```text
Physical room
  -> RoomPlan + ARKit + camera evidence + user annotations
  -> immutable .htdtcapture bundle
  -> HTDT ingestion
  -> RawVisualMesh
  -> SemanticAcousticGeometry
  -> SceneRevision
```

The canonical output of the app is a versioned capture bundle with source evidence, coordinate metadata, authority/provenance information, and cryptographic integrity checks.

GLB/USDZ/OBJ/PLY exports are derived convenience outputs, not the canonical authority.

## Near-term milestones

1. Capture Bundle v1 contract
2. SwiftUI / ARSession foundation
3. RoomPlan + ARMesh dual capture
4. Pose-linked image evidence
5. HTDT-specific equipment/reference annotations
6. Verified measurement authority
7. Bundle validation and export
8. HTDT ingestion integration

See the implementation plan for architecture, scope, acceptance criteria, testing strategy, and risk controls.
