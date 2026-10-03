import Foundation

/// Errors raised by the persisted-capture inventory authority.
public enum PersistedCaptureInventoryError:
    Error,
    Sendable,
    Equatable
{
    /// The artifact did not resolve to a direct child of one of the
    /// app-owned capture roots, so removing it was refused.
    case unsafeArtifactLocation
    /// A directory or file inside the app-owned working root could not
    /// be proven to be an abandoned `<uuid>` revision or a stale
    /// `.tmp-*` writer file, so removing it was refused.
    case unsafeWorkingOrphanLocation
    /// A storage-protection attribute was applied without an error but
    /// did not verify back on the item.
    case storagePolicyVerificationFailed(String)
    /// Removing the derived export archive was refused because the
    /// canonical finalized copy could not be revalidated; deleting the
    /// archive would have stranded the revision's only local authority
    /// (issue bolph71656-ai/HTDT-Capture#251).
    case exportArchiveRemovalRequiresFinalizedCopy
}

/// Classifies a filesystem item that lives under an app-owned capture
/// root but could not be adopted as validated capture authority.
public enum PersistedCaptureArtifactKind:
    String,
    Sendable,
    Equatable
{
    /// A direct child directory of `finalized/`.
    case finalizedDirectory
    /// A `.htdtcapture` file inside `exports/`.
    case exportArchive
    /// Any other item: stray files, partial temporary output, symbolic
    /// links, or directories where an archive file is expected.
    case unexpectedItem
}

/// A filesystem item inside the app-owned capture roots that failed
/// validation or does not occupy the canonical location of its manifest
/// identity. Quarantined artifacts are reported to the user, never
/// silently adopted.
public struct PersistedCaptureQuarantinedArtifact:
    Sendable,
    Equatable,
    Identifiable
{
    public let kind: PersistedCaptureArtifactKind
    public let url: URL
    /// Deterministic diagnostic text explaining why the artifact was not
    /// adopted.
    public let reason: String

    public init(
        kind: PersistedCaptureArtifactKind,
        url: URL,
        reason: String
    ) {
        self.kind = kind
        self.url = url
        self.reason = reason
    }

    public var id: URL { url }
}

/// A validated persisted capture. Identity always comes from the
/// validated manifest, never from a directory or file name.
public struct PersistedCaptureRecord:
    Sendable,
    Equatable,
    Identifiable
{
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    public let finalizedAtUTC: String
    /// The validated `finalized/<capture_revision_id>` directory, or nil
    /// when only a validated export archive remains on disk.
    public let finalizedDirectory: URL?
    public let finalizedValidation: BundleValidationReport?
    /// The validated `exports/<capture_revision_id>.htdtcapture`
    /// archive. When the finalized directory is also present the
    /// archive's bundle digest was proven identical at scan time.
    public let exportArchive: URL?
    public let exportValidation: BundleValidationReport?
    /// Bytes retained on disk by the validated finalized directory at
    /// scan time; nil when no finalized copy exists (issue bolph71656-ai/HTDT-Capture#251).
    public let finalizedByteCount: Int64?
    /// Bytes retained on disk by the validated export archive at scan
    /// time; nil when no archive exists (issue bolph71656-ai/HTDT-Capture#251).
    public let exportArchiveByteCount: Int64?
    /// The manifest-declared parent revision (`parent_revision_id`),
    /// when the validated bundle declares one (issue bolph71656-ai/HTDT-Capture#396). This is the
    /// lineage edge the revision-fork graph is built from — bundle
    /// authority, never inferred from ordering or timestamps.
    public let parentRevisionID: CaptureRevisionID?

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        finalizedAtUTC: String,
        finalizedDirectory: URL?,
        finalizedValidation: BundleValidationReport?,
        exportArchive: URL?,
        exportValidation: BundleValidationReport?,
        finalizedByteCount: Int64? = nil,
        exportArchiveByteCount: Int64? = nil,
        parentRevisionID: CaptureRevisionID? = nil
    ) {
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.finalizedAtUTC = finalizedAtUTC
        self.finalizedDirectory = finalizedDirectory
        self.finalizedValidation = finalizedValidation
        self.exportArchive = exportArchive
        self.exportValidation = exportValidation
        self.finalizedByteCount = finalizedByteCount
        self.exportArchiveByteCount = exportArchiveByteCount
        self.parentRevisionID = parentRevisionID
    }

    public var id: CaptureRevisionID {
        captureRevisionID
    }

    /// Only a record that still carries a validated finalized bundle can
    /// be adopted as the host's current finalized revision.
    public var canOpen: Bool {
        finalizedDirectory != nil && finalizedValidation != nil
    }

    /// True when a validated export archive exists next to the finalized
    /// copy. The scan only ever attaches an archive whose bundle digest
    /// proved identical to the finalized bundle, so such an archive is
    /// fully derived data that can be removed independently and
    /// regenerated later (issue bolph71656-ai/HTDT-Capture#251).
    public var exportArchiveIsDerivedCopy: Bool {
        finalizedValidation != nil && exportArchive != nil
    }

    /// Total local bytes attributable to this revision: the finalized
    /// bundle plus the export archive when both exist (issue bolph71656-ai/HTDT-Capture#251).
    public var retainedByteCount: Int64 {
        (finalizedByteCount ?? 0) + (exportArchiveByteCount ?? 0)
    }

    /// Manifest-declared frame preview paths in stable frame-id order
    /// (issue bolph71656-ai/HTDT-Capture#219): `evidence/frames/<id>.preview.heic` entries the
    /// validated manifest carries — from the finalized bundle's report
    /// when present, otherwise the export archive's (their digests
    /// matched at scan time). Only declared previews are candidates —
    /// undeclared files on disk never count.
    public var declaredPreviewPaths: [String] {
        let files =
            finalizedValidation?.manifest.files
            ?? exportValidation?.manifest.files
            ?? []
        return files.map(\.path)
            .filter {
                $0.hasPrefix("evidence/frames/")
                    && $0.hasSuffix(".preview.heic")
            }
            .sorted()
    }

    /// A representative preview file for library thumbnails (issue
    /// legacy bolph71656-ai/HTDT-Capture#219): the first manifest-declared preview present under the
    /// validated finalized directory. nil when no preview payload was
    /// retained or only an export archive remains.
    public func representativePreviewFile() -> URL? {
        guard let directory = finalizedDirectory else {
            return nil
        }
        for path in declaredPreviewPaths {
            let url = path.split(separator: "/").reduce(directory) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            if (try? url.checkResourceIsReachable()) == true {
                return url
            }
        }
        return nil
    }

    /// Representative preview bytes for records whose only copy is
    /// the validated export archive (issue bolph71656-ai/HTDT-Capture#219): archive entries
    /// are stored uncompressed, so the preview payload is read out
    /// of the single entry's local header without decompressing the
    /// package. nil when the finalized directory exists (use
    /// `representativePreviewFile`) or no preview was retained.
    public func representativePreviewData() -> Data? {
        if let url = representativePreviewFile() {
            return try? Data(contentsOf: url)
        }
        guard finalizedDirectory == nil,
              let archive = exportArchive,
              let path = declaredPreviewPaths.first
        else { return nil }
        return StoredCaptureBundleArchiveReader.readEntry(
            archive: archive,
            path: path
        )
    }
}

/// Classifies a direct child of the app-owned `working/` root that a
/// prior process left behind.
public enum PersistedCaptureWorkingOrphanKind:
    String,
    Sendable,
    Equatable
{
    /// A `working/<uuid>` revision directory whose process died before
    /// the revision was finalized or discarded. It is never resumable:
    /// the live AR coordinate authority it was bound to ended with the
    /// process.
    case abandonedRevision
    /// A `.tmp-*` scratch file left at the working root by an
    /// interrupted atomic writer.
    case staleWriterTempFile
}

/// An abandoned item inside the app-owned `working/` root, surfaced for
/// explicit bounded cleanup. Removal is proven against the resolved
/// path, never against this value's declared kind.
public struct PersistedCaptureWorkingOrphan:
    Sendable,
    Equatable,
    Identifiable
{
    public let kind: PersistedCaptureWorkingOrphanKind
    public let url: URL
    /// Best-effort total of bytes still retained on disk, so cleanup
    /// decisions and failure reports carry a concrete size.
    public let retainedBytes: Int64

    public init(
        kind: PersistedCaptureWorkingOrphanKind,
        url: URL,
        retainedBytes: Int64
    ) {
        self.kind = kind
        self.url = url
        self.retainedBytes = retainedBytes
    }

    public var id: URL { url }
}

/// An artifact that could not be removed during a deletion transaction,
/// together with the precise reason it stayed on disk.
public struct PersistedCaptureRemainingArtifact:
    Sendable,
    Equatable
{
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

/// One retained file inside an inspected working-root orphan
/// (issue bolph71656-ai/HTDT-Capture#224), reported with its size so cleanup decisions carry
/// concrete evidence.
public struct PersistedCaptureOrphanEntry:
    Sendable,
    Equatable
{
    /// Path relative to the orphan root.
    public let relativePath: String
    public let byteCount: Int64

    public init(relativePath: String, byteCount: Int64) {
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

/// Bounded listing of what an abandoned working revision or stale
/// writer file still retains on disk (issue bolph71656-ai/HTDT-Capture#224). Purely observational
/// — it never resurrects the revision as resumable authority.
public struct PersistedCaptureOrphanInspection:
    Sendable,
    Equatable
{
    public let url: URL
    public let entries: [PersistedCaptureOrphanEntry]
    public let enumerationFailures: [String]

    public init(
        url: URL,
        entries: [PersistedCaptureOrphanEntry],
        enumerationFailures: [String] = []
    ) {
        self.url = url
        self.entries = entries
        self.enumerationFailures = enumerationFailures
    }

    public var totalByteCount: Int64 {
        entries.reduce(0) { $0 + $1.byteCount }
    }
}

/// The exact outcome of a delete-local-capture transaction. A partial
/// result never reports success: anything left on disk is listed in
/// `remaining` with the reason it stayed.
public struct PersistedCaptureDeletionResult:
    Sendable,
    Equatable
{
    public let captureRevisionID: CaptureRevisionID
    public let removed: [URL]
    public let remaining: [PersistedCaptureRemainingArtifact]

    public init(
        captureRevisionID: CaptureRevisionID,
        removed: [URL],
        remaining: [PersistedCaptureRemainingArtifact]
    ) {
        self.captureRevisionID = captureRevisionID
        self.removed = removed
        self.remaining = remaining
    }

    public var succeeded: Bool {
        remaining.isEmpty
    }
}

/// The outcome of one deterministic scan of the app-owned capture
/// roots: validated captures, quarantined artifacts, and root-level
/// enumeration failures.
public struct PersistedCaptureInventoryResult:
    Sendable,
    Equatable
{
    public let captures: [PersistedCaptureRecord]
    public let quarantinedArtifacts:
        [PersistedCaptureQuarantinedArtifact]
    /// Non-resumable children of `working/` left by a prior process:
    /// abandoned `<uuid>` revision directories and stale `.tmp-*`
    /// writer files. They carry no live coordinate authority and are
    /// surfaced for bounded deletion.
    public let orphanedWorkingArtifacts:
        [PersistedCaptureWorkingOrphan]
    /// `working/<uuid>` revisions whose durable phase marker proves an
    /// accepted End boundary (issue bolph71656-ai/HTDT-Capture#297). They reopen into a spatially
    /// sealed Review — never into live capture.
    public let recoverableDrafts: [RecoverableWorkingRevision]
    public let enumerationFailures: [String]

    public init(
        captures: [PersistedCaptureRecord] = [],
        quarantinedArtifacts:
            [PersistedCaptureQuarantinedArtifact] = [],
        orphanedWorkingArtifacts:
            [PersistedCaptureWorkingOrphan] = [],
        recoverableDrafts: [RecoverableWorkingRevision] = [],
        enumerationFailures: [String] = []
    ) {
        self.captures = captures
        self.quarantinedArtifacts = quarantinedArtifacts
        self.orphanedWorkingArtifacts = orphanedWorkingArtifacts
        self.recoverableDrafts = recoverableDrafts
        self.enumerationFailures = enumerationFailures
    }

    public var isEmpty: Bool {
        captures.isEmpty
            && quarantinedArtifacts.isEmpty
            && orphanedWorkingArtifacts.isEmpty
            && recoverableDrafts.isEmpty
            && enumerationFailures.isEmpty
    }

    /// Total bytes retained by every inventoried artifact: validated
    /// finalized bundles, validated export archives (counted separately
    /// so storage UX can show the duplicate-derived share), and
    /// non-resumable working orphans (issue bolph71656-ai/HTDT-Capture#251). Quarantined items
    /// are not sized here; each carries its own deletion path.
    public var totalRetainedBytes: Int64 {
        captures.reduce(0) { $0 + $1.retainedByteCount }
            + orphanedWorkingArtifacts.reduce(0) {
                $0 + $1.retainedBytes
            }
    }
}

/// Deterministic inventory and deletion authority for the app-owned
/// persisted capture roots:
///
///     <captureRoot>/finalized/<capture_revision_id>/
///     <captureRoot>/exports/<capture_revision_id>.htdtcapture
///
/// Every candidate is validated with the same validators the capture
/// pipeline uses (`BundleDirectoryValidator` for directories,
/// `StoredCaptureBundleArchiveValidator` for stored archives). Revision
/// identity always comes from the validated manifest; directory and
/// file names only decide whether an artifact occupies its canonical
/// slot. This type never resurrects `working/` scans: an interrupted
/// scan leaves no live AR coordinate authority to resume into.
public struct PersistedCaptureInventory: Sendable {
    public let finalizedRoot: URL
    public let exportsRoot: URL
    /// The app-owned `working/` root. Optional so an inventory built on
    /// explicit roots without a working root simply enumerates no
    /// orphans; the canonical `captureRoot` initializer always sets it.
    public let workingRoot: URL?
    public let limits: BundleFilesystemLimits

    public init(
        captureRoot: URL,
        limits: BundleFilesystemLimits = .init()
    ) {
        self.init(
            finalizedRoot: captureRoot.appendingPathComponent(
                "finalized",
                isDirectory: true
            ),
            exportsRoot: captureRoot.appendingPathComponent(
                "exports",
                isDirectory: true
            ),
            workingRoot: captureRoot.appendingPathComponent(
                "working",
                isDirectory: true
            ),
            limits: limits
        )
    }

    public init(
        finalizedRoot: URL,
        exportsRoot: URL,
        workingRoot: URL? = nil,
        limits: BundleFilesystemLimits = .init()
    ) {
        self.finalizedRoot = finalizedRoot
        self.exportsRoot = exportsRoot
        self.workingRoot = workingRoot
        self.limits = limits
    }

    /// Enumerates both capture roots and validates every candidate.
    /// A validated finalized directory becomes a record; a validated
    /// archive joins the record of the same manifest revision when its
    /// bundle digest matches, or forms an export-only record when no
    /// finalized directory exists. Anything else is quarantined with a
    /// precise reason instead of being adopted.
    ///
    /// The `working/` root is inventoried without any validation or
    /// resume attempt: a `<uuid>`-named directory is an abandoned
    /// working revision whose AR coordinate authority died with the
    /// prior process, and a `.tmp-*` file is a stale writer artifact.
    /// `activeRevisionID` positively excludes the live in-process
    /// revision so it can never be surfaced as an orphan; anything else
    /// unexpected is quarantined, not recursively deleted.
    public func scan(
        activeRevisionID: CaptureRevisionID? = nil
    ) -> PersistedCaptureInventoryResult {
        var captures: [CaptureRevisionID: PersistedCaptureRecord] = [:]
        var order: [CaptureRevisionID] = []
        var quarantined:
            [PersistedCaptureQuarantinedArtifact] = []
        var orphanedWorking:
            [PersistedCaptureWorkingOrphan] = []
        var recoverableDrafts: [RecoverableWorkingRevision] = []
        var enumerationFailures: [String] = []

        for child in children(
            of: finalizedRoot,
            failures: &enumerationFailures
        ) {
            switch childKind(child) {
            case .directory:
                let report: BundleValidationReport
                do {
                    report = try BundleDirectoryValidator.validate(
                        root: child,
                        limits: limits
                    )
                } catch {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "finalized bundle validation failed: "
                                + Self.diagnostic(error)
                        )
                    )
                    continue
                }

                let revisionID =
                    report.manifest.captureRevisionID
                guard child.lastPathComponent
                        == revisionID.description
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "validated manifest revision "
                                + revisionID.description
                                + " is stored under a non-canonical directory name"
                        )
                    )
                    continue
                }
                guard captures[revisionID] == nil else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "duplicate finalized revision "
                                + revisionID.description
                        )
                    )
                    continue
                }

                captures[revisionID] = PersistedCaptureRecord(
                    captureRevisionID: revisionID,
                    captureSeriesID:
                        report.manifest.captureSeriesID,
                    finalizedAtUTC:
                        report.manifest.finalizedAtUTC,
                    finalizedDirectory: finalizedDirectory(
                        for: revisionID
                    ),
                    finalizedValidation: report,
                    exportArchive: nil,
                    exportValidation: nil,
                    finalizedByteCount: retainedBytes(
                        of: child,
                        failures: &enumerationFailures
                    ),
                    parentRevisionID:
                        report.manifest.parentRevisionID
                )
                order.append(revisionID)

            case .symbolicLink:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "symbolic-link entries are never adopted"
                    )
                )
            case .regularFile, .other, .unreadable:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "not a finalized revision directory"
                    )
                )
            }
        }

        for child in children(
            of: exportsRoot,
            failures: &enumerationFailures
        ) {
            switch childKind(child) {
            case .regularFile:
                guard child.pathExtension == "htdtcapture"
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .unexpectedItem,
                            url: child,
                            reason:
                                "unrecognized item inside the exports root"
                        )
                    )
                    continue
                }

                let report: BundleValidationReport
                do {
                    report =
                        try StoredCaptureBundleArchiveValidator
                            .validate(
                                archive: child,
                                limits: limits
                            )
                } catch {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .exportArchive,
                            url: child,
                            reason:
                                "export archive validation failed: "
                                + Self.diagnostic(error)
                        )
                    )
                    continue
                }

                let revisionID =
                    report.manifest.captureRevisionID
                guard child.lastPathComponent
                        == revisionID.description
                            + ".htdtcapture"
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .exportArchive,
                            url: child,
                            reason:
                                "validated manifest revision "
                                + revisionID.description
                                + " is stored under a non-canonical archive name"
                        )
                    )
                    continue
                }

                let archiveBytes = retainedBytes(
                    of: child,
                    failures: &enumerationFailures
                )
                if let existing = captures[revisionID] {
                    guard existing.finalizedValidation?
                        .bundleDigest == report.bundleDigest
                    else {
                        quarantined.append(
                            PersistedCaptureQuarantinedArtifact(
                                kind: .exportArchive,
                                url: child,
                                reason:
                                    "archive bundle digest does not match the finalized revision"
                            )
                        )
                        continue
                    }
                    captures[revisionID] =
                        PersistedCaptureRecord(
                            captureRevisionID:
                                existing.captureRevisionID,
                            captureSeriesID:
                                existing.captureSeriesID,
                            finalizedAtUTC:
                                existing.finalizedAtUTC,
                            finalizedDirectory:
                                existing.finalizedDirectory,
                            finalizedValidation:
                                existing.finalizedValidation,
                            exportArchive: exportArchiveURL(
                                for: revisionID
                            ),
                            exportValidation: report,
                            finalizedByteCount:
                                existing.finalizedByteCount,
                            exportArchiveByteCount: archiveBytes,
                            parentRevisionID:
                                existing.parentRevisionID
                        )
                } else {
                    captures[revisionID] =
                        PersistedCaptureRecord(
                            captureRevisionID: revisionID,
                            captureSeriesID:
                                report.manifest
                                    .captureSeriesID,
                            finalizedAtUTC:
                                report.manifest
                                    .finalizedAtUTC,
                            finalizedDirectory: nil,
                            finalizedValidation: nil,
                            exportArchive: exportArchiveURL(
                                for: revisionID
                            ),
                            exportValidation: report,
                            finalizedByteCount: nil,
                            exportArchiveByteCount: archiveBytes,
                            parentRevisionID:
                                report.manifest.parentRevisionID
                        )
                    order.append(revisionID)
                }

            case .symbolicLink:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "symbolic-link entries are never adopted"
                    )
                )
            case .directory, .other, .unreadable:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "not an export archive file"
                    )
                )
            }
        }

        // Abandoned-working-revision policy: enumerate only direct
        // children of the app-owned working root, skip the live
        // revision explicitly named by the caller, and never treat a
        // prior-process directory as resumable capture authority.
        if let workingRoot {
            for child in children(
                of: workingRoot,
                failures: &enumerationFailures
            ) {
                let name = child.lastPathComponent
                if let activeRevisionID,
                   name == activeRevisionID.description
                {
                    continue
                }

                switch childKind(child) {
                case .directory:
                    guard
                        let revisionID = CaptureRevisionID(
                            canonicalString: name
                        )
                    else {
                        quarantined.append(
                            PersistedCaptureQuarantinedArtifact(
                                kind: .unexpectedItem,
                                url: child,
                                reason:
                                    "unrecognized directory inside the working root; no ownership proof"
                            )
                        )
                        continue
                    }
                    // Issue bolph71656-ai/HTDT-Capture#297: a `working/<uuid>` directory carrying a
                    // durable end-accepted phase marker is a recoverable
                    // draft, not an abandoned revision. The marker is
                    // the only ownership proof — absent, undecodable,
                    // `live_scan_incomplete`, or practice-mode entries
                    // all stay on the non-resumable orphan path. One
                    // exception: a `live_scan_incomplete` marker next to
                    // the complete durable End payload set can only be a
                    // lost marker-flip write — the atomic End batch
                    // already committed, so the directory stays
                    // recoverable and restore heals the marker.
                    if let state = CaptureWorkingSetStore
                        .peekRevisionPhase(workingRevisionURL: child),
                       !state.practice,
                       (
                           state.phase.isRecoverableDraft
                           || (
                               state.phase == .liveScanIncomplete
                                   && CaptureWorkingSetStore
                                       .endTransactionEvidencePresent(
                                           workingRevisionURL: child
                                       )
                           )
                       )
                    {
                        recoverableDrafts.append(
                            RecoverableWorkingRevision(
                                url: child,
                                revisionID: revisionID,
                                phase: state.phase,
                                captureSessionID:
                                    state.captureSessionID,
                                coordinateSpaceID:
                                    state.coordinateSpaceID,
                                retainedBytes: retainedBytes(
                                    of: child,
                                    failures: &enumerationFailures
                                ),
                                endEvidenceCommitted:
                                    state.phase
                                        == .liveScanIncomplete
                            )
                        )
                        continue
                    }
                    orphanedWorking.append(
                        PersistedCaptureWorkingOrphan(
                            kind: .abandonedRevision,
                            url: child,
                            retainedBytes: retainedBytes(
                                of: child,
                                failures: &enumerationFailures
                            )
                        )
                    )
                case .regularFile:
                    guard name.hasPrefix(".tmp-") else {
                        quarantined.append(
                            PersistedCaptureQuarantinedArtifact(
                                kind: .unexpectedItem,
                                url: child,
                                reason:
                                    "unrecognized item inside the working root"
                            )
                        )
                        continue
                    }
                    orphanedWorking.append(
                        PersistedCaptureWorkingOrphan(
                            kind: .staleWriterTempFile,
                            url: child,
                            retainedBytes: retainedBytes(
                                of: child,
                                failures: &enumerationFailures
                            )
                        )
                    )
                case .symbolicLink:
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .unexpectedItem,
                            url: child,
                            reason:
                                "symbolic-link entries are never adopted"
                        )
                    )
                case .other, .unreadable:
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .unexpectedItem,
                            url: child,
                            reason:
                                "unreadable item inside the working root"
                        )
                    )
                }
            }
        }

        let sorted = order
            .compactMap { captures[$0] }
            .sorted { lhs, rhs in
                if lhs.finalizedAtUTC != rhs.finalizedAtUTC {
                    return lhs.finalizedAtUTC
                        > rhs.finalizedAtUTC
                }
                return lhs.captureRevisionID.description
                    < rhs.captureRevisionID.description
            }
        return PersistedCaptureInventoryResult(
            captures: sorted,
            quarantinedArtifacts: quarantined.sorted {
                $0.url.path < $1.url.path
            },
            orphanedWorkingArtifacts: orphanedWorking.sorted {
                $0.url.path < $1.url.path
            },
            recoverableDrafts: recoverableDrafts.sorted {
                $0.url.path < $1.url.path
            },
            enumerationFailures: enumerationFailures
        )
    }

    /// Revalidates the canonical finalized directory and matching
    /// export archive for `captureRevisionID` and returns a fresh
    /// record. Returns nil when the finalized revision can no longer
    /// be proven (missing, invalid, or manifest identity mismatch). A
    /// stale or missing archive never blocks adoption; it simply
    /// leaves the record without an export slot.
    public func validatedRecord(
        captureRevisionID: CaptureRevisionID
    ) -> PersistedCaptureRecord? {
        let directory = finalizedDirectory(
            for: captureRevisionID
        )
        guard let report = try? BundleDirectoryValidator.validate(
            root: directory,
            limits: limits
        ), report.manifest.captureRevisionID == captureRevisionID
        else {
            return nil
        }

        var exportArchive: URL?
        var exportValidation: BundleValidationReport?
        let archive = exportArchiveURL(
            for: captureRevisionID
        )
        if FileManager.default.fileExists(atPath: archive.path),
           let archiveReport =
            try? StoredCaptureBundleArchiveValidator.validate(
                archive: archive,
                limits: limits
            ),
           archiveReport.manifest.captureRevisionID
                == captureRevisionID,
           archiveReport.bundleDigest == report.bundleDigest
        {
            exportArchive = archive
            exportValidation = archiveReport
        }

        var sizingFailures: [String] = []
        return PersistedCaptureRecord(
            captureRevisionID: captureRevisionID,
            captureSeriesID: report.manifest.captureSeriesID,
            finalizedAtUTC: report.manifest.finalizedAtUTC,
            finalizedDirectory: directory,
            finalizedValidation: report,
            exportArchive: exportArchive,
            exportValidation: exportValidation,
            finalizedByteCount: retainedBytes(
                of: directory,
                failures: &sizingFailures
            ),
            exportArchiveByteCount: exportArchive.map {
                retainedBytes(
                    of: $0,
                    failures: &sizingFailures
                )
            },
            parentRevisionID: report.manifest.parentRevisionID
        )
    }

    /// Removes only the derived export archive for one revision while
    /// retaining the canonical finalized bundle (issue bolph71656-ai/HTDT-Capture#251). Refused
    /// when the finalized directory cannot be revalidated as belonging
    /// to `captureRevisionID`: without proven canonical bytes on disk,
    /// deleting the last remaining copy would silently destroy the
    /// revision's only local authority. The archive itself is derived
    /// data — it can always be regenerated from the finalized bundle —
    /// so its removal never requires revalidating its own contents.
    /// Returns true when the archive slot is now empty.
    @discardableResult
    public func deleteExportArchive(
        captureRevisionID: CaptureRevisionID
    ) throws -> Bool {
        let directory = finalizedDirectory(
            for: captureRevisionID
        )
        guard let report = try? BundleDirectoryValidator.validate(
            root: directory,
            limits: limits
        ), report.manifest.captureRevisionID == captureRevisionID
        else {
            throw PersistedCaptureInventoryError
                .exportArchiveRemovalRequiresFinalizedCopy
        }

        let archive = exportArchiveURL(
            for: captureRevisionID
        )
        guard FileManager.default.fileExists(atPath: archive.path)
        else {
            return false
        }
        try FileManager.default.removeItem(at: archive)
        return true
    }

    /// Bounded inspection of a working-root orphan (issue bolph71656-ai/HTDT-Capture#224):
    /// enumerates the retained payload paths and byte sizes so the
    /// operator can see what the failed/abandoned revision captured
    /// before deciding to export diagnostics or discard. Paths are
    /// reported relative to the orphan root; enumeration is capped so
    /// a pathological directory cannot stall the UI.
    public func inspectWorkingOrphan(
        _ orphan: PersistedCaptureWorkingOrphan,
        maxEntries: Int = 512
    ) throws -> PersistedCaptureOrphanInspection {
        guard let workingRoot else {
            throw PersistedCaptureInventoryError
                .unsafeWorkingOrphanLocation
        }
        let resolved = orphan.url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent()
            == workingRoot
                .standardizedFileURL
                .resolvingSymlinksInPath()
        else {
            throw PersistedCaptureInventoryError
                .unsafeWorkingOrphanLocation
        }

        var entries: [PersistedCaptureOrphanEntry] = []
        var failures: [String] = []
        switch childKind(resolved) {
        case .regularFile:
            let values = try? resolved.resourceValues(
                forKeys: [.fileSizeKey]
            )
            entries.append(
                PersistedCaptureOrphanEntry(
                    relativePath: resolved.lastPathComponent,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
            )
        case .directory:
            if let enumerator = FileManager.default.enumerator(
                at: resolved,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                ],
                options: []
            ) {
                for case let file as URL in enumerator {
                    guard entries.count < maxEntries else {
                        failures.append(
                            "inspection truncated at \(maxEntries) entries"
                        )
                        break
                    }
                    let values = try? file.resourceValues(
                        forKeys: [
                            .fileSizeKey,
                            .isRegularFileKey,
                        ]
                    )
                    guard values?.isRegularFile == true else {
                        continue
                    }
                    let rootPath =
                        resolved.standardizedFileURL.path
                    var relative = file.standardizedFileURL.path
                    if relative.hasPrefix(rootPath + "/") {
                        relative = String(
                            relative.dropFirst(rootPath.count + 1)
                        )
                    }
                    entries.append(
                        PersistedCaptureOrphanEntry(
                            relativePath: relative,
                            byteCount: Int64(
                                values?.fileSize ?? 0
                            )
                        )
                    )
                }
            } else {
                failures.append(
                    "directory contents could not be enumerated"
                )
            }
        case .symbolicLink, .unreadable, .other:
            failures.append("item is not inspectable")
        }

        entries.sort { $0.relativePath < $1.relativePath }
        return PersistedCaptureOrphanInspection(
            url: orphan.url,
            entries: entries,
            enumerationFailures: failures
        )
    }

    /// Deletes the local copy of one revision: the canonical finalized
    /// directory and the canonical export archive. Candidate paths are
    /// always reconstructed inside the app-owned roots from the
    /// manifest-derived revision identity, never taken from stored
    /// path strings.
    ///
    /// The finalized directory is removed only after its manifest is
    /// reread and the declared `capture_revision_id` reconfirmed. A
    /// missing archive is fine. Partial failures never report success:
    /// everything left on disk is returned in `remaining` so it stays
    /// discoverable for retry.
    public func deleteCapture(
        captureRevisionID: CaptureRevisionID
    ) -> PersistedCaptureDeletionResult {
        let fileManager = FileManager.default
        var removed: [URL] = []
        var remaining:
            [PersistedCaptureRemainingArtifact] = []

        let directory = finalizedDirectory(
            for: captureRevisionID
        )
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            if !isDirectory.boolValue {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: directory,
                        reason:
                            "the finalized slot is not a directory; revision identity cannot be reconfirmed"
                    )
                )
            } else if let refusal =
                identityReconfirmationFailure(
                    directory: directory,
                    captureRevisionID: captureRevisionID
                )
            {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: directory,
                        reason: refusal
                    )
                )
            } else {
                do {
                    try fileManager.removeItem(at: directory)
                    removed.append(directory)
                } catch {
                    remaining.append(
                        PersistedCaptureRemainingArtifact(
                            url: directory,
                            reason:
                                "finalized directory removal failed: "
                                + Self.diagnostic(error)
                        )
                    )
                }
            }
        }

        // The archive path is the revision's own export slot inside the
        // app-owned exports root. It is derived wrapper data, not
        // capture authority, so whatever occupies the slot belongs to
        // this revision's deletion transaction.
        let archive = exportArchiveURL(
            for: captureRevisionID
        )
        if fileManager.fileExists(atPath: archive.path) {
            do {
                try fileManager.removeItem(at: archive)
                removed.append(archive)
            } catch {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: archive,
                        reason:
                            "export archive removal failed: "
                            + Self.diagnostic(error)
                    )
                )
            }
        }

        return PersistedCaptureDeletionResult(
            captureRevisionID: captureRevisionID,
            removed: removed,
            remaining: remaining
        )
    }

    /// Removes a previously quarantined artifact. Removal is refused
    /// unless the artifact resolves to a direct child of one of the
    /// app-owned capture roots, so deletion can never escape the
    /// capture roots through a fabricated or redirected path.
    ///
    /// Inside `working/` only leaf items (files, symbolic links, other
    /// non-directories) may leave through this path. Working
    /// directories require the abandoned-revision ownership proof in
    /// `removeWorkingOrphan`; anything else named like a directory is
    /// refused rather than recursively deleted.
    public func removeArtifact(
        _ artifact: PersistedCaptureQuarantinedArtifact
    ) throws {
        let resolved = artifact.url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let parent = resolved.deletingLastPathComponent()
        let resolvedWorking = workingRoot?
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let roots = [
            finalizedRoot
                .standardizedFileURL
                .resolvingSymlinksInPath(),
            exportsRoot
                .standardizedFileURL
                .resolvingSymlinksInPath(),
            resolvedWorking,
        ].compactMap { $0 }
        guard roots.contains(parent) else {
            throw PersistedCaptureInventoryError
                .unsafeArtifactLocation
        }
        if parent == resolvedWorking,
           childKind(resolved) == .directory
        {
            let name = resolved.lastPathComponent
            let isRevisionDirectory =
                CaptureRevisionID(canonicalString: name) != nil
            // `.rollback-<uuid>` siblings are the writer's own
            // crash-interrupted quarantine dirs — app-owned leftovers
            // the removal path must accept, not just revision UUIDs.
            let isWriterRollbackQuarantine =
                name.hasPrefix(".rollback-")
                    && UUID(
                        uuidString: String(name.dropFirst(10))
                    ) != nil
            guard isRevisionDirectory
                    || isWriterRollbackQuarantine
            else {
                throw PersistedCaptureInventoryError
                    .unsafeArtifactLocation
            }
        }
        try FileManager.default.removeItem(at: artifact.url)
    }

    /// Removes one abandoned item inside the app-owned `working/`
    /// root. Deletion is bounded twice: the resolved URL must be a
    /// direct child of the working root, and ownership proof is
    /// re-derived from the resolved entry — either a directory whose
    /// name is a canonical revision UUID (an abandoned working
    /// revision) or a `.tmp-*` regular file (a stale writer artifact).
    /// Anything else is refused so a malformed or unexpected item can
    /// never be recursively deleted without ownership proof.
    public func removeWorkingOrphan(
        _ orphan: PersistedCaptureWorkingOrphan
    ) throws {
        guard let workingRoot else {
            throw PersistedCaptureInventoryError
                .unsafeWorkingOrphanLocation
        }
        let resolved = orphan.url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let parent = resolved.deletingLastPathComponent()
        guard parent == workingRoot
                .standardizedFileURL
                .resolvingSymlinksInPath()
        else {
            throw PersistedCaptureInventoryError
                .unsafeWorkingOrphanLocation
        }

        let name = resolved.lastPathComponent
        let isAbandonedRevision =
            childKind(resolved) == .directory
            && CaptureRevisionID(canonicalString: name) != nil
        let isStaleWriterTemp =
            childKind(resolved) == .regularFile
            && name.hasPrefix(".tmp-")
        guard isAbandonedRevision || isStaleWriterTemp else {
            throw PersistedCaptureInventoryError
                .unsafeWorkingOrphanLocation
        }

        try FileManager.default.removeItem(at: orphan.url)
    }

    /// The canonical finalized directory URL for a validated revision
    /// identity. Used by the host for adoption and export; never
    /// derived from a stored path string.
    public func finalizedDirectory(
        for captureRevisionID: CaptureRevisionID
    ) -> URL {
        finalizedRoot.appendingPathComponent(
            captureRevisionID.description,
            isDirectory: true
        )
    }

    /// The canonical export archive URL for a validated revision
    /// identity.
    public func exportArchiveURL(
        for captureRevisionID: CaptureRevisionID
    ) -> URL {
        exportsRoot.appendingPathComponent(
            captureRevisionID.description + ".htdtcapture",
            isDirectory: false
        )
    }

    private enum ChildKind {
        case directory
        case regularFile
        case symbolicLink
        case unreadable
        case other
    }

    private func childKind(_ url: URL) -> ChildKind {
        guard let values = try? url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            return .unreadable
        }
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isDirectory == true {
            return .directory
        }
        if values.isRegularFile == true {
            return .regularFile
        }
        return .other
    }

    private func children(
        of root: URL,
        failures: inout [String]
    ) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            // A missing root is an empty inventory, not a failure.
            return []
        }
        guard isDirectory.boolValue else {
            failures.append(
                root.lastPathComponent
                    + " exists but is not a directory"
            )
            return []
        }
        do {
            return try fileManager
                .contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ],
                    options: []
                )
                .sorted {
                    $0.lastPathComponent
                        < $1.lastPathComponent
                }
        } catch {
            failures.append(
                root.lastPathComponent
                    + " could not be enumerated: "
                    + Self.diagnostic(error)
            )
            return []
        }
    }

    /// Best-effort byte total for a working-root child. Directory
    /// totals are enumerated shallowly one level at a time by
    /// FileManager; a failure is reported through `failures` and the
    /// orphan still lists with the bytes that could be counted, so a
    /// sizing problem never hides the orphan itself.
    private func retainedBytes(
        of url: URL,
        failures: inout [String]
    ) -> Int64 {
        switch childKind(url) {
        case .regularFile:
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey]
            )
            return Int64(values?.fileSize ?? 0)
        case .directory:
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                ],
                options: []
            ) else {
                failures.append(
                    url.lastPathComponent
                        + " size could not be enumerated"
                )
                return 0
            }
            var total: Int64 = 0
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                )
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
            return total
        case .symbolicLink, .unreadable, .other:
            return 0
        }
    }

    /// Rereads the canonical manifest and proves the directory still
    /// declares the selected revision identity. A nil return means the
    /// directory is proven to belong to `captureRevisionID`.
    private func identityReconfirmationFailure(
        directory: URL,
        captureRevisionID: CaptureRevisionID
    ) -> String? {
        let manifestURL = directory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: manifestURL) else {
            return "manifest could not be read; revision identity"
                + " was not reconfirmed"
        }
        guard let manifest = try? JSONDecoder().decode(
            BundleManifest.self,
            from: data
        ) else {
            return "manifest could not be decoded; revision identity"
                + " was not reconfirmed"
        }
        guard let canonical = try? manifest.canonicalBytes(),
              canonical == data
        else {
            return "manifest is not canonical; revision identity"
                + " was not reconfirmed"
        }
        guard manifest.captureRevisionID == captureRevisionID
        else {
            return "manifest revision "
                + manifest.captureRevisionID.description
                + " does not match the selected revision "
                + captureRevisionID.description
        }
        return nil
    }

    private static func diagnostic(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            var text = String(describing: error)
            if let paren = text.firstIndex(of: "(") {
                text = String(text[text.startIndex..<paren])
            }
            return String(describing: type(of: error))
                + "."
                + text
        }
        let nsError = error as NSError
        return String(describing: type(of: error))
            + ":"
            + nsError.domain
            + ":"
            + String(nsError.code)
    }
}

/// The explicit at-rest filesystem policy for app-owned capture data
/// (`Application Support/HTDTCapture`). Two independent controls are
/// applied at creation and verified on write:
///
/// - **Data Protection** (legacy bolph71656-ai/HTDT-Capture#166): every app-owned capture root and every
///   working revision directory carries
///   `.completeUntilFirstUserAuthentication`. iOS propagates a
///   directory's default protection class to children created inside
///   it, and a rename/move keeps the moved item's class, so a working
///   revision promoted to `finalized/` retains the same class — the
///   policy survives promotion without weakening. The class still
///   permits reads/writes after the first unlock while the device is
///   locked, which an active capture session requires; `.complete`
///   would break an in-flight scan on device lock.
/// - **Backup exclusion** (legacy bolph71656-ai/HTDT-Capture#136): only the transient `working/` root
///   and each `working/<uuid>` revision are excluded. Finalized
///   revisions and exported `.htdtcapture` archives are user-facing
///   artifacts and remain eligible for the platform's user-managed
///   backup; they are never silently covered by the transient-working
///   policy.
///
/// Every application is idempotent and verified by reading the value
/// back; failures surface as thrown errors or entries in the returned
/// failure list rather than being silently ignored.
public enum CaptureStoragePolicy {
    /// The Data Protection class applied to app-owned capture data.
    /// Kept as a value so a policy change is a one-line, reviewable
    /// edit.
    public static let fileProtection: FileProtectionType =
        .completeUntilFirstUserAuthentication

    /// Applies the full capture-root policy: the capture root plus its
    /// `working/`, `finalized/`, and `exports/` children are created if
    /// missing, the protection class is applied to each, `working/`
    /// alone is excluded from backup, and `finalized/`/`exports/` are
    /// normalized to the configured finalized-backup policy (legacy bolph71656-ai/HTDT-Capture#305).
    /// Returns a deterministic list of per-item failures; an empty
    /// list means every reachable item was verified.
    @discardableResult
    public static func applyCaptureRootPolicy(
        captureRoot: URL,
        finalizedBackupPolicy: FinalizedBackupPolicy
            = .backupEligible
    ) -> [String] {
        let fileManager = FileManager.default
        var failures: [String] = []

        let working = captureRoot.appendingPathComponent(
            "working",
            isDirectory: true
        )
        let finalized = captureRoot.appendingPathComponent(
            "finalized",
            isDirectory: true
        )
        let exports = captureRoot.appendingPathComponent(
            "exports",
            isDirectory: true
        )

        for directory in [captureRoot, working, finalized, exports] {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                failures.append(
                    directory.lastPathComponent
                        + " could not be created: "
                        + diagnosticDescription(error)
                )
            }
        }

        for directory in [captureRoot, working, finalized, exports] {
            do {
                try applyFileProtection(to: directory)
            } catch {
                failures.append(
                    directory.lastPathComponent
                        + " file protection was not applied: "
                        + diagnosticDescription(error)
                )
            }
        }

        do {
            try excludeFromBackup(working)
        } catch {
            failures.append(
                "working backup exclusion was not applied: "
                    + diagnosticDescription(error)
            )
        }

        failures.append(
            contentsOf: applyFinalizedBackupPolicy(
                captureRoot: captureRoot,
                policy: finalizedBackupPolicy
            )
        )

        return failures
    }

    /// Applies the operator-configured finalized backup policy
    /// (legacy bolph71656-ai/HTDT-Capture#305): `finalized/` and `exports/` and each of their direct
    /// children are explicitly marked excluded or not excluded.
    ///
    /// The explicit write matters in both directions: promotion moves
    /// a `working/<uuid>` directory — which carries
    /// `isExcludedFromBackup` — into `finalized/`, and a rename
    /// preserves extended attributes, so an eligible policy must
    /// clear the flag rather than assume it is absent.
    ///
    /// Returns a deterministic list of per-item failures; an empty
    /// list means every reachable item was verified.
    @discardableResult
    public static func applyFinalizedBackupPolicy(
        captureRoot: URL,
        policy: FinalizedBackupPolicy
    ) -> [String] {
        let excluded = policy == .excludedFromBackup
        let fileManager = FileManager.default
        var failures: [String] = []

        for directoryName in ["finalized", "exports"] {
            let directory = captureRoot.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                failures.append(
                    directoryName
                        + " could not be created: "
                        + diagnosticDescription(error)
                )
                continue
            }
            do {
                try setBackupExcluded(directory, excluded)
            } catch {
                failures.append(
                    directoryName
                        + " backup policy was not applied: "
                        + diagnosticDescription(error)
                )
            }
            guard let children = try? fileManager
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
            else {
                continue
            }
            for child in children.sorted(by: {
                $0.lastPathComponent < $1.lastPathComponent
            }) {
                do {
                    try setBackupExcluded(child, excluded)
                } catch {
                    failures.append(
                        child.lastPathComponent
                            + " backup policy was not applied: "
                            + diagnosticDescription(error)
                    )
                }
            }
        }

        return failures
    }

    /// Applies the finalized backup policy to one newly promoted
    /// `finalized/<uuid>` revision directory (legacy bolph71656-ai/HTDT-Capture#305). Must be called
    /// after promotion: the atomic move preserves the
    /// `isExcludedFromBackup` attribute the working revision carried,
    /// so without this a finalized directory silently keeps whatever
    /// the working policy set regardless of the configured policy.
    public static func applyFinalizedRevisionPolicy(
        revisionRoot: URL,
        policy: FinalizedBackupPolicy
    ) throws {
        try setBackupExcluded(
            revisionRoot,
            policy == .excludedFromBackup
        )
    }

    /// Applies the finalized backup policy to one export archive
    /// (legacy bolph71656-ai/HTDT-Capture#305); same policy as its finalized sibling since both are
    /// user-facing retained artifacts.
    public static func applyExportArchivePolicy(
        archiveURL: URL,
        policy: FinalizedBackupPolicy
    ) throws {
        try setBackupExcluded(
            archiveURL,
            policy == .excludedFromBackup
        )
    }

    /// Applies the transient-working policy to one new
    /// `working/<uuid>` revision directory: backup exclusion plus the
    /// capture file-protection class. Callers should surface a thrown
    /// error to the operator rather than proceeding silently.
    public static func applyWorkingRevisionPolicy(
        revisionRoot: URL
    ) throws {
        try applyFileProtection(to: revisionRoot)
        try excludeFromBackup(revisionRoot)
    }

    /// Excludes `url` (a directory and everything inside it) from
    /// platform backup, then verifies the resource value round-trips.
    public static func excludeFromBackup(_ url: URL) throws {
        try setBackupExcluded(url, true)
    }

    /// Writes `isExcludedFromBackup` on `url` in either direction and
    /// verifies the value persisted (legacy bolph71656-ai/HTDT-Capture#305): an explicit `false` is
    /// required to clear an exclusion inherited through promotion or
    /// an earlier policy setting.
    ///
    /// `URL.resourceValues` can report a freshly written value from
    /// its resource cache even when the extended-attribute write did
    /// not persist, so the verification reads the exclusion attribute
    /// directly; one retry covers a silently dropped write.
    public static func setBackupExcluded(
        _ url: URL,
        _ excluded: Bool
    ) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        for _ in 0..<2 {
            try target.setResourceValues(values)
            if isBackupExcludedAttributePresent(at: url) == excluded {
                return
            }
        }
        throw PersistedCaptureInventoryError
            .storagePolicyVerificationFailed(
                "isExcludedFromBackup did not persist on "
                    + url.lastPathComponent
            )
    }

    /// Filesystem-level truth for the exclusion flag: the
    /// `com.apple.metadata:com_apple_backup_excludeItem` extended
    /// attribute is what the platform backup honors, and only its
    /// presence proves the write persisted.
    private static func isBackupExcludedAttributePresent(
        at url: URL
    ) -> Bool {
        url.path.withCString {
            getxattr(
                $0,
                "com.apple.metadata:com_apple_backup_excludeItem",
                nil,
                0,
                0,
                0
            ) >= 0
        }
    }

    /// Applies the capture Data Protection class to `url` and verifies
    /// the attribute where the platform reports it. Data Protection
    /// classes are enforced by the iOS-family filesystems; elsewhere
    /// this is an explicit no-op so the policy can be invoked
    /// unconditionally.
    public static func applyFileProtection(to url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let fileManager = FileManager.default
        try fileManager.setAttributes(
            [.protectionKey: fileProtection],
            ofItemAtPath: url.path
        )

        let attributes = try fileManager.attributesOfItem(
            atPath: url.path
        )
        guard let applied =
                attributes[.protectionKey] as? FileProtectionType,
              applied == fileProtection
        else {
            throw PersistedCaptureInventoryError
                .storagePolicyVerificationFailed(
                    "file protection class did not persist on "
                        + url.lastPathComponent
                )
        }
        #else
        _ = url
        #endif
    }

    private static func diagnosticDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return String(describing: type(of: error))
            + ":"
            + nsError.domain
            + ":"
            + String(nsError.code)
    }
}
