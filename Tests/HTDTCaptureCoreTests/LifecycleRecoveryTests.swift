import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Coverage for the lifecycle/recovery issues #296, #297, #298, #320:
/// typed guidance-completion sources, post-End draft recovery, review
/// remediation affordances, and the practice-mode working set.
final class LifecycleRecoveryTests: XCTestCase {
    private func makeCaptureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func makeFoundation(
        context: CaptureSessionContext
    ) throws -> CaptureSessionFoundationPackage {
        try CaptureSessionFoundationPackageBuilder.build(
            context: context,
            capabilities: CaptureCapabilityMatrix(
                roomPlanSupported: true,
                worldTrackingSupported: true,
                sceneReconstructionSupported: true,
                sceneDepthSupported: true
            ),
            configurationProfile: CaptureConfigurationProfile(
                captureMode: .roomPlanMesh,
                worldAlignment: "gravity",
                sceneReconstruction: "mesh"
            ),
            startedAtUTC: "2026-09-21T10:00:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
    }

    private func makeTiming() throws -> CaptureTimingPackage {
        try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-21T10:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-21T10:00:07Z",
                method: "fixture"
            )
        )
    }

    private func makeLineage(
        context: CaptureSessionContext
    ) throws -> RoomPlanArtifactLineage {
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"room":"raw"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        return RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"room":"processed"}"#.utf8),
            to: raw
        )
    }

    private func makeEndCoverage() -> CaptureEndCoverageSummary {
        CaptureEndCoverageSummary(
            algorithm: "fixture",
            algorithmVersion: "1.0.0",
            endSessionTimestampSeconds: 8,
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 2, count: 36),
            coverageFraction: 1,
            pitchBandFractions: [:],
            weakCells: [],
            latestTrackingState: .normal,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 1,
            latestHasSceneDepth: true,
            spatialCellSizeMeters: 0.5,
            observedRegionCount: 1,
            weakRegionCount: 0,
            displayUnknownRegionCount: 0,
            usesDepthFallback: false,
            meshAvailabilityState: "available",
            weakRegionKeys: [],
            geometryEvidenceMode: "mesh",
            movementCapability: "unrestricted",
            guidanceCompletedAttempts: 0,
            guidanceMaximumAttempts: 4,
            actionableWeakRegionCount: 0,
            saturatedWeakRegionCount: 0,
            guidanceComplete: true,
            guidanceCompletionSource:
                ScanGuidanceCompletionSource.observed.rawValue
        )
    }

    /// Drives a working set through foundation + accepted End so its
    /// durable phase marker reads `end_accepted`.
    private func makeEndAcceptedRevision(
        captureRoot: URL,
        practice: Bool = false
    ) async throws -> (
        store: CaptureWorkingSetStore,
        directory: URL,
        context: CaptureSessionContext,
        identity: CaptureWorkingSetIdentity
    ) {
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let directory = captureRoot
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: directory,
            practice: practice
        )
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        await store.recordAdvisoryEndContext(makeEndCoverage())
        try await store.persistEndRoomPlanTransaction(
            timingPackage: makeTiming(),
            roomPlanLineage: makeLineage(context: context)
        )
        return (store, directory, context, identity)
    }
}

// MARK: - #296 guidance completion source

extension LifecycleRecoveryTests {
    private func coverage(
        gap: ScanCoverageGap?,
        tracking: TrackingQualityState = .normal,
        observedCellCount: Int = 36
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
            currentRelativeYawRadians: 0,
            currentPitchRadians: 0,
            latestTrackingState: tracking,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 1,
            latestHasSceneDepth: true,
            recommendedGap: gap
        )
    }

    private func spatial(
        _ region: SpatialCoverageRegion
    ) -> SpatialScanCoverageSummary {
        SpatialScanCoverageSummary(
            cellSizeMeters: 0.5,
            maxRegionCount: 256,
            referenceOriginWorld:
                SpatialCoveragePoint3D(x: 0, y: 0, z: 0),
            referenceYawRadians: 0,
            currentCameraPosition:
                SpatialCoveragePoint2D(x: 0, z: 0),
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
        classification: SpatialCoverageClassification
    ) -> SpatialCoverageRegion {
        SpatialCoverageRegion(
            key: SpatialCoverageCellKey(x: 2, z: 2),
            observationCount: 5,
            normalTrackingObservationCount: 5,
            limitedTrackingObservationCount: 0,
            lastObservedTimestampSeconds: 5,
            viewAngleBucketMask: 0b11,
            elevationBucketMask: 0,
            latestDistanceBucket: .medium,
            depthObservationCount: 5,
            meshSupportCount: 5,
            classification: classification
        )
    }

    private var fullCoverage: ScanCoverageSummary {
        coverage(gap: nil)
    }

    func testCompletionSourceObservedWhenNothingUnresolved() {
        let tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                completionDirectionCoverageFraction: 0.95
            )
        )
        let progress = tracker.progress(
            coverage: fullCoverage,
            spatialCoverage: spatial(region(classification: .observed))
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.completionSource, .observed)
        XCTAssertEqual(progress.unresolvedWeakRegionCount, 0)
    }

    func testCompletionSourceWeakRegionRetriesExhausted() {
        // One no-progress attempt on the weak region saturates its
        // bounded retry budget; the region stays weak but stops being
        // actionable, so completion is attributed to saturation.
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                maximumActionDurationSeconds: 0.5,
                maximumWeakRegionGuidanceAttempts: 1,
                maximumSpatialGuidanceAttempts: 5,
                completionDirectionCoverageFraction: 0.95
            )
        )
        let weak = spatial(region(classification: .weak))
        XCTAssertNotNil(
            tracker.record(
                timestampSeconds: 0,
                coverage: fullCoverage,
                spatialCoverage: weak,
                observation: .empty
            )
        )
        // The attempt times out with the region still weak and no
        // progress signal — consuming its entire retry budget.
        _ = tracker.record(
            timestampSeconds: 1.0,
            coverage: fullCoverage,
            spatialCoverage: weak,
            observation: .empty
        )
        let progress = tracker.progress(
            coverage: fullCoverage,
            spatialCoverage: weak
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(
            progress.completionSource,
            .weakRegionRetriesExhausted
        )
        XCTAssertEqual(progress.saturatedWeakRegionCount, 1)
        XCTAssertEqual(progress.unresolvedWeakRegionCount, 1)
    }

    func testCompletionSourceAttemptBudgetExhausted() {
        // A single completed spatial attempt exhausts the global
        // budget while the weak region still has actionable retries.
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.55,
                maximumActionDurationSeconds: 0.5,
                maximumWeakRegionGuidanceAttempts: 5,
                maximumSpatialGuidanceAttempts: 1,
                completionDirectionCoverageFraction: 0.95
            )
        )
        let weak = spatial(region(classification: .weak))
        XCTAssertNotNil(
            tracker.record(
                timestampSeconds: 0,
                coverage: fullCoverage,
                spatialCoverage: weak,
                observation: .empty
            )
        )
        _ = tracker.record(
            timestampSeconds: 1.0,
            coverage: fullCoverage,
            spatialCoverage: weak,
            observation: .empty
        )
        let progress = tracker.progress(
            coverage: fullCoverage,
            spatialCoverage: weak
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.completedSpatialGuidanceAttemptCount, 1)
        XCTAssertEqual(
            progress.completionSource,
            .attemptBudgetExhausted
        )
        XCTAssertEqual(progress.unresolvedWeakRegionCount, 1)
    }

    func testCompletionSourceMovementConstrained() {
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                completionDirectionCoverageFraction: 0.95
            )
        )
        tracker.setMovementCapability(.stationaryOnly)
        let progress = tracker.progress(
            coverage: fullCoverage,
            spatialCoverage: spatial(region(classification: .weak))
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(
            progress.completionSource,
            .movementConstrained
        )
        XCTAssertEqual(progress.unresolvedWeakRegionCount, 1)
    }

    func testCompletionSourceIncompleteWhileScanning() {
        let tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                completionDirectionCoverageFraction: 0.95
            )
        )
        let progress = tracker.progress(
            coverage: coverage(
                gap: ScanCoverageGap(
                    sectorIndex: 3,
                    pitchBand: .level
                ),
                observedCellCount: 12
            ),
            spatialCoverage: spatial(
                region(classification: .weak)
            )
        )
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.completionSource, .incomplete)
    }

    func testCompletionSourceDefaultsFollowTheBoolean() {
        let complete = ScanGuidanceProgress(
            movementCapability: .unrestricted,
            completedSpatialGuidanceAttemptCount: 0,
            maximumSpatialGuidanceAttempts: 4,
            actionableWeakRegionCount: 0,
            saturatedWeakRegionCount: 0,
            directionCoverageFraction: 1,
            isComplete: true
        )
        XCTAssertEqual(complete.completionSource, .observed)

        let incomplete = ScanGuidanceProgress(
            movementCapability: .unrestricted,
            completedSpatialGuidanceAttemptCount: 0,
            maximumSpatialGuidanceAttempts: 4,
            actionableWeakRegionCount: 1,
            saturatedWeakRegionCount: 0,
            directionCoverageFraction: 0.4,
            isComplete: false
        )
        XCTAssertEqual(incomplete.completionSource, .incomplete)
        XCTAssertEqual(incomplete.unresolvedWeakRegionCount, 1)
    }

    func testEndCoveragePersistsGuidanceCompletionSource()
        async throws
    {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        var summary = makeEndCoverage()
        await store.recordAdvisoryEndContext(summary)
        let firstReport: CaptureAdvisoryReport? =
            await store.evaluateAdvisoryDiagnostics()
        var report = try XCTUnwrap(firstReport)
        XCTAssertEqual(
            report.endCoverage?.guidanceCompletionSource,
            ScanGuidanceCompletionSource.observed.rawValue
        )

        // A non-observational source survives the same path — the wire
        // value is verbatim, so persisted evidence names the bound
        // that ended guidance rather than claiming observation.
        summary = CaptureEndCoverageSummary(
            algorithm: summary.algorithm,
            algorithmVersion: summary.algorithmVersion,
            endSessionTimestampSeconds:
                summary.endSessionTimestampSeconds,
            sectorCount: summary.sectorCount,
            minimumSamplesPerCell: summary.minimumSamplesPerCell,
            cellSampleCounts: summary.cellSampleCounts,
            coverageFraction: summary.coverageFraction,
            pitchBandFractions: summary.pitchBandFractions,
            weakCells: summary.weakCells,
            latestTrackingState: summary.latestTrackingState,
            latestTrackingReason: summary.latestTrackingReason,
            latestMeshAnchorCount: summary.latestMeshAnchorCount,
            latestHasSceneDepth: summary.latestHasSceneDepth,
            spatialCellSizeMeters: summary.spatialCellSizeMeters,
            observedRegionCount: summary.observedRegionCount,
            weakRegionCount: summary.weakRegionCount,
            displayUnknownRegionCount:
                summary.displayUnknownRegionCount,
            usesDepthFallback: summary.usesDepthFallback,
            meshAvailabilityState: summary.meshAvailabilityState,
            weakRegionKeys: summary.weakRegionKeys,
            geometryEvidenceMode: summary.geometryEvidenceMode,
            movementCapability: summary.movementCapability,
            guidanceCompletedAttempts:
                summary.guidanceCompletedAttempts,
            guidanceMaximumAttempts:
                summary.guidanceMaximumAttempts,
            actionableWeakRegionCount:
                summary.actionableWeakRegionCount,
            saturatedWeakRegionCount:
                summary.saturatedWeakRegionCount,
            guidanceComplete: summary.guidanceComplete,
            guidanceCompletionSource:
                ScanGuidanceCompletionSource
                .weakRegionRetriesExhausted.rawValue
        )
        await store.recordAdvisoryEndContext(summary)
        let secondReport: CaptureAdvisoryReport? =
            await store.evaluateAdvisoryDiagnostics()
        report = try XCTUnwrap(secondReport)
        XCTAssertEqual(
            report.endCoverage?.guidanceCompletionSource,
            ScanGuidanceCompletionSource
                .weakRegionRetriesExhausted.rawValue
        )
    }
}

// MARK: - #297 post-End draft recovery

extension LifecycleRecoveryTests {
    func testEndAcceptedRevisionReopensAsSealedDraft() async throws {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let (live, directory, context, _) =
            try await makeEndAcceptedRevision(
                captureRoot: captureRoot
            )

        var snapshot = await live.snapshot()
        XCTAssertEqual(snapshot.revisionPhase, .endAccepted)
        XCTAssertTrue(snapshot.spatialAuthorityLive)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    WorkingRevisionStateDocument.path
                ).path
            )
        )

        // An unclassifiable payload from a newer app stays on disk and
        // is reported as unsupported rather than dropped or fatal.
        let stray = directory.appendingPathComponent(
            "session/unknown-debug-v2.json",
            isDirectory: false
        )
        try Data(#"{"future":true}"#.utf8).write(to: stray)

        let inventory = PersistedCaptureInventory(
            captureRoot: captureRoot
        )
        let result = inventory.scan()
        XCTAssertEqual(result.orphanedWorkingArtifacts.count, 0)
        let draft = try XCTUnwrap(result.recoverableDrafts.first)
        XCTAssertEqual(draft.phase, .endAccepted)
        XCTAssertEqual(
            draft.captureSessionID,
            context.captureSessionID
        )
        XCTAssertEqual(
            draft.coordinateSpaceID,
            context.coordinateSpaceID
        )
        XCTAssertGreaterThan(draft.retainedBytes, 0)

        let (restored, report) =
            try await CaptureWorkingSetStore
                .restoreWorkingRevision(draft)
        snapshot = await restored.snapshot()
        XCTAssertEqual(snapshot.revisionPhase, .endAccepted)
        XCTAssertFalse(snapshot.spatialAuthorityLive)
        XCTAssertFalse(snapshot.practiceCapture)
        XCTAssertEqual(
            snapshot.captureSessionIDs,
            [context.captureSessionID]
        )
        XCTAssertEqual(
            snapshot.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == WorkingRevisionStateDocument.path
            }
        )
        XCTAssertEqual(
            report.unsupportedPaths,
            ["session/unknown-debug-v2.json"]
        )
        // The unknown payload is preserved, declared generically, and
        // still passes the store's byte-vs-declaration proof.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: stray.path)
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == "session/unknown-debug-v2.json"
            }
        )

        // The checkpoint restored the End coverage snapshot instead of
        // reporting scan-time trackers as absent.
        let advisory = await restored
            .evaluateAdvisoryDiagnostics()
        XCTAssertEqual(
            advisory?.endCoverage?.guidanceCompletionSource,
            ScanGuidanceCompletionSource.observed.rawValue
        )
        XCTAssertFalse(
            report.missingCheckpointFields.contains("end_coverage")
        )

        // Live-spatial mutations are permanently unavailable: the End
        // transaction cannot be rolled back into a resumed scan.
        await XCTAssertThrowsErrorAsync(
            try await restored
                .rollbackAcceptedEndTransaction(
                    removeOwnedMesh: false
                )
        ) { error in
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .spatialAuthorityNotLive
            )
        }

        // Semantic authoring still works and advances the durable
        // phase to semantic_authoring.
        try await restored.recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .declaredRegion,
                sessionTimestampSeconds: 2,
                detail: "cell_x=2 cell_z=2 reason=inaccessible"
            )
        )
        snapshot = await restored.snapshot()
        XCTAssertEqual(
            snapshot.revisionPhase,
            .semanticAuthoring
        )
        let persisted = try XCTUnwrap(
            CaptureWorkingSetStore.peekRevisionPhase(
                workingRevisionURL: directory
            )
        )
        XCTAssertEqual(persisted.phase, .semanticAuthoring)

        // Quality re-evaluates cleanly against the restored bytes.
        let quality = await restored.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "0.0.0-test",
                requireCompletedRoomPlan: true,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .pass)

        // The recovered draft remains discardable.
        try await restored.discardIncompleteRevision()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path)
        )
    }

    func testLiveScanIncompleteRevisionIsNotRecoverable()
        async throws
    {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let directory = captureRoot
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: directory
        )
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.revisionPhase, .liveScanIncomplete)

        let result = PersistedCaptureInventory(
            captureRoot: captureRoot
        ).scan()
        XCTAssertTrue(result.recoverableDrafts.isEmpty)
        XCTAssertEqual(result.orphanedWorkingArtifacts.count, 1)
        XCTAssertEqual(
            result.orphanedWorkingArtifacts.first?.kind,
            .abandonedRevision
        )
    }

    func testNewerSchemaRevisionIsNotRecoverable() async throws {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let (_, directory, _, identity) =
            try await makeEndAcceptedRevision(
                captureRoot: captureRoot
            )
        // Rewrite the marker under a newer schema version — recovery
        // must surface it as an abandoned directory, never decode it.
        let tampered = """
            {
              "schema": "htdt.working-revision-state",
              "schema_version": "9.9.9",
              "capture_series_id":
                "\(identity.captureSeriesID.description)",
              "capture_revision_id":
                "\(identity.captureRevisionID.description)",
              "created_at_utc": "2026-09-21T10:00:00Z",
              "phase": "end_accepted",
              "updated_at_utc": "2026-09-21T10:00:00Z",
              "practice": false
            }
            """
        try Data(tampered.utf8).write(
            to: directory.appendingPathComponent(
                WorkingRevisionStateDocument.path
            ),
            options: .atomic
        )
        XCTAssertNil(
            CaptureWorkingSetStore.peekRevisionPhase(
                workingRevisionURL: directory
            )
        )
        let result = PersistedCaptureInventory(
            captureRoot: captureRoot
        ).scan()
        XCTAssertTrue(result.recoverableDrafts.isEmpty)
        XCTAssertEqual(result.orphanedWorkingArtifacts.count, 1)
    }

    func testRevisionWithoutEndIsNotRestorable() async throws {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let identity = CaptureWorkingSetIdentity()
        let directory = captureRoot
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let draft = RecoverableWorkingRevision(
            url: directory,
            revisionID: identity.captureRevisionID,
            phase: .endAccepted,
            captureSessionID: nil,
            coordinateSpaceID: nil,
            retainedBytes: 0
        )
        await XCTAssertThrowsErrorAsync(
            try await CaptureWorkingSetStore
                .restoreWorkingRevision(draft)
        ) { error in
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .workingRevisionNotRecoverable
            )
        }
    }

    func testStateMachineReopenAndSuspendReview() throws {
        var machine = CaptureStateMachine()
        try machine.apply(.reopenDraft)
        XCTAssertEqual(machine.state, .reviewing)
        try machine.apply(.suspendReview)
        XCTAssertEqual(machine.state, .idle)

        // Live-state shortcuts stay closed: reopenDraft is only legal
        // from Idle, and only ever lands in Review.
        try machine.apply(.beginCapabilityCheck)
        XCTAssertThrowsError(try machine.apply(.reopenDraft))
    }
}

// MARK: - #298 review remediation catalog

extension LifecycleRecoveryTests {
    private func diagnostic(
        _ code: String,
        severity: QualityDiagnosticSeverity = .error
    ) -> QualityDiagnostic {
        QualityDiagnostic(
            code: code,
            severity: severity,
            message: "fixture"
        )
    }

    func testEveryEvaluatorDiagnosticCodeHasRemediation() {
        let codes = [
            "roomplan_not_completed",
            "mesh_depth_fallback",
            "depth_fallback_insufficient",
            "insufficient_mesh_anchors",
            "insufficient_evidence_frames",
            "depth_evidence_missing",
            "annotation_missing",
            "measurement_missing",
            "tracking_unavailable_observed",
            "tracking_limited_observed",
            "tracking_unavailable_unrecovered",
            "tracking_unavailable_extended",
            "tracking_unavailable_recovering",
            "tracking_unavailable_recovered",
            "tracking_coordinate_discontinuity",
            "resource_error",
            "integrity_not_checked",
            "integrity_failed",
        ]
        // Findings whose evidence is expected provenance get a plan
        // with no affordance — nothing the operator does clears them.
        let nonActionable: Set<String> = ["mesh_depth_fallback"]
        for code in codes {
            let remediation = QualityRemediationCatalog
                .remediation(for: diagnostic(code))
            if !nonActionable.contains(code) {
                XCTAssertFalse(
                    remediation.actions.isEmpty,
                    "no remediation for \(code)"
                )
            }
            XCTAssertTrue(remediation.blocking)
            XCTAssertEqual(remediation.diagnosticCode, code)
        }
    }

    func testUnknownDiagnosticDegradesToDiscardOnly() {
        let remediation = QualityRemediationCatalog
            .remediation(for: diagnostic("future_code_v9"))
        XCTAssertEqual(remediation.actions, [.discardDraft])
        XCTAssertFalse(remediation.repairableInPlace)
    }

    func testAuthorityDamagedDiagnosticsOfferReplacement() {
        for code in [
            "tracking_unavailable_extended",
            "tracking_coordinate_discontinuity",
        ] {
            let remediation = QualityRemediationCatalog
                .remediation(for: diagnostic(code))
            XCTAssertEqual(
                remediation.actions,
                [.startReplacementRevision, .discardDraft]
            )
            XCTAssertFalse(remediation.repairableInPlace)
        }
    }

    func testUnrecoveredTrackingSpanOffersContinueScanning() {
        // The evaluator classifies spans from event history — a later
        // normal sample converts an unrecovered span to recovered, so
        // continuing the scan is a legitimate in-place repair, not a
        // dead end that can only discard.
        let remediation = QualityRemediationCatalog
            .remediation(
                for: diagnostic("tracking_unavailable_unrecovered")
            )
        XCTAssertEqual(
            remediation.actions,
            [.continueScanning, .startReplacementRevision]
        )
        XCTAssertTrue(remediation.repairableInPlace)
    }

    func testDraftActionsStripLiveOnlyAffordances() {
        let remediation = QualityRemediationCatalog
            .remediation(for: diagnostic("roomplan_not_completed"))
        XCTAssertEqual(
            remediation.actions,
            [.continueScanning, .startReplacementRevision]
        )
        XCTAssertEqual(
            remediation.draftActions,
            [.startReplacementRevision]
        )

        let annotation = QualityRemediationCatalog
            .remediation(for: diagnostic("annotation_missing"))
        XCTAssertEqual(annotation.actions, [.addAnnotation])
        XCTAssertEqual(annotation.draftActions, [.addAnnotation])
    }

    func testBlockingFlagFollowsSeverity() {
        let blocking = QualityRemediationCatalog.remediation(
            for: diagnostic("integrity_not_checked")
        )
        XCTAssertTrue(blocking.blocking)
        let advisory = QualityRemediationCatalog.remediation(
            for: diagnostic(
                "integrity_not_checked",
                severity: .warning
            )
        )
        XCTAssertFalse(advisory.blocking)
        XCTAssertEqual(
            advisory.actions,
            [.verifyIntegrityAgain]
        )
    }

    func testTaskCompletenessRemediationActions() {
        let noProfile = CaptureTaskCompletenessReport(
            profileIdentifier: nil,
            profileTitle: nil,
            evaluationState: .noProfileSelected,
            outcomes: [],
            requiredUnsatisfiedCount: 0,
            overallSatisfied: false
        )
        XCTAssertEqual(
            noProfile.remediationActions,
            [.reviewTaskRequirements]
        )

        let annotationRequirement = CaptureTaskRequirement(
            identifier: "req-door",
            match: CaptureTaskMatch(
                kind: .annotationEntityType,
                value: "door"
            )
        )
        let measurementRequirement = CaptureTaskRequirement(
            identifier: "req-width",
            match: CaptureTaskMatch(
                kind: .measurementQuantityType,
                value: "width"
            )
        )
        let unmet = CaptureTaskCompletenessReport(
            profileIdentifier: "p",
            profileTitle: "Profile",
            evaluationState: .evaluated,
            outcomes: [
                CaptureTaskRequirementOutcome(
                    requirement: annotationRequirement,
                    status: .missing,
                    observedCount: 0,
                    matchedRefs: []
                ),
                CaptureTaskRequirementOutcome(
                    requirement: measurementRequirement,
                    status: .partial,
                    observedCount: 1,
                    matchedRefs: ["measurement:1"]
                ),
            ],
            requiredUnsatisfiedCount: 2,
            overallSatisfied: false
        )
        XCTAssertEqual(
            unmet.remediationActions,
            [
                .addAnnotation,
                .addMeasurement,
                .reviewTaskRequirements,
            ]
        )

        let met = CaptureTaskCompletenessReport(
            profileIdentifier: "p",
            profileTitle: "Profile",
            evaluationState: .evaluated,
            outcomes: [
                CaptureTaskRequirementOutcome(
                    requirement: annotationRequirement,
                    status: .satisfied,
                    observedCount: 1,
                    matchedRefs: ["annotation:1"]
                ),
            ],
            requiredUnsatisfiedCount: 0,
            overallSatisfied: true
        )
        XCTAssertTrue(met.remediationActions.isEmpty)
    }
}

// MARK: - #320 practice mode

extension LifecycleRecoveryTests {
    func testPracticeWorkingSetIsFlaggedAndNeverFinalizable()
        async throws
    {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let (store, _, _, _) = try await makeEndAcceptedRevision(
            captureRoot: captureRoot,
            practice: true
        )
        let snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.practiceCapture)
        XCTAssertEqual(snapshot.revisionPhase, .endAccepted)

        await XCTAssertThrowsErrorAsync(
            try await store.sealForFinalization(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        ) { error in
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .practiceWorkingSetNotFinalizable
            )
        }
    }

    func testPracticeRevisionIsNeverARecoverableDraft() async throws {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let (_, directory, context, identity) =
            try await makeEndAcceptedRevision(
                captureRoot: captureRoot,
                practice: true
            )
        // The phase marker committed end_accepted, but practice data
        // is permanently separated from real capture recovery.
        let persisted = try XCTUnwrap(
            CaptureWorkingSetStore.peekRevisionPhase(
                workingRevisionURL: directory
            )
        )
        XCTAssertTrue(persisted.practice)

        let result = PersistedCaptureInventory(
            captureRoot: captureRoot
        ).scan()
        XCTAssertTrue(result.recoverableDrafts.isEmpty)
        XCTAssertEqual(result.orphanedWorkingArtifacts.count, 1)

        // Even a hand-constructed draft record is refused.
        let draft = RecoverableWorkingRevision(
            url: directory,
            revisionID: identity.captureRevisionID,
            phase: .endAccepted,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            retainedBytes: 0
        )
        await XCTAssertThrowsErrorAsync(
            try await CaptureWorkingSetStore
                .restoreWorkingRevision(draft)
        ) { error in
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .workingRevisionNotRecoverable
            )
        }
    }

    func testNonPracticeRevisionIsNotPracticeCapture() async throws {
        let root = try makeCaptureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let captureRoot = root.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
        let (store, _, _, _) = try await makeEndAcceptedRevision(
            captureRoot: captureRoot
        )
        let snapshot = await store.snapshot()
        XCTAssertFalse(snapshot.practiceCapture)
    }
}

/// `XCTAssertThrowsError` for an `async throws` expression.
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(
            "expected error to be thrown. \(message())",
            file: file,
            line: line
        )
    } catch {
        errorHandler(error)
    }
}
