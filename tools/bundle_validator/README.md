# HTDT Capture Bundle validator

Run:

```bash
python tools/bundle_validator/validator.py samples/minimal-capture
```

Validate a frozen digest (the expected value is kept in
`samples/minimal-capture.expected-bundle-digest.txt`):

```bash
python tools/bundle_validator/validator.py samples/minimal-capture \
  --expect-digest "$(cat samples/minimal-capture.expected-bundle-digest.txt)"
```

The reference validator is intentionally dependency-free in Phase 0.

It validates the bundle-level contract and safety boundary. It is not yet a complete generic JSON-Schema engine for every payload type.
