# Phase 4 Annotation + Measurement Implementation Record

Status: Software implementation complete; physical acceptance remains under Issue #9  
Issue: #5 (closed)

## Implemented in this slice

### Spatial annotation authority

HTDT-Capture now has a typed, versioned in-memory/JSON authority for:

- speakers;
- subwoofers;
- displays and projection screens;
- projectors;
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
- evidence references;
- creation/revision lifecycle metadata (`created_at_utc`, optional
  `updated_at_utc` / `observed_at_utc` / `source_created_at_utc` /
  `supersedes_entity_id`).

Optional contract extensions (annotation_contract cluster):

- `physical_envelope`: user-measured / catalog-derived / imported
  width-height-depth authority, never inferred by the app (#230);
- `listening_role`: typed primary/secondary/measurement-reference
  role for listening positions, independent of the human label
  (#243);
- `uncertainty`: optional isotropic/per-axis/angular uncertainty with
  a stated basis — user, instrument, or app estimate (#258);
- `authority`: per-component verification detail (placement,
  orientation, equipment, reference point, semantic role) so a mixed
  record never overstates which fields are evidence-backed; the
  aggregate `verification_state` remains the derived summary (#263);
- `reference_point`: explicit construction record for
  evidence-captured placements — a raycast hit cannot silently claim
  a semantic point such as `ear_center` without `surface_hit_confirmed`
  or `offset_from_surface` (#291).

### Speaker-specific authority

A speaker cannot be constructed without:

- explicit front/up orientation axes;
- explicit channel role.

Axes must be unit length and orthogonal.

Supported built-in role tokens include L/C/R, SL/SR, SBL/SBR, LFE, and common top channels. The role type also accepts additional uppercase stable tokens rather than geometry free text.

Subwoofers carry the same topology authority (#244): every subwoofer
requires a typed channel/instance role (LFE1/LFE2/... or a custom
token) and may carry an optional captured or yaw-entered body
orientation — so multi-sub layouts are distinguishable without label
parsing.

### Acoustic-center safety

An acoustic-center offset is represented only by `AcousticCenterOffsetAuthority`, which requires both:

- local offset in meters;
- non-empty explicit authority reference.

The app therefore cannot silently convert a cabinet reference point into an acoustic center.

### Exact HTDT equipment binding

Optional equipment binding is not a loose model-name string. It stores:

- equipment ID;
- equipment version;
- exact equipment authority hash;
- the catalog authority version the tuple was selected under.

This is sufficient to bind capture annotations to a pinned HTDT equipment authority later.

Compatibility is enforced below the UI (#237): the current
`o100c-equipment-definition-1` acoustic-source catalog contract only
authorizes equipment references on speaker/subwoofer annotations. The
builder rejects a tuple attached to an incompatible type or stamped
with an unknown authority version; legacy unversioned tuples resolve
to the original catalog contract and remain readable, with any
semantic mismatch surfaced in Review rather than silently ignored.

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

## Remaining physical acceptance

The software paths requested by Issue #5 are implemented: manual authoring,
canonical frame evidence linkage, live ARKit raycast placement, explicit
speaker-heading capture, and exact EquipmentDefinition catalog selection.

Remaining validation is physical evidence rather than missing authority/UI
plumbing:

- verify live raycast behavior and placement accuracy on the target LiDAR device;
- verify speaker-heading repeatability;
- benchmark placement/orientation error under Issue #9.

External Photos-library import remains intentionally outside the MVP because
canonical ARFrame evidence already supplies an exact pose-linked photo source.


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
- typed listening-position role (primary / secondary / measurement
  reference) for listening positions;
- explicit X/Y/Z position in the active Capture coordinate space;
- channel role for speakers and subwoofers;
- orientation yaw for any type with body/plane semantics, encoded as
  an explicit normalized front axis with +Y up;
- optional physical-envelope dimensions with `user_measured`
  provenance;
- type-appropriate reference-point semantics selection;
- optional pinned HTDT equipment reference requiring exact
  equipment ID + version + SHA-256, offered only for compatible
  annotation types (#237).

Placement provenance is `manual_numeric` unless the live raycast
action is used; no raycast or mesh-hit provenance is fabricated by
this UI. An evidence-captured placement additionally requires an
explicit reference-point construction choice (confirmed hit vs.
surface offset) before the record can be authored (#291).

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

### Remaining hardware gates

Still not claimed by software CI:

- physical verification of live raycast placement;
- physical verification of speaker-heading capture;
- physical placement/orientation repeatability benchmark under Issue #9.

The current raycast authority intentionally records ARKit raycast provenance
without inventing a mesh-anchor identity. External Photos-library capture
remains deferred.


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


## Live evidence-linked raycast placement

The review annotation editor now has an explicit **Use live center raycast**
action while the app-owned ARSession is still alive after the RoomPlan scan
boundary.

The path is:

`current ARFrame camera center ray -> ARSession raycast -> exact hit position -> persist that same ARFrame as canonical evidence -> annotation placement authority`.

The placement authority stores a translation-only
`T_world_from_annotation`; it does not adopt plane orientation as speaker
orientation. Speaker front-axis authority remains an independent explicit input.

Raycast provenance is only asserted when a real ARKit raycast returns a hit.
The supporting canonical frame descriptor is recorded in both placement
`source_evidence_refs` and entity `evidence_refs`. The adapter does not guess
that an ARKit plane hit corresponds to a particular mesh anchor.

If annotation editing is cancelled, staged annotation/measurement records are
not written. Any ARFrame explicitly captured by a raycast action remains valid
canonical evidence in the working revision rather than being silently deleted.

Physical placement accuracy and repeatability remain Issue #9 hardware gates.


## Evidence-linked speaker orientation capture

The speaker editor now supports an explicit **Capture current camera heading**
action. The user is instructed to point the phone in the intended speaker-front
direction before capture.

The adapter reads the same live ARSession world frame, projects the camera
forward vector onto the horizontal X/Z plane, rejects a near-vertical pose where
heading is undefined, and normalizes the result. +Y remains the explicit up
axis.

The exact ARFrame used for the heading is persisted as canonical evidence and
linked to the speaker entity. Captured heading overrides manual yaw only when
the user explicitly selects it. Position raycast and orientation capture remain
independent authorities.

This establishes the software path; speaker-orientation accuracy and
repeatability remain physical benchmark gates under Issue #9.


## Exact HTDT equipment catalog picker

The review workspace can now import the deterministic
`htdt.equipment.catalog-snapshot` v1 JSON exported by the HTDT backend.

The catalog is only a picker/index surface. Selecting an entry fills and locks
the exact immutable binding tuple already used by the Capture authority:

- `definition_id`;
- `version`;
- `semantic_sha256`.

Only that exact tuple is stored in the annotation's
`HTDTEquipmentReference`. The imported catalog file itself is not promoted to
equipment authority and is not copied into the capture bundle.

Manual exact ID/version/SHA-256 entry remains available when no catalog is
imported. The app never binds equipment by manufacturer/model display text
alone.
