import Foundation
import Testing
@testable import HTDTCaptureCore

// legacy bolph71656-ai/HTDT-Capture#143: a user-attested measurement built through the manual authority
// path must not claim a derived (LiDAR / RoomPlan) acquisition method.

@Test
func manualBuilderRejectsDerivedAcquisitionMethods() {
    #expect(
        throws: ManualAuthorityBuilderError
            .derivedAcquisitionNotUserAttestable
    ) {
        _ = try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "width",
            value: 1.0,
            unit: .meter,
            acquisitionMethod: .lidarDerived
        )
    }
    #expect(
        throws: ManualAuthorityBuilderError
            .derivedAcquisitionNotUserAttestable
    ) {
        _ = try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "width",
            value: 1.0,
            unit: .meter,
            acquisitionMethod: .roomPlanDerived
        )
    }
}

@Test
func manualBuilderAcceptsUserAcquisitionMethods() throws {
    let methods: [MeasurementAcquisitionMethod] = [
        .tapeMeasure,
        .laserDistanceMeter,
        .manufacturerSpecification,
        .other,
    ]
    for method in methods {
        let measurement =
            try ManualAuthorityBuilder.scalarMeasurement(
                quantityType: "width",
                value: 2.0,
                unit: .meter,
                acquisitionMethod: method
            )
        #expect(measurement.acquisitionMethod == method)
        #expect(
            measurement.provenanceClass == .userAttestedMeasurement
        )
        #expect(measurement.userAttestation == .attested)
    }
}

@Test
func modelRejectsUserAttestedDerivedCombination() {
    // Programmatic callers cannot bypass the builder's provenance rule.
    #expect(
        throws: MeasurementModelError
            .derivedAcquisitionNotUserAttestable
    ) {
        _ = try CaptureMeasurement(
            quantityType: "width",
            value: .scalar(1.0),
            unit: .meter,
            acquisitionMethod: .lidarDerived,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
    #expect(
        throws: MeasurementModelError
            .derivedAcquisitionNotUserAttestable
    ) {
        _ = try CaptureMeasurement(
            quantityType: "width",
            value: .scalar(1.0),
            unit: .meter,
            acquisitionMethod: .roomPlanDerived,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
}

@Test
func derivedMethodsRemainRepresentableWithDerivedProvenance() throws {
    let roomPlan = try CaptureMeasurement(
        quantityType: "table_diameter",
        value: .scalar(1.08),
        unit: .meter,
        acquisitionMethod: .roomPlanDerived,
        userAttestation: .notAttested,
        provenanceClass: .appleRoomPlanInference
    )
    #expect(roomPlan.acquisitionMethod == .roomPlanDerived)

    let lidar = try CaptureMeasurement(
        quantityType: "wall_length",
        value: .scalar(4.2),
        unit: .meter,
        acquisitionMethod: .lidarDerived,
        userAttestation: .notAttested,
        provenanceClass: .arkitMeshReconstruction
    )
    #expect(lidar.acquisitionMethod == .lidarDerived)
}
