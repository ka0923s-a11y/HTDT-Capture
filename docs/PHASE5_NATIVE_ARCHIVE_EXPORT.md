# Phase 5 Native Stored-ZIP Export

Date: 2026-09-20  
Issue: #6

## Purpose

This slice adds an app-native, dependency-free transport wrapper for an already
finalized Capture Bundle revision.

Logical identity remains the canonical `manifest.json` SHA-256. ZIP bytes are
transport only.

```text
finalized bundle directory
  -> BundleDirectoryValidator
  -> deterministic UTF-8 ZIP_STORED writer
  -> reopen archive
  -> local-header / central-directory / EOCD validation
  -> per-entry CRC-32
  -> canonical manifest decode
  -> payload byte length + SHA-256 validation
  -> logical bundle_digest equality
  -> atomic publish as .htdtcapture
```

## ZIP profile

The native writer uses a deliberately narrow ZIP profile:

- storage method only; no compression;
- UTF-8 entry names;
- no directory entries;
- no data descriptors;
- no archive comments;
- fixed DOS timestamp fields;
- file entries sorted by Capture Bundle UTF-8 logical path order.

This profile is compatible with the Phase 0 Python reference validator.

## Bounded size behavior

The current native writer intentionally implements classic ZIP only.

If entry count, file size, local-header offset, central-directory size, or total
archive size requires Zip64, export fails explicitly with
`archiveTooLargeForClassicZIP`.

This does not change Capture Bundle v1 logical limits and does not reduce what
can be finalized. It is a bounded transport limitation of this native export
slice. Zip64 support can be added without changing logical bundle identity.

## Validation and publication

The finalized source directory is validated before any archive is published.

The temporary archive is then reopened and independently checked for:

- exact local-header profile;
- normalized/collision-free entry paths;
- CRC-32 for every stored entry;
- matching central-directory records;
- exact EOCD counts/offsets;
- no trailing bytes;
- canonical Capture Bundle manifest;
- exact declared/present payload set;
- payload byte lengths and SHA-256 values.

Only when the archive logical bundle digest equals the finalized source digest
is the temporary file moved to the requested `.htdtcapture` destination.
Existing destinations are never overwritten.

## Remaining host/UI work

This slice provides the native export authority. A follow-up host/UI slice can
choose an export destination and invoke the iOS share sheet without changing
archive semantics.
