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
|   +-- coordinate-space-policy.json
|   +-- capture-task-plan.json
|   +-- task-plan-status.json
|   +-- connected-spaces.json
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
|   +-- reference-targets.json
|
+-- annotations/
|   +-- entities.json
|   +-- measurements.json
|
+-- derived/
|   +-- geometry-candidates.json
|
+-- verification/
|   +-- as-built.json
|
+-- quality/
    +-- capture-quality.json
    +-- benchmark-observations.json
```

Not every optional directory exists in every bundle. Every file other than `manifest.json` must be declared by the manifest in v1.

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

## 11. Advanced workflow payloads

Optional feature payloads committed through the supplemental-document path. Each is reserved-path-bound (media type / producer / provenance class / role pinned) but not schema-owned, matching the `session/coordinate-space-policy.json` precedent; producers keep the wire contract stable by validating every decode through the model initializers.

| Path | Producer | Provenance | Role | Purpose |
|---|---|---|---|---|
| `session/capture-task-plan.json` | `htdt_plan` | `imported_reference` | canonical | Imported HTDT capture task plan, persisted verbatim (#240); a workflow request, never capture truth. |
| `session/task-plan-status.json` | `capture_session` | `capture_app_derived` | canonical | Per-item plan outcomes (pending/completed/skipped/unavailable) before finalization, keyed to `plan_sha256` (#240). |
| `session/connected-spaces.json` | `capture_session` | `capture_app_derived` | canonical | Connected room/region segments and explicit portal relationships sharing the revision's bound coordinate space (#222). |
| `evidence/reference-targets.json` | `reference_target_capture` | `capture_app_derived` | canonical | Declared fiducial/reference targets with explicit dimension authority, evidence-linked observations, and advisory residuals (#227). |
| `derived/geometry-candidates.json` | `derived_geometry` | `capture_app_derived` | derived | Persisted derived-geometry candidates: algorithm/version, source space, source evidence refs, source mode, bounded contours, confidence/ambiguity diagnostics, fusion window (#249). Role `derived` requires non-empty `source_refs`. |
| `verification/as-built.json` | `asbuilt_verification` | `capture_app_derived` | canonical | As-built verification: immutable plan identity, explicit `captureWorld -> planned scene` alignment authority, per-item observed deviations (#293). |
