# HTDT-Capture Architecture

Status: Phase 0 baseline  
Schema line: Capture Bundle v1

## 1. Architectural objective

HTDT-Capture is an evidence acquisition frontend for Home Theater Digital Twin. Its primary responsibility is to preserve exact capture evidence, provenance, coordinate/time authority, and user-attested measurements so HTDT can derive versioned downstream authorities without losing the original source context.

The application must not treat a visually pleasing reconstructed model as the source of truth.

## 2. Layering

```text
Physical room
  -> Apple capture frameworks + explicit user input
  -> capture working set
  -> immutable HTDT-Capture revision
  -> validated .htdtcapture bundle
  -> HTDT source-evidence registry
  -> RawVisualMesh / semantic evidence
  -> SemanticAcousticGeometry
  -> SceneRevision
  -> solver-specific authorities
```

The capture app owns acquisition and evidence packaging. HTDT owns semantic reconciliation, mesh diagnostics/repair, acoustic geometry compilation, and solver-facing interpretation.

## 3. Identity model

The following identifiers are intentionally distinct:

- `capture_series_id`: logical lineage for one room/project.
- `capture_revision_id`: one immutable finalized capture bundle.
- `capture_session_id`: one sensor acquisition session.
- `coordinate_space_id`: one spatial world-frame authority.
- `parent_revision_id`: previous finalized revision when applicable.

A new ARSession or a world-origin reset does not inherit an existing `coordinate_space_id` unless an explicit alignment authority proves continuity.

## 4. Primary modules

### PlatformCapabilities
Evaluates framework capabilities at runtime. Device marketing names are not capability authorities.

### CaptureSession
Owns the app-controlled ARSession, state machine, coordinate-space identity, exact capture configuration, interruption handling, and monotonic-clock correlation.

### RoomPlanCapture
Adapts RoomPlan to the app-owned ARSession. It preserves raw `CapturedRoomData` separately from postprocessed `CapturedRoom`.

### MeshCapture
Tracks ARMeshAnchor lifecycle and preserves a final anchor-level snapshot. A merged mesh is always derived.

### EvidenceCapture
Captures selected camera/depth observations with frame-local metadata. It serializes only defined active pixel bytes, never allocator padding.

### Annotation
Stores HTDT-specific equipment/reference entities, orientation, placement method, and user-attested measurements.

### CaptureStore
Performs bounded asynchronous writes, streamed hashing, atomic artifact commit, cleanup, and finalization.

### Bundle
Implements schema models, canonical JSON, manifest integrity, archive wrapping, and validation.

### Review
Presents evidence/conflicts/quality without collapsing them into a single opaque score.

## 5. Capture modes

The implementation must not assume that RoomPlan, scene reconstruction, and scene depth remain simultaneously available in every configuration.

Phase 1 must physically probe the target combined configuration. The architecture supports explicit modes:

- `roomplan_mesh`: RoomPlan + reconstructed mesh in one world frame.
- `evidence_depth`: selected RGB/depth evidence in the current world frame where supported.
- `degraded_no_depth`: same-frame capture without depth when RoomPlan/ARKit configuration prevents it.

Preferred transition:

```text
roomplan_mesh
  -> stop RoomPlan with underlying ARSession preserved
  -> evidence_depth in the same coordinate_space_id
```

If the required reconfiguration resets tracking/world origin, the app must issue a new `coordinate_space_id`. It must never silently pretend continuity.

Startup policy (Option B): production capture requires `roomPlanMeshEligible` — a session only begins in `roomplan_mesh`. `evidence_depth` and `degraded_no_depth` are runtime-resolution modes reached when mesh reconstruction is lost after a mesh-eligible start; the capability contract keeps them so quality fallback stays honest about startup-vs-runtime mesh loss.

## 6. Session lifecycle

A capture session has an explicit domain state machine:

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

Tracking quality, thermal state, storage pressure, interruption state, persistence backlog, and recoverability are orthogonal status dimensions.

A finalized revision is immutable.

## 7. Persistence rules

- AR callbacks do not perform expensive encoding/hashing inline.
- Evidence required after callback return is copied/retained according to framework lifetime guarantees.
- Writes pass through a bounded writer.
- A required artifact that cannot be persisted causes an explicit failure.
- Temporary files are atomically promoted only after a complete write and hash.
- Finalization writes all payloads first and `manifest.json` last.
- Finalization is an atomic state transition, not a UI label.

## 8. Trust boundaries

A locally generated working set is trusted only as an in-process source. A `.htdtcapture` archive is untrusted input when reopened/imported.

Before evidence promotion, the validator checks:

- schema/version;
- normalized safe paths;
- archive expansion limits;
- duplicate/case-colliding paths;
- byte lengths and SHA-256;
- canonical manifest representation;
- declared-vs-present payload set.

Hash integrity is not origin authentication. Future signing, if added, is a separate authority.

## 9. Versioning

Capture Bundle v1 is forward-incompatible by default. An importer that does not recognize a schema major/minor version fails closed unless an explicit migration implementation exists.

Binary payload formats carry their own magic/version headers and do not rely solely on filename extensions.

## 10. Testing boundary

CI validates deterministic contracts, schema syntax, serialization, validator safety, and fixtures.

Physical device evidence is mandatory for RoomPlan, reconstruction, depth, session-lifetime behavior, combined capture modes, tracking interruptions, performance, and spatial accuracy.
