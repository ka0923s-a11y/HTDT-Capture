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
        coordinateSpaceID: CoordinateSpaceID(),
        listeningRole: .primary
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


@Test
func manualAuthoritiesPreserveSelectedEvidenceReferences() throws {
    let reference =
        "path:evidence/frames/"
        + "30000000-0000-4000-8000-000000000009.json"
    let entity = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "Reference",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID(),
        evidenceRefs: [reference]
    )
    let measurement =
        try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "screen_width",
            value: 2.4,
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            evidenceRefs: [reference]
        )

    #expect(entity.evidenceRefs == [reference])
    #expect(measurement.evidenceRefs == [reference])
}


@Test
func evidenceLinkedRaycastPlacementOverridesManualPosition() throws {
    let reference =
        "path:evidence/frames/"
        + "30000000-0000-4000-8000-000000000010.json"
    let transform = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        4, 5, 6, 1,
    ])
    let space = CoordinateSpaceID()
    let authority = try AnnotationPlacementAuthority(
        worldFromAnnotation: transform,
        placement: try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: [reference]
        ),
        coordinateSpaceID: space,
        evidenceRefs: [reference]
    )

    let entity = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "Raycast point",
        xMeters: 99,
        yMeters: 99,
        zMeters: 99,
        coordinateSpaceID: space,
        referencePointConstruction: .surfaceHitConfirmed,
        placementAuthority: authority
    )

    #expect(entity.worldFromAnnotation == transform)
    #expect(entity.placement.method == .raycast)
    #expect(entity.placement.sourceEvidenceRefs == [reference])
    #expect(entity.evidenceRefs == [reference])
    #expect(entity.verificationState == .evidenceLinked)
}


@Test
func evidenceLinkedSpeakerOrientationOverridesManualYaw() throws {
    let reference =
        "path:evidence/frames/"
        + "30000000-0000-4000-8000-000000000011.json"
    let orientation = try OrientationAxes(
        frontAxisLocal: .unit(0.6, 0, -0.8),
        upAxisLocal: .unit(0, 1, 0)
    )
    let space = CoordinateSpaceID()
    let authority = try AnnotationOrientationAuthority(
        orientation: orientation,
        coordinateSpaceID: space,
        evidenceRefs: [reference]
    )

    let speaker = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Center",
        xMeters: 0,
        yMeters: 0,
        zMeters: 1,
        coordinateSpaceID: space,
        speakerChannelRole: "C",
        speakerYawDegrees: nil,
        orientationAuthority: authority
    )

    #expect(speaker.orientation == orientation)
    #expect(speaker.evidenceRefs == [reference])
    #expect(speaker.verificationState == .evidenceLinked)
}

@Test
func capturedOrientationCannotBeAppliedToNonSpeaker() throws {
    let space = CoordinateSpaceID()
    let authority = try AnnotationOrientationAuthority(
        orientation: try OrientationAxes(
            frontAxisLocal: .unit(0, 0, -1),
            upAxisLocal: .unit(0, 1, 0)
        ),
        coordinateSpaceID: space,
        evidenceRefs: ["path:evidence/frames/example.json"]
    )

    #expect(
        throws: ManualAuthorityBuilderError.orientationNotSupportedForType
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .referencePoint,
            label: "Not a speaker",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            orientationAuthority: authority
        )
    }
}
