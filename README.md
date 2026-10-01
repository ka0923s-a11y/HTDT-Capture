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
  -> scanner-first live RoomPlan / shared ARSession capture
       -> rear-camera view + RoomPlan structural overlays/coaching
       -> RoomPlan miniature model
       -> advisory 12-direction × 3-height coverage HUD
       -> end-scan gap review with continue/end choice
  -> shared RoomPlan / ARSession evidence capture
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

The live scanner is intentionally explicit about authority: its directional
coverage and gap prompts are operator guidance only. They are not persisted as
measurement truth and do not silently become finalization or ingestion gates.
Terminal/background interruptions fail closed and require a fresh capture
authority rather than pretending AR coordinate continuity.

The software paths above are compiled/tested locally with `swift build` and
`swift test`. An IPA is built manually — there is no CI — either via a
manually dispatched workflow or the local script, both documented
in [docs/IPA_BUILD.md](docs/IPA_BUILD.md). **Physical-device success is not
implied by a clean build.** Real LiDAR RoomPlan/ARMesh/frame/depth behavior, spatial
alignment, interruption/relocalization behavior, resource behavior, and the
physical accuracy benchmark remain open. Manual authoring, evidence-linked
raycast placement, speaker-heading capture, exact equipment selection,
validated `.htdtcapture` share/export, and staged untrusted archive import are
implemented software paths.

The implementation baseline is documented in:

- [Detailed implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [iOS host capture workflow](docs/HOST_CAPTURE_WORKFLOW.md)
- [Guided scanning UX plan](docs/GUIDED_SCANNING_UX_PLAN.md)
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
5. HTDT-specific equipment/reference annotations — typed authority, manual authoring, canonical evidence linkage, live raycast placement, speaker-heading capture, and exact equipment-catalog selection implemented; physical repeatability remains open
6. User-attested measurement authority — typed authority + live staged entry/persistence implemented
7. Bundle validation/finalization/export — live quality, atomic finalization, validated share/export, archive validation, and staged untrusted import implemented; real-device end-to-end exercise remains open
8. HTDT ingestion integration — deterministic reference contract, production atomic backend ingestion, RawVisualMesh binding, and explicit semantic promotion implemented
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
- [Manual IPA build](docs/IPA_BUILD.md)
