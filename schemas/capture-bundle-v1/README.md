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

The reference bundle validator additionally enforces constraints that JSON Schema cannot safely express alone, including canonical JSON bytes, archive path safety, duplicate/case-colliding entries, SHA-256/length validation, expansion limits, and declared-vs-present payload equality.

The Capture Bundle v1 path collision key is `NFC(path)` followed by full Unicode case folding (Python `unicodedata.normalize("NFC", path).casefold()`; Swift `precomposedStringWithCanonicalMapping` + `folding(options: [.caseInsensitive])`). Distinct logical paths sharing a key are rejected. `path-collision-vectors.json` holds the shared contract vectors consumed by both validators.

All IDs use canonical lowercase UUID text. Current fixtures use UUIDv4-style values.
