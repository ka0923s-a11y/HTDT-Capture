# HTDT-Capture

HTDT-Capture is the iPhone/iPad capture frontend for **Home Theater Digital Twin (HTDT)**.

The project is designed to preserve real-room capture evidence and provenance rather than merely generate a visually attractive 3D model.

## Current status

The Capture Bundle v1 contract, canonical codecs, validator/finalizer authorities,
annotation and measurement authorities, HTDT ingestion reference contract, and
spatial-accuracy analysis foundation are implemented.

The iOS host now drives a concrete one-scan capture path through:

```text
capability + permission gates
  -> shared RoomPlan / ARSession capture
  -> one exact scan-end ARFrame
       -> final active ARMeshAnchor snapshot
       -> packed camera evidence
       -> discrete sceneDepth/confidence when actually available
  -> raw CapturedRoomData persistence
  -> RoomBuilder-derived CapturedRoom persistence
  -> mutable Capture Bundle working revision
  -> re-read integrity preflight
  -> explicit quality report
  -> canonical manifest + local validation
  -> same-volume atomic finalized revision
```

Annotation and measurement collections also have deterministic working-set
persistence and feed the quality completeness authority.

The repository includes an unsigned IPA build workflow, and the software paths
above are compiled/tested in GitHub Actions. **Physical-device success is not
implied by CI.** Real LiDAR RoomPlan/ARMesh/frame/depth behavior, alignment,
interruption/resource behavior, interactive placement UX, native
`.htdtcapture` share/export, and the physical accuracy benchmark remain open.

The implementation baseline is documented in:

- [Detailed implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [iOS host capture workflow](docs/HOST_CAPTURE_WORKFLOW.md)
- [Phase 2 live working-set persistence](docs/PHASE2_LIVE_WORKING_SET_PERSISTENCE.md)
- [Phase 3 frame/depth evidence](docs/PHASE3_FRAME_DEPTH_EVIDENCE.md)
- [Phase 4 working-set authorities](docs/PHASE4_WORKING_SET_AUTHORITIES.md)
- [Phase 5 live quality/finalization](docs/PHASE5_LIVE_QUALITY_FINALIZATION.md)

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

## Implementation milestones

1. Capture Bundle v1 contract — foundation implemented
2. SwiftUI / ARSession foundation — concrete host workflow integrated; physical-device recovery/resource verification open
3. RoomPlan + ARMesh dual capture — raw/postprocessed lineage + final active mesh persistence wired; real capture/alignment verification open
4. Pose-linked image/depth evidence — scan-end live working-set path wired; real-device pixel/depth behavior verification open
5. HTDT-specific equipment/reference annotations — typed authority + working-set persistence implemented; interactive placement/equipment UI open
6. User-attested measurement authority — typed authority + working-set persistence implemented; entry/edit UX open
7. Bundle validation/finalization/export — live quality + atomic finalization wired; native validated `.htdtcapture` share/export open
8. HTDT ingestion integration — deterministic reference contract implemented; production HTDT mesh adapter implemented; full backend transaction integration in progress
9. Spatial accuracy benchmark — protocol/analyzer implemented; physical benchmark open

See the implementation plan for architecture, scope, acceptance criteria, testing strategy, and risk controls.

## Core contracts

- [Architecture](docs/ARCHITECTURE.md)
- [Capture Bundle v1](docs/CAPTURE_BUNDLE_V1.md)
- [Coordinate and time contract](docs/COORDINATE_AND_TIME_CONTRACT.md)
- [Binary formats v1](docs/BINARY_FORMATS_V1.md)
- [Accuracy validation protocol](docs/ACCURACY_VALIDATION_PROTOCOL.md)
- [HTDT ingestion contract](docs/HTDT_INGESTION_CONTRACT.md)
- [JSON schemas](schemas/capture-bundle-v1/)
- [Reference bundle validator](tools/bundle_validator/README.md)
