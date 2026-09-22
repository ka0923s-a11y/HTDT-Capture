import CryptoKit
import Foundation

/// Contribution identity of a non-spatial field return (issue #400).
/// A contribution is *not* a capture revision — it carries no
/// coordinate space, no session timing, and no RoomPlan payload —
/// but it is the artifact HTDT receives when a mission's inventory,
/// photo, settings or wiring work completes without a scan.
public struct HTDTFieldReturnID: CaptureIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum HTDTFieldReturnError: Error, Sendable, Equatable {
    case emptyField(String)
    case invalidTimestamp(String)
    case invalidBindingRef(String)
    case invalidEvidenceRef(String)
    /// A staged authority record binds a revision id other than the
    /// contribution's own — typed-model reuse keys the record's
    /// `capture_revision_id` slot to the contribution id; anything
    /// else is a typed mismatch, never silently rewritten.
    case authorityBindingMismatch(String)
    case invalidContainerExtension
    case containerNotFinalized
    case artifactAlreadyFinalized
    case archiveTooLargeForClassicZIP
    case filenameTooLong(String)
    case fileOpenFailed(String)
    case atomicPublishFailed
    case destinationAlreadyExists
    /// `fulfilled` (or a claim of partial fulfillment) recorded
    /// without any fulfillment ref — an outcome is only a claim until
    /// an exact authority/evidence ref backs it (issue #418).
    case missingFulfillmentBasis(String)
    /// `declined`/`notApplicable` recorded without an operator or
    /// preflight reason (issue #418).
    case missingOutcomeReason(String)
    /// A fulfillment ref is grammar-valid but names no record this
    /// contribution contains, and is not an explicitly permitted
    /// external reference (issue #418).
    case unresolvedFulfillmentRef(String)
    /// A fulfillment ref resolves but its record type is not
    /// compatible with the task kind (issue #418).
    case incompatibleFulfillmentRef(String)
    /// An embedded authority document's `contribution_ref` disagrees
    /// with the root document's (issue #419).
    case conflictingContributionRef(String)
    /// An embedded document's schema does not match this container's
    /// binding-scope generation (issue #419).
    case incompatibleAuthoritySchema(String)
    /// A record carries a second owner binding inside a doc-level
    /// contribution envelope (issue #419).
    case dualOwnerRecord(String)
    /// The embedded doc's declared schema is not a field-authority
    /// family this container can carry.
    case unknownAuthoritySchema(String)
}

/// A mission contribution (issue #400/#397): either a spatial capture
/// revision or a non-spatial field return. Aggregate mission
/// fulfillment evaluates the *set* — a mission delivered by photos and
/// settings alone produces a `.fieldReturn` contribution alongside or
/// instead of any `.captureRevision`.
public enum HTDTMissionContribution:
    Codable, Sendable, Equatable, Hashable
{
    case captureRevision(CaptureRevisionID)
    case fieldReturn(HTDTFieldReturnID)

    public var kind: String {
        switch self {
        case .captureRevision: return "capture_revision"
        case .fieldReturn: return "field_return"
        }
    }

    /// Canonical `kind:id` text used in manifests and ledgers.
    public var ref: String {
        switch self {
        case .captureRevision(let id):
            return "capture_revision:" + id.description
        case .fieldReturn(let id):
            return "field_return:" + id.description
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let id = try container.decode(String.self, forKey: .id)
        switch kind {
        case "capture_revision":
            guard let uuid = UUID(canonicalUUIDv4Text: id)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription:
                        "Invalid capture revision id \(id)"
                )
            }
            self = .captureRevision(
                CaptureRevisionID(rawValue: uuid)
            )
        case "field_return":
            guard let uuid = UUID(canonicalUUIDv4Text: id)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription:
                        "Invalid field return id \(id)"
                )
            }
            self = .fieldReturn(HTDTFieldReturnID(rawValue: uuid))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown contribution kind \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .captureRevision(let id):
            try container.encode(id.description, forKey: .id)
        case .fieldReturn(let id):
            try container.encode(id.description, forKey: .id)
        }
    }
}

/// What a plan item needs the device to provide (issue #400). The
/// evaluator derives it from the item's type/kind — it is never
/// declared by the plan issuer and never overrides the document.
public enum HTDTTaskSpatialRequirement: String, Sendable, Equatable {
    /// The task needs RoomPlan/ARKit spatial capture output.
    case spatial
    /// The task completes without spatial capture — inventory, photo,
    /// settings or wiring work stands alone.
    case nonSpatial
}

extension SemanticTaskKind {
    /// Spatial requirement of one semantic task kind (issue #400).
    /// Kinds whose authority records bind room geometry — surfaces,
    /// furniture/screens/seats, spatial alignments, room-state
    /// snapshots — are spatial; inventory, routing, commissioning and
    /// room-state observations are non-spatial field work.
    public var spatialRequirement: HTDTTaskSpatialRequirement {
        switch self {
        case .inventoryItem,
             .routingVerification,
             .projectorCommissioning,
             .roomStateObservation:
            return .nonSpatial
        case .surfaceSemantics,
             .surfaceConstruction,
             .problemSurface,
             .constructionFeature,
             .roomStateSnapshot,
             .furnitureSemantics,
             .speakerInstallation,
             .screenSemantics,
             .seatLayout,
             .installationAlignment:
            return .spatial
        }
    }
}

/// The field-authoring kind of one plan task (issue #418): which
/// typed authoring workflow — and therefore which authority record
/// families — a plan item maps to. The evaluator derives it from the
/// item's type/kind; the ledger copies it so fulfillment-type
/// compatibility can be checked without re-reading the plan.
public enum HTDTFieldTaskKind:
    String, Codable, Sendable, CaseIterable
{
    /// Entity placement/identity from `entity_checklist`.
    case entityChecklist = "entity_checklist"
    /// A requested measurement from `measurement_requests`.
    case measurement
    /// A surface/opening review item.
    case surfaceReview = "surface_review"
    /// Inventory identity — `inventory_item` semantic tasks.
    case inventoryItem = "inventory_item"
    /// Cable/routing verification.
    case routingVerification = "routing_verification"
    /// Settings/commissioning values on installed equipment.
    case projectorCommissioning = "projector_commissioning"
    /// Bounded room-state observation.
    case roomStateObservation = "room_state_observation"
    /// An evidence/photo deliverable.
    case evidenceTask = "evidence_task"
    /// Any other semantic task kind (spatial or unclassified field
    /// work) — the conservative bucket.
    case otherSemantic = "other_semantic"

    /// Ref namespaces whose records can fulfill the task. Only
    /// contribution-local authority families are listed — the
    /// validator additionally permits references to external
    /// authorities the mission itself named (plan equipment/task
    /// refs) but never lets them stand alone against a
    /// typed-authority task kind.
    public var fulfillmentNamespaces: Set<String> {
        switch self {
        case .inventoryItem:
            return [
                "inventory_item", "equipment", "field_evidence",
                "task_item",
            ]
        case .routingVerification:
            return [
                "wiring_route", "inventory_item", "equipment",
                "entity", "field_evidence", "task_item",
            ]
        case .projectorCommissioning:
            return [
                "settings_observation", "inventory_item", "equipment",
                "instrument", "field_evidence", "task_item",
            ]
        case .roomStateObservation:
            return [
                "room_state", "settings_observation",
                "field_evidence", "task_item",
            ]
        case .evidenceTask:
            return ["field_evidence", "task_item"]
        case .measurement:
            return [
                "field_evidence", "instrument", "measurement",
                "task_item",
            ]
        case .entityChecklist:
            return [
                "entity", "inventory_item", "equipment",
                "field_evidence", "task_item",
            ]
        case .surfaceReview:
            return ["surface", "field_evidence", "task_item"]
        case .otherSemantic:
            return [
                "field_evidence", "settings_observation",
                "wiring_route", "inventory_item", "room_state",
                "instrument", "entity", "measurement", "equipment",
                "task_item",
            ]
        }
    }

    /// Whether this kind requires at least one contribution-local
    /// typed authority record for `fulfilled` — generic note/file
    /// evidence is not a substitute when the mission explicitly asks
    /// for typed inventory/settings/wiring data (issue #418 §11).
    public var requiresTypedFulfillment: Bool {
        switch self {
        case .inventoryItem:
            return true
        case .routingVerification:
            return true
        case .projectorCommissioning:
            return true
        case .roomStateObservation:
            return true
        case .evidenceTask, .measurement, .entityChecklist,
             .surfaceReview, .otherSemantic:
            return false
        }
    }

    /// The typed namespaces that satisfy `requiresTypedFulfillment`.
    public var typedNamespaces: Set<String> {
        switch self {
        case .inventoryItem:
            return ["inventory_item"]
        case .routingVerification:
            return ["wiring_route"]
        case .projectorCommissioning:
            return ["settings_observation"]
        case .roomStateObservation:
            return ["room_state"]
        default:
            return fulfillmentNamespaces
        }
    }
}

extension HTDTTaskPlanSemanticItem {
    /// The field-authoring kind a semantic task maps to (issue #418).
    public var fieldTaskKind: HTDTFieldTaskKind {
        switch semanticKind {
        case .inventoryItem: return .inventoryItem
        case .routingVerification: return .routingVerification
        case .projectorCommissioning: return .projectorCommissioning
        case .roomStateObservation: return .roomStateObservation
        default: return .otherSemantic
        }
    }
}

/// One task-preflight row (issue #400): every plan item gets an
/// enabled/disabled verdict plus the human-readable reason when the
/// device's capabilities leave it unworkable. The row never hides the
/// task — a disabled spatial task is shown with its reason.
public struct HTDTFieldTaskPreflight: Sendable, Equatable, Identifiable {
    /// `task_item:<item_id>` — the ledger/task-item ref token.
    public let itemRef: String
    public let title: String
    public let requirement: TaskPlanRequirement
    public let spatialRequirement: HTDTTaskSpatialRequirement
    /// Which typed authoring workflow the task maps to (issue #418).
    public let taskKind: HTDTFieldTaskKind
    public let enabled: Bool
    /// Human-readable reason when `enabled == false`; nil otherwise.
    public let disabledReason: String?

    public init(
        itemRef: String,
        title: String,
        requirement: TaskPlanRequirement,
        spatialRequirement: HTDTTaskSpatialRequirement,
        taskKind: HTDTFieldTaskKind,
        enabled: Bool,
        disabledReason: String? = nil
    ) {
        self.itemRef = itemRef
        self.title = title
        self.requirement = requirement
        self.spatialRequirement = spatialRequirement
        self.taskKind = taskKind
        self.enabled = enabled
        self.disabledReason = disabledReason
    }

    public var id: String { itemRef }
}

/// Per-task capability preflight (issue #400): classifies a mission's
/// imported plan items against the device's spatial capability so a
/// non-spatial device still runs inventory/photo/settings/wiring work
/// while spatial tasks surface a precise disabled reason.
public enum HTDTFieldTaskPreflightEvaluator {
    /// The human-readable reason a spatial task is disabled on a
    /// device without spatial capture.
    public static let spatialUnavailableReason =
        "requires spatial capture (RoomPlan/ARKit) — unavailable "
        + "on this device"

    /// Preflight the whole plan. `spatialAvailable` is the device's
    /// `roomPlanMeshEligible` verdict — false on non-LiDAR hardware.
    public static func evaluate(
        plan: HTDTCaptureTaskPlan,
        spatialAvailable: Bool
    ) -> [HTDTFieldTaskPreflight] {
        var rows: [HTDTFieldTaskPreflight] = []
        func row(
            itemID: String,
            title: String,
            requirement: TaskPlanRequirement,
            spatial: HTDTTaskSpatialRequirement,
            taskKind: HTDTFieldTaskKind
        ) -> HTDTFieldTaskPreflight {
            let enabled =
                spatialAvailable || spatial == .nonSpatial
            return HTDTFieldTaskPreflight(
                itemRef: "task_item:" + itemID,
                title: title,
                requirement: requirement,
                spatialRequirement: spatial,
                taskKind: taskKind,
                enabled: enabled,
                disabledReason: enabled
                    ? nil : spatialUnavailableReason
            )
        }
        for item in plan.entityChecklist {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.labelHint
                        ?? item.entityType.rawValue,
                    requirement: item.requirement,
                    spatial: .spatial,
                    taskKind: .entityChecklist
                )
            )
        }
        for item in plan.measurementRequests {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.quantityType,
                    requirement: item.requirement,
                    // The plan's typed acquisition requirement —
                    // never inferred from `quantityType`/endpoint
                    // strings (issue #418). Plans without the field
                    // fail conservatively as spatial.
                    spatial: (
                        item.acquisitionRequirement
                            ?? .spatialPointRequired
                    ).requiresSpatialAcquisition
                        ? .spatial : .nonSpatial,
                    taskKind: .measurement
                )
            )
        }
        for item in plan.surfaceReviewTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.surfaceKind,
                    requirement: item.requirement,
                    spatial: .spatial,
                    taskKind: .surfaceReview
                )
            )
        }
        for item in plan.semanticTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.label ?? item.semanticKind.rawValue,
                    requirement: item.requirement,
                    spatial: item.semanticKind.spatialRequirement,
                    taskKind: item.fieldTaskKind
                )
            )
        }
        for item in plan.evidenceTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.purpose,
                    requirement: item.requirement,
                    spatial: .nonSpatial,
                    taskKind: .evidenceTask
                )
            )
        }
        return rows
    }
}

/// One row of the field return's task fulfillment ledger (issue
/// #400): the plan item, its operator-marked outcome, and the
/// authority refs that fulfill it.
public struct HTDTFieldReturnTaskLedgerEntry:
    Codable, Sendable, Equatable
{
    public enum Outcome: String, Codable, Sendable {
        case fulfilled
        case partiallyFulfilled = "partially_fulfilled"
        case declined
        case notApplicable = "not_applicable"
        /// Required on the plan but skipped by the operator —
        /// recorded honestly, never silently dropped.
        case unfulfilled
    }

    /// `task_item:<id>` ref into the bound plan.
    public let itemRef: String
    public let title: String
    public let requirement: TaskPlanRequirement
    /// Which typed authoring workflow the item maps to (issue #418).
    /// nil on ledger rows written before the field existed — those
    /// evaluate through `.otherSemantic`'s permissive namespace set.
    public let taskKind: HTDTFieldTaskKind?
    /// Ref namespaces whose records may fulfill this item, captured
    /// from the kind at seed time so the validator need not re-derive
    /// it (issue #418). nil on legacy rows — interpreted through
    /// `taskKind`.
    public let fulfillmentNamespaces: Set<String>?
    public var outcome: Outcome
    /// Authority refs fulfilling the item —
    /// `field_evidence:`/`settings_observation:`/`wiring_route:`/
    /// `inventory_item:`/`entity:`/`measurement:` tokens.
    public var fulfilledByRefs: [String]
    /// Optional operator note (e.g. why declined).
    public var note: String?

    /// The effective fulfillment-namespace contract — explicit when
    /// persisted, derived from the kind otherwise.
    public var permittedFulfillmentNamespaces: Set<String> {
        fulfillmentNamespaces
            ?? (taskKind ?? .otherSemantic).fulfillmentNamespaces
    }

    /// Whether `fulfilled` requires a contribution-local typed
    /// record (issue #418 §11).
    public var requiresTypedFulfillment: Bool {
        (taskKind ?? .otherSemantic).requiresTypedFulfillment
    }

    /// The typed namespaces that count for `requiresTypedFulfillment`.
    public var typedFulfillmentNamespaces: Set<String> {
        (taskKind ?? .otherSemantic).typedNamespaces
    }

    public init(
        itemRef: String,
        title: String,
        requirement: TaskPlanRequirement,
        outcome: Outcome,
        fulfilledByRefs: [String] = [],
        note: String? = nil,
        taskKind: HTDTFieldTaskKind? = nil,
        fulfillmentNamespaces: Set<String>? = nil
    ) throws {
        guard FieldAuthorityGrammar.isBindingRef(itemRef)
                || itemRef.hasPrefix("task_item:")
        else {
            throw HTDTFieldReturnError.invalidBindingRef(itemRef)
        }
        for ref in fulfilledByRefs {
            guard FieldAuthorityGrammar.isBindingRef(ref) else {
                throw HTDTFieldReturnError.invalidBindingRef(ref)
            }
        }
        let trimmedTitle =
            SchemaOwnedText.nfc(title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw HTDTFieldReturnError.emptyField("title")
        }
        self.itemRef = itemRef
        self.title = trimmedTitle
        self.requirement = requirement
        self.outcome = outcome
        self.fulfilledByRefs = fulfilledByRefs
        self.note = SchemaOwnedText.nfc(note)
        self.taskKind = taskKind
        self.fulfillmentNamespaces = fulfillmentNamespaces
    }

    private enum CodingKeys: String, CodingKey {
        case itemRef = "item_ref"
        case title
        case requirement
        case outcome
        case fulfilledByRefs = "fulfilled_by_refs"
        case note
        case taskKind = "task_kind"
        case fulfillmentNamespaces = "fulfillment_namespaces"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            itemRef: container.decode(String.self, forKey: .itemRef),
            title: container.decode(String.self, forKey: .title),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            outcome: container.decode(Outcome.self, forKey: .outcome),
            fulfilledByRefs: container.decodeIfPresent(
                [String].self,
                forKey: .fulfilledByRefs
            ) ?? [],
            note: container.decodeIfPresent(
                String.self,
                forKey: .note
            ),
            taskKind: container.decodeIfPresent(
                HTDTFieldTaskKind.self,
                forKey: .taskKind
            ),
            fulfillmentNamespaces: container.decodeIfPresent(
                Set<String>.self,
                forKey: .fulfillmentNamespaces
            )
        )
    }
}

/// Provenance block of a field return (issue #400): who produced it —
/// never a device serial or account identity.
public struct HTDTFieldReturnProvenance:
    Codable, Sendable, Equatable
{
    public let producer: String
    public let appName: String
    public let appVersion: String
    public let deviceModelFamily: String

    public init(
        appName: String,
        appVersion: String,
        deviceModelFamily: String
    ) {
        self.producer = "field_return_finalizer"
        self.appName = appName
        self.appVersion = appVersion
        self.deviceModelFamily = deviceModelFamily
    }

    private enum CodingKeys: String, CodingKey {
        case producer
        case appName = "app_name"
        case appVersion = "app_version"
        case deviceModelFamily = "device_model_family"
    }
}

/// A committed authority document inside the `.htdtfieldreturn`
/// container — path plus digest so receivers can verify entries
/// without trusting the container manifest.
public struct HTDTFieldReturnDocumentRef:
    Codable, Sendable, Equatable
{
    public let path: String
    public let schema: String
    public let sha256: EvidenceSHA256
    public let bytes: Int

    public init(
        path: String,
        schema: String,
        sha256: EvidenceSHA256,
        bytes: Int
    ) {
        self.path = path
        self.schema = schema
        self.sha256 = sha256
        self.bytes = bytes
    }
}

/// The root document inside a `.htdtfieldreturn` container (issue
/// #400): the versioned `htdt.field_return` contract. Schema
/// version 2.0.0 (issue #419) binds every embedded typed authority
/// document through an explicit `contribution_ref` envelope —
/// documents no longer stuff the contribution id into a
/// `capture_revision_id` slot. Version 1.0.0 documents declared
/// `authority_binding_scope = contribution_id` and carried the
/// contribution id in that slot; the decoder normalizes them in
/// memory while `HTDTFieldReturnDocument.schemaVersion` retains the
/// original raw version for provenance.
public struct HTDTFieldReturnDocument:
    Codable, Sendable, Equatable
{
    public static let schemaName = "htdt.field_return"
    /// The generation this build emits. 2.0.0 embeds
    /// `htdt.field_return.*` contribution-ref envelopes.
    public static let schemaVersionValue = "2.0.0"
    /// The 1.0.0 generation (capture_revision_id binding).
    public static let schemaVersionV1 = "1.0.0"
    public static let path = "field-return.json"
    /// v2 `authority_binding_scope` — documents bind a typed
    /// `contribution_ref` at the document level.
    public static let bindingScope = "contribution_ref"
    /// v1 `authority_binding_scope` — documents bound the
    /// contribution id in their `capture_revision_id` slots.
    public static let bindingScopeV1 = "contribution_id"

    public let schema: String
    public let schemaVersion: String
    /// States how embedded typed docs are bound — `contribution_ref`
    /// for v2, `contribution_id` for v1.
    public let authorityBindingScope: String
    public let contributionID: HTDTFieldReturnID
    /// The typed owner binding of every embedded authority document
    /// (issue #419). v1 documents have no `contribution_ref` field —
    /// decoding synthesizes `.fieldReturn(contributionID)` under the
    /// declared `contribution_id` scope.
    public let contributionRef: HTDTMissionContribution
    /// The finalized contribution this return supersedes, when it is
    /// a follow-up/correction (issue #418 refinement) — lineage
    /// only; the superseded artifact's bytes stay immutable.
    public let supersedesContributionRef: HTDTMissionContribution?
    /// Mission identity the return was issued under, when bound.
    public let missionID: String?
    public let planID: String?
    public let planVersion: String?
    public let planSHA256: String?
    public let createdAtUTC: String
    public let finalizedAtUTC: String
    public let provenance: HTDTFieldReturnProvenance
    /// Capture revisions this return relates to (sibling contributions
    /// to the same mission) — references only; the return does not
    /// embed capture content.
    public let relatedCaptureRevisionIDs: [CaptureRevisionID]
    public let taskFulfillmentLedger:
        [HTDTFieldReturnTaskLedgerEntry]
    /// `authority/*.json` documents inside the container.
    public let authorityDocuments: [HTDTFieldReturnDocumentRef]
    /// `evidence/**` binary payloads inside the container.
    public let evidenceAssets: [HTDTFieldReturnDocumentRef]
    /// Semantic root-document digest (issue #419): v2 is a SHA-256
    /// over the canonical encoding of this document minus the
    /// `content_digest` field itself — no hand-maintained field list
    /// can silently omit a new field. v1 artifacts keep their
    /// published line-hash algorithm; `HTDTFieldReturnDigest.verify`
    /// dispatches on `schema_version`.
    public let contentDigest: EvidenceSHA256

    /// True when the decoded document came from a v1 container.
    public var isV1Layout: Bool {
        schemaVersion == Self.schemaVersionV1
            || authorityBindingScope == Self.bindingScopeV1
    }

    public init(
        contributionID: HTDTFieldReturnID,
        missionID: String?,
        planID: String?,
        planVersion: String?,
        planSHA256: String?,
        createdAtUTC: String,
        finalizedAtUTC: String,
        provenance: HTDTFieldReturnProvenance,
        relatedCaptureRevisionIDs: [CaptureRevisionID],
        taskFulfillmentLedger: [HTDTFieldReturnTaskLedgerEntry],
        authorityDocuments: [HTDTFieldReturnDocumentRef],
        evidenceAssets: [HTDTFieldReturnDocumentRef],
        supersedesContributionRef: HTDTMissionContribution? = nil,
        contentDigest: EvidenceSHA256
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(createdAtUTC),
              SchemaTimestampText.isUTCTimestamp(finalizedAtUTC)
        else {
            throw HTDTFieldReturnError.invalidTimestamp(
                createdAtUTC
            )
        }
        self.schema = Self.schemaName
        self.schemaVersion = Self.schemaVersionValue
        self.authorityBindingScope = Self.bindingScope
        self.contributionID = contributionID
        self.contributionRef = .fieldReturn(contributionID)
        self.supersedesContributionRef = supersedesContributionRef
        self.missionID = missionID
        self.planID = planID
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.createdAtUTC = createdAtUTC
        self.finalizedAtUTC = finalizedAtUTC
        self.provenance = provenance
        self.relatedCaptureRevisionIDs = relatedCaptureRevisionIDs
        self.taskFulfillmentLedger = taskFulfillmentLedger
        self.authorityDocuments = authorityDocuments
        self.evidenceAssets = evidenceAssets
        self.contentDigest = contentDigest
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case authorityBindingScope = "authority_binding_scope"
        case contributionID = "contribution_id"
        case contributionRef = "contribution_ref"
        case supersedesContributionRef =
            "supersedes_contribution_ref"
        case missionID = "mission_id"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case planSHA256 = "plan_sha256"
        case createdAtUTC = "created_at"
        case finalizedAtUTC = "finalized_at"
        case provenance
        case relatedCaptureRevisionIDs =
            "related_capture_revision_ids"
        case taskFulfillmentLedger = "task_fulfillment_ledger"
        case authorityDocuments = "authority_documents"
        case evidenceAssets = "evidence_assets"
        case contentDigest = "content_digest"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decode(
            String.self, forKey: .schema
        )
        self.schemaVersion = try container.decode(
            String.self, forKey: .schemaVersion
        )
        self.authorityBindingScope = try container.decode(
            String.self, forKey: .authorityBindingScope
        )
        self.contributionID = try container.decode(
            HTDTFieldReturnID.self, forKey: .contributionID
        )
        // v1 containers declared `contribution_id` scope and no
        // contribution_ref — normalize to the typed ref under that
        // declared scope, never by UUID inference.
        self.contributionRef = try container.decodeIfPresent(
            HTDTMissionContribution.self,
            forKey: .contributionRef
        ) ?? .fieldReturn(contributionID)
        self.supersedesContributionRef = try container
            .decodeIfPresent(
                HTDTMissionContribution.self,
                forKey: .supersedesContributionRef
            )
        self.missionID = try container.decodeIfPresent(
            String.self, forKey: .missionID
        )
        self.planID = try container.decodeIfPresent(
            String.self, forKey: .planID
        )
        self.planVersion = try container.decodeIfPresent(
            String.self, forKey: .planVersion
        )
        self.planSHA256 = try container.decodeIfPresent(
            String.self, forKey: .planSHA256
        )
        self.createdAtUTC = try container.decode(
            String.self, forKey: .createdAtUTC
        )
        self.finalizedAtUTC = try container.decode(
            String.self, forKey: .finalizedAtUTC
        )
        self.provenance = try container.decode(
            HTDTFieldReturnProvenance.self, forKey: .provenance
        )
        self.relatedCaptureRevisionIDs = try container
            .decodeIfPresent(
                [CaptureRevisionID].self,
                forKey: .relatedCaptureRevisionIDs
            ) ?? []
        self.taskFulfillmentLedger = try container.decode(
            [HTDTFieldReturnTaskLedgerEntry].self,
            forKey: .taskFulfillmentLedger
        )
        self.authorityDocuments = try container.decode(
            [HTDTFieldReturnDocumentRef].self,
            forKey: .authorityDocuments
        )
        self.evidenceAssets = try container.decode(
            [HTDTFieldReturnDocumentRef].self,
            forKey: .evidenceAssets
        )
        self.contentDigest = try container.decode(
            EvidenceSHA256.self, forKey: .contentDigest
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            authorityBindingScope,
            forKey: .authorityBindingScope
        )
        try container.encode(contributionID, forKey: .contributionID)
        try container.encode(contributionRef, forKey: .contributionRef)
        try container.encodeIfPresent(
            supersedesContributionRef,
            forKey: .supersedesContributionRef
        )
        try container.encodeIfPresent(missionID, forKey: .missionID)
        try container.encodeIfPresent(planID, forKey: .planID)
        try container.encodeIfPresent(
            planVersion, forKey: .planVersion
        )
        try container.encodeIfPresent(planSHA256, forKey: .planSHA256)
        try container.encode(createdAtUTC, forKey: .createdAtUTC)
        try container.encode(finalizedAtUTC, forKey: .finalizedAtUTC)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(
            relatedCaptureRevisionIDs,
            forKey: .relatedCaptureRevisionIDs
        )
        try container.encode(
            taskFulfillmentLedger,
            forKey: .taskFulfillmentLedger
        )
        try container.encode(
            authorityDocuments, forKey: .authorityDocuments
        )
        try container.encode(evidenceAssets, forKey: .evidenceAssets)
        try container.encode(contentDigest, forKey: .contentDigest)
    }
}

/// The assembled field return (issue #400): the root document plus
/// every container entry (path → bytes) in canonical order. The
/// archive writer streams these entries; nothing else interprets
/// them.
public struct HTDTFieldReturnArtifact: Sendable, Equatable {
    /// One container entry — path inside the archive and its bytes.
    public struct Entry: Sendable, Equatable {
        public let path: String
        public let data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public let document: HTDTFieldReturnDocument
    public let entries: [Entry]

    public init(
        document: HTDTFieldReturnDocument,
        entries: [Entry]
    ) {
        self.document = document
        self.entries = entries
    }
}

/// The staged, editable field-return workspace (issue #400): the
/// non-spatial equivalent of the capture working set. It reuses
/// `FieldAuthorityWorkspace` for the typed authority content — the
/// records there bind the contribution id in their
/// `capture_revision_id` slot (`HTDTFieldReturnDocument`
/// declares this scope). Persisted as app-private JSON at
/// `<captureRoot>/field-returns.json`; finalize produces the
/// immutable `.htdtfieldreturn` container.
public struct HTDTFieldReturnWorkspace:
    Codable, Sendable, Equatable
{
    public var contributionID: HTDTFieldReturnID
    /// Mission record this return works against, when issued.
    public var missionRecordID: String?
    public var missionID: String?
    public var planID: String?
    public var planVersion: String?
    public var planSHA256: String?
    /// Sibling capture revisions for aggregate fulfillment (#397).
    public var relatedCaptureRevisionIDs: [CaptureRevisionID]
    /// The finalized contribution this workspace supersedes — set
    /// when the operator starts a follow-up/correction against an
    /// already-finalized return (issue #418 refinement).
    public var supersedesContributionID: HTDTFieldReturnID?
    public var authority: FieldAuthorityWorkspace
    /// Inventory identity authored in this return (issue #418):
    /// canonical `SystemInventoryItem` records — never freeform
    /// field-evidence titles.
    public var inventoryItems: [SystemInventoryItem]
    /// Bounded room-state observations authored without spatial
    /// scene authority (issue #418).
    public var roomStateObservations: [RoomStateObservation]
    public var taskLedger: [HTDTFieldReturnTaskLedgerEntry]
    public var createdAtUTC: String
    /// Archive digest once finalized — an already-finalized workspace
    /// accepts no further edits.
    public var finalizedAtUTC: String?
    public var finalizedDigest: String?

    public init(
        contributionID: HTDTFieldReturnID = HTDTFieldReturnID(),
        missionRecordID: String? = nil,
        missionID: String? = nil,
        planID: String? = nil,
        planVersion: String? = nil,
        planSHA256: String? = nil,
        relatedCaptureRevisionIDs: [CaptureRevisionID] = [],
        supersedesContributionID: HTDTFieldReturnID? = nil,
        taskLedger: [HTDTFieldReturnTaskLedgerEntry] = [],
        createdAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) {
        self.contributionID = contributionID
        self.missionRecordID = missionRecordID
        self.missionID = missionID
        self.planID = planID
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.relatedCaptureRevisionIDs = relatedCaptureRevisionIDs
        self.supersedesContributionID = supersedesContributionID
        self.authority = FieldAuthorityWorkspace()
        self.inventoryItems = []
        self.roomStateObservations = []
        self.taskLedger = taskLedger
        self.createdAtUTC = createdAtUTC
        self.finalizedAtUTC = nil
        self.finalizedDigest = nil
    }

    public var isFinalized: Bool { finalizedAtUTC != nil }

    /// The typed owner of this contribution (issue #419) — a field
    /// return, never a capture revision.
    public var contributionRef: HTDTMissionContribution {
        .fieldReturn(contributionID)
    }

    /// Internal v1-compat carrier: the `CaptureRevisionID`-typed
    /// value the shared record models (`FieldEvidenceRecord`,
    /// `InstalledSettingsObservation`, `AsBuiltWiringRoute`) require
    /// in their `capture_revision_id` slot while the record lives in
    /// memory. It is a record-carrier only — no capture revision
    /// exists. The container emits `contribution_ref` envelopes and
    /// strips this slot on the wire (issue #419); the value never
    /// escapes into domain APIs or persisted v2 documents.
    public var recordCarrierID: CaptureRevisionID {
        CaptureRevisionID(rawValue: contributionID.rawValue)
    }

    /// Seeds the task ledger from a preflighted plan — one row per
    /// plan item, `unfulfilled`/`notApplicable` defaulting by whether
    /// the item is enabled on this device. Disabled rows carry the
    /// preflight reason as their outcome note so `notApplicable`
    /// always has a basis (issue #418).
    public mutating func seedTaskLedger(
        preflight: [HTDTFieldTaskPreflight]
    ) throws {
        guard taskLedger.isEmpty else {
            throw HTDTFieldReturnError.artifactAlreadyFinalized
        }
        taskLedger = try preflight.map { row in
            try HTDTFieldReturnTaskLedgerEntry(
                itemRef: row.itemRef,
                title: row.title,
                requirement: row.requirement,
                outcome: row.enabled
                    ? .unfulfilled : .notApplicable,
                note: row.enabled ? nil : row.disabledReason,
                taskKind: row.taskKind,
                fulfillmentNamespaces:
                    row.taskKind.fulfillmentNamespaces
            )
        }
    }

    /// Validates outcome semantics (issue #418) without touching the
    /// workspace — shared by `recordTaskOutcome` and the finalize
    /// validator.
    static func checkOutcomeSemantics(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome,
        fulfilledByRefs: [String],
        note: String?,
        permittedNamespaces: Set<String>
    ) throws {
        let hasReason = !(note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        switch outcome {
        case .fulfilled:
            guard !fulfilledByRefs.isEmpty else {
                throw HTDTFieldReturnError
                    .missingFulfillmentBasis(itemRef)
            }
        case .partiallyFulfilled:
            guard !fulfilledByRefs.isEmpty || hasReason else {
                throw HTDTFieldReturnError
                    .missingFulfillmentBasis(itemRef)
            }
        case .declined, .notApplicable:
            guard hasReason else {
                throw HTDTFieldReturnError
                    .missingOutcomeReason(itemRef)
            }
        case .unfulfilled:
            break
        }
        for ref in fulfilledByRefs {
            guard FieldAuthorityGrammar.isBindingRef(ref) else {
                throw HTDTFieldReturnError.invalidBindingRef(ref)
            }
            let namespace = ref.prefix {
                $0 != ":"
            }
            guard permittedNamespaces.contains(
                String(namespace)
            ) else {
                throw HTDTFieldReturnError
                    .incompatibleFulfillmentRef(ref)
            }
        }
    }

    /// Records a task outcome plus the authority refs that fulfill
    /// it. Outcome semantics (issue #418): `fulfilled` requires a
    /// resolvable basis ref, `partiallyFulfilled` a ref or a reason,
    /// `declined`/`notApplicable` a reason; every ref must be
    /// grammar-valid and type-compatible with the task kind.
    /// An unknown item ref is a typed rejection.
    public mutating func recordTaskOutcome(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome,
        fulfilledByRefs: [String] = [],
        note: String? = nil
    ) throws {
        guard !isFinalized else {
            throw HTDTFieldReturnError.containerNotFinalized
        }
        guard let index = taskLedger.firstIndex(where: {
            $0.itemRef == itemRef
        }) else {
            throw HTDTFieldReturnError.invalidBindingRef(itemRef)
        }
        let entry = taskLedger[index]
        try Self.checkOutcomeSemantics(
            itemRef: itemRef,
            outcome: outcome,
            fulfilledByRefs: fulfilledByRefs,
            note: note,
            permittedNamespaces:
                entry.permittedFulfillmentNamespaces
        )
        taskLedger[index].outcome = outcome
        taskLedger[index].fulfilledByRefs = fulfilledByRefs
        taskLedger[index].note = SchemaOwnedText.nfc(note)
    }

    private enum CodingKeys: String, CodingKey {
        case contributionID = "contribution_id"
        case missionRecordID = "mission_record_id"
        case missionID = "mission_id"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case planSHA256 = "plan_sha256"
        case relatedCaptureRevisionIDs =
            "related_capture_revision_ids"
        case supersedesContributionID =
            "supersedes_contribution_id"
        case authority
        case inventoryItems = "inventory_items"
        case roomStateObservations = "room_state_observations"
        case taskLedger = "task_ledger"
        case createdAtUTC = "created_at"
        case finalizedAtUTC = "finalized_at"
        case finalizedDigest = "finalized_digest"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        self.contributionID = try container.decode(
            HTDTFieldReturnID.self,
            forKey: .contributionID
        )
        self.missionRecordID = try container.decodeIfPresent(
            String.self,
            forKey: .missionRecordID
        )
        self.missionID = try container.decodeIfPresent(
            String.self,
            forKey: .missionID
        )
        self.planID = try container.decodeIfPresent(
            String.self,
            forKey: .planID
        )
        self.planVersion = try container.decodeIfPresent(
            String.self,
            forKey: .planVersion
        )
        self.planSHA256 = try container.decodeIfPresent(
            String.self,
            forKey: .planSHA256
        )
        self.relatedCaptureRevisionIDs = try container
            .decodeIfPresent(
                [CaptureRevisionID].self,
                forKey: .relatedCaptureRevisionIDs
            ) ?? []
        self.supersedesContributionID = try container
            .decodeIfPresent(
                HTDTFieldReturnID.self,
                forKey: .supersedesContributionID
            )
        self.authority = try container.decode(
            FieldAuthorityWorkspace.self,
            forKey: .authority
        )
        self.inventoryItems = try container.decodeIfPresent(
            [SystemInventoryItem].self,
            forKey: .inventoryItems
        ) ?? []
        self.roomStateObservations = try container.decodeIfPresent(
            [RoomStateObservation].self,
            forKey: .roomStateObservations
        ) ?? []
        self.taskLedger = try container.decode(
            [HTDTFieldReturnTaskLedgerEntry].self,
            forKey: .taskLedger
        )
        self.createdAtUTC = try container.decode(
            String.self,
            forKey: .createdAtUTC
        )
        self.finalizedAtUTC = try container.decodeIfPresent(
            String.self,
            forKey: .finalizedAtUTC
        )
        self.finalizedDigest = try container.decodeIfPresent(
            String.self,
            forKey: .finalizedDigest
        )
    }
}

/// Builds the immutable `.htdtfieldreturn` artifact (issue #400) from
/// a finalized workspace: typed authority docs under `authority/`,
/// staged evidence assets under `evidence/`, the root
/// `field-return.json`, then the container manifest. The builder
/// performs every validation the typed documents enforce — records
/// bound to another contribution id are rejected, not rebound.
/// Issue #418/#419: the finalize path runs the fulfillment-ledger
/// validator first, then emits `htdt.field_return.*`
/// contribution-ref envelopes so no synthetic CaptureRevisionID
/// reaches the wire.
public enum HTDTFieldReturnAssembler {
    /// Canonical document ordering inside the container.
    public static let authorityPathPrefix = "authority/"

    public static func assemble(
        workspace: HTDTFieldReturnWorkspace,
        provenance: HTDTFieldReturnProvenance,
        finalizedAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws -> HTDTFieldReturnArtifact {
        guard !workspace.isFinalized else {
            throw HTDTFieldReturnError.artifactAlreadyFinalized
        }
        // Fulfillment contract first: a `fulfilled` claim without a
        // resolvable compatible basis never reaches the artifact.
        try HTDTFieldReturnValidator.validate(workspace: workspace)
        let carrier = workspace.recordCarrierID
        let contributionRef = workspace.contributionRef
        var entries: [HTDTFieldReturnArtifact.Entry] = []
        var documentRefs: [HTDTFieldReturnDocumentRef] = []
        var assetRefs: [HTDTFieldReturnDocumentRef] = []

        func addDocument(
            family: FieldContributionDocs.Family,
            data: Data
        ) throws {
            let path = authorityPathPrefix + family.fileName
            entries.append(.init(path: path, data: data))
            documentRefs.append(
                .init(
                    path: path,
                    schema: family.rawValue,
                    sha256: EvidenceIntegrity.sha256(of: data),
                    bytes: data.count
                )
            )
        }

        let authority = workspace.authority
        if !authority.operatorProfiles.isEmpty {
            try addDocument(
                family: .operatorProfiles,
                data: FieldContributionDocs.encode(
                    family: .operatorProfiles,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: authority.operatorProfiles
                )
            )
        }
        if !authority.instruments.isEmpty {
            try addDocument(
                family: .instrumentProfiles,
                data: FieldContributionDocs.encode(
                    family: .instrumentProfiles,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: authority.instruments
                )
            )
        }
        if !authority.fieldEvidence.isEmpty {
            for record in authority.fieldEvidence {
                try requireBinding(
                    record.captureRevisionID,
                    carrier: carrier,
                    ref: "field_evidence:\(record.evidenceID)"
                )
            }
            try addDocument(
                family: .fieldEvidence,
                data: FieldContributionDocs.encode(
                    family: .fieldEvidence,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: authority.fieldEvidence
                )
            )
        }
        if !authority.settingsObservations.isEmpty {
            for observation in authority.settingsObservations {
                try requireBinding(
                    observation.captureRevisionID,
                    carrier: carrier,
                    ref: "settings_observation:"
                        + observation.observationID.description
                )
            }
            try addDocument(
                family: .settingsObservations,
                data: FieldContributionDocs.encode(
                    family: .settingsObservations,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: authority.settingsObservations
                )
            )
        }
        if !authority.wiringRoutes.isEmpty {
            for route in authority.wiringRoutes {
                try requireBinding(
                    route.captureRevisionID,
                    carrier: carrier,
                    ref: "wiring_route:\(route.routeID)"
                )
            }
            try addDocument(
                family: .wiringRoutes,
                data: FieldContributionDocs.encode(
                    family: .wiringRoutes,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: authority.wiringRoutes
                )
            )
        }
        if !workspace.inventoryItems.isEmpty {
            try addDocument(
                family: .inventoryItems,
                data: FieldContributionDocs.encode(
                    family: .inventoryItems,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: workspace.inventoryItems
                )
            )
        }
        if !workspace.roomStateObservations.isEmpty {
            try addDocument(
                family: .roomStateObservations,
                data: FieldContributionDocs.encode(
                    family: .roomStateObservations,
                    contributionRef: contributionRef,
                    recordedAtUTC: finalizedAtUTC,
                    records: workspace.roomStateObservations
                )
            )
        }

        // Evidence asset payloads — the staged workspace's data bytes
        // land under `evidence/` verbatim; removal-staged assets never
        // enter the container.
        for asset in authority.fieldEvidenceAssets
        where !asset.removal {
            entries.append(.init(path: asset.path, data: asset.data))
            assetRefs.append(
                .init(
                    path: asset.path,
                    schema: "",
                    sha256: EvidenceIntegrity.sha256(
                        of: asset.data
                    ),
                    bytes: asset.data.count
                )
            )
        }

        // v2 semantic digest (issue #419 refinement): SHA-256 over
        // the canonical encoding of the root document with its own
        // `content_digest` field removed — every other root field
        // (planVersion, provenance, ledger notes, related revision
        // ids, entry digests) is covered by construction, and new
        // fields can never be silently omitted. The v1 line-hash is
        // retained for replay under `HTDTFieldReturnDigest`.
        let placeholder = try EvidenceSHA256(
            String(repeating: "0", count: 64)
        )
        let provisional = try HTDTFieldReturnDocument(
            contributionID: workspace.contributionID,
            missionID: workspace.missionID,
            planID: workspace.planID,
            planVersion: workspace.planVersion,
            planSHA256: workspace.planSHA256,
            createdAtUTC: workspace.createdAtUTC,
            finalizedAtUTC: finalizedAtUTC,
            provenance: provenance,
            relatedCaptureRevisionIDs:
                workspace.relatedCaptureRevisionIDs,
            taskFulfillmentLedger: workspace.taskLedger,
            authorityDocuments: documentRefs,
            evidenceAssets: assetRefs,
            supersedesContributionRef:
                workspace.supersedesContributionID
                    .map { .fieldReturn($0) },
            contentDigest: placeholder
        )
        let contentDigest =
            try HTDTFieldReturnDigest.semanticDigest(
                of: provisional
            )
        let document = try HTDTFieldReturnDocument(
            contributionID: workspace.contributionID,
            missionID: workspace.missionID,
            planID: workspace.planID,
            planVersion: workspace.planVersion,
            planSHA256: workspace.planSHA256,
            createdAtUTC: workspace.createdAtUTC,
            finalizedAtUTC: finalizedAtUTC,
            provenance: provenance,
            relatedCaptureRevisionIDs:
                workspace.relatedCaptureRevisionIDs,
            taskFulfillmentLedger: workspace.taskLedger,
            authorityDocuments: documentRefs,
            evidenceAssets: assetRefs,
            supersedesContributionRef:
                workspace.supersedesContributionID
                    .map { .fieldReturn($0) },
            contentDigest: contentDigest
        )
        let docEncoder = JSONEncoder()
        docEncoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        entries.append(
            .init(
                path: HTDTFieldReturnDocument.path,
                data: try docEncoder.encode(document)
            )
        )
        entries.sort { $0.path < $1.path }
        return HTDTFieldReturnArtifact(
            document: document,
            entries: entries
        )
    }

    private static func requireBinding(
        _ recordRevision: CaptureRevisionID,
        carrier: CaptureRevisionID,
        ref: String
    ) throws {
        guard recordRevision == carrier else {
            throw HTDTFieldReturnError.authorityBindingMismatch(ref)
        }
    }
}

/// The field return's digest contract (issue #419 refinement). Two
/// algorithms exist and each artifact names its own:
///
/// - **v2 semantic digest** — SHA-256 over the canonical encoding of
///   the root document minus `content_digest`, computed by encoding
///   the document and re-serializing the JSON object with the key
///   removed. It covers every root field by construction.
/// - **v1 line hash** — the published 1.0.0 algorithm: newline-
///   separated identity/ledger/entry lines. Kept verbatim so any v1
///   artifact's digest replays byte-for-byte.
///
/// The ZIP/container manifest separately covers exact entry bytes —
/// it is the transport-integrity digest, not this semantic one.
public enum HTDTFieldReturnDigest {
    /// v2: semantic digest of the root document. The digest covers
    /// every field of the document except `content_digest` itself —
    /// provenance, plan identity, ledger notes, supersession lineage
    /// and entry digests all contribute.
    public static func semanticDigest(
        of document: HTDTFieldReturnDocument
    ) throws -> EvidenceSHA256 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let encoded = try encoder.encode(document)
        guard var object = try JSONSerialization
            .jsonObject(with: encoded) as? [String: Any]
        else {
            throw HTDTFieldReturnError
                .incompatibleAuthoritySchema("field-return.json")
        }
        object.removeValue(forKey: "content_digest")
        let canonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        let hash = SHA256.hash(data: canonical).map {
            String(format: "%02x", $0)
        }.joined()
        return try EvidenceSHA256(hash)
    }

    /// v1 replay: the published 1.0.0 line-hash algorithm over the
    /// fields that version covered — retained verbatim so existing
    /// `.htdtfieldreturn` v1 artifacts verify identically. Newer
    /// fields are deliberately not hashed; v1 semantics are frozen.
    public static func legacyDigest(
        of document: HTDTFieldReturnDocument
    ) throws -> EvidenceSHA256 {
        var hasher = SHA256()
        func hashLine(_ line: String) {
            hasher.update(data: Data(line.utf8))
            hasher.update(data: Data([0x0A]))
        }
        hashLine(HTDTFieldReturnDocument.schemaName)
        hashLine(HTDTFieldReturnDocument.schemaVersionV1)
        hashLine(document.contributionID.description)
        hashLine(document.missionID ?? "")
        hashLine(document.planID ?? "")
        hashLine(document.createdAtUTC)
        hashLine(document.finalizedAtUTC)
        for entry in document.taskFulfillmentLedger {
            hashLine(
                entry.itemRef + "|" + entry.outcome.rawValue
                    + "|" + entry.fulfilledByRefs.joined(
                        separator: ","
                    )
            )
        }
        for ref in document.authorityDocuments
            + document.evidenceAssets {
            hashLine(ref.path + "|" + ref.sha256.value)
        }
        let digestHex = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
        return try EvidenceSHA256(digestHex)
    }

    /// Recomputes the digest the document's own schema version
    /// declares and reports whether it matches `content_digest`.
    /// v1 documents replay the frozen v1 algorithm; v2 documents use
    /// the canonical-minus-digest algorithm. An unknown version is a
    /// typed rejection, never silently accepted.
    public static func verify(
        _ document: HTDTFieldReturnDocument
    ) throws -> Bool {
        let recomputed: EvidenceSHA256
        switch document.schemaVersion {
        case HTDTFieldReturnDocument.schemaVersionV1:
            recomputed = try legacyDigest(of: document)
        case HTDTFieldReturnDocument.schemaVersionValue:
            recomputed = try semanticDigest(of: document)
        default:
            throw HTDTFieldReturnError
                .incompatibleAuthoritySchema(
                    "htdt.field_return/"
                        + document.schemaVersion
                )
        }
        return recomputed == document.contentDigest
    }
}

/// The finalize/read-side contract of a field return (issue #418):
/// task outcomes must carry their required basis, every fulfillment
/// ref must be grammar-valid, type-compatible with the task kind and
/// resolvable to an exact record of this contribution (or an
/// explicitly permitted external reference), and typed-authority
/// tasks require a contribution-local typed record — a generic
/// note/file is not a substitute.
public enum HTDTFieldReturnValidator {
    /// Namespaces whose refs resolve *inside* this contribution —
    /// the validator checks exact membership against the workspace's
    /// typed records.
    private static let contributionNamespaces: Set<String> = [
        "field_evidence", "settings_observation", "wiring_route",
        "inventory_item", "room_state", "instrument", "operator",
    ]

    /// Validates one ledger entry's outcome semantics and ref
    /// compatibility (issue #418). Used by `recordTaskOutcome` for
    /// edit-time checks and again at finalize so a draft authored
    /// under an older build still fails honestly.
    public static func validate(
        workspace: HTDTFieldReturnWorkspace
    ) throws {
        for entry in workspace.taskLedger {
            try HTDTFieldReturnWorkspace.checkOutcomeSemantics(
                itemRef: entry.itemRef,
                outcome: entry.outcome,
                fulfilledByRefs: entry.fulfilledByRefs,
                note: entry.note,
                permittedNamespaces:
                    entry.permittedFulfillmentNamespaces
            )
            guard entry.outcome == .fulfilled
                    || entry.outcome == .partiallyFulfilled
            else { continue }
            for ref in entry.fulfilledByRefs {
                try validateFulfillmentRef(ref, in: workspace)
            }
            // Typed-authority tasks: at least one contribution-local
            // record of the required family must exist — a generic
            // note/file is not typed inventory/settings/wiring data.
            if entry.outcome == .fulfilled
                && entry.requiresTypedFulfillment {
                let typed = entry.fulfilledByRefs.contains { ref in
                    let ns = String(ref.prefix { $0 != ":" })
                    guard entry.typedFulfillmentNamespaces
                        .contains(ns)
                    else { return false }
                    return (try? resolves(ref, in: workspace))
                        == true
                }
                guard typed else {
                    throw HTDTFieldReturnError
                        .incompatibleFulfillmentRef(entry.itemRef)
                }
            }
        }
    }

    /// Whether `ref` names a record inside this workspace's typed
    /// authority collections (for contribution-local namespaces).
    public static func resolves(
        _ ref: String,
        in workspace: HTDTFieldReturnWorkspace
    ) throws -> Bool {
        guard let colon = ref.firstIndex(of: ":") else {
            return false
        }
        let namespace = String(ref[..<colon])
        let identifier = String(ref[ref.index(after: colon)...])
        guard let uuid = UUID(canonicalUUIDv4Text: identifier)
        else { return false }
        let authority = workspace.authority
        switch namespace {
        case "field_evidence":
            return authority.fieldEvidence.contains {
                $0.evidenceID.rawValue == uuid
            }
        case "settings_observation":
            return authority.settingsObservations.contains {
                $0.observationID.rawValue == uuid
            }
        case "wiring_route":
            return authority.wiringRoutes.contains {
                $0.routeID.rawValue == uuid
            }
        case "inventory_item":
            return workspace.inventoryItems.contains {
                $0.itemID.rawValue == uuid
            }
        case "room_state":
            return workspace.roomStateObservations.contains {
                $0.observationID.rawValue == uuid
            }
        case "instrument":
            return authority.instruments.contains {
                $0.instrumentID.rawValue == uuid
            }
        case "operator":
            return authority.operatorProfiles.contains {
                $0.operatorID.rawValue == uuid
            }
        default:
            return false
        }
    }

    /// One fulfillment ref: grammar → namespace compatibility →
    /// resolution. Contribution-local namespaces must resolve to an
    /// exact record; other namespaces are explicitly permitted
    /// external/imported references (plan equipment refs, capture
    /// entities) the contribution cannot contain.
    private static func validateFulfillmentRef(
        _ ref: String,
        in workspace: HTDTFieldReturnWorkspace
    ) throws {
        guard let colon = ref.firstIndex(of: ":") else {
            throw HTDTFieldReturnError.invalidBindingRef(ref)
        }
        let namespace = String(ref[..<colon])
        if contributionNamespaces.contains(namespace) {
            guard try resolves(ref, in: workspace) else {
                throw HTDTFieldReturnError
                    .unresolvedFulfillmentRef(ref)
            }
        }
    }

    /// Read-side validation of an opened artifact (issue #419):
    /// every embedded `authority/*.json` document is checked against
    /// the binding scope the root declares —
    ///
    /// - **v2** (`contribution_ref` scope): each document must be an
    ///   `htdt.field_return.*` envelope whose `contribution_ref`
    ///   equals the root's exactly; a record still carrying
    ///   `capture_revision_id` is a dual-owner rejection.
    /// - **v1** (`contribution_id` scope): each document must be a
    ///   published `htdt.capture.*` doc whose document-level
    ///   `capture_revision_id` equals the contribution id, and any
    ///   record-level `capture_revision_id` must equal it too —
    ///   legacy records never name a second owner.
    ///
    /// The root's own `contribution_ref` must equal its
    /// `contribution_id` (conflicting root identities reject), and a
    /// `.fieldReturn` kind is required — a Field Return never claims
    /// a capture-revision owner.
    public static func validateArtifact(
        document: HTDTFieldReturnDocument,
        entries: [HTDTFieldReturnArtifact.Entry]
    ) throws {
        guard document.contributionRef
            == .fieldReturn(document.contributionID)
        else {
            throw HTDTFieldReturnError
                .conflictingContributionRef(
                    HTDTFieldReturnDocument.path
                )
        }
        let carrier = CaptureRevisionID(
            rawValue: document.contributionID.rawValue
        )
        let carrierText = carrier.rawValue.uuidString.lowercased()
        let declaredPaths = Set(
            document.authorityDocuments.map(\.path)
        )
        for entry in entries {
            guard entry.path.hasPrefix("authority/"),
                  entry.path.hasSuffix(".json")
            else { continue }
            guard declaredPaths.contains(entry.path) else {
                throw HTDTFieldReturnError
                    .conflictingContributionRef(entry.path)
            }
            if document.isV1Layout {
                try validateLegacyDoc(
                    data: entry.data,
                    path: entry.path,
                    carrierText: carrierText
                )
            } else {
                _ = try FieldContributionDocs.parse(
                    data: entry.data,
                    path: entry.path,
                    expectedContribution:
                        document.contributionRef
                )
            }
        }
    }

    /// v1 embedded doc check: schema is a known `htdt.capture.*`
    /// family, doc-level `capture_revision_id` equals the
    /// contribution carrier, and no record-level
    /// `capture_revision_id` names a different owner.
    private static func validateLegacyDoc(
        data: Data,
        path: String,
        carrierText: String
    ) throws {
        guard let object = try JSONSerialization
            .jsonObject(with: data) as? [String: Any],
              let schema = object["schema"] as? String,
              schema.hasPrefix("htdt.capture.")
        else {
            throw HTDTFieldReturnError
                .unknownAuthoritySchema(path)
        }
        if let docCarrier = object["capture_revision_id"]
            as? String {
            guard docCarrier == carrierText else {
                throw HTDTFieldReturnError
                    .conflictingContributionRef(path)
            }
        }
        // Any record-level carrier must equal the contribution too —
        // a record naming a different owner is a conflict, never a
        // silent rebind.
        for value in object.values {
            guard let records = value as? [[String: Any]]
            else { continue }
            for record in records {
                if let recordCarrier =
                    record["capture_revision_id"] as? String,
                    recordCarrier != carrierText {
                    throw HTDTFieldReturnError
                        .conflictingContributionRef(path)
                }
            }
        }
    }
}

/// Writes the `.htdtfieldreturn` container (issue #400): a stored
/// (uncompressed) classic ZIP carrying the artifact's entries plus a
/// `container-manifest.json` integrity index — same deterministic
/// bytes strategy as `.htdtcapture`, a different container family so
/// the two never intermix on import.
public enum HTDTFieldReturnArchiveWriter {
    public static let pathExtension = "htdtfieldreturn"
    public static let containerManifestPath = "container-manifest.json"

    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let storeMethod: UInt16 = 0
    private static let version20: UInt16 = 20
    private static let fixedDOSTime: UInt16 = 0
    private static let fixedDOSDate: UInt16 = 33

    /// One stored entry's header metadata for the manifest.
    struct ContainerManifestEntry: Codable, Sendable, Equatable {
        let path: String
        let bytes: Int
        let crc32: UInt32
        let sha256: String
    }

    struct ContainerManifest: Codable, Sendable, Equatable {
        let schema = "htdt.field_return.container_manifest"
        let schemaVersion = "1.0.0"
        let entries: [ContainerManifestEntry]

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case entries
        }
    }

    /// Streams the artifact to `destination`. The archive is written
    /// to a temp sibling, then moved atomically; an existing file is
    /// never overwritten.
    public static func write(
        artifact: HTDTFieldReturnArtifact,
        to destination: URL
    ) throws {
        guard destination.pathExtension == pathExtension else {
            throw HTDTFieldReturnError.invalidContainerExtension
        }
        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            throw HTDTFieldReturnError.destinationAlreadyExists
        }
        guard artifact.entries.count <= Int(UInt16.max) else {
            throw HTDTFieldReturnError.archiveTooLargeForClassicZIP
        }

        // Manifest records every entry's integrity first; the
        // manifest itself then ships as the last entry.
        var manifestEntries: [ContainerManifestEntry] = []
        for entry in artifact.entries {
            manifestEntries.append(
                .init(
                    path: entry.path,
                    bytes: entry.data.count,
                    crc32: ZIPCRC32.data(entry.data),
                    sha256: EvidenceIntegrity.sha256(
                        of: entry.data
                    ).value
                )
            )
        }
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let manifestData = try manifestEncoder.encode(
            ContainerManifest(entries: manifestEntries)
        )

        var all = artifact.entries
        all.append(
            .init(
                path: containerManifestPath,
                data: manifestData
            )
        )

        struct StoredEntry {
            let path: String
            let data: Data
            let crc32: UInt32
            let localOffset: UInt32
        }
        var stored: [StoredEntry] = []
        var nextOffset: UInt64 = 0
        for entry in all {
            let nameBytes = Data(entry.path.utf8)
            guard nameBytes.count <= Int(UInt16.max) else {
                throw HTDTFieldReturnError.filenameTooLong(
                    entry.path
                )
            }
            guard entry.data.count <= Int(UInt32.max) else {
                throw HTDTFieldReturnError
                    .archiveTooLargeForClassicZIP
            }
            let required =
                nextOffset + UInt64(30 + nameBytes.count)
                + UInt64(entry.data.count)
            guard nextOffset <= UInt64(UInt32.max),
                  required <= UInt64(UInt32.max)
            else {
                throw HTDTFieldReturnError
                    .archiveTooLargeForClassicZIP
            }
            stored.append(
                StoredEntry(
                    path: entry.path,
                    data: entry.data,
                    crc32: ZIPCRC32.data(entry.data),
                    localOffset: UInt32(nextOffset)
                )
            )
            nextOffset = required
        }
        let centralOffset = nextOffset
        var centralSize: UInt64 = 0
        for entry in stored {
            centralSize += UInt64(
                46 + Data(entry.path.utf8).count
            )
        }
        guard centralOffset <= UInt64(UInt32.max),
              centralSize <= UInt64(UInt32.max),
              centralOffset + centralSize + 22
                <= UInt64(UInt32.max)
        else {
            throw HTDTFieldReturnError.archiveTooLargeForClassicZIP
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temp = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-"
                + UUID().uuidString.lowercased()
        )
        defer {
            if FileManager.default.fileExists(atPath: temp.path) {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        guard FileManager.default.createFile(
            atPath: temp.path,
            contents: nil
        ) else {
            throw HTDTFieldReturnError.fileOpenFailed(temp.path)
        }
        guard let output = try? FileHandle(forWritingTo: temp) else {
            throw HTDTFieldReturnError.fileOpenFailed(temp.path)
        }
        defer { try? output.close() }

        for entry in stored {
            let name = Data(entry.path.utf8)
            var header = Data()
            header.appendLE(localSignature)
            header.appendLE(version20)
            header.appendLE(utf8Flag)
            header.appendLE(storeMethod)
            header.appendLE(fixedDOSTime)
            header.appendLE(fixedDOSDate)
            header.appendLE(entry.crc32)
            header.appendLE(UInt32(entry.data.count))
            header.appendLE(UInt32(entry.data.count))
            header.appendLE(UInt16(name.count))
            header.appendLE(UInt16(0))
            header.append(name)
            try output.write(contentsOf: header)
            try output.write(contentsOf: entry.data)
        }
        for entry in stored {
            let name = Data(entry.path.utf8)
            var central = Data()
            central.appendLE(centralSignature)
            central.appendLE(version20)
            central.appendLE(version20)
            central.appendLE(utf8Flag)
            central.appendLE(storeMethod)
            central.appendLE(fixedDOSTime)
            central.appendLE(fixedDOSDate)
            central.appendLE(entry.crc32)
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(entry.localOffset)
            central.append(name)
            try output.write(contentsOf: central)
        }
        var end = Data()
        end.appendLE(endSignature)
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(stored.count))
        end.appendLE(UInt16(stored.count))
        end.appendLE(UInt32(centralSize))
        end.appendLE(UInt32(centralOffset))
        end.appendLE(UInt16(0))
        try output.write(contentsOf: end)
        try output.synchronize()

        do {
            try FileManager.default.moveItem(
                at: temp,
                to: destination
            )
        } catch {
            throw HTDTFieldReturnError.atomicPublishFailed
        }
    }
}

/// Reads a `.htdtfieldreturn` container (issue #400): stored-entry
/// extraction plus manifest verification — a corrupt archive reports
/// the mismatching path, never half-decodes.
public enum HTDTFieldReturnArchiveReader {
    public enum ReadError: Error, Sendable, Equatable {
        case invalidContainer(String)
        case manifestMismatch(String)
        case manifestMissing
    }

    /// Extracts and verifies the artifact: every entry's CRC and
    /// sha256 checked against the container manifest, and the
    /// manifest itself re-verified against the entry set.
    public static func read(
        archive: URL
    ) throws -> HTDTFieldReturnArtifact {
        guard archive.pathExtension
            == HTDTFieldReturnArchiveWriter.pathExtension
        else {
            throw ReadError.invalidContainer(
                archive.pathExtension
            )
        }
        let data = try Data(contentsOf: archive)
        let entries = try StoredZIPReader.entries(in: data)
        var byPath: [String: Data] = [:]
        for entry in entries {
            byPath[entry.path] = entry.data
        }
        guard let manifestData =
            byPath[HTDTFieldReturnArchiveWriter
                .containerManifestPath]
        else {
            throw ReadError.manifestMissing
        }
        let manifest = try JSONDecoder().decode(
            HTDTFieldReturnArchiveWriter.ContainerManifest.self,
            from: manifestData
        )
        var expected = Set(byPath.keys)
        expected.remove(
            HTDTFieldReturnArchiveWriter.containerManifestPath
        )
        var declared = Set<String>()
        for record in manifest.entries {
            declared.insert(record.path)
            guard let payload = byPath[record.path] else {
                throw ReadError.manifestMismatch(record.path)
            }
            guard record.bytes == payload.count,
                  EvidenceIntegrity.sha256(of: payload).value
                    == record.sha256
            else {
                throw ReadError.manifestMismatch(record.path)
            }
        }
        guard declared == expected else {
            throw ReadError.manifestMismatch("entry_set")
        }
        guard let docData =
            byPath[HTDTFieldReturnDocument.path]
        else {
            throw ReadError.manifestMismatch(
                HTDTFieldReturnDocument.path
            )
        }
        let document = try JSONDecoder().decode(
            HTDTFieldReturnDocument.self,
            from: docData
        )
        let artifactEntries =
            entries.filter {
                $0.path != HTDTFieldReturnArchiveWriter
                    .containerManifestPath
            }
            .map {
                HTDTFieldReturnArtifact.Entry(
                    path: $0.path,
                    data: $0.data
                )
            }
            .sorted { $0.path < $1.path }
        // Contribution-binding validation (issue #419): embedded
        // authority docs must agree with the root's declared binding
        // scope — v1 `capture_revision_id` carriers and v2
        // `contribution_ref` envelopes are each checked on their own
        // terms; mismatches are typed rejections, never repaired.
        try HTDTFieldReturnValidator.validateArtifact(
            document: document,
            entries: artifactEntries
        )
        return HTDTFieldReturnArtifact(
            document: document,
            entries: artifactEntries
        )
    }
}

/// Minimal stored-ZIP reader shared by the field-return container —
/// stored entries only, no compression, no data descriptors (the
/// writer never emits them). Internal scope; not a general ZIP
/// implementation.
struct StoredZIPReader {
    struct Entry {
        let path: String
        let data: Data
    }

    static func entries(in data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        var offset = 0
        let bytes = [UInt8](data)
        func readU16(_ at: Int) throws -> UInt16 {
            guard at + 2 <= bytes.count else {
                throw HTDTFieldReturnArchiveReader.ReadError
                    .invalidContainer("truncated_header")
            }
            return UInt16(bytes[at])
                | UInt16(bytes[at + 1]) << 8
        }
        func readU32(_ at: Int) throws -> UInt32 {
            guard at + 4 <= bytes.count else {
                throw HTDTFieldReturnArchiveReader.ReadError
                    .invalidContainer("truncated_header")
            }
            return UInt32(bytes[at])
                | UInt32(bytes[at + 1]) << 8
                | UInt32(bytes[at + 2]) << 16
                | UInt32(bytes[at + 3]) << 24
        }
        while offset + 4 <= bytes.count {
            let signature = try readU32(offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else {
                throw HTDTFieldReturnArchiveReader.ReadError
                    .invalidContainer("bad_local_signature")
            }
            let method = try readU16(offset + 8)
            guard method == 0 else {
                throw HTDTFieldReturnArchiveReader.ReadError
                    .invalidContainer("compressed_entry")
            }
            let size = Int(try readU32(offset + 18))
            let nameLen = Int(try readU16(offset + 26))
            let extraLen = Int(try readU16(offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLen + extraLen
            guard dataStart + size <= bytes.count else {
                throw HTDTFieldReturnArchiveReader.ReadError
                    .invalidContainer("truncated_entry")
            }
            let name = String(
                decoding: bytes[nameStart ..< nameStart + nameLen],
                as: UTF8.self
            )
            entries.append(
                Entry(
                    path: name,
                    data: Data(
                        bytes[dataStart ..< dataStart + size]
                    )
                )
            )
            offset = dataStart + size
        }
        return entries
    }
}

/// The field-return index (issue #400): app-private JSON at
/// `<captureRoot>/field-returns.json` holding the staged workspaces
/// and finalized digests. Same shape as `mission-inbox.json` — one
/// bounded document, atomic rewrite.
public struct HTDTFieldReturnStore: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.field-returns-index"
        public static let schemaVersion = "1.0.0"

        public var schema: String
        public var schemaVersion: String
        public var workspaces: [HTDTFieldReturnWorkspace]

        public init(
            workspaces: [HTDTFieldReturnWorkspace] = []
        ) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.workspaces = workspaces
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case workspaces
        }
    }

    public let captureRoot: URL

    public var fileURL: URL {
        captureRoot.appendingPathComponent(
            "field-returns.json",
            isDirectory: false
        )
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
                Document.self, from: data
              )
        else {
            return Document()
        }
        return document
    }

    public func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(
            at: temporary,
            to: fileURL
        )
    }
}

extension HTDTMissionRecord {
    /// Aggregate contribution set for fulfillment evaluation (issue
    /// #400/#397): every associated capture revision plus every
    /// attached field return.
    public var contributions: [HTDTMissionContribution] {
        associatedCaptureRevisionIDs.compactMap { idText in
            guard let uuid = UUID(uuidString: idText) else {
                return nil
            }
            return .captureRevision(
                CaptureRevisionID(rawValue: uuid)
            )
        }
            + fieldReturnIDs.compactMap { idText in
                guard let uuid = UUID(uuidString: idText) else {
                    return nil
                }
                return .fieldReturn(
                    HTDTFieldReturnID(rawValue: uuid)
                )
            }
    }
}
