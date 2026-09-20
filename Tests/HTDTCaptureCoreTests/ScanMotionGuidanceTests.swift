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

    func testBroadDirectionCoverageCanPrioritizeTranslationOverRemainingRotationGap() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55
            )
        )

        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: ScanCoverageGap(
                    sectorIndex: 4,
                    pitchBand: .level
                ),
                observedCellCount: 24
            ),
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

    func testOrbitAdvancesWhenViewAngleDiversityIncreases() {
        var tracker = ScanMotionGuidanceTracker()
        let key = SpatialCoverageCellKey(x: 2, z: 2)

        _ = tracker.record(
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

        let orbit = tracker.record(
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
        XCTAssertEqual(orbit?.action, .orbit)

        let advanced = tracker.record(
            timestampSeconds: 0.75,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0.35,
                cameraZ: 0,
                region: region(
                    key: key,
                    observations: 5,
                    diversity: 2,
                    distance: .medium,
                    classification: .weak
                )
            ),
            observation: .empty
        )

        XCTAssertEqual(advanced?.action, .holdObserve)
        XCTAssertEqual(advanced?.targetRegionKey, key)
    }

    func testDistanceBucketCanProduceApproachAndRetreatOnlyAfterDiversity() {
        var approachTracker = ScanMotionGuidanceTracker()
        let far = approachTracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    observations: 3,
                    diversity: 2,
                    distance: .far,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(far?.action, .approach)
        XCTAssertEqual(far?.translationDirection, .forward)

        var retreatTracker = ScanMotionGuidanceTracker()
        let near = retreatTracker.record(
            timestampSeconds: 0,
            coverage: coverage(gap: nil),
            spatialCoverage: spatial(
                cameraX: 0,
                cameraZ: 0,
                region: region(
                    observations: 3,
                    diversity: 2,
                    distance: .near,
                    classification: .weak
                )
            ),
            observation: .empty
        )
        XCTAssertEqual(near?.action, .retreat)
        XCTAssertEqual(near?.translationDirection, .backward)
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

    func testWeakRegionGuidanceTimesOutAndSaturatesInsteadOfLoopingForever() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                maximumActionDurationSeconds: 1.0,
                maximumWeakRegionGuidanceAttempts: 2
            )
        )
        let weak = spatial(
            cameraX: 0,
            cameraZ: 0,
            region: region(
                observations: 4,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        let completeDirectionCoverage = coverage(
            gap: nil,
            observedCellCount: 36
        )

        let first = tracker.record(
            timestampSeconds: 0,
            coverage: completeDirectionCoverage,
            spatialCoverage: weak,
            observation: .empty
        )
        XCTAssertEqual(first?.action, .translate)

        let second = tracker.record(
            timestampSeconds: 1.1,
            coverage: completeDirectionCoverage,
            spatialCoverage: weak,
            observation: .empty
        )
        XCTAssertEqual(second?.action, .translate)

        let saturated = tracker.record(
            timestampSeconds: 2.2,
            coverage: completeDirectionCoverage,
            spatialCoverage: weak,
            observation: .empty
        )
        XCTAssertNil(saturated)
    }

    func testSaturatedWeakRegionDoesNotFallBackToTargetlessReobserve() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                maximumActionDurationSeconds: 1.0,
                maximumWeakRegionGuidanceAttempts: 1
            )
        )
        let weak = spatial(
            cameraX: 0,
            cameraZ: 0,
            region: region(
                observations: 4,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        let coverage = coverage(
            gap: nil,
            observedCellCount: 36
        )
        let recheck = ObservationStabilitySummary(
            sectorCount: 12,
            referenceYawRadians: 0,
            currentSectorIndex: 0,
            state: .accumulating,
            stabilityScore: 0.4,
            normalObservationCount: 10,
            viewAngleDiversityCount: 2,
            depthSupportFraction: 0.2,
            meshSupportFraction: 0,
            movementConsistencyFraction: 0.8,
            recheckReason: .supportingEvidenceWeak
        )

        let initial = tracker.record(
            timestampSeconds: 0,
            coverage: coverage,
            spatialCoverage: weak,
            observation: recheck
        )
        XCTAssertEqual(initial?.action, .translate)

        let saturated = tracker.record(
            timestampSeconds: 1.1,
            coverage: coverage,
            spatialCoverage: weak,
            observation: recheck
        )

        XCTAssertNil(saturated)
    }

    func testStationaryOnlyModeConvertsEarlyRecheckToInPlaceObservation() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                spatialGuidanceActivationCoverageFraction: 0.80
            )
        )
        tracker.setMovementCapability(.stationaryOnly)

        let recheck = ObservationStabilitySummary(
            sectorCount: 12,
            referenceYawRadians: 0,
            currentSectorIndex: 0,
            state: .accumulating,
            stabilityScore: 0.4,
            normalObservationCount: 8,
            viewAngleDiversityCount: 1,
            depthSupportFraction: 0.4,
            meshSupportFraction: 0,
            movementConsistencyFraction: 0.9,
            recheckReason: .supportingEvidenceWeak
        )

        let result = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: nil,
                observedCellCount: 20
            ),
            spatialCoverage: .empty,
            observation: recheck
        )

        XCTAssertEqual(result?.action, .holdObserve)
        XCTAssertNil(result?.translationDirection)
    }

    func testStationaryOnlyModeNeverEmitsTranslationBeforeSpatialActivation() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55
            )
        )
        tracker.setMovementCapability(.stationaryOnly)

        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: coverage(
                gap: nil,
                observedCellCount: 10
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

        XCTAssertNil(guidance)
    }

    func testStationaryOnlyModeSuppressesPhysicalMovementGuidanceAndCanComplete() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                completionDirectionCoverageFraction: 0.95
            )
        )
        tracker.setMovementCapability(.stationaryOnly)

        let weak = spatial(
            cameraX: 0,
            cameraZ: 0,
            region: region(
                observations: 5,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        let fullDirection = coverage(
            gap: nil,
            observedCellCount: 36
        )

        let guidance = tracker.record(
            timestampSeconds: 0,
            coverage: fullDirection,
            spatialCoverage: weak,
            observation: .empty
        )
        let progress = tracker.progress(
            coverage: fullDirection,
            spatialCoverage: weak
        )

        XCTAssertNil(guidance)
        XCTAssertEqual(
            progress.movementCapability,
            .stationaryOnly
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.actionableWeakRegionCount, 1)
    }

    func testGlobalSpatialGuidanceBudgetCompletesEvenAcrossDifferentWeakRegions() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                maximumActionDurationSeconds: 0.5,
                maximumWeakRegionGuidanceAttempts: 5,
                maximumSpatialGuidanceAttempts: 2,
                completionDirectionCoverageFraction: 0.95
            )
        )
        let keyA = SpatialCoverageCellKey(x: 2, z: 2)
        let keyB = SpatialCoverageCellKey(x: 3, z: 2)
        let fullDirection = coverage(
            gap: nil,
            observedCellCount: 36
        )

        let firstSpatial = spatial(
            cameraX: 0,
            cameraZ: 0,
            region: region(
                key: keyA,
                observations: 5,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        XCTAssertNotNil(
            tracker.record(
                timestampSeconds: 0,
                coverage: fullDirection,
                spatialCoverage: firstSpatial,
                observation: .empty
            )
        )
        _ = tracker.record(
            timestampSeconds: 0.6,
            coverage: fullDirection,
            spatialCoverage: firstSpatial,
            observation: .empty
        )

        let secondSpatial = spatial(
            cameraX: 0,
            cameraZ: 0,
            region: region(
                key: keyB,
                observations: 5,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        XCTAssertNotNil(
            tracker.record(
                timestampSeconds: 1.0,
                coverage: fullDirection,
                spatialCoverage: secondSpatial,
                observation: .empty
            )
        )
        let afterBudget = tracker.record(
            timestampSeconds: 1.6,
            coverage: fullDirection,
            spatialCoverage: secondSpatial,
            observation: .empty
        )
        let progress = tracker.progress(
            coverage: fullDirection,
            spatialCoverage: secondSpatial
        )

        XCTAssertNil(afterBudget)
        XCTAssertEqual(
            progress.completedSpatialGuidanceAttemptCount,
            2
        )
        XCTAssertTrue(progress.isComplete)
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
        currentPitch: Double = 0,
        observedCellCount: Int = 0
    ) -> ScanCoverageSummary {
        var counts = Array(repeating: 0, count: 36)
        for index in 0..<min(max(observedCellCount, 0), counts.count) {
            counts[index] = 2
        }

        return ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: counts,
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
