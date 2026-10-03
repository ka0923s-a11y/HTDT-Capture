import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Tests for the workspace-UI support types added for issues
/// legacy bolph71656-ai/HTDT-Capture#214/legacy bolph71656-ai/HTDT-Capture#246 (targeted placement), legacy bolph71656-ai/HTDT-Capture#247 (plausibility), legacy bolph71656-ai/HTDT-Capture#266
/// (workspace drafts), legacy bolph71656-ai/HTDT-Capture#239 (equipment identity), legacy bolph71656-ai/HTDT-Capture#278 (speaker
/// layout), legacy bolph71656-ai/HTDT-Capture#245 (edit seeds) and legacy bolph71656-ai/HTDT-Capture#265 (catalog selection keys).
final class WorkspaceUIAuthorityTests: XCTestCase {

    private let spaceID = CoordinateSpaceID()

    private func translation(
        _ x: Float, _ y: Float, _ z: Float
    ) throws -> Matrix4x4F {
        try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            x, y, z, 1,
        ])
    }

    private func makeEntity(
        type: AnnotationEntityType = .referencePoint,
        label: String = "Ref",
        position: Float3 = Float3(0, 1, 0),
        channelRole: ChannelRole? = nil
    ) throws -> CaptureAnnotationEntity {
        let orientation: OrientationAxes? =
            type == .speaker
                ? try OrientationAxes(
                    frontAxisLocal: .unit(0, 0, -1),
                    upAxisLocal: .unit(0, 1, 0))
                : nil
        return try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: translation(
                position.x, position.y, position.z),
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(type),
            label: label,
            verificationState: .userAttested,
            placement: PlacementProvenance(method: .manualNumeric),
            orientation: orientation,
            channelRole: channelRole
        )
    }

    private func makeMeshAnchor(
        anchorID: UUID = UUID(),
        vertices: [Float3],
        indices: [UInt32],
        worldFromAnchor: Matrix4x4F = .identity
    ) throws -> MeshAnchorSnapshot {
        try MeshAnchorSnapshot(
            anchorID: anchorID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: spaceID,
            worldFromAnchor: worldFromAnchor,
            sessionTimestampSeconds: nil,
            geometry: MeshGeometryPayload(
                vertices: vertices,
                triangleIndices: indices
            )
        )
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#246 — mesh raycast

    func testMeshRaycastHitsTriangle() throws {
        // A triangle in the z = -2 plane spanning x,y ∈ [-1, 1].
        let anchor = try makeMeshAnchor(
            vertices: [
                Float3(-1, -1, -2),
                Float3(1, -1, -2),
                Float3(0, 1, -2),
            ],
            indices: [0, 1, 2]
        )
        let ray = try SpatialRay(
            origin: Float3(0, 0, 0),
            direction: Float3(0, 0, -1)
        )
        let hit = MeshRaycast.nearestHit(
            ray: ray,
            anchors: [anchor]
        )
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.meshAnchorID, anchor.anchorID)
        XCTAssertEqual(
            try XCTUnwrap(hit?.distanceMeters), 2, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(hit?.positionWorld).z, -2, accuracy: 0.001)
        XCTAssertEqual(hit?.triangleIndex, 0)
    }

    func testMeshRaycastMissesBehindOrigin() throws {
        let anchor = try makeMeshAnchor(
            vertices: [
                Float3(-1, -1, -2),
                Float3(1, -1, -2),
                Float3(0, 1, -2),
            ],
            indices: [0, 1, 2]
        )
        let ray = try SpatialRay(
            origin: Float3(0, 0, 0),
            direction: Float3(0, 0, 1)
        )
        XCTAssertNil(
            MeshRaycast.nearestHit(ray: ray, anchors: [anchor]))
    }

    func testMeshRaycastRespectsMaxDistance() throws {
        let anchor = try makeMeshAnchor(
            vertices: [
                Float3(-1, -1, -2),
                Float3(1, -1, -2),
                Float3(0, 1, -2),
            ],
            indices: [0, 1, 2]
        )
        let ray = try SpatialRay(
            origin: Float3(0, 0, 0),
            direction: Float3(0, 0, -1)
        )
        XCTAssertNil(
            MeshRaycast.nearestHit(
                ray: ray, anchors: [anchor], maxDistanceMeters: 1))
        XCTAssertNotNil(
            MeshRaycast.nearestHit(
                ray: ray, anchors: [anchor], maxDistanceMeters: 3))
    }

    func testMeshRaycastTransformedAnchor() throws {
        // Anchor translated +4 in z so its triangle sits at world z=+2.
        let anchor = try makeMeshAnchor(
            vertices: [
                Float3(-1, -1, -2),
                Float3(1, -1, -2),
                Float3(0, 1, -2),
            ],
            indices: [0, 1, 2],
            worldFromAnchor: translation(0, 0, 4)
        )
        let ray = try SpatialRay(
            origin: Float3(0, 0, 0),
            direction: Float3(0, 0, 1)
        )
        let hit = MeshRaycast.nearestHit(
            ray: ray, anchors: [anchor])
        XCTAssertEqual(
            try XCTUnwrap(hit?.positionWorld).z, 2, accuracy: 0.001)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#246 — RoomPlan object binding

    func testRoomPlanObjectRaycastHitsBox() throws {
        let object = RoomPlanBindableObject(
            identifier: "obj-1",
            category: "sofa",
            isSurface: false,
            worldFromObject: .identity,
            dimensionsMeters: Float3(2, 1, 1)
        )
        let ray = try SpatialRay(
            origin: Float3(0, 0, -5),
            direction: Float3(0, 0, 1)
        )
        let hit = RoomPlanObjectRaycast.nearestHit(
            ray: ray, objects: [object])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.object.identifier, "obj-1")
        XCTAssertEqual(
            try XCTUnwrap(hit?.distanceMeters), 4.5, accuracy: 0.001)
    }

    func testRoomPlanObjectRaycastMiss() throws {
        let object = RoomPlanBindableObject(
            identifier: "obj-1",
            category: "sofa",
            isSurface: false,
            worldFromObject: .identity,
            dimensionsMeters: Float3(1, 1, 1)
        )
        let ray = try SpatialRay(
            origin: Float3(10, 10, 10),
            direction: Float3(0, 1, 0)
        )
        XCTAssertNil(
            RoomPlanObjectRaycast.nearestHit(
                ray: ray, objects: [object]))
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#214/legacy bolph71656-ai/HTDT-Capture#246 — placement probe resolution

    private func meshHit(distance: Float) -> MeshRaycastHit {
        MeshRaycastHit(
            meshAnchorID: UUID(),
            distanceMeters: distance,
            positionWorld: Float3(0, 0, -distance),
            triangleIndex: 0
        )
    }

    private func roomPlanHit(
        distance: Float
    ) -> RoomPlanObjectHit {
        RoomPlanObjectHit(
            object: RoomPlanBindableObject(
                identifier: "wall-1",
                category: "wall",
                isSurface: true,
                worldFromObject: .identity,
                dimensionsMeters: Float3(1, 1, 1)
            ),
            distanceMeters: distance,
            positionWorld: Float3(0, 0, -distance)
        )
    }

    private func planeHit(
        distance: Float
    ) -> PlaneProbeHit {
        PlaneProbeHit(
            target: .estimatedPlane,
            distanceMeters: distance,
            positionWorld: Float3(0, 0, -distance)
        )
    }

    func testProbeAutomaticPicksNearestCandidate() {
        let probe = PlacementProbeResolver.resolve(
            candidates: PlacementProbeCandidates(
                meshHit: meshHit(distance: 3),
                roomPlanHit: roomPlanHit(distance: 1.5),
                planeHit: planeHit(distance: 2)
            ),
            preference: .automatic
        )
        XCTAssertEqual(probe.status, .hit)
        XCTAssertEqual(probe.target, .roomPlanObject)
        XCTAssertEqual(probe.roomPlanObjectID, "wall-1")
        XCTAssertEqual(probe.distanceMeters, 1.5)
    }

    func testProbeAutomaticTieBreakPrefersSpecificSource() {
        // At equal distance the more specific class wins (object >
        // mesh > plane) so a fallback is never silent.
        let probe = PlacementProbeResolver.resolve(
            candidates: PlacementProbeCandidates(
                meshHit: meshHit(distance: 2),
                planeHit: planeHit(distance: 2)
            ),
            preference: .automatic
        )
        XCTAssertEqual(probe.target, .mesh)
        XCTAssertNotNil(probe.meshAnchorID)
    }

    func testProbeExplicitMeshNeverFallsBackToPlane() {
        let probe = PlacementProbeResolver.resolve(
            candidates: PlacementProbeCandidates(
                planeHit: planeHit(distance: 1)
            ),
            preference: .mesh
        )
        XCTAssertEqual(probe.status, .noHit)
        XCTAssertNil(probe.target)
    }

    func testProbeExplicitPlaneKeepsPosition() {
        let probe = PlacementProbeResolver.resolve(
            candidates: PlacementProbeCandidates(
                planeHit: planeHit(distance: 1.25)
            ),
            preference: .plane
        )
        XCTAssertEqual(probe.status, .hit)
        XCTAssertEqual(probe.target, .estimatedPlane)
        XCTAssertEqual(probe.distanceMeters, 1.25)
        XCTAssertNotNil(probe.positionWorld)
    }

    func testProbeRoomPlanCarriesObjectIdentity() {
        let probe = PlacementProbeResolver.resolve(
            candidates: PlacementProbeCandidates(
                roomPlanHit: roomPlanHit(distance: 0.8)
            ),
            preference: .roomPlanObject
        )
        XCTAssertEqual(probe.status, .hit)
        XCTAssertEqual(probe.roomPlanObjectID, "wall-1")
        XCTAssertEqual(probe.roomPlanObjectCategory, "wall")
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#247 — spatial plausibility diagnostics

    private func plausibilityContext() -> SpatialPlausibilityContext {
        // A 4 x 3 x 4 m room corner-box spanning x,z ∈ [-2, 2],
        // y ∈ [0, 3].
        SpatialPlausibilityContext(
            meshBounds: [
                SpatialAxisBounds(
                    minimum: Float3(-2, 0, -2),
                    maximum: Float3(2, 3, 2)
                )
            ],
            floorYMeters: 0,
            roomDimensionsMeters: try? CapturedRoomDimensionsSummary(
                xMeters: 4, yMeters: 3, zMeters: 4)
        )
    }

    func testPlausibilityUnavailableWithoutGeometry() throws {
        let entity = try makeEntity()
        XCTAssertNil(
            SpatialPlausibilityEvaluator.evaluate(
                annotations: [entity],
                context: SpatialPlausibilityContext(
                    meshBounds: [], floorYMeters: nil,
                    roomDimensionsMeters: nil)
            )
        )
    }

    func testPlausibilityPassForReasonablePoint() throws {
        let entity = try makeEntity(position: Float3(0, 1.2, 0))
        let findings = SpatialPlausibilityEvaluator.evaluate(
            annotations: [entity],
            context: plausibilityContext()
        )
        XCTAssertEqual(findings, [])
    }

    func testPlausibilityFlagsBelowFloor() throws {
        let entity = try makeEntity(position: Float3(0, -0.5, 0))
        let findings = try XCTUnwrap(
            SpatialPlausibilityEvaluator.evaluate(
                annotations: [entity],
                context: plausibilityContext()
            )
        )
        XCTAssertTrue(findings.contains {
            $0.rule == .belowFloor && $0.entityID == entity.entityID
        })
        XCTAssertEqual(findings.first?.rulesVersion, "1.0.0")
    }

    func testPlausibilityFlagsOutsideRoomExtent() throws {
        let entity = try makeEntity(position: Float3(10, 1, 10))
        let findings = try XCTUnwrap(
            SpatialPlausibilityEvaluator.evaluate(
                annotations: [entity],
                context: plausibilityContext()
            )
        )
        XCTAssertTrue(findings.contains {
            $0.rule == .outsideRoomExtent
        })
    }

    func testPlausibilityFlagsDuplicatePosition() throws {
        let a = try makeEntity(label: "A", position: Float3(0, 1, 0))
        let b = try makeEntity(
            label: "B", position: Float3(0.01, 1.0, 0.0))
        let findings = try XCTUnwrap(
            SpatialPlausibilityEvaluator.evaluate(
                annotations: [a, b],
                context: plausibilityContext()
            )
        )
        let duplicates = findings.filter {
            $0.rule == .duplicatePosition
        }
        XCTAssertFalse(duplicates.isEmpty)
        XCTAssertTrue(duplicates.contains {
            $0.entityID == a.entityID || $0.entityID == b.entityID
        })
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#266 — workspace draft persistence

    private func makeDraft(
        revisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID
    ) throws -> AnnotationWorkspaceDraft {
        AnnotationWorkspaceDraft(
            captureRevisionID: revisionID,
            coordinateSpaceID: coordinateSpaceID,
            savedAtUTC: "2026-09-21T00:00:00Z",
            annotations: [try makeEntity(label: "Drafted")]
        )
    }

    func testDraftRoundTripPreservesContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let revisionID = CaptureRevisionID()
        let draft = try makeDraft(
            revisionID: revisionID, coordinateSpaceID: spaceID)

        try store.save(draft)
        let loaded = store.load(
            revisionID: revisionID, coordinateSpaceID: spaceID)
        XCTAssertEqual(loaded, draft)
    }

    func testDraftRoundTripPreservesTheaterAuthorities() throws {
        // legacy bolph71656-ai/HTDT-Capture#358: staged theater-semantic authorities must survive
        // autosave/restore like the other staged collections.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let revisionID = CaptureRevisionID()
        var draft = try makeDraft(
            revisionID: revisionID, coordinateSpaceID: spaceID)
        draft.theaterAuthorities = .empty

        try store.save(draft)
        let loaded = store.load(
            revisionID: revisionID, coordinateSpaceID: spaceID)
        XCTAssertEqual(loaded, draft)
        XCTAssertNotNil(loaded?.theaterAuthorities)
    }

    func testLegacyDraftWithoutTheaterAuthoritiesDecodes() throws {
        // Drafts written before legacy bolph71656-ai/HTDT-Capture#358 carry no `theater_authorities`
        // key; they must still decode so older autosaves restore.
        var draft = try makeDraft(
            revisionID: CaptureRevisionID(), coordinateSpaceID: spaceID)
        draft.theaterAuthorities = .empty
        let encoder = JSONEncoder()
        let data = try encoder.encode(draft)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        object.removeValue(forKey: "theater_authorities")
        let legacyData = try JSONSerialization.data(
            withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            AnnotationWorkspaceDraft.self, from: legacyData)
        XCTAssertNil(decoded.theaterAuthorities)
        XCTAssertEqual(decoded.annotations, draft.annotations)
    }

    func testDraftStaleCoordinateSpaceIsDiscarded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let revisionID = CaptureRevisionID()
        let draft = try makeDraft(
            revisionID: revisionID, coordinateSpaceID: spaceID)
        try store.save(draft)

        // A draft bound to a different coordinate space must not
        // apply — and is deleted so it cannot resurrect later.
        XCTAssertNil(
            store.load(
                revisionID: revisionID,
                coordinateSpaceID: CoordinateSpaceID()))
        XCTAssertNil(
            store.load(
                revisionID: revisionID,
                coordinateSpaceID: spaceID))
    }

    func testDraftStaleRevisionIsDiscarded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let revisionID = CaptureRevisionID()
        try store.save(
            makeDraft(
                revisionID: revisionID, coordinateSpaceID: spaceID))
        XCTAssertNil(
            store.load(
                revisionID: CaptureRevisionID(),
                coordinateSpaceID: spaceID))
    }

    func testDraftDiscardRemovesFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let revisionID = CaptureRevisionID()
        try store.save(
            makeDraft(
                revisionID: revisionID, coordinateSpaceID: spaceID))
        store.discard(revisionID: revisionID)
        XCTAssertNil(
            store.load(
                revisionID: revisionID, coordinateSpaceID: spaceID))
    }

    func testDraftDiscardAllRemovesEveryRevision() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AnnotationWorkspaceDraftStore(directoryURL: dir)
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        try store.save(
            makeDraft(revisionID: a, coordinateSpaceID: spaceID))
        try store.save(
            makeDraft(revisionID: b, coordinateSpaceID: spaceID))
        store.discardAll()
        XCTAssertNil(
            store.load(revisionID: a, coordinateSpaceID: spaceID))
        XCTAssertNil(
            store.load(revisionID: b, coordinateSpaceID: spaceID))
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#239 — equipment identity evidence

    private func makeEquipment() throws -> HTDTEquipmentReference {
        try HTDTEquipmentReference(
            equipmentID: "speaker.model.x",
            equipmentVersion: "1.0.0",
            equipmentHash: EvidenceSHA256(
                String(repeating: "a", count: 64))
        )
    }

    func testIdentityRecordRequiresAttestation() throws {
        let entity = try makeEntity()
        XCTAssertThrowsError(
            try EquipmentIdentityRecord(
                entityID: entity.entityID,
                equipment: makeEquipment(),
                attestedPhysicalMatch: false
            )
        ) { error in
            XCTAssertEqual(
                error as? EquipmentIdentityEvidenceError,
                .attestationRequired)
        }
    }

    func testIdentityDocumentRejectsUnboundEntity() throws {
        let entity = try makeEntity()
        XCTAssertThrowsError(
            try EquipmentIdentityDocument(
                captureRevisionID: CaptureRevisionID(),
                coordinateSpaceID: spaceID,
                records: [
                    EquipmentIdentityRecord(
                        entityID: AnnotationEntityID(),
                        equipment: makeEquipment(),
                        attestedPhysicalMatch: true
                    )
                ],
                entities: [entity]
            )
        ) { error in
            guard case .unboundRecord =
                error as? EquipmentIdentityEvidenceError
            else {
                return XCTFail("expected unboundRecord, got \(error)")
            }
        }
    }

    func testIdentityDocumentRejectsEquipmentMismatch() throws {
        let equipment = try makeEquipment()
        let entity = try makeEntity()
        let boundEntity = try CaptureAnnotationEntity(
            entityID: entity.entityID,
            type: .speaker,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: entity.worldFromAnnotation,
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(.speaker),
            label: "L speaker",
            verificationState: .userAttested,
            placement: entity.placement,
            orientation: OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)),
            channelRole: .left,
            equipmentRef: equipment
        )
        let otherEquipment = try HTDTEquipmentReference(
            equipmentID: "different.model",
            equipmentVersion: "1.0.0",
            equipmentHash: EvidenceSHA256(
                String(repeating: "b", count: 64))
        )
        XCTAssertThrowsError(
            try EquipmentIdentityDocument(
                captureRevisionID: CaptureRevisionID(),
                coordinateSpaceID: spaceID,
                records: [
                    EquipmentIdentityRecord(
                        entityID: boundEntity.entityID,
                        equipment: otherEquipment,
                        attestedPhysicalMatch: true
                    )
                ],
                entities: [boundEntity]
            )
        ) { error in
            guard case .unboundRecord =
                error as? EquipmentIdentityEvidenceError
            else {
                return XCTFail("expected unboundRecord, got \(error)")
            }
        }
    }

    func testIdentityPackageSourceRefsBindToAnnotations() throws {
        let equipment = try makeEquipment()
        let entity = try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: .identity,
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(.referencePoint),
            label: "P",
            verificationState: .userAttested,
            placement: PlacementProvenance(method: .manualNumeric),
            equipmentRef: equipment
        )
        let record = try EquipmentIdentityRecord(
            entityID: entity.entityID,
            equipment: equipment,
            identityEvidenceRefs: [
                "path:evidence/frames/abc.json",
            ],
            serialOrAssetTag: "SN-123",
            attestedPhysicalMatch: true
        )
        let document = try EquipmentIdentityDocument(
            captureRevisionID: CaptureRevisionID(),
            coordinateSpaceID: spaceID,
            records: [record],
            entities: [entity]
        )
        let package = try EquipmentIdentityEvidencePackage(
            document: document)
        XCTAssertEqual(
            EquipmentIdentityEvidencePackage.path,
            "derived/equipment-identity.json")
        XCTAssertTrue(package.sourceRefs.contains(
            "path:evidence/frames/abc.json"))
        XCTAssertTrue(package.sourceRefs.contains(
            "path:annotations/entities.json"))
        XCTAssertFalse(package.data.isEmpty)
    }

    func testSerialTagIsOptionalAndNormalized() throws {
        let entity = try makeEntity()
        let blank = try EquipmentIdentityRecord(
            entityID: entity.entityID,
            equipment: makeEquipment(),
            serialOrAssetTag: "   ",
            attestedPhysicalMatch: true
        )
        XCTAssertNil(blank.serialOrAssetTag)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#278 — speaker layout plan/progress

    func testLayoutPresetsCarryOrderedRoles() {
        let plan = SpeakerLayoutPresets.surround5_1
        XCTAssertEqual(
            plan.roles.map(\.channelRole),
            [.left, .center, .right,
             .surroundLeft, .surroundRight, .lfe])
        XCTAssertEqual(plan.roles.last?.isSubwoofer, true)
        // Every preset's role list is explicit — nothing hardcodes a
        // 7.1.4 assumption into the plan itself.
        XCTAssertFalse(SpeakerLayoutPresets.all.isEmpty)
    }

    func testLayoutProgressAutoAdvanceSkipsCompleted() throws {
        let plan = SpeakerLayoutPresets.stereo
        var progress = SpeakerLayoutProgress(plan: plan)
        XCTAssertEqual(
            progress.nextPendingRole(in: plan)?.roleID,
            plan.roles[0].roleID)
        progress.markCompleted(
            roleID: plan.roles[0].roleID,
            entityID: AnnotationEntityID())
        progress.markSkipped(roleID: plan.roles[1].roleID)
        XCTAssertNil(progress.nextPendingRole(in: plan))
        XCTAssertEqual(
            progress.state(for: plan.roles[1].roleID), .skipped)
    }

    func testLayoutProgressKeepsNotInstalledDistinct() {
        let plan = SpeakerLayoutPresets.stereo
        var progress = SpeakerLayoutProgress(plan: plan)
        progress.markNotInstalled(roleID: plan.roles[0].roleID)
        XCTAssertEqual(
            progress.state(for: plan.roles[0].roleID), .notInstalled)
        // Not-installed roles are deliberately absent from the
        // pending queue — distinct from forgotten roles.
        XCTAssertNotEqual(
            progress.nextPendingRole(in: plan)?.roleID,
            plan.roles[0].roleID)
    }

    func testLayoutProgressRebuiltFromStagedAnnotations() throws {
        let plan = SpeakerLayoutPresets.stereo
        let entity = try makeEntity(
            type: .speaker, label: "L",
            channelRole: .left)
        let progress = SpeakerLayoutProgress(
            plan: plan, annotations: [entity])
        XCTAssertEqual(
            progress.state(for: plan.roles[0].roleID), .completed)
        XCTAssertEqual(
            progress.entityByRole[plan.roles[0].roleID],
            entity.entityID)
        XCTAssertEqual(
            progress.nextPendingRole(in: plan)?.channelRole, .right)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#245 — edit seeds preserve identity

    func testEditSeedPreservesEntityIDAndProvenance() throws {
        let original = try makeEntity(
            label: "Original", position: Float3(1, 2, 3))
        let seed = AnnotationEditSeed(entity: original)
        let rebuilt = try seed.buildEntity(
            coordinateSpaceID: spaceID,
            type: original.type,
            label: "Renamed",
            channelRole: nil,
            equipmentRef: nil,
            yawDegrees: nil,
            evidenceSelection: AnnotationEvidenceSelection()
        )
        XCTAssertEqual(rebuilt.entityID, original.entityID)
        XCTAssertEqual(rebuilt.label, "Renamed")
        XCTAssertEqual(rebuilt.placement, original.placement)
        XCTAssertEqual(
            rebuilt.worldFromAnnotation,
            original.worldFromAnnotation)
    }

    func testEditSeedManualOverrideMarksManualNumeric() throws {
        let raycastPlacement = try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/x.json"]
        )
        let original = try CaptureAnnotationEntity(
            type: .seat,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: translation(1, 0.5, -2),
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(.seat),
            label: "Seat",
            verificationState: .evidenceLinked,
            placement: raycastPlacement
        )
        var seed = AnnotationEditSeed(entity: original)
        seed.manualPositionOverride = Float3(1.5, 0.5, -2)
        let rebuilt = try seed.buildEntity(
            coordinateSpaceID: spaceID,
            type: .seat,
            label: "Seat",
            channelRole: nil,
            equipmentRef: nil,
            yawDegrees: nil,
            evidenceSelection: AnnotationEvidenceSelection()
        )
        XCTAssertEqual(rebuilt.entityID, original.entityID)
        XCTAssertEqual(rebuilt.placement.method, .manualNumeric)
        XCTAssertEqual(
            rebuilt.worldFromAnnotation.translationWorld,
            Float3(1.5, 0.5, -2))
        XCTAssertEqual(
            rebuilt.verificationState, .userAttested)
    }

    func testEditSeedReplacementAuthorityWins() throws {
        let original = try makeEntity(position: Float3(0, 0, 0))
        let authority = try AnnotationPlacementAuthority(
            worldFromAnnotation: translation(5, 1, 5),
            placement: PlacementProvenance(
                method: .raycast,
                sourceEvidenceRefs: ["path:evidence/frames/y.json"]),
            coordinateSpaceID: spaceID,
            evidenceRefs: ["path:evidence/frames/y.json"]
        )
        var seed = AnnotationEditSeed(entity: original)
        seed.replacementPlacement = authority
        let rebuilt = try seed.buildEntity(
            coordinateSpaceID: spaceID,
            type: original.type,
            label: original.label,
            channelRole: nil,
            equipmentRef: nil,
            yawDegrees: nil,
            referencePointConstruction: .surfaceHitConfirmed,
            evidenceSelection: AnnotationEvidenceSelection()
        )
        XCTAssertEqual(rebuilt.placement.method, .raycast)
        XCTAssertEqual(
            rebuilt.worldFromAnnotation.translationWorld,
            Float3(5, 1, 5))
        XCTAssertEqual(
            rebuilt.verificationState, .evidenceLinked)
        XCTAssertTrue(rebuilt.evidenceRefs.contains(
            "path:evidence/frames/y.json"))
    }

    func testMeasurementEditPreservesIdentity() throws {
        let original = try CaptureMeasurement(
            quantityType: "room_width",
            value: .scalar(4.0),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
        let seed = MeasurementEditSeed(measurement: original)
        let edited = try MeasurementEditSupport
            .buildEditedMeasurement(
                seed: seed,
                quantityType: "room_length",
                value: 6.25,
                unit: .meter,
                acquisitionMethod: .laserDistanceMeter,
                instrument: nil,
                statedUncertainty: 0.01,
                sourceValueText: nil,
                evidenceRefs: []
            )
        XCTAssertEqual(
            edited.measurementID, original.measurementID)
        XCTAssertEqual(edited.quantityType, "room_length")
        XCTAssertEqual(edited.value, .scalar(6.25))
        XCTAssertEqual(
            edited.acquisitionMethod, .laserDistanceMeter)
        XCTAssertEqual(edited.statedUncertainty, 0.01)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#265 — catalog selection key determinism

    func testCatalogSelectionKeyIsDeterministic() throws {
        let hash = try EvidenceSHA256(
            String(repeating: "c", count: 64))
        let entry = try HTDTEquipmentCatalogEntry(
            definitionID: "vendor.speaker",
            version: "2.0.1",
            semanticSHA256: hash,
            identityKind: .manufacturer,
            manufacturer: "Vendor",
            model: "Speaker"
        )
        XCTAssertEqual(
            entry.selectionKey,
            "vendor.speaker\u{0}2.0.1\u{0}"
                + String(repeating: "c", count: 64))
        XCTAssertEqual(
            try entry.equipmentReference(
                authorityVersion: HTDTEquipmentCatalogSnapshot
                    .expectedAuthorityVersion
            ).equipmentID,
            "vendor.speaker")
        XCTAssertEqual(
            try entry.equipmentReference(
                authorityVersion: HTDTEquipmentCatalogSnapshot
                    .expectedAuthorityVersion
            ).equipmentHash,
            hash)
    }
}
