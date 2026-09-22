import Foundation
import Testing
@testable import HTDTCaptureCore

// Contract tests for the v1.1.0 contract/semantics work:
// #303 entity lineage, #304 measurement lineage/disposition,
// #332 payload-version policy, #333 relation graph,
// #334 value domains + structured uncertainty, #344 open-token
// namespaces, #354 task-plan fulfillment integrity, #356 as-built
// deviation/uncertainty verdicts.

private func makePlacement() throws -> PlacementProvenance {
    try PlacementProvenance(method: .manualNumeric)
}

private func makeSpeaker(
    label: String = "Left",
    channelRole: ChannelRole? = .left,
    lineage: AnnotationEntityLineage? = nil
) throws -> CaptureAnnotationEntity {
    try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: label,
        placement: makePlacement(),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: channelRole,
        evidenceRefs: ["frame:one"],
        lineage: lineage
    )
}

private func makeMeasurement(
    quantityType: String = "room_width",
    value: MeasurementValue = .scalar(3.0),
    lineage: MeasurementLineage? = nil,
    uncertainty: MeasurementUncertainty? = nil
) throws -> CaptureMeasurement {
    try CaptureMeasurement(
        quantityType: quantityType,
        value: value,
        unit: .meter,
        acquisitionMethod: .tapeMeasure,
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement,
        uncertainty: uncertainty,
        lineage: lineage
    )
}

// MARK: - #303 entity lineage

@Test
func entityLineageLinksToParentRevision() throws {
    let parentID = AnnotationEntityID()
    let parentRevision = CaptureRevisionID()
    let lineage = try AnnotationEntityLineage(
        stableEntityID: "physical-speaker-01",
        relation: .samePhysicalEntity,
        parentEntityRef: EntityLineageReference(
            captureRevisionID: parentRevision,
            entityID: parentID
        )
    )
    let entity = try makeSpeaker(lineage: lineage)
    #expect(entity.lineage?.stableEntityID == "physical-speaker-01")
    #expect(entity.lineage?.parentEntityRef?.entityID == parentID)
    #expect(
        entity.lineage?.parentEntityRef?.captureRevisionID
            == parentRevision
    )
}

@Test
func lineageRelationParentRequirement() throws {
    // same_physical_entity / replaced_entity require a parent ref.
    #expect(throws: AnnotationModelError.invalidEntityLineage) {
        try AnnotationEntityLineage(relation: .samePhysicalEntity)
    }
    #expect(throws: AnnotationModelError.invalidEntityLineage) {
        try AnnotationEntityLineage(relation: .replacedEntity)
    }
    // new_entity / relation_unknown forbid one.
    let ref = EntityLineageReference(
        captureRevisionID: CaptureRevisionID(),
        entityID: AnnotationEntityID()
    )
    #expect(throws: AnnotationModelError.invalidEntityLineage) {
        try AnnotationEntityLineage(
            relation: .newEntity,
            parentEntityRef: ref
        )
    }
    _ = try AnnotationEntityLineage(relation: .relationUnknown)
}

@Test
func replacedEntityCarriesDistinctStableIdentity() throws {
    // An equipment replacement is a *different* physical object:
    // replacedEntity records must not silently preserve the parent's
    // stable identity. Nothing blocks them sharing a stable id, but
    // the model forces the caller to declare the relation + parent.
    let ref = EntityLineageReference(
        captureRevisionID: CaptureRevisionID(),
        entityID: AnnotationEntityID()
    )
    let replaced = try AnnotationEntityLineage(
        stableEntityID: "physical-speaker-02",
        relation: .replacedEntity,
        parentEntityRef: ref
    )
    #expect(replaced.relation == .replacedEntity)
    #expect(replaced.stableEntityID == "physical-speaker-02")
}

@Test
func legacyEntitiesPayloadDecodesWithLineageUnknown() throws {
    let entity = try makeSpeaker()
    let collection = try CaptureAnnotationCollection(
        entities: [entity],
        relations: [],
        declaredSchemaVersion: "1.0.0"
    )
    #expect(collection.entities.first?.lineage == nil)
    #expect(collection.schemaVersion == "1.0.0")
}

// MARK: - #304 measurement lineage

@Test
func measurementLineageDistinguishesRepeatFromRetake() throws {
    let parent = try makeMeasurement()
    let independent = try makeMeasurement(
        value: .scalar(3.01),
        lineage: MeasurementLineage(
            relation: .independentRepeat,
            disposition: .retainedRepeat
        )
    )
    let retake = try makeMeasurement(
        value: .scalar(3.02),
        lineage: MeasurementLineage(
            relation: .retakeOf,
            parentMeasurementRef: MeasurementLineageReference(
                measurementID: parent.measurementID
            ),
            disposition: .active
        )
    )
    #expect(independent.lineage?.relation == .independentRepeat)
    #expect(retake.lineage?.parentMeasurementRef?.measurementID
        == parent.measurementID)
}

@Test
func measurementLineageParentRules() throws {
    #expect(throws: MeasurementModelError.invalidMeasurementLineage) {
        try MeasurementLineage(relation: .retakeOf)
    }
    #expect(throws: MeasurementModelError.invalidMeasurementLineage) {
        try MeasurementLineage(
            relation: nil,
            parentMeasurementRef: MeasurementLineageReference(
                measurementID: MeasurementID()
            )
        )
    }
    // rejected_with_reason requires a reason; active forbids one.
    #expect(throws: MeasurementModelError.invalidMeasurementLineage) {
        try MeasurementLineage(disposition: .rejectedWithReason)
    }
    #expect(throws: MeasurementModelError.invalidMeasurementLineage) {
        try MeasurementLineage(
            disposition: .active,
            dispositionReason: "bad aim"
        )
    }
    let rejected = try MeasurementLineage(
        disposition: .rejectedWithReason,
        dispositionReason: "obstructed tape path"
    )
    #expect(rejected.dispositionReason == "obstructed tape path")
}

@Test
func legacyMeasurementsDecodeWithoutLineage() throws {
    let collection = try CaptureMeasurementCollection(
        measurements: [makeMeasurement()],
        declaredSchemaVersion: "1.0.0"
    )
    #expect(collection.measurements.first?.lineage == nil)
    #expect(collection.measurements.first?.uncertainty == nil)
}

// MARK: - #332 payload-version policy

@Test
func supportMatrixDecodesEmbeddedDocument() throws {
    let matrix = CaptureBundleSchemaRegistry.supportMatrix
    #expect(matrix.schema == "htdt.capture.bundle-support-matrix")
    #expect(matrix.families["entities"]?.emitted == "1.1.0")
    #expect(matrix.families["entities"]?.read == ["1.0.0", "1.1.0"])
    #expect(matrix.isExternalAuthorityPath(
        "roomplan/captured-room.json"
    ))
    #expect(!matrix.isExternalAuthorityPath("docs/notes.json"))
}

@Test
func versionCompatibilityMapping() throws {
    let matrix = CaptureBundleSchemaRegistry.supportMatrix
    #expect(
        matrix.compatibility(family: "entities", version: "1.1.0")
            == .native
    )
    #expect(
        matrix.compatibility(family: "entities", version: "1.0.0")
            == .supportedReadOnly
    )
    #expect(
        matrix.compatibility(family: "entities", version: "9.9.9")
            == .unsupportedNewer
    )
    #expect(
        matrix.compatibility(family: "entities", version: "0.1.0")
            == .unsupportedLegacy
    )
    #expect(
        matrix.compatibility(family: "roomplan", version: nil)
            == .external
    )
}

@Test
func unknownPayloadVersionGetsExplicitDiagnostic() throws {
    let payload = Data(
        """
        {"entities":[],"schema":"htdt.capture.entities","schema_version":"9.9.9"}
        """.utf8
    )
    #expect(
        throws: BundleDirectoryValidationError.self
    ) {
        _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
            path: "annotations/entities.json",
            data: payload
        )
    }
}

@Test
func entitiesPayloadVersionsDispatchToMatchingSchema() throws {
    // A v1.0.0 entities payload validates against the 1.0.0 document.
    let legacy = Data(
        """
        {"entities":[],"schema":"htdt.capture.entities","schema_version":"1.0.0"}
        """.utf8
    )
    _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
        path: "annotations/entities.json",
        data: legacy
    )
    // v1.1.0 validates and requires `relations` to be an array.
    let current = Data(
        """
        {"entities":[],"relations":[],"schema":"htdt.capture.entities","schema_version":"1.1.0"}
        """.utf8
    )
    _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
        path: "annotations/entities.json",
        data: current
    )
    // A payload declaring 1.1.0 but carrying a 1.0.0-forbidden field
    // shape fails under the 1.1.0 document.
    let bad = Data(
        """
        {"entities":[],"relations":"nope","schema":"htdt.capture.entities","schema_version":"1.1.0"}
        """.utf8
    )
    #expect(throws: BundleDirectoryValidationError.self) {
        _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
            path: "annotations/entities.json",
            data: bad
        )
    }
}

// MARK: - #333 typed relation graph

@Test
func relationGraphRejectsDuplicatesSelfLinksAndDanglingRefs() throws {
    let speaker = try makeSpeaker()
    let seat = try CaptureAnnotationEntity(
        type: .seat,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .seatReferencePoint,
        label: "Seat",
        placement: makePlacement()
    )
    let relation = try CaptureSemanticRelation(
        relationType: .listenerPointForSeat,
        subjectRef: SemanticRelationEndpoint(entityID: speaker.entityID),
        objectRefs: [SemanticRelationEndpoint(entityID: seat.entityID)],
        provenanceClass: .userAnnotation,
        verificationState: .evidenceLinked
    )
    // listener_point_for_seat requires a seat object but the subject
    // must be a listening point — speaker subject is disallowed.
    #expect(
        throws: SemanticRelationGraphError.disallowedEndpointCombination
    ) {
        _ = try CaptureAnnotationCollection(
            entities: [speaker, seat],
            relations: [relation]
        )
    }
    // Dangling entity refs are rejected.
    let dangling = try CaptureSemanticRelation(
        relationType: .supportedBy,
        subjectRef: SemanticRelationEndpoint(entityID: speaker.entityID),
        objectRefs: [
            SemanticRelationEndpoint(entityID: AnnotationEntityID()),
        ],
        provenanceClass: .userAnnotation,
        verificationState: .evidenceLinked
    )
    #expect(
        throws: SemanticRelationGraphError.danglingEntityReference
    ) {
        _ = try CaptureAnnotationCollection(
            entities: [speaker, seat],
            relations: [dangling]
        )
    }
    // Self-links rejected at construction.
    #expect(throws: SemanticRelationError.selfReferentialRelation) {
        _ = try CaptureSemanticRelation(
            relationType: .supportedBy,
            subjectRef: SemanticRelationEndpoint(
                entityID: speaker.entityID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: speaker.entityID),
            ],
            provenanceClass: .userAnnotation,
            verificationState: .evidenceLinked
        )
    }
}

@Test
func supportedByRelationBetweenEntitiesValidates() throws {
    let speaker = try makeSpeaker()
    let rack = try CaptureAnnotationEntity(
        type: .equipmentRack,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Rack",
        placement: makePlacement()
    )
    let relation = try CaptureSemanticRelation(
        relationType: .supportedBy,
        subjectRef: SemanticRelationEndpoint(entityID: speaker.entityID),
        objectRefs: [SemanticRelationEndpoint(entityID: rack.entityID)],
        provenanceClass: .userAnnotation,
        verificationState: .userAttested,
        evidenceRefs: ["frame:rack"]
    )
    let collection = try CaptureAnnotationCollection(
        entities: [speaker, rack],
        relations: [relation]
    )
    #expect(collection.relations.count == 1)
    #expect(
        collection.relationsTouching(entityID: speaker.entityID)
            .count == 1
    )
}

@Test
func oneToManyRelationRepresentable() throws {
    let rack = try CaptureAnnotationEntity(
        type: .equipmentRack,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Rack",
        placement: makePlacement()
    )
    let speaker = try makeSpeaker()
    let sub = try makeSpeaker(label: "Sub", channelRole: .lfe1)
    // member_of_rack is subject-device → object-rack; the one-to-many
    // shape is exercised with a custom-scoped type (#344) whose
    // endpoint policy is open.
    let relation = try CaptureSemanticRelation(
        relationType: SemanticRelationType(rawValue: "x_rack_members")!,
        subjectRef: SemanticRelationEndpoint(entityID: rack.entityID),
        objectRefs: [
            SemanticRelationEndpoint(entityID: speaker.entityID),
            SemanticRelationEndpoint(entityID: sub.entityID),
        ],
        provenanceClass: .userAnnotation,
        verificationState: .evidenceLinked
    )
    _ = try CaptureAnnotationCollection(
        entities: [rack, speaker, sub],
        relations: [relation]
    )
}

@Test
func externalEndpointRequiresNamespacedAuthority() throws {
    let speaker = try makeSpeaker()
    // htdt_topology:L is an external authority ref — the object
    // resolves outside this revision.
    let external = SemanticRelationEndpoint(
        externalNamespace: "htdt_topology",
        reference: "L"
    )!
    #expect(external.entityID == nil)
    #expect(external.externalRef?.namespace == "htdt_topology")
    let relation = try CaptureSemanticRelation(
        relationType: .logicalRoleBinding,
        subjectRef: SemanticRelationEndpoint(entityID: speaker.entityID),
        objectRefs: [external],
        provenanceClass: .importedReference,
        verificationState: .unverified
    )
    _ = try CaptureAnnotationCollection(
        entities: [speaker],
        relations: [relation]
    )
}

// MARK: - #334 value domains + structured uncertainty

@Test
func standardQuantityDomainsEnforced() throws {
    // normalized_fraction domain: relative_humidity is 0...100.
    #expect(throws: MeasurementModelError.valueOutsideQuantityDomain) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "relative_humidity",
            value: .scalar(120),
            unit: .percent,
            endpointCount: 0
        )
    }
    // strictly_positive: room dimensions are never zero.
    #expect(throws: MeasurementModelError.valueOutsideQuantityDomain) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "room_width",
            value: .scalar(0),
            unit: .meter,
            endpointCount: 2
        )
    }
    // signed_unbounded: azimuth may be negative.
    try MeasurementQuantityRegistry.validate(
        quantityType: "azimuth",
        value: .scalar(-0.5),
        unit: .radian,
        endpointCount: 0
    )
    // Custom quantities declare no domain — the registry cannot
    // over-constrain them.
    try MeasurementQuantityRegistry.validate(
        quantityType: "x_leaf_deflection",
        value: .scalar(-42),
        unit: .meter,
        endpointCount: 0
    )
}

@Test
func structuredUncertaintyKindsEnforceCoverageRules() throws {
    // coverage_factor only accompanies expanded_uncertainty.
    #expect(throws: MeasurementModelError.invalidUncertainty) {
        try MeasurementUncertainty(
            value: 0.01,
            kind: .standardUncertainty,
            coverageFactor: 2.0,
            source: .instrumentStated
        )
    }
    // confidence_level only with statistical kinds.
    #expect(throws: MeasurementModelError.invalidUncertainty) {
        try MeasurementUncertainty(
            value: 0.01,
            kind: .absoluteBound,
            confidenceLevel: 0.95,
            source: .userStated
        )
    }
    let expanded = try MeasurementUncertainty(
        value: 0.02,
        kind: .expandedUncertainty,
        coverageFactor: 2.0,
        confidenceLevel: 0.95,
        source: .instrumentStated
    )
    #expect(expanded.coverageFactor == 2.0)
    // A bare legacy stated_uncertainty stays readable and must mirror
    // the structured value when both are present.
    #expect(throws: MeasurementModelError.invalidUncertainty) {
        try CaptureMeasurement(
            quantityType: "room_width",
            value: .scalar(3),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            statedUncertainty: 0.05,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            uncertainty: try MeasurementUncertainty(
                value: 0.01,
                kind: .standardUncertainty,
                source: .instrumentStated
            )
        )
    }
}

// MARK: - #344 open-token namespaces

@Test
func openTokenPolicyClassifiesAndScopes() throws {
    #expect(
        OpenTokenPolicy.classify(
            "room_width",
            vocabulary: .measurementQuantity
        ) == .standard
    )
    #expect(
        OpenTokenPolicy.classify(
            "x_panel_thickness",
            vocabulary: .measurementQuantity
        ) == .customScoped
    )
    #expect(
        OpenTokenPolicy.classify(
            "panel_thickness",
            vocabulary: .measurementQuantity
        ) == .legacyCustomUnscoped
    )
    // Authoring auto-scopes an unscoped custom token.
    #expect(
        OpenTokenPolicy.scopedForAuthoring(
            "panel_thickness",
            vocabulary: .measurementQuantity
        ) == "x_panel_thickness"
    )
    #expect(
        OpenTokenPolicy.scopedForAuthoring(
            "room_width",
            vocabulary: .measurementQuantity
        ) == "room_width"
    )
    // Channel roles scope with the X_ prefix.
    #expect(
        OpenTokenPolicy.scopedForAuthoring(
            "WIDE_L",
            vocabulary: .channelRole
        ) == "X_WIDE_L"
    )
    #expect(
        OpenTokenPolicy.classify("X_WIDE_L", vocabulary: .channelRole)
            == .customScoped
    )
    // Display labels are distinct from token identity: a label never
    // changes the namespace classification.
    #expect(
        OpenTokenPolicy.isWireLegal(
            "x_wall_clearance",
            vocabulary: .measurementQuantity
        )
    )
    #expect(
        !OpenTokenPolicy.isWireLegal(
            "wall_clearance",
            vocabulary: .measurementQuantity
        )
    )
}

@Test
func unscopedTokensRejectedOnV110ButReadableOnV100() throws {
    let measurement = try makeMeasurement(
        quantityType: "table_diameter"
    )
    // v1.1.0 rejects unscoped custom quantity tokens.
    #expect(throws: MeasurementModelError.unscopedCustomQuantity) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "table_diameter",
            value: .scalar(1.1),
            unit: .meter,
            endpointCount: 0
        )
    }
    // v1.0.0 collection stays readable and the record classifies
    // legacy_custom_unscoped for Review surfacing.
    let collection = try CaptureMeasurementCollection(
        measurements: [measurement],
        declaredSchemaVersion: "1.0.0"
    )
    #expect(collection.legacyUnscopedQuantityMeasurements.count == 1)
}

// MARK: - #354 task-plan fulfillment integrity

private func makePlanImport(
    entityItems: [HTDTTaskPlanEntityItem] = [],
    measurementItems: [HTDTTaskPlanMeasurementItem] = [],
    surfaceItems: [HTDTTaskPlanSurfaceItem] = []
) throws -> CaptureTaskPlanImport {
    var request: [String: Any] = [
        "schema": "htdt.capture-task-plan",
        "schema_version": "1.0.0",
        "plan_id": "plan-fulfillment",
        "plan_version": "1.0",
        "project_ref": "proj-1",
        "room_name": "Theater",
        "entity_checklist": [],
        "measurement_requests": [],
        "surface_review_tasks": [],
        "evidence_targets": ["frame:north-wall"],
    ]
    func encode<T: Encodable>(_ v: T) -> Any {
        let data = try! JSONEncoder().encode(v)
        return try! JSONSerialization.jsonObject(with: data)
    }
    request["entity_checklist"] = entityItems.map(encode)
    request["measurement_requests"] = measurementItems.map(encode)
    request["surface_review_tasks"] = surfaceItems.map(encode)
    let data = try JSONSerialization.data(
        withJSONObject: request,
        options: [.sortedKeys]
    )
    return try CaptureTaskPlanImport(data: data)
}

@Test
func fulfillmentRequiresExactTypedRecordIdentity() throws {
    let plan = try makePlanImport(
        measurementItems: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m-1",
                quantityType: "room_width",
                requirement: .required
            ),
            try HTDTTaskPlanMeasurementItem(
                itemID: "m-2",
                quantityType: "room_width",
                requirement: .required
            ),
        ]
    )
    let status = CaptureTaskPlanStatus(planImport: plan)
    let measurement = try makeMeasurement()
    // One measurement matching two requested items satisfies neither
    // automatically — a single record never fulfills two tasks.
    let outcomes = status.itemOutcomes(
        annotations: [],
        measurements: [measurement]
    )
    #expect(outcomes.allSatisfy { $0.outcome != .completed })
}

@Test
func explicitBindingSurvivesAmbiguousCandidates() throws {
    let plan = try makePlanImport(
        measurementItems: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m-1",
                quantityType: "room_width",
                requirement: .required
            ),
        ]
    )
    var status = CaptureTaskPlanStatus(planImport: plan)
    let first = try makeMeasurement()
    let second = try makeMeasurement(value: .scalar(3.5))
    try status.bind(itemID: "m-1", toMeasurement: first.measurementID)
    let outcomes = status.itemOutcomes(
        annotations: [],
        measurements: [first, second]
    )
    #expect(outcomes.first?.outcome == .completed)
    #expect(
        outcomes.first?.fulfillment?.recordID
            == first.measurementID.description
    )
    #expect(outcomes.first?.fulfillment?.recordKind == .measurement)
}

@Test
func deletedOrReplacedFulfillmentLeavesItemUnresolved() throws {
    let plan = try makePlanImport(
        measurementItems: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m-1",
                quantityType: "room_width",
                requirement: .required
            ),
        ]
    )
    var status = CaptureTaskPlanStatus(planImport: plan)
    let measurement = try makeMeasurement()
    try status.bind(itemID: "m-1", toMeasurement: measurement.measurementID)
    // Bound record absent from the committed set → unresolved.
    let outcomes = status.itemOutcomes(annotations: [], measurements: [])
    #expect(outcomes.first?.outcome == .pending)
    #expect(outcomes.first?.fulfillment == nil)
    // A superseded record never fulfills either.
    let superseded = try makeMeasurement(
        lineage: MeasurementLineage(disposition: .superseded)
    )
    let outcomes2 = status.itemOutcomes(
        annotations: [],
        measurements: [superseded]
    )
    #expect(outcomes2.first?.outcome == .pending)
}

@Test
func taskRefBindingFulfillsTypedEndpointRequest() throws {
    let plan = try makePlanImport(
        measurementItems: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m-1",
                quantityType: "room_width",
                requirement: .required,
                endpointSemantics: "wall_to_wall"
            ),
        ]
    )
    let status = CaptureTaskPlanStatus(planImport: plan)
    // Generic equality never satisfies a typed-endpoint request.
    let generic = try makeMeasurement()
    #expect(
        status.itemOutcomes(annotations: [], measurements: [generic])
            .first?.outcome == .pending
    )
    // A measurement whose lineage.task_ref names the item fulfills it.
    let bound = try makeMeasurement(
        lineage: MeasurementLineage(
            taskRef: MeasurementTaskRef(planID: "plan-fulfillment", itemID: "m-1")
        )
    )
    #expect(
        status.itemOutcomes(annotations: [], measurements: [bound])
            .first?.outcome == .completed
    )
}

@Test
func statusDocumentRejectsFulfillmentOnNonCompletedOutcome() throws {
    #expect(throws: CaptureTaskPlanError.invalidFulfillmentLink) {
        try CaptureTaskPlanStatusDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            planID: "p",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(of: Data("x".utf8)),
            items: [
                .init(
                    itemID: "m-1",
                    outcome: .pending,
                    fulfillment: try TaskFulfillmentLink(
                        recordKind: .measurement,
                        recordID: MeasurementID().description
                    )
                ),
            ]
        )
    }
}

// MARK: - #356 as-built deviation + uncertainty verdicts

@Test
func deviationStoresDeltaNotAbsolutePosition() throws {
    // Non-zero planned position: translation_scene must be
    // observed - planned on every axis and distance_m its norm.
    let spec = try PlannedAsBuiltSpec(
        plannedEntityID: "speaker-left",
        entityType: .speaker,
        positionScene: SpatialVector3F(1.0, 1.5, -2.0),
        toleranceMeters: 0.1
    )
    let space = CoordinateSpaceID()
    let observation = try AsBuiltObservation(
        plannedEntityID: "speaker-left",
        positionWorld: SpatialVector3F(1.05, 1.5, -1.97),
        coordinateSpaceID: space
    )
    let deviation = try AsBuiltVerificationSession.deviation(
        spec: spec,
        observation: observation,
        sceneFromCapture: .identity
    )
    let deltaX = abs(deviation.translationScene.x - Float(0.05))
    let deltaZ = abs(deviation.translationScene.z - Float(0.03))
    let expectedDistance = sqrt(0.05 * 0.05 + 0.03 * 0.03)
    let deltaDistance = abs(deviation.distanceMeters - expectedDistance)
    #expect(deltaX < 1e-6)
    #expect(deltaZ < 1e-6)
    #expect(deviation.translationScene.y == 0)
    #expect(deltaDistance < 1e-5)
}

@Test
func verdictAccountsForObservationUncertaintyAndResidual() throws {
    typealias Session = AsBuiltVerificationSession
    // No tolerance → captured (data present, no verdict claimed).
    #expect(
        Session.verdict(
            deviationMeters: 0.05,
            toleranceMeters: nil,
            observationUncertaintyMeters: nil,
            alignmentResidualMeters: nil
        ) == .captured
    )
    // Missing uncertainty is never treated as zero — policy-required
    // verdicts go indeterminate.
    #expect(
        Session.verdict(
            deviationMeters: 0.05,
            toleranceMeters: 0.1,
            observationUncertaintyMeters: nil,
            alignmentResidualMeters: 0.01
        ) == .indeterminate
    )
    // deviation + band <= tolerance → verified.
    #expect(
        Session.verdict(
            deviationMeters: 0.05,
            toleranceMeters: 0.1,
            observationUncertaintyMeters: 0.02,
            alignmentResidualMeters: 0.01
        ) == .verified
    )
    // deviation - band > tolerance → deviated.
    #expect(
        Session.verdict(
            deviationMeters: 0.2,
            toleranceMeters: 0.1,
            observationUncertaintyMeters: 0.02,
            alignmentResidualMeters: 0.01
        ) == .deviated
    )
    // Boundary overlap → indeterminate.
    #expect(
        Session.verdict(
            deviationMeters: 0.12,
            toleranceMeters: 0.1,
            observationUncertaintyMeters: 0.02,
            alignmentResidualMeters: 0.01
        ) == .indeterminate
    )
}

@Test
func alignmentResidualValidatesNonNegativeFinite() throws {
    #expect(throws: AsBuiltVerificationError.invalidResidualValue) {
        try PlanAlignmentAuthority(
            mechanism: .referenceTarget,
            sceneFromCapture: .identity,
            authorityRef: "reference_target:abc",
            establishedAtUTC: "2026-01-01T00:00:00Z",
            residualMeters: -0.1
        )
    }
}

// MARK: - #332 support-matrix file consistency

@Test
func emittedSchemasMatchSupportMatrix() throws {
    let matrix = CaptureBundleSchemaRegistry.supportMatrix
    // The versions the models emit match the matrix's `emitted` key.
    #expect(
        CaptureAnnotationCollection.expectedSchemaVersion
            == matrix.families["entities"]?.emitted
    )
    #expect(
        CaptureMeasurementCollection.expectedSchemaVersion
            == matrix.families["measurements"]?.emitted
    )
    #expect(
        CaptureTaskPlanStatusDocument.schemaVersion
            == matrix.families["task-plan-status"]?.emitted
    )
    #expect(
        AsBuiltVerificationDocument.schemaVersion
            == matrix.families["as-built"]?.emitted
    )
}
