# ADR-0004: Capture data at-rest protection and backup policy

Status: Accepted  
Date: 2026-09-21

## Context

Room imagery, scene depth, reconstructed mesh, measurements, and annotations under `Application Support/HTDTCapture` are sensitive local data. The implementation plan states that working data should not be implicitly synchronized to cloud backup unless explicitly designed and disclosed, and review found no explicit, testable at-rest policy (legacy bolph71656-ai/HTDT-Capture#136, legacy bolph71656-ai/HTDT-Capture#166).

Platform defaults are not a contract: a build or provisioning change could silently alter at-rest behavior.

## Decision

Two independent controls are applied at creation and verified by reading the value back; failures surface to the operator rather than being silently ignored (`CaptureStoragePolicy` in `PersistedCaptureInventory.swift`).

- **Data Protection (legacy bolph71656-ai/HTDT-Capture#166):** every app-owned capture root (`HTDTCapture/`, `working/`, `finalized/`, `exports/`) and every `working/<uuid>` revision directory is set to `FileProtectionType.completeUntilFirstUserAuthentication`. iOS propagates a directory's default protection class to children created inside it, and a rename/move preserves the moved item's class, so a revision promoted from `working/` into `finalized/` keeps the same class without a second transaction.
- **Backup exclusion (legacy bolph71656-ai/HTDT-Capture#136):** only the transient `working/` root and each `working/<uuid>` revision carry `isExcludedFromBackupKey`. `finalized/` and `exports/` are *not* excluded: they hold user-facing artifacts that remain eligible for the platform's user-managed backup, and must not silently inherit the transient-working policy.

The capture root and the three lifecycle roots are (re)created and re-marked at host init; each new `working/<uuid>` is marked when its working-set store is created.

## Consequences

- `.completeUntilFirstUserAuthentication` keeps capture writes working while the device is locked after first unlock; `.complete` would break an in-flight scan if the device locked mid-capture.
- Orphaned working revisions that survive process death remain both backup-excluded and protected, and are surfaced by the startup inventory for bounded cleanup (legacy bolph71656-ai/HTDT-Capture#137).
- On non-iOS builds (package/test hosts) the protection class is an explicit no-op; backup exclusion still applies and is unit-tested.
- Protection, backup, and retention stay independent controls per the review contract.

## Alternatives considered

### `FileProtectionType.complete` for everything
Rejected: it denies file access while the device is locked, which can break an active capture or a deferred finalize when the device locks mid-session.

### Excluding the whole `HTDTCapture/` root from backup
Rejected: it would also exclude finalized revisions and exported archives — user-facing artifacts that the operator may legitimately want covered by device backup.

## Validation

`WorkingRevisionOrphanTests` verifies exclusion placement and idempotence. iOS attribute enforcement is a platform behavior exercised on device; no RDC or iCloud transfer test is required.

## Amendment (2026-09-22, legacy bolph71656-ai/HTDT-Capture#305)

Two corrections to the backup-exclusion decision; the Data Protection decision is unchanged.

- **Rename carries the exclusion flag.** Promotion moves a `working/<uuid>` directory — which carries `isExcludedFromBackup` — into `finalized/`, and a same-volume rename preserves extended attributes. Left alone, finalized data actually remained excluded regardless of this decision. The flag is now written explicitly in *both* directions: at promotion (`applyFinalizedRevisionPolicy`), at startup and on settings change over `finalized/`/`exports/` and their direct children (`applyFinalizedBackupPolicy`), and on each new export archive (`applyExportArchivePolicy`).
- **The finalized backup policy is operator-selectable.** `FinalizedBackupPolicy` defaults to `backupEligible` — identical at-rest behavior to this decision — and `excludedFromBackup` restricts finalized revisions and export archives to on-device app storage. The policy lives in the app-local settings document (`app-settings.json`), never inside a capture bundle, so changing it never reinterprets recorded capture authority. Share/Send-to-HTDT remains the only path data takes off the device, and is unrelated to backup.
- **No Info.plist exclusion exists.** iOS offers no manifest-level backup exclusion; the runtime `isExcludedFromBackup` resource flag is the only mechanism, so "Info.plist exclusion where appropriate" resolves to the flag plus settings disclosure. Verification of the flag now reads the `com.apple.metadata:com_apple_backup_excludeItem` extended attribute directly: `URL.resourceValues` can report the in-memory value even when the attribute write did not persist.
