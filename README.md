# HTDT-Capture

HTDT-Capture is the iPhone/iPad capture frontend for **Home Theater Digital Twin (HTDT)**.

The project is designed to preserve real-room capture evidence and provenance rather than merely generate a visually attractive 3D model.

## Current status

The Capture Bundle v1 contract, canonical codecs, validator/finalizer foundations,
annotation and measurement authorities, HTDT ingestion reference contract, and
spatial-accuracy analysis foundation are implemented.

The repository also contains an iOS host application and an unsigned IPA build
workflow. The host now drives the existing capture state machine through runtime
capability checking, camera permission, RoomPlan start, pause/resume, and
transition to review while preserving the shared ARSession where intended.

Real-device RoomPlan/ARMesh/frame/depth evidence capture, live artifact
persistence, review/finalization/export wiring, and the physical accuracy
benchmark remain open.

The implementation baseline is documented in:

- [Detailed implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [iOS host capture workflow](docs/HOST_CAPTURE_WORKFLOW.md)

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
2. SwiftUI / ARSession foundation — host workflow integrated; physical-device verification open
3. RoomPlan + ARMesh dual capture — codecs/adapters implemented; real capture open
4. Pose-linked image evidence — codecs/adapters implemented; real capture open
5. HTDT-specific equipment/reference annotations — authorities implemented; placement UI open
6. User-attested measurement authority — implemented
7. Bundle validation/finalization/export — core authority implemented; live app wiring open
8. HTDT ingestion integration — reference contract implemented; production HTDT backend adapter open
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
