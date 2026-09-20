import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func manualSpeakerBuilderProducesExplicitPositionOrientationAndRole()
    throws
{
    let space = CoordinateSpaceID(
        rawValue: UUID(
            uuidString:
                "30000000-0000-4000-8000-000000000001"
        )!
    )

    let speaker = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Front Left",
        xMeters: 1.2,
        yMeters: 2.3,
        zMeters: 1.0,
        coordinateSpaceID: space,
        speakerChannelRole: "l",
        speakerYawDegrees: 90
    )

    #expect(speaker.coordinateSpaceID == space)
    #expect(speaker.placement.method == .manualNumeric)
    #expect(speaker.channelRole == .left)
    #expect(abs(speaker.worldFromAnnotation.values[12] - 1.2) < 0.001)
    #expect(abs(speaker.worldFromAnnotation.values[13] - 2.3) < 0.001)
    #expect(abs(speaker.worldFromAnnotation.values[14] - 1.0) < 0.001)
    let front = try #require(speaker.orientation).frontAxisLocal
    #expect(abs(front.x - 1) < 0.001)
    #expect(abs(front.y) < 0.001)
    #expect(abs(front.z) < 0.001)
}

@Test
func manualNonSpeakerDoesNotInventSpeakerSemantics() throws {
    let entity = try ManualAuthorityBuilder.annotation(
        type: .listeningPosition,
        label: "MLP",
        xMeters: 0,
        yMeters: 0,
        zMeters: 1.1,
        coordinateSpaceID: CoordinateSpaceID()
    )

    #expect(entity.referencePointSemantics == .earCenter)
    #expect(entity.orientation == nil)
    #expect(entity.channelRole == nil)
}

@Test
func manualScalarMeasurementRemainsUserAttested() throws {
    let measurement =
        try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "room_width",
            value: 3.42,
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            statedUncertainty: 0.002,
            sourceValueText: "3.420 m"
        )

    #expect(measurement.value == .scalar(3.42))
    #expect(measurement.userAttestation == .attested)
    #expect(
        measurement.provenanceClass
            == .userAttestedMeasurement
    )
}
