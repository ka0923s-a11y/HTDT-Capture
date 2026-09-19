# Adversarial bundle fixtures

Phase 0 keeps adversarial fixtures generated in `tools/bundle_validator/test_validator.py` so the repository does not store intentionally malformed archives as opaque binary blobs.

Covered cases:

- path traversal;
- absolute/backslash/non-normalized paths;
- duplicate archive entry;
- case-colliding paths;
- excessive compression ratio;
- undeclared payload;
- payload tamper;
- noncanonical manifest;
- unsupported schema version.

Additional archive attacks should be added as deterministic tests before importer behavior is broadened.
