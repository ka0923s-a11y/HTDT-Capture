# HTDT-Capture Implementation Plan

Status: Draft v1  
Target repository: `bolph71656-ai/HTDT-Capture`  
Primary platform: iPhone / iPadOS with LiDAR  
Primary integration target: HTDT (Home Theater Digital Twin)

## 1. Mission

HTDT-Capture is not a generic 3D-scanner application.

Its purpose is to produce a reproducible, provenance-preserving capture of a real home-theater environment that HTDT can ingest as evidence and convert into its own versioned authorities.

The canonical product of the app is therefore **not a GLB/USDZ model**. The canonical product is a lossless, versioned capture bundle that preserves:

- RoomPlan semantic/parametric output
- ARKit scene-reconstruction mesh evidence
- camera image evidence with synchronized pose and intrinsics
- optional depth/confidence evidence
- user-verified dimensions
- HTDT-specific annotations such as speakers, subwoofers, screen, listening positions, and acoustic treatments
- device/session metadata
- coordinate-system metadata
- checksums and provenance
- explicit separation between measured, inferred, user-declared, and derived values

Derived visualization formats such as USDZ, OBJ, PLY, glTF, or GLB may be exported, but must not replace the canonical evidence bundle.

## 2. Design principles

### 2.1 Evidence first

Raw or minimally processed capture evidence must be retained whenever technically possible.

Processing must be layered:

```text
Physical room
  -> capture evidence
  -> HTDT-Capture bundle
  -> backend ingestion
  -> RawVisualMesh / semantic evidence
  -> SemanticAcousticGeometry
  -> SceneRevision
  -> solver-specific compiled authorities
```

### 2.2 Authority separation

The application must not silently collapse different information sources into one "truth".

Every value that can affect downstream geometry or acoustics should retain an authority class such as:

- `sensor_observation`
- `apple_roomplan_inference`
- `arkit_mesh_reconstruction`
- `user_verified_measurement`
- `user_annotation`
- `backend_derived`

Example:

```text
table diameter:
  RoomPlan estimate: 1.08 m
  user verified:     1.10 m
```

The verified value may be selected for downstream use, but the original estimate must remain preserved.

### 2.3 Deterministic export

Given the same captured evidence and bundle version, serialization should be deterministic where practical:

- stable file naming
- stable IDs
- normalized JSON encoding
- explicit units
- explicit coordinate frames
- cryptographic checksums
- versioned schemas

### 2.4 Revision instead of mutation

A completed capture is immutable.

Corrections, additional measurements, re-scans, and relocalized scans create new capture revisions or linked sessions rather than mutating historical evidence.

### 2.5 Local-first privacy

Room scans and interior photos are sensitive spatial data.

The default architecture should be:

- on-device capture
- local bundle creation
- explicit user-controlled export/upload
- no mandatory cloud processing for core capture
- no silent telemetry containing room imagery or spatial geometry

## 3. Initial scope

### In scope for MVP

- LiDAR capability detection
- RoomPlan scan
- shared/custom ARSession where supported
- ARKit scene-reconstruction mesh collection
- RoomPlan semantic object capture
- captured camera-frame evidence with pose/intrinsics metadata
- explicit annotation workflow for:
  - speakers
  - subwoofers
  - display/screen
  - primary listening position
  - secondary listening positions
- manual dimension verification
- capture quality/completeness review
- immutable `.htdtcapture` bundle generation
- SHA-256 manifest
- local export through iOS share sheet
- bundle validation utility in repository
- schema documentation
- backend ingestion contract documentation

### Deferred from MVP

- automated speaker brand/model recognition
- automated acoustic material recognition as an authority
- automatic acoustic-center inference
- production-grade multi-room scan merging
- cloud account system
- automatic upload to HTDT
- photogrammetric texture reconstruction
- TSDF/fusion pipeline replacing Apple's reconstruction
- scan-to-BIM
- solver execution
- audio impulse-response measurement

These are intentionally deferred to avoid coupling raw capture with high-level interpretation.

## 4. Technical architecture

## 4.1 iOS application layers

Recommended module boundaries:

```text
HTDTCaptureApp
|
+-- AppShell
|   +-- navigation
|   +-- permissions
|   +-- device capability gate
|
+-- CaptureSession
|   +-- shared ARSession ownership
|   +-- session state machine
|   +-- interruption/recovery handling
|
+-- RoomPlanCapture
|   +-- RoomCaptureSession integration
|   +-- CapturedRoom serialization
|   +-- optional CapturedStructure support later
|
+-- MeshCapture
|   +-- ARMeshAnchor tracking
|   +-- vertices/faces/normals
|   +-- classifications
|   +-- anchor transforms
|
+-- EvidenceCapture
|   +-- camera image capture
|   +-- timestamp
|   +-- camera transform
|   +-- intrinsics
|   +-- optional depth/confidence maps
|
+-- Annotation
|   +-- equipment markers
|   +-- reference positions
|   +-- orientation capture
|   +-- manual dimensions
|
+-- CaptureQuality
|   +-- coverage diagnostics
|   +-- missing surfaces
|   +-- tracking quality
|   +-- capture completeness
|
+-- Bundle
|   +-- schema models
|   +-- manifest generation
|   +-- hashing
|   +-- deterministic serialization
|   +-- archive/export
|
+-- Review
    +-- 3D/2D review
    +-- evidence inspection
    +-- verification workflow
```

SwiftUI should own application UI/state presentation.

ARKit/RoomPlan objects should be kept behind narrow adapters rather than spread through views.

## 4.2 Session state machine

Define an explicit capture-session state machine.

Suggested states:

```text
idle
 -> capability_check
 -> permissions
 -> preparing
 -> scanning
 -> paused
 -> reviewing
 -> annotating
 -> validating
 -> finalized
 -> exported
```

Error/interruption substates must preserve whether the session can be resumed or must be restarted.

Important interruptions:

- camera permission denied
- unsupported LiDAR device
- thermal pressure
- memory pressure
- AR tracking degradation
- app interruption
- RoomPlan failure
- low storage
- bundle serialization failure

The state machine should be modeled independently of SwiftUI views.

## 5. Canonical coordinate model

Coordinate ambiguity is a critical failure mode.

The bundle must specify every transform explicitly.

### 5.1 Canonical frame

For MVP:

- right-handed 3D frame
- meters as canonical unit
- world frame defined by the active ARSession at capture start
- transforms stored as 4x4 matrices using a documented matrix layout
- quaternion included where orientation is semantically important
- no implicit axis conversion during capture serialization

### 5.2 Required transform relationships

At minimum preserve:

- AR world -> camera
- AR world -> ARMeshAnchor
- AR world -> RoomPlan objects
- AR world -> HTDT annotations
- image camera pose
- any export-format transform applied later

If a derived GLB/USDZ requires axis conversion, that conversion must be represented as a derived export transform rather than altering canonical evidence.

## 6. Capture bundle v1

Proposed directory structure:

```text
capture-<capture-id>.htdtcapture/
|
+-- manifest.json
+-- checksums.sha256
|
+-- session/
|   +-- session.json
|   +-- device.json
|   +-- capabilities.json
|
+-- roomplan/
|   +-- captured-room.json
|   +-- captured-room.usdz
|   +-- metadata.json
|
+-- mesh/
|   +-- anchors.json
|   +-- geometry/
|       +-- <anchor-id>.bin
|
+-- evidence/
|   +-- frames/
|   |   +-- <frame-id>.heic
|   |   +-- <frame-id>.json
|   +-- depth/
|       +-- <frame-id>.bin
|       +-- <frame-id>.json
|
+-- annotations/
|   +-- entities.json
|   +-- measurements.json
|
+-- quality/
    +-- capture-quality.json
```

The physical archive container format can initially be ZIP with a custom extension.

The logical schema must remain independent of the archive implementation.

## 7. Manifest v1

Minimum manifest fields:

```json
{
  "schema": "htdt.capture.bundle",
  "schema_version": "1.0.0",
  "capture_id": "uuid",
  "revision_id": "uuid",
  "created_at": "RFC3339",
  "app": {
    "name": "HTDT-Capture",
    "version": "semver",
    "build": "string"
  },
  "device_ref": "session/device.json",
  "session_ref": "session/session.json",
  "roomplan_ref": "roomplan/captured-room.json",
  "mesh_ref": "mesh/anchors.json",
  "annotations_ref": "annotations/entities.json",
  "measurements_ref": "annotations/measurements.json",
  "quality_ref": "quality/capture-quality.json",
  "files": []
}
```

Each file entry should include:

- relative path
- byte length
- media/type identifier
- SHA-256
- creation timestamp where relevant
- producing subsystem
- authority class
- optional source relationship

## 8. Annotation model

HTDT-specific annotations must be first-class, not encoded as arbitrary free text.

Initial entity types:

- `speaker`
- `subwoofer`
- `display`
- `projection_screen`
- `listening_position`
- `seat`
- `acoustic_treatment`
- `equipment_rack`
- `reference_point`
- `custom`

Each entity needs:

- stable UUID
- type
- position
- orientation where meaningful
- reference-point semantics
- label
- optional HTDT equipment reference
- evidence links
- user verification status
- provenance

For speakers, position alone is insufficient.

Capture at minimum:

- device location reference point
- front-facing orientation
- up axis
- optional acoustic-center offset
- role/channel label such as L/C/R/SL/SR
- optional exact HTDT EquipmentDefinition reference

## 9. Measurement model

Manual measurements must be modeled as independent authorities.

Minimum fields:

- measurement ID
- measurement type
- scalar/vector value
- unit
- endpoint/reference IDs
- method
- source
- uncertainty if known
- timestamp
- user verification flag

Example methods:

- tape measure
- laser distance meter
- user-entered manufacturer dimension
- LiDAR-derived
- RoomPlan-derived

The schema must allow disagreement between measurements without destructive overwrite.

## 10. Mesh evidence

ARMeshAnchor evidence should preserve source segmentation instead of immediately fusing everything into one mesh.

Per anchor preserve:

- anchor UUID
- anchor transform
- vertex buffer
- vertex stride/format
- face indices
- normals if available
- face classifications if available
- timestamp / last update information where practical

A derived merged mesh may be generated for preview, but the original anchor-level representation remains canonical.

This aligns with HTDT's downstream RawVisualMesh pipeline, where diagnostics and bounded repair should occur after ingestion.

## 11. Camera evidence

MVP evidence capture should support explicit snapshots rather than recording every video frame.

For every evidence image preserve:

- image bytes
- frame ID
- capture timestamp
- camera transform
- camera intrinsics
- image resolution
- orientation
- exposure metadata where practical
- links to nearby annotations/surfaces when explicitly created for that purpose

Later phases may add sampled continuous frame capture if storage/performance permits.

## 12. Capture-quality model

The app should not reduce scan quality to a single opaque score.

Capture quality should be represented by explicit diagnostics such as:

- tracking state history
- RoomPlan completion status
- mesh-anchor count
- observed surface coverage
- unobserved/low-confidence region hints
- number of evidence images
- annotation completeness
- required manual measurements pending
- relocalization status
- thermal/memory interruptions
- bundle integrity validation

A final `ready_for_htdt_ingestion` decision may be derived from explicit rules.

## 13. UX flow

Recommended MVP wizard:

1. **Device check**
   - LiDAR availability
   - supported OS
   - camera permission
   - storage check

2. **Room scan**
   - RoomPlan-guided capture
   - AR mesh collection in same session
   - visible tracking/capture diagnostics

3. **Coverage review**
   - missing wall/ceiling/floor regions
   - unresolved openings
   - prompt to rescan weak areas

4. **Equipment annotation**
   - speaker/subwoofer/screen/MLP placement
   - channel/role assignment
   - orientation confirmation

5. **Precision measurements**
   - optional but strongly encouraged user-verified dimensions
   - known reference lengths
   - screen dimensions
   - critical room dimensions

6. **Evidence photos**
   - guided photos of ambiguous/important areas
   - photo linkage to annotations

7. **Final review**
   - inspect semantic plan
   - inspect mesh
   - inspect annotations
   - inspect measurement conflicts

8. **Finalize**
   - freeze revision
   - generate hashes
   - run bundle validator

9. **Export**
   - Files/share sheet
   - backend upload in a later phase

## 14. HTDT backend ingestion contract

HTDT-Capture should not directly construct HTDT solver authority objects.

Instead, ingestion should expose enough exact evidence for backend adapters.

Proposed conceptual mapping:

```text
HTDT-Capture bundle
  -> CaptureBundleIngestion
  -> source asset/evidence registry
  -> RawVisualMesh
  -> diagnostics / bounded repair
  -> SemanticAcousticGeometry
  -> equipment/reference bindings
  -> SceneRevision
```

Important constraints:

- retain original capture bundle hash
- retain per-file hashes
- retain capture schema version
- retain mapping from derived HTDT entities to source evidence IDs
- preserve authority type for manual/user/inferred values
- do not overwrite original capture evidence after ingestion

## 15. Repository structure

Initial target repository structure:

```text
/
+-- README.md
+-- docs/
|   +-- IMPLEMENTATION_PLAN.md
|   +-- ARCHITECTURE.md
|   +-- CAPTURE_BUNDLE_V1.md
|   +-- HTDT_INGESTION_CONTRACT.md
|   +-- RESEARCH_NOTES.md
|
+-- app/
|   +-- HTDTCapture/
|   +-- HTDTCaptureTests/
|
+-- schemas/
|   +-- capture-bundle-v1/
|
+-- tools/
|   +-- bundle-validator/
|
+-- samples/
|   +-- minimal-capture/
|
+-- .github/
    +-- workflows/
```

The repository should keep design decisions in version control.

Major authority/schema changes should be documented as ADRs under `docs/adr/` once implementation begins.

## 16. Implementation phases

## Phase 0 - Foundation and contracts

Deliverables:

- repository bootstrap
- implementation plan
- architecture document
- capture bundle v1 draft schema
- coding conventions
- CI skeleton
- ADR template
- issue decomposition

Exit criteria:

- canonical bundle concept is documented
- coordinate conventions are explicit
- authority/provenance classes are explicit
- no ambiguity remains about what constitutes source evidence vs derived output

## Phase 1 - Device and AR session foundation

Deliverables:

- SwiftUI app shell
- capability detection
- camera permission flow
- shared ARSession owner
- explicit session state machine
- interruption handling
- diagnostic UI

Exit criteria:

- supported LiDAR device can start/stop a stable AR session
- unsupported device receives a deterministic unsupported state
- session state survives ordinary SwiftUI navigation changes

## Phase 2 - RoomPlan + raw mesh capture

Deliverables:

- RoomPlan integration
- custom/shared ARSession integration
- ARMeshAnchor collection
- anchor serialization
- RoomPlan serialization
- local capture working directory

Exit criteria:

- one scan produces both RoomPlan and ARMesh evidence in one common AR world frame
- raw anchor transforms and geometry survive serialize/deserialize round-trip
- RoomPlan result is retained independently of mesh evidence

## Phase 3 - Evidence photos and provenance

Deliverables:

- evidence photo capture
- pose/intrinsics metadata
- evidence indexing
- per-file hashing
- device/session metadata
- immutable capture revision ID

Exit criteria:

- every saved image can be reconstructed in the AR world frame from stored metadata
- bundle validator detects missing or modified evidence files

## Phase 4 - HTDT annotation workflow

Deliverables:

- entity annotation UI
- orientation capture
- speaker role/channel assignment
- listening position support
- manual measurement authority
- evidence linkage

Exit criteria:

- user can represent at least a 3.x.x / 5.x.x theater layout without free-text geometry hacks
- verified dimensions remain distinct from inferred dimensions
- annotations serialize deterministically

## Phase 5 - Review, quality, and bundle finalization

Deliverables:

- capture review UI
- explicit quality diagnostics
- completeness gate
- bundle exporter
- local validator
- sample bundles

Exit criteria:

- finalization creates an immutable `.htdtcapture`
- all files validate against checksums
- manifest references are resolvable
- incomplete captures show concrete diagnostics rather than an opaque failure

## Phase 6 - HTDT integration

Deliverables:

- versioned ingestion contract
- backend-side fixture bundle
- exact mapping documentation
- compatibility tests against HTDT ingestion implementation

Exit criteria:

- HTDT can ingest a frozen sample bundle
- derived RawVisualMesh retains lineage to source bundle and anchor evidence
- semantic/manual authorities retain provenance
- re-ingestion is deterministic for the same bundle

## Phase 7 - Advanced capture

Candidates:

- multi-room / CapturedStructure
- ARWorldMap relocalization
- capture resume across sessions
- scan-diff/revision comparison
- improved coverage heatmaps
- depth/confidence preservation
- photo-to-surface association
- acoustic-treatment-specific capture workflow
- optional calibration/reference targets
- external laser/tape measurement integration

These should not block MVP.

## 17. Testing strategy

Tests should exist where they validate non-trivial contracts.

Priority tests:

- manifest/schema encode-decode round trip
- stable IDs / deterministic serialization
- coordinate-transform conversion
- mesh binary serialization
- checksum generation/verification
- annotation schema round trip
- bundle validation
- capture state machine transitions

Avoid redundant UI snapshot tests for reversible low-impact presentation changes.

Physical-device verification is required for:

- RoomPlan
- LiDAR scene reconstruction
- ARSession sharing
- tracking/relocalization
- thermal and performance behavior

Where possible, preserve anonymized fixture data so non-device tests can run in CI.

## 18. CI

Initial CI should eventually run:

- Swift build
- unit tests that do not require LiDAR hardware
- schema validation
- bundle validator tests
- fixture integrity checks

Hardware-dependent behavior cannot be treated as validated by simulator CI.

## 19. Primary technical risks

### Risk: RoomPlan and raw AR mesh do not remain perfectly aligned

Mitigation:

- one explicit ARSession owner
- preserve all transforms unchanged
- generate alignment diagnostics
- test with reference geometry

### Risk: consumer LiDAR geometry is not sufficiently precise for critical dimensions

Mitigation:

- treat LiDAR as evidence, not unquestionable authority
- support user-verified dimensions
- later support external reference measurements
- preserve uncertainty/source metadata

### Risk: bundle size becomes excessive

Mitigation:

- explicit snapshot capture for MVP
- binary geometry representation
- separate source evidence from derived preview
- compression at archive layer without lossy source modification

### Risk: Apple's APIs evolve

Mitigation:

- adapter boundaries around RoomPlan/ARKit
- versioned capture schema
- avoid exposing Apple-specific object graphs directly as HTDT backend contracts
- retain exported Apple artifacts as evidence but normalize metadata into HTDT-Capture schema

### Risk: accidental semantic overreach

Mitigation:

- no automatic material/equipment identification becomes authoritative without explicit evidence
- keep inference and verification states separate
- do not derive acoustic properties in the capture app

## 20. PoC acceptance criteria

The first physical-device PoC is successful when one supported LiDAR iPhone can:

1. start a shared AR/RoomPlan capture session;
2. capture a room through RoomPlan;
3. retain ARMeshAnchor geometry from the same world frame;
4. take at least one evidence image with camera pose and intrinsics;
5. create at least one speaker annotation with orientation;
6. record one user-verified measurement;
7. finalize an immutable local capture revision;
8. export a `.htdtcapture` archive;
9. pass the repository's bundle validator;
10. prove that all canonical source artifacts are still present after reopening the archive.

The PoC does **not** need to produce final acoustic geometry.

## 21. Immediate next work

After this plan is accepted as the repository baseline, implementation should proceed in this order:

1. bootstrap README and repository conventions;
2. define Capture Bundle v1 schemas before writing sensor-specific serialization;
3. create SwiftUI application shell and ARSession state machine;
4. implement RoomPlan + ARMesh dual capture;
5. add evidence photo capture;
6. add annotations and verified measurements;
7. add validator/finalization;
8. establish frozen sample bundle;
9. connect to HTDT ingestion.

This ordering intentionally establishes the data contract before large volumes of capture code are written.

## 22. Research baseline

Implementation should cross-check current behavior against primary sources before each Apple-framework-specific slice, especially:

- Apple RoomPlan documentation
- Apple ARKit scene reconstruction documentation
- Apple's RoomPlan WWDC sessions covering custom ARSession, continuous scanning, relocalization, and CapturedStructure
- relevant Apple sample code

Reference OSS can be used to learn implementation patterns, but HTDT-Capture should avoid making a third-party scanner framework part of the canonical evidence path unless its license, maintenance status, serialization semantics, and data-loss behavior have been explicitly reviewed.

The principal architectural choice is therefore:

**Use Apple capture frameworks directly, preserve their outputs plus raw evidence, and keep HTDT's provenance/revision semantics in our own versioned schema.**
