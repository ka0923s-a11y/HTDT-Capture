# Phase 4 Annotation + Measurement Implementation Record

Status: In progress  
Issue: #5

## Implemented in this slice

### Spatial annotation authority

HTDT-Capture now has a typed, versioned in-memory/JSON authority for:

- speakers;
- subwoofers;
- displays and projection screens;
- listening positions and seats;
- acoustic treatments;
- equipment racks;
- reference points;
- custom spatial entities.

Every entity carries:

- stable entity UUID;
- exact `coordinate_space_id`;
- `T_world_from_annotation`;
- stable reference-point semantics token;
- provenance and verification state;
- placement provenance;
- evidence references.

### Speaker-specific authority

A speaker cannot be constructed without:

- explicit front/up orientation axes;
- explicit channel role.

Axes must be unit length and orthogonal.

Supported built-in role tokens include L/C/R, SL/SR, SBL/SBR, LFE, and common top channels. The role type also accepts additional uppercase stable tokens rather than geometry free text.

### Acoustic-center safety

An acoustic-center offset is represented only by `AcousticCenterOffsetAuthority`, which requires both:

- local offset in meters;
- non-empty explicit authority reference.

The app therefore cannot silently convert a cabinet reference point into an acoustic center.

### Exact HTDT equipment binding

Optional equipment binding is not a loose model-name string. It stores:

- equipment ID;
- equipment version;
- exact equipment authority hash.

This is sufficient to bind capture annotations to a pinned HTDT equipment authority later.

### Placement provenance

Placement records the method and source lineage. Raycast/mesh-hit-test placement requires at least one supporting source reference. RoomPlan binding requires a RoomPlan/semantic source identity.

### Measurement authority

Measurements preserve independent records instead of resolving conflicts destructively.

Each record can carry:

- quantity token;
- scalar or 3-vector value;
- canonical SI unit;
- coordinate-space authority when spatial;
- endpoint references;
- acquisition method;
- instrument class/model;
- calibration metadata;
- uncertainty in the measurement unit;
- observation timestamp;
- user-attestation state;
- provenance class;
- exact user/source text;
- evidence references.

A `user_attested_measurement` is invalid unless the record is actually marked attested.

RoomPlan/LiDAR-derived values can coexist beside user-attested measurements with the same quantity type.

## Tested behavior

Core tests cover:

- required speaker orientation/channel role;
- unit/orthogonal orientation axes;
- acoustic-center authority requirement;
- 5-channel + LFE + MLP topology representation;
- coordinate/placement JSON lineage;
- exact equipment ID/version/hash;
- stable reference-point semantics;
- attestation requirements;
- spatial coordinate-space requirements;
- conflicting measurement coexistence;
- instrument/source-text preservation.

## Remaining hardware/UI work

Issue #5 remains open for:

- interactive annotation placement UI;
- real raycast/mesh-hit-test source binding on device;
- orientation capture UX;
- evidence photo linkage UX (canonical frame linkage is now implemented; external photo capture remains deferred);
- exact HTDT EquipmentDefinition selection UI;
- physical repeatability measurements under Issue #9.


## Manual authority authoring UI

The iOS host now provides a bounded manual authoring workflow during review.

The user can stage and inspect records before any immutable working-set payload
is written. **Save annotation authority** then writes both canonical collections
once:

- `annotations/entities.json`;
- `annotations/measurements.json`.

This one-shot commit matches the working-set no-overwrite rule. Records can be
edited by deleting/re-adding them while staged; after canonical persistence the
host does not pretend that the immutable payload can be edited in place.

### Spatial annotation inputs

The current software-only editor supports:

- annotation entity type and label;
- explicit X/Y/Z position in the active Capture coordinate space;
- speaker channel role;
- speaker yaw, encoded as an explicit normalized front axis with +Y up;
- optional pinned HTDT equipment reference requiring exact
  equipment ID + version + SHA-256.

Placement provenance is `manual_numeric`; no raycast or mesh-hit provenance is
fabricated by this UI.

### Measurement inputs

The editor supports user-attested scalar measurements with:

- quantity type;
- value and unit;
- acquisition method;
- optional stated uncertainty;
- optional source value text;
- optional instrument class and make/model.

These records remain distinct from LiDAR/RoomPlan-derived measurement
authorities.

### Remaining hardware/UI gates

Still not claimed by this slice:

- live camera/3D raycast placement;
- mesh-hit placement provenance;
- physical speaker-orientation capture;
- external photo capture beyond the canonical ARFrame evidence linkage;
- connected HTDT equipment-catalog picker;
- physical placement/repeatability benchmark.


## Canonical evidence-frame linkage

The review authoring UI now receives the exact canonical frame-descriptor
references already persisted in the active working revision.

Annotations and user-attested measurements can select one or more of those
frames. The resulting record keeps references such as:

`path:evidence/frames/<frame-id>.json`

The link points to the exact frame descriptor, which in turn binds the camera
pixels, pose, intrinsics, timestamp and any captured depth/confidence evidence.
The UI does not copy image bytes or create an untracked preview-only photo.

Only evidence already present in the same working revision is offered for
selection. This slice does not add external Photos-library imports or claim a
separate photographic provenance class.
