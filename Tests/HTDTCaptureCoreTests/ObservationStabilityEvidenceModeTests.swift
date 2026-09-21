import XCTest
@testable import HTDTCaptureCore

final class ObservationStabilityEvidenceModeTests: XCTestCase {
    func testDepthFallbackSessionReachesWellObservedWithoutMesh() {
        var tracker = ObservationStabilityTracker()

        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in Self.wellObservedTrajectory {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 0,
                    hasDepth: true
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .depthOnly
        )
        XCTAssertEqual(summary.state, .wellObserved)
        XCTAssertEqual(summary.normalObservationCount, 11)
        XCTAssertEqual(summary.depthSupportFraction, 1)
        XCTAssertEqual(summary.meshSupportFraction, 0)
        // Unavailable mesh must not create a permanent recheck loop.
        XCTAssertFalse(summary.recheckSuggested)
    }

    func testDepthFallbackSessionWithSparseDepthStillFlagsWeakEvidence() {
        var tracker = ObservationStabilityTracker()

        var summary = ObservationStabilitySummary.empty
        for (index, step) in
            Self.wellObservedTrajectory.enumerated()
        {
            summary = tracker.record(
                sample(
                    yaw: step.0,
                    pitch: step.1,
                    positionX: step.2,
                    meshCount: 0,
                    hasDepth: index < 3
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .depthOnly
        )
        XCTAssertEqual(summary.state, .accumulating)
        XCTAssertTrue(summary.recheckSuggested)
        XCTAssertEqual(
            summary.recheckReason,
            .supportingEvidenceWeak
        )
    }

    func testMeshOnlySessionReachesWellObservedWithoutDepth() {
        var tracker = ObservationStabilityTracker()

        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in Self.wellObservedTrajectory {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 4,
                    hasDepth: false
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .meshOnly
        )
        XCTAssertEqual(summary.state, .wellObserved)
        XCTAssertEqual(summary.depthSupportFraction, 0)
        XCTAssertEqual(summary.meshSupportFraction, 1)
        XCTAssertFalse(summary.recheckSuggested)
    }

    func testMeshAndDepthSessionStillRequiresBothEvidencePaths() {
        var tracker = ObservationStabilityTracker()

        // Establish a combined mesh+depth session in sector 0.
        for (yaw, pitch, x) in Self.wellObservedTrajectory.prefix(4) {
            _ = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 4,
                    hasDepth: true
                )
            )
        }

        // The opposite sector is then observed through the depth path
        // only; mesh exists in this session so the stronger combined
        // criterion still applies to the region.
        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in Self.oppositeSectorTrajectory {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 0,
                    hasDepth: true
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .meshAndDepth
        )
        XCTAssertEqual(summary.state, .accumulating)
        XCTAssertEqual(
            summary.recheckReason,
            .supportingEvidenceWeak
        )

        // Once the region accumulates real mesh support the combined
        // criterion is satisfied and the recheck clears.
        for index in 0..<8 {
            let step = 0.55 + Double(index) * 0.05
            summary = tracker.record(
                sample(
                    yaw: index.isMultiple(of: 2)
                        ? .pi - 0.12
                        : .pi + 0.08,
                    pitch: index.isMultiple(of: 3)
                        ? -0.5
                        : 0.4,
                    positionX: step,
                    meshCount: 4,
                    hasDepth: true
                )
            )
        }

        XCTAssertEqual(summary.state, .wellObserved)
        XCTAssertFalse(summary.recheckSuggested)
    }

    func testSessionWithoutGeometryEvidenceCannotStabilize() {
        var tracker = ObservationStabilityTracker()

        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in Self.wellObservedTrajectory {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 0,
                    hasDepth: false
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .none
        )
        XCTAssertEqual(summary.state, .accumulating)
        XCTAssertTrue(summary.recheckSuggested)
        XCTAssertEqual(
            summary.recheckReason,
            .supportingEvidenceWeak
        )
    }

    func testMeshAnchorsArrivingLateRestoreCombinedCriterion() {
        var tracker = ObservationStabilityTracker()

        // A region that stabilizes while only depth evidence has been
        // observed...
        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in
            Self.wellObservedTrajectory.prefix(8)
        {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x,
                    meshCount: 0,
                    hasDepth: true
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .depthOnly
        )
        XCTAssertEqual(summary.state, .wellObserved)

        // ...remains stable once mesh anchors appear and the region
        // accumulates real mesh support under the combined criterion.
        for index in 0..<5 {
            summary = tracker.record(
                sample(
                    yaw: index.isMultiple(of: 2)
                        ? -0.12
                        : 0.10,
                    pitch: index.isMultiple(of: 3)
                        ? 0.5
                        : -0.4,
                    positionX: 0.40 + Double(index) * 0.05,
                    meshCount: 4,
                    hasDepth: true
                )
            )
        }

        XCTAssertEqual(
            summary.geometryEvidenceMode,
            .meshAndDepth
        )
        XCTAssertEqual(summary.state, .wellObserved)
        XCTAssertFalse(summary.recheckSuggested)
    }

    // All |yaw| <= 0.18 stays inside sector 0 (half width ~0.26) while
    // the pitch/yaw spread covers at least three view-angle buckets and
    // the 0.05 m steps keep movement consistent.
    private static let wellObservedTrajectory:
        [(Double, Double, Double)] = [
            (0.00, 0.00, 0.00),
            (-0.18, -0.50, 0.05),
            (0.00, 0.00, 0.10),
            (0.18, 0.50, 0.15),
            (-0.16, 0.00, 0.20),
            (0.16, -0.50, 0.25),
            (0.00, 0.50, 0.30),
            (-0.10, 0.00, 0.35),
            (0.10, -0.50, 0.40),
            (0.00, 0.00, 0.45),
            (-0.14, 0.50, 0.50),
        ]

    // Yaw around .pi lands in the opposite sector while the offsets and
    // pitch spread keep the same bucket diversity and movement pattern.
    private static let oppositeSectorTrajectory:
        [(Double, Double, Double)] = [
            (.pi, 0.00, 0.00),
            (.pi - 0.15, -0.50, 0.05),
            (.pi, 0.00, 0.10),
            (.pi + 0.15, 0.50, 0.15),
            (.pi - 0.14, 0.00, 0.20),
            (.pi + 0.14, -0.50, 0.25),
            (.pi, 0.50, 0.30),
            (.pi - 0.10, 0.00, 0.35),
            (.pi + 0.10, -0.50, 0.40),
            (.pi, 0.00, 0.45),
            (.pi - 0.12, 0.50, 0.50),
        ]

    private func sample(
        yaw: Double,
        pitch: Double = 0,
        positionX: Double,
        meshCount: Int,
        hasDepth: Bool
    ) -> ScanCoverageSample {
        ScanCoverageSample(
            sessionTimestampSeconds: positionX,
            yawRadians: yaw,
            pitchRadians: pitch,
            cameraPosition: ScanCameraPosition(
                x: positionX,
                y: 1.4,
                z: 0
            ),
            trackingState: .normal,
            activeMeshAnchorCount: meshCount,
            hasSceneDepth: hasDepth
        )
    }
}
