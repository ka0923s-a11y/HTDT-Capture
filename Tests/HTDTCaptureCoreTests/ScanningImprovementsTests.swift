import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Unit tests for the scanning-improvement batch: #313 movement
/// safety, #325 revisit flags, #329 3D-aware coverage, #352
/// pre-capture mission binding.
final class ScanningImprovementsTests: XCTestCase {

    // MARK: - #313 movement safety

    func testOnlyUnrestrictedCapabilityGuidesTranslation() {
        XCTAssertTrue(ScanMovementCapability.unrestricted
            .canGuideTranslation)
        XCTAssertFalse(ScanMovementCapability.stationaryOnly
            .canGuideTranslation)
        XCTAssertFalse(ScanMovementCapability.safetyConstrained
            .canGuideTranslation)
    }

    func testOnlyTranslationActionsRequirePhysicalTranslation() {
        for action in [
            ScanMotionGuidanceAction.translate,
            .approach,
            .retreat,
            .orbit,
            .reobserveAnotherAngle,
        ] {
            XCTAssertTrue(
                action.requiresPhysicalTranslation,
                "\(action.rawValue) must carry safety wording"
            )
        }
        for action in [
            ScanMotionGuidanceAction.trackingRecovery,
            .rotate,
            .tilt,
            .holdObserve,
        ] {
            XCTAssertFalse(
                action.requiresPhysicalTranslation,
                "\(action.rawValue) is in-place; no movement wording"
            )
        }
    }

    func testMovementPromptsAreQualifiedNotRequired() {
        // Every movement prompt must carry an explicit safety
        // precondition ("If the path is clear" / "If safe") — never
        // present walking as a required or sensor-verified-safe step.
        let movingActions: [ScanMotionGuidance] = [
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .left
            ),
            ScanMotionGuidance(
                action: .translate,
                translationDirection: .backward
            ),
            ScanMotionGuidance(action: .approach),
            ScanMotionGuidance(action: .retreat),
            ScanMotionGuidance(action: .orbit),
            ScanMotionGuidance(action: .reobserveAnotherAngle),
        ]
        for guidance in movingActions {
            let prompt = ScanMotionGuidanceCopy.prompt(
                for: guidance
            )
            XCTAssertTrue(
                prompt.hasPrefix("If"),
                "prompt must be safety-qualified: \(prompt)"
            )
            XCTAssertNotNil(
                ScanMotionGuidanceCopy.safetyNote(
                    for: guidance
                )
            )
        }
    }

    func testInPlacePromptsCarryNoMovementQualifier() {
        for guidance in [
            ScanMotionGuidance(action: .trackingRecovery),
            ScanMotionGuidance(
                action: .rotate,
                horizontalDirection: .left
            ),
            ScanMotionGuidance(
                action: .tilt,
                verticalDirection: .up
            ),
            ScanMotionGuidance(action: .holdObserve),
        ] {
            XCTAssertNil(
                ScanMotionGuidanceCopy.safetyNote(
                    for: guidance
                ),
                "\(guidance.action) needs no movement note"
            )
        }
    }

    func testSafetyDisclaimerNeverClaimsObstacleDetection() {
        let disclaimer = ScanMotionGuidanceCopy.safetyDisclaimer()
        XCTAssertFalse(disclaimer.isEmpty)
        XCTAssertTrue(disclaimer.contains("advisory only"))
    }

    // MARK: - #325 revisit flags

    private func makeFlag(
        coordinateSpaceID: CoordinateSpaceID = CoordinateSpaceID(),
        captureSessionID: CaptureSessionID = CaptureSessionID(),
        timestamp: Double = 10
    ) -> ScanRevisitFlag {
        ScanRevisitFlag(
            coordinateSpaceID: coordinateSpaceID,
            captureSessionID: captureSessionID,
            targetPointWorld: ScanRevisitFlagVector(
                x: 1.2,
                y: 0.4,
                z: -2.1
            ),
            targetFromRaycast: true,
            cameraPositionWorld: ScanRevisitFlagVector(
                x: 0.5,
                y: 1.5,
                z: -0.5
            ),
            cameraForwardWorld: ScanRevisitFlagVector(
                x: 0,
                y: -0.1,
                z: -1
            ),
            coverageCell: "2,-4",
            category: nil,
            note: nil,
            createdSessionTimestampSeconds: timestamp
        )
    }

    func testFlagStoreAddListAndCap() {
        var store = CaptureRevisitFlagStore(maxFlagCount: 2)
        XCTAssertTrue(store.add(makeFlag(timestamp: 1)))
        XCTAssertTrue(store.add(makeFlag(timestamp: 2)))
        XCTAssertTrue(store.isFull)
        XCTAssertFalse(store.add(makeFlag(timestamp: 3)))
        XCTAssertEqual(store.flags.count, 2)
        XCTAssertEqual(store.unresolvedFlags.count, 2)
    }

    func testFlagDetailsAndResolutionLifecycle() {
        var store = CaptureRevisitFlagStore()
        let flag = makeFlag()
        XCTAssertTrue(store.add(flag))
        let flagID = flag.flagID

        XCTAssertTrue(
            store.updateDetails(
                flagID: flagID,
                category: .reflectiveTransparent,
                note: "glass wall"
            )
        )
        XCTAssertEqual(
            store.flags.first?.category,
            .reflectiveTransparent
        )
        XCTAssertEqual(store.flags.first?.note, "glass wall")
        XCTAssertEqual(
            store.flags.first?.suggestedRemediation,
            .reobserve
        )

        // A flag must never silently become an annotation — resolving
        // links real authority instead.
        XCTAssertTrue(
            store.resolve(
                flagID: flagID,
                outcome: .linkedAuthority,
                authorityRef: "annotation/abc",
                sessionTimestampSeconds: 120
            )
        )
        XCTAssertEqual(store.flags.first?.status, .resolved)
        XCTAssertEqual(
            store.flags.first?.resolution?.authorityRef,
            "annotation/abc"
        )
        XCTAssertEqual(store.unresolvedFlags.count, 0)

        XCTAssertTrue(store.reopen(flagID: flagID))
        XCTAssertEqual(store.flags.first?.status, .unresolved)
        XCTAssertNil(store.flags.first?.resolution)
    }

    func testResolutionOutcomeStatusMapping() {
        var store = CaptureRevisitFlagStore()
        let flagA = makeFlag()
        let flagB = makeFlag()
        let flagC = makeFlag()
        store.add(flagA)
        store.add(flagB)
        store.add(flagC)

        XCTAssertTrue(store.resolve(
            flagID: flagA.flagID,
            outcome: .acknowledged
        ))
        XCTAssertTrue(store.resolve(
            flagID: flagB.flagID,
            outcome: .markedUnavailable
        ))
        XCTAssertTrue(store.resolve(
            flagID: flagC.flagID,
            outcome: .linkedAuthority
        ))

        XCTAssertEqual(store.flags[0].status, .skipped)
        XCTAssertEqual(store.flags[1].status, .unavailable)
        XCTAssertEqual(store.flags[2].status, .resolved)
    }

    func testNoteIsTruncatedToBound() {
        var store = CaptureRevisitFlagStore()
        let flag = makeFlag()
        store.add(flag)
        let long = String(repeating: "x", count: 500)
        XCTAssertTrue(store.updateDetails(
            flagID: flag.flagID,
            category: nil,
            note: long
        ))
        XCTAssertEqual(
            store.flags.first?.note?.count,
            CaptureRevisitFlagDocument.maxNoteLength
        )
    }

    func testMarkFlagsUnavailableOnSpaceChange() {
        var store = CaptureRevisitFlagStore()
        let oldSpace = CoordinateSpaceID()
        let flagOld = makeFlag(coordinateSpaceID: oldSpace)
        let flagResolved = makeFlag(coordinateSpaceID: oldSpace)
        store.add(flagOld)
        store.add(flagResolved)
        store.resolve(flagID: flagResolved.flagID, outcome: .acknowledged)

        store.markFlagsUnavailable(notIn: CoordinateSpaceID())

        // The unresolved flag in the stale space is marked unavailable;
        // already-resolved flags are untouched.
        XCTAssertEqual(store.flags[0].status, .unavailable)
        XCTAssertEqual(store.flags[1].status, .skipped)
    }

    func testFlagDocumentRoundTrips() throws {
        var store = CaptureRevisitFlagStore()
        let flag = makeFlag()
        store.add(flag)
        store.updateDetails(
            flagID: flag.flagID,
            category: .measurement,
            note: "re-check opening width"
        )
        let revision = CaptureRevisionID()
        let data = try store
            .document(captureRevisionID: revision)
            .encoded()
        let decoded = try JSONDecoder().decode(
            CaptureRevisitFlagDocument.self,
            from: data
        )
        XCTAssertEqual(decoded.schema, "htdt.capture.revisit_flags")
        XCTAssertEqual(decoded.schemaVersion, "1.0.0")
        XCTAssertEqual(decoded.captureRevisionID, revision)
        XCTAssertEqual(decoded.flags.count, 1)
        XCTAssertEqual(
            decoded.flags.first?.targetPointWorld,
            flag.targetPointWorld
        )
        XCTAssertEqual(
            decoded.flags.first?.coverageCell,
            "2,-4"
        )
    }

    // MARK: - #329 3D-aware coverage

    private func sample3D(
        timestamp: Double,
        camera: (x: Double, y: Double, z: Double),
        points: [(x: Double, y: Double, z: Double)]
    ) -> SpatialCoverageSample {
        SpatialCoverageSample(
            sessionTimestampSeconds: timestamp,
            cameraPositionWorld: SpatialCoveragePoint3D(
                x: camera.x,
                y: camera.y,
                z: camera.z
            ),
            cameraYawRadians: 0,
            trackingState: .normal,
            hasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            surfaceEvidenceSource: .mesh,
            surfacePointsWorld: points.map {
                SpatialCoveragePoint3D(x: $0.x, y: $0.y, z: $0.z)
            }
        )
    }

    func testVerticalGapsCannotHideInA2DCell() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1
        )
        // Same (x,z) cell, two heights: floor and ceiling points land
        // in different y-bands of the same 2D cell.
        let summary = tracker.record(
            sample3D(
                timestamp: 1,
                camera: (0, 1.5, 0),
                points: [
                    (1.0, 0.1, -1.0),
                    (1.0, 3.1, -1.0),
                ]
            )
        )
        XCTAssertEqual(summary.knownRegionCount, 1)
        XCTAssertEqual(summary.vertical.voxelCount, 2)
        XCTAssertEqual(
            (summary.vertical.observedYBandMax ?? 0)
                - (summary.vertical.observedYBandMin ?? 0),
            5
        )
    }

    func testOrbitAloneCannotClaimElevatedVoxelObserved() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 3,
            minimumViewAngleBuckets: 2
        )
        // A ceiling point seen from three azimuths, all from the same
        // camera height → single elevation bucket (camera below the
        // point). Orbit alone must not promote it (#329).
        let ceiling: (x: Double, y: Double, z: Double) =
            (1.0, 3.1, -1.0)
        for (index, camera) in [
            (0.0, 1.5, 0.0),
            (2.0, 1.5, 0.5),
            (-0.5, 1.5, 0.2),
        ].enumerated() {
            _ = tracker.record(
                sample3D(
                    timestamp: Double(index + 1),
                    camera: camera,
                    points: [ceiling]
                )
            )
        }

        var voxel = tracker.summary().vertical.voxels.first
        XCTAssertEqual(voxel?.classification, .weak)
        XCTAssertEqual(voxel?.elevationDiversityCount, 1)
        XCTAssertTrue(voxel?.elevationSensitive ?? false)

        // Add a second elevation bucket: the operator raises/tilts
        // the device so the same point is seen near level.
        let summary = tracker.record(
            sample3D(
                timestamp: 4,
                camera: (0.2, 3.4, 0.1),
                points: [ceiling]
            )
        )
        voxel = summary.vertical.voxels.first
        XCTAssertEqual(voxel?.elevationDiversityCount, 2)
        XCTAssertEqual(voxel?.classification, .observed)
    }

    func testLevelOnlyVoxelNeedsNoElevationDiversity() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 2,
            minimumViewAngleBuckets: 2
        )
        // A wall-level point seen only at level elevation from two
        // azimuths promotes to observed — the elevated-voxel rule
        // applies only when the viewpoint mask is height-sensitive.
        let wall: (x: Double, y: Double, z: Double) =
            (1.0, 1.4, -1.0)
        _ = tracker.record(
            sample3D(
                timestamp: 1,
                camera: (0, 1.5, 0),
                points: [wall]
            )
        )
        let summary = tracker.record(
            sample3D(
                timestamp: 2,
                camera: (1.5, 1.5, 0.2),
                points: [wall]
            )
        )
        let voxel = summary.vertical.voxels.first
        XCTAssertFalse(voxel?.elevationSensitive ?? true)
        XCTAssertEqual(voxel?.classification, .observed)
    }

    func testTwoDRegionPromotionUnchangedByVoxelLayer() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 2,
            minimumViewAngleBuckets: 2
        )
        let surface: (x: Double, y: Double, z: Double) =
            (1.0, 0.2, -1.0)
        _ = tracker.record(
            sample3D(
                timestamp: 1,
                camera: (0, 1.5, 0),
                points: [surface]
            )
        )
        let summary = tracker.record(
            sample3D(
                timestamp: 2,
                camera: (2.0, 1.5, 0),
                points: [surface]
            )
        )
        // 2D classification is azimuth-only (orthogonal to #336
        // budget work and to the additive voxel layer).
        XCTAssertEqual(
            summary.regions.first?.classification,
            .observed
        )
        XCTAssertEqual(
            summary.vertical.voxels.first?.classification,
            .weak
        )
    }

    func testVoxelStorageIsBoundedAndEvictsOldest() {
        var tracker = SpatialScanCoverageTracker(
            cellSizeMeters: 0.5,
            maxRegionCount: 256,
            minimumNormalObservations: 1,
            minimumViewAngleBuckets: 1,
            maxVoxelCount: 2
        )
        _ = tracker.record(
            sample3D(
                timestamp: 1,
                camera: (0, 1.5, 0),
                points: [(1.0, 0.1, -1.0)]
            )
        )
        _ = tracker.record(
            sample3D(
                timestamp: 2,
                camera: (0, 1.5, 0),
                points: [(1.0, 1.2, -1.0)]
            )
        )
        let summary = tracker.record(
            sample3D(
                timestamp: 3,
                camera: (0, 1.5, 0),
                points: [(1.0, 2.5, -1.0)]
            )
        )
        XCTAssertEqual(summary.vertical.voxelCount, 2)
        XCTAssertLessThanOrEqual(
            summary.vertical.voxelCount,
            summary.vertical.maxVoxelCount
        )
        // Oldest (y-band of the 0.1 m point) was evicted.
        XCTAssertEqual(
            summary.vertical.voxels.map(\.key.yBand),
            [-1, 1]
        )
    }

    func testVerticalDisplayBandsExposeWeakStrata() {
        var tracker = SpatialScanCoverageTracker(
            minimumNormalObservations: 2,
            minimumViewAngleBuckets: 2
        )
        let summary = tracker.record(
            sample3D(
                timestamp: 1,
                camera: (0, 1.5, 0),
                points: [
                    (1.0, 0.2, -1.0),
                    (1.0, 3.0, -1.0),
                ]
            )
        )
        XCTAssertEqual(
            summary.vertical.displayBands.map(\.band),
            SpatialVerticalDisplayBand.allCases
        )
        // Both ends were sampled once → weak at both extremes, the
        // strata between them remain representable.
        XCTAssertEqual(
            summary.vertical.displayBands.first?.weakCount,
            1
        )
        XCTAssertEqual(
            summary.vertical.displayBands.last?.weakCount,
            1
        )
    }

    func testEndCoverageSummaryIsBackwardReadableWithout3D() throws {
        // #329: a payload written before the vertical layer existed
        // decodes with nil 3D fields (azimuth-only semantics).
        let legacy = """
            {
              "algorithm": "advisory-scan-coverage",
              "algorithm_version": "1.0.0",
              "sector_count": 12,
              "minimum_samples_per_cell": 2,
              "cell_sample_counts": [1, 2],
              "coverage_fraction": 0.5,
              "pitch_band_fractions": {},
              "weak_cells": [],
              "latest_mesh_anchor_count": 3,
              "latest_has_scene_depth": true,
              "spatial_cell_size_meters": 0.5,
              "observed_region_count": 4,
              "weak_region_count": 1,
              "display_unknown_region_count": 9,
              "uses_depth_fallback": false,
              "mesh_availability_state": "anchors_observed",
              "weak_region_keys": ["2,-4"],
              "geometry_evidence_mode": "mesh_anchors",
              "movement_capability": "unrestricted",
              "guidance_completed_attempts": 1,
              "guidance_maximum_attempts": 5,
              "actionable_weak_region_count": 1,
              "saturated_weak_region_count": 0,
              "guidance_complete": false
            }
            """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(
            CaptureEndCoverageSummary.self,
            from: legacy
        )
        XCTAssertNil(decoded.viewpointDiversitySemantics)
        XCTAssertNil(decoded.verticalVoxelCount)
        XCTAssertNil(decoded.verticalBandSummaries)

        // New fields round-trip through the extended schema.
        let summary = CaptureEndCoverageSummary(
            algorithm: "advisory-scan-coverage",
            algorithmVersion: "1.1.0",
            endSessionTimestampSeconds: 12.5,
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: [2],
            coverageFraction: 0.9,
            pitchBandFractions: [:],
            weakCells: [],
            latestTrackingState: .normal,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 5,
            latestHasSceneDepth: true,
            spatialCellSizeMeters: 0.5,
            observedRegionCount: 6,
            weakRegionCount: 1,
            displayUnknownRegionCount: 2,
            usesDepthFallback: false,
            meshAvailabilityState: "anchors_observed",
            weakRegionKeys: ["3,-1"],
            geometryEvidenceMode: "mesh_anchors",
            movementCapability: "safety_constrained",
            guidanceCompletedAttempts: 2,
            guidanceMaximumAttempts: 5,
            actionableWeakRegionCount: 1,
            saturatedWeakRegionCount: 0,
            guidanceComplete: false,
            viewpointDiversitySemantics: "azimuth_elevation_3d",
            verticalCellSizeMeters: 0.6,
            verticalVoxelCount: 10,
            verticalObservedVoxelCount: 7,
            verticalWeakVoxelCount: 2,
            verticalWeakVoxelKeys: ["3,-1,4"],
            verticalBandSummaries: [
                "highest": CaptureVerticalBandSummary(
                    voxelCount: 2,
                    observedCount: 0,
                    weakCount: 2
                ),
                "middle": CaptureVerticalBandSummary(
                    voxelCount: 5,
                    observedCount: 5,
                    weakCount: 0
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(summary)
        let decoded2 = try JSONDecoder().decode(
            CaptureEndCoverageSummary.self,
            from: encoded
        )
        XCTAssertEqual(
            decoded2.viewpointDiversitySemantics,
            "azimuth_elevation_3d"
        )
        XCTAssertEqual(decoded2.verticalWeakVoxelKeys, ["3,-1,4"])
        // Keys come back in floor→ceiling display order.
        XCTAssertEqual(
            decoded2.sortedVerticalBandKeys,
            ["middle", "highest"]
        )
    }

    // MARK: - #352 pre-capture mission binding

    func testImportedPlanBindsVerbatimAndStartsPending() throws {
        let planJSON = """
            {
              "schema": "htdt.capture-task-plan",
              "schema_version": "1.0.0",
              "plan_id": "plan-352",
              "plan_version": "2026.09.1",
              "project_ref": "proj-1/doc-1",
              "room_name": "Theater A",
              "issued_at": "2026-09-20T08:00:00Z",
              "entity_checklist": [
                {
                  "item_id": "screen",
                  "title": "Main screen",
                  "entity_type": "display",
                  "requirement": "required"
                }
              ],
              "measurement_requests": [],
              "surface_review_tasks": [],
              "evidence_targets": [],
              "expected_channel_roles": []
            }
            """.data(using: .utf8)!
        let planImport = try CaptureTaskPlanImport(data: planJSON)
        // The plan binds by verbatim bytes — the digest identity is
        // recorded, never the re-encoded model.
        XCTAssertEqual(planImport.data, planJSON)
        XCTAssertEqual(planImport.plan.planID, "plan-352")
        XCTAssertEqual(
            CaptureTaskPlanImport.path,
            "session/capture-task-plan.json"
        )

        var status = CaptureTaskPlanStatus(planImport: planImport)
        // A freshly bound plan starts all-pending — the mission is
        // workflow intent, not observed truth.
        XCTAssertEqual(
            Set(
                status.itemOutcomes(
                    annotations: [],
                    measurements: []
                ).map(\.outcome)
            ),
            [.pending]
        )

        // Entity items cannot be marked completed ahead of evidence —
        // only explicit non-completion outcomes are assertable.
        XCTAssertThrowsError(
            try status.mark(itemID: "screen", as: .completed)
        )
        try status.mark(itemID: "screen", as: .skipped)

        let package = try status.statusPackage(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            annotations: [],
            measurements: []
        )
        let decoded = try JSONDecoder().decode(
            CaptureTaskPlanStatusDocument.self,
            from: package
        )
        XCTAssertEqual(decoded.planID, "plan-352")
        XCTAssertEqual(decoded.items.first?.outcome, .skipped)
    }
}
