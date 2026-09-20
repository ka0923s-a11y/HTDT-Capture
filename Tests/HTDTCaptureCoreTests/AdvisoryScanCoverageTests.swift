import XCTest
@testable import HTDTCaptureCore

final class AdvisoryScanCoverageTests: XCTestCase {
    func testNormalSamplesEstablishReferenceAndObserveCells() {
        var tracker = AdvisoryScanCoverageTracker()

        let first = tracker.record(
            sample(
                yaw: 1.2,
                pitch: 0,
                tracking: .normal
            )
        )
        XCTAssertEqual(first.observedCellCount, 0)
        XCTAssertNotNil(first.referenceYawRadians)

        let second = tracker.record(
            sample(
                yaw: 1.2,
                pitch: 0,
                tracking: .normal
            )
        )

        XCTAssertEqual(second.observedCellCount, 1)
        XCTAssertTrue(
            second.isObserved(
                sectorIndex: 0,
                pitchBand: .level
            )
        )
        XCTAssertEqual(
            second.recommendedGap,
            ScanCoverageGap(
                sectorIndex: 1,
                pitchBand: .level
            )
        )
    }

    func testPitchBandsProduceIndependentCoverageCells() {
        var tracker = AdvisoryScanCoverageTracker()

        for pitch in [0.0, -0.6, 0.6] {
            _ = tracker.record(
                sample(
                    yaw: 0,
                    pitch: pitch,
                    tracking: .normal
                )
            )
            _ = tracker.record(
                sample(
                    yaw: 0,
                    pitch: pitch,
                    tracking: .normal
                )
            )
        }

        let summary = tracker.summary()
        XCTAssertEqual(
            summary.observedPitchBandCount(sectorIndex: 0),
            3
        )
        XCTAssertEqual(summary.observedCellCount, 3)
        XCTAssertEqual(
            summary.coverageFraction,
            3.0 / 36.0,
            accuracy: 0.000_001
        )
    }

    func testLimitedTrackingDoesNotAdvanceCoverage() {
        var tracker = AdvisoryScanCoverageTracker()

        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .limited
            )
        )
        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .limited
            )
        )

        var summary = tracker.summary()
        XCTAssertNil(summary.referenceYawRadians)
        XCTAssertEqual(summary.observedCellCount, 0)

        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal
            )
        )
        summary = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal
            )
        )

        XCTAssertEqual(summary.observedCellCount, 1)
    }

    private func sample(
        yaw: Double,
        pitch: Double,
        tracking: TrackingQualityState
    ) -> ScanCoverageSample {
        ScanCoverageSample(
            sessionTimestampSeconds: 1,
            yawRadians: yaw,
            pitchRadians: pitch,
            trackingState: tracking,
            activeMeshAnchorCount: 4,
            hasSceneDepth: true
        )
    }
}
