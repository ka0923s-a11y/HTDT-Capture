import Foundation

/// Errors raised by the mission inbox (issue #386).
public enum HTDTMissionInboxError: Error, Sendable, Equatable {
    /// Payload is neither a valid `htdt.capture-mission` envelope nor
    /// a bare `htdt.capture-task-plan` document.
    case invalidMissionPayload
    /// The mission's schema version is newer than this build imports.
    case unsupportedSchema
    /// Same mission identity, different payload bytes — the import
    /// fails closed rather than silently replacing the record.
    case conflictingIdentity
    /// No record under that record id or mission id.
    case unknownMission(String)
    /// Another mission is currently in progress; starting requires an
    /// explicit decision to pause it first.
    case missionAlreadyInProgress(String)
    /// The record's lifecycle does not allow the requested action.
    case invalidLifecycleTransition(String)
    /// Required dependencies are unmet — surfaced before Start so a
    /// mission never begins already blocked.
    case blockedDependencies([String])
    /// The persisted inbox document is missing required invariants.
    case unreadableDocument
}

/// Kind of work the mission asks the operator to perform.
public enum HTDTMissionKind: String, Codable, Sendable, CaseIterable {
    case initialSurvey = "initial_survey"
    case followUp = "follow_up"
    case repair = "repair"
    case commissioning = "commissioning"
    case other
}

/// A dependency the mission declares for its Start action (issue
/// #386). `ref` names the depended-upon mission id, capture revision,
/// equipment-catalog digest, or receiver capability subject; `kind`
/// tells the evaluator how to resolve it; `required` decides whether
/// an unmet dependency blocks Start or is advisory.
public struct HTDTMissionDependency: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Another mission record must be `completed`/`delivered`.
        case missionCompleted = "mission_completed"
        /// A capture revision must exist in the persisted inventory.
        case captureFinalized = "capture_finalized"
        /// A delivery job for the named capture must be
        /// `delivered_staged`.
        case captureDelivered = "capture_delivered"
    }

    public let ref: String
    public let kind: Kind
    public let required: Bool

    public init(ref: String, kind: Kind, required: Bool = true) {
        self.ref = ref
        self.kind = kind
        self.required = required
    }
}

/// Mission envelope document (issue #386): the unit HTDT issues and
/// this app imports. A mission wraps exactly one task plan plus the
/// mission-level intent (purpose, supersession, follow-up lineage,
/// dependencies, minimum receiver capability) that must never become
/// capture truth on its own — the plan inside stays the capture's
/// imported reference.
public struct HTDTMissionPackage: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture-mission"
    public static let supportedSchemaVersions = ["1.0.0"]

    public let schema: String
    public let schemaVersion: String
    /// Issuer-assigned mission identity, stable across re-issue.
    public let missionID: String
    public let missionKind: HTDTMissionKind
    public let purpose: String?
    /// The embedded task plan — the capture's imported reference.
    public let plan: HTDTCaptureTaskPlan
    public let issuedAtUTC: String?
    /// Mission id this package explicitly supersedes.
    public let supersedesMissionID: String?
    /// Mission this follow-up was issued against.
    public let followUpOfMissionID: String?
    /// Free-form origin reference for the follow-up (a capture
    /// revision id, a finding id — issuer's vocabulary).
    public let followUpOriginRef: String?
    public let dependencies: [HTDTMissionDependency]
    /// Minimum receiver capability the mission requires (#374).
    public let receiverRequirement: HTDTMissionReceiverRequirement?

    public init(
        missionID: String,
        missionKind: HTDTMissionKind,
        plan: HTDTCaptureTaskPlan,
        purpose: String? = nil,
        issuedAtUTC: String? = nil,
        supersedesMissionID: String? = nil,
        followUpOfMissionID: String? = nil,
        followUpOriginRef: String? = nil,
        dependencies: [HTDTMissionDependency] = [],
        receiverRequirement: HTDTMissionReceiverRequirement? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.supportedSchemaVersions[0]
        self.missionID = missionID
        self.missionKind = missionKind
        self.plan = plan
        self.purpose = purpose
        self.issuedAtUTC = issuedAtUTC
        self.supersedesMissionID = supersedesMissionID
        self.followUpOfMissionID = followUpOfMissionID
        self.followUpOriginRef = followUpOriginRef
        self.dependencies = dependencies
        self.receiverRequirement = receiverRequirement
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case missionID = "mission_id"
        case missionKind = "mission_kind"
        case purpose
        case plan
        case issuedAtUTC = "issued_at"
        case supersedesMissionID = "supersedes_mission_id"
        case followUpOfMissionID = "follow_up_of_mission_id"
        case followUpOriginRef = "follow_up_origin_ref"
        case dependencies
        case receiverRequirement = "receiver_requirement"
    }
}

/// What an import call classified the payload as (issue #386).
public enum HTDTMissionImportOutcome: Sendable, Equatable {
    /// A distinct new record was added.
    case imported(HTDTMissionRecord)
    /// Byte-identical payload re-imported — idempotent no-op
    /// returning the existing record.
    case duplicate(HTDTMissionRecord)
    /// A new record that supersedes an existing mission; the old
    /// record is marked `superseded` and keeps its captures/history.
    case superseding(
        record: HTDTMissionRecord,
        superseded: HTDTMissionRecord
    )
}

/// Decodes either mission payload shape: a `htdt.capture-mission`
/// envelope, or a bare `htdt.capture-task-plan` wrapped in a derived
/// mission identity (`plan:<planID>`) so plan files issued before
/// envelopes existed still land in the inbox.
public struct HTDTMissionImport: Sendable, Equatable {
    public let package: HTDTMissionPackage
    /// Exact bytes as imported — stored verbatim under
    /// `missions/<record>.json`.
    public let data: Data
    /// SHA-256 of the imported bytes — provenance identity.
    public let payloadSHA256: EvidenceSHA256
    /// True when the payload was a bare plan wrapped by the app.
    public let derivedFromBarePlan: Bool

    public init(data: Data) throws {
        if let package = try? JSONDecoder().decode(
            HTDTMissionPackage.self,
            from: data
        ), package.schema == HTDTMissionPackage.schema,
            HTDTMissionPackage.supportedSchemaVersions.contains(
                package.schemaVersion
            ),
            !package.missionID.isEmpty
        {
            self.package = package
            self.data = data
            self.payloadSHA256 = EvidenceIntegrity.sha256(of: data)
            self.derivedFromBarePlan = false
            return
        }
        if let planImport = try? CaptureTaskPlanImport(data: data) {
            // Bare plans get a deterministic mission identity so the
            // same plan file always resolves to the same record.
            let derived = try? HTDTMissionPackage(
                missionID: "plan:" + planImport.plan.planID,
                missionKind: .other,
                plan: planImport.plan,
                issuedAtUTC: planImport.plan.issuedAtUTC
            )
            guard let derived else {
                throw HTDTMissionInboxError.invalidMissionPayload
            }
            self.package = derived
            self.data = data
            self.payloadSHA256 = planImport.planSHA256
            self.derivedFromBarePlan = true
            return
        }
        throw HTDTMissionInboxError.invalidMissionPayload
    }
}

/// Mission lifecycle (issue #386). Terminal-ish states still keep the
/// record selectable — `archived` only hides it from the default list.
public enum HTDTMissionLifecycle: String, Codable, Sendable {
    case received
    /// All required dependencies satisfied — Start is available.
    case ready
    /// Required dependencies unmet; Start is refused.
    case blockedDependency = "blocked_dependency"
    case inProgress = "in_progress"
    case fieldCaptureCompleted = "field_capture_completed"
    case finalized
    case delivered
    /// Receiver signaled follow-up work on this mission.
    case needsFollowUp = "needs_follow_up"
    case completed
    /// Explicitly replaced by a newer mission record — keeps its
    /// capture associations and history (#386).
    case superseded
    /// Hidden from the default inbox but never deleted.
    case archived

    /// States from which Start is allowed.
    public var canStart: Bool {
        switch self {
        case .received, .ready, .blockedDependency, .inProgress:
            return true
        case .fieldCaptureCompleted, .finalized, .delivered,
             .needsFollowUp, .completed, .superseded, .archived:
            return false
        }
    }

    /// States from which the operator may close the mission — its
    /// field work or delivery has already landed.
    public var canMarkCompleted: Bool {
        switch self {
        case .fieldCaptureCompleted, .finalized, .delivered,
             .needsFollowUp:
            return true
        case .received, .ready, .blockedDependency, .inProgress,
             .completed, .superseded, .archived:
            return false
        }
    }
}

/// One persisted mission record (issue #386). Every field survives
/// app relaunch verbatim; non-AR progress (capture associations,
/// delivery jobs, lifecycle) is reconstructed entirely from this
/// record plus the stores it cross-references.
public struct HTDTMissionRecord:
    Codable, Sendable, Equatable, Identifiable
{
    /// Device-local record identity (UUIDv4) — distinct from the
    /// issuer's `missionID` so a conflicting re-import never rewrites
    /// an existing record in place.
    public let recordID: String
    public let missionID: String
    public let missionKind: HTDTMissionKind
    public let purpose: String?
    /// Inbox-relative path of the verbatim imported payload bytes.
    public let payloadRelativePath: String
    /// SHA-256 of the imported payload bytes.
    public let payloadSHA256: String
    /// The embedded plan's identity fields, denormalized for listing.
    public let planID: String
    public let planVersion: String
    public let planSHA256: String
    public let projectRef: String
    public let roomName: String
    public let issuedAtUTC: String?
    public let importedAtUTC: String
    public var lifecycle: HTDTMissionLifecycle
    /// Capture revisions opened under this mission — a mission may
    /// have several captures, and standalone captures never gain a
    /// mission association.
    public var associatedCaptureRevisionIDs: [String]
    /// Field-return contribution ids attached to this mission (issue
    /// #400). Non-spatial work completes a mission through these
    /// alongside (or instead of) capture revisions.
    public var fieldReturnIDs: [String]
    public let supersedesMissionID: String?
    public var supersededByMissionID: String?
    public let followUpOfMissionID: String?
    public let followUpOriginRef: String?
    /// Declared dependencies carried from the envelope.
    public let dependencies: [HTDTMissionDependency]
    /// Minimum receiver capability the mission requires (#374).
    public let receiverRequirement: HTDTMissionReceiverRequirement?
    /// Delivery-queue jobs satisfying this mission's send (#387).
    public var deliveryJobIDs: [String]
    /// Operator annotation; never issuer truth.
    public var userNote: String?

    public init(
        recordID: String,
        missionID: String,
        missionKind: HTDTMissionKind,
        purpose: String?,
        payloadRelativePath: String,
        payloadSHA256: String,
        planID: String,
        planVersion: String,
        planSHA256: String,
        projectRef: String,
        roomName: String,
        issuedAtUTC: String?,
        importedAtUTC: String,
        lifecycle: HTDTMissionLifecycle,
        associatedCaptureRevisionIDs: [String] = [],
        fieldReturnIDs: [String] = [],
        supersedesMissionID: String? = nil,
        supersededByMissionID: String? = nil,
        followUpOfMissionID: String? = nil,
        followUpOriginRef: String? = nil,
        dependencies: [HTDTMissionDependency] = [],
        receiverRequirement: HTDTMissionReceiverRequirement? = nil,
        deliveryJobIDs: [String] = [],
        userNote: String? = nil
    ) {
        self.recordID = recordID
        self.missionID = missionID
        self.missionKind = missionKind
        self.purpose = purpose
        self.payloadRelativePath = payloadRelativePath
        self.payloadSHA256 = payloadSHA256
        self.planID = planID
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.projectRef = projectRef
        self.roomName = roomName
        self.issuedAtUTC = issuedAtUTC
        self.importedAtUTC = importedAtUTC
        self.lifecycle = lifecycle
        self.associatedCaptureRevisionIDs = associatedCaptureRevisionIDs
        self.fieldReturnIDs = fieldReturnIDs
        self.supersedesMissionID = supersedesMissionID
        self.supersededByMissionID = supersededByMissionID
        self.followUpOfMissionID = followUpOfMissionID
        self.followUpOriginRef = followUpOriginRef
        self.dependencies = dependencies
        self.receiverRequirement = receiverRequirement
        self.deliveryJobIDs = deliveryJobIDs
        self.userNote = userNote
    }

    public var id: String { recordID }

    private enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case missionID = "mission_id"
        case missionKind = "mission_kind"
        case purpose
        case payloadRelativePath = "payload_relative_path"
        case payloadSHA256 = "payload_sha256"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case planSHA256 = "plan_sha256"
        case projectRef = "project_ref"
        case roomName = "room_name"
        case issuedAtUTC = "issued_at"
        case importedAtUTC = "imported_at"
        case lifecycle
        case associatedCaptureRevisionIDs =
            "associated_capture_revision_ids"
        case fieldReturnIDs = "field_return_ids"
        case supersedesMissionID = "supersedes_mission_id"
        case supersededByMissionID = "superseded_by_mission_id"
        case followUpOfMissionID = "follow_up_of_mission_id"
        case followUpOriginRef = "follow_up_origin_ref"
        case dependencies
        case receiverRequirement = "receiver_requirement"
        case deliveryJobIDs = "delivery_job_ids"
        case userNote = "user_note"
    }

    /// Inbox files written before #400 lack `field_return_ids` —
    /// decode them as an empty set rather than failing the whole
    /// inbox.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recordID = try container.decode(String.self, forKey: .recordID)
        self.missionID = try container.decode(String.self, forKey: .missionID)
        self.missionKind = try container.decode(
            HTDTMissionKind.self, forKey: .missionKind
        )
        self.purpose = try container.decodeIfPresent(
            String.self, forKey: .purpose
        )
        self.payloadRelativePath = try container.decode(
            String.self, forKey: .payloadRelativePath
        )
        self.payloadSHA256 = try container.decode(
            String.self, forKey: .payloadSHA256
        )
        self.planID = try container.decode(String.self, forKey: .planID)
        self.planVersion = try container.decode(
            String.self, forKey: .planVersion
        )
        self.planSHA256 = try container.decode(
            String.self, forKey: .planSHA256
        )
        self.projectRef = try container.decode(
            String.self, forKey: .projectRef
        )
        self.roomName = try container.decode(
            String.self, forKey: .roomName
        )
        self.issuedAtUTC = try container.decodeIfPresent(
            String.self, forKey: .issuedAtUTC
        )
        self.importedAtUTC = try container.decode(
            String.self, forKey: .importedAtUTC
        )
        self.lifecycle = try container.decode(
            HTDTMissionLifecycle.self, forKey: .lifecycle
        )
        self.associatedCaptureRevisionIDs = try container.decode(
            [String].self, forKey: .associatedCaptureRevisionIDs
        )
        self.fieldReturnIDs = try container.decodeIfPresent(
            [String].self, forKey: .fieldReturnIDs
        ) ?? []
        self.supersedesMissionID = try container.decodeIfPresent(
            String.self, forKey: .supersedesMissionID
        )
        self.supersededByMissionID = try container.decodeIfPresent(
            String.self, forKey: .supersededByMissionID
        )
        self.followUpOfMissionID = try container.decodeIfPresent(
            String.self, forKey: .followUpOfMissionID
        )
        self.followUpOriginRef = try container.decodeIfPresent(
            String.self, forKey: .followUpOriginRef
        )
        self.dependencies = try container.decode(
            [HTDTMissionDependency].self, forKey: .dependencies
        )
        self.receiverRequirement = try container.decodeIfPresent(
            HTDTMissionReceiverRequirement.self,
            forKey: .receiverRequirement
        )
        self.deliveryJobIDs = try container.decode(
            [String].self, forKey: .deliveryJobIDs
        )
        self.userNote = try container.decodeIfPresent(
            String.self, forKey: .userNote
        )
    }
}

/// Result of evaluating a record's declared dependencies plus its
/// plan's equipment-catalog pin (issue #386). Required misses block
/// Start; optional misses and receiver gaps are surfaced advisedly.
public struct HTDTMissionDependencyReport: Sendable, Equatable {
    public var missingRequired: [String]
    public var missingOptional: [String]
    /// Human-readable receiver-capability gaps when the mission names
    /// a `receiverRequirement` and a paired destination was checked.
    public var receiverGaps: [String]
    /// Equipment-catalog pin status from `EquipmentCatalogRequirement`.
    public var catalogRequirement: EquipmentCatalogRequirement

    public init(
        missingRequired: [String] = [],
        missingOptional: [String] = [],
        receiverGaps: [String] = [],
        catalogRequirement: EquipmentCatalogRequirement = .notRequired
    ) {
        self.missingRequired = missingRequired
        self.missingOptional = missingOptional
        self.receiverGaps = receiverGaps
        self.catalogRequirement = catalogRequirement
    }

    /// Required dependency misses plus an unsatisfied catalog pin all
    /// block Start.
    public var startBlocked: Bool {
        !missingRequired.isEmpty || !catalogRequirement.isSatisfied
    }
}

/// What resuming a mission means (issue #386): the persisted record,
/// its plan bytes ready to re-import as the capture's task plan, and
/// an honest statement that workflow progress resumes but the live AR
/// session never does.
public struct HTDTMissionResume: Sendable, Equatable {
    public let record: HTDTMissionRecord
    public let planImport: CaptureTaskPlanImport
    /// The mission payload bytes as stored — callers persist them as
    /// the capture's imported plan reference.
    public var planData: Data { planImport.data }
    /// Always true: the inbox's non-AR progress survives relaunch.
    public var workflowProgressResumable: Bool { true }
    /// Always false: no code path may claim a live AR session can be
    /// resumed across app termination.
    public var liveARSessionResumable: Bool { false }
}

/// Mission inbox store (issue #386): `<captureRoot>/mission-inbox.json`
/// plus verbatim payloads under `<captureRoot>/missions/`. Import is
/// idempotent on byte-identical payloads, fails closed on conflicting
/// same-identity bytes, and lands superseding missions as distinct
/// records linked to the record they replace.
public struct HTDTMissionInboxStore: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.mission-inbox"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var records: [HTDTMissionRecord]
        /// The record whose plan drives the active capture, if any.
        public var activeMissionRecordID: String?

        public init(
            records: [HTDTMissionRecord] = [],
            activeMissionRecordID: String? = nil
        ) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.records = records
            self.activeMissionRecordID = activeMissionRecordID
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case records
            case activeMissionRecordID = "active_mission_record_id"
        }
    }

    public let captureRoot: URL

    public var fileURL: URL {
        captureRoot.appendingPathComponent(
            "mission-inbox.json",
            isDirectory: false
        )
    }

    public var payloadDirectory: URL {
        captureRoot.appendingPathComponent("missions", isDirectory: true)
    }

    public init(captureRoot: URL) {
        self.captureRoot = captureRoot
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
            throw HTDTMissionInboxError.unreadableDocument
        }
        return document
    }

    public func records() throws -> [HTDTMissionRecord] {
        try load().records
    }

    public func record(id: String) throws -> HTDTMissionRecord? {
        try load().records.first { $0.recordID == id }
    }

    public func record(missionID: String) throws -> HTDTMissionRecord? {
        try load().records.first { $0.missionID == missionID }
    }

    /// Non-archived, non-superseded records for the default inbox.
    public func activeRecords() throws -> [HTDTMissionRecord] {
        try load().records.filter {
            $0.lifecycle != .archived && $0.lifecycle != .superseded
        }
    }

    public func activeMissionRecord() throws -> HTDTMissionRecord? {
        let document = try load()
        guard let activeID = document.activeMissionRecordID else {
            return nil
        }
        return document.records.first { $0.recordID == activeID }
    }

    /// Records grouped project → room for the inbox UI (issue #386).
    public func grouped() throws
        -> [String: [String: [HTDTMissionRecord]]]
    {
        var groups: [String: [String: [HTDTMissionRecord]]] = [:]
        for record in try activeRecords() {
            groups[record.projectRef, default: [:]][
                record.roomName,
                default: []
            ].append(record)
        }
        return groups
    }

    /// Imports a mission payload — envelope or bare plan. Idempotent
    /// on byte-identical re-import; fails closed when the same
    /// `mission_id` arrives with different bytes and no supersession
    /// declaration; a declared supersession lands a distinct record
    /// and marks the replaced one `superseded` (#386).
    @discardableResult
    public func importMission(
        data: Data,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> HTDTMissionImportOutcome {
        let parsed = try HTDTMissionImport(data: data)
        var document = try load()

        if let existing = document.records.first(where: {
            $0.missionID == parsed.package.missionID
        }) {
            if existing.payloadSHA256 == parsed.payloadSHA256.value {
                return .duplicate(existing)
            }
            let isExplicitSupersession = parsed.package
                .supersedesMissionID == existing.missionID
            guard isExplicitSupersession else {
                // Same identity, different bytes, no declared
                // supersession — fail closed (#386).
                throw HTDTMissionInboxError.conflictingIdentity
            }
        }

        let recordID = UUID().uuidString.lowercased()
        let payloadRelativePath = "missions/" + recordID + ".json"
        let payloadURL = captureRoot.appendingPathComponent(
            payloadRelativePath,
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: payloadDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: payloadURL)

        let record = HTDTMissionRecord(
            recordID: recordID,
            missionID: parsed.package.missionID,
            missionKind: parsed.package.missionKind,
            purpose: parsed.package.purpose,
            payloadRelativePath: payloadRelativePath,
            payloadSHA256: parsed.payloadSHA256.value,
            planID: parsed.package.plan.planID,
            planVersion: parsed.package.plan.planVersion,
            planSHA256: EvidenceIntegrity.sha256(
                of: (try? JSONEncoder().encode(parsed.package.plan))
                    ?? Data()
            ).value,
            projectRef: parsed.package.plan.projectRef,
            roomName: parsed.package.plan.roomName,
            issuedAtUTC: parsed.package.issuedAtUTC
                ?? parsed.package.plan.issuedAtUTC,
            importedAtUTC: nowUTC,
            lifecycle: .received,
            supersedesMissionID: parsed.package.supersedesMissionID,
            followUpOfMissionID: parsed.package.followUpOfMissionID,
            followUpOriginRef: parsed.package.followUpOriginRef,
            dependencies: parsed.package.dependencies,
            receiverRequirement: parsed.package.receiverRequirement
        )
        document.records.append(record)

        var superseded: HTDTMissionRecord?
        if let supersedesID = parsed.package.supersedesMissionID,
           let index = document.records.firstIndex(where: {
               $0.missionID == supersedesID
               && $0.lifecycle != .superseded
           })
        {
            var old = document.records[index]
            old.lifecycle = .superseded
            old.supersededByMissionID = parsed.package.missionID
            if document.activeMissionRecordID == old.recordID {
                document.activeMissionRecordID = nil
            }
            document.records[index] = old
            superseded = old
        }
        // A mission naming an earlier mission as its follow-up origin
        // is the receiver's signal that the earlier mission needs
        // follow-up work (#386) — it flips to `needs_follow_up`
        // unless it already sits in a terminal-ish state.
        if let followUpOf = parsed.package.followUpOfMissionID,
           let index = document.records.firstIndex(where: {
               $0.missionID == followUpOf
               && $0.lifecycle != .superseded
               && $0.lifecycle != .completed
               && $0.lifecycle != .archived
           })
        {
            document.records[index].lifecycle = .needsFollowUp
        }
        try save(document)
        if let superseded {
            return .superseding(record: record, superseded: superseded)
        }
        return .imported(record)
    }

    /// Evaluates a record's declared dependencies against the inbox,
    /// the persisted capture inventory, and the delivery queue, plus
    /// the plan's equipment-catalog pin (issue #386). Called before
    /// Start so blockers surface before scanning begins.
    public func evaluateDependencies(
        recordID: String,
        inventory: PersistedCaptureInventoryResult? = nil,
        deliveryQueue: HTDTDeliveryQueue? = nil,
        activeCatalog: HTDTEquipmentCatalogSnapshot? = nil
    ) throws -> HTDTMissionDependencyReport {
        guard let record = try record(id: recordID) else {
            throw HTDTMissionInboxError.unknownMission(recordID)
        }
        var report = HTDTMissionDependencyReport()
        let records = try load().records
        for dependency in record.dependencies {
            let satisfied: Bool
            switch dependency.kind {
            case .missionCompleted:
                satisfied = records.contains {
                    $0.missionID == dependency.ref
                        && ($0.lifecycle == .completed
                            || $0.lifecycle == .delivered)
                }
            case .captureFinalized:
                satisfied = inventory?.captures.contains {
                    $0.captureRevisionID.description == dependency.ref
                } ?? false
            case .captureDelivered:
                // #423: a delivered capture dependency matches the
                // job's artifact id, whatever artifact family rides
                // the queue.
                satisfied = (try? deliveryQueue?.jobs())?
                    .contains {
                        $0.artifactIDText == dependency.ref
                            && $0.state == .deliveredStaged
                    } ?? false
            }
            if !satisfied {
                if dependency.required {
                    report.missingRequired.append(dependency.ref)
                } else {
                    report.missingOptional.append(dependency.ref)
                }
            }
        }
        report.catalogRequirement = EquipmentCatalogRequirement.check(
            plan: try? plan(for: record),
            activeCatalog: activeCatalog
        )
        return report
    }

    /// Starts a mission: evaluates dependencies, refuses when required
    /// blockers exist, enforces a single active mission (the current
    /// one must be paused first — starting never silently discards
    /// in-progress work), and returns the embedded plan as a
    /// `CaptureTaskPlanImport` so the capture pipeline treats it
    /// exactly like a plan imported any other way.
    @discardableResult
    public func startMission(
        recordID: String,
        inventory: PersistedCaptureInventoryResult? = nil,
        deliveryQueue: HTDTDeliveryQueue? = nil,
        activeCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> HTDTMissionResume {
        var document = try load()
        guard let index = document.records.firstIndex(where: {
            $0.recordID == recordID
        }) else {
            throw HTDTMissionInboxError.unknownMission(recordID)
        }
        var record = document.records[index]
        guard record.lifecycle.canStart else {
            throw HTDTMissionInboxError.invalidLifecycleTransition(
                record.lifecycle.rawValue
            )
        }
        if let activeID = document.activeMissionRecordID,
           activeID != recordID
        {
            throw HTDTMissionInboxError.missionAlreadyInProgress(
                activeID
            )
        }
        let report = try evaluateDependencies(
            recordID: recordID,
            inventory: inventory,
            deliveryQueue: deliveryQueue,
            activeCatalog: activeCatalog
        )
        if report.startBlocked {
            record.lifecycle = .blockedDependency
            document.records[index] = record
            try save(document)
            var blockers = report.missingRequired
            if !report.catalogRequirement.isSatisfied {
                blockers.append("equipment_catalog")
            }
            throw HTDTMissionInboxError.blockedDependencies(blockers)
        }
        let planImport = try planImport(for: record)
        record.lifecycle = .inProgress
        document.records[index] = record
        document.activeMissionRecordID = recordID
        try save(document)
        return HTDTMissionResume(
            record: record,
            planImport: planImport
        )
    }

    /// Re-opens a mission that is already in progress — same record,
    /// same plan bytes; the live AR session is never claimed resumed.
    /// New starts go through `startMission`, which also re-evaluates
    /// dependencies — this path must not become a second Start that
    /// bypasses them.
    public func resumeMission(
        recordID: String
    ) throws -> HTDTMissionResume {
        var document = try load()
        guard let index = document.records.firstIndex(where: {
            $0.recordID == recordID
        }) else {
            throw HTDTMissionInboxError.unknownMission(recordID)
        }
        var record = document.records[index]
        guard record.lifecycle == .inProgress else {
            throw HTDTMissionInboxError.invalidLifecycleTransition(
                record.lifecycle.rawValue
            )
        }
        if let activeID = document.activeMissionRecordID,
           activeID != recordID
        {
            throw HTDTMissionInboxError.missionAlreadyInProgress(
                activeID
            )
        }
        let planImport = try planImport(for: record)
        record.lifecycle = .inProgress
        document.records[index] = record
        document.activeMissionRecordID = recordID
        try save(document)
        return HTDTMissionResume(
            record: record,
            planImport: planImport
        )
    }

    /// Clears the active pointer without touching the record's
    /// captures — pausing is persistence, not deletion. A mission
    /// still in `in_progress` returns to `ready` so it can be
    /// started again (#386).
    public func pauseActiveMission() throws {
        var document = try load()
        if let activeID = document.activeMissionRecordID,
           let index = document.records.firstIndex(where: {
               $0.recordID == activeID
           }),
           document.records[index].lifecycle == .inProgress
        {
            document.records[index].lifecycle = .ready
        }
        document.activeMissionRecordID = nil
        try save(document)
    }

    /// Lifecycle updates the app performs as captures progress. The
    /// record is never deleted; `archived` only hides it.
    public func setLifecycle(
        recordID: String,
        _ lifecycle: HTDTMissionLifecycle
    ) throws {
        try mutate(recordID: recordID) { record in
            record.lifecycle = lifecycle
        }
    }

    /// Notes that a live capture under this mission finished its
    /// field scan — advances `in_progress` only; later states arrive
    /// through `reconcileLifecycles` or explicit completion.
    public func noteFieldCaptureCompleted(recordID: String) throws {
        try mutate(recordID: recordID) { record in
            if record.lifecycle == .inProgress {
                record.lifecycle = .fieldCaptureCompleted
            }
        }
    }

    /// Closes a mission whose field work or delivery already landed
    /// — the explicit operator counterpart of the derived states.
    public func completeMission(recordID: String) throws {
        try mutate(recordID: recordID) { record in
            guard record.lifecycle.canMarkCompleted else {
                throw HTDTMissionInboxError
                    .invalidLifecycleTransition(
                        record.lifecycle.rawValue
                    )
            }
            record.lifecycle = .completed
        }
    }

    /// Operator annotation — never issuer truth. Empty text clears
    /// the note.
    public func setUserNote(recordID: String, _ note: String?) throws {
        try mutate(recordID: recordID) { record in
            let trimmed = note?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            record.userNote = trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    /// Derives post-field lifecycle from the associations the app
    /// records as work lands (#386): a record with associated capture
    /// revisions in the inventory or committed field returns is
    /// `finalized`, and once an associated queue job reaches
    /// `deliveredStaged` the mission is `delivered`. Only forward
    /// motion is applied — pre-field states, `needs_follow_up`,
    /// `completed`, `superseded` and `archived` are untouched.
    @discardableResult
    public func reconcileLifecycles(
        inventory: PersistedCaptureInventoryResult? = nil,
        deliveryQueue: HTDTDeliveryQueue? = nil
    ) throws -> [HTDTMissionRecord] {
        var document = try load()
        let inventoryRevisionIDs = Set(
            (inventory?.captures ?? []).map {
                $0.captureRevisionID.description
            }
        )
        let deliveredJobIDs = Set(
            ((try? deliveryQueue?.jobs()) ?? []).filter {
                $0.state == .deliveredStaged
            }.map(\.deliveryJobID)
        )
        var changed = false
        for index in document.records.indices {
            var record = document.records[index]
            switch record.lifecycle {
            case .inProgress, .fieldCaptureCompleted, .finalized:
                break
            case .received, .ready, .blockedDependency, .delivered,
                 .needsFollowUp, .completed, .superseded, .archived:
                continue
            }
            let isDelivered = record.deliveryJobIDs.contains {
                deliveredJobIDs.contains($0)
            }
            let hasCommittedFieldWork =
                record.associatedCaptureRevisionIDs.contains {
                    inventoryRevisionIDs.contains($0)
                } || !record.fieldReturnIDs.isEmpty
            let target: HTDTMissionLifecycle
            if isDelivered {
                target = .delivered
            } else if hasCommittedFieldWork {
                target = .finalized
            } else {
                continue
            }
            if record.lifecycle != target {
                record.lifecycle = target
                document.records[index] = record
                changed = true
            }
        }
        if changed {
            try save(document)
        }
        return document.records
    }

    /// Associates a capture revision with the mission — many-to-one
    /// (a mission may drive several captures; a standalone capture
    /// has no mission and never gains one implicitly).
    public func associateCapture(
        recordID: String,
        captureRevisionID: CaptureRevisionID
    ) throws {
        try mutate(recordID: recordID) { record in
            let id = captureRevisionID.description
            if !record.associatedCaptureRevisionIDs.contains(id) {
                record.associatedCaptureRevisionIDs.append(id)
            }
        }
    }

    /// Links a finalized field-return contribution to this mission
    /// (#400) — the non-spatial counterpart of `associateCapture`.
    public func associateFieldReturn(
        recordID: String,
        contributionID: HTDTFieldReturnID
    ) throws {
        try mutate(recordID: recordID) { record in
            let id = contributionID.description
            if !record.fieldReturnIDs.contains(id) {
                record.fieldReturnIDs.append(id)
            }
        }
    }

    /// Records a delivery-queue job launched for this mission (#387).
    public func associateDeliveryJob(
        recordID: String,
        deliveryJobID: String
    ) throws {
        try mutate(recordID: recordID) { record in
            if !record.deliveryJobIDs.contains(deliveryJobID) {
                record.deliveryJobIDs.append(deliveryJobID)
            }
        }
    }

    /// The embedded task plan, decoded from the verbatim stored
    /// payload — missions carry a plan; the plan inside is what the
    /// capture pipeline imports (#386).
    public func plan(for record: HTDTMissionRecord) throws
        -> HTDTCaptureTaskPlan
    {
        try planImport(for: record).plan
    }

    /// The verbatim stored payload decoded as a `CaptureTaskPlanImport`
    /// — for envelopes, only the embedded plan bytes are surfaced so
    /// capture truth comes from the plan, not mission intent.
    public func planImport(for record: HTDTMissionRecord) throws
        -> CaptureTaskPlanImport
    {
        let payloadURL = captureRoot.appendingPathComponent(
            record.payloadRelativePath,
            isDirectory: false
        )
        let data = try Data(contentsOf: payloadURL)
        if let package = try? JSONDecoder().decode(
            HTDTMissionPackage.self,
            from: data
        ), package.schema == HTDTMissionPackage.schema {
            // Re-encode just the embedded plan so `CaptureTaskPlanImport`
            // receives canonical plan bytes — the mission envelope is
            // provenance, the plan is the capture's imported reference.
            let planData = try JSONEncoder().encode(package.plan)
            return try CaptureTaskPlanImport(data: planData)
        }
        return try CaptureTaskPlanImport(data: data)
    }

    private func mutate(
        recordID: String,
        _ body: (inout HTDTMissionRecord) throws -> Void
    ) throws {
        var document = try load()
        guard let index = document.records.firstIndex(where: {
            $0.recordID == recordID
        }) else {
            throw HTDTMissionInboxError.unknownMission(recordID)
        }
        var record = document.records[index]
        try body(&record)
        document.records[index] = record
        try save(document)
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }
}
