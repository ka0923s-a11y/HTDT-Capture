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
    /// Catalog `strategy_id` the plan recommends (or pins) for this
    /// capture (#307). Absent for plans that leave strategy to the
    /// operator. Unknown identifiers are rejected at decode.
    public let recommendedCaptureStrategy: String?
    /// When true, `recommendedCaptureStrategy` is a plan pin: the app
    /// applies it as binding. When false it is a recommendation the
    /// operator may override.
    public let captureStrategyPinned: Bool

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
        captureStrategyPinned: Bool = false
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
        case recommendedCaptureStrategy = "recommended_capture_strategy"
        case captureStrategyPinned = "capture_strategy_pinned"
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
            ),
            recommendedCaptureStrategy: container.decodeIfPresent(
                String.self,
                forKey: .recommendedCaptureStrategy
            ),
            captureStrategyPinned: container.decodeIfPresent(
                Bool.self,
                forKey: .captureStrategyPinned
            ) ?? false
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

        public init(itemID: String, outcome: TaskPlanItemOutcome) {
            self.itemID = itemID
            self.outcome = outcome
        }

        private enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case outcome
        }
    }

    public static let schema = "htdt.capture-task-plan-status"
    public static let schemaVersion = "1.0.0"
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
              schemaVersion == Self.schemaVersion
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

    public init(planImport: CaptureTaskPlanImport) {
        self.planImport = planImport
        self.explicitMarks = [:]
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
    /// capture truth. Auto-computed completion wins over explicit
    /// marks — committed evidence is the authority.
    public func itemOutcomes(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) -> [CaptureTaskPlanStatusDocument.ItemOutcome] {
        var outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome] = []
        for item in planImport.plan.entityChecklist {
            let satisfied = annotations.contains { entity in
                entity.type == item.entityType
                    && (item.channelRole == nil
                        || entity.channelRole == item.channelRole)
                    && (item.labelHint == nil
                        || entity.label == item.labelHint)
            }
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: satisfied
                        ? .completed
                        : explicitMarks[item.itemID] ?? .pending
                )
            )
        }
        for item in planImport.plan.measurementRequests {
            let satisfied = measurements.contains { measurement in
                measurement.quantityType == item.quantityType
                    && (item.expectedUnit == nil
                        || measurement.unit == item.expectedUnit)
            }
            outcomes.append(
                .init(
                    itemID: item.itemID,
                    outcome: satisfied
                        ? .completed
                        : explicitMarks[item.itemID] ?? .pending
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
