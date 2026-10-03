import XCTest
@testable import HTDTCaptureCore

/// Follow-up coverage for the derived-candidate promotion flow:
/// centroid/geometry selections on the authoring session, re-fitting
/// ambiguous candidates from persisted contours, the re-observation
/// advisory -> motion-guidance link, and `derived_candidate:` spatial
/// evidence congruence at entity commit.
final class DerivedCandidatePromotionTests: XCTestCase {
    private let spaceID = CoordinateSpaceID()
    private let sessionID = CaptureSessionID()

    private func contour(_ points: [(Double, Double)])
        -> [DerivedObservationPoint]
    {
        points.map {
            DerivedObservationPoint(
                position: DerivedPoint2D(x: $0.0, y: $0.1),
                evidenceRef: "e",
                evidenceKind: .mesh
            )
        }
    }

    private func resolvedRecord() throws
        -> DerivedGeometryCandidateRecord
    {
        try DerivedGeometryCandidateRecord(
            resolution: .resolved,
            shapeKind: .circle,
            geometry: .circle(
                DerivedCircle(
                    center: DerivedPoint2D(x: 1.5, y: 2.5),
                    radius: 0.4
                )
            ),
            coordinateSpaceID: spaceID,
            sourceMode: .classifiedMesh,
            sourceEvidenceRefs: ["path:mesh/anchors.json"],
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            contourPoints: contour([(1, 2), (2, 3), (1, 3)])
        )
    }

    private func ambiguousRecord() throws
        -> DerivedGeometryCandidateRecord
    {
        try DerivedGeometryCandidateRecord(
            resolution: .ambiguousEvidence,
            ambiguityShapeKinds: [.polygon, .circle],
            coordinateSpaceID: spaceID,
            sourceMode: .classifiedMesh,
            sourceEvidenceRefs: ["path:mesh/anchors.json"],
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            contourPoints: contour(
                [(1, 1), (2, 1), (2, 2), (1, 2), (1.5, 1.5)]
            )
        )
    }

    // MARK: - authoring selections

    func testCentroidSelectionUsesContourMeanAndDerivedRef() throws {
        let record = try resolvedRecord()
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            derivedCandidates: [record]
        )
        let selection = try session.selectDerivedCandidateCentroid(
            candidateID: record.candidateID
        )
        XCTAssertFalse(selection.isCanonicalSource)
        XCTAssertEqual(selection.source, .derivedCandidate)
        let authority = try session.placementAuthority(
            for: selection.selectionID
        )
        XCTAssertEqual(authority.placement.method, .other)
        XCTAssertTrue(
            authority.evidenceRefs.contains(
                "derived_candidate:\(record.candidateID)"
            )
        )
    }

    func testCentroidSelectionRejectsUnresolvedRecord() throws {
        let record = try ambiguousRecord()
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            derivedCandidates: [record]
        )
        XCTAssertThrowsError(
            try session.selectDerivedCandidateCentroid(
                candidateID: record.candidateID
            )
        )
    }

    func testRefittedSelectionRequiresAmbiguousRecord() throws {
        let resolved = try resolvedRecord()
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            derivedCandidates: [resolved]
        )
        XCTAssertThrowsError(
            try session.selectRefittedCandidateGeometry(
                candidateID: resolved.candidateID,
                geometry: .circle(
                    DerivedCircle(
                        center: DerivedPoint2D(x: 0, y: 0),
                        radius: 1
                    )
                )
            )
        )
    }

    func testRefittedSelectionProducesDerivedSelection() throws {
        let record = try ambiguousRecord()
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            derivedCandidates: [record]
        )
        let selection = try session.selectRefittedCandidateGeometry(
            candidateID: record.candidateID,
            geometry: .polygon(
                DerivedPolygon(
                    vertices: [
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 1, y: 1),
                            supportEvidenceRefs: ["e"]
                        ),
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 2, y: 1),
                            supportEvidenceRefs: ["e"]
                        ),
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 2, y: 2),
                            supportEvidenceRefs: ["e"]
                        ),
                    ],
                    isConcave: false
                )
            )
        )
        XCTAssertEqual(selection.source, .derivedCandidate)
        let authority = try session.placementAuthority(
            for: selection.selectionID
        )
        XCTAssertTrue(
            authority.evidenceRefs.contains(
                "derived_candidate:\(record.candidateID)"
            )
        )
    }

    func testRefitCandidateFromPersistedContour() throws {
        let record = try ambiguousRecord()
        // A square-ish contour should re-derive at least one of the
        // ambiguous hypotheses under either fit configuration.
        let refit =
            record.refitCandidate(kind: .polygon)
            ?? record.refitCandidate(kind: .circle)
        XCTAssertNotNil(refit)
    }

    // MARK: - re-observation advisory -> guidance

    private func coverage(observedCellCount: Int) -> ScanCoverageSummary {
        var counts = Array(repeating: 0, count: 36)
        for index in 0..<min(observedCellCount, counts.count) {
            counts[index] = 2
        }
        return ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: counts,
            referenceYawRadians: 0,
            currentRelativeYawRadians: 0,
            currentPitchRadians: 0,
            latestTrackingState: .normal,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 1,
            latestHasSceneDepth: true,
            recommendedGap: nil
        )
    }

    private func spatial(
        cameraX: Double,
        cameraZ: Double,
        regions: [SpatialCoverageRegion]
    ) -> SpatialScanCoverageSummary {
        SpatialScanCoverageSummary(
            cellSizeMeters: 0.5,
            maxRegionCount: 256,
            referenceOriginWorld:
                SpatialCoveragePoint3D(x: 0, y: 0, z: 0),
            referenceYawRadians: 0,
            currentCameraPosition:
                SpatialCoveragePoint2D(x: cameraX, z: cameraZ),
            currentRelativeHeadingRadians: 0,
            latestTrackingState: .normal,
            latestHasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            regions: regions,
            displayBounds: SpatialCoverageBounds(
                minX: -6, maxX: 6, minZ: -6, maxZ: 6
            )
        )
    }

    private func region(
        key: SpatialCoverageCellKey,
        classification: SpatialCoverageClassification
    ) -> SpatialCoverageRegion {
        SpatialCoverageRegion(
            key: key,
            observationCount: 3,
            normalTrackingObservationCount: 3,
            limitedTrackingObservationCount: 0,
            lastObservedTimestampSeconds: 3,
            viewAngleBucketMask: 0b11,
            elevationBucketMask: 0,
            latestDistanceBucket: .near,
            depthObservationCount: 3,
            meshSupportCount: 3,
            classification: classification
        )
    }

    private func makeTracker() -> ScanMotionGuidanceTracker {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55
            )
        )
        tracker.setMovementCapability(.unrestricted)
        return tracker
    }

    func testFlaggedRegionEmitsReobserveGuidance() {
        var tracker = makeTracker()
        let key = SpatialCoverageCellKey(x: 4, z: 4)
        tracker.setDerivedReobservationCellKeys([key])
        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(observedCellCount: 10),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                regions: [region(key: key, classification: .observed)]
            ),
            observation: .empty
        )
        XCTAssertEqual(guidance?.action, .reobserveAnotherAngle)
        XCTAssertEqual(guidance?.targetRegionKey, key)
    }

    func testClearingFlaggedKeysDropsDerivedGuidance() {
        var tracker = makeTracker()
        let key = SpatialCoverageCellKey(x: 4, z: 4)
        tracker.setDerivedReobservationCellKeys([key])
        _ = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(observedCellCount: 10),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                regions: [region(key: key, classification: .observed)]
            ),
            observation: .empty
        )
        XCTAssertNotNil(tracker.guidance())
        tracker.setDerivedReobservationCellKeys([])
        XCTAssertNil(tracker.guidance())
    }

    func testDeclaredFlaggedRegionIsNotSelected() {
        var tracker = makeTracker()
        let key = SpatialCoverageCellKey(x: 4, z: 4)
        tracker.setDerivedReobservationCellKeys([key])
        tracker.setDeclaredRegionKeys([key])
        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(observedCellCount: 10),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                regions: [region(key: key, classification: .observed)]
            ),
            observation: .empty
        )
        XCTAssertNil(guidance)
    }

    func testSafetyConstrainedMovementSuppressesDerivedPrompt() {
        var tracker = makeTracker()
        let key = SpatialCoverageCellKey(x: 4, z: 4)
        tracker.setDerivedReobservationCellKeys([key])
        tracker.setMovementCapability(.safetyConstrained)
        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(observedCellCount: 10),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                regions: [region(key: key, classification: .observed)]
            ),
            observation: .empty
        )
        XCTAssertNil(guidance)
    }

    func testWeakFlaggedRegionKeptWhenFlagsCleared() {
        // A flagged cell that is also weak is owned by the coverage
        // flow — clearing the advisory set must not drop a prompt the
        // coverage evidence itself selected.
        var tracker = makeTracker()
        let key = SpatialCoverageCellKey(x: 4, z: 4)
        tracker.setDerivedReobservationCellKeys([key])
        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(observedCellCount: 10),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                regions: [region(key: key, classification: .weak)]
            ),
            observation: .empty
        )
        XCTAssertNotNil(guidance)
        tracker.setDerivedReobservationCellKeys([])
        XCTAssertNotNil(tracker.guidance())
    }

    // MARK: - derived_candidate: evidence congruence

    private func candidateDoc(
        candidateID: DerivedGeometryCandidateID,
        space: CoordinateSpaceID,
        declaredSpace: CoordinateSpaceID? = nil
    ) throws -> WorkingSetSupplementalDocument {
        let record = try DerivedGeometryCandidateRecord(
            candidateID: candidateID,
            resolution: .resolved,
            shapeKind: .circle,
            geometry: .circle(
                DerivedCircle(
                    center: DerivedPoint2D(x: 0, y: 0),
                    radius: 0.5
                )
            ),
            coordinateSpaceID: space,
            sourceMode: .classifiedMesh,
            sourceEvidenceRefs: ["capture_session:x"],
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            contourPoints: contour([(0, 0), (1, 0), (0, 1)])
        )
        let data = try JSONEncoder().encode(
            DerivedGeometryCandidateDocument(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: sessionID,
                candidates: [record]
            )
        )
        return try WorkingSetSupplementalDocument(
            path: DerivedGeometryCandidatePackage.path,
            data: data,
            declaration: BundlePayloadDeclaration(
                path: DerivedGeometryCandidatePackage.path,
                mediaType: "application/json",
                producer: "derived_geometry",
                provenanceClass: .captureAppDerived,
                role: .derived,
                sourceRefs: ["capture_session:x"]
            ),
            coordinateSpaceIDs: [declaredSpace ?? space],
            captureSessionIDs: [sessionID]
        )
    }

    private func annotationPackage(
        space: CoordinateSpaceID,
        evidenceRefs: [String]
    ) throws -> AnnotationEvidencePackage {
        try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .referencePoint,
                    coordinateSpaceID: space,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .userReferencePoint,
                    label: "promoted",
                    provenanceClass: .userAnnotation,
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    ),
                    evidenceRefs: evidenceRefs
                ),
            ]
        )
    }

    private func measurementPackage() throws
        -> MeasurementEvidencePackage
    {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "x_wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    func testDerivedCandidateEvidenceLinkResolvesAtCommit()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let candidateID = DerivedGeometryCandidateID()
        try await store.replaceSupplementalDocument(
            candidateDoc(candidateID: candidateID, space: spaceID)
        )
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: annotationPackage(
                space: spaceID,
                evidenceRefs: [
                    "derived_candidate:\(candidateID.description)"
                ]
            ),
            measurementPackage: try measurementPackage()
        )
    }

    func testDerivedCandidateEvidenceLinkUnknownIDFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.replaceSupplementalDocument(
            candidateDoc(
                candidateID: DerivedGeometryCandidateID(),
                space: spaceID
            )
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: annotationPackage(
                    space: spaceID,
                    evidenceRefs: [
                        "derived_candidate:\(DerivedGeometryCandidateID().description)"
                    ]
                ),
                measurementPackage: try measurementPackage()
            )
            XCTFail("unknown derived_candidate link must fail closed")
        } catch CaptureWorkingSetError.unresolvableSpatialEvidenceLink {
        }
    }

    func testDerivedCandidateEvidenceLinkSpaceMismatchFails()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let candidateID = DerivedGeometryCandidateID()
        // Candidate record persisted in a different space than the
        // entity, while the document declares the store's space so the
        // commit reaches the link-congruence check.
        try await store.replaceSupplementalDocument(
            candidateDoc(
                candidateID: candidateID,
                space: CoordinateSpaceID(),
                declaredSpace: spaceID
            )
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: annotationPackage(
                    space: spaceID,
                    evidenceRefs: [
                        "derived_candidate:\(candidateID.rawValue)"
                    ]
                ),
                measurementPackage: try measurementPackage()
            )
            XCTFail("cross-space derived_candidate link must fail")
        } catch CaptureWorkingSetError.spatialEvidenceSpaceMismatch {
        }
    }
}
