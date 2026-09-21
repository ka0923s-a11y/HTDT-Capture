import Foundation
import Testing
@testable import HTDTCaptureCore

// annotation_contract cluster: #230 physical-entity authority,
// #237 equipment-ref compatibility, #243 listening-position roles,
// #244 subwoofer channel/orientation, #258 spatial uncertainty,
// #263 per-component authority, #267 lifecycle metadata,
// #291 reference-point construction.

private func makeSpace() -> CoordinateSpaceID { CoordinateSpaceID() }

private func makeEquipmentReference(
    authorityVersion: String? =
        HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion
) throws -> HTDTEquipmentReference {
    try HTDTEquipmentReference(
        equipmentID: "amp-1",
        equipmentVersion: "1.0.0",
        equipmentHash: EvidenceSHA256(
            String(repeating: "ab", count: 32)
        ),
        authorityVersion: authorityVersion
    )
}

private func makeRaycastAuthority(
    in space: CoordinateSpaceID,
    evidence: String = "path:evidence/frames/a.json"
) throws -> AnnotationPlacementAuthority {
    try AnnotationPlacementAuthority(
        worldFromAnnotation: .identity,
        placement: try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: [evidence]
        ),
        coordinateSpaceID: space,
        evidenceRefs: [evidence]
    )
}

// MARK: - #267 lifecycle metadata

@Test
func builderAlwaysStampsCreationTime() throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let entity = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "R",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: makeSpace(),
        createdAt: createdAt
    )
    #expect(entity.lifecycle?.createdAtUTC == "2023-11-14T22:13:20Z")
    #expect(entity.lifecycle?.updatedAtUTC == nil)
    #expect(entity.lifecycle?.observedAtUTC == nil)
}

@Test
func revisionKeepsIdentityAndStampsUpdated() throws {
    let entity = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "R",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: makeSpace(),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let revised = try entity.revised(at: "2023-11-15T00:00:00Z")
    #expect(revised.entityID == entity.entityID)
    #expect(revised.lifecycle?.createdAtUTC
                == entity.lifecycle?.createdAtUTC)
    #expect(revised.lifecycle?.updatedAtUTC == "2023-11-15T00:00:00Z")
}

@Test
func packageBuilderStampsUpdatedOnlyForChangedEntities() throws {
    let space = makeSpace()
    let unchanged = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "Kept",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let edited = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "Old",
        xMeters: 1,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    var editedCopy = edited
    editedCopy = try CaptureAnnotationEntity(
        entityID: edited.entityID,
        type: edited.type,
        coordinateSpaceID: edited.coordinateSpaceID,
        worldFromAnnotation: edited.worldFromAnnotation,
        referencePointSemantics: edited.referencePointSemantics,
        label: "New label",
        placement: edited.placement,
        lifecycle: edited.lifecycle
    )

    let now = Date(timeIntervalSince1970: 1_700_100_000)
    let package = try AnnotationEvidencePackageBuilder.build(
        entities: [unchanged, editedCopy],
        priorEntities: [unchanged, edited],
        revisedAt: now
    )
    let byID = Dictionary(
        package.collection.entities.map { ($0.entityID, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    #expect(byID[unchanged.entityID]?.lifecycle?.updatedAtUTC == nil)
    #expect(
        byID[edited.entityID]?.lifecycle?.updatedAtUTC
            == BundleTimestamp.utcString(from: now)
    )
    #expect(byID[edited.entityID]?.lifecycle?.createdAtUTC
                == edited.lifecycle?.createdAtUTC)
}

@Test
func legacyEntityWithoutLifecycleDecodes() throws {
    let json = """
        {"entity_id":"30000000-0000-4000-8000-0000000000aa",\
        "type":"reference_point",\
        "coordinate_space_id":"30000000-0000-4000-8000-0000000000bb",\
        "T_world_from_annotation":{"representation":\
        "column_major_4x4_f32","values":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},\
        "reference_point_semantics":"user_reference_point",\
        "label":"legacy","provenance_class":"user_annotation",\
        "verification_state":"unverified",\
        "placement":{"method":"manual_numeric","source_evidence_refs":[],\
        "source_mesh_anchor_id":null,"source_roomplan_object_id":null,\
        "source_semantic_entity_id":null,"raycast":null},\
        "orientation":null,"channel_role":null,"acoustic_center":null,\
        "equipment_ref":null,"evidence_refs":[]}
        """
    let entity = try JSONDecoder().decode(
        CaptureAnnotationEntity.self,
        from: Data(json.utf8)
    )
    #expect(entity.lifecycle == nil)
    #expect(entity.authority == nil)
    #expect(entity.listeningRole == nil)
}

@Test
func lifecycleRejectsMalformedTimestamps() {
    #expect(throws: AnnotationModelError.invalidTimestamp) {
        _ = try AnnotationLifecycle(createdAtUTC: "not a time")
    }
    #expect(throws: AnnotationModelError.invalidTimestamp) {
        _ = try AnnotationLifecycle(
            createdAtUTC: "2023-11-14T22:13:20Z",
            observedAtUTC: "2023-11-14 22:13:20"
        )
    }
}

// MARK: - #243 listening-position roles

@Test
func builderRequiresListeningRoleForListeningPositions() throws {
    #expect(
        throws: ManualAuthorityBuilderError.listeningRoleRequired
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .listeningPosition,
            label: "Seat",
            xMeters: 0,
            yMeters: 0,
            zMeters: 1,
            coordinateSpaceID: makeSpace()
        )
    }
    let seat = try ManualAuthorityBuilder.annotation(
        type: .listeningPosition,
        label: "Seat",
        xMeters: 0,
        yMeters: 0,
        zMeters: 1,
        coordinateSpaceID: makeSpace(),
        listeningRole: .secondary
    )
    #expect(seat.listeningRole == .secondary)
    #expect(seat.authority?.semanticRole?.state == .userAttested)
}

@Test
func listeningRoleRejectedOnOtherTypes() throws {
    #expect(
        throws: AnnotationModelError.incompatibleListeningRole
    ) {
        try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: makeSpace(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "x",
            placement: try PlacementProvenance(method: .manualNumeric),
            listeningRole: .primary
        )
    }
}

@Test
func reviewFlagsDuplicatePrimaryAndMissingRole() throws {
    let space = makeSpace()
    func listening(
        _ label: String,
        role: ListeningPositionRole?
    ) throws -> CaptureAnnotationEntity {
        try ManualAuthorityBuilder.annotation(
            type: .listeningPosition,
            label: label,
            xMeters: 0,
            yMeters: 0,
            zMeters: 1,
            coordinateSpaceID: space,
            listeningRole: role ?? .primary
        )
    }
    var legacy = try listening("Legacy seat", role: .primary)
    // Emulate a pre-role record by clearing the field through init.
    legacy = try CaptureAnnotationEntity(
        entityID: legacy.entityID,
        type: legacy.type,
        coordinateSpaceID: legacy.coordinateSpaceID,
        worldFromAnnotation: legacy.worldFromAnnotation,
        referencePointSemantics: legacy.referencePointSemantics,
        label: legacy.label,
        placement: legacy.placement
    )
    let findings = AnnotationContractReview.findings(in: [
        try listening("MLP", role: .primary),
        try listening("Seat 2", role: .primary),
        legacy,
    ])
    #expect(findings.contains {
        $0.code == .duplicatePrimaryListeningPosition
            && $0.severity == .warning
    })
    #expect(findings.contains {
        $0.code == .listeningRoleMissing
            && $0.entityID == legacy.entityID
    })
}

// MARK: - #244 subwoofer channel role + orientation

@Test
func subwooferRequiresChannelRoleAndAcceptsOrientation() throws {
    let space = makeSpace()
    #expect(
        throws: ManualAuthorityBuilderError
            .invalidSubwooferChannelRole
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .subwoofer,
            label: "Sub",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space
        )
    }
    let sub = try ManualAuthorityBuilder.annotation(
        type: .subwoofer,
        label: "Sub 1",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        subwooferChannelRole: "lfe1",
        orientationYawDegrees: 45
    )
    #expect(sub.channelRole == .lfe1)
    #expect(sub.orientation != nil)
    #expect(abs(sub.orientation!.frontAxisLocal.x - 0.707) < 0.01)
}

@Test
func reviewFlagsDuplicateChannelRoles() throws {
    let space = makeSpace()
    func sub(_ label: String) throws -> CaptureAnnotationEntity {
        try ManualAuthorityBuilder.annotation(
            type: .subwoofer,
            label: label,
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            subwooferChannelRole: "LFE1"
        )
    }
    let findings = AnnotationContractReview.findings(in: [
        try sub("Sub A"),
        try sub("Sub B"),
    ])
    #expect(findings.contains {
        $0.code == .duplicateChannelRole && $0.severity == .warning
    })
}

// MARK: - #258 spatial uncertainty

@Test
func uncertaintyRequiresAtLeastOneFiniteComponent() throws {
    #expect(throws: AnnotationModelError.invalidUncertainty) {
        _ = try SpatialUncertaintyAuthority(basis: .userStated)
    }
    #expect(throws: AnnotationModelError.invalidUncertainty) {
        _ = try SpatialUncertaintyAuthority(
            isotropicMeters: -0.5,
            basis: .userStated
        )
    }
    let uncertainty = try SpatialUncertaintyAuthority(
        isotropicMeters: 0.05,
        angularRadians: 0.02,
        basis: .instrumentStated,
        sourceEvidenceRefs: ["path:evidence/instrument/spec.json"]
    )
    let entity = try ManualAuthorityBuilder.annotation(
        type: .referencePoint,
        label: "Measured",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: makeSpace(),
        uncertainty: uncertainty
    )
    #expect(entity.uncertainty?.isotropicMeters == 0.05)
    #expect(entity.contractEvidenceRefs
                == ["path:evidence/instrument/spec.json"])
}

// MARK: - #263 per-component authority

@Test
func componentAuthorityTracksEachFieldIndependently() throws {
    let space = makeSpace()
    let evidence = "path:evidence/frames/b.json"
    let entity = try ManualAuthorityBuilder.annotation(
        type: .speaker,
        label: "Mixed",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        speakerChannelRole: "C",
        speakerYawDegrees: 30,
        referencePointConstruction: .surfaceHitConfirmed,
        equipmentReference: makeEquipmentReference(),
        placementAuthority: makeRaycastAuthority(
            in: space,
            evidence: evidence
        )
    )
    let authority = try #require(entity.authority)
    // Placement is evidence-backed; yaw-entered orientation, the
    // catalog-selected equipment ref and the typed role are not
    // sensor-verified (#263).
    #expect(authority.placement.state == .evidenceLinked)
    #expect(authority.placement.evidenceRefs == [evidence])
    #expect(authority.orientation?.state == .userAttested)
    #expect(authority.equipment?.state == .userAttested)
    #expect(authority.semanticRole?.state == .userAttested)
    #expect(authority.referencePoint?.state == .evidenceLinked)
    // Aggregate stays the legacy summary.
    #expect(entity.verificationState == .evidenceLinked)
}

@Test
func componentRecordMustMatchPresentFields() throws {
    let space = makeSpace()
    let placement = try AnnotationComponentAuthority(
        state: .userAttested
    )
    #expect(
        throws: AnnotationModelError.invalidAuthorityComponent
    ) {
        try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "x",
            placement: try PlacementProvenance(
                method: .manualNumeric
            ),
            orientation: try OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            authority: AnnotationAuthorityComponents(
                placement: placement
            )
        )
    }
    #expect(throws: AnnotationModelError.missingEvidenceLink) {
        _ = try AnnotationComponentAuthority(state: .evidenceLinked)
    }
}

// MARK: - #230 physical envelope + projector

@Test
func envelopeRequiresPositiveDimensionAndProvenance() throws {
    #expect(throws: AnnotationModelError.invalidEnvelope) {
        _ = try EntityPhysicalEnvelope(provenance: .userMeasured)
    }
    #expect(throws: AnnotationModelError.invalidEnvelope) {
        _ = try EntityPhysicalEnvelope(
            widthMeters: 0,
            provenance: .userMeasured
        )
    }
    let screen = try ManualAuthorityBuilder.annotation(
        type: .projectionScreen,
        label: "Screen",
        xMeters: 0,
        yMeters: 1.2,
        zMeters: 0,
        coordinateSpaceID: makeSpace(),
        orientationYawDegrees: 0,
        physicalEnvelope: try EntityPhysicalEnvelope(
            widthMeters: 2.4,
            heightMeters: 1.05,
            provenance: .userMeasured
        )
    )
    #expect(screen.physicalEnvelope?.widthMeters == 2.4)
    #expect(screen.physicalEnvelope?.provenance == .userMeasured)
    #expect(screen.orientation != nil)
}

@Test
func projectorIsFirstClassWithLensSemantics() throws {
    let projector = try ManualAuthorityBuilder.annotation(
        type: .projector,
        label: "PJ",
        xMeters: 0,
        yMeters: 2.2,
        zMeters: 3.0,
        coordinateSpaceID: makeSpace(),
        orientationYawDegrees: 180,
        referencePointSemantics: .projectorLensCenter
    )
    #expect(projector.type == .projector)
    #expect(projector.referencePointSemantics
                == .projectorLensCenter)
    #expect(projector.referencePointSemantics
                != .projectorBodyReference)

    #expect(
        throws: AnnotationModelError.invalidReferencePointSemantics
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .projector,
            label: "PJ",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: makeSpace(),
            referencePointSemantics: .earCenter
        )
    }
}

// MARK: - #237 equipment-reference compatibility

@Test
func equipmentReferenceOnlyAttachesToCompatibleTypes() throws {
    let space = makeSpace()
    let reference = try makeEquipmentReference()
    // Speaker/subwoofer attach fine.
    _ = try ManualAuthorityBuilder.annotation(
        type: .subwoofer,
        label: "Sub",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        subwooferChannelRole: "LFE2",
        equipmentReference: reference
    )
    #expect(
        throws: AnnotationModelError.incompatibleEquipmentReference
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .listeningPosition,
            label: "MLP",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            listeningRole: .primary,
            equipmentReference: reference
        )
    }
    #expect(
        throws: AnnotationModelError.unknownEquipmentAuthority
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: "L",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            speakerYawDegrees: 0,
            equipmentReference: makeEquipmentReference(
                authorityVersion: "future-catalog-9"
            )
        )
    }
}

@Test
func legacyEquipmentRefsStayReadableAndFlagged() throws {
    let legacy = try HTDTEquipmentReference(
        equipmentID: "amp-1",
        equipmentVersion: "1.0.0",
        equipmentHash: EvidenceSHA256(String(repeating: "cd", count: 32))
    )
    #expect(legacy.authorityVersion == nil)
    #expect(legacy.resolvedAuthorityVersion
                == HTDTEquipmentCatalogSnapshot
                    .expectedAuthorityVersion)
    // A legacy tuple on an incompatible type decodes but is surfaced
    // by review, never silently ignored.
    let entity = try CaptureAnnotationEntity(
        type: .referencePoint,
        coordinateSpaceID: makeSpace(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .userReferencePoint,
        label: "x",
        placement: try PlacementProvenance(method: .manualNumeric),
        equipmentRef: legacy
    )
    #expect(entity.equipmentCompatibility == .incompatible)
    #expect(AnnotationContractReview.findings(in: [entity]).contains {
        $0.code == .incompatibleEquipmentReference
            && $0.severity == .error
    })
}

// MARK: - #291 reference-point construction

@Test
func capturedPlacementRequiresExplicitConstruction() throws {
    let space = makeSpace()
    let authority = try makeRaycastAuthority(in: space)
    #expect(
        throws: ManualAuthorityBuilderError
            .referencePointConstructionRequired
    ) {
        try ManualAuthorityBuilder.annotation(
            type: .listeningPosition,
            label: "MLP",
            xMeters: 0,
            yMeters: 0,
            zMeters: 0,
            coordinateSpaceID: space,
            listeningRole: .primary,
            placementAuthority: authority
        )
    }
}

@Test
func offsetFromSurfaceAppliesWorldOffset() throws {
    let space = makeSpace()
    let hit = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0.5, 0.4, 2.0, 1,
    ])
    let authority = try AnnotationPlacementAuthority(
        worldFromAnnotation: hit,
        placement: try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/hit.json"]
        ),
        coordinateSpaceID: space,
        evidenceRefs: ["path:evidence/frames/hit.json"]
    )
    let mlp = try ManualAuthorityBuilder.annotation(
        type: .listeningPosition,
        label: "MLP",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        listeningRole: .primary,
        referencePointConstruction: .offsetFromSurface,
        referencePointOffset: try SpatialVector3F(0, 1.1, 0),
        placementAuthority: authority
    )
    #expect(abs(mlp.worldFromAnnotation.values[13] - 1.5) < 0.001)
    #expect(mlp.referencePoint?.construction == .offsetFromSurface)
    #expect(mlp.referencePoint?.offsetMeters?.y == 1.1)
    #expect(mlp.referencePoint?.sourceEvidenceRefs
                == ["path:evidence/frames/hit.json"])
}

@Test
func constructionMustMatchPlacementMethod() throws {
    let space = makeSpace()
    let manual = try PlacementProvenance(method: .manualNumeric)
    // A surface construction on a manual placement is incoherent.
    #expect(
        throws: AnnotationModelError.invalidReferencePointAuthority
    ) {
        try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "x",
            placement: manual,
            referencePoint: try ReferencePointAuthority(
                construction: .surfaceHitConfirmed
            )
        )
    }
    // `direct_placement` on a surface-derived placement is likewise
    // rejected — the hit is not inherently the semantic point.
    #expect(
        throws: AnnotationModelError.invalidReferencePointAuthority
    ) {
        try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "x",
            placement: try PlacementProvenance(
                method: .raycast,
                sourceEvidenceRefs: ["path:evidence/frames/c.json"]
            ),
            referencePoint: try ReferencePointAuthority(
                construction: .directPlacement
            )
        )
    }
    // Offset is only valid for the offset construction.
    #expect(
        throws: AnnotationModelError.invalidReferencePointAuthority
    ) {
        _ = try ReferencePointAuthority(
            construction: .surfaceHitConfirmed,
            offsetMeters: try SpatialVector3F(0, 1, 0)
        )
    }
}

@Test
func contractEvidenceRefsFeedCongruence() throws {
    let space = makeSpace()
    let entity = try ManualAuthorityBuilder.annotation(
        type: .subwoofer,
        label: "Sub",
        xMeters: 0,
        yMeters: 0,
        zMeters: 0,
        coordinateSpaceID: space,
        subwooferChannelRole: "LFE1",
        physicalEnvelope: try EntityPhysicalEnvelope(
            widthMeters: 0.4,
            provenance: .other,
            sourceEvidenceRefs: ["path:evidence/manual/tape.json"]
        ),
        uncertainty: try SpatialUncertaintyAuthority(
            isotropicMeters: 0.03,
            basis: .userStated,
            sourceEvidenceRefs: ["path:evidence/manual/tape.json"]
        )
    )
    #expect(Set(entity.contractEvidenceRefs).contains(
        "path:evidence/manual/tape.json"
    ))
}
