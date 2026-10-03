import Foundation

public enum RepairTaskError: Error, Sendable, Equatable {
    case emptyField
    case invalidTimestamp
    case duplicateTaskID
    case unknownTaskID
    case unsupportedSchema
    case encodedDocumentMismatch
    case unreadableDocument
}

/// The corrective action an HTDT diagnostic maps onto (issue bolph71656-ai/HTDT-Capture#321).
/// The mapping is the authority boundary: an HTDT diagnostic is task
/// intent, never observation truth, and a spatial repair always
/// produces a fresh coordinate authority.
public enum RepairTaskKind: String, Codable, Sendable, Equatable {
    /// Labels/roles/values/equipment corrections — no new spatial
    /// evidence. Rides the existing annotation-authority edit path.
    case semanticCorrection = "semantic_correction"
    /// Additional evidence bound to the same live coordinate space —
    /// only possible while that authority is still open.
    case sameCoordinateEvidence = "same_coordinate_evidence"
    /// A spatial defect: the repair is a new revision with its own
    /// coordinate authority; the source capture stays immutable.
    case freshRescan = "fresh_rescan"
    /// An external/manual instrument reading is needed to verify or
    /// supply a measurement.
    case externalMeasurement = "external_measurement"
}

/// One targeted recapture/correction task issued by HTDT. Each task
/// pins a machine-readable issue code, a human-readable reason, the
/// evidence the repair must produce, and the entity/region/reference
/// it targets.
public struct HTDTRepairTask: Codable, Sendable, Equatable {
    public let taskID: String
    public let issueCode: String
    public let kind: RepairTaskKind
    public let requirement: TaskPlanRequirement
    /// Human-readable explanation the operator acts on.
    public let reason: String
    /// The evidence class the repair must produce.
    public let requiredEvidenceType: String
    /// Optional plan-space reference (entity/region/reference) the
    /// task targets — a reference for the operator, never capture
    /// truth.
    public let targetRef: String?

    public init(
        taskID: String,
        issueCode: String,
        kind: RepairTaskKind,
        requirement: TaskPlanRequirement,
        reason: String,
        requiredEvidenceType: String,
        targetRef: String? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(taskID)
        let normalizedCode = SchemaOwnedText.nfc(issueCode)
        let normalizedReason = SchemaOwnedText.nfc(reason)
        let normalizedEvidence = SchemaOwnedText.nfc(
            requiredEvidenceType
        )
        guard !normalizedID.isEmpty,
              !normalizedCode.isEmpty,
              !normalizedReason.isEmpty,
              !normalizedEvidence.isEmpty
        else {
            throw RepairTaskError.emptyField
        }
        self.taskID = normalizedID
        self.issueCode = normalizedCode
        self.kind = kind
        self.requirement = requirement
        self.reason = normalizedReason
        self.requiredEvidenceType = normalizedEvidence
        self.targetRef = SchemaOwnedText.nfc(targetRef)
    }

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case issueCode = "issue_code"
        case kind
        case requirement
        case reason
        case requiredEvidenceType = "required_evidence_type"
        case targetRef = "target_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            taskID: container.decode(String.self, forKey: .taskID),
            issueCode: container.decode(
                String.self,
                forKey: .issueCode
            ),
            kind: container.decode(RepairTaskKind.self, forKey: .kind),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            reason: container.decode(String.self, forKey: .reason),
            requiredEvidenceType: container.decode(
                String.self,
                forKey: .requiredEvidenceType
            ),
            targetRef: container.decodeIfPresent(
                String.self,
                forKey: .targetRef
            )
        )
    }
}

/// A versioned HTDT repair/follow-up task plan (issue bolph71656-ai/HTDT-Capture#321): the
/// targeted recapture/correction list HTDT returns after ingestion or
/// promotion diagnostics. The plan pins the exact source capture
/// revision, its bundle digest, and the ingestion receipt it responds
/// to, so a returned task can never be mistaken for a generic request
/// or replayed against the wrong capture.
public struct HTDTRepairTaskPlan: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture-repair-task-plan"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let planID: String
    public let planVersion: String
    public let projectRef: String
    public let roomName: String
    /// The finalized Capture revision the diagnostics apply to.
    public let sourceCaptureRevisionID: String
    /// The bundle digest HTDT ingested — binds the plan to the exact
    /// bytes it describes.
    public let sourceBundleDigest: String
    /// The ingestion receipt/transaction this plan answers.
    public let ingestionReceiptRef: String
    public let issuedAtUTC: String?
    /// Originating software + protocol version for audit.
    public let issuedBySoftware: String
    public let issuedByProtocolVersion: String
    public let tasks: [HTDTRepairTask]

    public init(
        planID: String,
        planVersion: String,
        projectRef: String,
        roomName: String,
        sourceCaptureRevisionID: String,
        sourceBundleDigest: String,
        ingestionReceiptRef: String,
        issuedAtUTC: String? = nil,
        issuedBySoftware: String,
        issuedByProtocolVersion: String,
        tasks: [HTDTRepairTask]
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(planID)
        let normalizedVersion = SchemaOwnedText.nfc(planVersion)
        let normalizedProject = SchemaOwnedText.nfc(projectRef)
        let normalizedRoom = SchemaOwnedText.nfc(roomName)
        let normalizedRevision = SchemaOwnedText.nfc(
            sourceCaptureRevisionID
        )
        let normalizedDigest = SchemaOwnedText.nfc(
            sourceBundleDigest
        )
        let normalizedReceipt = SchemaOwnedText.nfc(
            ingestionReceiptRef
        )
        let normalizedSoftware = SchemaOwnedText.nfc(
            issuedBySoftware
        )
        let normalizedProtocol = SchemaOwnedText.nfc(
            issuedByProtocolVersion
        )
        guard !normalizedID.isEmpty,
              !normalizedVersion.isEmpty,
              !normalizedProject.isEmpty,
              !normalizedRoom.isEmpty,
              !normalizedRevision.isEmpty,
              !normalizedDigest.isEmpty,
              !normalizedReceipt.isEmpty,
              !normalizedSoftware.isEmpty,
              !normalizedProtocol.isEmpty
        else {
            throw RepairTaskError.emptyField
        }
        if let issuedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(issuedAtUTC)
            else {
                throw RepairTaskError.invalidTimestamp
            }
        }
        guard Set(tasks.map(\.taskID)).count == tasks.count else {
            throw RepairTaskError.duplicateTaskID
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.planID = normalizedID
        self.planVersion = normalizedVersion
        self.projectRef = normalizedProject
        self.roomName = normalizedRoom
        self.sourceCaptureRevisionID = normalizedRevision
        self.sourceBundleDigest = normalizedDigest
        self.ingestionReceiptRef = normalizedReceipt
        self.issuedAtUTC = issuedAtUTC
        self.issuedBySoftware = normalizedSoftware
        self.issuedByProtocolVersion = normalizedProtocol
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case projectRef = "project_ref"
        case roomName = "room_name"
        case sourceCaptureRevisionID = "source_capture_revision_id"
        case sourceBundleDigest = "source_bundle_digest"
        case ingestionReceiptRef = "ingestion_receipt_ref"
        case issuedAtUTC = "issued_at"
        case issuedBySoftware = "issued_by_software"
        case issuedByProtocolVersion = "issued_by_protocol_version"
        case tasks
    }

    /// Decodes an imported plan. Malformed bytes, unsupported schema
    /// versions, and semantic violations all fail closed — a bad plan
    /// is rejected at import, never partially trusted.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw RepairTaskError.unsupportedSchema
        }
        try self.init(
            planID: container.decode(String.self, forKey: .planID),
            planVersion: container.decode(
                String.self,
                forKey: .planVersion
            ),
            projectRef: container.decode(
                String.self,
                forKey: .projectRef
            ),
            roomName: container.decode(String.self, forKey: .roomName),
            sourceCaptureRevisionID: container.decode(
                String.self,
                forKey: .sourceCaptureRevisionID
            ),
            sourceBundleDigest: container.decode(
                String.self,
                forKey: .sourceBundleDigest
            ),
            ingestionReceiptRef: container.decode(
                String.self,
                forKey: .ingestionReceiptRef
            ),
            issuedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .issuedAtUTC
            ),
            issuedBySoftware: container.decode(
                String.self,
                forKey: .issuedBySoftware
            ),
            issuedByProtocolVersion: container.decode(
                String.self,
                forKey: .issuedByProtocolVersion
            ),
            tasks: container.decode(
                [HTDTRepairTask].self,
                forKey: .tasks
            )
        )
    }
}

/// The exact imported bytes of a repair plan plus its identity digest.
/// The app-local ledger stores the decoded plan; bundles only ever
/// carry the link document that references it.
public struct HTDTRepairTaskPlanImport: Sendable, Equatable {
    public let plan: HTDTRepairTaskPlan
    public let data: Data
    public let planSHA256: EvidenceSHA256

    public init(data: Data) throws {
        let plan = try JSONDecoder().decode(
            HTDTRepairTaskPlan.self,
            from: data
        )
        self.plan = plan
        self.data = data
        self.planSHA256 = EvidenceIntegrity.sha256(of: data)
    }

    /// Canonical re-encoding for a plan decoded in-process (e.g. an
    /// ingestion-response body) so the ledger and repair link can pin
    /// a stable digest of the plan bytes.
    public init(plan: HTDTRepairTaskPlan) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(plan)
        self.plan = plan
        self.data = data
        self.planSHA256 = EvidenceIntegrity.sha256(of: data)
    }
}

/// One inbound HTDT ingestion/promotion diagnostic before mapping
/// (issue bolph71656-ai/HTDT-Capture#321): a machine-readable issue code plus the human reason
/// and optional target reference HTDT attached.
public struct HTDTIngestionDiagnostic: Sendable, Equatable {
    public let issueCode: String
    public let reason: String
    public let targetRef: String?
    public let requirement: TaskPlanRequirement

    public init(
        issueCode: String,
        reason: String,
        targetRef: String? = nil,
        requirement: TaskPlanRequirement = .required
    ) {
        self.issueCode = issueCode
        self.reason = reason
        self.targetRef = targetRef
        self.requirement = requirement
    }
}

/// Maps inbound HTDT diagnostics onto targeted Capture repair tasks
/// (issue bolph71656-ai/HTDT-Capture#321). The mapping is deliberately conservative: an
/// unrecognized issue code always degrades to `fresh_rescan` — the
/// only repair that produces a fresh coordinate authority — rather
/// than guessing at a weaker corrective action.
public enum HTDTRepairTaskMapping {
    /// Known ingestion/promotion issue codes and the corrective
    /// action they imply.
    public static func taskKind(
        forIssueCode code: String
    ) -> RepairTaskKind {
        switch code {
        case "annotation_mismatch",
             "label_error",
             "role_mismatch",
             "channel_role_mismatch",
             "quantity_type_mismatch",
             "catalog_outdated",
             "equipment_identity_mismatch":
            return .semanticCorrection
        case "evidence_missing",
             "insufficient_evidence",
             "unverifiable",
             "verification_failed",
             "opening_unreviewed",
             "frame_missing":
            return .sameCoordinateEvidence
        case "measurement_unverified",
             "measurement_deviation",
             "dimension_mismatch",
             "calibration_suspect",
             "scale_check_failed":
            return .externalMeasurement
        case "coverage_gap",
             "geometry_missing",
             "tracking_loss",
             "insufficient_overlap",
             "roomplan_failed",
             "coordinate_authority_lost",
             "recapture_required":
            return .freshRescan
        default:
            return .freshRescan
        }
    }

    /// The evidence class a repair of this kind must produce.
    public static func requiredEvidenceType(
        for kind: RepairTaskKind
    ) -> String {
        switch kind {
        case .semanticCorrection:
            return "annotation_revision"
        case .sameCoordinateEvidence:
            return "same_coordinate_evidence"
        case .freshRescan:
            return "fresh_revision_rescan"
        case .externalMeasurement:
            return "instrument_measurement"
        }
    }

    /// Builds a validated repair plan from inbound diagnostics for
    /// the pinned source revision/receipt.
    public static func plan(
        planID: String,
        planVersion: String,
        projectRef: String,
        roomName: String,
        sourceCaptureRevisionID: CaptureRevisionID,
        sourceBundleDigest: EvidenceSHA256,
        ingestionReceiptRef: String,
        issuedAtUTC: String? = nil,
        issuedBySoftware: String,
        issuedByProtocolVersion: String,
        diagnostics: [HTDTIngestionDiagnostic]
    ) throws -> HTDTRepairTaskPlan {
        let tasks = try diagnostics.enumerated().map {
            index, diagnostic in
            let kind = taskKind(forIssueCode: diagnostic.issueCode)
            return try HTDTRepairTask(
                taskID: "task-\(index + 1)",
                issueCode: diagnostic.issueCode,
                kind: kind,
                requirement: diagnostic.requirement,
                reason: diagnostic.reason,
                requiredEvidenceType: requiredEvidenceType(for: kind),
                targetRef: diagnostic.targetRef
            )
        }
        return try HTDTRepairTaskPlan(
            planID: planID,
            planVersion: planVersion,
            projectRef: projectRef,
            roomName: roomName,
            sourceCaptureRevisionID:
                sourceCaptureRevisionID.description,
            sourceBundleDigest: sourceBundleDigest.value,
            ingestionReceiptRef: ingestionReceiptRef,
            issuedAtUTC: issuedAtUTC,
            issuedBySoftware: issuedBySoftware,
            issuedByProtocolVersion: issuedByProtocolVersion,
            tasks: tasks
        )
    }
}

/// The link document persisted into the *repair* revision's bundle at
/// `session/repair-task-link.json` (issue bolph71656-ai/HTDT-Capture#321): the new capture
/// revision's provenance back to the repair request and the exact
/// source revision it corrects. The source capture is never opened
/// for mutation; this document is the only carry-over.
public struct HTDTRepairTaskLink: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture-repair-task-link"
    public static let schemaVersion = "1.0.0"
    public static let path = "session/repair-task-link.json"

    public let schema: String
    public let schemaVersion: String
    /// The revision that carries this link (the repair capture).
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let repairPlanID: String
    public let repairPlanVersion: String
    public let repairPlanSHA256: EvidenceSHA256
    public let repairTaskID: String
    /// The immutable source revision the repair responds to.
    public let sourceCaptureRevisionID: CaptureRevisionID
    public let ingestionReceiptRef: String

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        repairPlanID: String,
        repairPlanVersion: String,
        repairPlanSHA256: EvidenceSHA256,
        repairTaskID: String,
        sourceCaptureRevisionID: CaptureRevisionID,
        ingestionReceiptRef: String
    ) throws {
        let normalizedPlan = SchemaOwnedText.nfc(repairPlanID)
        let normalizedVersion = SchemaOwnedText.nfc(repairPlanVersion)
        let normalizedTask = SchemaOwnedText.nfc(repairTaskID)
        let normalizedReceipt = SchemaOwnedText.nfc(
            ingestionReceiptRef
        )
        guard !normalizedPlan.isEmpty,
              !normalizedVersion.isEmpty,
              !normalizedTask.isEmpty,
              !normalizedReceipt.isEmpty
        else {
            throw RepairTaskError.emptyField
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.repairPlanID = normalizedPlan
        self.repairPlanVersion = normalizedVersion
        self.repairPlanSHA256 = repairPlanSHA256
        self.repairTaskID = normalizedTask
        self.sourceCaptureRevisionID = sourceCaptureRevisionID
        self.ingestionReceiptRef = normalizedReceipt
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case repairPlanID = "repair_plan_id"
        case repairPlanVersion = "repair_plan_version"
        case repairPlanSHA256 = "repair_plan_sha256"
        case repairTaskID = "repair_task_id"
        case sourceCaptureRevisionID = "source_capture_revision_id"
        case ingestionReceiptRef = "ingestion_receipt_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw RepairTaskError.unsupportedSchema
        }
        try self.init(
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            repairPlanID: container.decode(
                String.self,
                forKey: .repairPlanID
            ),
            repairPlanVersion: container.decode(
                String.self,
                forKey: .repairPlanVersion
            ),
            repairPlanSHA256: container.decode(
                EvidenceSHA256.self,
                forKey: .repairPlanSHA256
            ),
            repairTaskID: container.decode(
                String.self,
                forKey: .repairTaskID
            ),
            sourceCaptureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .sourceCaptureRevisionID
            ),
            ingestionReceiptRef: container.decode(
                String.self,
                forKey: .ingestionReceiptRef
            )
        )
    }

    /// Encoded payload for the supplemental-document store path.
    public func package() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(self)
        guard
            let decoded = try? JSONDecoder().decode(
                HTDTRepairTaskLink.self,
                from: data
            ),
            decoded == self
        else {
            throw RepairTaskError.encodedDocumentMismatch
        }
        return data
    }
}

/// Operator-facing row for one repair task: the task plus the plan
/// identity it arrived under and whether a repair revision already
/// resolved it.
public struct HTDTRepairTaskRow: Sendable, Equatable, Identifiable {
    public let planKey: String
    public let planID: String
    public let planVersion: String
    public let task: HTDTRepairTask
    public let resolvedByRevisionID: String?

    public var id: String { planKey + "|" + task.taskID }
    public var resolved: Bool { resolvedByRevisionID != nil }
}

/// App-local ledger of received HTDT repair plans at
/// `<captureRoot>/repair-task-plans.json` (issue bolph71656-ai/HTDT-Capture#321). Plans are
/// deduplicated by plan identity + the ingestion receipt they answer,
/// and tasks by `task_id` inside a plan — a repeated handoff of the
/// same plan is an idempotent merge, never a silent duplicate.
public struct HTDTRepairPlanStore: Sendable {
    public struct StoredTask: Codable, Sendable, Equatable {
        public let task: HTDTRepairTask
        public var resolvedByRevisionID: String?
        public var resolvedAtUTC: String?

        public init(
            task: HTDTRepairTask,
            resolvedByRevisionID: String? = nil,
            resolvedAtUTC: String? = nil
        ) {
            self.task = task
            self.resolvedByRevisionID = resolvedByRevisionID
            self.resolvedAtUTC = resolvedAtUTC
        }
    }

    public struct StoredPlan: Codable, Sendable, Equatable {
        public let planKey: String
        public let plan: HTDTRepairTaskPlan
        public let planSHA256: String
        public let receivedAtUTC: String
        public var tasks: [StoredTask]

        public init(
            planKey: String,
            plan: HTDTRepairTaskPlan,
            planSHA256: String,
            receivedAtUTC: String,
            tasks: [StoredTask]
        ) {
            self.planKey = planKey
            self.plan = plan
            self.planSHA256 = planSHA256
            self.receivedAtUTC = receivedAtUTC
            self.tasks = tasks
        }
    }

    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.repair-task-plans"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var plans: [StoredPlan]

        public init(plans: [StoredPlan] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.plans = plans
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case plans
        }
    }

    /// Identity key under which a plan deduplicates: the plan's own
    /// identity plus the exact ingestion transaction it answers. A
    /// re-issued plan for a different ingestion is a distinct plan.
    public static func planKey(
        planID: String,
        planVersion: String,
        ingestionReceiptRef: String
    ) -> String {
        planID + "|" + planVersion + "|" + ingestionReceiptRef
    }

    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "repair-task-plans.json",
            isDirectory: false
        )
    }

    public func load() throws -> Document {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return Document()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                Document.self,
                from: data
              ),
              document.schema == Document.schema,
              document.schemaVersion == Document.schemaVersion
        else {
            throw RepairTaskError.unreadableDocument
        }
        return document
    }

    /// Records an imported plan. Re-import of the same plan key merges
    /// tasks by `task_id` — already-resolved tasks keep their
    /// resolution, new tasks append — so a repeated HTDT handoff can
    /// never silently duplicate or resurrect tasks.
    @discardableResult
    public func record(
        _ planImport: HTDTRepairTaskPlanImport,
        receivedAtUTC: String
    ) throws -> StoredPlan {
        var document = try load()
        let plan = planImport.plan
        let key = Self.planKey(
            planID: plan.planID,
            planVersion: plan.planVersion,
            ingestionReceiptRef: plan.ingestionReceiptRef
        )
        if let index = document.plans.firstIndex(where: {
            $0.planKey == key
        }) {
            var stored = document.plans[index]
            for task in plan.tasks {
                if !stored.tasks.contains(where: {
                    $0.task.taskID == task.taskID
                }) {
                    stored.tasks.append(StoredTask(task: task))
                } else if let existing = stored.tasks.first(where: {
                    $0.task.taskID == task.taskID
                }), existing.task != task {
                    // Same task id re-issued with changed content:
                    // update the task body but preserve any recorded
                    // resolution so a repair revision is never
                    // un-credited.
                    stored.tasks = stored.tasks.map { storedTask in
                        guard storedTask.task.taskID == task.taskID
                        else {
                            return storedTask
                        }
                        return StoredTask(
                            task: task,
                            resolvedByRevisionID:
                                storedTask.resolvedByRevisionID,
                            resolvedAtUTC: storedTask.resolvedAtUTC
                        )
                    }
                }
            }
            document.plans[index] = stored
            try write(document)
            return stored
        }
        let stored = StoredPlan(
            planKey: key,
            plan: plan,
            planSHA256: planImport.planSHA256.value,
            receivedAtUTC: receivedAtUTC,
            tasks: plan.tasks.map { StoredTask(task: $0) }
        )
        document.plans.append(stored)
        try write(document)
        return stored
    }

    /// Marks one task resolved by the exact repair revision that
    /// answered it. Unknown keys/tasks fail closed.
    public func markTaskResolved(
        planKey: String,
        taskID: String,
        resolvedBy revisionID: CaptureRevisionID,
        at resolvedAtUTC: String
    ) throws {
        var document = try load()
        guard let planIndex = document.plans.firstIndex(where: {
            $0.planKey == planKey
        }) else {
            throw RepairTaskError.unknownTaskID
        }
        guard let taskIndex = document.plans[planIndex].tasks
            .firstIndex(where: { $0.task.taskID == taskID })
        else {
            throw RepairTaskError.unknownTaskID
        }
        document.plans[planIndex].tasks[taskIndex]
            .resolvedByRevisionID = revisionID.description
        document.plans[planIndex].tasks[taskIndex]
            .resolvedAtUTC = resolvedAtUTC
        try write(document)
    }

    /// All stored plans for one source capture revision.
    public func plans(
        forSourceRevisionID revisionID: CaptureRevisionID
    ) throws -> [StoredPlan] {
        try load().plans.filter {
            $0.plan.sourceCaptureRevisionID
                == revisionID.description
        }
    }

    /// Flattened operator rows for one source revision — every task,
    /// resolved or not, so the repair history is inspectable.
    public func taskRows(
        forSourceRevisionID revisionID: CaptureRevisionID
    ) throws -> [HTDTRepairTaskRow] {
        try plans(forSourceRevisionID: revisionID).flatMap { plan in
            plan.tasks.map { stored in
                HTDTRepairTaskRow(
                    planKey: plan.planKey,
                    planID: plan.plan.planID,
                    planVersion: plan.plan.planVersion,
                    task: stored.task,
                    resolvedByRevisionID: stored.resolvedByRevisionID
                )
            }
        }
    }

    /// Unresolved rows across every plan — used for the mission
    /// summary when no specific revision is adopted.
    public func unresolvedTaskRows() throws -> [HTDTRepairTaskRow] {
        try load().plans.flatMap { plan in
            plan.tasks.filter {
                $0.resolvedByRevisionID == nil
            }.map { stored in
                HTDTRepairTaskRow(
                    planKey: plan.planKey,
                    planID: plan.plan.planID,
                    planVersion: plan.plan.planVersion,
                    task: stored.task,
                    resolvedByRevisionID: nil
                )
            }
        }
    }

    private func write(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(document)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: fileURL
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
