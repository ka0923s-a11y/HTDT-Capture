# Capture Bundle v1 schemas

These schemas describe HTDT-Capture-owned JSON records.

Schema family:

- `manifest.schema.json`
- `session.schema.json`
- `device.schema.json`
- `capabilities.schema.json`
- `timing.schema.json`
- `frame.schema.json`
- `mesh-anchors.schema.json`
- `entities.schema.json`
- `measurements.schema.json`
- `quality.schema.json`
- `capture-advisory.schema.json` — derived `quality/capture-advisory.json`: bounded advisory diagnostics (End coverage, task completeness, RoomPlan guidance, mesh lifecycle, depth sufficiency, conflicts, geometry consistency). `capture_app_derived`, non-canonical.
- `authority-dependencies.schema.json` — derived `derived/authority-dependencies.json`: the generic external-authority dependency manifest (HTDT-Capture issue #337). Each dependency declares `kind`, exact `authority_id`/`authority_version`/`authority_sha256`, `required`, optional `resolution_context` (portable make/model/serial + catalog-identity hints for resolution on another HTDT instance), and optional `embedded_ref` for a bundle-embedded authority copy. Kinds: `equipment_definition` (entity `equipment_ref` targets), `layout_profile` (entity `role_binding` targets, #315), `task_plan`, `calibration_asset`, `manufacturer_documentation`, `floor_plan`, `tolerance_profile`.
- `advisory-notes.schema.json` (derived `advisory/operator-advisories.json` payload)
- `room-reference-frame.schema.json`
- `coordinate-space-policy.schema.json`
- `connected-spaces.schema.json`
- `capture-task-plan.schema.json` — imported `session/capture-task-plan.json` contract
- `task-plan-status-1.0.0.schema.json` / `task-plan-status-1.1.0.schema.json` — `session/task-plan-status.json`; 1.1.0 adds typed `fulfillment` links (#354)
- `entities-1.1.0.schema.json` — `annotations/entities.json` v1.1.0; adds `relations[]` (#333), `lineage` (#303), and enforces the open-token namespace policy (#344)
- `measurements-1.1.0.schema.json` — `annotations/measurements.json` v1.1.0; adds `uncertainty`/`lineage` (#304, #334)
- `as-built-verification-1.0.0.schema.json` / `as-built-verification-1.1.0.schema.json` — `verification/as-built.json`; 1.1.0 adds `indeterminate`, `residual_m`, and observation `uncertainty` (#356)
- `derived-geometry-candidates.schema.json` — `derived/geometry-candidates.json`
- `equipment-identity.schema.json` — `derived/equipment-identity.json`
- `reference-targets.schema.json` — `evidence/reference-targets.json`
- `opening-review.schema.json`
- `support-matrix.json` — the payload-version contract (#332): per-family emitted/read versions, document keys, and external-authority paths. Both validators dispatch `schema_version` through this matrix; versions not listed are rejected with a supported-version diagnostic.

`entities.schema.json` notes: `entity.role_binding` (#315) is the logical role assignment — `{profile_id, profile_version, role_id}` binding the physical `channel_role` token to a versioned speaker-layout/profile vocabulary. Entities written before the contract have no `role_binding` (nil → unbound/legacy). A missing required authority dependency fails the declared capability deterministically; unresolved optional dependencies never fail bundle integrity.

The reference bundle validator additionally enforces constraints that JSON Schema cannot safely express alone, including canonical JSON bytes, archive path safety, duplicate/case-colliding entries, SHA-256/length validation, expansion limits, and declared-vs-present payload equality.

The Capture Bundle v1 path collision key is `NFC(path)` followed by full Unicode case folding (Python `unicodedata.normalize("NFC", path).casefold()`; Swift `precomposedStringWithCanonicalMapping` + `folding(options: [.caseInsensitive])`). Distinct logical paths sharing a key are rejected. `path-collision-vectors.json` holds the shared contract vectors consumed by both validators.

All IDs use canonical lowercase UUID text. Current fixtures use UUIDv4-style values.
