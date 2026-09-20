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
                tracking: .normal,
                timestamp: 0.25
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
        var timestamp = 0.0

        for pitch in [0.0, -0.6, 0.6] {
            _ = tracker.record(
                sample(
                    yaw: 0,
                    pitch: pitch,
                    tracking: .normal,
                    timestamp: timestamp
                )
            )
            timestamp += 0.25
            _ = tracker.record(
                sample(
                    yaw: 0,
                    pitch: pitch,
                    tracking: .normal,
                    timestamp: timestamp
                )
            )
            timestamp += 0.25
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
                tracking: .limited,
                timestamp: 0.25
            )
        )

        var summary = tracker.summary()
        XCTAssertNil(summary.referenceYawRadians)
        XCTAssertEqual(summary.observedCellCount, 0)

        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal,
                timestamp: 0.5
            )
        )
        summary = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal,
                timestamp: 0.75
            )
        )

        XCTAssertEqual(summary.observedCellCount, 1)
    }

    func testTargetSectorProducesSignedCurrentRelativeYawError() {
        let guidance = ScanCoverageGuidance.make(
            target: ScanCoverageGap(
                sectorIndex: 4,
                pitchBand: .level
            ),
            sectorCount: 12,
            currentRelativeYawRadians:
                degrees(40),
            currentPitchRadians: 0
        )

        XCTAssertNotNil(guidance)
        XCTAssertEqual(
            guidance?.targetYawRadians ?? 0,
            degrees(120),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            guidance?.signedYawErrorRadians ?? 0,
            degrees(80),
            accuracy: 0.000_001
        )
        XCTAssertEqual(guidance?.arrow, .right)
    }

    func testSignedYawErrorWrapsAcrossPlusMinus180() {
        XCTAssertEqual(
            ScanCoverageGuidance.signedYawError(
                targetYawRadians: degrees(-170),
                currentYawRadians: degrees(170)
            ),
            degrees(20),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ScanCoverageGuidance.signedYawError(
                targetYawRadians: degrees(170),
                currentYawRadians: degrees(-170)
            ),
            degrees(-20),
            accuracy: 0.000_001
        )
    }

    func testPitchBandGuidanceProducesVerticalDirection() {
        let high = ScanCoverageGuidance.make(
            target: ScanCoverageGap(
                sectorIndex: 0,
                pitchBand: .high
            ),
            sectorCount: 12,
            currentRelativeYawRadians: 0,
            currentPitchRadians: 0
        )
        let low = ScanCoverageGuidance.make(
            target: ScanCoverageGap(
                sectorIndex: 0,
                pitchBand: .low
            ),
            sectorCount: 12,
            currentRelativeYawRadians: 0,
            currentPitchRadians: 0
        )

        XCTAssertEqual(high?.arrow, .up)
        XCTAssertGreaterThan(high?.pitchErrorRadians ?? 0, 0)
        XCTAssertEqual(low?.arrow, .down)
        XCTAssertLessThan(low?.pitchErrorRadians ?? 0, 0)
    }

    func testTargetHysteresisHoldsThenAllowsMoreSevereGap() {
        let configuration = ScanGuidanceConfiguration(
            minimumTargetHoldSeconds: 1.0
        )
        var tracker = AdvisoryScanCoverageTracker(
            guidanceConfiguration: configuration
        )

        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal,
                timestamp: 0
            )
        )
        XCTAssertEqual(
            tracker.summary().recommendedGap,
            ScanCoverageGap(
                sectorIndex: 0,
                pitchBand: .level
            )
        )

        for (timestamp, pitch) in [
            (0.10, -0.6),
            (0.20, -0.6),
            (0.30, 0.6),
            (0.40, 0.6),
        ] {
            _ = tracker.record(
                sample(
                    yaw: 0,
                    pitch: pitch,
                    tracking: .normal,
                    timestamp: timestamp
                )
            )
        }

        XCTAssertEqual(
            tracker.summary().recommendedGap,
            ScanCoverageGap(
                sectorIndex: 0,
                pitchBand: .level
            )
        )

        _ = tracker.record(
            sample(
                yaw: degrees(30),
                pitch: -0.6,
                tracking: .normal,
                timestamp: 1.10
            )
        )

        XCTAssertEqual(
            tracker.summary().recommendedGap,
            ScanCoverageGap(
                sectorIndex: 1,
                pitchBand: .level
            )
        )
    }

    func testObservedTargetImmediatelySelectsNextGap() {
        var tracker = AdvisoryScanCoverageTracker(
            guidanceConfiguration:
                ScanGuidanceConfiguration(
                    minimumTargetHoldSeconds: 10
                )
        )

        _ = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal,
                timestamp: 0
            )
        )
        let completed = tracker.record(
            sample(
                yaw: 0,
                pitch: 0,
                tracking: .normal,
                timestamp: 0.25
            )
        )

        XCTAssertTrue(
            completed.isObserved(
                sectorIndex: 0,
                pitchBand: .level
            )
        )
        XCTAssertEqual(
            completed.recommendedGap,
            ScanCoverageGap(
                sectorIndex: 1,
                pitchBand: .level
            )
        )
    }

    private func sample(
        yaw: Double,
        pitch: Double,
        tracking: TrackingQualityState,
        timestamp: Double = 0
    ) -> ScanCoverageSample {
        ScanCoverageSample(
            sessionTimestampSeconds: timestamp,
            yawRadians: yaw,
            pitchRadians: pitch,
            trackingState: tracking,
            activeMeshAnchorCount: 4,
            hasSceneDepth: true
        )
    }

    private func degrees(_ value: Double) -> Double {
        value * Double.pi / 180
    }
}
