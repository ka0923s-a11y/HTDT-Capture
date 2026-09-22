import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - #342: octant vocabulary

@Test
func octantSectorMappingMatchesTwelveSectorGridLabels() {
    // The 12-sector grid maps to eight principal directions exactly
    // like the visual cell labels: sector pairs share an octant.
    let expected: [ScanDirectionOctant] = [
        .front,
        .frontRight, .frontRight,
        .right,
        .rearRight, .rearRight,
        .rear,
        .rearLeft, .rearLeft,
        .left,
        .frontLeft, .frontLeft,
    ]
    for (sector, octant) in expected.enumerated() {
        #expect(
            ScanDirectionOctant(
                sectorIndex: sector,
                sectorCount: 12
            ) == octant,
            "sector \(sector) should map to \(octant)"
        )
    }
}

@Test
func octantAzimuthMappingMatchesRegionLabelMath() {
    // Azimuth clockwise from +z buckets into 45°-wide sectors
    // centered on the principal directions.
    #expect(
        ScanDirectionOctant(azimuthRadians: 0) == .front
    )
    #expect(
        ScanDirectionOctant(azimuthRadians: .pi / 4) == .frontRight
    )
    #expect(
        ScanDirectionOctant(azimuthRadians: .pi / 2) == .right
    )
    #expect(
        ScanDirectionOctant(azimuthRadians: .pi) == .rear
    )
    #expect(
        ScanDirectionOctant(azimuthRadians: -.pi / 4) == .frontLeft
    )
    #expect(
        ScanDirectionOctant(azimuthRadians: -.pi / 2) == .left
    )
    // Just inside each 45° window still resolves to that direction.
    #expect(
        ScanDirectionOctant(
            azimuthRadians: .pi / 4 - 0.01
        ) == .frontRight
    )
    #expect(
        ScanDirectionOctant(
            azimuthRadians: .pi / 8 + 0.01
        ) == .frontRight
    )
}

@Test
func octantNamesRenderInBothLanguages() {
    #expect(
        ScanDirectionOctant.rearLeft
            .name(language: .english) == "rear left"
    )
    #expect(
        ScanDirectionOctant.rearLeft
            .name(language: .japanese) == "左後方"
    )
    #expect(
        ScanDirectionOctant.front
            .name(language: .english) == "front"
    )
    #expect(
        ScanDirectionOctant.front
            .name(language: .japanese) == "前方"
    )
}

// MARK: - #342: direction coverage summary

private func makeCoverage(
    observed: Set<Int>,
    recommendedGap: ScanCoverageGap? = nil
) -> ScanCoverageSummary {
    var counts = Array(repeating: 0, count: 36)
    for index in observed {
        counts[index] = 2
    }
    return ScanCoverageSummary(
        sectorCount: 12,
        minimumSamplesPerCell: 2,
        cellSampleCounts: counts,
        referenceYawRadians: 0,
        currentRelativeYawRadians: 0,
        currentPitchRadians: 0,
        latestTrackingState: nil,
        latestTrackingReason: nil,
        latestMeshAnchorCount: 0,
        latestHasSceneDepth: false,
        recommendedGap: recommendedGap
    )
}

private func cellIndex(
    _ sector: Int,
    _ band: ScanCoveragePitchBand
) -> Int {
    sector * 3 + band.rawValue
}

@Test
func directionSummaryReportsPercentAndMissingBands() {
    // Observe everything except the low band of sectors 6..8
    // (rear / rear-left octants).
    var observed = Set(0..<36)
    for sector in 6...8 {
        observed.remove(cellIndex(sector, .low))
    }
    let summary = DirectionCoverageAccessibilitySummary(
        coverage: makeCoverage(
            observed: observed,
            recommendedGap: ScanCoverageGap(
                sectorIndex: 6,
                pitchBand: .low
            )
        )
    )
    #expect(summary.coveragePercent == 92)
    #expect(summary.missingBands.count == 1)
    let missing = try? #require(summary.missingBands.first)
    #expect(missing?.band == .low)
    #expect(
        missing?.octants == [.rear, .rearLeft]
    )
    #expect(summary.nextTargetOctant == .rear)
}

@Test
func directionSummaryEnglishTextIsOneCompactReadout() {
    var observed = Set(0..<36)
    for sector in 6...8 {
        observed.remove(cellIndex(sector, .low))
    }
    let text = ScanAccessibilityText.directionCoverage(
        DirectionCoverageAccessibilitySummary(
            coverage: makeCoverage(
                observed: observed,
                recommendedGap: ScanCoverageGap(
                    sectorIndex: 6,
                    pitchBand: .low
                )
            )
        ),
        language: .english
    )
    #expect(text.hasPrefix("Direction coverage 92 percent."))
    #expect(text.contains("lower room missing: rear, rear left."))
    #expect(text.contains("Next target: rear, lower room."))
}

@Test
func directionSummaryJapaneseTextSharesVocabulary() {
    var observed = Set(0..<36)
    for sector in 6...8 {
        observed.remove(cellIndex(sector, .low))
    }
    let text = ScanAccessibilityText.directionCoverage(
        DirectionCoverageAccessibilitySummary(
            coverage: makeCoverage(observed: observed)
        ),
        language: .japanese
    )
    #expect(text.hasPrefix("方向カバレッジ 92%。"))
    #expect(text.contains("下部が未走査：後方、左後方。"))
}

@Test
func directionSummaryEmptyCoverageHasNoMissingBands() {
    let summary = DirectionCoverageAccessibilitySummary(
        coverage: makeCoverage(observed: Set(0..<36))
    )
    #expect(summary.missingBands.isEmpty)
    #expect(summary.coveragePercent == 100)
    let text = ScanAccessibilityText.directionCoverage(
        summary,
        language: .english
    )
    #expect(text == "Direction coverage 100 percent.")
}

// MARK: - #342: spatial coverage summary

private func makeRegion(
    x: Int,
    z: Int,
    classification: SpatialCoverageClassification,
    observationCount: Int = 1,
    distanceBucket: SpatialCoverageDistanceBucket = .near
) -> SpatialCoverageRegion {
    SpatialCoverageRegion(
        key: SpatialCoverageCellKey(x: x, z: z),
        observationCount: observationCount,
        normalTrackingObservationCount: observationCount,
        limitedTrackingObservationCount: 0,
        lastObservedTimestampSeconds: 0,
        viewAngleBucketMask: 1,
        elevationBucketMask: 0,
        latestDistanceBucket: distanceBucket,
        depthObservationCount: 0,
        meshSupportCount: 1,
        classification: classification
    )
}

private func makeSpatialCoverage(
    regions: [SpatialCoverageRegion],
    cameraPosition: SpatialCoveragePoint2D? = nil,
    headingRadians: Double? = nil
) -> SpatialScanCoverageSummary {
    SpatialScanCoverageSummary(
        cellSizeMeters: 0.5,
        maxRegionCount: 256,
        referenceOriginWorld: SpatialCoveragePoint3D(
            x: 0, y: 0, z: 0
        ),
        referenceYawRadians: 0,
        currentCameraPosition: cameraPosition,
        currentRelativeHeadingRadians: headingRadians,
        latestTrackingState: nil,
        latestHasSceneDepth: true,
        meshAvailability: MeshAvailabilityDiagnostic(
            sceneReconstructionSupported: true,
            sceneReconstructionEnabled: true,
            activeMeshAnchorCount: 4,
            activeConfigurationName: nil,
            configurationMismatchSuspected: false
        ),
        regions: regions,
        displayBounds: nil
    )
}

@Test
func spatialSummaryPrioritizesLeastObservedWeakRegions() {
    let coverage = makeSpatialCoverage(
        regions: [
            makeRegion(
                x: 0, z: 3,
                classification: .observed,
                observationCount: 12
            ),
            makeRegion(
                x: 2, z: 0,
                classification: .weak,
                observationCount: 4
            ),
            makeRegion(
                x: -2, z: 0,
                classification: .weak,
                observationCount: 1
            ),
            makeRegion(
                x: 0, z: -3,
                classification: .weak,
                observationCount: 2
            ),
        ]
    )
    let summary = SpatialCoverageAccessibilitySummary(
        coverage: coverage
    )
    #expect(summary.observedRegionCount == 1)
    #expect(summary.weakRegionCount == 3)
    #expect(summary.priorityWeakRegions.count == 3)
    // Least-observed first: x=-2 (count 1), x=0 z=-3 (2), x=2 (4).
    #expect(
        summary.priorityWeakRegions.map { $0.key }
            == [
                SpatialCoverageCellKey(x: -2, z: 0),
                SpatialCoverageCellKey(x: 0, z: -3),
                SpatialCoverageCellKey(x: 2, z: 0),
            ]
    )
}

@Test
func spatialSummaryBoundsThePrioritizedList() {
    let coverage = makeSpatialCoverage(
        regions: (0..<6).map {
            makeRegion(
                x: $0, z: 1,
                classification: .weak,
                observationCount: $0 + 1
            )
        }
    )
    let summary = SpatialCoverageAccessibilitySummary(
        coverage: coverage
    )
    #expect(
        summary.priorityWeakRegions.count
            == SpatialCoverageAccessibilitySummary
                .maximumPrioritizedRegions
    )
}

@Test
func spatialSummaryExcludesDeclaredRegionsFromPriorityList() {
    let declared = SpatialCoverageCellKey(x: -2, z: 0)
    let coverage = makeSpatialCoverage(
        regions: [
            makeRegion(
                x: -2, z: 0,
                classification: .weak,
                observationCount: 1
            ),
            makeRegion(
                x: 2, z: 0,
                classification: .weak,
                observationCount: 3
            ),
        ]
    )
    let summary = SpatialCoverageAccessibilitySummary(
        coverage: coverage,
        declaredRegionKeys: [declared]
    )
    #expect(summary.declaredRegionCount == 1)
    #expect(
        !summary.priorityWeakRegions.contains { $0.key == declared }
    )
    #expect(summary.priorityWeakRegions.count == 1)
}

@Test
func spatialSummaryDescribesCameraPosition() {
    let coverage = makeSpatialCoverage(
        regions: [
            makeRegion(x: 0, z: 2, classification: .observed),
        ],
        cameraPosition: SpatialCoveragePoint2D(x: 0.4, z: 1.2),
        headingRadians: -.pi / 2
    )
    let summary = SpatialCoverageAccessibilitySummary(
        coverage: coverage
    )
    let camera = try? #require(summary.cameraRegion)
    // +x/+z quadrant at ~18° → front octant, <1.5 m → near.
    #expect(camera?.octant == .front)
    #expect(camera?.distanceBucket == .near)
    #expect(summary.cameraHeadingOctant == .left)
}

@Test
func spatialSummaryEnglishTextCarriesCountsAndLabels() {
    let coverage = makeSpatialCoverage(
        regions: [
            makeRegion(x: 0, z: 2, classification: .observed),
            makeRegion(
                x: -3, z: 2,
                classification: .weak,
                observationCount: 1
            ),
        ]
    )
    let summary = SpatialCoverageAccessibilitySummary(
        coverage: coverage
    )
    let text = ScanAccessibilityText.spatialCoverage(
        summary,
        language: .english
    )
    #expect(
        text.hasPrefix(
            "Spatial coverage: 1 observed, 1 weak, 0 unknown."
        )
    )
    #expect(text.contains("Weakest regions: "))
}

@Test
func spatialSummaryJapaneseTextIsDeterministic() {
    let text = ScanAccessibilityText.spatialCoverage(
        SpatialCoverageAccessibilitySummary(
            coverage: makeSpatialCoverage(regions: [
                makeRegion(x: 0, z: 2, classification: .weak),
            ])
        ),
        language: .japanese
    )
    #expect(
        text.hasPrefix("空間カバレッジ：観測済み0、弱い領域1、未観測0。")
    )
}

@Test
func spatialSummaryEmptyHasNoObservationClaim() {
    let text = ScanAccessibilityText.spatialCoverage(
        SpatialCoverageAccessibilitySummary(
            coverage: SpatialScanCoverageSummary.empty
        ),
        language: .english
    )
    #expect(text == "No spatial regions observed yet.")
}

@Test
func pitchBandNamesMatchReviewVocabulary() {
    #expect(
        ScanAccessibilityText.pitchBandName(
            .low,
            language: .english
        ) == "lower room"
    )
    #expect(
        ScanAccessibilityText.pitchBandName(
            .level,
            language: .english
        ) == "level view"
    )
    #expect(
        ScanAccessibilityText.pitchBandName(
            .high,
            language: .english
        ) == "upper room"
    )
    #expect(
        ScanAccessibilityText.pitchBandName(
            .low,
            language: .japanese
        ) == "下部"
    )
}
