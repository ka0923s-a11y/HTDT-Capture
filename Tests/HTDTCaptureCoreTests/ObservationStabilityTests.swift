import XCTest
@testable import HTDTCaptureCore

final class ObservationStabilityTests: XCTestCase {
    func testRepeatedObservationTransitionsToAccumulating() {
        var tracker = ObservationStabilityTracker()

        let first = tracker.record(
            sample(yaw: 0, positionX: 0)
        )
        XCTAssertEqual(first.state, .provisional)
        XCTAssertEqual(first.normalObservationCount, 1)

        _ = tracker.record(
            sample(yaw: 0.04, positionX: 0.05)
        )
        let third = tracker.record(
            sample(yaw: -0.04, positionX: 0.10)
        )

        XCTAssertEqual(third.state, .accumulating)
        XCTAssertEqual(third.normalObservationCount, 3)
        XCTAssertFalse(third.recheckSuggested)
    }

    func testMultiAngleEvidenceRequiresRepeatedSupportBeforeWellObserved() {
        var tracker = ObservationStabilityTracker()
        let observations: [(Double, Double, Double)] = [
            (0.00, 0.00, 0.00),
            (-0.18, -0.50, 0.05),
            (0.00, 0.00, 0.10),
            (0.18, 0.50, 0.15),
            (-0.16, 0.00, 0.20),
            (0.16, -0.50, 0.25),
            (0.00, 0.50, 0.30),
            (-0.10, 0.00, 0.35),
        ]

        var summary = ObservationStabilitySummary.empty
        for (yaw, pitch, x) in observations {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: pitch,
                    positionX: x
                )
            )
        }

        XCTAssertEqual(summary.state, .wellObserved)
        XCTAssertGreaterThanOrEqual(
            summary.normalObservationCount,
            8
        )
        XCTAssertGreaterThanOrEqual(
            summary.viewAngleDiversityCount,
            3
        )
        XCTAssertGreaterThanOrEqual(
            summary.stabilityScore,
            0.68
        )
    }

    func testLimitedTrackingDoesNotIncreaseObservationConfidence() {
        var tracker = ObservationStabilityTracker()

        _ = tracker.record(
            sample(yaw: 0, positionX: 0)
        )
        let before = tracker.summary()

        for index in 1...8 {
            _ = tracker.record(
                sample(
                    yaw: Double(index) * 0.01,
                    positionX: Double(index) * 0.05,
                    tracking: .limited
                )
            )
        }

        let after = tracker.summary()
        XCTAssertEqual(
            after.normalObservationCount,
            before.normalObservationCount
        )
        XCTAssertEqual(after.state, .provisional)
    }

    func testWeakSupportingEvidenceAfterSufficientTrajectoryRequestsRecheck() {
        var tracker = ObservationStabilityTracker()

        let yaws = [
            0.00, -0.18, 0.00, 0.18, -0.16,
            0.16, -0.10, 0.10, -0.18, 0.18,
            0.00,
        ]

        var summary = ObservationStabilitySummary.empty
        for (index, yaw) in yaws.enumerated() {
            summary = tracker.record(
                sample(
                    yaw: yaw,
                    pitch: index % 3 == 0
                        ? -0.5
                        : (index % 3 == 1 ? 0 : 0.5),
                    positionX: Double(index) * 0.05,
                    meshCount: 0,
                    hasDepth: false
                )
            )
        }

        XCTAssertEqual(summary.state, .accumulating)
        XCTAssertTrue(summary.recheckSuggested)
        XCTAssertEqual(
            summary.recheckReason,
            .supportingEvidenceWeak
        )
    }

    private func sample(
        yaw: Double,
        pitch: Double = 0,
        positionX: Double,
        tracking: TrackingQualityState = .normal,
        meshCount: Int = 4,
        hasDepth: Bool = true
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
            trackingState: tracking,
            activeMeshAnchorCount: meshCount,
            hasSceneDepth: hasDepth
        )
    }
}
