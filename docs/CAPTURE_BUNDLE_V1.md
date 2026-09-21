# HTDT Capture Bundle v1

Status: Phase 0 contract  
Logical schema: `htdt.capture.bundle`  
Schema version: `1.0.0`

## 1. Container and content type

The logical bundle is independent of its archive wrapper.

Provisional exported Apple content type:

- identifier: `com.hometheaterdigitaltwin.capture-bundle`
- filename extension: `.htdtcapture`
- physical MVP wrapper: ZIP-compatible archive
- logical integrity authority: canonical `manifest.json`, not ZIP bytes

The identifier is project-owned and may be renamed before public App Store distribution, but the extension and logical schema remain versioned separately.

## 2. Logical layout

```text
capture-<capture-revision-id>.htdtcapture/
|
+-- manifest.json
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
|
+-- mesh/
|   +-- anchors.json
|   +-- geometry/
|
+-- evidence/
|   +-- frames/
|   +-- depth/
|
+-- annotations/
|   +-- entities.json
|   +-- measurements.json
|
+-- advisory/
|   +-- operator-advisories.json
|
+-- quality/
    +-- capture-quality.json
    +-- capture-advisory.json
    +-- benchmark-observations.json
```

Not every optional directory exists in every bundle. Every file other than `manifest.json` must be declared by the manifest in v1.

`advisory/operator-advisories.json` is a derived `capture_app_derived` payload: bounded operator/policy provenance notes (declared inaccessible regions, automatic-keyframe retention, frame-usability warnings, the optional return-to-start check, targeted object passes). It informs Review and downstream repair planning but never asserts canonical geometry or evidence authority.

## 3. Canonical versus derived role

Every manifest entry has a `role`:

- `canonical`: source evidence or HTDT-Capture authority needed for deterministic re-ingestion.
- `derived`: convenience output reproducible or replaceable from canonical evidence.

Examples:

| Artifact | Role |
|---|---|
| CapturedRoomData encoding | canonical |
| final ARMeshAnchor snapshot | canonical |
| packed selected camera frame | canonical |
| discrete sceneDepth/confidence | canonical when captured |
| user-attested measurements | canonical |
| postprocessed CapturedRoom | canonical evidence, but explicitly derived from CapturedRoomData |
| HEIC preview | derived |
| USD/USDZ/GLB preview/export | derived |
| merged mesh preview | derived |
| `quality/capture-advisory.json` advisory diagnostics | derived (`capture_app_derived`) |

`quality/capture-advisory.json` is the bounded advisory-diagnostics payload persisted at seal: End-boundary coverage/guidance summary, operator task completeness, RoomPlan guidance transitions, mesh lifecycle statistics, depth sufficiency summary, conflict reconciliation, and RoomPlan↔mesh consistency. It is never a geometry/truth authority, never a finalization gate, and unknown coverage cells are never proof of missing geometry.

"Canonical" does not mean "physically exact"; it means the bundle preserves that exact source/authority artifact.

## 4. Provenance vocabulary v1

Allowed initial provenance classes:

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

A provenance class is descriptive and does not encode precedence.

## 5. Manifest integrity

The manifest includes the byte length and SHA-256 digest of every payload.

The manifest never includes its own hash.

```text
bundle_digest = SHA256(canonical_bytes(manifest.json))
```

Because every payload digest is committed inside the manifest, `bundle_digest` identifies the complete logical bundle.

The v1 validator requires `manifest.json` itself to be encoded in canonical JSON form.

SHA-256 establishes content integrity/identity. It is not a signature and does not establish author identity.

## 6. Canonical JSON profile v1

For schema-owned JSON written by HTDT-Capture:

1. UTF-8, no BOM.
2. Unicode strings and keys must be NFC-normalized.
3. Object keys are lexicographically sorted.
4. No insignificant whitespace.
5. JSON control characters use standard JSON escaping.
6. Non-ASCII Unicode is emitted directly rather than ASCII-escaped.
7. Integers use base-10 canonical representation.
8. Floating-point numbers are forbidden in `manifest.json`. Spatial JSON schemas that require floats define their own finite IEEE-754 constraints.
9. NaN and infinities are forbidden.
10. The file has no required trailing newline.

The reference Python implementation is `tools/bundle_validator/validator.py`. Swift serialization must reproduce the same manifest bytes for the same logical manifest.

## 7. Manifest paths

Paths use normalized relative POSIX syntax.

Rejected:

- absolute paths;
- backslashes;
- empty segments;
- `.` or `..`;
- NUL;
- symlinks/hardlinks in archives;
- duplicate paths;
- Unicode/case-fold collisions.

V1 additionally rejects undeclared payload files to keep the logical content set exact.

## 8. Archive safety limits

Reference default validator limits:

- maximum entries: 10,000
- maximum one expanded file: 512 MiB
- maximum total expanded bytes: 4 GiB
- maximum compression ratio for a non-empty compressed member: 200:1

These are safety defaults, not bundle-format capacity claims. A future version may parameterize them by authenticated policy.

## 9. Identity and revision rules

A finalized `capture_revision_id` never mutates.

Corrections produce another revision under the same `capture_series_id` with `parent_revision_id` pointing at the prior revision when applicable.

A new sensor session gets a new `capture_session_id`.

A tracking/world-frame discontinuity gets a new `coordinate_space_id`.

## 10. Finalization order

1. close or snapshot required capture producers;
2. complete all required payload writes;
3. hash payload bytes;
4. build and canonicalize manifest;
5. validate the working directory as if it were external input;
6. atomically mark the revision finalized;
7. optionally wrap the logical directory as `.htdtcapture`.

If validation fails, the revision remains non-finalized.
