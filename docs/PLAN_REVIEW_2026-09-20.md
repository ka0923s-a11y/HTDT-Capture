# HTDT-Capture Plan Review — 2026-09-20

## Outcome

The original v1 plan had the correct overall direction:

- evidence-first capture;
- HTDT-owned provenance/revision semantics;
- direct use of RoomPlan/ARKit;
- GLB/USDZ treated as derived visualization;
- explicit annotations and measurements;
- backend conversion into HTDT authorities.

However, the review identified several issues that should be corrected **before implementation**.

The revised plan is now `docs/IMPLEMENTATION_PLAN.md` (Reviewed v2).

## Critical changes

### 1. Preserve RoomPlan `CapturedRoomData`, not only `CapturedRoom`

The original plan retained post-processed RoomPlan output but omitted the framework's raw scan object.

Apple documents `CapturedRoomData` as an opaque raw scan result that conforms to Codable and can be serialized and processed later with `RoomBuilder`.

Decision:

- `roomplan/captured-room-data.json` becomes canonical evidence.
- `CapturedRoom` is preserved separately as post-processed evidence.
- USD/USDZ remains derived.

References:

- https://developer.apple.com/documentation/roomplan/capturedroomdata
- https://developer.apple.com/documentation/roomplan/capturedroom

### 2. Replace ambiguous transform arrows with explicit transform semantics

The v1 plan used phrases such as "AR world -> camera", which are easy to interpret in the wrong direction.

Apple's `ARCamera.transform` describes camera pose in world space, and `ARAnchor.transform` describes the anchor relative to world space.

Decision:

- use `T_destination_from_source` names;
- canonical examples are `T_world_from_camera` and `T_world_from_mesh_anchor`;
- explicitly define handedness, units, scalar type, matrix layout, image orientation handling.

References:

- https://developer.apple.com/documentation/arkit/arcamera/transform
- https://developer.apple.com/documentation/arkit/aranchor/transform

### 3. Stop calling the whole capture "lossless"

RoomPlan and ARKit outputs are already reconstructions/interpretations, and an HEIC export is not necessarily an exact byte representation of the AR camera pixel buffer.

Decision:

- use "evidence-preserving" / "loss-minimizing";
- make no claim to raw LiDAR samples unless such samples are actually available;
- retain exact selected camera pixel-plane bytes in a defined binary payload where practical;
- treat HEIC as a preview/derived encoding unless proven otherwise.

### 4. Add an explicit time model

AR frame timestamps are session/monotonic timestamps, not wall-clock RFC3339 timestamps.

Decision:

- preserve session monotonic timestamps for synchronization;
- preserve UTC timestamps for audit chronology;
- record clock-correlation samples at session boundaries;
- never conflate the two domains.

Reference:

- https://developer.apple.com/documentation/arkit/arframe

### 5. Fix bundle integrity design

A manifest that contains its own digest or a checksum file that hashes itself creates circularity.

Decision:

- `manifest.json` lists hashes for canonical payloads;
- `bundle_digest = SHA256(canonical_bytes(manifest.json))`;
- the manifest does not include its own digest;
- optional human-readable checksum files are derived convenience outputs.

### 6. Promote scene depth + confidence to selected MVP evidence

Apple exposes discrete `sceneDepth` with a corresponding confidence map when supported.

Decision:

- selected evidence frames should preserve discrete depth and confidence when supported;
- smoothed depth is marked processed/derived rather than silently replacing discrete depth;
- capability-gate the feature.

References:

- https://developer.apple.com/documentation/arkit/arframe/scenedepth
- https://developer.apple.com/documentation/arkit/ardepthdata

## High-priority changes

### 7. Clarify mesh evidence semantics

The ARKit mesh is a reconstructed scene estimate, not raw LiDAR.

Decision:

- preserve final active `ARMeshAnchor` snapshots;
- retain anchor identity and transforms;
- serialize portable canonical arrays rather than implementation-specific buffer padding;
- a merged mesh is derived.

### 8. Separate capture series, revision, session, and coordinate-space identity

The original `capture_id` / `revision_id` model was insufficient for re-scan semantics.

Decision:

- `capture_series_id`;
- `capture_revision_id`;
- `capture_session_id`;
- `coordinate_space_id`;
- `parent_revision_id`.

A fresh ARSession creates a fresh coordinate space unless an explicit alignment authority is produced.

### 9. Replace "verified measurement" with "user-attested measurement"

User confirmation does not imply metrological certification.

Decision:

Measurement records include:

- method;
- instrument;
- optional calibration metadata;
- uncertainty/tolerance where known;
- user attestation;
- evidence links.

Conflicts are retained rather than overwritten.

### 10. Add storage/backpressure/failure-closed rules

Raw image/depth/mesh artifacts can be large and AR callbacks are latency-sensitive.

Decision:

- no heavy persistence on ARSession delegate callback paths;
- bounded writer;
- streamed writes/hashing;
- free-space preflight;
- explicit persistence backlog diagnostics;
- finalization fails closed if required canonical evidence is missing.

### 11. Make capability checks runtime-driven

Do not encode assumptions from device model names.

Decision:

Gate RoomPlan, scene reconstruction, scene depth, and related features using framework capability APIs.

References:

- https://developer.apple.com/documentation/roomplan/roomcapturesession/issupported
- https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction

## Accuracy review

Published work does not support a single universal accuracy value for smartphone LiDAR.

Results depend materially on:

- app/processing pipeline;
- scan path;
- drift/loop closure;
- scene size;
- range;
- incidence angle;
- surface properties.

Examples:

- Askar & Sternberg (2023), DOI 10.3390/geomatics3040030 — same iPhone hardware produced materially different outcomes across apps.
- Vipavec & Kregar (2024), DOI 10.15292/geodetski-vestnik.2024.02.145-179 — reports that relative positional accuracy better than 10 cm could not be achieved in their tested Apple-device workflow.
- Treccani et al. (2024), DOI 10.5194/isprs-archives-XLVIII-2-W8-2024-431-2024 — reports errors from around centimeter scale to around 10 cm depending on area/app, and notes benefits from loop closure.
- Strecha et al. (2024), DOI 10.5194/isprs-archives-XLVIII-2-2024-415-2024 — focuses on drift compensation and combining independent mobile scans.

Decision:

HTDT-Capture gets a dedicated accuracy-validation program. Visual plausibility is not an acceptance test.

Metrics include:

- absolute dimensional error;
- bias;
- RMSE;
- repeatability;
- plane residuals;
- drift / loop closure error;
- RoomPlan-to-mesh alignment;
- annotation position repeatability;
- speaker orientation error;
- depth error by confidence/range.

Critical dimensions may still require user-attested external measurements.

## Scope changes

### Added to MVP

- raw `CapturedRoomData`;
- explicit coordinate contract;
- explicit time contract;
- selected raw camera pixel payload;
- selected discrete depth + confidence;
- bundle-root integrity model;
- storage/backpressure rules;
- accuracy benchmark protocol.

### Still deferred

- cross-session spatial alignment;
- multi-room production workflow;
- automatic model recognition as authority;
- automatic material inference as authority;
- full continuous video evidence;
- custom reconstruction/fusion pipeline;
- cloud accounts/uploads.

## Implementation-order change

v1 moved quickly from schema to app shell.

v2 requires the following contracts to be frozen first:

1. coordinate/time contract;
2. manifest/integrity model;
3. RoomPlan raw/postprocessed evidence distinction;
4. mesh binary format;
5. frame/depth binary format;
6. revision/session/coordinate identity model;
7. accuracy validation protocol.

Only then should sensor-specific persistence be implemented.

## Review conclusion

The project direction is sound, but the v1 plan was not yet strict enough for HTDT's provenance requirements.

The v2 plan corrects the main risks before code exists, particularly:

- irreversible loss of RoomPlan raw evidence;
- transform inversion bugs;
- false "lossless" claims;
- timestamp ambiguity;
- integrity recursion;
- silent coordinate reuse across re-scans;
- unvalidated spatial accuracy.

No production code existed at review time, so these changes are low-cost and should be adopted before Phase 0 implementation.
