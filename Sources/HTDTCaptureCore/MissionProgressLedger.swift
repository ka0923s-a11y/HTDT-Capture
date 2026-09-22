import Foundation

/// Which plan checklist family an item belongs to — stored on every
/// ledger entry so the per-kind aggregation replays without the plan
/// (issue #397).
public enum MissionLedgerTaskKind: String, Codable, Sendable, Equatable {
    case entityChecklist = "entity_checklist"
    case measurementRequest = "measurement_request"
    case surfaceReview = "surface_review"
    case semanticTask = "semantic_task"
    case evidenceTask = "evidence_task"
}

public enum MissionProgressLedgerError: Error, Sendable, Equatable {
    case emptyField
    case invalidTimestamp
    case invalidSHA256
    /// The status document's plan identity does not exactly match the
    /// mission record's imported plan — fulfillments are only
    /// aggregated when they are *exact compatible* (#397).
    case incompatibleSourceDocument
    /// A status-document item id does not exist in the mission plan.
    case unknownItemID
    case unknownMissionRecord
    case unreadableDocument
    case schemaMismatch
    case encodedDocumentMismatch
}

/// One accepted item outcome from one immutable revision's persisted
/// status document (issue #397). Entries are append-only history:
/// replacement/retake lands as a new entry that names the entry it
/// supersedes — superseded rows are kept verbatim.
public struct MissionProgressLedgerEntry: Codable, Sendable, Equatable {
    /// Device-local entry identity (UUIDv4) — referenced by
    /// `supersedes` on later entries.
    public let entryID: String
    public let taskItemID: String
    public let taskKind: MissionLedgerTaskKind
    public let requirement: TaskPlanRequirement
    public let outcome: TaskPlanItemOutcome
    public let captureRevisionID: CaptureRevisionID
    /// Exact fulfilling record/evidence identity, when the status
    /// document resolved one.
    public let fulfillmentRef: String?
    /// Typed fulfillment link for entity/measurement items.
    public let fulfillment: TaskFulfillmentLink?
    /// SHA-256 of the source `session/task-plan-status.json` bytes.
    public let sourceStatusSHA256: EvidenceSHA256
    /// When the ledger accepted this outcome (ingest order is the
    /// precedence — never `finalized_at`).
    public let acceptedAtUTC: String
    /// The previous winning entry for this item, when this entry is a
    /// replacement/retake.
    public let supersedes: String?

    public init(
        entryID: String,
        taskItemID: String,
        taskKind: MissionLedgerTaskKind,
        requirement: TaskPlanRequirement,
        outcome: TaskPlanItemOutcome,
        captureRevisionID: CaptureRevisionID,
        fulfillmentRef: String? = nil,
        fulfillment: TaskFulfillmentLink? = nil,
        sourceStatusSHA256: EvidenceSHA256,
        acceptedAtUTC: String,
        supersedes: String? = nil
    ) throws {
        guard UUID(canonicalUUIDv4Text: entryID) != nil else {
            throw MissionProgressLedgerError.emptyField
        }
        guard !taskItemID.isEmpty else {
            throw MissionProgressLedgerError.emptyField
        }
        guard acceptedAtUTC.hasSuffix("Z") else {
            throw MissionProgressLedgerError.invalidTimestamp
        }
        self.entryID = entryID
        self.taskItemID = taskItemID
        self.taskKind = taskKind
        self.requirement = requirement
        self.outcome = outcome
        self.captureRevisionID = captureRevisionID
        self.fulfillmentRef = fulfillmentRef
        self.fulfillment = fulfillment
        self.sourceStatusSHA256 = sourceStatusSHA256
        self.acceptedAtUTC = acceptedAtUTC
        self.supersedes = supersedes
    }

    private enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case taskItemID = "task_item_id"
        case taskKind = "task_kind"
        case requirement
        case outcome
        case captureRevisionID = "capture_revision_id"
        case fulfillmentRef = "fulfillment_ref"
        case fulfillment
        case sourceStatusSHA256 = "source_status_sha256"
        case acceptedAtUTC = "accepted_at"
        case supersedes
    }
}

/// Explicit mission-level waiver (issue #397): a revision-local
/// `skipped`/`unavailable` outcome never waives a required item at the
/// mission level — only an auditable waiver recorded here does.
public struct MissionProgressWaiver: Codable, Sendable, Equatable {
    /// Device-local waiver identity (UUIDv4).
    public let waiverID: String
    public let taskItemID: String
    public let waivedAtUTC: String
    public let note: String?

    public init(
        waiverID: String,
        taskItemID: String,
        waivedAtUTC: String,
        note: String? = nil
    ) throws {
        guard UUID(canonicalUUIDv4Text: waiverID) != nil else {
            throw MissionProgressLedgerError.emptyField
        }
        guard !taskItemID.isEmpty else {
            throw MissionProgressLedgerError.emptyField
        }
        guard waivedAtUTC.hasSuffix("Z") else {
            throw MissionProgressLedgerError.invalidTimestamp
        }
        self.waiverID = waiverID
        self.taskItemID = taskItemID
        self.waivedAtUTC = waivedAtUTC
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case waiverID = "waiver_id"
        case taskItemID = "task_item_id"
        case waivedAtUTC = "waived_at"
        case note
    }
}

/// One mission's ledger slice: every accepted item outcome plus every
/// explicit waiver, both in acceptance order.
public struct MissionProgressLedgerRecord: Codable, Sendable, Equatable {
    /// `HTDTMissionRecord.recordID` this slice belongs to.
    public let missionRecordID: String
    /// Plan identity the fulfillments must exactly match.
    public let planID: String
    public let planSHA256: String
    public var entries: [MissionProgressLedgerEntry]
    public var waivers: [MissionProgressWaiver]

    public init(
        missionRecordID: String,
        planID: String,
        planSHA256: String,
        entries: [MissionProgressLedgerEntry] = [],
        waivers: [MissionProgressWaiver] = []
    ) throws {
        guard UUID(canonicalUUIDv4Text: missionRecordID) != nil else {
            throw MissionProgressLedgerError.emptyField
        }
        guard !planID.isEmpty else {
            throw MissionProgressLedgerError.emptyField
        }
        guard planSHA256.count == 64,
              planSHA256.allSatisfy(\.isHexDigit)
        else {
            throw MissionProgressLedgerError.invalidSHA256
        }
        self.missionRecordID = missionRecordID
        self.planID = planID
        self.planSHA256 = planSHA256
        self.entries = entries
        self.waivers = waivers
    }

    private enum CodingKeys: String, CodingKey {
        case missionRecordID = "mission_record_id"
        case planID = "plan_id"
        case planSHA256 = "plan_sha256"
        case entries
        case waivers
    }
}

/// Replayed mission completeness for one item (#397): derived, never
/// stored — completeness is always recomputed from the append-only
/// entries, not persisted as a percentage.
public struct MissionProgressItemResolution: Sendable, Equatable {
    public let taskItemID: String
    public let taskKind: MissionLedgerTaskKind
    public let requirement: TaskPlanRequirement
    /// The item's current winning entry — the most recent accepted
    /// outcome never superseded by a later entry. Nil when no
    /// revision has reported the item.
    public let acceptedEntry: MissionProgressLedgerEntry?
    /// All accepted entries for the item, oldest first (retake
    /// history is preserved).
    public let history: [MissionProgressLedgerEntry]
    /// True when the item is explicitly waived at mission level.
    public let waived: Bool

    /// The winning outcome — `.pending` when never reported.
    public var outcome: TaskPlanItemOutcome {
        acceptedEntry?.outcome ?? .pending
    }

    /// Completed through capture evidence, or covered by an explicit
    /// mission waiver.
    public var resolved: Bool {
        outcome == .completed || waived
    }
}

/// Replayable mission progress for a single task kind.
public struct MissionProgressKindSummary: Sendable, Equatable {
    public let kind: MissionLedgerTaskKind
    public var itemCount: Int = 0
    public var requiredCount: Int = 0
    public var completedCount: Int = 0
    public var requiredOutstandingCount: Int = 0
}

/// The mission's completeness replayed from ledger entries (issue
/// #397): per-item winners, per-kind aggregation, and the strict
/// field-complete verdict. Field-complete means every *required* item
/// completed through capture evidence; an explicit waiver only
/// resolves — it does not falsify field completion records.
public struct MissionProgressEvaluation: Sendable, Equatable {
    public let missionRecordID: String
    /// Every plan item in plan order with its replayed resolution.
    public let items: [MissionProgressItemResolution]
    /// Per-task-kind aggregation.
    public let kinds: [MissionProgressKindSummary]
    /// Items with more than one non-superseded winning entry — a fork
    /// where two heads both claimed the item. The last-accepted entry
    /// still wins deterministically, but the contest is surfaced.
    public let contestedItemIDs: [String]

    public var completedItemIDs: [String] {
        items.filter { $0.outcome == .completed }.map(\.taskItemID)
    }

    public var outstandingItemIDs: [String] {
        items.filter { !$0.resolved }.map(\.taskItemID)
    }

    public var waivedItemIDs: [String] {
        items.filter { $0.waived }.map(\.taskItemID)
    }

    /// Strict field completeness: every required item's winning
    /// outcome is `completed`. Waivers do not count — they resolve
    /// responsibility, not the evidence verdict.
    public var fieldComplete: Bool {
        items.allSatisfy {
            $0.requirement != .required || $0.outcome == .completed
        }
    }

    /// Every required item is completed or explicitly waived.
    public var requiredItemsResolved: Bool {
        items.allSatisfy {
            $0.requirement != .required || $0.resolved
        }
    }
}

/// App-local mission aggregate fulfillment authority (issue #397):
/// `<captureRoot>/mission-progress-ledger.json`. Each finalized
/// revision's `session/task-plan-status.json` is ingested once —
/// replays never rewrite entries, so completeness is always
/// recomputed from history. Aggregation is checklist-item level only:
/// it is *not* spatial fusion and never substitutes for the
/// cross-revision registration authority (#395), and field-complete
/// stays separate from delivered (#387).
public struct MissionProgressLedgerStore: Sendable {
    public static let filename = "mission-progress-ledger.json"

    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.mission-progress-ledger"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var records: [MissionProgressLedgerRecord]

        public init(records: [MissionProgressLedgerRecord] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.records = records
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case records
        }
    }

    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(Self.filename)
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Document()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MissionProgressLedgerError.unreadableDocument
        }
        guard
            let decoded = try? JSONDecoder().decode(
                Document.self,
                from: data
            ),
            decoded.schema == Document.schema,
            decoded.schemaVersion == Document.schemaVersion
        else {
            throw MissionProgressLedgerError.schemaMismatch
        }
        return decoded
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes, .prettyPrinted,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                Document.self,
                from: data
            ),
            decoded == document
        else {
            throw MissionProgressLedgerError.encodedDocumentMismatch
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let temporary = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)"
        )
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: temporary
        )
    }

    /// The mission's stored slice, or nil when nothing has been
    /// ingested for it yet.
    public func record(
        for missionRecordID: String
    ) throws -> MissionProgressLedgerRecord? {
        try load().records.first {
            $0.missionRecordID == missionRecordID
        }
    }

    /// Accepted item ids the mission already resolved to `completed`.
    public func completedItemIDs(
        for missionRecordID: String
    ) throws -> [String] {
        guard let record = try record(for: missionRecordID) else {
            return []
        }
        let superseded = Set(record.entries.compactMap(\.supersedes))
        var winners: [String: MissionProgressLedgerEntry] = [:]
        for entry in record.entries
        where !superseded.contains(entry.entryID) {
            winners[entry.taskItemID] = entry
        }
        return winners.values
            .filter { $0.outcome == .completed }
            .map(\.taskItemID)
            .sorted()
    }

    /// Ingests one finalized revision's persisted status document as
    /// accepted item outcomes (issue #397). Requires exact plan
    /// compatibility — plan id and sha-256 must equal the mission
    /// record's imported plan — and marks each entry as superseding
    /// the item's current winner. Same-document re-ingest is
    /// idempotent: an entry set already recorded for
    /// (revision, digest) appends nothing.
    @discardableResult
    public func ingestStatusDocument(
        _ statusDocument: CaptureTaskPlanStatusDocument,
        for record: HTDTMissionRecord,
        plan: HTDTCaptureTaskPlan,
        sourceStatusSHA256: EvidenceSHA256? = nil,
        acceptedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> [MissionProgressLedgerEntry] {
        guard statusDocument.planID == record.planID,
              statusDocument.planSHA256.description == record.planSHA256
        else {
            throw MissionProgressLedgerError.incompatibleSourceDocument
        }
        var kindByItem: [String: MissionLedgerTaskKind] = [:]
        var requirementByItem: [String: TaskPlanRequirement] = [:]
        for item in plan.entityChecklist {
            kindByItem[item.itemID] = .entityChecklist
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.measurementRequests {
            kindByItem[item.itemID] = .measurementRequest
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.surfaceReviewTasks {
            kindByItem[item.itemID] = .surfaceReview
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.semanticTasks {
            kindByItem[item.itemID] = .semanticTask
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.evidenceTasks {
            kindByItem[item.itemID] = .evidenceTask
            requirementByItem[item.itemID] = item.requirement
        }
        let statusSHA256 = try sourceStatusSHA256
            ?? EvidenceIntegrity.sha256(
                of: encodedStatusDocument(statusDocument)
            )
        var document = try load()
        var ledgerRecord: MissionProgressLedgerRecord
        if let index = document.records.firstIndex(where: {
            $0.missionRecordID == record.recordID
        }) {
            ledgerRecord = document.records[index]
            // Idempotent re-ingest: an identical entry set for this
            // (revision, digest) already landed — append nothing.
            let existing = ledgerRecord.entries.filter {
                $0.captureRevisionID
                    == statusDocument.captureRevisionID
                    && $0.sourceStatusSHA256 == statusSHA256
            }
            if existing.count == statusDocument.items.count {
                return []
            }
        } else {
            ledgerRecord = try MissionProgressLedgerRecord(
                missionRecordID: record.recordID,
                planID: record.planID,
                planSHA256: record.planSHA256
            )
        }

        let superseded = Set(
            ledgerRecord.entries.compactMap(\.supersedes)
        )
        var winners: [String: MissionProgressLedgerEntry] = [:]
        for entry in ledgerRecord.entries
        where !superseded.contains(entry.entryID) {
            winners[entry.taskItemID] = entry
        }

        var appended: [MissionProgressLedgerEntry] = []
        for item in statusDocument.items {
            guard let kind = kindByItem[item.itemID],
                  let requirement = requirementByItem[item.itemID]
            else {
                throw MissionProgressLedgerError.unknownItemID
            }
            let entry = try MissionProgressLedgerEntry(
                entryID: UUID().uuidString.lowercased(),
                taskItemID: item.itemID,
                taskKind: kind,
                requirement: requirement,
                outcome: item.outcome,
                captureRevisionID: statusDocument.captureRevisionID,
                fulfillmentRef: item.fulfillmentRef,
                fulfillment: item.fulfillment,
                sourceStatusSHA256: statusSHA256,
                acceptedAtUTC: acceptedAtUTC,
                supersedes: winners[item.itemID]?.entryID
            )
            winners[item.itemID] = entry
            ledgerRecord.entries.append(entry)
            appended.append(entry)
        }

        if let index = document.records.firstIndex(where: {
            $0.missionRecordID == record.recordID
        }) {
            document.records[index] = ledgerRecord
        } else {
            document.records.append(ledgerRecord)
        }
        try save(document)
        return appended
    }

    /// Records an explicit mission-level waiver for a plan item
    /// (issue #397). Auditable — the waiver appends, it never deletes
    /// or rewrites accepted entries.
    @discardableResult
    public func waive(
        itemID: String,
        for record: HTDTMissionRecord,
        plan: HTDTCaptureTaskPlan,
        note: String? = nil,
        waivedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> MissionProgressWaiver {
        guard plan.allItemIDs.contains(itemID) else {
            throw MissionProgressLedgerError.unknownItemID
        }
        var document = try load()
        var ledgerRecord: MissionProgressLedgerRecord
        if let index = document.records.firstIndex(where: {
            $0.missionRecordID == record.recordID
        }) {
            ledgerRecord = document.records[index]
        } else {
            ledgerRecord = try MissionProgressLedgerRecord(
                missionRecordID: record.recordID,
                planID: record.planID,
                planSHA256: record.planSHA256
            )
        }
        let waiver = try MissionProgressWaiver(
            waiverID: UUID().uuidString.lowercased(),
            taskItemID: itemID,
            waivedAtUTC: waivedAtUTC,
            note: note
        )
        ledgerRecord.waivers.append(waiver)
        if let index = document.records.firstIndex(where: {
            $0.missionRecordID == record.recordID
        }) {
            document.records[index] = ledgerRecord
        } else {
            document.records.append(ledgerRecord)
        }
        try save(document)
        return waiver
    }

    /// Replays the mission's completeness from its stored entries —
    /// the verdict is derived fresh on every call, never read back
    /// from a stored percentage.
    public func evaluate(
        record: HTDTMissionRecord,
        plan: HTDTCaptureTaskPlan
    ) throws -> MissionProgressEvaluation {
        let stored = try self.record(for: record.recordID)
        let entries = stored?.entries ?? []
        let waivedItemIDs = Set(
            (stored?.waivers ?? []).map(\.taskItemID)
        )
        let superseded = Set(entries.compactMap(\.supersedes))

        var order: [String] = []
        var kindByItem: [String: MissionLedgerTaskKind] = [:]
        var requirementByItem: [String: TaskPlanRequirement] = [:]
        for item in plan.entityChecklist {
            order.append(item.itemID)
            kindByItem[item.itemID] = .entityChecklist
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.measurementRequests {
            order.append(item.itemID)
            kindByItem[item.itemID] = .measurementRequest
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.surfaceReviewTasks {
            order.append(item.itemID)
            kindByItem[item.itemID] = .surfaceReview
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.semanticTasks {
            order.append(item.itemID)
            kindByItem[item.itemID] = .semanticTask
            requirementByItem[item.itemID] = item.requirement
        }
        for item in plan.evidenceTasks {
            order.append(item.itemID)
            kindByItem[item.itemID] = .evidenceTask
            requirementByItem[item.itemID] = item.requirement
        }
        // Entries naming items no longer in the plan still appear —
        // history is never dropped — after every known item.
        let known = Set(order)
        for entry in entries where !known.contains(entry.taskItemID) {
            order.append(entry.taskItemID)
            kindByItem[entry.taskItemID] = entry.taskKind
            requirementByItem[entry.taskItemID] = entry.requirement
        }

        var contested: [String] = []
        var resolutions: [MissionProgressItemResolution] = []
        var seen = Set<String>()
        for itemID in order where seen.insert(itemID).inserted {
            let history = entries.filter {
                $0.taskItemID == itemID
            }
            let live = history.filter {
                !superseded.contains($0.entryID)
            }
            if live.count > 1 {
                contested.append(itemID)
            }
            resolutions.append(
                MissionProgressItemResolution(
                    taskItemID: itemID,
                    taskKind: kindByItem[itemID] ?? .entityChecklist,
                    requirement: requirementByItem[itemID] ?? .required,
                    acceptedEntry: live.last,
                    history: history,
                    waived: waivedItemIDs.contains(itemID)
                )
            )
        }

        var kinds: [MissionProgressKindSummary] = []
        for resolution in resolutions {
            if let index = kinds.firstIndex(where: {
                $0.kind == resolution.taskKind
            }) {
                kinds[index].itemCount += 1
                if resolution.requirement == .required {
                    kinds[index].requiredCount += 1
                    if resolution.outcome != .completed {
                        kinds[index].requiredOutstandingCount += 1
                    }
                }
                if resolution.outcome == .completed {
                    kinds[index].completedCount += 1
                }
            } else {
                var summary = MissionProgressKindSummary(
                    kind: resolution.taskKind
                )
                summary.itemCount = 1
                if resolution.requirement == .required {
                    summary.requiredCount = 1
                    if resolution.outcome != .completed {
                        summary.requiredOutstandingCount = 1
                    }
                }
                if resolution.outcome == .completed {
                    summary.completedCount = 1
                }
                kinds.append(summary)
            }
        }

        return MissionProgressEvaluation(
            missionRecordID: record.recordID,
            items: resolutions,
            kinds: kinds,
            contestedItemIDs: contested
        )
    }

    private func encodedStatusDocument(
        _ statusDocument: CaptureTaskPlanStatusDocument
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        return try encoder.encode(statusDocument)
    }
}
