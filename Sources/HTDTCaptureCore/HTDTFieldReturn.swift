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
    public let enabled: Bool
    /// Human-readable reason when `enabled == false`; nil otherwise.
    public let disabledReason: String?

    public init(
        itemRef: String,
        title: String,
        requirement: TaskPlanRequirement,
        spatialRequirement: HTDTTaskSpatialRequirement,
        enabled: Bool,
        disabledReason: String? = nil
    ) {
        self.itemRef = itemRef
        self.title = title
        self.requirement = requirement
        self.spatialRequirement = spatialRequirement
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
            spatial: HTDTTaskSpatialRequirement
        ) -> HTDTFieldTaskPreflight {
            let enabled =
                spatialAvailable || spatial == .nonSpatial
            return HTDTFieldTaskPreflight(
                itemRef: "task_item:" + itemID,
                title: title,
                requirement: requirement,
                spatialRequirement: spatial,
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
                    spatial: .spatial
                )
            )
        }
        for item in plan.measurementRequests {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.quantityType,
                    requirement: item.requirement,
                    spatial: .spatial
                )
            )
        }
        for item in plan.surfaceReviewTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.surfaceKind,
                    requirement: item.requirement,
                    spatial: .spatial
                )
            )
        }
        for item in plan.semanticTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.label ?? item.semanticKind.rawValue,
                    requirement: item.requirement,
                    spatial: item.semanticKind.spatialRequirement
                )
            )
        }
        for item in plan.evidenceTasks {
            rows.append(
                row(
                    itemID: item.itemID,
                    title: item.purpose,
                    requirement: item.requirement,
                    spatial: .nonSpatial
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
    public var outcome: Outcome
    /// Authority refs fulfilling the item —
    /// `field_evidence:`/`settings_observation:`/`wiring_route:`/
    /// `inventory_item:`/`entity:`/`measurement:` tokens.
    public var fulfilledByRefs: [String]
    /// Optional operator note (e.g. why declined).
    public var note: String?

    public init(
        itemRef: String,
        title: String,
        requirement: TaskPlanRequirement,
        outcome: Outcome,
        fulfilledByRefs: [String] = [],
        note: String? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case itemRef = "item_ref"
        case title
        case requirement
        case outcome
        case fulfilledByRefs = "fulfilled_by_refs"
        case note
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
/// #400): the versioned `htdt.field_return` contract. Embedded typed
/// authority documents reuse the capture bundle's field-authority
/// models; their `capture_revision_id` slot carries this
/// contribution's id — `authority_binding_scope` states that
/// explicitly so no reader mistakes it for a capture revision.
public struct HTDTFieldReturnDocument:
    Codable, Sendable, Equatable
{
    public static let schemaName = "htdt.field_return"
    public static let schemaVersionValue = "1.0.0"
    public static let path = "field-return.json"
    /// Value of `authority_binding_scope` — documents inside this
    /// container bind the contribution id in their
    /// `capture_revision_id` slots.
    public static let bindingScope = "contribution_id"

    public let schema: String
    public let schemaVersion: String
    /// States how embedded typed docs are bound — always
    /// `contribution_id` for this artifact.
    public let authorityBindingScope: String
    public let contributionID: HTDTFieldReturnID
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
    /// Semantic hash over the canonical artifact content — identity,
    /// ledger, document refs and asset digests — excluding this
    /// field itself.
    public let contentDigest: EvidenceSHA256

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
    public var authority: FieldAuthorityWorkspace
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
        self.authority = FieldAuthorityWorkspace()
        self.taskLedger = taskLedger
        self.createdAtUTC = createdAtUTC
        self.finalizedAtUTC = nil
        self.finalizedDigest = nil
    }

    public var isFinalized: Bool { finalizedAtUTC != nil }

    /// The capture-revision-typed identifier embedded authority docs
    /// bind — the contribution id occupies the `capture_revision_id`
    /// slot for typed-model reuse (see
    /// `HTDTFieldReturnDocument.authority_binding_scope`).
    public var bindingRevisionID: CaptureRevisionID {
        CaptureRevisionID(rawValue: contributionID.rawValue)
    }

    /// Seeds the task ledger from a preflighted plan — one row per
    /// plan item, `unfulfilled`/`notApplicable` defaulting by whether
    /// the item is enabled on this device.
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
                    ? .unfulfilled : .notApplicable
            )
        }
    }

    /// Records a task outcome plus the authority refs that fulfill it.
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
        for ref in fulfilledByRefs {
            guard FieldAuthorityGrammar.isBindingRef(ref) else {
                throw HTDTFieldReturnError.invalidBindingRef(ref)
            }
        }
        taskLedger[index].outcome = outcome
        taskLedger[index].fulfilledByRefs = fulfilledByRefs
        taskLedger[index].note = SchemaOwnedText.nfc(note)
    }
}

/// Builds the immutable `.htdtfieldreturn` artifact (issue #400) from
/// a finalized workspace: typed authority docs under `authority/`,
/// staged evidence assets under `evidence/`, the root
/// `field-return.json`, then the container manifest. The builder
/// performs every validation the typed documents enforce — records
/// bound to another contribution id are rejected, not rebound.
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
        let binding = workspace.bindingRevisionID
        var entries: [HTDTFieldReturnArtifact.Entry] = []
        var documentRefs: [HTDTFieldReturnDocumentRef] = []
        var assetRefs: [HTDTFieldReturnDocumentRef] = []

        func addDocument(
            name: String,
            schema: String,
            data: Data
        ) throws {
            let path = authorityPathPrefix + name
            entries.append(.init(path: path, data: data))
            documentRefs.append(
                .init(
                    path: path,
                    schema: schema,
                    sha256: EvidenceIntegrity.sha256(of: data),
                    bytes: data.count
                )
            )
        }

        let authority = workspace.authority
        // Operator/instrument profiles carry no per-record
        // revision binding — document-level `capture_revision_id`
        // covers them.
        if !authority.operatorProfiles.isEmpty {
            let doc = try OperatorProfileDocument(
                captureRevisionID: binding,
                operators: authority.operatorProfiles
            )
            try addDocument(
                name: "operator-profiles.json",
                schema: OperatorProfileDocument.schema,
                data: try FieldAuthorityCoding.encoder().encode(doc)
            )
        }
        if !authority.instruments.isEmpty {
            let doc = try InstrumentProfileDocument(
                captureRevisionID: binding,
                instruments: authority.instruments
            )
            try addDocument(
                name: "instrument-profiles.json",
                schema: InstrumentProfileDocument.schema,
                data: try FieldAuthorityCoding.encoder().encode(doc)
            )
        }
        if !authority.fieldEvidence.isEmpty {
            for record in authority.fieldEvidence {
                try requireBinding(
                    record.captureRevisionID,
                    binding: binding,
                    ref: "field_evidence:\(record.evidenceID)"
                )
            }
            let doc = try FieldEvidenceDocument(
                captureRevisionID: binding,
                records: authority.fieldEvidence
            )
            try addDocument(
                name: "field-evidence.json",
                schema: FieldEvidenceDocument.schema,
                data: try FieldAuthorityCoding.encoder().encode(doc)
            )
        }
        if !authority.settingsObservations.isEmpty {
            for observation in authority.settingsObservations {
                try requireBinding(
                    observation.captureRevisionID,
                    binding: binding,
                    ref: "settings_observation:"
                        + observation.observationID.description
                )
            }
            let doc = try InstalledSettingsDocument(
                captureRevisionID: binding,
                observations: authority.settingsObservations
            )
            try addDocument(
                name: "settings-observations.json",
                schema: InstalledSettingsDocument.schema,
                data: try FieldAuthorityCoding.encoder().encode(doc)
            )
        }
        if !authority.wiringRoutes.isEmpty {
            for route in authority.wiringRoutes {
                try requireBinding(
                    route.captureRevisionID,
                    binding: binding,
                    ref: "wiring_route:\(route.routeID)"
                )
            }
            let doc = try AsBuiltWiringDocument(
                captureRevisionID: binding,
                routes: authority.wiringRoutes
            )
            try addDocument(
                name: "wiring-routes.json",
                schema: AsBuiltWiringDocument.schema,
                data: try FieldAuthorityCoding.encoder().encode(doc)
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

        // Semantic hash over the artifact's canonical content — the
        // identity fields, ledger, and per-entry digests — independent
        // of ZIP container details.
        var hasher = SHA256()
        func hashLine(_ line: String) {
            hasher.update(data: Data(line.utf8))
            hasher.update(data: Data([0x0A]))
        }
        hashLine(HTDTFieldReturnDocument.schemaName)
        hashLine(HTDTFieldReturnDocument.schemaVersionValue)
        hashLine(workspace.contributionID.description)
        hashLine(workspace.missionID ?? "")
        hashLine(workspace.planID ?? "")
        hashLine(workspace.createdAtUTC)
        hashLine(finalizedAtUTC)
        for entry in workspace.taskLedger {
            hashLine(
                entry.itemRef + "|" + entry.outcome.rawValue
                    + "|" + entry.fulfilledByRefs.joined(
                        separator: ","
                    )
            )
        }
        for ref in documentRefs + assetRefs {
            hashLine(ref.path + "|" + ref.sha256.value)
        }
        let digestHex = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
        let contentDigest = try EvidenceSHA256(digestHex)

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
        binding: CaptureRevisionID,
        ref: String
    ) throws {
        guard recordRevision == binding else {
            throw HTDTFieldReturnError.authorityBindingMismatch(ref)
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
