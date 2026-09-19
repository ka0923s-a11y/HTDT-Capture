# Coordinate and Time Contract

Status: Capture Bundle v1

## 1. Coordinate-space authority

Every spatial record must identify a `coordinate_space_id`.

For the MVP, one active app-owned ARSession defines one AR world space. A world-origin reset, incompatible ARSession restart, or failed continuity event creates a new coordinate-space authority.

## 2. Spatial convention

Canonical capture coordinates use:

- right-handed 3D coordinates;
- meters;
- homogeneous 4x4 transforms;
- IEEE-754 binary32 transform components unless a schema explicitly states otherwise;
- column-major SIMD semantic order when serialized as a flat 16-element matrix.

Transform names use:

```text
T_<destination>_from_<source>
```

Examples:

- `T_world_from_camera`
- `T_world_from_mesh_anchor`
- `T_world_from_annotation`

The equation is:

```text
p_destination = T_destination_from_source * p_source
```

Ambiguous notation such as "world -> camera" is prohibited in schemas and production code.

## 3. AR camera and anchor semantics

The capture adapter stores Apple transform values according to their API meaning without opportunistic inversion.

A conversion to another rendering/export convention is a derived transform and must preserve:

- source coordinate-space ID;
- destination convention;
- exact conversion matrix;
- unit conversion;
- producing tool/version.

## 4. Matrix serialization

A serialized matrix object uses:

```json
{
  "representation": "column_major_4x4_f32",
  "values": [16 finite numbers]
}
```

Element sequence is the four SIMD columns in order:

```text
c0.x c0.y c0.z c0.w
c1.x c1.y c1.z c1.w
c2.x c2.y c2.z c2.w
c3.x c3.y c3.z c3.w
```

No implicit row-major transposition is permitted.

## 5. Image orientation

Camera extrinsics are independent from display/UI orientation.

Frame metadata preserves:

- camera transform;
- native pixel-buffer dimensions;
- camera intrinsics;
- pixel format;
- source orientation semantics;
- preview/display transform if one is used.

A portrait UI transform never modifies canonical `T_world_from_camera`.

## 6. Annotation orientation

Equipment orientation records explicit semantic axes:

- `front_axis_local`
- `up_axis_local`
- optional `acoustic_center_offset_local_m`

The acoustic-center offset is absent unless supplied by an explicit equipment/reference authority.

## 7. Session time

AR/session timestamps are monotonic session time, not civil time.

Frame records use:

- `capture_session_id`
- `session_timestamp_s`
- `clock_domain`

They are used for synchronization/order within the session.

## 8. Wall-clock time

UTC timestamps are used for audit chronology.

At capture-session start and end, store a correlation observation containing:

- monotonic/process clock sample;
- UTC wall-clock sample;
- sampling method;
- estimated correlation uncertainty if known.

No frame timestamp is converted to UTC without referring to this correlation authority.

## 9. Reset/relocalization events

The session event log records any event that can invalidate spatial assumptions:

- ARSession restart;
- world-origin reset;
- tracking relocalization transition;
- application interruption;
- explicit reconfiguration that restarts tracking.

If spatial continuity cannot be demonstrated, subsequent spatial records use a new `coordinate_space_id`.

## 10. Verification tests

Phase 0/1 tests must cover:

- known transform multiplication cases;
- matrix serialize/deserialize round trip;
- inverse-consistency checks;
- no accidental portrait rotation in camera extrinsics;
- separate monotonic and UTC fields;
- new coordinate-space ID on simulated reset transitions.
