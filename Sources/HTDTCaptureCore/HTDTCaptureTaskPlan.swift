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

/// A versioned HTDT capture task plan (issue #240): project/document
/// reference, room name, required/optional entity checklist, expected
/// channel roles, equipment catalog snapshot, requested measurements
/// with endpoint semantics, evidence targets, and surface/opening
/// review tasks. The plan is an operator workflow request and is
/// persisted verbatim as imported reference — it is never capture
/// truth and never pre-populates the working set.
public struct HTDTCaptureTaskPlan: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture-task-plan"
    public static let schemaVersion = "1.0.0"

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
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil
    ) throws {
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
        let normalizedEvidenceTargets = SchemaOwnedText.nfc(
            evidenceTargets
        )
        guard normalizedEvidenceTargets
            .allSatisfy({ !$0.isEmpty })
        else {
            throw CaptureTaskPlanError.emptyField
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.planID = normalizedID
        self.planVersion = normalizedVersion
        self.projectRef = normalizedProject
        self.roomName = normalizedRoom
        self.issuedAtUTC = issuedAtUTC
        self.entityChecklist = entityChecklist
        self.measurementRequests = measurementRequests
        self.surfaceReviewTasks = surfaceReviewTasks
        self.evidenceTargets = normalizedEvidenceTargets
        self.expectedChannelRoles = expectedChannelRoles
        self.equipmentCatalog = equipmentCatalog
    }

    public var allItemIDs: [String] {
        entityChecklist.map(\.itemID)
            + measurementRequests.map(\.itemID)
            + surfaceReviewTasks.map(\.itemID)
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
            )
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

        public init(
            itemID: String,
            outcome: TaskPlanItemOutcome,
            fulfillment: TaskFulfillmentLink? = nil
        ) {
            self.itemID = itemID
            self.outcome = outcome
            self.fulfillment = fulfillment
        }

        private enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case outcome
            case fulfillment
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
                )
            )
        }
    }

    public static let schema = "htdt.capture-task-plan-status"
    /// The payload version this build emits (#332): v1.1.0 adds the
    /// typed `fulfillment` link per item (#354).
    public static let schemaVersion = "1.1.0"
    /// Every payload version this build can decode (#332): v1.0.0
    /// documents carry outcomes without fulfillment links.
    public static let supportedSchemaVersions: [String] = [
        "1.0.0", "1.1.0",
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

    public init(planImport: CaptureTaskPlanImport) {
        self.planImport = planImport
        self.explicitMarks = [:]
        self.bindings = [:]
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
    }

    /// Operator marks an item skipped or unavailable. `pending` clears
    /// the mark. `completed` cannot be asserted ahead of evidence for
    /// entity/measurement items; surface review items are operator-
    /// assessed and may be marked completed directly.
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
    public func itemOutcomes(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
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

    /// Builds the persisted status document for the working set.
    public func statusDocument(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) throws -> CaptureTaskPlanStatusDocument {
        try CaptureTaskPlanStatusDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            planID: planImport.plan.planID,
            planVersion: planImport.plan.planVersion,
            planSHA256: planImport.planSHA256,
            items: itemOutcomes(
                annotations: annotations,
                measurements: measurements
            )
        )
    }

    /// Encoded status package for the supplemental-document store path.
    public func statusPackage(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) throws -> Data {
        let document = try statusDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            annotations: annotations,
            measurements: measurements
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
