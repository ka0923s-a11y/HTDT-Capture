import Foundation

/// Which revisions a Library Export covers (issue #378). Scope is by
/// series or revision identity only — `working/` captures are never
/// exportable, and the default (`all`) covers every retained revision
/// including archived series so archiving never hides captures from
/// portability (#394).
public enum CaptureLibraryExportScope: Sendable, Equatable {
    case all
    case series(Set<CaptureSeriesID>)
    case revisions(Set<CaptureRevisionID>)

    public func includes(
        _ record: PersistedCaptureRecord
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .series(let ids):
            return ids.contains(record.captureSeriesID)
        case .revisions(let ids):
            return ids.contains(record.captureRevisionID)
        }
    }
}

/// What one revision contributes to a Library Export: the source of
/// the exact archive bytes that ride in the package.
public enum CaptureLibraryExportArchiveSource:
    Sendable,
    Equatable
{
    /// The stored derived archive — byte-identical to what the device
    /// already exports or has imported; reused without reserializing.
    case existingArchive
    /// Exported fresh from the canonical finalized directory because
    /// no derived archive is currently retained.
    case regeneratedFromFinalized
}

public struct CaptureLibraryExportResult:
    Sendable,
    Equatable
{
    public let packageURL: URL
    public let revisionCount: Int
    /// Sum of the `.htdtcapture` member byte counts.
    public let archiveByteCount: Int64
    /// Revisions the operator scoped in that had no exportable bytes
    /// (neither a valid derived archive nor a finalized directory).
    public let skippedRevisions: [CaptureRevisionID]

    public init(
        packageURL: URL,
        revisionCount: Int,
        archiveByteCount: Int64,
        skippedRevisions: [CaptureRevisionID]
    ) {
        self.packageURL = packageURL
        self.revisionCount = revisionCount
        self.archiveByteCount = archiveByteCount
        self.skippedRevisions = skippedRevisions
    }
}

/// Writes a `.htdtcapturelibrary` from the persisted library (issue
/// #378). Canonical `.htdtcapture` archives ride byte-exact when a
/// validated derived copy already exists; when it doesn't, the bundle
/// exporter produces one from the finalized directory (still a valid
/// canonical archive — the bundle's own validator attests it). The
/// package never reserializes bundle payloads, never rewrites bundle
/// IDs, and includes the filtered app-local metadata and receipt
/// ledger entries for the exported revisions only.
public enum CaptureLibraryPackageExporter {
    /// Writes the package atomically (sibling temp + publish) at
    /// `destination`, which must not already exist.
    public static func export(
        records: [PersistedCaptureRecord],
        scope: CaptureLibraryExportScope = .all,
        metadata: CaptureLibraryMetadataDocument,
        receipts: [HTDTHandoffReceipt],
        destination: URL,
        appVersion: String,
        appBuild: String,
        nowUTC: String = BundleTimestamp.utcString(from: Date()),
        limits: BundleFilesystemLimits = .init()
    ) throws -> CaptureLibraryExportResult {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let staging = parent.appendingPathComponent(
            ".library-export-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false
        )
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        let selected = records.filter { scope.includes($0) }
        var manifestEntries: [
            CaptureLibraryPackageManifest.RevisionEntry
        ] = []
        var skipped: [CaptureRevisionID] = []
        var memberEntries: [CaptureLibraryPackageEntry] = []
        var totalArchiveBytes: Int64 = 0

        for record in selected {
            let archiveURL: URL
            var expectedDigest: EvidenceSHA256? = nil

            if let existing = record.exportArchive,
               let validation = record.exportValidation,
               fileManager.fileExists(atPath: existing.path)
            {
                archiveURL = existing
                expectedDigest = validation.bundleDigest
            } else if let directory = record.finalizedDirectory,
                      let validation = record.finalizedValidation
            {
                let generated = staging.appendingPathComponent(
                    record.captureRevisionID.description
                        + ".htdtcapture",
                    isDirectory: false
                )
                _ = try CaptureBundleArchiveExporter.export(
                    finalizedDirectory: directory,
                    destination: generated,
                    limits: limits
                )
                archiveURL = generated
                expectedDigest = validation.bundleDigest
            } else {
                // Neither byte source is available — the record is
                // reported skipped rather than fabricating content.
                skipped.append(record.captureRevisionID)
                continue
            }

            let (sha, byteCount) = try BundleFileReader.sha256(
                archiveURL,
                maxBytes: limits.maxTotalBytes
            )
            guard let digest = expectedDigest else {
                skipped.append(record.captureRevisionID)
                continue
            }
            let archivePath =
                "archives/"
                + record.captureRevisionID.description
                + ".htdtcapture"
            manifestEntries.append(
                CaptureLibraryPackageManifest.RevisionEntry(
                    captureRevisionID:
                        record.captureRevisionID.description,
                    captureSeriesID:
                        record.captureSeriesID.description,
                    bundleDigest: digest.description,
                    archiveSHA256: sha.description,
                    archiveByteCount: byteCount,
                    archivePath: archivePath,
                    finalizedAtUTC: record.finalizedAtUTC
                )
            )
            memberEntries.append(
                CaptureLibraryPackageEntry(
                    path: archivePath,
                    source: .file(archiveURL)
                )
            )
            totalArchiveBytes += byteCount
        }

        guard !manifestEntries.isEmpty else {
            throw CaptureLibraryPackageError.emptyPackage
        }

        let includedSeries = Set(
            manifestEntries.map(\.captureSeriesID)
        )
        let includedRevisions = Set(
            manifestEntries.map(\.captureRevisionID)
        )
        let filteredMetadata = CaptureLibraryMetadataDocument(
            series: metadata.series.filter {
                includedSeries.contains($0.key)
            },
            revisions: metadata.revisions.filter {
                includedRevisions.contains($0.key)
            },
            seriesStates: metadata.seriesStates.filter {
                includedSeries.contains($0.key)
            },
            revisionMarks: metadata.revisionMarks.filter {
                includedRevisions.contains($0.key)
            },
            preferredHeads: metadata.preferredHeads.filter {
                includedSeries.contains($0.key)
            }
        )
        let filteredReceipts = HTDTHandoffReceiptStore.Document(
            receipts: receipts.filter {
                $0.artifactIDText.map(includedRevisions.contains)
                    ?? false
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]

        let manifest = CaptureLibraryPackageManifest(
            createdAtUTC: nowUTC,
            app: BundleAppIdentity(
                version: appVersion,
                build: appBuild
            ),
            revisions: manifestEntries.sorted {
                $0.captureRevisionID < $1.captureRevisionID
            },
            includesLibraryMetadata: true,
            includesHandoffReceipts: true
        )
        var entries: [CaptureLibraryPackageEntry] = [
            CaptureLibraryPackageEntry(
                path: "library-package.json",
                source: .data(try manifest.canonicalBytes())
            ),
            CaptureLibraryPackageEntry(
                path: "library-metadata.json",
                source: .data(
                    try encoder.encode(filteredMetadata)
                )
            ),
            CaptureLibraryPackageEntry(
                path: "handoff-receipts.json",
                source: .data(
                    try encoder.encode(filteredReceipts)
                )
            ),
        ]
        entries.append(contentsOf: memberEntries)

        try CaptureLibraryPackageWriter.write(
            entries: entries,
            destination: destination
        )
        return CaptureLibraryExportResult(
            packageURL: destination,
            revisionCount: manifestEntries.count,
            archiveByteCount: totalArchiveBytes,
            skippedRevisions: skipped
        )
    }
}

/// How one packaged revision relates to the local library (issue
/// #378): drives the staged import preview and decides whether the
/// revision can land at all.
public enum CaptureLibraryImportDisposition:
    String,
    Sendable,
    Equatable
{
    /// Revision id unknown locally, in a series this library has
    /// never seen.
    case newSeries = "new_series"
    /// Revision id unknown locally, but the series already exists —
    /// newer or older than what is stored; ordering is by the
    /// validated `finalized_at`, never by trust in the package.
    case newRevisionInKnownSeries = "new_revision_in_known_series"
    /// Same revision id and the same bundle digest already stored —
    /// idempotent re-import; nothing is rewritten.
    case duplicate
    /// Same revision id but a different bundle digest — a hard
    /// conflict; the local revision is never overwritten and the
    /// packaged bytes are quarantined out of the import.
    case conflict
    /// The package entry itself failed to prove its integrity —
    /// archive sha mismatch, bundle digest mismatch, or archive
    /// validation failure. Untouched.
    case invalid
}

public struct CaptureLibraryImportEntryPreview:
    Sendable,
    Equatable
{
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    public let bundleDigest: String
    public let archiveSHA256: String
    public let archiveByteCount: Int64
    public let finalizedAtUTC: String
    public let disposition: CaptureLibraryImportDisposition
    /// Operator-safe reason for `.invalid`/`.conflict` entries.
    public let detail: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        bundleDigest: String,
        archiveSHA256: String,
        archiveByteCount: Int64,
        finalizedAtUTC: String,
        disposition: CaptureLibraryImportDisposition,
        detail: String? = nil
    ) {
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.bundleDigest = bundleDigest
        self.archiveSHA256 = archiveSHA256
        self.archiveByteCount = archiveByteCount
        self.finalizedAtUTC = finalizedAtUTC
        self.disposition = disposition
        self.detail = detail
    }
}

/// A metadata value the package disagrees with locally (issue #378):
/// both sides are retained in the preview so the import can adopt the
/// local value while surfacing the incoming one as an import
/// candidate rather than dropping it.
public struct CaptureLibraryMetadataConflict:
    Sendable,
    Equatable,
    Identifiable
{
    public enum Scope: String, Sendable, Equatable {
        case series
        case revision
    }

    public let scope: Scope
    public let identity: String
    public let local: CaptureLibraryEntryMetadata
    public let incoming: CaptureLibraryEntryMetadata

    public var id: String { scope.rawValue + ":" + identity }

    public init(
        scope: Scope,
        identity: String,
        local: CaptureLibraryEntryMetadata,
        incoming: CaptureLibraryEntryMetadata
    ) {
        self.scope = scope
        self.identity = identity
        self.local = local
        self.incoming = incoming
    }
}

/// The validated, staged import state produced by
/// `CaptureLibraryImporter.preview` (issue #378): manifest proven,
/// every included archive re-validated under the existing bundle
/// validator, conflicts and duplicates already classified against
/// the local library, and member bytes extracted into a staging
/// directory the caller must eventually release via `commit` or
/// `discard`.
public struct CaptureLibraryImportPreview: Sendable {
    public let packageURL: URL
    public let manifest: CaptureLibraryPackageManifest
    public let entries: [CaptureLibraryImportEntryPreview]
    /// Staged member files: `staging/<revision_id>.htdtcapture`.
    public let stagingDirectory: URL
    /// Number of local metadata entries the package would fill in
    /// where local is empty (name or note adoption).
    public let metadataAdoptions: Int
    /// Entries where both sides carry different non-empty values —
    /// surfaced so the operator knows local values were kept.
    public let metadataConflicts:
        [CaptureLibraryMetadataConflict]
    /// Receipts that would append (already deduped by receipt id).
    public let receiptsToAppend: Int

    public var importableCount: Int {
        entries.filter {
            $0.disposition == .newSeries
                || $0.disposition == .newRevisionInKnownSeries
        }.count
    }

    public init(
        packageURL: URL,
        manifest: CaptureLibraryPackageManifest,
        entries: [CaptureLibraryImportEntryPreview],
        stagingDirectory: URL,
        metadataAdoptions: Int,
        metadataConflicts: [CaptureLibraryMetadataConflict],
        receiptsToAppend: Int
    ) {
        self.packageURL = packageURL
        self.manifest = manifest
        self.entries = entries
        self.stagingDirectory = stagingDirectory
        self.metadataAdoptions = metadataAdoptions
        self.metadataConflicts = metadataConflicts
        self.receiptsToAppend = receiptsToAppend
    }
}

public struct CaptureLibraryImportResult:
    Sendable,
    Equatable
{
    /// Revisions imported this commit.
    public let imported: [CaptureRevisionID]
    /// Idempotent skips — same revision and digest already stored.
    public let duplicates: [CaptureRevisionID]
    /// Same-identity different-digest conflicts; local bytes never
    /// overwritten.
    public let conflicts: [CaptureRevisionID]
    /// Entries that failed integrity or write — untouched locally,
    /// each with its reason.
    public let failed: [CaptureRevisionID]
    public let metadataConflictsKeptLocal: Int
    public let receiptsAppended: Int

    public init(
        imported: [CaptureRevisionID],
        duplicates: [CaptureRevisionID],
        conflicts: [CaptureRevisionID],
        failed: [CaptureRevisionID],
        metadataConflictsKeptLocal: Int,
        receiptsAppended: Int
    ) {
        self.imported = imported
        self.duplicates = duplicates
        self.conflicts = conflicts
        self.failed = failed
        self.metadataConflictsKeptLocal = metadataConflictsKeptLocal
        self.receiptsAppended = receiptsAppended
    }
}

/// The staged, transactional importer for `.htdtcapturelibrary`
/// packages (issue #378). `preview` proves the package and classifies
/// every member against the local library without touching any
/// stored state; `commit` then applies the importable members through
/// the existing bundle importer, merges metadata and receipts by the
/// issue's rules, and reports exactly which revisions landed and
/// which were left untouched.
public enum CaptureLibraryImporter {
    /// Opens and validates the package, extracts each member archive
    /// into `stagingDirectory` (created if needed), re-validates each
    /// under `StoredCaptureBundleArchiveValidator`, and classifies
    /// them against `localRecords`. Package-level failures throw;
    /// member-level failures are reported per entry in the preview.
    public static func preview(
        package: URL,
        captureRoot: URL,
        localRecords: [PersistedCaptureRecord],
        stagingDirectory: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> CaptureLibraryImportPreview {
        let validated = try CaptureLibraryPackageReader.validate(
            archive: package,
            limits: limits
        )
        let manifest = validated.manifest

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let localByRevision = Dictionary(
            uniqueKeysWithValues: localRecords.map {
                ($0.captureRevisionID, $0)
            }
        )
        let knownSeries = Set(localRecords.map(\.captureSeriesID))

        var previews: [CaptureLibraryImportEntryPreview] = []
        for entry in manifest.revisions {
            guard let revisionID = CaptureRevisionID(
                canonicalString: entry.captureRevisionID
            ), let seriesID = CaptureSeriesID(
                canonicalString: entry.captureSeriesID
            ) else {
                previews.append(
                    invalidEntry(
                        entry,
                        detail: "non-canonical capture identity"
                    )
                )
                continue
            }

            let expectedPath =
                "archives/" + entry.captureRevisionID
                + ".htdtcapture"
            guard entry.archivePath == expectedPath,
                  let member = validated.entries[entry.archivePath]
            else {
                previews.append(
                    invalidEntry(
                        entry,
                        detail:
                            "archive member missing from package"
                    )
                )
                continue
            }

            let staged = stagingDirectory.appendingPathComponent(
                entry.captureRevisionID + ".htdtcapture",
                isDirectory: false
            )
            if fileManager.fileExists(atPath: staged.path) {
                try? fileManager.removeItem(at: staged)
            }
            do {
                try CaptureLibraryPackageReader.extractEntry(
                    archive: package,
                    entry: member,
                    destination: staged
                )
                guard Int64(member.size)
                        == entry.archiveByteCount
                else {
                    throw CaptureLibraryPackageError
                        .archiveSHA256Mismatch(
                            entry.captureRevisionID
                        )
                }
                let (sha, _) = try BundleFileReader.sha256(
                    staged,
                    maxBytes: limits.maxTotalBytes
                )
                guard sha.description == entry.archiveSHA256 else {
                    throw CaptureLibraryPackageError
                        .archiveSHA256Mismatch(
                            entry.captureRevisionID
                        )
                }
                let report =
                    try StoredCaptureBundleArchiveValidator.validate(
                        archive: staged,
                        limits: limits
                    )
                guard report.bundleDigest.description
                        == entry.bundleDigest,
                      report.manifest.captureRevisionID
                        == revisionID,
                      report.manifest.captureSeriesID == seriesID
                else {
                    throw CaptureLibraryPackageError
                        .archiveDigestMismatch(
                            entry.captureRevisionID
                        )
                }
            } catch {
                try? fileManager.removeItem(at: staged)
                previews.append(
                    CaptureLibraryImportEntryPreview(
                        captureRevisionID: revisionID,
                        captureSeriesID: seriesID,
                        bundleDigest: entry.bundleDigest,
                        archiveSHA256: entry.archiveSHA256,
                        archiveByteCount: entry.archiveByteCount,
                        finalizedAtUTC: entry.finalizedAtUTC,
                        disposition: .invalid,
                        detail:
                            "archive failed integrity validation"
                    )
                )
                continue
            }

            if let local = localByRevision[revisionID] {
                let localDigest = local.finalizedValidation?
                    .bundleDigest
                    ?? local.exportValidation?.bundleDigest
                if localDigest?.description == entry.bundleDigest {
                    previews.append(
                        CaptureLibraryImportEntryPreview(
                            captureRevisionID: revisionID,
                            captureSeriesID: seriesID,
                            bundleDigest: entry.bundleDigest,
                            archiveSHA256: entry.archiveSHA256,
                            archiveByteCount:
                                entry.archiveByteCount,
                            finalizedAtUTC: entry.finalizedAtUTC,
                            disposition: .duplicate,
                            detail: nil
                        )
                    )
                } else {
                    previews.append(
                        CaptureLibraryImportEntryPreview(
                            captureRevisionID: revisionID,
                            captureSeriesID: seriesID,
                            bundleDigest: entry.bundleDigest,
                            archiveSHA256: entry.archiveSHA256,
                            archiveByteCount:
                                entry.archiveByteCount,
                            finalizedAtUTC: entry.finalizedAtUTC,
                            disposition: .conflict,
                            detail:
                                "a different revision already exists under this identity locally"
                        )
                    )
                }
                continue
            }

            previews.append(
                CaptureLibraryImportEntryPreview(
                    captureRevisionID: revisionID,
                    captureSeriesID: seriesID,
                    bundleDigest: entry.bundleDigest,
                    archiveSHA256: entry.archiveSHA256,
                    archiveByteCount: entry.archiveByteCount,
                    finalizedAtUTC: entry.finalizedAtUTC,
                    disposition: knownSeries.contains(seriesID)
                        ? .newRevisionInKnownSeries
                        : .newSeries,
                    detail: nil
                )
            )
        }

        // Filtered app-local documents: metadata merges per the
        // issue's rules, receipts append deduped by receipt id.
        var metadataAdoptions = 0
        var metadataConflicts:
            [CaptureLibraryMetadataConflict] = []
        var receiptsToAppend = 0
        if manifest.includesLibraryMetadata,
           let metadataEntry =
               validated.entries["library-metadata.json"]
        {
            let data = try CaptureLibraryPackageReader.readSegment(
                archive: package,
                entry: metadataEntry
            )
            if let incoming = try? JSONDecoder().decode(
                CaptureLibraryMetadataDocument.self,
                from: data
            ), incoming.schema
                == CaptureLibraryMetadataDocument.schema,
               CaptureLibraryMetadataDocument.supportedReadVersions
                .contains(incoming.schemaVersion)
            {
                let local = (try? CaptureLibraryMetadataStore(
                    captureRoot: captureRoot
                ).load()) ?? CaptureLibraryMetadataDocument()
                for (key, value) in incoming.series {
                    guard includedIDs(
                        key,
                        manifest: manifest,
                        series: true
                    ) else { continue }
                    metadataAdoptions +=
                        mergePreview(
                            identity: key,
                            scope: .series,
                            local: local.series[key],
                            incoming: value,
                            conflicts: &metadataConflicts
                        )
                }
                for (key, value) in incoming.revisions {
                    guard includedIDs(
                        key,
                        manifest: manifest,
                        series: false
                    ) else { continue }
                    metadataAdoptions +=
                        mergePreview(
                            identity: key,
                            scope: .revision,
                            local: local.revisions[key],
                            incoming: value,
                            conflicts: &metadataConflicts
                        )
                }
            }
        }
        if manifest.includesHandoffReceipts,
           let receiptsEntry =
               validated.entries["handoff-receipts.json"]
        {
            let data = try CaptureLibraryPackageReader.readSegment(
                archive: package,
                entry: receiptsEntry
            )
            if let incoming = try? JSONDecoder().decode(
                HTDTHandoffReceiptStore.Document.self,
                from: data
            ), incoming.schema
                == HTDTHandoffReceiptStore.Document.schema,
               incoming.schemaVersion
                == HTDTHandoffReceiptStore.Document.schemaVersion
            {
                let localReceipts =
                    ((try? HTDTHandoffReceiptStore(
                        captureRoot: captureRoot
                    ).load().receipts) ?? [])
                let localIDs = Set(
                    localReceipts.map(\.receiptID)
                )
                let included = Set(
                    manifest.revisions.map(\.captureRevisionID)
                )
                receiptsToAppend = incoming.receipts.filter {
                    ($0.artifactIDText.map(included.contains) ?? false)
                        && !localIDs.contains($0.receiptID)
                }.count
            }
        }

        return CaptureLibraryImportPreview(
            packageURL: package,
            manifest: manifest,
            entries: previews,
            stagingDirectory: stagingDirectory,
            metadataAdoptions: metadataAdoptions,
            metadataConflicts: metadataConflicts,
            receiptsToAppend: receiptsToAppend
        )
    }

    /// Applies the staged preview: each importable member promotes
    /// through the existing bundle importer into `finalized/`, its
    /// exact archive bytes fill the exports slot when free, then
    /// metadata merges and receipts append — every member outcome is
    /// reported so a partial failure names precisely which revisions
    /// imported and which stayed untouched.
    public static func commit(
        preview: CaptureLibraryImportPreview,
        captureRoot: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> CaptureLibraryImportResult {
        let fileManager = FileManager.default
        let inventory = PersistedCaptureInventory(
            captureRoot: captureRoot,
            limits: limits
        )
        var imported: [CaptureRevisionID] = []
        var duplicates: [CaptureRevisionID] = []
        var conflicts: [CaptureRevisionID] = []
        var failed: [CaptureRevisionID] = []

        for entry in preview.entries {
            let staged = preview.stagingDirectory
                .appendingPathComponent(
                    entry.captureRevisionID.description
                        + ".htdtcapture",
                    isDirectory: false
                )
            switch entry.disposition {
            case .newSeries, .newRevisionInKnownSeries:
                break
            case .duplicate:
                duplicates.append(entry.captureRevisionID)
                continue
            case .conflict:
                conflicts.append(entry.captureRevisionID)
                continue
            case .invalid:
                failed.append(entry.captureRevisionID)
                continue
            }

            // Commit is transactional per revision: identity is
            // re-confirmed absent, the validated archive promotes via
            // the staging importer, then the exact archive bytes fill
            // the exports slot when it is free. A failure at any
            // point leaves the revision untouched or fully imported —
            // never half-published.
            let finalized = inventory.finalizedDirectory(
                for: entry.captureRevisionID
            )
            let archiveDestination = inventory.exportArchiveURL(
                for: entry.captureRevisionID
            )
            do {
                if !fileManager.fileExists(atPath: finalized.path) {
                    try fileManager.createDirectory(
                        at: finalized.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    _ = try StoredCaptureBundleArchiveImporter
                        .importArchive(
                            archive: staged,
                            destination: finalized,
                            limits: limits
                        )
                }
                try fileManager.createDirectory(
                    at: archiveDestination
                        .deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fileManager.fileExists(
                    atPath: archiveDestination.path
                ) {
                    let temp = archiveDestination
                        .deletingLastPathComponent()
                        .appendingPathComponent(
                            ".\(archiveDestination.lastPathComponent).tmp-\(UUID().uuidString.lowercased())"
                        )
                    try fileManager.copyItem(
                        at: staged,
                        to: temp
                    )
                    do {
                        try fileManager.moveItem(
                            at: temp,
                            to: archiveDestination
                        )
                    } catch {
                        try? fileManager.removeItem(at: temp)
                        throw error
                    }
                }
                imported.append(entry.captureRevisionID)
            } catch {
                failed.append(entry.captureRevisionID)
            }
        }

        // Metadata merge: identical → no-op; one side empty → adopt;
        // both non-empty and different → keep local and surface the
        // incoming value as a retained conflict (#378).
        var conflictCount = 0
        if preview.manifest.includesLibraryMetadata,
           let package = try? CaptureLibraryPackageReader
               .validate(archive: preview.packageURL,
                         limits: limits),
           let entry = package.entries["library-metadata.json"],
           let data = try? CaptureLibraryPackageReader
               .readSegment(
                   archive: preview.packageURL,
                   entry: entry
               ),
           let incoming = try? JSONDecoder().decode(
               CaptureLibraryMetadataDocument.self,
               from: data
           ), incoming.schema
               == CaptureLibraryMetadataDocument.schema,
           CaptureLibraryMetadataDocument.supportedReadVersions
               .contains(incoming.schemaVersion)
        {
            let store = CaptureLibraryMetadataStore(
                captureRoot: captureRoot
            )
            if var document = try? store.load() {
                var series = document.series
                var revisions = document.revisions
                var seriesStates = document.seriesStates
                var revisionMarks = document.revisionMarks
                let importedIDs = Set(
                    imported.map(\.description)
                )
                let importedSeries = Set(
                    preview.entries.filter {
                        importedIDs.contains(
                            $0.captureRevisionID.description
                        )
                    }.map(\.captureSeriesID.description)
                )
                for (key, value) in incoming.series {
                    guard importedSeries.contains(key) else {
                        continue
                    }
                    _ = merge(
                        into: &series,
                        key: key,
                        incoming: value,
                        conflicts: &conflictCount
                    )
                }
                for (key, value) in incoming.revisions {
                    guard importedIDs.contains(key) else {
                        continue
                    }
                    _ = merge(
                        into: &revisions,
                        key: key,
                        incoming: value,
                        conflicts: &conflictCount
                    )
                }
                for (key, value) in incoming.seriesStates {
                    guard importedSeries.contains(key),
                          seriesStates[key] == nil
                    else {
                        continue
                    }
                    seriesStates[key] = value
                }
                for (key, value) in incoming.revisionMarks {
                    guard importedIDs.contains(key),
                          revisionMarks[key] == nil
                    else {
                        continue
                    }
                    revisionMarks[key] = value
                }
                var preferredHeads = document.preferredHeads
                for (key, value) in incoming.preferredHeads {
                    guard importedSeries.contains(key),
                          preferredHeads[key] == nil
                    else {
                        continue
                    }
                    preferredHeads[key] = value
                }
                document = CaptureLibraryMetadataDocument(
                    series: series,
                    revisions: revisions,
                    seriesStates: seriesStates,
                    revisionMarks: revisionMarks,
                    preferredHeads: preferredHeads
                )
                try? store.save(document)
            }
        }

        // Receipt ledger: append-only, deduped by receipt id (#378).
        var appended = 0
        if preview.manifest.includesHandoffReceipts,
           let package = try? CaptureLibraryPackageReader
               .validate(archive: preview.packageURL,
                         limits: limits),
           let entry = package.entries["handoff-receipts.json"],
           let data = try? CaptureLibraryPackageReader
               .readSegment(
                   archive: preview.packageURL,
                   entry: entry
               ),
           let incoming = try? JSONDecoder().decode(
               HTDTHandoffReceiptStore.Document.self,
               from: data
           ), incoming.schema
               == HTDTHandoffReceiptStore.Document.schema,
           incoming.schemaVersion
               == HTDTHandoffReceiptStore.Document.schemaVersion
        {
            let store = HTDTHandoffReceiptStore(
                captureRoot: captureRoot
            )
            if let local = try? store.load().receipts {
                let localIDs = Set(local.map(\.receiptID))
                let importedIDs = Set(imported.map(\.description))
                for receipt in incoming.receipts {
                    guard receipt.artifactIDText.map(
                        importedIDs.contains
                    ) ?? false, !localIDs.contains(receipt.receiptID)
                    else {
                        continue
                    }
                    try? store.append(receipt)
                    appended += 1
                }
            }
        }

        try? fileManager.removeItem(
            at: preview.stagingDirectory
        )

        return CaptureLibraryImportResult(
            imported: imported,
            duplicates: duplicates,
            conflicts: conflicts,
            failed: failed,
            metadataConflictsKeptLocal: conflictCount,
            receiptsAppended: appended
        )
    }

    /// Releases a staged preview when the operator declines the
    /// import — no stored state was ever touched.
    public static func discard(
        preview: CaptureLibraryImportPreview
    ) {
        try? FileManager.default.removeItem(
            at: preview.stagingDirectory
        )
    }

    private static func invalidEntry(
        _ entry: CaptureLibraryPackageManifest.RevisionEntry,
        detail: String
    ) -> CaptureLibraryImportEntryPreview {
        CaptureLibraryImportEntryPreview(
            captureRevisionID: CaptureRevisionID(
                canonicalString: entry.captureRevisionID
            ) ?? CaptureRevisionID(),
            captureSeriesID: CaptureSeriesID(
                canonicalString: entry.captureSeriesID
            ) ?? CaptureSeriesID(),
            bundleDigest: entry.bundleDigest,
            archiveSHA256: entry.archiveSHA256,
            archiveByteCount: entry.archiveByteCount,
            finalizedAtUTC: entry.finalizedAtUTC,
            disposition: .invalid,
            detail: detail
        )
    }

    private static func includedIDs(
        _ key: String,
        manifest: CaptureLibraryPackageManifest,
        series: Bool
    ) -> Bool {
        if series {
            return manifest.revisions.contains {
                $0.captureSeriesID == key
            }
        }
        return manifest.revisions.contains {
            $0.captureRevisionID == key
        }
    }

    /// Counts the entries the package would adopt where local is
    /// empty and registers a conflict where both sides disagree —
    /// the preview-side of the merge rules.
    private static func mergePreview(
        identity: String,
        scope: CaptureLibraryMetadataConflict.Scope,
        local: CaptureLibraryEntryMetadata?,
        incoming: CaptureLibraryEntryMetadata,
        conflicts: inout [CaptureLibraryMetadataConflict]
    ) -> Int {
        guard let local, !local.isEmpty else {
            return incoming.isEmpty ? 0 : 1
        }
        guard !incoming.isEmpty else {
            return 0
        }
        if local == incoming {
            return 0
        }
        conflicts.append(
            CaptureLibraryMetadataConflict(
                scope: scope,
                identity: identity,
                local: local,
                incoming: incoming
            )
        )
        return 0
    }

    /// Applies one incoming value under the merge rules; returns true
    /// when the local map changed.
    private static func merge(
        into map: inout [String: CaptureLibraryEntryMetadata],
        key: String,
        incoming: CaptureLibraryEntryMetadata,
        conflicts: inout Int
    ) -> Bool {
        guard let local = map[key], !local.isEmpty else {
            guard !incoming.isEmpty else {
                return false
            }
            map[key] = incoming
            return true
        }
        guard !incoming.isEmpty, local != incoming else {
            return false
        }
        conflicts += 1
        return false
    }
}
