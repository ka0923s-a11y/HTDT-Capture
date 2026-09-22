import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Commissioning authorities + mission contract (#316, #335, #346,
/// #359): record invariants, collection cross-reference resolution,
/// descriptor projection, task-plan semantic/evidence fulfillment,
/// and canonical packaging against the updated authorities schema.
final class TheaterCommissioningTests: XCTestCase {
    private let space = CoordinateSpaceID()
    private let utc = "2026-09-22T00:00:00Z"

    private func speakerEntity(
        label: String = "L"
    ) throws -> CaptureAnnotationEntity {
        try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: label,
            xMeters: 1,
            yMeters: 1,
            zMeters: 2,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            speakerYawDegrees: 0
        )
    }

    private func entity(
        type: AnnotationEntityType,
        label: String
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: label,
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(method: .manualNumeric)
        )
    }

    private func routing(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        supersedes: AuthorityRecordID? = nil
    ) throws -> RoutingVerificationAuthority {
        try RoutingVerificationAuthority(
            authorityID: authorityID,
            channelRole: ChannelRole(rawValue: "L"),
            bandScope: .fullRange,
            speakerEntityIDs: [speakerEntity().entityID],
            verificationState: .verified,
            verificationMethod: .listenedTestSignal,
            observedAtUTC: utc,
            supersedesRecordID: supersedes
        )
    }

    // MARK: - #316 routing verification

    func testRoutingRequiresChannelRoleOrLabel() throws {
        XCTAssertThrowsError(
            try RoutingVerificationAuthority(
                bandScope: .fullRange,
                speakerEntityIDs: [speakerEntity().entityID],
                verificationState: .verified,
                verificationMethod: .userAttestation,
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testRoutingRequiresAtLeastOneSpeaker() throws {
        XCTAssertThrowsError(
            try RoutingVerificationAuthority(
                outputLabel: "Front R Pre-Out",
                bandScope: .fullRange,
                speakerEntityIDs: [],
                verificationState: .unknown,
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedEntityReference
            )
        }
    }

    func testRoutingUnknownStateNeedsNoMethod() throws {
        let record = try RoutingVerificationAuthority(
            outputLabel: "Amp ch 3",
            bandScope: .lowBandBassManaged,
            speakerEntityIDs: [speakerEntity().entityID],
            verificationState: .unknown,
            observedAtUTC: utc
        )
        XCTAssertNil(record.verificationMethod)
        XCTAssertEqual(record.bandScope, .lowBandBassManaged)
    }

    func testRoutingNonUnknownStateRequiresMethod() throws {
        XCTAssertThrowsError(
            try RoutingVerificationAuthority(
                channelRole: ChannelRole(rawValue: "LFE1"),
                bandScope: .lowBandBassManaged,
                speakerEntityIDs: [speakerEntity().entityID],
                verificationState: .conflicting,
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testCableLabelEvidenceCannotVerifyLivePath() throws {
        XCTAssertThrowsError(
            try RoutingVerificationAuthority(
                channelRole: ChannelRole(rawValue: "L"),
                bandScope: .fullRange,
                speakerEntityIDs: [speakerEntity().entityID],
                verificationState: .verified,
                verificationMethod: .cableLabelEvidence,
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testRoutingCannotSupersedeItself() throws {
        let id = AuthorityRecordID()
        XCTAssertThrowsError(
            try routing(authorityID: id, supersedes: id)
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedEntityReference
            )
        }
    }

    func testRoutingSupersedesChainResolves() throws {
        let first = try routing()
        let second = try routing(supersedes: first.authorityID)
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [first, second]
        )
        XCTAssertEqual(collection.routingVerifications.count, 2)
    }

    func testRoutingSupersedesMustResolveInCollection() throws {
        let record = try routing(
            supersedes: AuthorityRecordID()
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                routingVerifications: [record]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedFeatureReference
            )
        }
    }

    func testRoutingSourceMustBeAnInventoryItem() throws {
        let item = try SystemInventoryItem(
            equipmentClass: .avReceiver,
            userLabel: "AVR"
        )
        var record = try routing()
        record = try RoutingVerificationAuthority(
            authorityID: record.authorityID,
            channelRole: record.channelRole,
            sourceInventoryItemID: item.itemID,
            bandScope: record.bandScope,
            speakerEntityIDs: record.speakerEntityIDs,
            verificationState: record.verificationState,
            verificationMethod: record.verificationMethod,
            observedAtUTC: utc
        )
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [item],
            routingVerifications: [record]
        )
        XCTAssertEqual(
            collection.routingVerifications.first?
                .sourceInventoryItemID,
            item.itemID
        )
    }

    func testRoutingDanglingSourceRejected() throws {
        let record = try RoutingVerificationAuthority(
            channelRole: ChannelRole(rawValue: "L"),
            sourceInventoryItemID: AuthorityRecordID(),
            bandScope: .fullRange,
            speakerEntityIDs: [speakerEntity().entityID],
            verificationState: .verified,
            verificationMethod: .userAttestation,
            observedAtUTC: utc
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                routingVerifications: [record]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedFeatureReference
            )
        }
    }

    func testRoutingEvidenceRequiresSpace() throws {
        XCTAssertThrowsError(
            try RoutingVerificationAuthority(
                channelRole: ChannelRole(rawValue: "L"),
                bandScope: .fullRange,
                speakerEntityIDs: [speakerEntity().entityID],
                verificationState: .verified,
                verificationMethod: .userAttestation,
                observedAtUTC: utc,
                evidenceRefs: ["ev_1"]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    // MARK: - #335 projector commissioning

    func testLensCenterCannotBeProjectorEntity() throws {
        let projector = try entity(type: .projector, label: "PJ")
        XCTAssertThrowsError(
            try ProjectorCommissioningAuthority(
                projectorEntityID: projector.entityID,
                lensCenterEntityID: projector.entityID,
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedEntityReference
            )
        }
    }

    func testThrowObservationRequiresEndpoints() throws {
        let projector = try entity(type: .projector, label: "PJ")
        XCTAssertThrowsError(
            try ProjectorCommissioningAuthority(
                projectorEntityID: projector.entityID,
                throwObservation: AttestedSettingValue(
                    state: .attested,
                    numericValue: 3.4
                ),
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
        XCTAssertThrowsError(
            try ProjectorCommissioningAuthority(
                projectorEntityID: projector.entityID,
                throwEndpointSemantics:
                    "lens_center_to_screen_aperture",
                observedAtUTC: utc
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testAttestedSettingRequiresAValue() throws {
        XCTAssertThrowsError(
            try AttestedSettingValue(state: .attested)
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testUnknownSettingCarriesNoValue() throws {
        XCTAssertThrowsError(
            try AttestedSettingValue(
                state: .unknown,
                textValue: "Preset 1"
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .invalidPatchGeometry
            )
        }
        let unknown = try AttestedSettingValue(state: .unknown)
        XCTAssertEqual(unknown.state, .unknown)
        XCTAssertNil(unknown.textValue)
        XCTAssertNil(unknown.numericValue)
    }

    func testProjectorScreenLinkMustResolve() throws {
        let projector = try entity(type: .projector, label: "PJ")
        let record = try ProjectorCommissioningAuthority(
            projectorEntityID: projector.entityID,
            screenSemanticsAuthorityID: AuthorityRecordID(),
            observedAtUTC: utc
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                projectorCommissionings: [record]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedFeatureReference
            )
        }
    }

    func testProjectorCommissioningRoundTrips() throws {
        let projector = try entity(type: .projector, label: "PJ")
        let lensCenter = try entity(
            type: .referencePoint,
            label: "lens"
        )
        let record = try ProjectorCommissioningAuthority(
            projectorEntityID: projector.entityID,
            lensCenterEntityID: lensCenter.entityID,
            throwObservation: AttestedSettingValue(
                state: .attested,
                numericValue: 3.4
            ),
            throwEndpointSemantics: "lens_center_to_screen_aperture",
            zoom: AttestedSettingValue(
                state: .attested,
                textValue: "mid-range"
            ),
            lensShiftHorizontal: AttestedSettingValue(
                state: .attested,
                numericValue: -5
            ),
            lensShiftVertical: AttestedSettingValue(
                state: .attested,
                numericValue: 70
            ),
            lensMemoryPreset: .unknown,
            mountOrientation: .ceilingFront,
            focusState: .verified,
            plannedSpecRef: "spec:projector-1",
            deviceContextRef: "settings-profile-A",
            observedAtUTC: utc
        )
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            ProjectorCommissioningAuthority.self,
            from: encoded
        )
        XCTAssertEqual(decoded, record)
    }

    // MARK: - #346 installation alignment

    func testAlignmentRequiresPlannedTarget() throws {
        let speaker = try speakerEntity()
        XCTAssertThrowsError(
            try InstallationAlignmentRecord(
                targetPlannedEntityID: "",
                targetEntityType: .speaker,
                guidanceMode: .textualInstructions,
                precisionSufficiency: .unknown,
                finalEntityID: speaker.entityID,
                observedAtUTC: utc,
                coordinateSpaceID: space
            )
        ) { error in
            XCTAssertEqual(
                error as? AnnotationModelError,
                .emptyAuthorityReference
            )
        }
    }

    func testAlignmentAimCannotEqualFinal() throws {
        let speaker = try speakerEntity()
        XCTAssertThrowsError(
            try InstallationAlignmentRecord(
                targetPlannedEntityID: "planned-L",
                targetEntityType: .speaker,
                aimAtEntityID: speaker.entityID,
                guidanceMode: .textualInstructions,
                precisionSufficiency: .unknown,
                finalEntityID: speaker.entityID,
                observedAtUTC: utc,
                coordinateSpaceID: space
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedEntityReference
            )
        }
    }

    func testSpatialDeltaRequiresProvenAlignment() throws {
        let speaker = try speakerEntity()
        XCTAssertThrowsError(
            try InstallationAlignmentRecord(
                targetPlannedEntityID: "planned-L",
                targetEntityType: .speaker,
                guidanceMode: .spatialDelta,
                precisionSufficiency: .insufficient,
                finalEntityID: speaker.entityID,
                observedAtUTC: utc,
                coordinateSpaceID: space
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testTextualGuidanceWithoutAlignmentRecords() throws {
        let speaker = try speakerEntity()
        let record = try InstallationAlignmentRecord(
            targetPlannedEntityID: "planned-L",
            targetEntityType: .speaker,
            guidanceMode: .textualInstructions,
            precisionSufficiency: .insufficient,
            finalEntityID: speaker.entityID,
            observedAtUTC: utc,
            coordinateSpaceID: space
        )
        XCTAssertNil(record.alignment)
        XCTAssertNil(record.reportedDeviation)
        XCTAssertEqual(
            record.precisionSufficiency, .insufficient
        )
    }

    func testSpatialRecordCarriesDeviation() throws {
        let speaker = try speakerEntity()
        let alignment = try PlanAlignmentAuthority(
            mechanism: .manualSurvey,
            sceneFromCapture: .identity,
            authorityRef: "survey:2026-09-22",
            establishedAtUTC: utc
        )
        let deviation = try AsBuiltDeviation(
            translationScene: try SpatialVector3F(0.1, 0, 0.05),
            distanceMeters: 0.1118
        )
        let record = try InstallationAlignmentRecord(
            targetPlannedEntityID: "planned-L",
            targetEntityType: .speaker,
            guidanceMode: .spatialDelta,
            alignment: alignment,
            precisionSufficiency: .sufficient,
            finalEntityID: speaker.entityID,
            reportedDeviation: deviation,
            observedAtUTC: utc,
            coordinateSpaceID: space,
            evidenceRefs: ["ev_1"]
        )
        XCTAssertEqual(record.reportedDeviation, deviation)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            InstallationAlignmentRecord.self,
            from: encoded
        )
        XCTAssertEqual(decoded, record)
    }

    // MARK: - descriptor projection (#359)

    func testRecordDescriptorsCoverAllSections() throws {
        let speaker = try speakerEntity()
        let projector = try entity(type: .projector, label: "PJ")
        let record = try routing()
        let projectorRecord = try ProjectorCommissioningAuthority(
            projectorEntityID: projector.entityID,
            plannedSpecRef: "spec:pj",
            observedAtUTC: utc
        )
        let alignmentRecord = try InstallationAlignmentRecord(
            targetPlannedEntityID: "planned-L",
            targetEntityType: .speaker,
            guidanceMode: .textualInstructions,
            precisionSufficiency: .unknown,
            finalEntityID: speaker.entityID,
            observedAtUTC: utc,
            coordinateSpaceID: space
        )
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record],
            projectorCommissionings: [projectorRecord],
            installationAlignments: [alignmentRecord]
        )
        let descriptors = collection.recordDescriptors
        let byID = Dictionary(
            descriptors.map { ($0.recordID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(byID[record.authorityID]?.kind,
                       .routingVerification)
        // The routing subtype token is the band scope — the exact
        // discriminator a plan's expected_subtype matches on.
        XCTAssertEqual(
            byID[record.authorityID]?.subtype, "full_range"
        )
        XCTAssertEqual(
            byID[projectorRecord.authorityID]?.kind,
            .projectorCommissioning
        )
        XCTAssertEqual(
            byID[projectorRecord.authorityID]?.targetEntityID,
            projector.entityID
        )
        XCTAssertEqual(
            byID[alignmentRecord.authorityID]?.kind,
            .installationAlignment
        )
        XCTAssertEqual(
            byID[alignmentRecord.authorityID]?.targetPlannedRef,
            "planned-L"
        )
    }

    // MARK: - #359 mission contract

    private func plan(
        entityChecklist: [HTDTTaskPlanEntityItem] = [],
        semanticTasks: [HTDTTaskPlanSemanticItem] = [],
        evidenceTasks: [HTDTTaskPlanEvidenceItem] = []
    ) throws -> HTDTCaptureTaskPlan {
        try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "project-1",
            roomName: "theater",
            entityChecklist: entityChecklist,
            semanticTasks: semanticTasks,
            evidenceTasks: evidenceTasks
        )
    }

    private func status(
        plan: HTDTCaptureTaskPlan
    ) throws -> CaptureTaskPlanStatus {
        let data = try JSONEncoder().encode(plan)
        return CaptureTaskPlanStatus(
            planImport: try CaptureTaskPlanImport(data: data)
        )
    }

    func testV2PlanDecodesSemanticAndEvidenceTasks() throws {
        let plan = try plan(
            semanticTasks: [
                try HTDTTaskPlanSemanticItem(
                    itemID: "sem-1",
                    requirement: .required,
                    semanticKind: .routingVerification,
                    expectedSubtype: "L",
                    label: "Verify L routing"
                ),
            ],
            evidenceTasks: [
                try HTDTTaskPlanEvidenceItem(
                    itemID: "ev-1",
                    requirement: .optional,
                    purpose: "avr_rack_wiring"
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(
            HTDTCaptureTaskPlan.self,
            from: encoded
        )
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.schemaVersion, "2.0.0")
        XCTAssertEqual(decoded.semanticTasks.count, 1)
        XCTAssertEqual(decoded.evidenceTasks.count, 1)
    }

    func testV1PlanDecodesWithEmptyNewSections() throws {
        let json = """
        {
            "schema": "htdt.capture-task-plan",
            "schema_version": "1.0.0",
            "plan_id": "p1",
            "plan_version": "1",
            "project_ref": "proj",
            "room_name": "room",
            "entity_checklist": [],
            "measurement_requests": [],
            "surface_review_tasks": []
        }
        """
        let decoded = try JSONDecoder().decode(
            HTDTCaptureTaskPlan.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.schemaVersion, "1.0.0")
        XCTAssertTrue(decoded.semanticTasks.isEmpty)
        XCTAssertTrue(decoded.evidenceTasks.isEmpty)
    }

    func testUnknownSemanticKindFailsClosed() throws {
        let json = """
        {
            "item_id": "sem-1",
            "requirement": "required",
            "semantic_kind": "wire_colors"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                HTDTTaskPlanSemanticItem.self,
                from: Data(json.utf8)
            )
        )
    }

    func testFulfillBindsExactRecord() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification,
                        expectedSubtype: "full_range"
                    ),
                ]
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        let outcomes = status.itemOutcomes(
            annotations: [],
            measurements: [],
            authorities: collection
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].outcome, .completed)
        XCTAssertEqual(
            outcomes[0].fulfillmentRef,
            record.authorityID.description
        )
    }

    func testFulfillRejectsWrongKind() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .projectorCommissioning
                    ),
                ]
            )
        )
        XCTAssertThrowsError(
            try status.fulfill(
                itemID: "sem-1",
                with: record.authorityID,
                in: collection
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .fulfillmentMismatch
            )
        }
    }

    func testFulfillRejectsSubtypeMismatch() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification,
                        expectedSubtype: "RS"
                    ),
                ]
            )
        )
        XCTAssertThrowsError(
            try status.fulfill(
                itemID: "sem-1",
                with: record.authorityID,
                in: collection
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .fulfillmentMismatch
            )
        }
    }

    func testFulfillRejectsNonAuthorityPayload() throws {
        var status = try status(
            plan: plan(
                entityChecklist: [
                    try HTDTTaskPlanEntityItem(
                        itemID: "ent-1",
                        entityType: .speaker,
                        requirement: .required
                    ),
                ]
            )
        )
        XCTAssertThrowsError(
            try status.fulfill(
                itemID: "ent-1",
                with: AuthorityRecordID(),
                in: TheaterAuthorityCollection.empty
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .fulfillmentKindMismatch
            )
        }
    }

    func testSharedFulfillmentNeedsBothOptIn() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-2",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                ]
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        XCTAssertThrowsError(
            try status.fulfill(
                itemID: "sem-2",
                with: record.authorityID,
                in: collection
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .fulfillmentMismatch
            )
        }
    }

    func testSharedFulfillmentWhenBothAllow() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification,
                        allowSharedFulfillment: true
                    ),
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-2",
                        requirement: .required,
                        semanticKind: .routingVerification,
                        allowSharedFulfillment: true
                    ),
                ]
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        try status.fulfill(
            itemID: "sem-2",
            with: record.authorityID,
            in: collection
        )
        let outcomes = status.itemOutcomes(
            annotations: [],
            measurements: [],
            authorities: collection
        )
        XCTAssertEqual(
            outcomes.map(\.outcome),
            [.completed, .completed]
        )
    }

    func testFulfillEvidenceRequiresCommittedRef() throws {
        var status = try status(
            plan: plan(
                evidenceTasks: [
                    try HTDTTaskPlanEvidenceItem(
                        itemID: "ev-1",
                        requirement: .required,
                        purpose: "avr_rack_wiring"
                    ),
                ]
            )
        )
        XCTAssertThrowsError(
            try status.fulfillEvidence(
                itemID: "ev-1",
                evidenceRef: "frame_1",
                in: []
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .fulfillmentMismatch
            )
        }
        try status.fulfillEvidence(
            itemID: "ev-1",
            evidenceRef: "frame_1",
            in: ["frame_1"]
        )
        let outcomes = status.itemOutcomes(
            annotations: [],
            measurements: [],
            committedEvidenceRefs: ["frame_1"]
        )
        XCTAssertEqual(outcomes[0].outcome, .completed)
        XCTAssertEqual(outcomes[0].fulfillmentRef, "frame_1")
    }

    func testSemanticTaskCannotBeMarkedComplete() throws {
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                ]
            )
        )
        XCTAssertThrowsError(
            try status.mark(itemID: "sem-1", as: .completed)
        ) { error in
            // The item exists — .completed is simply not markable
            // for a semantic task kind (#455).
            XCTAssertEqual(
                error as? CaptureTaskPlanError,
                .outcomeNotMarkable
            )
        }
    }

    func testRemovedRecordUnsatisfiesTask() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                ]
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        let empty = try TheaterAuthorityCollection()
        let outcomes = status.itemOutcomes(
            annotations: [],
            measurements: [],
            authorities: empty
        )
        XCTAssertEqual(outcomes[0].outcome, .pending)
        XCTAssertNil(outcomes[0].fulfillmentRef)
    }

    func testRequiredMissionCompleteNeedsFulfillment() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-2",
                        requirement: .optional,
                        semanticKind: .projectorCommissioning
                    ),
                ],
                evidenceTasks: [
                    try HTDTTaskPlanEvidenceItem(
                        itemID: "ev-1",
                        requirement: .required,
                        purpose: "avr_rack_wiring"
                    ),
                ]
            )
        )
        XCTAssertFalse(
            status.requiredMissionComplete(
                annotations: [],
                measurements: [],
                authorities: collection
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        try status.fulfillEvidence(
            itemID: "ev-1",
            evidenceRef: "frame_1",
            in: ["frame_1"]
        )
        // The optional projector task stays pending — required
        // completeness is unaffected.
        XCTAssertTrue(
            status.requiredMissionComplete(
                annotations: [],
                measurements: [],
                authorities: collection,
                committedEvidenceRefs: ["frame_1"]
            )
        )
    }

    func testStatusPackageRoundTripsFulfillmentRef() throws {
        let record = try routing()
        let collection = try TheaterAuthorityCollection(
            routingVerifications: [record]
        )
        var status = try status(
            plan: plan(
                semanticTasks: [
                    try HTDTTaskPlanSemanticItem(
                        itemID: "sem-1",
                        requirement: .required,
                        semanticKind: .routingVerification
                    ),
                ]
            )
        )
        try status.fulfill(
            itemID: "sem-1",
            with: record.authorityID,
            in: collection
        )
        let data = try status.statusPackage(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            annotations: [],
            measurements: [],
            authorities: collection
        )
        let decoded = try JSONDecoder().decode(
            CaptureTaskPlanStatusDocument.self,
            from: data
        )
        XCTAssertEqual(
            decoded.items.first?.fulfillmentRef,
            record.authorityID.description
        )
        XCTAssertEqual(decoded.schemaVersion, "2.0.0")
    }

    // MARK: - schema + packaging

    func testNewSectionsPassAuthoritiesSchema() throws {
        let projector = try entity(type: .projector, label: "PJ")
        let item = try SystemInventoryItem(
            equipmentClass: .avReceiver,
            userLabel: "AVR"
        )
        let screen = try entity(
            type: .projectionScreen,
            label: "screen"
        )
        let screenAuthority = try ProjectionScreenSemantics(
            screenEntityID: screen.entityID,
            visibleApertureWidthMeters: 2.4,
            acousticallyTransparent: .transparent,
            transparencySource: .userAttestation
        )
        let record = try RoutingVerificationAuthority(
            channelRole: ChannelRole(rawValue: "L"),
            sourceInventoryItemID: item.itemID,
            bandScope: .fullRange,
            speakerEntityIDs: [speakerEntity().entityID],
            verificationState: .verified,
            verificationMethod: .listenedTestSignal,
            observedAtUTC: utc
        )
        let projectorRecord = try ProjectorCommissioningAuthority(
            projectorEntityID: projector.entityID,
            throwObservation: AttestedSettingValue(
                state: .attested,
                numericValue: 3.4
            ),
            throwEndpointSemantics:
                "lens_center_to_screen_aperture",
            screenSemanticsAuthorityID: screenAuthority.authorityID,
            observedAtUTC: utc
        )
        let alignmentRecord = try InstallationAlignmentRecord(
            targetPlannedEntityID: "planned-L",
            targetEntityType: .speaker,
            guidanceMode: .textualInstructions,
            precisionSufficiency: .unknown,
            finalEntityID: projector.entityID,
            observedAtUTC: utc,
            coordinateSpaceID: space
        )
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [item],
            screenSemantics: [screenAuthority],
            routingVerifications: [record],
            projectorCommissionings: [projectorRecord],
            installationAlignments: [alignmentRecord]
        )
        let package = try TheaterAuthorityPackageBuilder.build(
            collection: collection
        )
        XCTAssertNotNil(
            try CanonicalPayloadValidator.validateSchemaOwnedJSON(
                path: TheaterAuthorityPackage.path,
                data: package.data
            )
        )
    }

    func testSemanticTaskKindWireTokens() throws {
        XCTAssertEqual(
            SemanticTaskKind.allCases.count, 14
        )
        XCTAssertEqual(
            SemanticTaskKind.routingVerification.rawValue,
            "routing_verification"
        )
        XCTAssertEqual(
            SemanticTaskKind.projectorCommissioning.rawValue,
            "projector_commissioning"
        )
        XCTAssertEqual(
            SemanticTaskKind.installationAlignment.rawValue,
            "installation_alignment"
        )
    }
}
