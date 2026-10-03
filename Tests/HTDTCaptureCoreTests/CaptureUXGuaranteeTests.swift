import XCTest
@testable import HTDTCaptureCore

/// Regression coverage for the capture-UX issue batch:
/// legacy bolph71656-ai/HTDT-Capture#295 permission-gate recovery, legacy bolph71656-ai/HTDT-Capture#336 coverage-capacity
/// observability, legacy bolph71656-ai/HTDT-Capture#347 global (viewport-independent) guidance
/// completeness, and legacy bolph71656-ai/HTDT-Capture#343 start-relative direction conventions.
final class CaptureUXGuaranteeTests: XCTestCase {

    // MARK: legacy bolph71656-ai/HTDT-Capture#295 — permission gate is a recoverable state

    func testPermissionsGateResetsToIdleWithoutFailure() throws {
        var machine = CaptureStateMachine(state: .permissions)
        try machine.apply(.reset)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.lastFailure)
    }

    func testCapabilityCheckResetsToIdleWithoutFailure() throws {
        var machine = CaptureStateMachine(state: .capabilityCheck)
        try machine.apply(.reset)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.lastFailure)
    }

    func testPermissionGateStillContinuesWhenGranted() throws {
        var machine = CaptureStateMachine(state: .permissions)
        try machine.apply(.permissionsGranted)
        XCTAssertEqual(machine.state, .preparing)
    }

    func testResetFromPermissionsDoesNotFailTheCapture() throws {
        var machine = CaptureStateMachine(state: .permissions)
        try machine.apply(.reset)
        // A cancelled permission gate must never surface as a failed
        // capture (legacy bolph71656-ai/HTDT-Capture#295): no failure code, no `.failed` state.
        XCTAssertNotEqual(machine.state, .failed)
        XCTAssertNil(machine.lastFailure)
    }

    func testScanningStillRejectsReset() {
        var machine = CaptureStateMachine(state: .scanning)
        XCTAssertThrowsError(try machine.apply(.reset))
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#336 — capacity eviction is never silent

    func testDefaultCoverageBudgetIsLargerThanLegacy() {
        // The legacy 256-cell budget forgot completed regions on an
        // ordinary room path; the new default covers a large
        // multi-room path while staying deterministically bounded.
        XCTAssertGreaterThanOrEqual(
            SpatialScanCoverageTracker.defaultMaxRegionCount,
            1024
        )
    }

    func testCapacityEvictionIsRecorded() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 2,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )

        _ = tracker.record(
            sample(timestamp: 1, points: [point(0.5, -0.5)])
        )
        _ = tracker.record(
            sample(timestamp: 2, points: [point(1.5, -0.5)])
        )
        let summary = tracker.record(
            sample(timestamp: 3, points: [point(2.5, -0.5)])
        )

        XCTAssertEqual(summary.knownRegionCount, 2)
        XCTAssertEqual(summary.capacity.maxRegionCount, 2)
        XCTAssertEqual(summary.capacity.peakRegionCount, 2)
        XCTAssertEqual(summary.capacity.regionEntryCount, 3)
        XCTAssertEqual(summary.capacity.evictionCount, 1)
        XCTAssertEqual(
            summary.capacity.firstEvictionTimestampSeconds,
            3
        )
        XCTAssertEqual(
            summary.capacity.lastEvictionTimestampSeconds,
            3
        )
        XCTAssertTrue(summary.capacity.isSaturated)
    }

    func testEvictionDropsLeastValuableRegionFirst() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 2,
            minimumNormalObservations: 2,
            minimumViewAngleBuckets: 2
        )

        // Promote cell (1, -1) to `.observed` with two
        // normal-tracking observations from different view angles.
        let observedPoint = point(0.5, -0.5)
        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [observedPoint]
            )
        )
        _ = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 2,
                cameraZ: 0,
                points: [observedPoint]
            )
        )

        // A single-observation weak cell.
        _ = tracker.record(
            sample(
                timestamp: 3,
                cameraX: 0,
                cameraZ: 0,
                points: [point(1.5, -0.5)]
            )
        )

        let summary = tracker.record(
            sample(
                timestamp: 4,
                cameraX: 0,
                cameraZ: 0,
                points: [point(2.5, -0.5)]
            )
        )

        let retained = Set(summary.regions.map(\.key))
        XCTAssertTrue(
            retained.contains(SpatialCoverageCellKey(x: 1, z: 1)),
            "a high-confidence observed region must survive eviction"
        )
        XCTAssertTrue(
            retained.contains(SpatialCoverageCellKey(x: 5, z: 1))
        )
        // The weak cell, not the observed one, paid the eviction.
        XCTAssertTrue(
            summary.wasRecentlyEvicted(
                at: SpatialCoverageCellKey(x: 3, z: 1)
            )
        )
        XCTAssertEqual(summary.capacity.evictionCount, 1)
    }

    func testWasRecentlyEvictedDistinguishesPreviouslyObserved() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 2,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )

        let evictedKey = SpatialCoverageCellKey(x: 1, z: 1)
        _ = tracker.record(
            sample(timestamp: 1, points: [point(0.5, -0.5)])
        )
        _ = tracker.record(
            sample(timestamp: 2, points: [point(1.5, -0.5)])
        )
        let summary = tracker.record(
            sample(timestamp: 3, points: [point(2.5, -0.5)])
        )

        // Previously observed but no longer retained.
        XCTAssertTrue(summary.wasRecentlyEvicted(at: evictedKey))
        // Never observed at all — a plain `unknown` cell.
        XCTAssertFalse(
            summary.wasRecentlyEvicted(
                at: SpatialCoverageCellKey(x: 99, z: 99)
            )
        )
        XCTAssertEqual(
            summary.classification(at: evictedKey),
            .unknown
        )
    }

    func testReobservationClearsTheEvictedMarker() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 2,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )

        let key = SpatialCoverageCellKey(x: 1, z: 1)
        _ = tracker.record(
            sample(timestamp: 1, points: [point(0.5, -0.5)])
        )
        _ = tracker.record(
            sample(timestamp: 2, points: [point(1.5, -0.5)])
        )
        _ = tracker.record(
            sample(timestamp: 3, points: [point(2.5, -0.5)])
        )
        XCTAssertTrue(
            tracker.summary().wasRecentlyEvicted(at: key)
        )

        // Observing the dropped cell again re-enters it; it is no
        // longer "previously observed but no longer retained".
        let summary = tracker.record(
            sample(timestamp: 4, points: [point(0.5, -0.5)])
        )
        XCTAssertFalse(summary.wasRecentlyEvicted(at: key))
        XCTAssertNotEqual(
            summary.classification(at: key),
            .unknown
        )
    }

    func testEvictedKeyRecencyListStaysBounded() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 3,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )

        // Force many evictions; the recency list must never grow
        // beyond the configured budget.
        for index in 0..<10 {
            _ = tracker.record(
                sample(
                    timestamp: Double(index + 1),
                    points: [point(Double(index) + 0.5, -0.5)]
                )
            )
        }

        let summary = tracker.summary()
        XCTAssertLessThanOrEqual(
            summary.recentlyEvictedKeys.count,
            summary.capacity.maxRegionCount
        )
        XCTAssertEqual(
            summary.capacity.evictionCount,
            7
        )
        XCTAssertEqual(summary.capacity.regionEntryCount, 10)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#347 — completeness is global, not viewport-local

    func testRemoteWeakRegionIsCountedOutsideDisplayWindow() {
        let tracker = ScanMotionGuidanceTracker()
        let remote = region(
            key: SpatialCoverageCellKey(x: 20, z: 0),
            classification: .weak
        )
        // Display window only spans ±3 cells around the origin — the
        // weak region at x=20 is outside it.
        let spatial = spatial(
            cameraX: 0,
            cameraZ: 0,
            regions: [remote],
            displayRadiusCells: 3
        )

        let progress = tracker.progress(
            coverage: coverage(observedCellCount: 36),
            spatialCoverage: spatial
        )

        XCTAssertEqual(progress.remoteWeakRegionCount, 1)
        // The remote weak region still counts as actionable — walking
        // away from it must not complete the spatial dimension.
        XCTAssertEqual(progress.actionableWeakRegionCount, 1)
        XCTAssertFalse(progress.isComplete)
    }

    func testSpatialCompletenessDoesNotDependOnViewport() {
        let tracker = ScanMotionGuidanceTracker()
        let weak = region(
            key: SpatialCoverageCellKey(x: 20, z: 0),
            classification: .weak
        )

        // Narrow viewport centered on the camera: the weak cell is
        // invisible on the map yet completion must stay false.
        let narrow = spatial(
            cameraX: 0,
            cameraZ: 0,
            regions: [weak],
            displayRadiusCells: 1
        )
        let progress = tracker.progress(
            coverage: coverage(observedCellCount: 36),
            spatialCoverage: narrow
        )
        XCTAssertFalse(progress.isComplete)

        // Same retained evidence seen from the weak cell's own
        // neighbourhood — identical unresolved count.
        let near = spatial(
            cameraX: 10,
            cameraZ: 0,
            regions: [weak],
            displayRadiusCells: 1
        )
        let nearbyProgress = tracker.progress(
            coverage: coverage(observedCellCount: 36),
            spatialCoverage: near
        )
        XCTAssertEqual(
            nearbyProgress.actionableWeakRegionCount,
            progress.actionableWeakRegionCount
        )
        XCTAssertEqual(nearbyProgress.remoteWeakRegionCount, 0)
        XCTAssertFalse(nearbyProgress.isComplete)
    }

    func testAllWeakResolvedCompletesRegardlessOfRemotePlacement() {
        let tracker = ScanMotionGuidanceTracker()
        let observed = region(
            key: SpatialCoverageCellKey(x: 20, z: 0),
            classification: .observed
        )
        let spatial = spatial(
            cameraX: 0,
            cameraZ: 0,
            regions: [observed],
            displayRadiusCells: 1
        )
        let progress = tracker.progress(
            coverage: coverage(observedCellCount: 36),
            spatialCoverage: spatial
        )
        XCTAssertEqual(progress.remoteWeakRegionCount, 0)
        XCTAssertEqual(progress.actionableWeakRegionCount, 0)
        XCTAssertTrue(progress.isComplete)
    }

    func testDeclaredRemoteRegionStopsCountingAsUnresolved() {
        var tracker = ScanMotionGuidanceTracker()
        let key = SpatialCoverageCellKey(x: 20, z: 0)
        tracker.setDeclaredRegionKeys([key])
        let spatial = spatial(
            cameraX: 0,
            cameraZ: 0,
            regions: [
                region(key: key, classification: .weak)
            ],
            displayRadiusCells: 1
        )
        let progress = tracker.progress(
            coverage: coverage(observedCellCount: 36),
            spatialCoverage: spatial
        )
        XCTAssertEqual(progress.remoteWeakRegionCount, 0)
        XCTAssertEqual(progress.actionableWeakRegionCount, 0)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#343 — direction labels are start-relative

    func testOctantMappingCoversAllEightDirections() {
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: 0
            ),
            .ahead
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: .pi / 4
            ),
            .aheadRight
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: .pi / 2
            ),
            .right
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: 3 * .pi / 4
            ),
            .behindRight
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: .pi
            ),
            .behind
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: -3 * .pi / 4
            ),
            .behindLeft
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: -.pi / 2
            ),
            .left
        )
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: -.pi / 4
            ),
            .aheadLeft
        )
        // Wrapped negatives land on the same octant.
        XCTAssertEqual(
            StartRelativeDirection.octant(
                forRelativeAngleRadians: -.pi / 2 + 2 * .pi
            ),
            .left
        )
    }

    func testSectorLabelsAreOffsetsFromStartDirection() {
        // Sector 0 is the start direction itself.
        XCTAssertEqual(
            StartRelativeDirection.sectorOffsetDegrees(
                sectorIndex: 0,
                sectorCount: 12
            ),
            0
        )
        XCTAssertEqual(
            StartRelativeDirection.sectorSignedDegrees(
                sectorIndex: 3,
                sectorCount: 12
            ),
            90
        )
        // The far half wraps to signed left-of-start values.
        XCTAssertEqual(
            StartRelativeDirection.sectorSignedDegrees(
                sectorIndex: 9,
                sectorCount: 12
            ),
            -90
        )
        XCTAssertEqual(
            StartRelativeDirection.sectorSignedDegrees(
                sectorIndex: 6,
                sectorCount: 12
            ),
            180
        )
        // Out-of-range indices wrap deterministically.
        XCTAssertEqual(
            StartRelativeDirection.sectorSignedDegrees(
                sectorIndex: -3,
                sectorCount: 12
            ),
            -90
        )
    }

    func testDirectionConventionIdentifierIsStable() {
        // Persisted advisory payloads record the convention; the
        // identifier is contractual so consumers can distinguish it
        // from a future room-relative authority (legacy bolph71656-ai/HTDT-Capture#232).
        XCTAssertEqual(
            StartRelativeDirection.convention,
            "start_relative"
        )
    }

    // MARK: persisted advisory back-compat (legacy bolph71656-ai/HTDT-Capture#336/legacy bolph71656-ai/HTDT-Capture#343/legacy bolph71656-ai/HTDT-Capture#347)

    func testEndCoverageSummaryDecodesPreChangePayload() throws {
        // A v1.0.0 advisory written before the scope/capacity/
        // convention fields existed must still decode.
        let legacy = """
        {
            "algorithm": "advisory-scan-coverage",
            "algorithm_version": "1.0.0",
            "end_session_timestamp_seconds": 12.5,
            "sector_count": 12,
            "minimum_samples_per_cell": 2,
            "cell_sample_counts": [0, 2, 0],
            "coverage_fraction": 0.75,
            "pitch_band_fractions": {},
            "weak_cells": [],
            "latest_tracking_state": "normal",
            "latest_tracking_reason": null,
            "latest_mesh_anchor_count": 4,
            "latest_has_scene_depth": true,
            "spatial_cell_size_meters": 0.5,
            "observed_region_count": 10,
            "weak_region_count": 2,
            "display_unknown_region_count": 3,
            "uses_depth_fallback": false,
            "mesh_availability_state": "anchors_observed",
            "weak_region_keys": ["1,1"],
            "geometry_evidence_mode": "mesh",
            "movement_capability": "unrestricted",
            "guidance_completed_attempts": 1,
            "guidance_maximum_attempts": 6,
            "actionable_weak_region_count": 2,
            "saturated_weak_region_count": 0,
            "guidance_complete": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            CaptureEndCoverageSummary.self,
            from: legacy
        )
        XCTAssertEqual(decoded.weakRegionCount, 2)
        XCTAssertNil(decoded.remoteWeakRegionCount)
        XCTAssertNil(decoded.spatialMaxRegionCount)
        XCTAssertNil(decoded.spatialPeakRegionCount)
        XCTAssertNil(decoded.spatialRegionEvictionCount)
        XCTAssertNil(decoded.spatialCapacitySaturated)
        XCTAssertNil(decoded.directionReference)
    }

    func testEndCoverageSummaryRoundTripsNewScopeFields() throws {
        let summary = CaptureEndCoverageSummary(
            algorithm: "advisory-scan-coverage",
            algorithmVersion: "1.0.0",
            endSessionTimestampSeconds: 12.5,
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: [0, 2, 0],
            coverageFraction: 0.75,
            pitchBandFractions: [:],
            weakCells: [],
            latestTrackingState: .normal,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 4,
            latestHasSceneDepth: true,
            spatialCellSizeMeters: 0.5,
            observedRegionCount: 10,
            weakRegionCount: 2,
            displayUnknownRegionCount: 3,
            usesDepthFallback: false,
            meshAvailabilityState: "anchors_observed",
            weakRegionKeys: ["1,1"],
            geometryEvidenceMode: "mesh",
            movementCapability: "unrestricted",
            guidanceCompletedAttempts: 1,
            guidanceMaximumAttempts: 6,
            actionableWeakRegionCount: 2,
            saturatedWeakRegionCount: 0,
            guidanceComplete: false,
            remoteWeakRegionCount: 1,
            spatialMaxRegionCount: 2048,
            spatialPeakRegionCount: 16,
            spatialRegionEvictionCount: 3,
            spatialCapacitySaturated: true,
            directionReference: StartRelativeDirection.convention
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(
            CaptureEndCoverageSummary.self,
            from: data
        )
        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.remoteWeakRegionCount, 1)
        XCTAssertEqual(decoded.spatialRegionEvictionCount, 3)
        XCTAssertEqual(decoded.spatialCapacitySaturated, true)
        XCTAssertEqual(decoded.directionReference, "start_relative")
    }

    // MARK: - fixtures

    private func point(_ x: Double, _ z: Double)
        -> SpatialCoveragePoint3D
    {
        SpatialCoveragePoint3D(x: x, y: 0, z: z)
    }

    private func sample(
        timestamp: Double,
        cameraX: Double = 0,
        cameraZ: Double = 0,
        tracking: TrackingQualityState = .normal,
        points: [SpatialCoveragePoint3D]
    ) -> SpatialCoverageSample {
        SpatialCoverageSample(
            sessionTimestampSeconds: timestamp,
            cameraPositionWorld:
                SpatialCoveragePoint3D(x: cameraX, y: 1.5, z: cameraZ),
            cameraYawRadians: 0,
            trackingState: tracking,
            hasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            surfacePointsWorld: points
        )
    }

    private func region(
        key: SpatialCoverageCellKey,
        classification: SpatialCoverageClassification
    ) -> SpatialCoverageRegion {
        SpatialCoverageRegion(
            key: key,
            observationCount: 2,
            normalTrackingObservationCount: 2,
            limitedTrackingObservationCount: 0,
            lastObservedTimestampSeconds: 1,
            viewAngleBucketMask: 0b11,
            elevationBucketMask: 0,
            latestDistanceBucket: .near,
            depthObservationCount: 0,
            meshSupportCount: 2,
            classification: classification
        )
    }

    private func spatial(
        cameraX: Double,
        cameraZ: Double,
        regions: [SpatialCoverageRegion],
        displayRadiusCells: Int
    ) -> SpatialScanCoverageSummary {
        let center = SpatialCoverageCellKey(
            x: Int(floor(cameraX / 0.5)),
            z: Int(floor(cameraZ / 0.5))
        )
        return SpatialScanCoverageSummary(
            cellSizeMeters: 0.5,
            maxRegionCount: SpatialScanCoverageTracker
                .defaultMaxRegionCount,
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
                minX: center.x - displayRadiusCells,
                maxX: center.x + displayRadiusCells,
                minZ: center.z - displayRadiusCells,
                maxZ: center.z + displayRadiusCells
            )
        )
    }

    private func coverage(
        observedCellCount: Int
    ) -> ScanCoverageSummary {
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
}
