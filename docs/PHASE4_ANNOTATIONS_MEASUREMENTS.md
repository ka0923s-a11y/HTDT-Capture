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
- evidence photo linkage UX;
- exact HTDT EquipmentDefinition selection UI;
- physical repeatability measurements under Issue #9.
