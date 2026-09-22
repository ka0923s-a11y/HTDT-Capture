import Foundation

/// What the retention preview recommends for one revision (issue
/// #394). "Keep latest only" is never an automatic policy: the newest
/// revision and marked revisions recommend `keep`, older unmarked
/// revisions recommend `deleteCandidate` so the operator reviews them
/// one preview at a time.
public enum CaptureRetentionRecommendation:
    String,
    Sendable,
    Equatable
{
    case keep
    case deleteCandidate = "delete_candidate"
}

/// Hard blocks on deleting a revision (issue #394). A blocked
/// revision is skipped rather than deleted — the preview names the
/// reason so the operator can resolve it explicitly.
public enum CaptureRetentionBlocker:
    Sendable,
    Hashable
{
    /// A non-terminal delivery-queue job still references this
    /// revision's archive bytes; cancel the job first.
    case pendingDeliveryJob(String)
    /// The revision carries an operator importance mark — deletion
    /// requires the explicit protected override.
    case protectedMark
}

/// Advisory context shown alongside a deletion preview (issue #394):
/// the deletion may proceed, but the operator sees exactly what the
/// bytes leaving local storage imply.
public enum CaptureRetentionWarning:
    Sendable,
    Hashable
{
    /// Other local revisions declare this revision as their parent —
    /// deleting it never rewrites or reparents them; they will show
    /// an absent local predecessor.
    case parentOfRevisions(Int)
    /// Handoff receipts remain as the historical send record after
    /// the bytes are gone; they are evidence, not backup proof, and
    /// the bundle will no longer be inspectable from them.
    case handoffReceipts(Int)
    /// A mission record lists this revision as an associated capture.
    case linkedToMission(String)
    /// Nothing proves a copy exists anywhere else — no delivered
    /// handoff receipt and no derived archive elsewhere.
    case onlyLocalCopy
}

/// One revision's row inside a series retention preview (issue #394):
/// the bytes it holds, the marks protecting it, the recommendation,
/// and every blocker and warning the deletion flow must respect.
public struct CaptureRevisionRetentionRow:
    Sendable,
    Equatable,
    Identifiable
{
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    public let finalizedAtUTC: String
    /// Canonical finalized-bundle bytes on this device.
    public let finalizedByteCount: Int64
    /// Derived `.htdtcapture` archive bytes — listed separately so
    /// "delete derived archives only" is always the safest first
    /// suggestion (#251/#394).
    public let archiveByteCount: Int64
    public let isLatest: Bool
    public let mark: CaptureRevisionMark
    public let recommendation: CaptureRetentionRecommendation
    public let blockers: [CaptureRetentionBlocker]
    public let warnings: [CaptureRetentionWarning]

    public var id: CaptureRevisionID { captureRevisionID }

    public var isDeletable: Bool { blockers.isEmpty }

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        finalizedAtUTC: String,
        finalizedByteCount: Int64,
        archiveByteCount: Int64,
        isLatest: Bool,
        mark: CaptureRevisionMark,
        recommendation: CaptureRetentionRecommendation,
        blockers: [CaptureRetentionBlocker],
        warnings: [CaptureRetentionWarning]
    ) {
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.finalizedAtUTC = finalizedAtUTC
        self.finalizedByteCount = finalizedByteCount
        self.archiveByteCount = archiveByteCount
        self.isLatest = isLatest
        self.mark = mark
        self.recommendation = recommendation
        self.blockers = blockers
        self.warnings = warnings
    }
}

/// The full retention picture of one series (issue #394): every
/// revision row plus the byte totals, so the preview can name what
/// stays and what could leave before any delete action exists.
public struct CaptureSeriesRetentionPreview:
    Sendable,
    Equatable
{
    public let captureSeriesID: CaptureSeriesID
    public let revisionCount: Int
    public let totalFinalizedBytes: Int64
    /// Sum of derived `.htdtcapture` archives — separately countable
    /// so the operator sees exactly the bytes "delete archives only"
    /// would reclaim.
    public let totalDerivedArchiveBytes: Int64
    public let rows: [CaptureRevisionRetentionRow]

    public var blockedCount: Int {
        rows.filter { !$0.isDeletable }.count
    }

    public var deleteCandidateCount: Int {
        rows.filter {
            $0.recommendation == .deleteCandidate
                && $0.isDeletable
        }.count
    }

    public init(
        captureSeriesID: CaptureSeriesID,
        revisionCount: Int,
        totalFinalizedBytes: Int64,
        totalDerivedArchiveBytes: Int64,
        rows: [CaptureRevisionRetentionRow]
    ) {
        self.captureSeriesID = captureSeriesID
        self.revisionCount = revisionCount
        self.totalFinalizedBytes = totalFinalizedBytes
        self.totalDerivedArchiveBytes = totalDerivedArchiveBytes
        self.rows = rows
    }
}

/// The preview a series delete or any chosen-revisions delete renders
/// before anything is removed (issue #394): revision count, the two
/// byte classes, per-revision outcomes with blockers and warnings,
/// and provenance notes (imported vs. local origin).
public struct CaptureLibraryDeletionPreview:
    Sendable,
    Equatable
{
    public struct RevisionOutcome:
        Sendable,
        Equatable,
        Identifiable
    {
        public let captureRevisionID: CaptureRevisionID
        public let canDelete: Bool
        public let blockers: [CaptureRetentionBlocker]
        public let warnings: [CaptureRetentionWarning]

        public var id: CaptureRevisionID {
            captureRevisionID
        }

        public init(
            captureRevisionID: CaptureRevisionID,
            canDelete: Bool,
            blockers: [CaptureRetentionBlocker],
            warnings: [CaptureRetentionWarning]
        ) {
            self.captureRevisionID = captureRevisionID
            self.canDelete = canDelete
            self.blockers = blockers
            self.warnings = warnings
        }
    }

    public let revisionCount: Int
    public let finalizedByteCount: Int64
    public let derivedArchiveByteCount: Int64
    /// True when at least one selected revision exists only as an
    /// export archive (an imported-or-trimmed revision with no local
    /// finalized directory).
    public let containsExportOnlyRecords: Bool
    public let outcomes: [RevisionOutcome]

    public var blockedCount: Int {
        outcomes.filter { !$0.canDelete }.count
    }

    public init(
        revisionCount: Int,
        finalizedByteCount: Int64,
        derivedArchiveByteCount: Int64,
        containsExportOnlyRecords: Bool,
        outcomes: [RevisionOutcome]
    ) {
        self.revisionCount = revisionCount
        self.finalizedByteCount = finalizedByteCount
        self.derivedArchiveByteCount = derivedArchiveByteCount
        self.containsExportOnlyRecords = containsExportOnlyRecords
        self.outcomes = outcomes
    }
}

public struct CaptureSeriesDeletionResult:
    Sendable,
    Equatable
{
    /// One revision the preview refused, with its blockers.
    public struct SkippedRevision: Sendable, Equatable {
        public let captureRevisionID: CaptureRevisionID
        public let blockers: [CaptureRetentionBlocker]

        public init(
            captureRevisionID: CaptureRevisionID,
            blockers: [CaptureRetentionBlocker]
        ) {
            self.captureRevisionID = captureRevisionID
            self.blockers = blockers
        }
    }

    /// One revision whose delete left surviving artifacts, with the
    /// inventory-reported reasons.
    public struct RemainingRevision: Sendable, Equatable {
        public let captureRevisionID: CaptureRevisionID
        public let artifacts:
            [PersistedCaptureRemainingArtifact]

        public init(
            captureRevisionID: CaptureRevisionID,
            artifacts: [PersistedCaptureRemainingArtifact]
        ) {
            self.captureRevisionID = captureRevisionID
            self.artifacts = artifacts
        }
    }

    /// Revisions whose finalized directory and export slot were
    /// removed.
    public let deleted: [CaptureRevisionID]
    /// Revisions the preview refused — each with its blockers.
    public let skipped: [SkippedRevision]
    /// Surviving artifacts reported by the inventory per revision.
    public let remaining: [RemainingRevision]

    public init(
        deleted: [CaptureRevisionID],
        skipped: [SkippedRevision],
        remaining: [RemainingRevision]
    ) {
        self.deleted = deleted
        self.skipped = skipped
        self.remaining = remaining
    }
}

/// The retention planner (issue #394): dependency-aware previews and
/// the series delete executor. All classification is derived from the
/// validated inventory and the durable ledgers — never from file
/// names — and deleting a parent never rewrites a child's lineage.
public enum CaptureLibraryRetentionPlanner {
    /// Per-revision retention rows for one series: latest revision
    /// and marked revisions keep; everything older and unmarked is a
    /// delete candidate the operator reviews — there is no "keep
    /// latest only" mode (#394).
    public static func seriesPreview(
        seriesID: CaptureSeriesID,
        records: [PersistedCaptureRecord],
        allRecords: [PersistedCaptureRecord],
        metadata: CaptureLibraryMetadataDocument,
        deliveryJobs: [HTDTDeliveryJob],
        missionRecords: [HTDTMissionRecord],
        receipts: [HTDTHandoffReceipt]
    ) -> CaptureSeriesRetentionPreview {
        let sorted = records.sorted {
            if $0.finalizedAtUTC != $1.finalizedAtUTC {
                return $0.finalizedAtUTC < $1.finalizedAtUTC
            }
            return $0.captureRevisionID.description
                < $1.captureRevisionID.description
        }
        let latestID = sorted.last?.captureRevisionID
        var rows: [CaptureRevisionRetentionRow] = []
        rows.reserveCapacity(sorted.count)
        for record in sorted {
            let mark = metadata.revisionMark(
                for: record.captureRevisionID
            )
            rows.append(
                row(
                    for: record,
                    mark: mark,
                    isLatest:
                        record.captureRevisionID == latestID,
                    allRecords: allRecords,
                    deliveryJobs: deliveryJobs,
                    missionRecords: missionRecords,
                    receipts: receipts
                )
            )
        }
        return CaptureSeriesRetentionPreview(
            captureSeriesID: seriesID,
            revisionCount: rows.count,
            totalFinalizedBytes: rows.reduce(0) {
                $0 + $1.finalizedByteCount
            },
            totalDerivedArchiveBytes: rows.reduce(0) {
                $0 + $1.archiveByteCount
            },
            rows: rows
        )
    }

    /// The deletion preview for a chosen set of revisions — the
    /// series-delete confirmation and any chosen-revision cleanup
    /// both render from this (issue #394).
    public static func deletionPreview(
        records: [PersistedCaptureRecord],
        allRecords: [PersistedCaptureRecord],
        metadata: CaptureLibraryMetadataDocument,
        deliveryJobs: [HTDTDeliveryJob],
        missionRecords: [HTDTMissionRecord],
        receipts: [HTDTHandoffReceipt]
    ) -> CaptureLibraryDeletionPreview {
        var outcomes: [
            CaptureLibraryDeletionPreview.RevisionOutcome
        ] = []
        outcomes.reserveCapacity(records.count)
        for record in records {
            let mark = metadata.revisionMark(
                for: record.captureRevisionID
            )
            let row = row(
                for: record,
                mark: mark,
                isLatest: false,
                allRecords: allRecords,
                deliveryJobs: deliveryJobs,
                missionRecords: missionRecords,
                receipts: receipts
            )
            outcomes.append(
                CaptureLibraryDeletionPreview.RevisionOutcome(
                    captureRevisionID: record.captureRevisionID,
                    canDelete: row.isDeletable,
                    blockers: row.blockers,
                    warnings: row.warnings
                )
            )
        }
        return CaptureLibraryDeletionPreview(
            revisionCount: records.count,
            finalizedByteCount: records.reduce(0) {
                $0 + ($1.finalizedByteCount ?? 0)
            },
            derivedArchiveByteCount: records.reduce(0) {
                $0 + ($1.exportArchiveByteCount ?? 0)
            },
            containsExportOnlyRecords: records.contains {
                $0.finalizedDirectory == nil
            },
            outcomes: outcomes
        )
    }

    /// Dependency-aware series delete (issue #394): every revision
    /// runs the same preview rules; blocked revisions are skipped and
    /// reported, deletable revisions go through the inventory's own
    /// identity-reconfirming removal. Metadata for deleted revisions
    /// and the emptied series entry are pruned in one document save.
    /// `includeProtected` is the explicit override that lets marked
    /// revisions delete; without it a marked revision is skipped.
    public static func deleteSeries(
        seriesID: CaptureSeriesID,
        records: [PersistedCaptureRecord],
        allRecords: [PersistedCaptureRecord],
        inventory: PersistedCaptureInventory,
        metadataStore: CaptureLibraryMetadataStore,
        deliveryJobs: [HTDTDeliveryJob],
        missionRecords: [HTDTMissionRecord],
        receipts: [HTDTHandoffReceipt],
        includeProtected: Bool = false
    ) -> CaptureSeriesDeletionResult {
        let metadata = (try? metadataStore.load())
            ?? CaptureLibraryMetadataDocument()
        let preview = deletionPreview(
            records: records,
            allRecords: allRecords,
            metadata: metadata,
            deliveryJobs: deliveryJobs,
            missionRecords: missionRecords,
            receipts: receipts
        )

        var deleted: [CaptureRevisionID] = []
        var skipped: [
            CaptureSeriesDeletionResult.SkippedRevision
        ] = []
        var remaining: [
            CaptureSeriesDeletionResult.RemainingRevision
        ] = []

        let recordByID = Dictionary(
            uniqueKeysWithValues: records.map {
                ($0.captureRevisionID, $0)
            }
        )
        for outcome in preview.outcomes {
            var blockers = outcome.blockers
            // A mark blocks only without the explicit override — with
            // it, the operator has already acknowledged.
            if includeProtected {
                blockers = blockers.filter {
                    $0 != .protectedMark
                }
            }
            guard blockers.isEmpty,
                  recordByID[outcome.captureRevisionID] != nil
            else {
                skipped.append(
                    CaptureSeriesDeletionResult.SkippedRevision(
                        captureRevisionID: outcome.captureRevisionID,
                        blockers: blockers
                    )
                )
                continue
            }
            let result = inventory.deleteCapture(
                captureRevisionID: outcome.captureRevisionID
            )
            if !result.remaining.isEmpty {
                // Partial or refused removal lands in `remaining`
                // with its reason — neither fully deleted nor a
                // clean skip.
                remaining.append(
                    CaptureSeriesDeletionResult
                        .RemainingRevision(
                            captureRevisionID:
                                outcome.captureRevisionID,
                            artifacts: result.remaining
                        )
                )
            }
            if result.succeeded {
                deleted.append(outcome.captureRevisionID)
            }
        }

        // Prune in one write: the emptied series entry/state and the
        // deleted revisions' entries/marks leave no dangling rows in
        // the metadata document.
        if !deleted.isEmpty {
            try? pruneSeries(
                seriesID: seriesID,
                deletedRevisionIDs: deleted,
                store: metadataStore
            )
        }

        return CaptureSeriesDeletionResult(
            deleted: deleted,
            skipped: skipped,
            remaining: remaining
        )
    }

    /// Removes a series' metadata + lifecycle state and the deleted
    /// revisions' entries/marks in a single document write.
    private static func pruneSeries(
        seriesID: CaptureSeriesID,
        deletedRevisionIDs: [CaptureRevisionID],
        store: CaptureLibraryMetadataStore
    ) throws {
        var document = try store.load()
        var series = document.series
        var revisions = document.revisions
        var states = document.seriesStates
        var marks = document.revisionMarks
        series.removeValue(forKey: seriesID.description)
        states.removeValue(forKey: seriesID.description)
        for id in deletedRevisionIDs {
            revisions.removeValue(forKey: id.description)
            marks.removeValue(forKey: id.description)
        }
        try store.save(
            CaptureLibraryMetadataDocument(
                series: series,
                revisions: revisions,
                seriesStates: states,
                revisionMarks: marks
            )
        )
    }

    /// One revision's row: byte breakdown, mark, recommendation, and
    /// the full dependency picture — shared by the series preview and
    /// the deletion preview so both surfaces classify identically.
    private static func row(
        for record: PersistedCaptureRecord,
        mark: CaptureRevisionMark,
        isLatest: Bool,
        allRecords: [PersistedCaptureRecord],
        deliveryJobs: [HTDTDeliveryJob],
        missionRecords: [HTDTMissionRecord],
        receipts: [HTDTHandoffReceipt]
    ) -> CaptureRevisionRetentionRow {
        var blockers: [CaptureRetentionBlocker] = []
        var warnings: [CaptureRetentionWarning] = []

        // Delivery queue: a non-terminal job still needs its
        // queue-owned payload of this revision's archive bytes — the
        // operator cancels it before the revision can leave.
        for job in deliveryJobs where job.needsPayload {
            if job.captureRevisionID == record.captureRevisionID {
                blockers.append(.pendingDeliveryJob(job.deliveryJobID))
            }
        }
        if mark.isProtected {
            blockers.append(.protectedMark)
        }

        // Lineage: revisions that name this one as parent keep their
        // declared lineage — deleting the parent never rewrites or
        // reparents them; the preview states the consequence.
        let children = allRecords.filter {
            $0.captureRevisionID != record.captureRevisionID
                && ($0.finalizedValidation?.manifest.parentRevisionID
                        ?? $0.exportValidation?.manifest
                            .parentRevisionID)
                    == record.captureRevisionID
        }
        if !children.isEmpty {
            warnings.append(.parentOfRevisions(children.count))
        }

        // Mission linkage: any inbox record that associates this
        // revision is named so deletion is an informed decision.
        for mission in missionRecords
        where mission.associatedCaptureRevisionIDs.contains(
            record.captureRevisionID.description
        ) {
            warnings.append(.linkedToMission(mission.recordID))
        }

        // Receipt history + only-local-copy: receipts remain as the
        // historical record even after the bytes leave — the UI must
        // say they no longer prove the bundle is inspectable.
        let revisionReceipts = receipts.filter {
            $0.captureRevisionID == record.captureRevisionID
        }
        if !revisionReceipts.isEmpty {
            warnings.append(.handoffReceipts(revisionReceipts.count))
        }
        let delivered = revisionReceipts.contains {
            $0.outcome == "delivered"
        }
        if !delivered {
            warnings.append(.onlyLocalCopy)
        }

        let recommendation: CaptureRetentionRecommendation =
            isLatest || mark.isProtected ? .keep : .deleteCandidate

        return CaptureRevisionRetentionRow(
            captureRevisionID: record.captureRevisionID,
            captureSeriesID: record.captureSeriesID,
            finalizedAtUTC: record.finalizedAtUTC,
            finalizedByteCount: record.finalizedByteCount ?? 0,
            archiveByteCount: record.exportArchiveByteCount ?? 0,
            isLatest: isLatest,
            mark: mark,
            recommendation: recommendation,
            blockers: blockers,
            warnings: warnings
        )
    }
}
