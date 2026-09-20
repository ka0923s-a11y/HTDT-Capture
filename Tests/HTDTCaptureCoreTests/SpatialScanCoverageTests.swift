import XCTest
@testable import HTDTCaptureCore

final class SpatialScanCoverageTests: XCTestCase {
    func testRepeatedObservationsAccumulateInSameRegion() {
        var tracker = SpatialScanCoverageTracker()

        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [point(1, -1)]
            )
        )
        let summary = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 0,
                cameraZ: 0,
                points: [point(1.1, -1.1)]
            )
        )

        XCTAssertEqual(summary.knownRegionCount, 1)
        XCTAssertEqual(summary.regions.first?.observationCount, 2)
        XCTAssertEqual(summary.regions.first?.classification, .weak)
    }

    func testViewAngleDiversityAccumulates() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 4,
            minimumViewAngleBuckets: 2
        )
        let surface = point(1, -1)

        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [surface]
            )
        )
        _ = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 0,
                cameraZ: 0,
                points: [surface]
            )
        )
        let diversified = tracker.record(
            sample(
                timestamp: 3,
                cameraX: 2,
                cameraZ: 0,
                points: [surface]
            )
        )

        XCTAssertGreaterThanOrEqual(
            diversified.regions.first?.viewAngleDiversityCount ?? 0,
            2
        )
    }

    func testLimitedTrackingCannotPromoteObserved() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 2,
            minimumViewAngleBuckets: 1
        )
        let surface = point(1, -1)

        _ = tracker.record(
            sample(
                timestamp: 0,
                cameraX: 0,
                cameraZ: 0,
                tracking: .normal,
                points: [surface]
            )
        )

        for timestamp in 1...5 {
            _ = tracker.record(
                sample(
                    timestamp: Double(timestamp),
                    cameraX: 0,
                    cameraZ: 0,
                    tracking: .limited,
                    points: [surface]
                )
            )
        }

        let region = tracker.summary().regions.first
        XCTAssertEqual(region?.limitedTrackingObservationCount, 5)
        XCTAssertEqual(region?.normalTrackingObservationCount, 1)
        XCTAssertEqual(region?.classification, .weak)
    }

    func testMeshAvailabilityDistinguishesThreeStates() {
        XCTAssertEqual(
            MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: false,
                sceneReconstructionEnabled: false,
                activeMeshAnchorCount: 0
            ).state,
            .unavailable
        )
        XCTAssertEqual(
            MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 0
            ).state,
            .enabledNoAnchors
        )
        XCTAssertEqual(
            MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 2
            ).state,
            .anchorsObserved
        )
        XCTAssertEqual(
            MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: false,
                activeMeshAnchorCount: 1,
                configurationMismatchSuspected: true
            ).state,
            .anchorsObserved
        )
    }

    func testWeakTransitionsToObservedAfterNormalDiverseViews() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 3,
            minimumViewAngleBuckets: 2
        )
        let surface = point(1, -1)

        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [surface]
            )
        )
        XCTAssertEqual(
            tracker.summary().regions.first?.classification,
            .weak
        )

        _ = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 2,
                cameraZ: 0,
                points: [surface]
            )
        )
        let observed = tracker.record(
            sample(
                timestamp: 3,
                cameraX: 0,
                cameraZ: 0,
                points: [surface]
            )
        )

        XCTAssertEqual(
            observed.regions.first?.classification,
            .observed
        )
    }

    func testRegionStorageIsBoundedAndEvictsOldest() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 2,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )

        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [point(0.5, -0.5)]
            )
        )
        _ = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 0,
                cameraZ: 0,
                points: [point(1.5, -0.5)]
            )
        )
        let summary = tracker.record(
            sample(
                timestamp: 3,
                cameraX: 0,
                cameraZ: 0,
                points: [point(2.5, -0.5)]
            )
        )

        XCTAssertEqual(summary.knownRegionCount, 2)
        XCTAssertLessThanOrEqual(
            summary.knownRegionCount,
            summary.maxRegionCount
        )
        XCTAssertNil(
            summary.region(
                at: SpatialCoverageCellKey(x: 1, z: 1)
            )
        )
    }

    func testUnknownMeansNoObservationAuthority() {
        var tracker = SpatialScanCoverageTracker()
        let summary = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: []
            )
        )

        XCTAssertEqual(summary.knownRegionCount, 0)
        XCTAssertEqual(
            summary.classification(
                at: SpatialCoverageCellKey(x: 4, z: 4)
            ),
            .unknown
        )
        XCTAssertGreaterThan(summary.displayUnknownRegionCount, 0)
    }

    private func point(
        _ x: Double,
        _ z: Double
    ) -> SpatialCoveragePoint3D {
        SpatialCoveragePoint3D(x: x, y: 0, z: z)
    }

    private func sample(
        timestamp: Double,
        cameraX: Double,
        cameraZ: Double,
        tracking: TrackingQualityState = .normal,
        points: [SpatialCoveragePoint3D]
    ) -> SpatialCoverageSample {
        SpatialCoverageSample(
            sessionTimestampSeconds: timestamp,
            cameraPositionWorld: SpatialCoveragePoint3D(
                x: cameraX,
                y: 1.5,
                z: cameraZ
            ),
            cameraYawRadians: 0,
            trackingState: tracking,
            hasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: points.isEmpty ? 0 : 1
            ),
            surfacePointsWorld: points
        )
    }
}
