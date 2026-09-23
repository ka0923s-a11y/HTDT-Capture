import Foundation
import Testing
@testable import HTDTCaptureCore

// #315 reopened: a physical speaker must permit no logical role
// binding. `role_binding` is the preferred exact vocabulary,
// `channel_role` is optional legacy, and "unbound" is a first-class
// state — never silently assigned a placeholder token.

private func makeSpeaker(
    channelRole: ChannelRole? = nil,
    roleBinding: SpeakerRoleBinding? = nil,
    label: String = "Speaker"
) throws -> CaptureAnnotationEntity {
    try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: label,
        placement: PlacementProvenance(method: .manualNumeric),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: channelRole,
        roleBinding: roleBinding
    )
}

@Test
func unboundSpeakerIsValidAndEncodesNoPlaceholderRole() throws {
    let entity = try makeSpeaker()
    #expect(entity.channelRole == nil)
    #expect(entity.roleBinding == nil)

    let data = try JSONEncoder().encode(entity)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    // No silent placeholder: neither key may carry an invented token.
    #expect(json["channel_role"] == nil
                || json["channel_role"] is NSNull)
    #expect(json["role_binding"] == nil
                || json["role_binding"] is NSNull)
    let decoded = try JSONDecoder().decode(
        CaptureAnnotationEntity.self,
        from: data
    )
    #expect(decoded.channelRole == nil)
    #expect(decoded.roleBinding == nil)
}

@Test
func speakerAimUnknownIsAValidRecord() throws {
    // #228: an un-aimed speaker is position-only evidence — the
    // record is valid and nothing is fabricated.
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Speaker",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    #expect(entity.orientation == nil)
    #expect(entity.authority?.orientation == nil)
}

@Test
func exactRoleBindingResolvesWithoutFindings() throws {
    let profile = SpeakerLayoutProfiles.stereo
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "L"
    )
    let entity = try makeSpeaker(roleBinding: binding)
    if case .resolved = profile.resolve(
        binding: binding,
        entityID: entity.entityID
    ) {
    } else {
        Issue.record("expected resolved binding")
    }
    let findings = AnnotationContractReview.findings(in: [entity])
    #expect(findings.isEmpty)
}

@Test
func legacyChannelRoleOnlyStaysReadable() throws {
    let entity = try makeSpeaker(channelRole: .left)
    let findings = AnnotationContractReview.findings(in: [entity])
    #expect(!findings.contains { $0.code == .speakerRoleUnbound })
}

@Test
func unaimedSpeakerSurfacesInfoFindingNotError() throws {
    // #228: missing aim is a completeness surface, never an
    // invalidation.
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Speaker",
        placement: PlacementProvenance(method: .manualNumeric),
        channelRole: .left
    )
    let findings = AnnotationContractReview.findings(in: [entity])
    let missing = try #require(
        findings.first { $0.code == .speakerAimMissing }
    )
    #expect(missing.severity == .info)
}

@Test
func aimedSpeakerHasNoAimMissingFinding() throws {
    let entity = try makeSpeaker()
    let findings = AnnotationContractReview.findings(in: [entity])
    #expect(!findings.contains { $0.code == .speakerAimMissing })
}

@Test
func elevationRoundTripsThroughEncoder() throws {
    // #228: azimuth+elevation aim survives an encode/decode round
    // trip bit-for-bit.
    let axes = try ManualAuthorityBuilder.speakerOrientationAxes(
        azimuthDegrees: 30,
        elevationDegrees: 15
    )
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Atmos",
        placement: PlacementProvenance(method: .manualNumeric),
        orientation: axes
    )
    let data = try JSONEncoder().encode(entity)
    let decoded = try JSONDecoder().decode(
        CaptureAnnotationEntity.self,
        from: data
    )
    #expect(decoded.orientation == axes)
}

@Test
func manualBuilderLeavesUnaimedSpeakerOrientationNil() throws {
    // #228: no azimuth means no synthesized orientation.
    let entity = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Rear right",
        xMeters: 1, yMeters: 0, zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID(),
        speakerChannelRole: "R"
    )
    #expect(entity.orientation == nil)
    #expect(entity.channelRole == .right)
}

@Test
func unboundSpeakerSurfacesInfoFindingNotError() throws {
    let entity = try makeSpeaker()
    let findings = AnnotationContractReview.findings(in: [entity])
    let unbound = try #require(
        findings.first { $0.code == .speakerRoleUnbound }
    )
    #expect(unbound.severity == .info)
}

@Test
func conflictingRoleAndBindingSurfacesWarning() throws {
    let profile = SpeakerLayoutProfiles.stereo
    // channel_role L coexisting with a binding to role R (canonical
    // channel right) is a distinct conflict for Review.
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "R"
    )
    let entity = try makeSpeaker(
        channelRole: .left,
        roleBinding: binding
    )
    let findings = AnnotationContractReview.findings(in: [entity])
    let conflict = try #require(
        findings.first { $0.code == .speakerRoleConflict }
    )
    #expect(conflict.severity == .warning)
}

@Test
func agreeingRoleAndBindingHasNoConflict() throws {
    let profile = SpeakerLayoutProfiles.stereo
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "L"
    )
    let entity = try makeSpeaker(
        channelRole: .left,
        roleBinding: binding
    )
    let findings = AnnotationContractReview.findings(in: [entity])
    #expect(!findings.contains { $0.code == .speakerRoleConflict })
}

@Test
func bindingToUnknownRoleInBuiltinProfileWarns() throws {
    let profile = SpeakerLayoutProfiles.stereo
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "BOGUS"
    )
    let entity = try makeSpeaker(roleBinding: binding)
    let findings = AnnotationContractReview.findings(in: [entity])
    let unknown = try #require(
        findings.first { $0.code == .speakerRoleBindingUnknownRole }
    )
    #expect(unknown.severity == .warning)
}

@Test
func bindingToForeignProfileIsNotFlagged() throws {
    // Custom vocabularies stay deployment-defined — a binding naming
    // a profile outside the builtins is never called unverifiable.
    let binding = try SpeakerRoleBinding(
        profileID: "custom.atmos-layout",
        profileVersion: "9.9.9",
        roleID: "ANYTHING"
    )
    let entity = try makeSpeaker(roleBinding: binding)
    let findings = AnnotationContractReview.findings(in: [entity])
    #expect(findings.isEmpty)
}

@Test
func missionCompletenessReportsMissingRoleWhileEntityStaysValid()
    throws
{
    let profile = CaptureTaskProfile.layoutProfile(
        SpeakerLayoutProfiles.stereo
    )
    let unbound = try makeSpeaker()
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile,
        annotations: [unbound],
        measurements: []
    )
    let roleOutcomes = report.outcomes.filter {
        $0.requirement.match.kind == .annotationRoleBinding
    }
    #expect(!roleOutcomes.isEmpty)
    #expect(roleOutcomes.allSatisfy { $0.status == .missing })
    #expect(report.requiredUnsatisfiedCount > 0)
}

@Test
func manualBuilderAllowsUnboundSpeaker() throws {
    let entity = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Front left",
        xMeters: 1, yMeters: 0, zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID(),
        speakerChannelRole: nil,
        speakerYawDegrees: 45
    )
    #expect(entity.channelRole == nil)
    #expect(entity.orientation != nil)
}

@Test
func manualBuilderTrimsBlankSpeakerRoleToUnbound() throws {
    let entity = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Front left",
        xMeters: 1, yMeters: 0, zMeters: 0,
        coordinateSpaceID: CoordinateSpaceID(),
        speakerChannelRole: "   ",
        speakerYawDegrees: 45
    )
    #expect(entity.channelRole == nil)
}

@Test
func manualBuilderStillRejectsMalformedSpeakerRole() throws {
    #expect(
        throws: ManualAuthorityBuilderError.invalidSpeakerChannelRole
    ) {
        _ = try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: "Front left",
            xMeters: 1, yMeters: 0, zMeters: 0,
            coordinateSpaceID: CoordinateSpaceID(),
            speakerChannelRole: "not a role!",
            speakerYawDegrees: 45
        )
    }
}

@Test
func subwooferStillRequiresChannelRole() throws {
    #expect(
        throws: ManualAuthorityBuilderError.invalidSubwooferChannelRole
    ) {
        _ = try ManualAuthorityBuilder.annotation(
            type: .subwoofer,
            label: "Sub",
            xMeters: 1, yMeters: 0, zMeters: 0,
            coordinateSpaceID: CoordinateSpaceID(),
            subwooferChannelRole: nil
        )
    }
}
