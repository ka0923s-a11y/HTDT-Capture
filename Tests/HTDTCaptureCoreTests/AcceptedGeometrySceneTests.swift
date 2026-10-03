import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#408: the accepted-geometry scene is a derived read model —
/// captured evidence, derived candidates, and semantic authority
/// stay visually distinct, and camera presets resolve without the
/// renderer.
final class AcceptedGeometrySceneTests: XCTestCase {

    private func meshSnapshot(
        anchorID: UUID = UUID(),
        vertices: [Float3]
    ) throws -> MeshAnchorSnapshot {
        try MeshAnchorSnapshot(
            anchorID: anchorID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnchor: .identity,
            sessionTimestampSeconds: nil,
            geometry: MeshGeometryPayload(
                vertices: vertices,
                triangleIndices: [0, 1, 2]
            )
        )
    }

    private func scene(
        meshSnapshots: [MeshAnchorSnapshot] = [],
        roomPlanObjects: [RoomPlanBindableObject] = [],
        derivedCandidates: [DerivedGeometryCandidateRecord] = [],
        entities: [CaptureAnnotationEntity] = [],
        measurements: [CaptureMeasurement] = []
    ) -> AcceptedGeometrySceneModel {
        AcceptedGeometrySceneModel(
            coordinateSpaceID: CoordinateSpaceID(),
            meshSnapshots: meshSnapshots,
            roomPlanObjects: roomPlanObjects,
            derivedCandidates: derivedCandidates,
            entities: entities,
            measurements: measurements
        )
    }

    // MARK: - Elements and layers

    /// Mesh anchors become captured-evidence elements whose bounds
    /// come from the world-transformed vertices.
    func testMeshAnchorBecomesCapturedEvidence() throws {
        let anchorID = UUID()
        let snapshot = try meshSnapshot(
            anchorID: anchorID,
            vertices: [
                Float3(0, 0, 0),
                Float3(2, 0, 0),
                Float3(0, 0, 3),
            ]
        )
        let scene = scene(meshSnapshots: [snapshot])
        let element = scene.elements.first {
            $0.sourceMeshAnchorID == anchorID
        }
        XCTAssertEqual(element?.layer, .capturedEvidence)
        XCTAssertEqual(element?.kind, .meshAnchor)
        XCTAssertEqual(element?.extentsWorld?.x, 2)
        XCTAssertEqual(element?.extentsWorld?.z, 3)
        XCTAssertEqual(element?.centerWorld.x, 1)
        XCTAssertEqual(element?.centerWorld.z, 1.5)
        XCTAssertNotNil(scene.boundsMin)
        XCTAssertEqual(scene.meshSnapshots[anchorID]?.anchorID, anchorID)
    }

    /// RoomPlan surfaces and objects land at their world transform,
    /// keeping surface vs object kinds distinct.
    func testRoomPlanElements() throws {
        var values = [Float](repeating: 0, count: 16)
        values[0] = 1
        values[5] = 1
        values[10] = 1
        values[12] = 3
        values[13] = 1
        values[14] = -2
        values[15] = 1
        let transform = try Matrix4x4F(values: values)
        let surface = RoomPlanBindableObject(
            identifier: "wall-1",
            category: "wall",
            isSurface: true,
            worldFromObject: transform,
            dimensionsMeters: Float3(4, 2.5, 0.1)
        )
        let object = RoomPlanBindableObject(
            identifier: "sofa-1",
            category: "sofa",
            isSurface: false,
            worldFromObject: .identity,
            dimensionsMeters: Float3(2, 1, 1)
        )
        let scene = scene(
            roomPlanObjects: [surface, object]
        )
        let wall = scene.elements.first {
            $0.sourceRoomPlanObjectID == "wall-1"
        }
        XCTAssertEqual(wall?.kind, .roomPlanSurface)
        XCTAssertEqual(wall?.centerWorld.x, 3)
        XCTAssertEqual(wall?.centerWorld.y, 1)
        XCTAssertEqual(wall?.centerWorld.z, -2)

        let sofa = scene.elements.first {
            $0.sourceRoomPlanObjectID == "sofa-1"
        }
        XCTAssertEqual(sofa?.kind, .roomPlanObject)
        XCTAssertEqual(sofa?.layer, .capturedEvidence)
    }

    /// Derived candidates render on their own layer — plan-space
    /// contour points map x→X, y→Z, vertical offset→Y.
    func testDerivedCandidateLayerAndMapping() throws {
        let candidate = try DerivedGeometryCandidateRecord(
            resolution: .resolved,
            shapeKind: .polygon,
            geometry: .polygon(
                DerivedPolygon(
                    vertices: [
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 0, y: 0),
                            supportEvidenceRefs: ["e"]
                        ),
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 2, y: 0),
                            supportEvidenceRefs: ["e"]
                        ),
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 2, y: 1),
                            supportEvidenceRefs: ["e"]
                        ),
                    ],
                    isConcave: false
                )
            ),
            coordinateSpaceID: CoordinateSpaceID(),
            sourceMode: .fused,
            sourceEvidenceRefs: ["e"],
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            contourPoints: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 1, y: 2),
                    evidenceRef: "e",
                    evidenceKind: .mesh,
                    verticalPositionMeters: 0.5
                ),
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 3, y: 2),
                    evidenceRef: "e",
                    evidenceKind: .mesh
                ),
            ]
        )
        let scene = scene(derivedCandidates: [candidate])
        let element = scene.elements.first {
            $0.sourceDerivedCandidateID == candidate.candidateID
        }
        XCTAssertEqual(element?.layer, .derivedCandidate)
        XCTAssertEqual(element?.kind, .derivedCandidate)
        // X from plan-x, Z from plan-y, Y from vertical offset.
        XCTAssertEqual(element?.centerWorld.x, 2)
        XCTAssertEqual(element?.centerWorld.z, 2)
        XCTAssertEqual(element?.extentsWorld?.x, 2)
        XCTAssertEqual(
            scene.derivedCandidates[candidate.candidateID]?.candidateID,
            candidate.candidateID
        )
    }

    /// Annotation entities land on the authority layer; an entity
    /// with orientation emits a direction indicator carrying the
    /// real 3D vector.
    func testEntitiesAndDirectionIndicators() throws {
        let speaker = try CaptureAnnotationEntity(
            type: .speaker,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: "Left main",
            placement: PlacementProvenance(method: .manualNumeric),
            orientation: OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            channelRole: ChannelRole(rawValue: "L")
        )
        let scene = scene(entities: [speaker])
        let element = scene.elements.first {
            $0.sourceEntityID == speaker.entityID
        }
        XCTAssertEqual(element?.layer, .semanticAuthority)
        XCTAssertEqual(element?.label, "Left main")

        let indicator = scene.directionIndicators.first {
            $0.ownerToken.hasSuffix(speaker.entityID.description)
        }
        XCTAssertEqual(indicator?.directionWorld?.z, -1)
        // A horizontal direction is flagged, not silently leveled.
        XCTAssertEqual(indicator?.verticalDropped, true)
    }

    /// An entity without orientation emits no direction indicator —
    /// the renderer never invents an arrow.
    func testEntityWithoutOrientationHasNoIndicator() throws {
        let seat = try CaptureAnnotationEntity(
            type: .seat,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: "Row A seat 3",
            placement: PlacementProvenance(method: .manualNumeric)
        )
        let scene = scene(entities: [seat])
        XCTAssertTrue(scene.directionIndicators.isEmpty)
    }

    // MARK: - Camera presets

    /// Every preset resolves to a finite spec — a fit for the whole
    /// room, a focus on one element, and the orthographic-style
    /// elevations.
    func testCameraPresetsResolve() throws {
        let snapshot = try meshSnapshot(
            vertices: [
                Float3(0, 0, 0),
                Float3(4, 0, 0),
                Float3(0, 0, 6),
            ]
        )
        let scene = scene(meshSnapshots: [snapshot])
        for preset in [
            GeometryCameraPreset.orbit,
            .frontElevation, .sideElevation, .topPlan, .fitRoom,
        ] {
            let spec = scene.cameraSpec(for: preset)
            XCTAssertTrue(spec.positionWorld.isFinite)
            XCTAssertTrue(spec.lookAtWorld.isFinite)
            XCTAssertGreaterThan(spec.fieldOfViewDegrees, 0)
        }
        // Fit looks at the room's center.
        let fit = scene.cameraSpec(for: .fitRoom)
        XCTAssertEqual(fit.lookAtWorld.x, 2)
        XCTAssertEqual(fit.lookAtWorld.z, 3)
        // Focus targets the element's center.
        let element = scene.elements[0]
        let focus = scene.cameraSpec(
            for: .focusElement(element.elementID)
        )
        XCTAssertEqual(focus.lookAtWorld, element.centerWorld)
    }

    /// An empty scene still resolves a readable orbit — the preset
    /// contract is total.
    func testEmptySceneCameraFallback() {
        let spec = scene().cameraSpec(for: .orbit)
        XCTAssertTrue(spec.positionWorld.isFinite)
    }
}
