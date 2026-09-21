import Foundation
import Testing
@testable import HTDTCaptureCore

// #184: `evidence_linked` is a provenance claim and requires at least
// one evidence or placement source reference at construction.

@Test
func evidenceLinkedWithoutAnyReferenceIsRejected() {
    #expect(throws: AnnotationModelError.missingEvidenceLink) {
        _ = try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "orphan",
            verificationState: .evidenceLinked,
            placement: PlacementProvenance(method: .manualNumeric),
            evidenceRefs: []
        )
    }
}

@Test
func evidenceLinkedWithEntityRefsIsAccepted() throws {
    let entity = try CaptureAnnotationEntity(
        type: .referencePoint,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .userReferencePoint,
        label: "linked",
        verificationState: .evidenceLinked,
        placement: PlacementProvenance(method: .manualNumeric),
        evidenceRefs: ["path:evidence/frames/a.json"]
    )
    #expect(entity.verificationState == .evidenceLinked)
}

@Test
func evidenceLinkedWithPlacementSourceRefsIsAccepted() throws {
    let entity = try CaptureAnnotationEntity(
        type: .referencePoint,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .userReferencePoint,
        label: "linked",
        verificationState: .evidenceLinked,
        placement: PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/a.json"]
        )
    )
    #expect(entity.placement.hasSourceReference)
}

@Test
func userAttestedWithoutEvidenceRemainsValid() throws {
    let entity = try CaptureAnnotationEntity(
        type: .seat,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .seatReferencePoint,
        label: "manual",
        verificationState: .userAttested,
        placement: PlacementProvenance(method: .manualNumeric)
    )
    #expect(entity.verificationState == .userAttested)
    #expect(entity.evidenceRefs.isEmpty)
}

@Test
func placementAuthorityRequiresEvidence() throws {
    let transform = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        1, 2, 3, 1,
    ])
    #expect(throws: AnnotationModelError.missingEvidenceLink) {
        _ = try AnnotationPlacementAuthority(
            worldFromAnnotation: transform,
            placement: PlacementProvenance(method: .manualNumeric),
            evidenceRefs: []
        )
    }
    // Placement-level source refs satisfy the claim.
    let authority = try AnnotationPlacementAuthority(
        worldFromAnnotation: transform,
        placement: PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/a.json"]
        ),
        evidenceRefs: []
    )
    #expect(authority.placement.hasSourceReference)
}

@Test
func orientationAuthorityRequiresEvidence() throws {
    let orientation = try OrientationAxes(
        frontAxisLocal: .unit(0, 0, -1),
        upAxisLocal: .unit(0, 1, 0)
    )
    #expect(throws: AnnotationModelError.missingEvidenceLink) {
        _ = try AnnotationOrientationAuthority(
            orientation: orientation,
            evidenceRefs: []
        )
    }
}

@Test
func builderNeverUpgradesEmptyAuthorityToEvidenceLinked() throws {
    // Manual-only annotation stays user-attested.
    let manual = try ManualAuthorityBuilder.annotation(
        type: .seat,
        label: "manual seat",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID()
    )
    #expect(manual.verificationState == .userAttested)

    // Evidence-backed authority produces evidence_linked with refs.
    let ref = "path:evidence/frames/b.json"
    let authority = try AnnotationPlacementAuthority(
        worldFromAnnotation: .identity,
        placement: PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: [ref]
        ),
        evidenceRefs: [ref]
    )
    let linked = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "linked point",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID(),
        placementAuthority: authority
    )
    #expect(linked.verificationState == .evidenceLinked)
    #expect(!linked.evidenceRefs.isEmpty)
}
