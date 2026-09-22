import Foundation

public enum TaskPlanRequirement: String, Codable, Sendable, Equatable {
    case required
    case optional
}

/// Operator-visible lifecycle of one plan checklist item (issue #240).
/// `completed` is reached by committing matching evidence or by an
/// explicit operator mark; `skipped`/`unavailable` are explicit marks.
public enum TaskPlanItemOutcome: String, Codable, Sendable, Equatable {
    case pending
    case completed
    case skipped
    case unavailable
}

public enum CaptureTaskPlanError: Error, Sendable, Equatable {
    case emptyField
    case invalidTimestamp
    case duplicateItemID
    case unknownItemID
    case unsupportedSchema
    case encodedDocumentMismatch
    /// A fulfillment binding names a record of the wrong kind for
    /// this plan item (#354).
    case fulfillmentKindMismatch
    /// A fulfillment binding does not name a canonical record id
    /// (#354).
    case invalidFulfillmentLink
    /// A fulfillment binding does not match the item's declared kind,
    /// subtype, or target — or points at a record/evidence ref that
    /// does not exist, or shares one record across tasks without an
    /// explicit `allow_shared_fulfillment` on both items.
    case fulfillmentMismatch
}

/// The record kind a plan item's fulfillment link may name (#354).
public enum TaskFulfillmentRecordKind: String, Codable, Sendable,
    Equatable
{
    case entity
    case measurement
}

/// Exact identity of the committed record fulfilling a plan item
/// (#354). Fulfillment is a typed link — never inferred from generic
/// type/unit equality on the persisted status document.
public struct TaskFulfillmentLink: Codable, Sendable, Equatable {
    public let recordKind: TaskFulfillmentRecordKind
    /// Canonical UUIDv4 text of the entity or measurement record.
    public let recordID: String

    public init(
        recordKind: TaskFulfillmentRecordKind,
        recordID: String
    ) throws {
        guard UUID(canonicalUUIDv4Text: recordID) != nil else {
            throw CaptureTaskPlanError.invalidFulfillmentLink
        }
        self.recordKind = recordKind
        self.recordID = recordID
    }

    private enum CodingKeys: String, CodingKey {
        case recordKind = "record_kind"
        case recordID = "record_id"
    }
}

/// One entity the plan asks the operator to place (issue #240). The
/// plan is a workflow request only — it never pre-populates capture
/// truth.
public struct HTDTTaskPlanEntityItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let entityType: AnnotationEntityType
    public let requirement: TaskPlanRequirement
    public let channelRole: ChannelRole?
    public let labelHint: String?
    public let equipmentRef: HTDTEquipmentReference?

    public init(
        itemID: String,
        entityType: AnnotationEntityType,
        requirement: TaskPlanRequirement,
        channelRole: ChannelRole? = nil,
        labelHint: String? = nil,
        equipmentRef: HTDTEquipmentReference? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(itemID)
        guard !normalizedID.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        self.itemID = normalizedID
        self.entityType = entityType
        self.requirement = requirement
        self.channelRole = channelRole
        self.labelHint = SchemaOwnedText.nfc(labelHint)
        self.equipmentRef = equipmentRef
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case entityType = "entity_type"
        case requirement
        case channelRole = "channel_role"
        case labelHint = "label_hint"
        case equipmentRef = "equipment_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(String.self, forKey: .itemID),
            entityType: container.decode(
                AnnotationEntityType.self,
                forKey: .entityType
            ),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            channelRole: container.decodeIfPresent(
                ChannelRole.self,
                forKey: .channelRole
            ),
            labelHint: container.decodeIfPresent(
                String.self,
                forKey: .labelHint
            ),
            equipmentRef: container.decodeIfPresent(
                HTDTEquipmentReference.self,
                forKey: .equipmentRef
            )
        )
    }
}

/// One measurement the plan requests, with the endpoint semantics the
/// plan intends ("wall_width", "floor_to_ceiling", ...).
public struct HTDTTaskPlanMeasurementItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let quantityType: String
    public let requirement: TaskPlanRequirement
    public let endpointSemantics: String?
    public let expectedUnit: MeasurementUnit?

    public init(
        itemID: String,
        quantityType: String,
        requirement: TaskPlanRequirement,
        endpointSemantics: String? = nil,
        expectedUnit: MeasurementUnit? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(itemID)
        let normalizedType = SchemaOwnedText.nfc(quantityType)
        guard !normalizedID.isEmpty, !normalizedType.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        self.itemID = normalizedID
        self.quantityType = normalizedType
        self.requirement = requirement
        self.endpointSemantics = SchemaOwnedText.nfc(endpointSemantics)
        self.expectedUnit = expectedUnit
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case quantityType = "quantity_type"
        case requirement
        case endpointSemantics = "endpoint_semantics"
        case expectedUnit = "expected_unit"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(String.self, forKey: .itemID),
            quantityType: container.decode(
                String.self,
                forKey: .quantityType
            ),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            endpointSemantics: container.decodeIfPresent(
                String.self,
                forKey: .endpointSemantics
            ),
            expectedUnit: container.decodeIfPresent(
                MeasurementUnit.self,
                forKey: .expectedUnit
            )
        )
    }
}

/// A surface/opening review task the plan asks the operator to perform
/// during Review (e.g. "confirm window opening on north wall").
public struct HTDTTaskPlanSurfaceItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let surfaceKind: String
    public let note: String?
    public let requirement: TaskPlanRequirement

    public init(
        itemID: String,
        surfaceKind: String,
        note: String? = nil,
        requirement: TaskPlanRequirement
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(itemID)
        let normalizedKind = SchemaOwnedText.nfc(surfaceKind)
        guard !normalizedID.isEmpty, !normalizedKind.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        self.itemID = normalizedID
        self.surfaceKind = normalizedKind
        self.note = SchemaOwnedText.nfc(note)
        self.requirement = requirement
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case surfaceKind = "surface_kind"
        case note
        case requirement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(String.self, forKey: .itemID),
            surfaceKind: container.decode(
                String.self,
                forKey: .surfaceKind
            ),
            note: container.decodeIfPresent(
                String.self,
                forKey: .note
            ),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            )
        )
    }
}

/// A theater-semantic authority task the plan requests (#359). The
/// item names an exact record kind — never a free-form string — so a
/// single vague record cannot silently satisfy unrelated tasks. The
/// operator fulfills it by binding an exact authority record via
/// `CaptureTaskPlanStatus.fulfill`.
public struct HTDTTaskPlanSemanticItem: Codable, Sendable, Equatable,
    Identifiable
{
    public let itemID: String
    public var id: String { itemID }
    public let requirement: TaskPlanRequirement
    /// The authority record kind that satisfies this item.
    public let semanticKind: SemanticTaskKind
    /// Exact subtype token within the kind the fulfilling record must
    /// carry — e.g. an inventory `equipment_class` value, a room-state
    /// `kind`, a mounting mode. nil accepts any subtype.
    public let expectedSubtype: String?
    /// Exact entity identity (`AnnotationEntityID` text) the
    /// fulfilling record must describe, when the plan targets one.
    public let targetRef: String?
    /// Operator-facing label for the requested work.
    public let label: String?
    /// Plan-side reference the record answers to (e.g. a planned
    /// entity id or spec ref), when the plan declares one.
    public let plannedRef: String?
    /// Whether this item permits one record to also satisfy other
    /// items. Sharing is only allowed when both items opt in.
    public let allowSharedFulfillment: Bool

    public init(
        itemID: String,
        requirement: TaskPlanRequirement,
        semanticKind: SemanticTaskKind,
        expectedSubtype: String? = nil,
        targetRef: String? = nil,
        label: String? = nil,
        plannedRef: String? = nil,
        allowSharedFulfillment: Bool = false
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(itemID)
        guard !normalizedID.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        for value in [
            SchemaOwnedText.nfc(expectedSubtype),
            SchemaOwnedText.nfc(targetRef),
            SchemaOwnedText.nfc(label),
            SchemaOwnedText.nfc(plannedRef),
        ] {
            if let value, value.isEmpty {
                throw CaptureTaskPlanError.emptyField
            }
        }
        self.itemID = normalizedID
        self.requirement = requirement
        self.semanticKind = semanticKind
        self.expectedSubtype = SchemaOwnedText.nfc(expectedSubtype)
        self.targetRef = SchemaOwnedText.nfc(targetRef)
        self.label = SchemaOwnedText.nfc(label)
        self.plannedRef = SchemaOwnedText.nfc(plannedRef)
        self.allowSharedFulfillment = allowSharedFulfillment
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case requirement
        case semanticKind = "semantic_kind"
        case expectedSubtype = "expected_subtype"
        case targetRef = "target_ref"
        case label
        case plannedRef = "planned_ref"
        case allowSharedFulfillment = "allow_shared_fulfillment"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(String.self, forKey: .itemID),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            semanticKind: container.decode(
                SemanticTaskKind.self,
                forKey: .semanticKind
            ),
            expectedSubtype: container.decodeIfPresent(
                String.self,
                forKey: .expectedSubtype
            ),
            targetRef: container.decodeIfPresent(
                String.self,
                forKey: .targetRef
            ),
            label: container.decodeIfPresent(
                String.self,
                forKey: .label
            ),
            plannedRef: container.decodeIfPresent(
                String.self,
                forKey: .plannedRef
            ),
            allowSharedFulfillment: container.decodeIfPresent(
                Bool.self,
                forKey: .allowSharedFulfillment
            ) ?? false
        )
    }
}

/// A first-class evidence target the plan requests (#359): a stable
/// item id plus the evidence purpose, so the fulfilled answer is an
/// exact committed evidence ref — never a loose string match.
public struct HTDTTaskPlanEvidenceItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let requirement: TaskPlanRequirement
    /// What the evidence is for — e.g. "equipment_label_photo",
    /// "avr_rack_wiring". A typed purpose token, not a capture value.
    public let purpose: String
    /// Entity/record the evidence must relate to, when the plan names
    /// one (entity id text or authority record id text).
    public let subjectRef: String?
    /// Free-text capture guidance for the operator.
    public let guidance: String?

    public init(
        itemID: String,
        requirement: TaskPlanRequirement,
        purpose: String,
        subjectRef: String? = nil,
        guidance: String? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(itemID)
        let normalizedPurpose = SchemaOwnedText.nfc(purpose)
        guard !normalizedID.isEmpty, !normalizedPurpose.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        for value in [
            SchemaOwnedText.nfc(subjectRef),
            SchemaOwnedText.nfc(guidance),
        ] {
            if let value, value.isEmpty {
                throw CaptureTaskPlanError.emptyField
            }
        }
        self.itemID = normalizedID
        self.requirement = requirement
        self.purpose = normalizedPurpose
        self.subjectRef = SchemaOwnedText.nfc(subjectRef)
        self.guidance = SchemaOwnedText.nfc(guidance)
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case requirement
        case purpose
        case subjectRef = "subject_ref"
        case guidance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(String.self, forKey: .itemID),
            requirement: container.decode(
                TaskPlanRequirement.self,
                forKey: .requirement
            ),
            purpose: container.decode(
                String.self,
                forKey: .purpose
            ),
            subjectRef: container.decodeIfPresent(
                String.self,
                forKey: .subjectRef
            ),
            guidance: container.decodeIfPresent(
                String.self,
                forKey: .guidance
            )
        )
    }
}

/// The exact payload a semantic or evidence task is fulfilled with
/// (#359): an authority record id for semantic tasks, a committed
/// evidence ref for evidence tasks. Encoded tagged so a status
/// document round-trips without ambiguity.
public enum TaskPlanFulfillment: Codable, Sendable, Equatable {
    case authorityRecord(AuthorityRecordID)
    case evidenceRef(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case ref
    }

    private enum Kind: String, Codable {
        case authorityRecord = "authority_record"
        case evidenceRef = "evidence_ref"
    }

    /// Canonical string form persisted on item outcomes — the exact
    /// fulfilling record/evidence identity.
    public var refText: String {
        switch self {
        case let .authorityRecord(id):
            return id.description
        case let .evidenceRef(ref):
            return ref
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .authorityRecord:
            self = .authorityRecord(
                try container.decode(AuthorityRecordID.self, forKey: .ref)
            )
        case .evidenceRef:
            self = .evidenceRef(
                try container.decode(String.self, forKey: .ref)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .authorityRecord(id):
            try container.encode(Kind.authorityRecord, forKey: .kind)
            try container.encode(id, forKey: .ref)
        case let .evidenceRef(ref):
            try container.encode(Kind.evidenceRef, forKey: .kind)
            try container.encode(ref, forKey: .ref)
        }
    }
}

/// A versioned HTDT capture task plan (issue #240): project/document
/// reference, room name, required/optional entity checklist, expected
/// channel roles, equipment catalog snapshot, requested measurements
/// with endpoint semantics, evidence targets, surface/opening review
/// tasks, and — from schema 2.0.0 (#359) — first-class theater-semantic
/// authority tasks and stable-id evidence tasks. The plan is an
/// operator workflow request and is persisted verbatim as imported
/// reference — it is never capture truth and never pre-populates the
/// working set.
public struct HTDTCaptureTaskPlan: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture-task-plan"
    /// Every plan version this build can import. v1 files decode with
    /// the new task arrays empty — their meaning is unchanged (#359).
    public static let supportedSchemaVersions = ["1.0.0", "2.0.0"]
    /// The version emitted when a plan is authored in-process.
    public static let schemaVersion = "2.0.0"

    public let schema: String
    public let schemaVersion: String
    public let planID: String
    public let planVersion: String
    public let projectRef: String
    public let roomName: String
    public let issuedAtUTC: String?
    public let entityChecklist: [HTDTTaskPlanEntityItem]
    public let measurementRequests: [HTDTTaskPlanMeasurementItem]
    public let surfaceReviewTasks: [HTDTTaskPlanSurfaceItem]
    /// Evidence items the plan requests (frame shots, target captures).
    public let evidenceTargets: [String]
    /// Channel roles the room is expected to host.
    public let expectedChannelRoles: [ChannelRole]
    /// Equipment catalog snapshot/reference supplied with the plan.
    public let equipmentCatalog: HTDTEquipmentCatalogSnapshot?
    /// Catalog `strategy_id` the plan recommends (or pins) for this
    /// capture (#307). Absent for plans that leave strategy to the
    /// operator. Unknown identifiers are rejected at decode.
    public let recommendedCaptureStrategy: String?
    /// When true, `recommendedCaptureStrategy` is a plan pin: the app
    /// applies it as binding. When false it is a recommendation the
    /// operator may override.
    public let captureStrategyPinned: Bool
    /// Optional exact layout profile the plan supplies (#315): the
    /// versioned role vocabulary bindings resolve against and the
    /// completeness requirements evaluate from. Nil plans keep the
    /// legacy `expected_channel_roles` behavior.
    public let layoutProfile: SpeakerLayoutProfile?
    /// Theater-semantic authority tasks the plan requests (#359).
    public let semanticTasks: [HTDTTaskPlanSemanticItem]
    /// Stable-id evidence tasks the plan requests (#359).
    public let evidenceTasks: [HTDTTaskPlanEvidenceItem]

    public init(
        planID: String,
        planVersion: String,
        projectRef: String,
        roomName: String,
        issuedAtUTC: String? = nil,
        entityChecklist: [HTDTTaskPlanEntityItem] = [],
        measurementRequests: [HTDTTaskPlanMeasurementItem] = [],
        surfaceReviewTasks: [HTDTTaskPlanSurfaceItem] = [],
        evidenceTargets: [String] = [],
        expectedChannelRoles: [ChannelRole] = [],
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        recommendedCaptureStrategy: String? = nil,
        captureStrategyPinned: Bool = false,
        layoutProfile: SpeakerLayoutProfile? = nil,
        semanticTasks: [HTDTTaskPlanSemanticItem] = [],
        evidenceTasks: [HTDTTaskPlanEvidenceItem] = [],
        schemaVersion: String = HTDTCaptureTaskPlan.schemaVersion
    ) throws {
        guard Self.supportedSchemaVersions.contains(schemaVersion)
        else {
            throw CaptureTaskPlanError.unsupportedSchema
        }
        let normalizedID = SchemaOwnedText.nfc(planID)
        let normalizedVersion = SchemaOwnedText.nfc(planVersion)
        let normalizedProject = SchemaOwnedText.nfc(projectRef)
        let normalizedRoom = SchemaOwnedText.nfc(roomName)
        guard !normalizedID.isEmpty,
              !normalizedVersion.isEmpty,
              !normalizedProject.isEmpty,
              !normalizedRoom.isEmpty
        else {
            throw CaptureTaskPlanError.emptyField
        }
        if let issuedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(issuedAtUTC)
            else {
                throw CaptureTaskPlanError.invalidTimestamp
            }
        }
        var seen = Set<String>()
        for item in entityChecklist {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
        }
        for item in measurementRequests {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
        }
        for item in surfaceReviewTasks {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
        }
        for item in semanticTasks {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
        }
        for item in evidenceTasks {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
        }
        let normalizedEvidenceTargets = SchemaOwnedText.nfc(
            evidenceTargets
        )
        guard normalizedEvidenceTargets
            .allSatisfy({ !$0.isEmpty })
        else {
            throw CaptureTaskPlanError.emptyField
        }
        self.schema = Self.schema
        self.schemaVersion = schemaVersion
        self.planID = normalizedID
        self.planVersion = normalizedVersion
        self.projectRef = normalizedProject
        self.roomName = normalizedRoom
        self.issuedAtUTC = issuedAtUTC
        self.entityChecklist = entityChecklist
        self.measurementRequests = measurementRequests
        self.surfaceReviewTasks = surfaceReviewTasks
        let normalizedStrategy = SchemaOwnedText.nfc(
            recommendedCaptureStrategy
        )
        if let normalizedStrategy {
            guard !normalizedStrategy.isEmpty,
                  CaptureStrategyIdentifier(
                      rawValue: normalizedStrategy
                  ) != nil
            else {
                throw CaptureTaskPlanError.emptyField
            }
        }
        self.evidenceTargets = normalizedEvidenceTargets
        self.expectedChannelRoles = expectedChannelRoles
        self.equipmentCatalog = equipmentCatalog
        self.recommendedCaptureStrategy = normalizedStrategy
        // A pin without a recommended strategy is meaningless — only
        // honor the flag when a strategy is present.
        self.captureStrategyPinned = captureStrategyPinned
            && normalizedStrategy != nil
        self.layoutProfile = layoutProfile
        self.semanticTasks = semanticTasks
        self.evidenceTasks = evidenceTasks
    }

    public var allItemIDs: [String] {
        entityChecklist.map(\.itemID)
            + measurementRequests.map(\.itemID)
            + surfaceReviewTasks.map(\.itemID)
            + semanticTasks.map(\.itemID)
            + evidenceTasks.map(\.itemID)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case projectRef = "project_ref"
        case roomName = "room_name"
        case issuedAtUTC = "issued_at"
        case entityChecklist = "entity_checklist"
        case measurementRequests = "measurement_requests"
        case surfaceReviewTasks = "surface_review_tasks"
        case evidenceTargets = "evidence_targets"
        case expectedChannelRoles = "expected_channel_roles"
        case equipmentCatalog = "equipment_catalog"
        case recommendedCaptureStrategy = "recommended_capture_strategy"
        case captureStrategyPinned = "capture_strategy_pinned"
        case layoutProfile = "layout_profile"
        case semanticTasks = "semantic_tasks"
        case evidenceTasks = "evidence_tasks"
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
              Self.supportedSchemaVersions.contains(schemaVersion)
        else {
            throw CaptureTaskPlanError.unsupportedSchema
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
            roomName: container.decode(
                String.self,
                forKey: .roomName
            ),
            issuedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .issuedAtUTC
            ),
            entityChecklist: container.decode(
                [HTDTTaskPlanEntityItem].self,
                forKey: .entityChecklist
            ),
            measurementRequests: container.decode(
                [HTDTTaskPlanMeasurementItem].self,
                forKey: .measurementRequests
            ),
            surfaceReviewTasks: container.decode(
                [HTDTTaskPlanSurfaceItem].self,
                forKey: .surfaceReviewTasks
            ),
            evidenceTargets: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceTargets
            ) ?? [],
            expectedChannelRoles: container.decodeIfPresent(
                [ChannelRole].self,
                forKey: .expectedChannelRoles
            ) ?? [],
            equipmentCatalog: container.decodeIfPresent(
                HTDTEquipmentCatalogSnapshot.self,
                forKey: .equipmentCatalog
            ),
            recommendedCaptureStrategy: container.decodeIfPresent(
                String.self,
                forKey: .recommendedCaptureStrategy
            ),
            captureStrategyPinned: container.decodeIfPresent(
                Bool.self,
                forKey: .captureStrategyPinned
            ) ?? false,
            layoutProfile: container.decodeIfPresent(
                SpeakerLayoutProfile.self,
                forKey: .layoutProfile
            ),
            semanticTasks: container.decodeIfPresent(
                [HTDTTaskPlanSemanticItem].self,
                forKey: .semanticTasks
            ) ?? [],
            evidenceTasks: container.decodeIfPresent(
                [HTDTTaskPlanEvidenceItem].self,
                forKey: .evidenceTasks
            ) ?? [],
            schemaVersion: schemaVersion
        )
    }
}

/// Result of comparing an imported plan's pinned equipment catalog
/// against the catalog currently adopted on this device (#302).
///
/// A plan that carries an `equipment_catalog` snapshot demands that
/// exact catalog — matched by semantic content digest, never by label.
/// A mismatched or absent active catalog is reported so the operator
/// can switch deliberately instead of unknowingly selecting
/// definitions from a stale or unrelated last-used catalog.
public enum EquipmentCatalogRequirement: Sendable, Equatable {
    /// The plan does not pin a catalog; any selection context is fine.
    case notRequired
    /// The active catalog's content digest equals the pinned digest.
    case satisfied
    /// The plan pins a catalog but none is adopted on this device.
    case missingCatalog(pinnedSHA256: EvidenceSHA256)
    /// The plan pins a catalog whose content digest differs from the
    /// adopted catalog's — an explicit switch/import is required.
    case mismatchedCatalog(
        pinnedSHA256: EvidenceSHA256,
        activeSHA256: EvidenceSHA256
    )

    /// Whether selections made under the current catalog satisfy the
    /// plan's pin. `satisfied`/`notRequired` are fine; the other cases
    /// must be visibly surfaced.
    public var isSatisfied: Bool {
        switch self {
        case .notRequired, .satisfied:
            return true
        case .missingCatalog, .mismatchedCatalog:
            return false
        }
    }

    public static func check(
        plan: HTDTCaptureTaskPlan?,
        activeCatalog: HTDTEquipmentCatalogSnapshot?
    ) -> EquipmentCatalogRequirement {
        guard let pinned = plan?.equipmentCatalog else {
            return .notRequired
        }
        let pinnedDigest = pinned.contentSHA256
        guard let activeCatalog else {
            return .missingCatalog(pinnedSHA256: pinnedDigest)
        }
        return activeCatalog.contentSHA256 == pinnedDigest
            ? .satisfied
            : .mismatchedCatalog(
                pinnedSHA256: pinnedDigest,
                activeSHA256: activeCatalog.contentSHA256
            )
    }
}

/// The plan payload persisted verbatim under
/// `session/capture-task-plan.json` as imported reference (issue #240).
public struct CaptureTaskPlanImport: Sendable, Equatable {
    public static let path = "session/capture-task-plan.json"

    public let plan: HTDTCaptureTaskPlan
    /// Exact bytes as imported — persisted verbatim so the plan
    /// identity hash covers what HTDT sent.
    public let data: Data
    public let planSHA256: EvidenceSHA256

    public init(data: Data) throws {
        let plan = try JSONDecoder().decode(
            HTDTCaptureTaskPlan.self,
            from: data
        )
        self.plan = plan
        self.data = data
        self.planSHA256 = EvidenceIntegrity.sha256(of: data)
    }
}

/// Persisted per-item outcomes at `session/task-plan-status.json`
/// (issue #240): the operator-visible state of the checklist before
/// finalization.
public struct CaptureTaskPlanStatusDocument: Codable, Sendable,
    Equatable
{
    public struct ItemOutcome: Codable, Sendable, Equatable {
        public let itemID: String
        public let outcome: TaskPlanItemOutcome
        /// The exact fulfilling record for `completed` items (#354).
        /// Nil means completion was operator-asserted (surface review
        /// items) or the outcome is not completed.
        public let fulfillment: TaskFulfillmentLink?
        /// Exact fulfilling record/evidence identity (#359): the
        /// authority record id for semantic tasks, the committed
        /// evidence ref for evidence tasks. nil for the other item
        /// kinds, which resolve against committed capture truth.
        public let fulfillmentRef: String?

        public init(
            itemID: String,
            outcome: TaskPlanItemOutcome,
            fulfillment: TaskFulfillmentLink? = nil,
            fulfillmentRef: String? = nil
        ) {
            self.itemID = itemID
            self.outcome = outcome
            self.fulfillment = fulfillment
            self.fulfillmentRef = fulfillmentRef
        }

        private enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case outcome
            case fulfillment
            case fulfillmentRef = "fulfillment_ref"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            try self.init(
                itemID: container.decode(
                    String.self,
                    forKey: .itemID
                ),
                outcome: container.decode(
                    TaskPlanItemOutcome.self,
                    forKey: .outcome
                ),
                fulfillment: container.decodeIfPresent(
                    TaskFulfillmentLink.self,
                    forKey: .fulfillment
                ),
                fulfillmentRef: container.decodeIfPresent(
                    String.self,
                    forKey: .fulfillmentRef
                )
            )
        }
    }

    public static let schema = "htdt.capture-task-plan-status"
    /// The payload version this build emits: v1.1.0 adds the typed
    /// `fulfillment` link (#354); v2.0.0 adds `fulfillment_ref` (#359).
    public static let schemaVersion = "2.0.0"
    /// Every payload version this build can decode: v1.0.0 documents
    /// carry outcomes without fulfillment fields, v1.1.0 adds the
    /// typed link, v2.0.0 adds the identity string.
    public static let supportedSchemaVersions: [String] = [
        "1.0.0", "1.1.0", "2.0.0",
    ]
    public static let path = "session/task-plan-status.json"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let planID: String
    public let planVersion: String
    public let planSHA256: EvidenceSHA256
    public let items: [ItemOutcome]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        planID: String,
        planVersion: String,
        planSHA256: EvidenceSHA256,
        items: [ItemOutcome]
    ) throws {
        guard !items.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        var seen = Set<String>()
        for item in items {
            guard seen.insert(item.itemID).inserted else {
                throw CaptureTaskPlanError.duplicateItemID
            }
            // A fulfillment link only accompanies a completed
            // outcome — it never decorates a pending/skipped item
            // (#354).
            guard item.outcome == .completed
                    || item.fulfillment == nil
            else {
                throw CaptureTaskPlanError.invalidFulfillmentLink
            }
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.planID = planID
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case planSHA256 = "plan_sha256"
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              Self.supportedSchemaVersions.contains(schemaVersion)
        else {
            throw CaptureTaskPlanError.unsupportedSchema
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
            planID: container.decode(String.self, forKey: .planID),
            planVersion: container.decode(
                String.self,
                forKey: .planVersion
            ),
            planSHA256: container.decode(
                EvidenceSHA256.self,
                forKey: .planSHA256
            ),
            items: container.decode(
                [ItemOutcome].self,
                forKey: .items
            )
        )
    }
}

/// Live tracker for an imported plan (issue #240). Item completion is
/// computed against committed annotations/measurements — the plan
/// never writes capture truth — while skipped/unavailable are explicit
/// operator marks.
public struct CaptureTaskPlanStatus: Sendable, Equatable {
    public let planImport: CaptureTaskPlanImport
    private var explicitMarks: [String: TaskPlanItemOutcome]
    /// Explicit fulfillment bindings (#354): operator-confirmed links
    /// from a plan item to the exact committed record that satisfies
    /// it. A binding never makes an item complete on its own — the
    /// bound record must still exist and still satisfy the item's
    /// declared constraints at outcome-evaluation time.
    private var bindings: [String: TaskFulfillmentLink]
    /// Exact fulfillment bindings for semantic/evidence tasks (#359).
    public private(set) var fulfillments: [String: TaskPlanFulfillment]

    public init(planImport: CaptureTaskPlanImport) {
        self.planImport = planImport
        self.explicitMarks = [:]
        self.bindings = [:]
        self.fulfillments = [:]
    }

    /// Bind a plan item to the exact entity record fulfilling it
    /// (#354). Used to disambiguate when several entities match the
    /// item's declared constraints, or when the plan pins a specific
    /// target.
    public mutating func bind(
        itemID: String,
        toEntity entityID: AnnotationEntityID
    ) throws {
        guard planImport.plan.entityChecklist
            .contains(where: { $0.itemID == itemID })
        else {
            throw planImport.plan.allItemIDs.contains(itemID)
                ? CaptureTaskPlanError.fulfillmentKindMismatch
                : CaptureTaskPlanError.unknownItemID
        }
        bindings[itemID] = try TaskFulfillmentLink(
            recordKind: .entity,
            recordID: entityID.description
        )
    }

    /// Bind a plan item to the exact measurement record fulfilling it
    /// (#354).
    public mutating func bind(
        itemID: String,
        toMeasurement measurementID: MeasurementID
    ) throws {
        guard planImport.plan.measurementRequests
            .contains(where: { $0.itemID == itemID })
        else {
            throw planImport.plan.allItemIDs.contains(itemID)
                ? CaptureTaskPlanError.fulfillmentKindMismatch
                : CaptureTaskPlanError.unknownItemID
        }
        bindings[itemID] = try TaskFulfillmentLink(
            recordKind: .measurement,
            recordID: measurementID.description
        )
    }

    /// Clear an explicit fulfillment binding (#354).
    public mutating func unbind(itemID: String) throws {
        guard planImport.plan.allItemIDs.contains(itemID) else {
            throw CaptureTaskPlanError.unknownItemID
        }
        bindings.removeValue(forKey: itemID)
        self.fulfillments = [:]
    }

    /// Rebuilds fulfillment bindings from a persisted status document
    /// — `fulfillment_ref` on each item is the durable copy of the
    /// in-memory binding (#359).
    public mutating func restoreFulfillments(
        from document: CaptureTaskPlanStatusDocument
    ) {
        let semanticIDs = Set(planImport.plan.semanticTasks.map(\.itemID))
        let evidenceIDs = Set(planImport.plan.evidenceTasks.map(\.itemID))
        for item in document.items {
            guard let ref = item.fulfillmentRef else { continue }
            if semanticIDs.contains(item.itemID),
               let id = AuthorityRecordID(canonicalString: ref)
            {
                fulfillments[item.itemID] = .authorityRecord(id)
            } else if evidenceIDs.contains(item.itemID) {
                fulfillments[item.itemID] = .evidenceRef(ref)
            }
        }
    }

    /// Operator marks an item skipped or unavailable. `pending` clears
    /// the mark. `completed` cannot be asserted ahead of evidence for
    /// entity/measurement items and never applies to semantic/evidence
    /// tasks — those complete only through an exact fulfillment
    /// binding; surface review items are operator-assessed and may be
    /// marked completed directly.
    public mutating func mark(
        itemID: String,
        as outcome: TaskPlanItemOutcome
    ) throws {
        guard planImport.plan.allItemIDs.contains(itemID) else {
            throw CaptureTaskPlanError.unknownItemID
        }
        let isSurfaceItem = planImport.plan.surfaceReviewTasks
            .contains { $0.itemID == itemID }
        if outcome == .completed, !isSurfaceItem {
            throw CaptureTaskPlanError.unknownItemID
        }
        if outcome == .pending {
            explicitMarks.removeValue(forKey: itemID)
        } else {
            explicitMarks[itemID] = outcome
        }
    }

    /// Binds an exact authority record to a semantic task (#359).
    /// Fails closed: the record must exist in `authorities`, carry the
    /// item's `semantic_kind`, match `expected_subtype`/`target_ref`
    /// when declared, and — unless both items opt into
    /// `allow_shared_fulfillment` — must not already fulfill another
    /// task.
    public mutating func fulfill(
        itemID: String,
        with recordID: AuthorityRecordID,
        in authorities: TheaterAuthorityCollection
    ) throws {
        guard let item = planImport.plan.semanticTasks
            .first(where: { $0.itemID == itemID })
        else {
            guard planImport.plan.allItemIDs.contains(itemID) else {
                throw CaptureTaskPlanError.unknownItemID
            }
            throw CaptureTaskPlanError.fulfillmentKindMismatch
        }
        guard let descriptor = authorities.recordDescriptors
            .first(where: { $0.recordID == recordID }),
            descriptor.kind == item.semanticKind
        else {
            throw CaptureTaskPlanError.fulfillmentMismatch
        }
        if let expected = item.expectedSubtype,
           descriptor.subtype != expected
        {
            throw CaptureTaskPlanError.fulfillmentMismatch
        }
        if let target = item.targetRef {
            let matches = descriptor.targetEntityID?.description == target
                || descriptor.targetPlannedRef == target
            guard matches else {
                throw CaptureTaskPlanError.fulfillmentMismatch
            }
        }
        for (otherID, fulfillment) in fulfillments
        where otherID != itemID {
            guard case let .authorityRecord(otherRecord) = fulfillment,
                  otherRecord == recordID
            else { continue }
            let otherAllows = planImport.plan.semanticTasks
                .first(where: { $0.itemID == otherID })?
                .allowSharedFulfillment ?? false
            guard item.allowSharedFulfillment, otherAllows else {
                throw CaptureTaskPlanError.fulfillmentMismatch
            }
        }
        fulfillments[itemID] = .authorityRecord(recordID)
    }

    /// Binds an exact committed evidence ref to an evidence task
    /// (#359). The ref must already exist among the session's
    /// committed evidence — the plan cannot conjure it.
    public mutating func fulfillEvidence(
        itemID: String,
        evidenceRef: String,
        in committedEvidenceRefs: [String]
    ) throws {
        guard let item = planImport.plan.evidenceTasks
            .first(where: { $0.itemID == itemID })
        else {
            guard planImport.plan.allItemIDs.contains(itemID) else {
                throw CaptureTaskPlanError.unknownItemID
            }
            throw CaptureTaskPlanError.fulfillmentKindMismatch
        }
        _ = item
        let normalized = SchemaOwnedText.nfc(evidenceRef)
        guard !normalized.isEmpty else {
            throw CaptureTaskPlanError.emptyField
        }
        guard committedEvidenceRefs.contains(normalized) else {
            throw CaptureTaskPlanError.fulfillmentMismatch
        }
        fulfillments[itemID] = .evidenceRef(normalized)
    }

    /// Drops a fulfillment binding so the item returns to pending.
    public mutating func clearFulfillment(itemID: String) throws {
        guard planImport.plan.allItemIDs.contains(itemID) else {
            throw CaptureTaskPlanError.unknownItemID
        }
        fulfillments.removeValue(forKey: itemID)
    }

    private func semanticOutcome(
        item: HTDTTaskPlanSemanticItem,
        authorities: TheaterAuthorityCollection
    ) -> (TaskPlanItemOutcome, String?) {
        guard case let .authorityRecord(recordID) =
            fulfillments[item.itemID]
        else {
            return (explicitMarks[item.itemID] ?? .pending, nil)
        }
        // The bound record must still exist and still match the item —
        // a deleted record cannot satisfy the task.
        guard let descriptor = authorities.recordDescriptors
            .first(where: { $0.recordID == recordID }),
            descriptor.kind == item.semanticKind
        else {
            return (explicitMarks[item.itemID] ?? .pending, nil)
        }
        if let expected = item.expectedSubtype,
           descriptor.subtype != expected
        {
            return (explicitMarks[item.itemID] ?? .pending, nil)
        }
        if let target = item.targetRef,
           descriptor.targetEntityID?.description != target,
           descriptor.targetPlannedRef != target
        {
            return (explicitMarks[item.itemID] ?? .pending, nil)
        }
        return (.completed, recordID.description)
    }

    private func evidenceOutcome(
        item: HTDTTaskPlanEvidenceItem,
        committedEvidenceRefs: [String]
    ) -> (TaskPlanItemOutcome, String?) {
        guard case let .evidenceRef(ref) = fulfillments[item.itemID],
              committedEvidenceRefs.contains(ref)
        else {
            return (explicitMarks[item.itemID] ?? .pending, nil)
        }
        return (.completed, ref)
    }

    /// Resolves every checklist item's outcome against committed
    /// capture truth (#354). Completion is typed fulfillment, not
    /// generic type/unit equality:
    ///
    ///   * an explicit `bind` link wins — the bound record must still
    ///     exist and still satisfy the item's declared constraints
    ///     (type + channel_role + label_hint + equipment_ref tuple, or
    ///     quantity_type + expected_unit); a replaced or deleted
    ///     fulfillment record never silently leaves the item
    ///     completed.
    ///   * a measurement carrying `lineage.task_ref` naming the item
    ///     fulfills it directly — the stronger typed contract
    ///     `endpoint_semantics` demands.
    ///   * generic declarative matching only completes an item when
    ///     exactly one candidate satisfies the item AND that record
    ///     satisfies no other item — a single record can never
    ///     accidentally satisfy two distinct requested tasks.
    ///
    /// Superseded or rejected measurements never fulfill a plan.
    /// Auto-computed completion wins over explicit marks — committed
    /// evidence is the authority. The evaluation is deterministic,
    /// so a persisted status document replays exactly from plan +
    /// records + fulfillment links.
    /// capture truth. Auto-computed completion wins over explicit
    /// marks — committed evidence is the authority. Semantic tasks
    /// complete only via an exact record fulfillment that still matches
    /// the live collection; evidence tasks only via a committed ref.
    public func itemOutcomes(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        authorities: TheaterAuthorityCollection = .empty,
        committedEvidenceRefs: [String] = []
    ) -> [CaptureTaskPlanStatusDocument.ItemOutcome] {
        var outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome] = []

        for item in planImport.plan.entityChecklist {
            let candidates = annotations.filter { entity in
                entity.type == item.entityType
                    && (item.channelRole == nil
                        || entity.channelRole == item.channelRole)
                    && (item.labelHint == nil
                        || entity.label == item.labelHint)
                    && (item.equipmentRef == nil
                        || entity.equipmentRef == item.equipmentRef)
            }
            let link = resolveEntityBinding(
                itemID: item.itemID,
                candidates: candidates
            )
            let mark = explicitMarks[item.itemID] ?? .pending
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: link != nil ? .completed : mark,
                    fulfillment: link
                )
            )
        }

        // Measurement fulfillment needs global uniqueness context: a
        // record matching two requested items satisfies neither
        // automatically.
        let eligible = measurements.filter {
            $0.lineage?.disposition != .superseded
                && $0.lineage?.disposition != .rejectedWithReason
        }
        var itemsMatchingRecord: [MeasurementID: [String]] = [:]
        var candidatesByItem: [String: [CaptureMeasurement]] = [:]
        for item in planImport.plan.measurementRequests {
            let candidates = eligible.filter { measurement in
                measurement.quantityType == item.quantityType
                    && (item.expectedUnit == nil
                        || measurement.unit == item.expectedUnit)
            }
            candidatesByItem[item.itemID] = candidates
            for measurement in candidates {
                itemsMatchingRecord[
                    measurement.measurementID,
                    default: []
                ].append(item.itemID)
            }
        }

        for item in planImport.plan.measurementRequests {
            let candidates = candidatesByItem[item.itemID] ?? []
            // Typed task binding (#354): a measurement declaring
            // lineage.task_ref -> this item fulfills it. Required
            // when the item declares endpoint semantics — generic
            // equality never satisfies a typed-endpoint request.
            let taskBound = candidates.filter {
                $0.lineage?.taskRef?.itemID == item.itemID
                    && $0.lineage?.taskRef?.planID
                        == planImport.plan.planID
            }
            let mark = explicitMarks[item.itemID] ?? .pending
            let link: TaskFulfillmentLink?
            if let binding = bindings[item.itemID] {
                link = resolveMeasurementBinding(
                    binding,
                    candidates: candidates
                )
            } else if let taskHit = taskBound.first,
                      taskBound.count == 1
            {
                link = try? TaskFulfillmentLink(
                    recordKind: .measurement,
                    recordID: taskHit.measurementID.description
                )
            } else if item.endpointSemantics == nil,
                      candidates.count == 1,
                      let candidate = candidates.first,
                      itemsMatchingRecord[candidate.measurementID]?
                        .count == 1
            {
                link = try? TaskFulfillmentLink(
                    recordKind: .measurement,
                    recordID: candidate.measurementID.description
                )
            } else {
                link = nil
            }
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: link != nil ? .completed : mark,
                    fulfillment: link
                )
            )
        }
        for item in planImport.plan.surfaceReviewTasks {
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: explicitMarks[item.itemID] ?? .pending
                )
            )
        }
        for item in planImport.plan.semanticTasks {
            let (outcome, ref) = semanticOutcome(
                item: item,
                authorities: authorities
            )
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: outcome,
                    fulfillmentRef: ref
                )
            )
        }
        for item in planImport.plan.evidenceTasks {
            let (outcome, ref) = evidenceOutcome(
                item: item,
                committedEvidenceRefs: committedEvidenceRefs
            )
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: outcome,
                    fulfillmentRef: ref
                )
            )
        }
        return outcomes
    }

    /// Resolve an explicit entity binding: the bound record must
    /// still exist and still satisfy every declared constraint —
    /// otherwise the item falls back to its unresolved outcome
    /// (#354).
    private func resolveEntityBinding(
        itemID: String,
        candidates: [CaptureAnnotationEntity]
    ) -> TaskFulfillmentLink? {
        if let binding = bindings[itemID] {
            return candidates.contains(where: {
                $0.entityID.description == binding.recordID
            }) ? binding : nil
        }
        // Unique-candidate auto-binding: unambiguous typed match.
        guard candidates.count == 1, let candidate = candidates.first
        else {
            return nil
        }
        return try? TaskFulfillmentLink(
            recordKind: .entity,
            recordID: candidate.entityID.description
        )
    }

    /// Resolve an explicit measurement binding — the record must
    /// still exist and satisfy the item's constraints.
    private func resolveMeasurementBinding(
        _ binding: TaskFulfillmentLink,
        candidates: [CaptureMeasurement]
    ) -> TaskFulfillmentLink? {
        candidates.contains(where: {
            $0.measurementID.description == binding.recordID
        }) ? binding : nil
    }

    /// Whether every required plan item resolved to `completed` —
    /// mission completeness, deliberately separate from technical
    /// ingestion/bundle readiness (#359). Optional items may stay
    /// pending or be skipped without blocking.
    public func requiredMissionComplete(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        authorities: TheaterAuthorityCollection = .empty,
        committedEvidenceRefs: [String] = []
    ) -> Bool {
        let outcomesByID = Dictionary(
            itemOutcomes(
                annotations: annotations,
                measurements: measurements,
                authorities: authorities,
                committedEvidenceRefs: committedEvidenceRefs
            ).map { ($0.itemID, $0.outcome) },
            uniquingKeysWith: { first, _ in first }
        )
        var requiredIDs: [String] = []
        requiredIDs += planImport.plan.entityChecklist
            .filter { $0.requirement == .required }.map(\.itemID)
        requiredIDs += planImport.plan.measurementRequests
            .filter { $0.requirement == .required }.map(\.itemID)
        requiredIDs += planImport.plan.surfaceReviewTasks
            .filter { $0.requirement == .required }.map(\.itemID)
        requiredIDs += planImport.plan.semanticTasks
            .filter { $0.requirement == .required }.map(\.itemID)
        requiredIDs += planImport.plan.evidenceTasks
            .filter { $0.requirement == .required }.map(\.itemID)
        return requiredIDs.allSatisfy {
            outcomesByID[$0] == .completed
        }
    }

    /// Builds the persisted status document for the working set.
    public func statusDocument(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        authorities: TheaterAuthorityCollection = .empty,
        committedEvidenceRefs: [String] = []
    ) throws -> CaptureTaskPlanStatusDocument {
        try CaptureTaskPlanStatusDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            planID: planImport.plan.planID,
            planVersion: planImport.plan.planVersion,
            planSHA256: planImport.planSHA256,
            items: itemOutcomes(
                annotations: annotations,
                measurements: measurements,
                authorities: authorities,
                committedEvidenceRefs: committedEvidenceRefs
            )
        )
    }

    /// Encoded status package for the supplemental-document store path.
    public func statusPackage(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        authorities: TheaterAuthorityCollection = .empty,
        committedEvidenceRefs: [String] = []
    ) throws -> Data {
        let document = try statusDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            annotations: annotations,
            measurements: measurements,
            authorities: authorities,
            committedEvidenceRefs: committedEvidenceRefs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                CaptureTaskPlanStatusDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw CaptureTaskPlanError.encodedDocumentMismatch
        }
        return data
    }
}
