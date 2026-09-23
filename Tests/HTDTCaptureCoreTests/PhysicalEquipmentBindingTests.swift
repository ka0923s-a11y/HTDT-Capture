import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Physical-equipment identity bridge (#403) and rack-membership
/// canonicalization (#333): the first-class `inventory_item:`
/// endpoint, the `same_physical_equipment` identity relation,
/// cross-collection referential integrity, and the advisory review
/// surface.
final class PhysicalEquipmentBindingTests: XCTestCase {
    private let space = CoordinateSpaceID()

    private func entity(
        type: AnnotationEntityType,
        label: String = "E",
        equipmentRef: HTDTEquipmentReference? = nil
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: label,
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(method: .manualNumeric),
            equipmentRef: equipmentRef
        )
    }

    private func item(
        kind: InventoryEquipmentClass = .projector,
        label: String = "PJ",
        equipmentRef: HTDTEquipmentReference? = nil,
        serial: String? = nil,
        hostRack: AnnotationEntityID? = nil
    ) throws -> SystemInventoryItem {
        try SystemInventoryItem(
            equipmentClass: kind,
            userLabel: label,
            equipmentRef: equipmentRef,
            serialNumber: serial,
            hostRackEntityID: hostRack
        )
    }

    private func equipmentRef(
        _ id: String = "eq-pj-x",
        _ version: String = "1.0.0"
    ) throws -> HTDTEquipmentReference {
        try HTDTEquipmentReference(
            equipmentID: id,
            equipmentVersion: version,
            equipmentHash: try EvidenceSHA256(
                String(repeating: "a", count: 64)
            )
        )
    }

    private func binding(
        entity: CaptureAnnotationEntity,
        itemID: AuthorityRecordID
    ) throws -> CaptureSemanticRelation {
        try CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: SemanticRelationEndpoint(
                entityID: entity.entityID
            ),
            objectRefs: [
                SemanticRelationEndpoint(inventoryItemID: itemID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
    }

    private func measurementPackage()
        throws -> MeasurementEvidencePackage
    {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "x_wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    private func annotationPackage(
        _ entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation] = []
    ) throws -> AnnotationEvidencePackage {
        try AnnotationEvidencePackageBuilder.build(
            entities: entities,
            relations: relations
        )
    }

    private func makeStore() throws -> (
        store: CaptureWorkingSetStore, root: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        return (
            try CaptureWorkingSetStore(rootDirectory: root),
            root
        )
    }

    // MARK: - #403 inventory_item endpoint

    func testInventoryItemEndpointParsesAndRoundTrips() throws {
        let itemID = AuthorityRecordID()
        let endpoint = SemanticRelationEndpoint(
            inventoryItemID: itemID
        )
        XCTAssertEqual(
            endpoint.rawValue,
            "inventory_item:\(itemID.description)"
        )
        XCTAssertEqual(endpoint.inventoryItemID, itemID)
        XCTAssertEqual(
            endpoint.externalRef?.namespace,
            "inventory_item"
        )
        XCTAssertNil(endpoint.entityID)
        XCTAssertTrue(endpoint.isInventoryItemRef)
        XCTAssertEqual(
            SemanticRelationEndpoint(validating: endpoint.rawValue),
            endpoint
        )
    }

    func testInventoryItemEndpointRejectsMalformedRefs() throws {
        XCTAssertNil(
            SemanticRelationEndpoint(
                validating: "inventory_item:not-a-uuid"
            )
        )
        XCTAssertNil(
            SemanticRelationEndpoint(
                externalNamespace: "inventory_item",
                reference: "legacy-row-7"
            )
        )
        // The malformed reserved ref is a dangling endpoint, never an
        // opaque external authority.
        let projector = try entity(type: .projector)
        let malformed = SemanticRelationEndpoint(
            rawValue: "inventory_item:not-a-uuid"
        )
        let relation = try CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: malformed,
            objectRefs: [
                SemanticRelationEndpoint(entityID: projector.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector],
                relations: [relation]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .danglingEntityReference
            )
        }
    }

    // MARK: - #403 same_physical_equipment semantics

    func testSamePhysicalEquipmentBindsEitherDirection() throws {
        let projector = try entity(type: .projector)
        let itemID = AuthorityRecordID()
        let relation = try binding(entity: projector, itemID: itemID)
        XCTAssertTrue(
            relation.isIdentityBinding(touching: projector.entityID)
        )
        XCTAssertTrue(relation.isIdentityBinding(touching: itemID))
        XCTAssertTrue(relation.referencesInventoryItem)
        _ = try CaptureAnnotationCollection(
            entities: [projector],
            relations: [relation]
        )

        let inverse = try CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: projector.entityID)
            ],
            provenanceClass: .captureAppDerived,
            verificationState: .unverified
        )
        _ = try CaptureAnnotationCollection(
            entities: [projector],
            relations: [inverse]
        )
    }

    func testSamePhysicalEquipmentRejectsWrongPairs() throws {
        let projector = try entity(type: .projector)
        let seat = try entity(type: .seat)
        let itemID = AuthorityRecordID()

        // entity ↔ entity is not an identity binding.
        let display = try entity(type: .display)
        let entityPair = try CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: SemanticRelationEndpoint(
                entityID: projector.entityID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: display.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector, display],
                relations: [entityPair]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .disallowedEndpointCombination
            )
        }

        // item ↔ item is not an identity binding either.
        let itemPair = try? CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(
                    inventoryItemID: AuthorityRecordID()
                )
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        XCTAssertNotNil(itemPair)
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector],
                relations: [itemPair!]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .disallowedEndpointCombination
            )
        }

        // A seat is not physical equipment (#403 endpoint kinds).
        let seatBinding = try? CaptureSemanticRelation(
            relationType: .samePhysicalEquipment,
            subjectRef: SemanticRelationEndpoint(
                entityID: seat.entityID
            ),
            objectRefs: [
                SemanticRelationEndpoint(inventoryItemID: itemID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        XCTAssertNotNil(seatBinding)
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [seat],
                relations: [seatBinding!]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .disallowedEndpointCombination
            )
        }
    }

    func testIdentityBindingIsPairwiseAndOneToOne() throws {
        let projector = try entity(type: .projector)
        let itemA = AuthorityRecordID()
        let itemB = AuthorityRecordID()

        // Identity equivalence takes exactly one object.
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector],
                relations: [
                    try CaptureSemanticRelation(
                        relationType: .samePhysicalEquipment,
                        subjectRef: SemanticRelationEndpoint(
                            entityID: projector.entityID
                        ),
                        objectRefs: [
                            SemanticRelationEndpoint(
                                inventoryItemID: itemA
                            ),
                            SemanticRelationEndpoint(
                                inventoryItemID: itemB
                            ),
                        ],
                        provenanceClass: .userAnnotation,
                        verificationState: .unverified
                    ),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .invalidIdentityBindingShape
            )
        }

        // The same entity bound to two items is a 1:1 violation.
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector],
                relations: [
                    try binding(entity: projector, itemID: itemA),
                    try binding(entity: projector, itemID: itemB),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .duplicatePhysicalEquipmentBinding
            )
        }

        // The same item bound to two entities is a 1:1 violation.
        let other = try entity(type: .projector, label: "PJ-2")
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [projector, other],
                relations: [
                    try binding(entity: projector, itemID: itemA),
                    try binding(entity: other, itemID: itemA),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .duplicatePhysicalEquipmentBinding
            )
        }
    }

    func testMemberOfRackAcceptsInventorySubject() throws {
        let rack = try entity(type: .equipmentRack)
        let itemID = AuthorityRecordID()
        let relation = try CaptureSemanticRelation(
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: rack.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        _ = try CaptureAnnotationCollection(
            entities: [rack],
            relations: [relation]
        )

        // Inventory items only belong in real racks.
        let speaker = try entity(type: .display, label: "disp")
        let badTarget = try CaptureSemanticRelation(
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: speaker.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        XCTAssertThrowsError(
            try CaptureAnnotationCollection(
                entities: [speaker],
                relations: [badTarget]
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticRelationGraphError,
                .disallowedEndpointCombination
            )
        }
    }

    // MARK: - #403/#333 vocabulary versioning

    func testIdentityTokenRequiresTwelve() throws {
        let projector = try entity(type: .projector)
        let itemID = AuthorityRecordID()
        let collection = try CaptureAnnotationCollection(
            entities: [projector],
            relations: [
                try binding(entity: projector, itemID: itemID)
            ]
        )
        XCTAssertEqual(collection.schemaVersion, "1.3.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payload = try JSONSerialization.jsonObject(
            with: encoder.encode(collection)
        ) as! [String: Any]
        payload["schema_version"] = "1.1.0"
        let downgraded = try JSONSerialization.data(
            withJSONObject: payload
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CaptureAnnotationCollection.self,
                from: downgraded
            )
        ) { error in
            XCTAssertEqual(
                error as? AnnotationModelError,
                .unscopedCustomToken
            )
        }
    }

    // MARK: - #333 legacy host_rack_entity_id bridging

    func testLegacyHostRackDerivesCanonicalMembership() throws {
        let rackA = try entity(type: .equipmentRack, label: "RACK-A")
        let rackB = try entity(type: .equipmentRack, label: "RACK-B")
        let unit = try item(hostRack: rackA.entityID)

        // No relation committed: the denormalized field reads back
        // and a deterministic member_of_rack view derives from it.
        XCTAssertEqual(
            unit.rackMembershipEntity(relations: []),
            rackA.entityID
        )
        let derived = try XCTUnwrap(
            unit.canonicalRackMembership(relations: [])
        )
        XCTAssertEqual(derived.relationType, .memberOfRack)
        XCTAssertEqual(
            derived.subjectRef.inventoryItemID,
            unit.itemID
        )
        XCTAssertEqual(
            derived.objectRefs.first?.entityID,
            rackA.entityID
        )
        XCTAssertEqual(
            unit.canonicalRackMembership(relations: []),
            derived
        )

        // The committed relation is authoritative over the field.
        let committed = try CaptureSemanticRelation(
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: unit.itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: rackB.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .userAttested
        )
        XCTAssertEqual(
            unit.canonicalRackMembership(relations: [committed]),
            committed
        )
        XCTAssertEqual(
            unit.rackMembershipEntity(relations: [committed]),
            rackB.entityID
        )
    }

    // MARK: - #403 review surface

    func testReviewSurfacesCandidatesNotMerges() throws {
        let ref = try equipmentRef()
        let projector = try entity(
            type: .projector,
            equipmentRef: ref
        )
        let looseDisplay = try entity(type: .display, label: "disp")
        let bound = try item(equipmentRef: ref)
        let candidate = try item(serial: "SN-1")
        let duplicate = try item(serial: "SN-1")
        let relation = try binding(
            entity: projector,
            itemID: bound.itemID
        )

        let findings = PhysicalEquipmentReview.findings(
            entities: [projector, looseDisplay],
            inventoryItems: [bound, candidate, duplicate],
            relations: [relation]
        )
        let codes = findings.map(\.code)
        XCTAssertTrue(codes.contains(.duplicateSerialNumber))
        XCTAssertTrue(codes.contains(.unboundSpatialEquipment))
        XCTAssertTrue(codes.contains(.unboundInventoryUnit))
        // Bound pair shares one equipment_ref — no false conflict.
        XCTAssertFalse(
            findings.contains {
                $0.code == .conflictingEquipmentDefinition
            }
        )
        // Advisory only — findings never rewrite the inputs.
        XCTAssertTrue(findings.allSatisfy { $0.severity != .error })
    }

    func testReviewFlagsBoundDefinitionAndRackConflicts() throws {
        let projector = try entity(
            type: .projector,
            equipmentRef: try equipmentRef("eq-a")
        )
        let rackA = try entity(type: .equipmentRack, label: "RACK-A")
        let rackB = try entity(type: .equipmentRack, label: "RACK-B")
        let unit = try item(
            equipmentRef: try equipmentRef("eq-b"),
            hostRack: rackB.entityID
        )
        let entityRack = try CaptureSemanticRelation(
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                entityID: projector.entityID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: rackA.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        let identity = try binding(
            entity: projector,
            itemID: unit.itemID
        )
        let findings = PhysicalEquipmentReview.findings(
            entities: [projector, rackA, rackB],
            inventoryItems: [unit],
            relations: [identity, entityRack]
        )
        XCTAssertTrue(
            findings.contains {
                $0.code == .conflictingEquipmentDefinition
                    && $0.itemID == unit.itemID
            }
        )
        XCTAssertTrue(
            findings.contains {
                $0.code == .conflictingRackMembership
                    && $0.itemID == unit.itemID
            }
        )
    }

    // MARK: - #403/#333 cross-collection commit validation

    func testInventoryEndpointMustResolveInAuthorities() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let projector = try entity(type: .projector)
        let unit = try item()
        let relation = try binding(
            entity: projector,
            itemID: unit.itemID
        )
        let authorities = try TheaterAuthorityCollection(
            inventoryItems: [unit]
        )

        // Resolves against the staged authority package.
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(
                [projector],
                relations: [relation]
            ),
            measurementPackage: try measurementPackage(),
            authorityPackage: try TheaterAuthorityPackageBuilder.build(
                collection: authorities
            )
        )
    }

    func testDanglingInventoryEndpointRejected() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let projector = try entity(type: .projector)
        let relation = try binding(
            entity: projector,
            itemID: AuthorityRecordID()
        )

        // Rejected with an (empty) authority package.
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    [projector],
                    relations: [relation]
                ),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: try TheaterAuthorityCollection()
                    )
            )
            XCTFail("expected unresolvedAuthorityReference")
        } catch let error as CaptureWorkingSetError {
            guard case .unresolvedAuthorityReference = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }

        // Rejected with no authority collection at all.
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    [projector],
                    relations: [relation]
                ),
                measurementPackage: try measurementPackage()
            )
            XCTFail("expected unresolvedAuthorityReference")
        } catch let error as CaptureWorkingSetError {
            guard case .unresolvedAuthorityReference = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testDenormalizedHostRackMustAgreeWithRelation() async throws {
        let rackA = try entity(type: .equipmentRack, label: "RACK-A")
        let rackB = try entity(type: .equipmentRack, label: "RACK-B")

        // Denormalized field agreeing with the canonical relation:
        // accepted.
        do {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }
            let unit = try item(hostRack: rackA.entityID)
            let membership = try CaptureSemanticRelation(
                relationType: .memberOfRack,
                subjectRef: SemanticRelationEndpoint(
                    inventoryItemID: unit.itemID
                ),
                objectRefs: [
                    SemanticRelationEndpoint(
                        entityID: rackA.entityID
                    )
                ],
                provenanceClass: .userAnnotation,
                verificationState: .unverified
            )
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    [rackA],
                    relations: [membership]
                ),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: try TheaterAuthorityCollection(
                            inventoryItems: [unit]
                        )
                    )
            )
        }

        // Field and relation disagreeing: rejected.
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let unit = try item(hostRack: rackA.entityID)
        let conflicting = try CaptureSemanticRelation(
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: unit.itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: rackB.entityID)
            ],
            provenanceClass: .userAnnotation,
            verificationState: .unverified
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    [rackA, rackB],
                    relations: [conflicting]
                ),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: try TheaterAuthorityCollection(
                            inventoryItems: [unit]
                        )
                    )
            )
            XCTFail("expected conflictingAuthorityValue")
        } catch let error as CaptureWorkingSetError {
            guard case .conflictingAuthorityValue = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }
}
