import Foundation
import Testing
@testable import HTDTCaptureCore

// Issues #215, #235, #238, #253, #269, #270, #271, #275, #286, #287:
// measurement contract coverage — input parsing/unit conversion,
// quantity registry dimensionality, manufacturer source authority,
// derivation lineage, endpoint binding, and measurement points.

private func testSpace() -> CoordinateSpaceID {
    CoordinateSpaceID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000001"
        )!
    )
}

private func testEntity(
    x: Double,
    z: Double,
    placementMethod: PlacementMethod = .manualNumeric,
    label: String = "point"
) throws -> CaptureAnnotationEntity {
    let placement = try PlacementProvenance(
        method: placementMethod,
        sourceMeshAnchorID: placementMethod == .raycast
            || placementMethod == .meshHitTest
            ? UUID(uuidString: "40000000-0000-4000-8000-000000000001")
            : nil,
        sourceRoomPlanObjectID: placementMethod == .roomPlanBinding
            ? "rp-object-1"
            : nil
    )
    return try CaptureAnnotationEntity(
        type: .referencePoint,
        coordinateSpaceID: testSpace(),
        worldFromAnnotation: Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            Float(x), 0, Float(z),
            1,
        ]),
        referencePointSemantics: .userReferencePoint,
        label: label,
        provenanceClass: .userAnnotation,
        placement: placement
    )
}

// MARK: - Input parsing (#235)

@Test
func inputParserAcceptsDotAndCommaDecimals() {
    #expect(MeasurementInputParser.parse("4.2") == 4.2)
    #expect(MeasurementInputParser.parse("4,2") == 4.2)
    #expect(MeasurementInputParser.parse("  -3.5 ") == -3.5)
    #expect(MeasurementInputParser.parse("+0.25") == 0.25)
    #expect(MeasurementInputParser.parse("12") == 12)
}

@Test
func inputParserRejectsAmbiguousAndNonNumericText() {
    #expect(MeasurementInputParser.parse("") == nil)
    #expect(MeasurementInputParser.parse("   ") == nil)
    #expect(MeasurementInputParser.parse("abc") == nil)
    #expect(MeasurementInputParser.parse("1.2.3") == nil)
    #expect(MeasurementInputParser.parse("1,2,3") == nil)
    #expect(MeasurementInputParser.parse("1.2,3") == nil)
    #expect(MeasurementInputParser.parse("1e3") == nil)
    #expect(MeasurementInputParser.parse("-") == nil)
    #expect(MeasurementInputParser.parse(",") == nil)
    #expect(MeasurementInputParser.parse("4'2\"") == nil)
}

// MARK: - Input-unit conversion (#235, #269)

@Test
func inputUnitsConvertDeterministicallyToCanonicalUnits() {
    #expect(MeasurementInputUnit.meter.canonicalValue(3.4) == 3.4)
    #expect(MeasurementInputUnit.centimeter.canonicalValue(420) == 4.2)
    #expect(MeasurementInputUnit.millimeter.canonicalValue(2450) == 2.45)
    #expect(
        abs(MeasurementInputUnit.foot.canonicalValue(12) - 3.6576)
            < 1e-9
    )
    #expect(
        abs(MeasurementInputUnit.inch.canonicalValue(135) - 3.429)
            < 1e-9
    )
    // 12 ft 8 in = 152 in = 3.8608 m
    #expect(
        abs(
            MeasurementInputUnit.footAndInch
                .canonicalValue(12, secondary: 8) - 3.8608
        ) < 1e-9
    )
    #expect(
        abs(MeasurementInputUnit.degree.canonicalValue(90) - .pi / 2)
            < 1e-12
    )
    // 68 F = 20 C
    #expect(
        abs(MeasurementInputUnit.fahrenheit.canonicalValue(68) - 20)
            < 1e-9
    )
    #expect(MeasurementInputUnit.fraction.canonicalValue(0.45) == 45)
    #expect(MeasurementInputUnit.percent.canonicalValue(45) == 45)
}

@Test
func inputUnitsMapToCanonicalWireUnits() {
    #expect(MeasurementInputUnit.centimeter.canonicalUnit == .meter)
    #expect(MeasurementInputUnit.footAndInch.canonicalUnit == .meter)
    #expect(MeasurementInputUnit.degree.canonicalUnit == .radian)
    #expect(MeasurementInputUnit.fahrenheit.canonicalUnit == .degreeCelsius)
    #expect(MeasurementInputUnit.fraction.canonicalUnit == .percent)
}

// MARK: - Unit vocabulary (#269)

@Test
func wireUnitDimensionsAreMachineReadable() {
    #expect(MeasurementUnit.meter.dimension == .length)
    #expect(MeasurementUnit.radian.dimension == .angle)
    #expect(MeasurementUnit.second.dimension == .time)
    #expect(MeasurementUnit.degreeCelsius.dimension == .temperature)
    #expect(MeasurementUnit.percent.dimension == .dimensionless)
    #expect(MeasurementUnit.dimensionless.dimension == .dimensionless)
}

// MARK: - Quantity registry (#287)

@Test
func registryRejectsDimensionallyWrongUnits() throws {
    #expect(
        throws: MeasurementModelError.incompatibleUnitForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "room_width",
            value: .scalar(4.2),
            unit: .radian,
            endpointCount: 0
        )
    }
    #expect(
        throws: MeasurementModelError.incompatibleUnitForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "azimuth",
            value: .scalar(1.0),
            unit: .meter,
            endpointCount: 0
        )
    }
    #expect(
        throws: MeasurementModelError.incompatibleUnitForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "relative_humidity",
            value: .scalar(45),
            unit: .dimensionless,
            endpointCount: 0
        )
    }
    try MeasurementQuantityRegistry.validate(
        quantityType: "room_width",
        value: .scalar(4.2),
        unit: .meter,
        endpointCount: 2
    )
}

@Test
func registryEnforcesValueShapeAndEndpointSemantics() throws {
    #expect(
        throws: MeasurementModelError.incompatibleValueShapeForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "room_width",
            value: .vector3(1, 0, 0),
            unit: .meter,
            endpointCount: 2
        )
    }
    #expect(
        throws: MeasurementModelError.incompatibleValueShapeForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "displacement",
            value: .scalar(1),
            unit: .meter,
            endpointCount: 2
        )
    }
    // Environmental quantities never take spatial endpoints (#253).
    #expect(
        throws: MeasurementModelError.invalidEndpointCountForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "air_temperature",
            value: .scalar(20),
            unit: .degreeCelsius,
            endpointCount: 2
        )
    }
    // Exactly-2 quantities reject a single dangling endpoint.
    #expect(
        throws: MeasurementModelError.invalidEndpointCountForQuantity
    ) {
        try MeasurementQuantityRegistry.validate(
            quantityType: "speaker_distance",
            value: .scalar(3),
            unit: .meter,
            endpointCount: 1
        )
    }
}

@Test
func customQuantitiesPassRegistryWithDeclaredUnit() throws {
    // #344: custom quantities remain possible but must carry the
    // reserved x_ namespace so they can never collide with future
    // standard vocabulary.
    try MeasurementQuantityRegistry.validate(
        quantityType: "x_panel_thickness",
        value: .scalar(0.02),
        unit: .meter,
        endpointCount: 0
    )
    #expect(
        MeasurementQuantityRegistry.definition(for: "x_panel_thickness")
            == nil
    )
    #expect(MeasurementQuantityRegistry.version == "1.1.0")
}

// MARK: - Manufacturer source authority (#275)

@Test
func sourceAuthorityRequiresAtLeastOneField() {
    #expect(throws: MeasurementModelError.emptySourceAuthority) {
        try MeasurementSourceAuthority()
    }
}

@Test
func sourceAuthorityIsRejectedOnNonManufacturerMethods() throws {
    let source = try MeasurementSourceAuthority(
        documentRef: "vendor-datasheet",
        documentRevision: "rev-c",
        propertyKey: "cabinet_height"
    )
    #expect(
        throws: MeasurementModelError
            .sourceAuthorityRequiresManufacturerSpecification
    ) {
        try ManualAuthorityBuilder.measurement(
            quantityType: "cabinet_height",
            value: .scalar(0.9),
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            sourceAuthority: source
        )
    }
}

@Test
func manufacturerSpecCarriesExactSourceAuthority() throws {
    let measurement = try ManualAuthorityBuilder.measurement(
        quantityType: "cabinet_height",
        value: .scalar(0.9),
        unit: .meter,
        acquisitionMethod: .manufacturerSpecification,
        instrument: MeasurementInstrument(
            instrumentClass: "not-a-source"
        ),
        sourceValueText: "35.4 in",
        sourceAuthority: MeasurementSourceAuthority(
            documentRef: "vendor-spec-sheet",
            documentRevision: "2026-03",
            propertyKey: "cabinet_height"
        )
    )

    #expect(
        measurement.sourceAuthority?.documentRef == "vendor-spec-sheet"
    )
    #expect(measurement.sourceAuthority?.documentRevision == "2026-03")
    #expect(measurement.sourceAuthority?.propertyKey == "cabinet_height")
    #expect(measurement.userAttestation == .attested)
    #expect(
        measurement.provenanceClass == .userAttestedMeasurement
    )

    // Round-trip through the wire codec preserves the structured source.
    let data = try JSONEncoder().encode(measurement)
    let decoded = try JSONDecoder().decode(
        CaptureMeasurement.self,
        from: data
    )
    #expect(decoded == measurement)

    let json = try #require(
        String(data: data, encoding: .utf8)
    )
    #expect(json.contains("\"source_authority\""))
    #expect(json.contains("\"document_ref\":\"vendor-spec-sheet\""))
}

// MARK: - Observation time / provenance (#238)

@Test
func observationAndCalibrationMetadataPersist() throws {
    let measurement = try ManualAuthorityBuilder.measurement(
        quantityType: "air_temperature",
        value: .scalar(21.5),
        unit: .degreeCelsius,
        acquisitionMethod: .externalInstrument,
        instrument: MeasurementInstrument(
            instrumentClass: "thermohygrometer",
            makeModel: "Acme TH-1",
            calibrationStatus: "calibrated",
            calibrationDate: "2026-01-15"
        ),
        observedAtUTC: "2026-09-21T10:15:00Z"
    )

    #expect(measurement.observedAtUTC == "2026-09-21T10:15:00Z")
    #expect(
        measurement.instrument?.calibrationStatus == "calibrated"
    )
    #expect(measurement.instrument?.calibrationDate == "2026-01-15")
    #expect(measurement.acquisitionMethod == .externalInstrument)
}

@Test
func invalidObservationAndCalibrationTimestampsThrow() {
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        try ManualAuthorityBuilder.measurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .other,
            observedAtUTC: "2026-09-21 10:15:00"
        )
    }
    #expect(throws: MeasurementModelError.invalidCalibrationDate) {
        try ManualAuthorityBuilder.measurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .other,
            instrument: MeasurementInstrument(
                calibrationDate: "15/01/2026"
            )
        )
    }
}

// MARK: - Endpoint binding (#215)

@Test
func manualMeasurementBindsEndpointsAndCoordinateSpace() throws {
    let space = testSpace()
    let a = try testEntity(x: 0, z: 0, label: "wall-a")
    let b = try testEntity(x: 4, z: 0, label: "wall-b")

    let measurement = try ManualAuthorityBuilder.measurement(
        quantityType: "room_width",
        value: .scalar(4.0),
        unit: .meter,
        acquisitionMethod: .laserDistanceMeter,
        coordinateSpaceID: space,
        endpointRefs: [
            "entity:" + a.entityID.description,
            "entity:" + b.entityID.description,
        ]
    )

    // Endpoint-bound + typed-in value: stays user-attested (issue #215).
    #expect(measurement.coordinateSpaceID == space)
    #expect(measurement.endpointRefs.count == 2)
    #expect(measurement.provenanceClass == .userAttestedMeasurement)
    #expect(measurement.userAttestation == .attested)
}

@Test
func endpointRefsRequireCoordinateSpace() {
    #expect(
        throws: MeasurementModelError.missingSpatialCoordinateAuthority
    ) {
        try ManualAuthorityBuilder.measurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .other,
            endpointRefs: ["entity:deadbeef-dead-4ead-8ead-000000000001"]
        )
    }
}

@Test
func manualBuilderRejectsDerivedMethods() {
    #expect(
        throws: ManualAuthorityBuilderError
            .derivedAcquisitionNotUserAttestable
    ) {
        try ManualAuthorityBuilder.measurement(
            quantityType: "room_width",
            value: .scalar(4),
            unit: .meter,
            acquisitionMethod: .roomPlanDerived
        )
    }
}

// MARK: - Vector authoring (#270)

@Test
func manualVectorMeasurementPersistsCoordinateSpace() throws {
    let measurement = try ManualAuthorityBuilder.measurement(
        quantityType: "surveyed_offset",
        value: .vector3(0.5, 0, -1.2),
        unit: .meter,
        acquisitionMethod: .other,
        coordinateSpaceID: testSpace()
    )
    guard case let .vector3(x, y, z) = measurement.value else {
        Issue.record("expected vector3 value")
        return
    }
    #expect(x == 0.5 && y == 0 && z == -1.2)
    #expect(measurement.coordinateSpaceID != nil)
}

// MARK: - Derived measurements (#286)

@Test
func derivedDistanceFromRoomPlanEndpointsIsRoomPlanAuthority() throws {
    let a = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 0, placementMethod: .roomPlanBinding)
    )
    let b = try MeasurementEndpointAuthority(
        entity: testEntity(
            x: 3,
            z: 4,
            placementMethod: .roomPlanBinding
        )
    )

    let measurement = try DerivedMeasurementBuilder.distance(
        endpointA: a,
        endpointB: b,
        coordinateSpaceID: testSpace()
    )

    #expect(measurement.acquisitionMethod == .roomPlanDerived)
    #expect(
        measurement.provenanceClass == .appleRoomPlanInference
    )
    #expect(measurement.userAttestation == .notAttested)
    #expect(measurement.derivation?.algorithm
        == "endpoint_euclidean_distance")
    #expect(measurement.derivation?.algorithmVersion == "1.0.0")
    #expect(measurement.endpointRefs.count == 2)
    guard case let .scalar(distance) = measurement.value else {
        Issue.record("expected scalar value")
        return
    }
    #expect(abs(distance - 5.0) < 1e-9)
    #expect(measurement.derivation != nil)
    #expect(
        Set(measurement.derivation?.sourceRefs ?? []).count
            == measurement.derivation?.sourceRefs.count
    )
}

@Test
func derivedDistanceFromMeshEndpointsIsLidarAuthority() throws {
    let a = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 0, placementMethod: .raycast)
    )
    let b = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 2, placementMethod: .meshHitTest)
    )

    let measurement = try DerivedMeasurementBuilder.distance(
        endpointA: a,
        endpointB: b,
        coordinateSpaceID: testSpace()
    )

    #expect(measurement.acquisitionMethod == .lidarDerived)
    #expect(
        measurement.provenanceClass == .arkitMeshReconstruction
    )
}

@Test
func derivedValueFromManualOrMixedEndpointsIsAppDerived() throws {
    let manual = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 0)
    )
    let meshBound = try MeasurementEndpointAuthority(
        entity: testEntity(x: 1, z: 0, placementMethod: .raycast)
    )
    let otherManual = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 1)
    )

    let mixed = try DerivedMeasurementBuilder.distance(
        endpointA: manual,
        endpointB: meshBound,
        coordinateSpaceID: testSpace()
    )
    #expect(mixed.acquisitionMethod == .other)
    #expect(mixed.provenanceClass == .captureAppDerived)
    #expect(mixed.derivation != nil)

    let bothManual = try DerivedMeasurementBuilder.distance(
        endpointA: manual,
        endpointB: otherManual,
        coordinateSpaceID: testSpace()
    )
    #expect(bothManual.acquisitionMethod == .other)
    #expect(bothManual.provenanceClass == .captureAppDerived)
}

@Test
func derivedDisplacementIsVectorWithEndpointRefs() throws {
    let a = try MeasurementEndpointAuthority(
        entity: testEntity(x: 1, z: 1, placementMethod: .roomPlanBinding)
    )
    let b = try MeasurementEndpointAuthority(
        entity: testEntity(x: 3, z: 5, placementMethod: .roomPlanBinding)
    )

    let measurement = try DerivedMeasurementBuilder.displacement(
        endpointA: a,
        endpointB: b,
        coordinateSpaceID: testSpace()
    )
    guard case let .vector3(x, y, z) = measurement.value else {
        Issue.record("expected vector3 value")
        return
    }
    #expect(x == 2 && y == 0 && z == 4)
    #expect(measurement.coordinateSpaceID == testSpace())
    #expect(measurement.endpointRefs.count == 2)
    #expect(
        measurement.derivation?.algorithm
            == "endpoint_displacement_vector"
    )
}

@Test
func derivedBuilderRejectsSameEndpointTwice() throws {
    let entity = try testEntity(x: 0, z: 0)
    let endpoint = try MeasurementEndpointAuthority(entity: entity)
    #expect(
        throws: MeasurementModelError.duplicateEndpointReference
    ) {
        try DerivedMeasurementBuilder.distance(
            endpointA: endpoint,
            endpointB: endpoint,
            coordinateSpaceID: testSpace()
        )
    }
}

// MARK: - Provenance mapping invariants (#286)

@Test
func provenanceMappingIsEnforcedAtConstruction() {
    // roomplan_derived must carry apple_roomplan_inference.
    #expect(throws: MeasurementModelError.derivedProvenanceMismatch) {
        try CaptureMeasurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .roomPlanDerived,
            userAttestation: .notAttested,
            provenanceClass: .arkitMeshReconstruction
        )
    }
    // capture_app_derived requires derivation lineage and .other method.
    #expect(throws: MeasurementModelError.missingDerivationAuthority) {
        try CaptureMeasurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .other,
            userAttestation: .notAttested,
            provenanceClass: .captureAppDerived
        )
    }
    // A derivation block on a user-entered laser value is incoherent.
    #expect(throws: MeasurementModelError.nonDerivedDerivation) {
        try CaptureMeasurement(
            quantityType: "custom_q",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            userAttestation: .notAttested,
            provenanceClass: .importedReference,
            derivation: MeasurementDerivation(
                algorithm: "endpoint_euclidean_distance",
                algorithmVersion: "1.0.0",
                sourceRefs: ["entity:deadbeef-dead-4ead-8ead-000000000001"]
            )
        )
    }
}

// MARK: - Measurement point entity (#271)

@Test
func measurementPointCarriesMicrophoneCapsuleSemanticsAndFullOrientation()
    throws
{
    let space = testSpace()
    let orientation = try AnnotationOrientationAuthority(
        orientation: OrientationAxes(
            frontAxisLocal: .unit(0, -0.5, -0.866),
            upAxisLocal: .unit(0, 0.866, -0.5)
        ),
        coordinateSpaceID: space,
        evidenceRefs: ["path:evidence/frames/abc/descriptor.json"]
    )

    let point = try ManualAuthorityBuilder.annotation(
        type: .measurementPoint,
        label: "mic-pos-1",
        xMeters: 0,
        yMeters: 1.1,
        zMeters: 2.0,
        coordinateSpaceID: space,
        orientationAuthority: orientation
    )

    #expect(point.type == .measurementPoint)
    #expect(point.referencePointSemantics == .microphoneCapsule)
    // Full 3D direction is retained, never flattened to a heading.
    let front = try #require(point.orientation).frontAxisLocal
    #expect(abs(front.y - -0.5) < 0.001)
    #expect(abs(front.z - -0.866) < 0.001)
    #expect(point.channelRole == nil)
    #expect(point.verificationState == .evidenceLinked)
    #expect(
        point.evidenceRefs.contains(
            "path:evidence/frames/abc/descriptor.json"
        )
    )
}

@Test
func measurementPointWorksWithoutDirectionCapture() throws {
    let point = try ManualAuthorityBuilder.annotation(
        type: .measurementPoint,
        label: "mic-pos-2",
        xMeters: 0,
        yMeters: 1.0,
        zMeters: 0,
        coordinateSpaceID: testSpace()
    )
    #expect(point.orientation == nil)
    #expect(point.verificationState == .userAttested)
    #expect(point.referencePointSemantics == .microphoneCapsule)
}

@Test
func purePointTypesStillRejectOrientationAuthority() throws {
    let space = testSpace()
    let orientation = try AnnotationOrientationAuthority(
        orientation: OrientationAxes(
            frontAxisLocal: .unit(1, 0, 0),
            upAxisLocal: .unit(0, 1, 0)
        ),
        coordinateSpaceID: space,
        evidenceRefs: ["path:evidence/frames/abc/descriptor.json"]
    )
    #expect(
        throws: ManualAuthorityBuilderError
            .orientationNotSupportedForType
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .referencePoint,
            label: "ref-1",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            orientationAuthority: orientation
        )
    }
}

// MARK: - Schema conformance (#269, #275, #286)

@Test
func extendedMeasurementsValidateAgainstEmbeddedSchema() throws {
    let space = testSpace()
    let manual = try ManualAuthorityBuilder.measurement(
        quantityType: "air_temperature",
        value: .scalar(21.5),
        unit: .degreeCelsius,
        acquisitionMethod: .externalInstrument,
        instrument: MeasurementInstrument(
            instrumentClass: "thermohygrometer",
            calibrationStatus: "calibrated",
            calibrationDate: "2026-01-15"
        ),
        observedAtUTC: "2026-09-21T10:15:00Z",
        sourceValueText: "68.7 degF"
    )
    let spec = try ManualAuthorityBuilder.measurement(
        quantityType: "cabinet_height",
        value: .scalar(0.9),
        unit: .meter,
        acquisitionMethod: .manufacturerSpecification,
        sourceValueText: "35.4 in",
        sourceAuthority: MeasurementSourceAuthority(
            documentRef: "vendor-spec-sheet",
            documentRevision: "2026-03",
            propertyKey: "cabinet_height",
            sourceSHA256: EvidenceSHA256(
                String(repeating: "ab", count: 32)
            )
        )
    )
    let a = try MeasurementEndpointAuthority(
        entity: testEntity(x: 0, z: 0, placementMethod: .roomPlanBinding)
    )
    let b = try MeasurementEndpointAuthority(
        entity: testEntity(x: 3, z: 4, placementMethod: .roomPlanBinding)
    )
    let derived = try DerivedMeasurementBuilder.distance(
        endpointA: a,
        endpointB: b,
        coordinateSpaceID: space,
        observedAtUTC: "2026-09-21T10:16:00Z"
    )

    let package = try MeasurementEvidencePackageBuilder.build(
        measurements: [manual, spec, derived]
    )
    // The embedded schema registry must accept the extended records:
    // new units, external_instrument, capture_app_derived provenance,
    // source_authority, and derivation all pass contract validation.
    _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
        path: MeasurementEvidencePackage.path,
        data: package.data
    )
}

@Test
func measurementPointEntityValidatesAgainstEmbeddedSchema() throws {
    let space = testSpace()
    let orientation = try AnnotationOrientationAuthority(
        orientation: OrientationAxes(
            frontAxisLocal: .unit(0, -0.5, -0.866),
            upAxisLocal: .unit(0, 0.866, -0.5)
        ),
        coordinateSpaceID: space,
        evidenceRefs: ["path:evidence/frames/abc/descriptor.json"]
    )
    let point = try ManualAuthorityBuilder.annotation(
        type: .measurementPoint,
        label: "mic-pos-1",
        xMeters: 0,
        yMeters: 1.1,
        zMeters: 2.0,
        coordinateSpaceID: space,
        orientationAuthority: orientation
    )
    let package = try AnnotationEvidencePackageBuilder.build(
        entities: [point]
    )
    _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
        path: AnnotationEvidencePackage.path,
        data: package.data
    )
}
