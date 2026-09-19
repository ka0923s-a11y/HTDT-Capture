import Foundation
import Testing
@testable import HTDTCaptureCore

private func canonicalSpeaker(
    role: ChannelRole,
    space: CoordinateSpaceID
) throws -> CaptureAnnotationEntity {
    try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: space,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: role.rawValue,
        verificationState: .evidenceLinked,
        placement: PlacementProvenance(
            method: .manualNumeric,
            sourceEvidenceRefs: ["measurement:speaker-position"]
        ),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: role,
        evidenceRefs: ["frame:speaker"]
    )
}

@Test
func speakerRequiresOrientationAndChannelRole() throws {
    let space = CoordinateSpaceID()
    let placement = try PlacementProvenance(method: .manualNumeric)

    #expect(throws: AnnotationModelError.self) {
        _ = try CaptureAnnotationEntity(
            type: .speaker,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: "Left",
            placement: placement,
            orientation: nil,
            channelRole: .left
        )
    }

    #expect(throws: AnnotationModelError.self) {
        _ = try CaptureAnnotationEntity(
            type: .speaker,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: "Left",
            placement: placement,
            orientation: OrientationAxes(
                frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
                upAxisLocal: SpatialVector3F.unit(0, 1, 0)
            ),
            channelRole: nil
        )
    }
}

@Test
func orientationAxesMustBeUnitAndOrthogonal() throws {
    #expect(throws: AnnotationModelError.self) {
        _ = try OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 0, 1)
        )
    }
}

@Test
func acousticCenterOffsetRequiresAuthorityReference() throws {
    #expect(throws: AnnotationModelError.self) {
        _ = try AcousticCenterOffsetAuthority(
            offsetLocalMeters: SpatialVector3F(0, 0.1, 0),
            authorityRef: ""
        )
    }
}

@Test
func fiveChannelTopologyIsRepresentableWithoutGeometryFreeText() throws {
    let space = CoordinateSpaceID()
    let roles: [ChannelRole] = [
        .left, .center, .right, .surroundLeft, .surroundRight
    ]
    let speakers = try roles.map {
        try canonicalSpeaker(role: $0, space: space)
    }
    let subwoofer = try CaptureAnnotationEntity(
        type: .subwoofer,
        coordinateSpaceID: space,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Subwoofer",
        placement: PlacementProvenance(method: .manualNumeric),
        channelRole: .lfe
    )
    let mlp = try CaptureAnnotationEntity(
        type: .listeningPosition,
        coordinateSpaceID: space,
        worldFromAnnotation: .identity,
        referencePointSemantics: .earCenter,
        label: "MLP",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let collection = try CaptureAnnotationCollection(
        entities: speakers + [subwoofer, mlp]
    )

    #expect(collection.entities.count == 7)
    #expect(
        Set(
            collection.entities.compactMap(\.channelRole)
        ).isSuperset(of: Set(roles))
    )
}

@Test
func annotationJSONKeepsPlacementAndCoordinateAuthority() throws {
    let space = CoordinateSpaceID(
        rawValue: UUID(
            uuidString: "00000000-0000-4000-8000-000000000004"
        )!
    )
    let speaker = try canonicalSpeaker(role: .left, space: space)
    let collection = try CaptureAnnotationCollection(
        entities: [speaker]
    )
    let data = try JSONEncoder().encode(collection)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let entities = try #require(
        json["entities"] as? [[String: Any]]
    )
    #expect(
        entities[0]["coordinate_space_id"] as? String
            == space.description
    )
    #expect(entities[0]["placement"] != nil)
    #expect(entities[0]["T_world_from_annotation"] != nil)
}

@Test
func userAttestedMeasurementRequiresAttestation() throws {
    #expect(throws: MeasurementModelError.self) {
        _ = try CaptureMeasurement(
            quantityType: "distance",
            value: .scalar(1.1),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            userAttestation: .notAttested,
            provenanceClass: .userAttestedMeasurement
        )
    }
}

@Test
func spatialMeasurementRequiresCoordinateSpace() throws {
    #expect(throws: MeasurementModelError.self) {
        _ = try CaptureMeasurement(
            quantityType: "point",
            value: .vector3(1, 2, 3),
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
}

@Test
func conflictingMeasurementsCoexistWithoutOverwrite() throws {
    let inferred = try CaptureMeasurement(
        quantityType: "table_diameter",
        value: .scalar(1.08),
        unit: .meter,
        acquisitionMethod: .roomPlanDerived,
        userAttestation: .notAttested,
        provenanceClass: .appleRoomPlanInference
    )
    let attested = try CaptureMeasurement(
        quantityType: "table_diameter",
        value: .scalar(1.10),
        unit: .meter,
        acquisitionMethod: .tapeMeasure,
        instrument: MeasurementInstrument(
            instrumentClass: "tape_measure"
        ),
        statedUncertainty: 0.005,
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement,
        sourceValueText: "110 cm"
    )

    let collection = try CaptureMeasurementCollection(
        measurements: [inferred, attested]
    )

    #expect(collection.measurements.count == 2)
    #expect(
        collection.measurements.map(\.provenanceClass)
            == [.appleRoomPlanInference, .userAttestedMeasurement]
    )
}

@Test
func measurementJSONPreservesInstrumentAndSourceText() throws {
    let measurement = try CaptureMeasurement(
        quantityType: "room_width",
        value: .scalar(3.4),
        unit: .meter,
        acquisitionMethod: .laserDistanceMeter,
        instrument: MeasurementInstrument(
            instrumentClass: "laser_distance_meter",
            makeModel: "fixture-model",
            calibrationStatus: "user_reported_current",
            calibrationDate: "2026-09-01"
        ),
        statedUncertainty: 0.003,
        observedAtUTC: "2026-09-20T00:00:00Z",
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement,
        sourceValueText: "3.400 m",
        evidenceRefs: ["frame:width-reference"]
    )
    let collection = try CaptureMeasurementCollection(
        measurements: [measurement]
    )
    let data = try JSONEncoder().encode(collection)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let measurements = try #require(
        json["measurements"] as? [[String: Any]]
    )
    #expect(
        measurements[0]["source_value_text"] as? String
            == "3.400 m"
    )
    #expect(measurements[0]["instrument"] != nil)
}


@Test
func exactEquipmentReferenceCarriesIDVersionAndHash() throws {
    let hash = try EvidenceSHA256(String(repeating: "a", count: 64))
    let reference = try HTDTEquipmentReference(
        equipmentID: "eq-speaker-left",
        equipmentVersion: "3",
        equipmentHash: hash
    )
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Left",
        placement: PlacementProvenance(method: .manualNumeric),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: .left,
        equipmentRef: reference
    )

    let data = try JSONEncoder().encode(entity)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let equipment = try #require(
        json["equipment_ref"] as? [String: Any]
    )
    #expect(equipment["equipment_id"] as? String == "eq-speaker-left")
    #expect(equipment["equipment_version"] as? String == "3")
    #expect(
        equipment["equipment_hash"] as? String
            == String(repeating: "a", count: 64)
    )
}

@Test
func referencePointSemanticsRejectsFreeFormText() {
    #expect(ReferencePointSemantics(rawValue: "speaker center") == nil)
    #expect(
        ReferencePointSemantics(rawValue: "cabinet_reference_point")
            == .cabinetReferencePoint
    )
}
