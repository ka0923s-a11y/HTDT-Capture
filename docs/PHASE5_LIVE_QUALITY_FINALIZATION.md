# Phase 5 Live Quality and Finalization Slice

Date: 2026-09-20  
Issue: #6

## Purpose

This slice connects the mutable live capture working set to the existing quality
and atomic finalization authorities without asserting integrity by fiat.

The authority chain is:

```text
live working set
  -> re-read integrity preflight
  -> CaptureQualityReport
  -> quality/capture-quality.json
  -> exact BundleFinalizationRequest
  -> canonical manifest
  -> complete directory validation
  -> same-volume atomic promotion
```

## Working-set integrity semantics

`BundleIntegrityStatus.pass` in the live quality report now means the current
mutable working set was re-read successfully and its typed evidence references
still match the bytes on disk.

The preflight checks:

- no pre-existing `manifest.json`;
- exact declared/present payload path set;
- every file is readable/hashable;
- raw RoomPlan byte count and SHA-256;
- processed RoomPlan byte count/SHA-256 and raw-source lineage;
- exact encoded mesh index equality;
- every mesh geometry hash referenced by that index;
- exact encoded frame descriptor equality;
- frame pixel byte count and SHA-256;
- depth/confidence byte counts and SHA-256 when present.

A failed preflight produces quality `integrity_status = fail`; it is not
converted into a passing assertion.

This preflight is distinct from finalized-bundle validation. The finalizer still
rehashes every payload, creates the canonical manifest, validates the complete
bundle including that manifest, and only then atomically promotes the revision.

## Quality payload

Only a quality report that is both:

- `ready_for_htdt_ingestion = true`; and
- `integrity_status = pass`

can be persisted as `quality/capture-quality.json` by the live working-set
store.

The quality payload itself is then included in the finalization declaration set
and hashed by the finalizer like every other payload.

## Finalization request binding

`CaptureWorkingSetFinalizationRequestBuilder` binds the exact working-set
revision identity, session/coordinate authorities, payload declarations,
quality report and app identity into `BundleFinalizationRequest`.

It fails closed when capture/coordinate authority or the persisted quality
payload is missing.

## Verification

Core tests exercise:

- complete raw RoomPlan + processed RoomPlan + mesh + frame working set;
- re-read integrity pass;
- ready quality derivation;
- quality payload persistence;
- atomic finalization;
- finalized bundle revalidation and logical bundle digest;
- post-write camera evidence tamper -> integrity failure -> not ready.


## iOS host integration

The host refreshes quality after both scan-end mesh/frame persistence and
RoomPlan postprocessing persistence. This makes callback ordering irrelevant:
the report becomes ready only once all required persisted authorities are
present and the re-read preflight passes.

The finalization control is disabled until the report is ready. On activation
the host:

1. transitions `reviewing -> validating`;
2. persists the exact ready quality report;
3. snapshots the updated declaration set;
4. creates a finalization request from the exact revision/session/coordinate
   authority;
5. atomically promotes the working directory under Application Support from
   `working/<revision-id>` to `finalized/<revision-id>`;
6. revalidates the promoted bundle;
7. transitions to `finalized` only when the returned and revalidated logical
   bundle digests agree.

A rejected commit does NOT move the host to `failed`. While the revision is
outside the finalized authority, the host returns to `reviewing` with a typed
`finalizeRejection` plan (`deferredThermal`, `deferredStorage`,
`qualityRegression`, `commitRejected`) and the spatial authority stays sealed —
non-spatial corrections remain possible in Details/annotation. A commit that
reached `validating` but whose revalidation could not confirm the digest is
adopted as "committed but unverified" with an explicit Re-validate affordance
(#185 FinalizationCommitPolicy). Only non-commit lifecycle failures move the
host to the typed failed state; those still preserve a reopenable draft where
the resource condition allows (#437).
