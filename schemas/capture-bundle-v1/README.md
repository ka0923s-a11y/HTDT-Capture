# Capture Bundle v1 schemas

These schemas describe HTDT-Capture-owned JSON records.

Schema family:

- `manifest.schema.json`
- `session.schema.json`
- `device.schema.json`
- `capabilities.schema.json`
- `timing.schema.json`
- `entities.schema.json`
- `measurements.schema.json`
- `quality.schema.json`

The reference bundle validator additionally enforces constraints that JSON Schema cannot safely express alone, including canonical JSON bytes, archive path safety, duplicate/case-colliding entries, SHA-256/length validation, expansion limits, and declared-vs-present payload equality.

All IDs use canonical lowercase UUID text. Current fixtures use UUIDv4-style values.
