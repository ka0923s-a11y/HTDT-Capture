# ADR-0002: Manifest-rooted integrity and canonical JSON

Status: Accepted  
Date: 2026-09-20

## Context

The capture bundle needs deterministic logical identity without depending on ZIP metadata or creating a recursive self-hash.

## Decision

- Every payload is declared in `manifest.json` with byte length and SHA-256.
- The manifest excludes its own digest.
- The manifest is serialized with Capture Bundle v1 canonical JSON.
- `bundle_digest = SHA256(canonical manifest bytes)`.
- ZIP bytes are not part of logical bundle identity.
- SHA-256 integrity is not a signature/authenticity authority.

## Consequences

Recompression or archive metadata changes do not change logical bundle identity when the manifest/payload bytes remain unchanged.

Manifest canonicalization becomes a compatibility contract and therefore has fixed test vectors.

## Alternatives considered

### Hash the ZIP
Rejected because ZIP metadata/compression choices would make logical identity unstable.

### Include manifest hash inside the manifest
Rejected because this is recursive.

### Separate checksum file as root
Rejected because it adds another root-object canonicalization problem without benefit.

## Validation

The reference validator and fixture tests must reproduce the expected manifest digest exactly.
