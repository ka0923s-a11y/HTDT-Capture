# ADR-0004: Capture data at-rest protection and backup policy

Status: Accepted  
Date: 2026-09-21

## Context

Room imagery, scene depth, reconstructed mesh, measurements, and annotations under `Application Support/HTDTCapture` are sensitive local data. The implementation plan states that working data should not be implicitly synchronized to cloud backup unless explicitly designed and disclosed, and review found no explicit, testable at-rest policy (#136, #166).

Platform defaults are not a contract: a build or provisioning change could silently alter at-rest behavior.

## Decision

Two independent controls are applied at creation and verified by reading the value back; failures surface to the operator rather than being silently ignored (`CaptureStoragePolicy` in `PersistedCaptureInventory.swift`).

- **Data Protection (#166):** every app-owned capture root (`HTDTCapture/`, `working/`, `finalized/`, `exports/`) and every `working/<uuid>` revision directory is set to `FileProtectionType.completeUntilFirstUserAuthentication`. iOS propagates a directory's default protection class to children created inside it, and a rename/move preserves the moved item's class, so a revision promoted from `working/` into `finalized/` keeps the same class without a second transaction.
- **Backup exclusion (#136):** only the transient `working/` root and each `working/<uuid>` revision carry `isExcludedFromBackupKey`. `finalized/` and `exports/` are *not* excluded: they hold user-facing artifacts that remain eligible for the platform's user-managed backup, and must not silently inherit the transient-working policy.

The capture root and the three lifecycle roots are (re)created and re-marked at host init; each new `working/<uuid>` is marked when its working-set store is created.

## Consequences

- `.completeUntilFirstUserAuthentication` keeps capture writes working while the device is locked after first unlock; `.complete` would break an in-flight scan if the device locked mid-capture.
- Orphaned working revisions that survive process death remain both backup-excluded and protected, and are surfaced by the startup inventory for bounded cleanup (#137).
- On non-iOS builds (package/test hosts) the protection class is an explicit no-op; backup exclusion still applies and is unit-tested.
- Protection, backup, and retention stay independent controls per the review contract.

## Alternatives considered

### `FileProtectionType.complete` for everything
Rejected: it denies file access while the device is locked, which can break an active capture or a deferred finalize when the device locks mid-session.

### Excluding the whole `HTDTCapture/` root from backup
Rejected: it would also exclude finalized revisions and exported archives — user-facing artifacts that the operator may legitimately want covered by device backup.

## Validation

`WorkingRevisionOrphanTests` verifies exclusion placement and idempotence. iOS attribute enforcement is a platform behavior exercised on device; no RDC or iCloud transfer test is required.
