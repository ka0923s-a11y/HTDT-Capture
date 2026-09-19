# HTDT Capture Bundle validator

Run:

```bash
python tools/bundle_validator/validator.py samples/minimal-capture
```

Validate a frozen digest:

```bash
python tools/bundle_validator/validator.py samples/minimal-capture \
  --expect-digest 1e29f755ce8f3557de60fa45f2c01a81936d3eca8db510cae795ba58170f035f
```

The reference validator is intentionally dependency-free in Phase 0.

It validates the bundle-level contract and safety boundary. It is not yet a complete generic JSON-Schema engine for every payload type.
