# Phase 5 Quality, Finalization, and Export Implementation Record

Status: In progress  
Issue: #6

## Implemented in this slice

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

Swift now implements Capture Bundle v1 canonical manifest bytes directly:

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

### Export type

The platform layer defines the project-owned UTI:

`com.hometheaterdigitaltwin.capture-bundle`

with filename extension:

`.htdtcapture`

The actual app target must also declare the exported type and filename extension in its Info.plist/document-type configuration. Apple requires proprietary document types to be declared in the app bundle; the Swift UTType alone does not register the extension system-wide.

### ZIP wrapper authority

ZIP bytes are not logical identity. The reference archiver validates the finalized directory first, creates a ZIP-compatible wrapper, validates the archive, and requires the archive `bundle_digest` to equal the source directory digest before atomic promotion.

## Important integrity semantics

SHA-256 is used for content integrity and logical identity only. It is not a signature and does not authenticate the bundle author.

## Remaining Phase 5 work

- wire the review surface into a production iOS app target/navigation flow;
- register the UTI in the final app target Info.plist;
- invoke ZIP export from the iOS share/export UI;
- exercise finalization and export against a real captured room working set;
- measure storage/thermal/backpressure behavior on device.

The archive attack boundary remains enforced by the Phase 0 reference validator and adversarial tests.
