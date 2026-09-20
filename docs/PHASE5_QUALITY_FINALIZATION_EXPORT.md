# Phase 5 Quality, Finalization, and Export Implementation Record

Status: In progress  
Issue: #6

## Implemented

### Explicit capture-quality authority

Quality is represented as concrete diagnostics, not a scalar score.

The v1 evaluator records:

- tracking events;
- RoomPlan state;
- active mesh-anchor count;
- evidence-frame count;
- depth-evidence count;
- annotation completeness;
- measurement completeness;
- resource/persistence events;
- integrity state;
- benchmark references;
- versioned diagnostics.

The readiness result is derived from an explicit `CaptureQualityRequirements` ruleset. Missing requirements produce specific error diagnostics.

### Canonical manifest implementation

Swift implements Capture Bundle v1 canonical manifest bytes directly:

- UTF-8;
- NFC-only strings;
- UTF-8 lexical object-key ordering;
- no insignificant whitespace;
- defined JSON string escaping;
- integer-only manifest numbers;
- stable payload ordering.

The implementation is tested against the frozen Phase 0 bundle digest.

### Streamed hashing and local validation

Payload hashing uses incremental SHA-256 via `FileHandle` and CryptoKit rather than loading large payloads into memory.

The local directory validator checks:

- normalized relative paths;
- symlinks;
- case-colliding paths;
- file-count and byte limits;
- canonical manifest bytes;
- exact declared/present payload set;
- declared byte lengths;
- payload SHA-256;
- logical `bundle_digest`.

### Atomic finalization

Finalization is an explicit gate:

1. require a ready quality report with finalization integrity assertion;
2. scan the staging directory;
3. require exact payload declarations;
4. stream-hash payloads;
5. build canonical manifest;
6. write `manifest.json` last;
7. validate the complete staging bundle;
8. require same-volume promotion;
9. atomically move the directory to the finalized destination.

Existing destinations are never overwritten. If validation/promotion fails, the manifest is removed from the mutable staging directory.

The finalized revision API exposes no mutation operation.

### Review UI

A SwiftUI review surface displays:

- readiness;
- RoomPlan/mesh/evidence counts;
- annotation/measurement completeness;
- concrete diagnostics;
- integrity result and logical bundle digest.

The iOS host now derives quality directly from the persisted live working set.
The review surface exposes explicit diagnostics and only enables finalization
when the report is ready and the re-read working-set integrity preflight passes.

### Export type and app registration

The platform layer defines the project-owned UTI:

`com.hometheaterdigitaltwin.capture-bundle`

with filename extension:

`.htdtcapture`

The concrete iOS host target now declares that type and document association in
`App/Info.plist`.

### ZIP wrapper authority

ZIP bytes are not logical identity. The reference archiver validates the finalized directory first, creates a ZIP-compatible wrapper, validates the archive, and requires the archive `bundle_digest` to equal the source directory digest before atomic promotion.

The Swift core now also provides a dependency-free native ZIP_STORED exporter
and archive validator. It revalidates the finalized source, writes a bounded
classic-ZIP transport wrapper, reopens and validates local/central records plus
CRC/SHA/manifest semantics, requires the same logical bundle digest, and only
then atomically publishes the `.htdtcapture` file. Zip64-required exports fail
closed in this slice.

## Important integrity semantics

SHA-256 is used for content integrity and logical identity only. It is not a signature and does not authenticate the bundle author.

### Live host finalization

The concrete host now executes:

```text
reviewing
  -> re-read integrity preflight + quality evaluation
  -> validating
  -> persist quality/capture-quality.json
  -> canonical manifest + complete bundle validator
  -> same-volume atomic working -> finalized promotion
  -> finalized
```

The host does not enter `finalized` until the promoted directory validates and
its logical bundle digest matches the finalizer result.

## Remaining Phase 5 work

- connect live annotation/measurement authorities into the same working set;
- exercise finalization and export against a real captured-room working set;
- measure storage/thermal/backpressure behavior on device.

The archive attack boundary is now enforced both by the Phase 0 reference validator and by the native Swift import path.


See `docs/PHASE5_LIVE_QUALITY_FINALIZATION.md` for the integrity semantics and
request-binding details of the live finalization path.


### iOS share/export wiring

The concrete host now retains the exact `FinalizedCaptureRevision` after
successful atomic finalization.

From `finalized`, the user can prepare one validated
`.htdtcapture` archive. The host invokes the native archive exporter into the
app's Application Support export area, verifies the returned logical
`bundle_digest` against the finalized revision, and only then transitions to
`exported`.

In this state, `exported` means a validated share-ready archive exists. It does
not claim that an external destination accepted the file. SwiftUI `ShareLink`
hands the exact validated file URL to the system share sheet, where the user
chooses the actual destination.

Existing export destinations are not overwritten. A new capture revision gets a
new revision UUID and therefore a distinct archive path.


## Native untrusted archive import

The Swift core now has a staged importer for untrusted `.htdtcapture` files.

The importer intentionally supports only the same bounded classic
`ZIP_STORED` profile produced by the native exporter. Before any extraction it
requires the archive validator to pass. This rejects:

- absolute/traversal/backslash/NUL/non-NFC logical paths;
- duplicate or case-colliding entries;
- compression methods (including deflate), data descriptors and extra fields;
- Zip64 and unsupported classic-ZIP structures;
- file-count, per-file expanded-size and total expanded-size limit violations;
- CRC mismatch, manifest/payload mismatch, non-canonical manifest, unknown
  Capture Bundle schema and payload SHA-256 tamper.

Because compressed entries are not accepted, decompression-ratio attacks are
outside the accepted transport profile rather than being conditionally
expanded.

Extraction then occurs only into a unique sibling staging directory. The
resulting directory is independently scanned and validated again. Its logical
`bundle_digest` must equal the digest from the pre-extraction archive
validation. Only then is the complete directory atomically moved to the caller's
destination. Existing destinations are never overwritten, and failed imports
clean up the staging directory.
