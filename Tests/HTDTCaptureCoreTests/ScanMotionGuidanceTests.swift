import XCTest
@testable import HTDTCaptureCore

final class ScanMotionGuidanceTests: XCTestCase {
    func testDirectionGapProducesRotateGuidance() {
        var tracker = ScanMotionGuidanceTracker()
        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: ScanCoverageGap(
                    sectorIndex: 3,
                    pitchBand: .level
                )
            ),
            spatialCoverage: .empty,
            observation: .empty
        )

        XCTAssertEqual(result?.action, .rotate)
        XCTAssertEqual(result?.horizontalDirection, .right)
    }

    func testPitchGapProducesTiltGuidance() {
        var tracker = ScanMotionGuidanceTracker()
        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: ScanCoverageGap(
                    sectorIndex: 0,
                    pitchBand: .high
                )
            ),
            spatialCoverage: .empty,
            observation: .empty
        )

        XCTAssertEqual(result?.action, .tilt)
        XCTAssertEqual(result?.verticalDirection, .up)
    }

    func testRepeatedSamePositionWeakRegionProducesTranslation() {
        var tracker = ScanMotionGuidanceTracker()
        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    observations: 3,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )

        XCTAssertEqual(result?.action, .translate)
        XCTAssertNotNil(result?.translationDirection)
    }

    func testTranslationAdvancesToOrbitAfterCameraBaselineChanges() {
        var tracker = ScanMotionGuidanceTracker()
        let key = SpatialCoverageCellKey(x: 2, z: 2)

        let initial = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 3,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(initial?.action, .translate)

        let advanced = tracker.record(
            timestampSeconds: 0.5,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0.35,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 4,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )

        XCTAssertEqual(advanced?.action, .orbit)
        XCTAssertEqual(advanced?.targetRegionKey, key)
    }

    func testNewAngleDiversityAndObservedRegionClearGuidance() {
        var tracker = ScanMotionGuidanceTracker()
        let key = SpatialCoverageCellKey(x: 2, z: 2)

        let first = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 3,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(first?.action, .translate)

        let cleared = tracker.record(
            timestampSeconds: 0.5,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0.35,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 4,
                    diversity: 2,
                    distance: .medium,
                    classification: .observed
                )
            ),
            observation: .empty
        )

        XCTAssertNil(cleared)
    }

    func testTrackingLimitedSuppressesMovementGuidance() {
        var tracker = ScanMotionGuidanceTracker()
        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: nil,
                tracking: .limited
            ),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    observations: 5,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )

        XCTAssertEqual(result?.action, .trackingRecovery)
        XCTAssertNil(result?.translationDirection)
    }

    func testGuidanceHysteresisPreventsRapidTranslateToApproachFlip() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumGuidanceDwellSeconds: 1.5
            )
        )
        let key = SpatialCoverageCellKey(x: 2, z: 2)

        let initial = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 3,
                    diversity: 1,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(initial?.action, .translate)

        let held = tracker.record(
            timestampSeconds: 0.5,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 4,
                    diversity: 2,
                    distance: .far,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(held?.action, .translate)

        let advanced = tracker.record(
            timestampSeconds: 2.0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 5,
                    diversity: 2,
                    distance: .far,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(advanced?.action, .approach)
    }

    func testWrapAroundDirectionUsesShortestYawAndTurnsRight() {
        var tracker = ScanMotionGuidanceTracker()
        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: ScanCoverageGap(
                    sectorIndex: 7,
                    pitchBand: .level
                ),
                currentYaw: degrees(170)
            ),
            spatialCoverage: .empty,
            observation: .empty
        )

        XCTAssertEqual(result?.action, .rotate)
        XCTAssertEqual(result?.horizontalDirection, .right)
    }

    func testLocalizedCopySupportsRequiredMovementPhrasesWithoutStepCounts() {
        let samples: [ScanMotionGuidance] = [
            ScanMotionGuidance(
                action: .rotate,
                horizontalDirection: .right
            ),
            ScanMotionGuidance(
                action: .rotate,
                horizontalDirection: .left
            ),
            ScanMotionGuidance(
                action: .tilt,
                verticalDirection: .up
            ),
            ScanMotionGuidance(
                action: .tilt,
                verticalDirection: .down
            ),
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .right
            ),
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .left
            ),
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .forward
            ),
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .backward
            ),
            ScanMotionGuidance(action: .approach),
            ScanMotionGuidance(action: .retreat),
            ScanMotionGuidance(action: .reobserveAnotherAngle),
            ScanMotionGuidance(action: .orbit),
            ScanMotionGuidance(action: .holdObserve),
        ]

        let japanese = samples.map {
            ScanMotionGuidanceCopy.prompt(
                for: $0,
                language: .japanese
            )
        }

        XCTAssertTrue(japanese.contains("その場で右を向いてください"))
        XCTAssertTrue(japanese.contains("その場で左を向いてください"))
        XCTAssertTrue(japanese.contains("上側を映してください"))
        XCTAssertTrue(japanese.contains("下側を映してください"))
        XCTAssertTrue(japanese.contains("少し右へ移動してください"))
        XCTAssertTrue(japanese.contains("少し左へ移動してください"))
        XCTAssertTrue(japanese.contains("少し前へ進んでください"))
        XCTAssertTrue(japanese.contains("少し下がってください"))
        XCTAssertTrue(japanese.contains("別角度から映してください"))
        XCTAssertTrue(japanese.contains("この領域の反対側へ回り込んでください"))
        XCTAssertTrue(japanese.contains("この方向をゆっくり映してください"))

        for prompt in japanese {
            XCTAssertFalse(prompt.contains("歩"))
            XCTAssertNil(
                prompt.range(
                    of: #"[0-9０-９]"#,
                    options: .regularExpression
                )
            )
        }

        for sample in samples {
            let english = ScanMotionGuidanceCopy.prompt(
                for: sample,
                language: .english
            )
            XCTAssertFalse(english.lowercased().contains("step"))
            XCTAssertNil(
                english.range(
                    of: #"[0-9]"#,
                    options: .regularExpression
                )
            )
        }
    }

    private func coverage(
        gap: ScanCoverageGap?,
        tracking: TrackingQualityState = .normal,
        currentYaw: Double = 0,
        currentPitch: Double = 0
    ) -> ScanCoverageSummary {
        ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 0, count: 36),
            referenceYawRadians: 0,
            currentRelativeYawRadians: currentYaw,
            currentPitchRadians: currentPitch,
            latestTrackingState: tracking,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 1,
            latestHasSceneDepth: true,
            recommendedGap: gap
        )
    }

    private func spatial(
        cameraX: Double,
        cameraZ: Double,
        region: SpatialCoverageRegion
    ) -> SpatialScanCoverageSummary {
        SpatialScanCoverageSummary(
            cellSizeMeters: 0.5,
            maxRegionCount: 256,
            referenceOriginWorld:
                SpatialCoveragePoint3D(x: 0, y: 0, z: 0),
            referenceYawRadians: 0,
            currentCameraPosition:
                SpatialCoveragePoint2D(
                    x: cameraX,
                    z: cameraZ
                ),
            currentRelativeHeadingRadians: 0,
            latestTrackingState: .normal,
            latestHasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            regions: [region],
            displayBounds: SpatialCoverageBounds(
                minX: -6,
                maxX: 6,
                minZ: -6,
                maxZ: 6
            )
        )
    }

    private func region(
        key: SpatialCoverageCellKey =
            SpatialCoverageCellKey(x: 2, z: 2),
        observations: Int,
        diversity: Int,
        distance: SpatialCoverageDistanceBucket,
        classification: SpatialCoverageClassification
    ) -> SpatialCoverageRegion {
        let mask: UInt16
        if diversity <= 0 {
            mask = 0
        } else {
            mask = (UInt16(1) << UInt16(min(diversity, 8))) - 1
        }

        return SpatialCoverageRegion(
            key: key,
            observationCount: observations,
            normalTrackingObservationCount: observations,
            limitedTrackingObservationCount: 0,
            lastObservedTimestampSeconds: Double(observations),
            viewAngleBucketMask: mask,
            latestDistanceBucket: distance,
            depthObservationCount: observations,
            meshSupportCount: observations,
            classification: classification
        )
    }

    private func degrees(_ value: Double) -> Double {
        value * Double.pi / 180
    }
}
