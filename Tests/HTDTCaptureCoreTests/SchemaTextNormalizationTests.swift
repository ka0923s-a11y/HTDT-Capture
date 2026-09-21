import Foundation
import Testing
@testable import HTDTCaptureCore

// #139: schema-owned free text is NFC-normalized at the
// authority-construction boundary so canonically equivalent input
// produces identical canonical JSON.
private let decomposedLabel = "Cafe\u{0301}" // "Café" decomposed
private let precomposedLabel = "Caf\u{00E9}" // "Café" precomposed

@Test
func annotationLabelIsStoredNFC() throws {
    let entity = try CaptureAnnotationEntity(
        type: .referencePoint,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .userReferencePoint,
        label: decomposedLabel,
        placement: PlacementProvenance(method: .manualNumeric)
    )
    #expect(entity.label == precomposedLabel)
    #expect(entity.label == entity.label.precomposedStringWithCanonicalMapping)
}

@Test
func decomposedAndPrecomposedInputProduceIdenticalJSON() throws {
    let space = CoordinateSpaceID()
    let entityID = AnnotationEntityID()
    func build(_ label: String) throws -> CaptureAnnotationCollection {
        try CaptureAnnotationCollection(entities: [
            CaptureAnnotationEntity(
                entityID: entityID,
                type: .seat,
                coordinateSpaceID: space,
                worldFromAnnotation: .identity,
                referencePointSemantics: .seatReferencePoint,
                label: label,
                placement: PlacementProvenance(method: .manualNumeric)
            ),
        ])
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let a = try encoder.encode(build(decomposedLabel))
    let b = try encoder.encode(build(precomposedLabel))
    #expect(a == b)
}

@Test
func equipmentReferenceNormalizesIDAndVersion() throws {
    let hash = try EvidenceSHA256(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
    let reference = try HTDTEquipmentReference(
        equipmentID: "acme\u{0300}amp", // decomposed
        equipmentVersion: "v1\u{0301}",
        equipmentHash: hash
    )
    #expect(reference.equipmentID == "acme\u{0300}amp".precomposedStringWithCanonicalMapping)
    #expect(
        reference.equipmentVersion
            == "v1\u{0301}".precomposedStringWithCanonicalMapping
    )
}

@Test
func placementSourceTextAndRefsAreNormalized() throws {
    let placement = try PlacementProvenance(
        method: .roomPlanBinding,
        sourceSemanticEntityID: "table\u{0301}",
        sourceRoomPlanObjectID: "obj\u{0301}",
        sourceEvidenceRefs: ["path:evidence/f\u{0301}.json"]
    )
    #expect(
        placement.sourceSemanticEntityID
            == "table\u{0301}".precomposedStringWithCanonicalMapping
    )
    #expect(
        placement.sourceRoomPlanObjectID
            == "obj\u{0301}".precomposedStringWithCanonicalMapping
    )
    #expect(
        placement.sourceEvidenceRefs
            == ["path:evidence/f\u{0301}.json".precomposedStringWithCanonicalMapping]
    )
}

@Test
func canonicallyEquivalentDuplicateRefsFailAfterNormalization() throws {
    // "é" precomposed vs "é" decomposed normalize to the same ref.
    #expect(throws: AnnotationModelError.duplicateEvidenceReference) {
        _ = try PlacementProvenance(
            method: .manualNumeric,
            sourceEvidenceRefs: [
                "path:evidence/f\u{00E9}.json",
                "path:evidence/f\u{0065}\u{0301}.json",
            ]
        )
    }
}

@Test
func measurementTextFieldsAreNormalized() throws {
    let measurement = try CaptureMeasurement(
        quantityType: "width\u{0301}",
        value: .scalar(1.0),
        unit: .meter,
        coordinateSpaceID: CoordinateSpaceID(),
        endpointRefs: ["ref\u{0301}"],
        acquisitionMethod: .tapeMeasure,
        instrument: MeasurementInstrument(
            instrumentClass: "cls\u{0301}",
            makeModel: "mod\u{0301}",
            calibrationStatus: "st\u{0301}tus"
        ),
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement,
        sourceValueText: "1.0 m\u{0301}",
        evidenceRefs: ["frame:\u{0301}x"]
    )
    #expect(
        measurement.quantityType
            == "width\u{0301}".precomposedStringWithCanonicalMapping
    )
    #expect(
        measurement.endpointRefs
            == ["ref\u{0301}".precomposedStringWithCanonicalMapping]
    )
    #expect(
        measurement.sourceValueText
            == "1.0 m\u{0301}".precomposedStringWithCanonicalMapping
    )
    let instrument = try #require(measurement.instrument)
    #expect(
        instrument.instrumentClass
            == "cls\u{0301}".precomposedStringWithCanonicalMapping
    )
    #expect(
        instrument.makeModel
            == "mod\u{0301}".precomposedStringWithCanonicalMapping
    )
    #expect(
        instrument.calibrationStatus
            == "st\u{0301}tus".precomposedStringWithCanonicalMapping
    )
}

@Test
func asciitokensKeepTheirStricterRules() throws {
    // Token fields must not accept arbitrary text even when NFC-clean.
    #expect(ReferencePointSemantics(rawValue: "Has Spaces") == nil)
    #expect(ChannelRole(rawValue: "mixed case") == nil)
    #expect(ReferencePointSemantics(rawValue: "valid_token") != nil)
}
