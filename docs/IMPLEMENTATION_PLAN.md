# HTDT-Capture Implementation Plan

Status: Reviewed v2  
Review date: 2026-09-20  
Target repository: `bolph71656-ai/HTDT-Capture`  
Primary platform: LiDAR-capable iPhone / iPad  
Primary integration target: HTDT (Home Theater Digital Twin)

## 1. Mission

HTDT-Capture is not a generic 3D-scanner application.

Its purpose is to produce a reproducible, provenance-preserving capture of a real home-theater environment that HTDT can ingest as evidence and convert into its own immutable/versioned authorities.

The canonical product is therefore **not a GLB/USDZ model**. It is an evidence-preserving, versioned capture bundle that retains the highest-fidelity artifacts available through supported Apple APIs plus HTDT-specific annotations and provenance.

"Evidence-preserving" is intentionally used instead of "lossless physical-room capture". RoomPlan and ARKit already produce processed reconstructions, and encoded image exports may be transformed from the camera pixel buffer. HTDT-Capture must never claim to retain inaccessible raw LiDAR sensor samples unless it actually does so.

The bundle should preserve, where supported:

- RoomPlan `CapturedRoomData` raw scan result for later reprocessing;
- post-processed `CapturedRoom` / later `CapturedStructure` outputs;
- ARKit scene-reconstruction mesh snapshots;
- selected camera-frame evidence with exact pose/intrinsics metadata;
- selected `sceneDepth` and confidence maps;
- user-attested dimensions;
- HTDT-specific annotations such as speakers, subwoofers, screen, listening positions, and acoustic treatments;
- device/session/framework metadata;
- explicit coordinate and time models;
- cryptographic integrity metadata;
- separation between observed, inferred, user-attested, imported, and derived values.

Derived visualization formats such as USD/USDZ, OBJ, PLY, glTF, or GLB may be exported, but must not replace canonical capture evidence.

## 2. Non-negotiable design principles

### 2.1 Evidence before interpretation

Processing remains layered:

~~~text
Physical room
  -> Apple capture APIs + explicit user input
  -> immutable HTDT-Capture revision
  -> HTDT ingestion
  -> source evidence registry
  -> RawVisualMesh / semantic evidence
  -> SemanticAcousticGeometry
  -> SceneRevision
  -> solver-specific compiled authorities
~~~

Capture code must not silently "repair" or simplify canonical mesh evidence.

### 2.2 Authority and provenance separation

Different information sources must remain independently identifiable.

Initial provenance classes:

- `arkit_frame_observation`
- `arkit_scene_depth_observation`
- `arkit_mesh_reconstruction`
- `apple_roomplan_raw_scan`
- `apple_roomplan_inference`
- `user_attested_measurement`
- `user_annotation`
- `imported_reference`
- `capture_app_derived`
- `backend_derived`

A provenance class does not by itself imply numerical superiority.

Example:

~~~text
table diameter
  apple_roomplan_inference: 1.08 m
  user_attested_measurement:
    value: 1.10 m
    method: tape_measure
    uncertainty: unknown
~~~

The backend may choose an authority according to an explicit policy, but the capture bundle must preserve disagreement.

### 2.3 Immutable finalization and revision lineage

A finalized capture revision is immutable.

Use distinct IDs for distinct concepts:

- `capture_series_id`: logical lineage of captures/revisions for one room project;
- `capture_revision_id`: immutable finalized bundle revision;
- `capture_session_id`: one active sensor-capture session;
- `coordinate_space_id`: one AR world coordinate frame;
- `parent_revision_id`: previous finalized revision when applicable.

A re-scan performed in a new ARSession creates a **new coordinate space** unless an explicit alignment authority is produced. It must never be assumed to share coordinates with an earlier session.

MVP supports one primary AR coordinate space per sensor-capture session. Cross-session alignment is deferred.

### 2.4 Deterministic logical serialization

"Deterministic" means that reserializing the same logical capture revision with the same schema and already-assigned IDs produces the same canonical metadata bytes and payload digests.

It does **not** mean that independent scans receive the same IDs.

Requirements:

- stable IDs after creation;
- canonical JSON encoding;
- explicit numeric units and scalar widths;
- explicit byte order for binary payloads;
- stable file ordering;
- no locale-dependent number/date serialization;
- deterministic integrity calculation.

ZIP byte-for-byte reproducibility is not required for MVP because archive metadata/compression implementations may vary. Integrity is defined over logical bundle content, not ZIP wrapper bytes.

### 2.5 Local-first privacy

Room geometry and interior imagery are sensitive.

Default behavior:

- capture into the app-private container;
- no mandatory cloud dependency;
- no automatic upload;
- explicit export/share action;
- no telemetry containing imagery, geometry, measurements, or annotation coordinates;
- transient capture data is deletable;
- finalized captures are deletable;
- working data should not be implicitly synchronized to cloud backup unless explicitly designed and disclosed.

### 2.6 Capability-gated behavior

Never infer support from a marketing device name.

Runtime gates must use framework capabilities such as:

- RoomPlan support;
- AR world-tracking support;
- scene-reconstruction support;
- scene-depth frame semantic support;
- high-resolution frame capture support where used.

The exact deployment target and SDK baseline are a Phase 0 decision, recorded in an ADR after API compatibility review.

## 3. Platform facts verified before implementation

The implementation plan relies on these current Apple platform behaviors:

- RoomPlan can be created with an app-owned `ARSession`, and RoomPlan preserves the session settings.
- `CapturedRoomData` is a Codable opaque raw RoomPlan scan result that can be stored and processed later by `RoomBuilder`.
- `CapturedRoom` is post-processed and separately Codable/exportable.
- ARKit world space is right-handed.
- `ARCamera.transform` represents camera pose in world space.
- `ARAnchor.transform` represents anchor pose relative to AR world space.
- scene reconstruction must be capability-checked.
- `sceneDepth` and its confidence map are capability-gated and are associated with the captured image for that AR frame.
- `ARFrame` provides captured image, frame timestamp, camera transform, camera intrinsics, image resolution, and EXIF metadata.

These facts must be rechecked against the SDK used for each implementation slice rather than copied indefinitely as assumptions.

## 4. MVP scope

### In scope

- runtime capability matrix;
- RoomPlan scan using an explicit app-owned ARSession;
- preservation of `CapturedRoomData`;
- preservation of post-processed `CapturedRoom`;
- ARKit scene-reconstruction mesh collection;
- selected AR camera-frame evidence;
- selected scene-depth/confidence evidence when supported;
- explicit annotation workflow for:
  - speakers;
  - subwoofers;
  - display / projection screen;
  - primary listening position;
  - secondary listening positions;
- user-attested dimensions and measurement metadata;
- capture quality/completeness diagnostics;
- immutable `.htdtcapture` logical bundle;
- manifest-based integrity;
- local validation and export;
- accuracy/calibration benchmark harness and protocol;
- backend ingestion contract documentation.

### Deferred

- automatic equipment manufacturer/model recognition as authority;
- automatic acoustic-material recognition as authority;
- automatic acoustic-center inference as authority;
- cross-session spatial alignment;
- production multi-room merging;
- cloud accounts;
- automatic backend upload;
- photogrammetric texture reconstruction;
- custom TSDF/fusion replacing Apple's reconstruction;
- scan-to-BIM;
- acoustic solver execution;
- impulse-response measurement.

## 5. iOS architecture

Recommended module boundaries:

~~~text
HTDTCaptureApp
|
+-- AppShell
|   +-- navigation
|   +-- permissions
|   +-- capability presentation
|
+-- PlatformCapabilities
|   +-- RoomPlan support
|   +-- world tracking support
|   +-- scene reconstruction support
|   +-- scene depth support
|   +-- capture-format capabilities
|
+-- CaptureSession
|   +-- app-owned ARSession
|   +-- session state machine
|   +-- interruption/recovery handling
|   +-- coordinate-space identity
|   +-- monotonic time correlation
|
+-- RoomPlanCapture
|   +-- RoomCaptureSession / RoomCaptureView adapter
|   +-- CapturedRoomData preservation
|   +-- RoomBuilder post-processing
|   +-- CapturedRoom preservation
|
+-- MeshCapture
|   +-- ARMeshAnchor lifecycle
|   +-- final active-anchor snapshot
|   +-- canonical geometry serialization
|
+-- EvidenceCapture
|   +-- selected ARFrame snapshot
|   +-- pixel-buffer preservation/encoding
|   +-- pose/intrinsics
|   +-- sceneDepth/confidence
|   +-- EXIF/format metadata
|
+-- Annotation
|   +-- equipment/reference entities
|   +-- orientation
|   +-- measurement records
|   +-- evidence links
|
+-- CaptureQuality
|   +-- tracking diagnostics
|   +-- coverage/completeness
|   +-- resource/thermal events
|   +-- accuracy benchmark hooks
|
+-- CaptureStore
|   +-- bounded asynchronous writes
|   +-- atomic artifact commits
|   +-- streamed hashing
|   +-- revision finalization
|
+-- Bundle
|   +-- schema models
|   +-- canonical JSON
|   +-- integrity manifest
|   +-- archive/export adapter
|
+-- Review
    +-- 3D/2D review
    +-- conflict review
    +-- finalization gate
~~~

### 5.1 Concurrency rule

ARSession delegate callbacks must not perform expensive serialization, image encoding, or hashing inline.

Sensor buffers that need persistence must be copied or retained according to documented lifetime guarantees, then handed to a bounded writer actor/serial queue.

The writer must provide backpressure and explicit failure when storage cannot keep up. Silent frame/evidence loss is unacceptable.

## 6. Session state machine

Suggested states:

~~~text
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
~~~

Orthogonal status dimensions should track:

- tracking quality;
- RoomPlan status;
- storage pressure;
- memory pressure;
- thermal state;
- interruption state;
- persistence backlog;
- recoverability.

Important failure events:

- camera permission denied;
- RoomPlan unsupported;
- scene reconstruction unsupported;
- requested scene depth unsupported;
- AR tracking limited/not available;
- RoomPlan failure;
- session interruption;
- thermal pressure;
- memory warning;
- insufficient free storage;
- persistence backlog overflow;
- serialization/hash failure.

The state machine belongs to the domain layer, not SwiftUI view state.

## 7. Coordinate contract

Coordinate ambiguity is a release-blocking defect.

### 7.1 Canonical convention

For the MVP canonical AR coordinate space:

- right-handed;
- meters;
- homogeneous 4x4 transforms;
- storage order explicitly documented as 16 IEEE-754 binary32 values in column-major SIMD semantic order;
- transform names use `T_<destination>_from_<source>`;
- no ambiguous arrow notation in schemas or code.

Examples:

- `T_world_from_camera`
- `T_world_from_mesh_anchor`
- `T_world_from_annotation`

Apple values are stored with their original semantic meaning.

### 7.2 Camera basis and image orientation

The camera transform is independent from UI orientation.

For every saved camera frame preserve:

- AR camera transform;
- intrinsics;
- native captured-image dimensions;
- pixel format;
- source orientation semantics;
- any display transform used only for UI preview.

A portrait preview transformation must never be baked into canonical camera extrinsics.

### 7.3 Cross-format conversions

USD/glTF/GLB/OBJ conversions are derived exports.

Every derived export must record:

- source coordinate space;
- destination coordinate convention;
- exact conversion transform;
- units conversion if any;
- export tool/version.

## 8. Time contract

Two time domains are required.

### 8.1 Session monotonic time

Use AR frame/session timestamps for synchronization inside a capture session.

Store:

- `session_timestamp_s`;
- source clock identifier/description;
- capture-session ID.

### 8.2 Wall-clock time

Store UTC wall-clock timestamps only for audit/user chronology.

At session start and end, record a correlation sample between:

- monotonic process/session time;
- UTC wall clock.

Do not treat an AR frame timestamp as an RFC3339 wall-clock time.

## 9. Canonical Capture Bundle v1

Proposed logical structure:

~~~text
capture-<capture-revision-id>.htdtcapture/
|
+-- manifest.json
|
+-- session/
|   +-- capture-session.json
|   +-- device.json
|   +-- capabilities.json
|   +-- timing.json
|
+-- roomplan/
|   +-- captured-room-data.json
|   +-- captured-room.json
|   +-- captured-room-metadata.json
|   +-- exports/
|       +-- roomplan-mesh.usd[z]
|
+-- mesh/
|   +-- anchors.json
|   +-- geometry/
|       +-- <anchor-id>.meshbin
|
+-- evidence/
|   +-- frames/
|   |   +-- <frame-id>.frame.json
|   |   +-- <frame-id>.pixelbin
|   |   +-- <frame-id>.preview.heic
|   +-- depth/
|       +-- <frame-id>.depthbin
|       +-- <frame-id>.confidencebin
|       +-- <frame-id>.depth.json
|
+-- annotations/
|   +-- entities.json
|   +-- measurements.json
|
+-- quality/
    +-- capture-quality.json
    +-- benchmark-observations.json
~~~

Notes:

- `captured-room-data.json` is canonical RoomPlan raw scan output.
- `captured-room.json` is a post-processed derivative that remains valuable and independently versioned.
- USD/USDZ under `roomplan/exports/` is derived.
- `preview.heic` is a convenience derivative unless the implementation proves bit-preserving source semantics.
- `pixelbin` is intended to preserve selected ARFrame pixel-plane bytes plus enough layout metadata to reconstruct the pixel buffer representation. Phase 0 must define the exact binary format before implementation.
- ZIP with a custom extension may wrap the logical directory, but archive bytes are not themselves the integrity authority.

## 10. Manifest and integrity model

Avoid circular hashing.

`manifest.json` is the canonical integrity root document and contains:

- schema name/version;
- capture-series ID;
- capture-revision ID;
- parent revision ID;
- capture-session IDs;
- coordinate-space IDs;
- creation/finalization time;
- app version/build;
- OS/framework/device metadata references;
- every canonical payload path;
- byte length;
- media/type identifier;
- SHA-256 digest;
- provenance class;
- optional source relationship;
- canonical/derived role.

The manifest does **not** include its own hash.

Define:

~~~text
bundle_digest = SHA256(canonical_bytes(manifest.json))
~~~

Because each canonical payload digest is inside the manifest, the bundle digest commits to the logical bundle contents without recursion.

A human-readable `checksums.sha256` may be generated as a convenience derivative, but it is not the root authority.

Phase 0 must select and test a canonical JSON encoding strategy, with fixed test vectors.

## 11. RoomPlan evidence model

Preserve two different layers.

### 11.1 Raw RoomPlan scan

Persist encoded `CapturedRoomData` immediately after RoomPlan session completion.

Record:

- producing OS version/build;
- app version/build;
- RoomPlan-relevant configuration;
- capture-session ID;
- coordinate-space ID;
- serialization format/version;
- SHA-256.

This is the preferred artifact for future reprocessing.

### 11.2 Post-processed room

Generate/preserve `CapturedRoom` separately.

Record:

- input `CapturedRoomData` hash;
- RoomBuilder configuration/options if exposed;
- producing OS/framework context;
- `CapturedRoom.version`;
- serialization hash.

Do not overwrite the raw RoomPlan scan when users correct semantic labels or dimensions. Corrections become HTDT annotations/measurements or a new capture revision.

## 12. Mesh evidence model

The ARKit mesh is a reconstructed estimate, not raw LiDAR samples.

For each active ARMeshAnchor at finalization preserve:

- anchor UUID;
- capture-session ID;
- coordinate-space ID;
- `T_world_from_mesh_anchor`;
- observation/update session timestamp;
- vertex count;
- canonical float32 vertex positions;
- canonical float32 normals where available;
- face count;
- canonical face indices with explicit integer width;
- face classification bytes where available;
- source descriptors needed to interpret copied values;
- serialization format version.

Prefer a canonical portable representation over dumping implementation-specific MTLBuffer padding.

An optional mesh-anchor update journal may be added later. MVP canonical state is the finalized active-anchor snapshot plus capture diagnostics.

A merged mesh is derived only.

## 13. Camera-frame evidence

### 13.1 Selected snapshots

MVP records explicit evidence snapshots rather than every video frame.

For each frame:

- frame UUID;
- capture-session ID;
- coordinate-space ID;
- `session_timestamp_s`;
- UTC correlation-derived capture time when useful;
- `T_world_from_camera`;
- 3x3 intrinsics;
- native image resolution;
- pixel format;
- plane count;
- plane dimensions/row strides;
- raw selected pixel-plane payload reference;
- EXIF metadata after privacy review;
- optional preview encoding reference.

If high-resolution AR frame capture is adopted, its output must be treated as a distinct frame with its own intrinsics/resolution rather than substituted into a normal-frame record.

### 13.2 Depth

When `sceneDepth` is supported and enabled, a selected evidence frame should preserve:

- depth map float format and dimensions;
- confidence map format and dimensions;
- frame association;
- camera intrinsics and transform from the associated ARFrame;
- whether depth is discrete `sceneDepth` or temporally averaged `smoothedSceneDepth`.

Prefer discrete `sceneDepth` for canonical evidence. Smoothed depth may be stored as an additional derived/processed observation.

## 14. Annotation model

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

Each entity requires:

- stable UUID;
- entity type;
- coordinate-space ID;
- position/transform;
- orientation when meaningful;
- reference-point semantics;
- label;
- optional exact HTDT equipment reference;
- evidence links;
- creation/revision metadata;
- provenance class;
- verification state.

### 14.1 Speaker-specific requirements

Position alone is insufficient.

Capture:

- reference point used for placement;
- front-axis convention;
- up-axis convention;
- channel/role;
- optional acoustic-center offset;
- optional HTDT `EquipmentDefinition` reference;
- orientation capture method;
- supporting images/measurements.

The app must not pretend that a visual cabinet center is the acoustic center unless an explicit authority supplies that relationship.

## 15. Measurement model

Replace ambiguous "verified measurement" semantics with **user-attested measurement authority**.

Minimum fields:

- measurement ID;
- measured quantity type;
- scalar/vector value;
- SI unit;
- endpoint/reference IDs;
- coordinate-space ID if spatial;
- acquisition method;
- instrument class;
- instrument make/model if provided;
- calibration status/date if provided;
- stated uncertainty/tolerance if known;
- observation timestamp;
- user-attestation state;
- provenance;
- evidence links.

Methods may include:

- tape measure;
- laser distance meter;
- manufacturer specification;
- LiDAR-derived;
- RoomPlan-derived;
- other.

User attestation means "the user confirms this record represents the measurement they entered/observed"; it does not imply metrological certification.

Conflicting measurements remain separate records.

## 16. Capture quality model

Do not compress capture quality into a single opaque score.

Record explicit diagnostics:

- AR tracking state history;
- RoomPlan completion/errors/instructions;
- active mesh-anchor count;
- mesh update statistics;
- observed surface coverage estimates;
- weak/unobserved region hints;
- evidence frame count;
- depth availability;
- annotation completeness;
- required measurement completeness;
- resource/thermal interruptions;
- storage backlog/failures;
- session interruptions;
- bundle integrity result;
- accuracy benchmark references where applicable.

A `ready_for_htdt_ingestion` result can be derived only from versioned explicit rules.

## 17. Capture protocol and UX

Recommended MVP workflow:

1. **Capability / privacy check**
   - framework support;
   - permissions;
   - available storage;
   - local-data notice.

2. **Scan preparation**
   - remove/limit moving people;
   - identify reflective/transparent/problem areas;
   - coach user on range and overlap;
   - encourage a closed-loop scan path where practical.

3. **Room scan**
   - RoomPlan coaching enabled where useful;
   - AR mesh collection;
   - live tracking/resource diagnostics.

4. **Coverage review**
   - unresolved walls/openings;
   - weak geometry regions;
   - explicit re-scan prompts.

5. **Equipment annotation**
   - speaker/subwoofer/screen/MLP;
   - role;
   - orientation;
   - reference-point semantics.

6. **Precision measurements**
   - room reference dimensions;
   - screen dimensions;
   - speaker/reference distances when important;
   - method/instrument metadata.

7. **Evidence snapshots**
   - ambiguous/important surfaces;
   - each major equipment item;
   - reference measurement endpoints;
   - depth/confidence retained when supported.

8. **Conflict review**
   - RoomPlan vs user-attested dimensions;
   - missing orientation;
   - unattached evidence.

9. **Finalize**
   - freeze IDs;
   - canonicalize metadata;
   - hash payloads;
   - write manifest;
   - validate;
   - atomically mark revision finalized.

10. **Export**
    - user-controlled share/files flow;
    - backend upload is later work.

## 18. Storage and resource policy

Raw evidence can be large.

Requirements:

- preflight free-space check;
- configurable minimum free-space reserve;
- bounded in-memory queues;
- streamed file writes;
- streamed SHA-256 hashing;
- atomic temp-file -> final-file commit;
- explicit incomplete-artifact cleanup;
- no unbounded continuous camera recording in MVP;
- selected evidence snapshot count/size visible to the user;
- capture must fail closed if a requested canonical artifact cannot be persisted.

## 19. HTDT backend ingestion contract

HTDT-Capture does not create solver-specific authority objects.

Conceptual mapping:

~~~text
HTDT-Capture revision
  -> CaptureBundleIngestion
  -> source evidence registry
  -> RoomPlan raw/postprocessed evidence
  -> ARKit reconstructed mesh evidence
  -> RawVisualMesh
  -> diagnostics / bounded repair
  -> SemanticAcousticGeometry
  -> equipment/reference bindings
  -> SceneRevision
~~~

Backend requirements:

- retain bundle digest;
- retain manifest schema version;
- retain per-file hashes;
- retain source capture/revision/session/coordinate IDs;
- preserve source-to-derived lineage;
- never treat a convenience GLB/USDZ export as canonical truth when source evidence is available;
- distinguish Apple inference, ARKit reconstruction, user attestation, and backend derivation;
- same finalized bundle + same ingestion software version must produce deterministic identity/lineage results where specified.

## 20. Accuracy and calibration program

Consumer LiDAR accuracy must be measured for the actual HTDT workflow.

Published studies report results varying from centimeter-level measurements under some conditions to errors on the order of 10 cm in others, with software and trajectory/drift handling materially affecting results. Therefore HTDT-Capture must not advertise a fixed spatial accuracy based only on hardware.

### 20.1 Benchmark fixtures

Create at least:

- small-room geometric fixture with independently measured wall/reference distances;
- known planar surfaces;
- known speaker/reference marker positions;
- closed-loop scan route;
- repeat scans by the same operator;
- repeat scans by different operators if practical.

Reference measurements should use a more trustworthy method, such as calibrated laser distance measurement or an independently surveyed model.

### 20.2 Metrics

Measure:

- absolute dimension error;
- signed bias;
- RMSE;
- repeatability across captures;
- plane residual;
- RoomPlan vs mesh alignment;
- loop-closure/drift error;
- annotation placement repeatability;
- orientation error for speakers;
- depth error by range/confidence bucket.

### 20.3 Promotion gate

Do not set marketing accuracy claims before benchmark evidence exists.

Phase 0/PoC must define provisional engineering thresholds, then Phase 2 physical-device testing must either demonstrate them or explicitly revise them with recorded rationale.

Critical downstream dimensions can require user-attested measurement even when scan geometry passes general capture quality.

## 21. Repository structure

~~~text
/
+-- README.md
+-- docs/
|   +-- IMPLEMENTATION_PLAN.md
|   +-- PLAN_REVIEW_2026-09-20.md
|   +-- ARCHITECTURE.md
|   +-- CAPTURE_BUNDLE_V1.md
|   +-- COORDINATE_AND_TIME_CONTRACT.md
|   +-- ACCURACY_VALIDATION_PROTOCOL.md
|   +-- HTDT_INGESTION_CONTRACT.md
|   +-- RESEARCH_NOTES.md
|   +-- adr/
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
|   +-- benchmark-fixtures/
|
+-- .github/
    +-- workflows/
~~~

Major authority/schema decisions require ADRs.

## 22. Implementation phases

### Phase 0 - Contracts and foundation

Deliverables:

- reviewed implementation plan;
- deployment-target/API-baseline ADR;
- architecture document;
- Capture Bundle v1 schema;
- coordinate/time contract;
- provenance vocabulary;
- integrity/canonical JSON contract;
- RoomPlan raw/postprocessed distinction;
- mesh binary format;
- evidence-frame binary format;
- accuracy validation protocol;
- validator skeleton;
- minimal synthetic fixture;
- CI skeleton.

Exit criteria:

- no ambiguous transform direction;
- no ambiguous timestamp domain;
- no circular integrity definition;
- raw `CapturedRoomData` has a canonical location;
- canonical vs derived files are explicit;
- re-scan/new-coordinate-space behavior is explicit;
- schema test vectors exist.

### Phase 1 - App shell and AR session foundation

Deliverables:

- SwiftUI shell;
- capability matrix;
- permission flow;
- app-owned ARSession;
- state machine;
- interruption/resource monitoring;
- capture working directory;
- bounded CaptureStore.

Exit criteria:

- support is decided by runtime capability APIs;
- state is independent of transient views;
- storage/resource failure paths are explicit;
- one session receives stable capture-session and coordinate-space IDs.

### Phase 2 - RoomPlan + mesh dual capture

Deliverables:

- RoomPlan integration with app-owned ARSession;
- raw `CapturedRoomData` persistence;
- `CapturedRoom` generation/persistence;
- ARMeshAnchor lifecycle capture;
- canonical mesh serialization;
- physical-device alignment benchmark.

Exit criteria:

- RoomPlan and AR mesh belong to the same declared coordinate space;
- raw RoomPlan scan survives reopen/reprocessing;
- mesh geometry/transform round trips;
- benchmark report is produced rather than relying on visual inspection.

### Phase 3 - Camera + depth evidence

Deliverables:

- selected ARFrame evidence;
- raw pixel-plane serialization;
- pose/intrinsics/native orientation metadata;
- EXIF allowlist;
- sceneDepth/confidence persistence when supported;
- optional preview HEIC;
- per-payload hashes.

Exit criteria:

- canonical frame payload is reconstructable according to its recorded layout;
- stored camera pose/intrinsics correspond to the same frame record;
- depth/confidence is linked to the correct frame;
- validator catches modified/missing payloads.

### Phase 4 - HTDT annotations and measurements

Deliverables:

- entity annotation UI;
- orientation capture;
- speaker role/channel;
- listening positions;
- user-attested measurement records;
- instrument/uncertainty metadata;
- evidence linkage.

Exit criteria:

- 3.x.x / 5.x.x room topology can be represented without free-text geometry hacks;
- speaker orientation/reference semantics are explicit;
- conflicting measurements coexist;
- no inferred value is overwritten by attestation.

### Phase 5 - Review, quality, finalization, export

Deliverables:

- semantic/mesh/evidence review;
- explicit quality diagnostics;
- conflict review;
- finalization transaction;
- canonical manifest;
- bundle digest;
- local validator;
- export wrapper;
- frozen sample bundle.

Exit criteria:

- finalization is atomic;
- finalized revision is immutable;
- manifest validates all canonical payloads;
- incomplete captures report concrete diagnostics;
- logical bundle survives archive/unarchive without digest change.

### Phase 6 - HTDT integration

Deliverables:

- versioned ingestion contract;
- frozen integration fixture;
- source lineage mapping;
- RawVisualMesh adapter;
- compatibility verification.

Exit criteria:

- original bundle digest and payload hashes remain traceable;
- RawVisualMesh lineage points to exact mesh source evidence;
- RoomPlan/user/ARKit authorities remain distinct;
- re-ingestion with the same versions is deterministic where contractually required.

### Phase 7 - Advanced capture

Candidates:

- CapturedStructure/multi-room workflow;
- ARWorldMap or equivalent relocalization research;
- cross-session alignment authority;
- scan-diff/revision comparison;
- improved coverage heatmaps;
- sampled continuous evidence capture;
- calibration targets/fiducials;
- external measurement-device integration;
- treatment-specific workflow.

## 23. Testing strategy

Write tests for non-trivial contracts, not reversible presentation changes.

Priority tests:

- canonical JSON test vectors;
- manifest digest calculation;
- schema encode/decode;
- transform convention and inverse tests;
- timestamp-domain serialization;
- RoomPlan encoded artifact fixture decode when platform-testable;
- mesh binary round trip;
- frame/depth binary round trip;
- annotation/measurement round trip;
- state-machine transitions;
- failure-closed finalization;
- bundle validation;
- mutation/tamper detection.

Physical-device validation is required for:

- RoomPlan;
- scene reconstruction;
- scene depth;
- shared/app-owned ARSession;
- camera evidence synchronization;
- tracking/interruption behavior;
- benchmark accuracy/repeatability;
- thermal/storage behavior.

Simulator CI must not be reported as validation of hardware capture behavior.

## 24. CI strategy

CI should run only meaningful checks for the current slice:

- build supported non-hardware targets;
- unit tests for contracts/state;
- schema validation;
- validator tests;
- fixture integrity;
- deterministic canonicalization test vectors.

Do not repeatedly broaden/re-run successful checks without a change that justifies it.

## 25. Primary technical risks

### Cross-modal coordinate error
Mitigation: explicit transform semantics, one ARSession owner, physical reference benchmark.

### Drift / large-room error
Mitigation: capture protocol, closed-loop guidance, benchmark drift metrics, future cross-session alignment authority.

### Consumer LiDAR insufficient for critical dimensions
Mitigation: user-attested/reference measurements, uncertainty metadata, no fixed accuracy claim without evidence.

### Raw evidence storage pressure
Mitigation: selected frames, binary payloads, streamed writes/hashing, free-space gate.

### Buffer lifetime/concurrency bugs
Mitigation: copy/retain data before asynchronous persistence as required; bounded writer; no heavy delegate work.

### Apple API evolution
Mitigation: adapters, raw RoomPlan artifact preservation, OS/framework provenance, versioned schemas.

### Semantic overreach
Mitigation: inference and attestation separated; capture app does not invent acoustic properties.

### Privacy leakage
Mitigation: app-private local capture, explicit export, metadata allowlist, no spatial telemetry.

## 26. First vertical PoC acceptance criteria

The PoC is successful only when one supported LiDAR iPhone can:

1. pass runtime capability checks;
2. start an app-owned ARSession used by RoomPlan and mesh capture;
3. capture and persist `CapturedRoomData`;
4. regenerate/persist `CapturedRoom` from that raw RoomPlan result;
5. persist final ARMeshAnchor geometry in the same declared coordinate space;
6. capture one evidence ARFrame with pose/intrinsics/native image metadata;
7. persist scene depth + confidence for that frame when supported;
8. create one speaker annotation with explicit orientation;
9. record one user-attested measurement with method metadata;
10. finalize an immutable revision;
11. compute a manifest-rooted bundle digest;
12. export and reopen `.htdtcapture`;
13. pass validator/tamper checks;
14. run the documented geometric benchmark and record measured errors.

The PoC does not need to generate final acoustic geometry.

A visually plausible 3D model alone is not a PoC pass.

## 27. Immediate next work

Proceed in this order:

1. freeze Phase 0 contracts;
2. write coordinate/time contract and schema test vectors;
3. define mesh/frame/depth binary formats;
4. define benchmark protocol;
5. bootstrap SwiftUI app/session/store foundation;
6. implement RoomPlan raw + postprocessed preservation;
7. implement AR mesh capture;
8. implement camera/depth evidence;
9. add annotations/measurements;
10. add finalization/validator;
11. create frozen real-device fixture;
12. connect HTDT ingestion.

## 28. Primary references for implementation

Apple primary documentation should be rechecked at implementation time:

- RoomPlan `RoomCaptureView.init(frame:arSession:)`
- RoomPlan `RoomCaptureSession.init(arSession:)`
- RoomPlan `CapturedRoomData`
- RoomPlan `CapturedRoom`
- ARKit `ARCamera.transform`
- ARKit `ARAnchor.transform`
- ARKit scene reconstruction
- ARKit `ARFrame`
- ARKit `sceneDepth` / confidence

Accuracy protocol should remain informed by independent measurement literature, including studies showing strong dependence on acquisition software, trajectory, scene, and processing.

## 29. Architectural conclusion

The reviewed architecture is:

**Use Apple RoomPlan/ARKit directly; preserve raw RoomPlan scan output plus reconstructed mesh, selected image/depth evidence, exact coordinate/time metadata, and user-attested measurements in HTDT-owned versioned schemas; treat all visualization/repair/semantic reconciliation as explicit downstream derivation.**

This is stricter than a generic scanner app, but it matches HTDT's requirement that a Digital Twin remain auditable, revisable, and reprocessable.
