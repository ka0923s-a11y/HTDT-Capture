# Phase 4 Annotation + Measurement Implementation Record

Status: Software implementation complete; physical acceptance remains under Issue bolph71656-ai/HTDT-Capture#9  
Issue: legacy bolph71656-ai/HTDT-Capture#5 (closed)

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
  width-height-depth authority, never inferred by the app (legacy bolph71656-ai/HTDT-Capture#230);
- `listening_role`: typed primary/secondary/measurement-reference
  role for listening positions, independent of the human label
  (legacy bolph71656-ai/HTDT-Capture#243);
- `uncertainty`: optional isotropic/per-axis/angular uncertainty with
  a stated basis — user, instrument, or app estimate (legacy bolph71656-ai/HTDT-Capture#258);
- `authority`: per-component verification detail (placement,
  orientation, equipment, reference point, semantic role) so a mixed
  record never overstates which fields are evidence-backed; the
  aggregate `verification_state` remains the derived summary (legacy bolph71656-ai/HTDT-Capture#263);
- `reference_point`: explicit construction record for
  evidence-captured placements — a raycast hit cannot silently claim
  a semantic point such as `ear_center` without `surface_hit_confirmed`
  or `offset_from_surface` (legacy bolph71656-ai/HTDT-Capture#291).

### Speaker-specific authority

A speaker cannot be constructed without:

- explicit front/up orientation axes;
- explicit channel role.

Axes must be unit length and orthogonal.

Supported built-in role tokens include L/C/R, SL/SR, SBL/SBR, LFE, and common top channels. The role type also accepts additional uppercase stable tokens rather than geometry free text.

Subwoofers carry the same topology authority (legacy bolph71656-ai/HTDT-Capture#244): every subwoofer
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

Compatibility is enforced below the UI (legacy bolph71656-ai/HTDT-Capture#237): the current
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
- canonical SI unit (`m`, `rad`, `1`, `s`, `degC`, `%` — versioned
  vocabulary extended for environmental quantities, issues bolph71656-ai/HTDT-Capture#269/legacy bolph71656-ai/HTDT-Capture#253);
- coordinate-space authority when spatial;
- endpoint references;
- acquisition method (including `external_instrument` for metered
  room-condition readings, issue bolph71656-ai/HTDT-Capture#253);
- instrument class/model;
- calibration metadata;
- uncertainty in the measurement unit;
- observation timestamp;
- user-attestation state;
- provenance class;
- exact user/source text;
- optional structured source authority for `manufacturer_specification`
  values (document ref/revision, property key, pinned equipment
  reference, source SHA-256 — issue bolph71656-ai/HTDT-Capture#275);
- optional derivation lineage (`algorithm` / `algorithm_version` /
  `source_refs`) for computed values (issue bolph71656-ai/HTDT-Capture#286);
- evidence references.

A `user_attested_measurement` is invalid unless the record is actually marked attested.

A versioned quantity registry (`MeasurementQuantityRegistry`) binds each
standardized `quantity_type` token to a physical dimension, a canonical
unit, a value shape, and endpoint semantics (issue bolph71656-ai/HTDT-Capture#287). Production
producers — the manual builder and the derived builder — validate against
it, so a registered length quantity cannot persist `rad` or `%`. Custom
quantity tokens remain legal: an unregistered token skips registry
validation and its chosen unit declares its dimension.

RoomPlan/LiDAR-derived values can coexist beside user-attested measurements with the same quantity type.
Because a collection may now mix per-record provenance classes, the
manifest declaration for `annotations/measurements.json` is derived as
follows: a homogeneous collection declares its exact class, a heterogeneous
collection declares `capture_app_derived` container authority (the same
class an empty collection uses), and per-record `provenance_class` remains
authoritative (issue bolph71656-ai/HTDT-Capture#286). The manifest can never overclaim a mixed
collection as user-attested.

Derived measurements are produced by `DerivedMeasurementBuilder`, which
computes endpoint distance / displacement from accepted spatial
authorities:

- both endpoints RoomPlan-bound → `roomplan_derived` +
  `apple_roomplan_inference`;
- both endpoints mesh/raycast-bound → `lidar_derived` +
  `arkit_mesh_reconstruction`;
- manual or mixed endpoint authorities → `other` +
  `capture_app_derived` with mandatory derivation lineage.

Derived records are always `not_attested`; the operator's own laser/tape
value remains a separate `user_attested_measurement` record for conflict
review.

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

The software paths requested by Issue bolph71656-ai/HTDT-Capture#5 are implemented: manual authoring,
canonical frame evidence linkage, live ARKit raycast placement, explicit
speaker-heading capture, and exact EquipmentDefinition catalog selection.

Remaining validation is physical evidence rather than missing authority/UI
plumbing:

- verify live raycast behavior and placement accuracy on the target LiDAR device;
- verify speaker-heading repeatability;
- benchmark placement/orientation error under Issue bolph71656-ai/HTDT-Capture#9.

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

A bounded replace path also exists for revision commits:
`replaceAnnotationAndMeasurementPackages` swaps the entities/measurements
(and optionally authorities) packages atomically as one rollback-capable
batch, re-validating authority references against the replacement so a
deleted entity cannot leave a dangling reference.

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
  annotation types (legacy bolph71656-ai/HTDT-Capture#237).

Placement provenance is `manual_numeric` unless the live raycast
action is used; no raycast or mesh-hit provenance is fabricated by
this UI. An evidence-captured placement additionally requires an
explicit reference-point construction choice (confirmed hit vs.
surface offset) before the record can be authored (legacy bolph71656-ai/HTDT-Capture#291).

### Measurement inputs

The editor supports user-attested scalar and vector measurements with:

- quantity type picked from the versioned quantity registry (with an
  explicit custom-quantity escape);
- value entered in practical input units — m, cm, mm, ft, in, or
  combined ft+in for lengths; deg for angles; °C/°F for temperature;
  % or a 0–1 fraction for humidity — parsed deterministically
  (`.`/`,` decimal separators both accepted) and normalized to the
  canonical unit before authority creation, with the original text kept
  in `source_value_text` (issue bolph71656-ai/HTDT-Capture#235);
- optional endpoint A/B bound to staged annotation authorities
  (`entity:` refs) plus the capture `coordinate_space_id` (issue bolph71656-ai/HTDT-Capture#215);
- acquisition method — tape, laser, external instrument, manufacturer
  specification, other; derived methods are never offered to the manual
  path;
- automatic UTC observation timestamp for live readings —
  manufacturer-specification values never receive one, so a datasheet
  number is not mislabeled as a live observation (issue bolph71656-ai/HTDT-Capture#238);
- optional stated uncertainty, source value text, instrument
  class/make/model, calibration status and calibration date;
- for `manufacturer_specification`, a required-at-least-one structured
  source authority: document ref/revision, property key, source
  SHA-256, or a pinned equipment reference (issue bolph71656-ai/HTDT-Capture#275);
- when both endpoints are bound, a derive action computes distance or
  displacement through `DerivedMeasurementBuilder` and appends a
  provenance-correct derived record alongside the manual one
  (issue bolph71656-ai/HTDT-Capture#286);
- vector3 values authored either as raw components or via derived
  displacement — always with coordinate-space binding (issue bolph71656-ai/HTDT-Capture#270).

Room-condition quantities (`air_temperature`, `relative_humidity`) are
registry entries with `expectedEndpoints == 0`, so environmental
readings never fabricate spatial endpoints (issue bolph71656-ai/HTDT-Capture#253).

These records remain distinct from LiDAR/RoomPlan-derived measurement
authorities.

The annotation entity vocabulary additionally includes
`measurement_point` — a typed microphone-capsule/receiver point whose
optional orientation authority captures the full 3D camera orientation
(forward + up), not the flattened speaker-heading convention
(issue bolph71656-ai/HTDT-Capture#271). It never claims an FR/IR was acquired; it only records
where and in which direction a measurement microphone sat.

### Remaining hardware gates

Still not claimed by automated software checks:

- physical verification of live raycast placement;
- physical verification of speaker-heading capture;
- physical placement/orientation repeatability benchmark under Issue bolph71656-ai/HTDT-Capture#9.

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

Physical placement accuracy and repeatability remain Issue bolph71656-ai/HTDT-Capture#9 hardware gates.


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
repeatability remain physical benchmark gates under Issue bolph71656-ai/HTDT-Capture#9.


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
