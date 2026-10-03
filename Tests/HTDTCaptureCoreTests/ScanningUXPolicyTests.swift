import XCTest
@testable import HTDTCaptureCore

/// Issue-cluster tests for the scanning-UX policies: pre-capture
/// setup state (#212/#272/#283), capture-mode startup contract (#248),
/// bounded automatic keyframes (#216), frame usability (#274),
/// targeted object passes (#250), non-visual cues (#252),
/// operator-declared regions (#257) and the loop-closure check (#273).
final class ScanningUXPolicyTests: XCTestCase {

    // MARK: - #212 pre-capture setup state

    func testSetupStateRequiresExplicitBeginBeforeCapabilityCheck() throws {
        var machine = CaptureStateMachine()
        XCTAssertEqual(machine.state, .idle)

        try machine.apply(.prepareCapture)
        XCTAssertEqual(machine.state, .setup)

        // Starting scanning from setup enters the ordinary pipeline.
        try machine.apply(.beginCapabilityCheck)
        XCTAssertEqual(machine.state, .capabilityCheck)
    }

    func testSetupCancelReturnsToIdle() throws {
        var machine = CaptureStateMachine()
        try machine.apply(.prepareCapture)
        XCTAssertEqual(machine.state, .setup)
        try machine.apply(.reset)
        XCTAssertEqual(machine.state, .idle)
    }

    func testLegacyIdleDirectBeginStillWorks() throws {
        var machine = CaptureStateMachine()
        try machine.apply(.beginCapabilityCheck)
        XCTAssertEqual(machine.state, .capabilityCheck)
    }

    // MARK: - #212 storage preflight

    func testStoragePreflightThresholds() {
        let preflight = CaptureStoragePreflight(
            availableBytes: 4 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(preflight.readiness, .sufficient)
        XCTAssertFalse(preflight.blocksCaptureStart)

        let low = CaptureStoragePreflight(
            availableBytes: 1 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(low.readiness, .low)
        XCTAssertFalse(low.blocksCaptureStart)

        let critical = CaptureStoragePreflight(
            availableBytes: 400 * 1024 * 1024
        )
        XCTAssertEqual(critical.readiness, .critical)
        XCTAssertTrue(critical.blocksCaptureStart)

        let unknown = CaptureStoragePreflight(availableBytes: nil)
        XCTAssertEqual(unknown.readiness, .unknown)
        XCTAssertFalse(unknown.blocksCaptureStart)
    }

    // MARK: - #272 device readiness

    func testDeviceReadinessAdvisories() {
        let low = CaptureDeviceReadiness(
            batteryLevel: 0.15,
            batteryState: .unplugged,
            lowPowerModeEnabled: false
        )
        XCTAssertTrue(low.hasLowBattery)
        XCTAssertEqual(low.advisories, [.lowBattery])

        let charging = CaptureDeviceReadiness(
            batteryLevel: 0.15,
            batteryState: .charging,
            lowPowerModeEnabled: true
        )
        XCTAssertFalse(charging.hasLowBattery)
        XCTAssertEqual(charging.advisories, [.lowPowerMode])

        let healthy = CaptureDeviceReadiness(
            batteryLevel: 0.8,
            batteryState: .unplugged,
            lowPowerModeEnabled: false
        )
        XCTAssertTrue(healthy.advisories.isEmpty)
    }

    // MARK: - #283 lighting assessment

    func testLightingAssessment() {
        let policy = ScanLightingPolicy()
        XCTAssertEqual(
            policy.assess(ambientIntensityLumens: nil),
            .unknown
        )
        XCTAssertEqual(
            policy.assess(ambientIntensityLumens: 400),
            .adequate
        )
        let low = policy.assess(ambientIntensityLumens: 12)
        XCTAssertEqual(low, .lowLight)
        XCTAssertTrue(
            policy.shouldSurfaceLowLightGuidance(status: low)
        )
        XCTAssertFalse(
            policy.shouldSurfaceLowLightGuidance(status: .adequate)
        )
    }

    // MARK: - #248 startup mode policy (Option B)

    func testStartupModesRequireMeshEligibility() {
        let eligible = CaptureCapabilityMatrix(
            roomPlanSupported: true,
            worldTrackingSupported: true,
            sceneReconstructionSupported: true,
            sceneDepthSupported: true
        )
        XCTAssertEqual(eligible.startupModes, [.roomPlanMesh])
        XCTAssertEqual(
            eligible.allowedModes,
            [.roomPlanMesh, .degradedNoDepth, .evidenceDepth]
        )

        let depthOnly = CaptureCapabilityMatrix(
            roomPlanSupported: true,
            worldTrackingSupported: true,
            sceneReconstructionSupported: false,
            sceneDepthSupported: true
        )
        XCTAssertEqual(depthOnly.startupModes, [])
        XCTAssertEqual(depthOnly.allowedModes, [])
    }

    // MARK: - #216 automatic keyframe selection

    private func keyframeSample(
        at seconds: Double,
        x: Double?,
        z: Double?,
        yaw: Double? = 0,
        tracking: TrackingQualityState = .normal,
        depth: Bool = true,
        usability: FrameUsabilityStatus? = .usable,
        estimatedBytes: Int = 1024
    ) -> AutomaticKeyframeSample {
        AutomaticKeyframeSample(
            timestampSeconds: seconds,
            cameraX: x,
            cameraZ: z,
            yawRadians: yaw,
            trackingState: tracking,
            hasSceneDepth: depth,
            usabilityStatus: usability,
            estimatedBytes: estimatedBytes
        )
    }

    func testKeyframeRetainsSpatiallyNovelNormalFrame() {
        var tracker = AutomaticKeyframeTracker()
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 0, x: 0, z: 0)
            ),
            .retain
        )
        tracker.markRetained(
            keyframeSample(at: 0, x: 0, z: 0),
            actualBytes: 2048
        )
        XCTAssertEqual(tracker.retainedCount, 1)
        XCTAssertEqual(tracker.retainedByteEstimate, 2048)

        // Moved past the translation threshold with an interval gap:
        // retained again.
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 20, x: 2, z: 0)
            ),
            .retain
        )
    }

    func testKeyframeRejectsDuplicatesAndFastIntervals() {
        var tracker = AutomaticKeyframeTracker()
        tracker.markRetained(keyframeSample(at: 0, x: 0, z: 0))

        // Inside the minimum interval.
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 5, x: 2, z: 0)
            ),
            .skippedInterval
        )

        // Same spot and heading after the interval: no novelty.
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 20, x: 0.1, z: 0.1, yaw: 0.05)
            ),
            .skippedDuplicate
        )
    }

    func testKeyframeSkipsBadCandidates() {
        var tracker = AutomaticKeyframeTracker()
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 0, x: 0, z: 0, tracking: .limited)
            ),
            .skippedTrackingNotNormal
        )
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(
                    at: 0, x: 0, z: 0, usability: .unusable
                )
            ),
            .skippedUnusable
        )
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(at: 0, x: nil, z: nil)
            ),
            .skippedNoPosition
        )
    }

    func testKeyframeHardBudgetCaps() {
        var tracker = AutomaticKeyframeTracker(
            configuration: AutomaticKeyframeConfiguration(
                maximumRetainedFrames: 2,
                minimumIntervalSeconds: 1,
                maximumRetainedBytes: 1000
            )
        )
        for i in 0..<2 {
            let sample = keyframeSample(
                at: Double(i * 10), x: Double(i * 10), z: 0,
                estimatedBytes: 400
            )
            XCTAssertEqual(tracker.evaluate(sample), .retain)
            tracker.markRetained(sample, actualBytes: 400)
        }
        // Frame-count cap hit first.
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(
                    at: 100, x: 30, z: 0, estimatedBytes: 10
                )
            ),
            .skippedBudgetFrames
        )

        var byteTracker = AutomaticKeyframeTracker(
            configuration: AutomaticKeyframeConfiguration(
                maximumRetainedFrames: 10,
                minimumIntervalSeconds: 1,
                maximumRetainedBytes: 500
            )
        )
        let first = keyframeSample(
            at: 0, x: 0, z: 0, estimatedBytes: 400
        )
        XCTAssertEqual(byteTracker.evaluate(first), .retain)
        byteTracker.markRetained(first, actualBytes: 400)
        XCTAssertEqual(
            byteTracker.evaluate(
                keyframeSample(
                    at: 10, x: 5, z: 0, estimatedBytes: 200
                )
            ),
            .skippedBudgetBytes
        )
    }

    func testKeyframeNoDepthAllowanceIsBounded() {
        var tracker = AutomaticKeyframeTracker(
            configuration: AutomaticKeyframeConfiguration(
                minimumIntervalSeconds: 1,
                maximumNoDepthFrames: 1
            )
        )
        let a = keyframeSample(
            at: 0, x: 0, z: 0, depth: false
        )
        XCTAssertEqual(tracker.evaluate(a), .retain)
        tracker.markRetained(a)
        XCTAssertEqual(
            tracker.evaluate(
                keyframeSample(
                    at: 10, x: 5, z: 0, depth: false
                )
            ),
            .skippedNoDepthAllowance
        )
    }

    // MARK: - #274 frame usability evaluation

    private func metrics(
        meanLuminance: Double = 0.5,
        clippedFraction: Double = 0.01,
        darkFraction: Double = 0.05,
        gradientEnergy: Double = 0.02,
        exposureSeconds: Double? = nil
    ) -> FrameUsabilityMetrics {
        FrameUsabilityMetrics(
            meanLuminance: meanLuminance,
            clippedFraction: clippedFraction,
            darkFraction: darkFraction,
            gradientEnergy: gradientEnergy,
            exposureSeconds: exposureSeconds
        )
    }

    func testUsableFrameAssessment() {
        let assessment = FrameUsabilityEvaluator().assess(
            metrics: metrics(),
            trackingState: .normal
        )
        XCTAssertEqual(assessment.status, .usable)
        XCTAssertTrue(assessment.issues.isEmpty)
        XCTAssertEqual(
            assessment.policyVersion, "frame_usability_v1"
        )
    }

    func testDarkBlurryOverexposedFramesAreFlagged() {
        let dark = FrameUsabilityEvaluator().assess(
            metrics: metrics(meanLuminance: 0.02, darkFraction: 0.9),
            trackingState: .normal
        )
        XCTAssertEqual(dark.status, .unusable)
        XCTAssertTrue(dark.issues.contains(.tooDark))

        // Clipping alone is advisory-suspect, not a hard reject: a
        // clipped region can still carry usable evidence.
        let clipped = FrameUsabilityEvaluator().assess(
            metrics: metrics(clippedFraction: 0.6),
            trackingState: .normal
        )
        XCTAssertEqual(clipped.status, .suspect)
        XCTAssertTrue(clipped.issues.contains(.overexposed))

        let blurred = FrameUsabilityEvaluator().assess(
            metrics: metrics(
                gradientEnergy: 0.001,
                exposureSeconds: 0.1
            ),
            trackingState: .normal
        )
        XCTAssertEqual(
            blurred.status, .suspect
        )
        XCTAssertTrue(
            blurred.issues.contains(.motionBlurSuspected)
        )
    }

    func testMissingMetricsFallsBackToTrackingOnly() {
        let limited = FrameUsabilityEvaluator().assess(
            metrics: nil,
            trackingState: .limited
        )
        XCTAssertEqual(limited.status, .suspect)
        XCTAssertEqual(limited.issues, [.trackingNotNormal])

        let normal = FrameUsabilityEvaluator().assess(
            metrics: nil,
            trackingState: .normal
        )
        XCTAssertEqual(normal.status, .usable)
    }

    // MARK: - #252 non-visual cue policy

    private func cueInputs(
        tracking: TrackingQualityState? = .normal,
        guidance: ScanMotionGuidance? = nil,
        guidanceComplete: Bool = false,
        endAvailable: Bool = false
    ) -> ScanGuidanceCueInputs {
        ScanGuidanceCueInputs(
            trackingState: tracking,
            guidance: guidance,
            guidanceComplete: guidanceComplete,
            endScanAvailable: endAvailable
        )
    }

    func testCuesAreEdgeTriggeredAndRateLimited() {
        var policy = ScanGuidanceCuePolicy()

        // Seed with normal tracking; the first sample has nothing to
        // edge against, so it emits nothing.
        XCTAssertTrue(
            policy.update(
                cueInputs(tracking: .normal),
                timestampSeconds: 0
            ).isEmpty
        )

        // Tracking loss edge emits the cue once; a steady limited
        // state does not spam.
        let lost = policy.update(
            cueInputs(tracking: .limited),
            timestampSeconds: 1
        )
        XCTAssertTrue(lost.contains(.trackingLost))
        XCTAssertTrue(
            policy.update(
                cueInputs(tracking: .limited),
                timestampSeconds: 2
            ).isEmpty
        )

        let recovered = policy.update(
            cueInputs(tracking: .normal),
            timestampSeconds: 3
        )
        XCTAssertTrue(recovered.contains(.trackingRecovered))
    }

    func testCueCooldownSuppressedRapidRepetition() {
        var policy = ScanGuidanceCuePolicy()
        let guidance = ScanMotionGuidance(
            action: .rotate,
            horizontalDirection: .left
        )
        // In-place turn prompts map to turn cues, never move cues.
        XCTAssertEqual(
            policy.update(
                cueInputs(guidance: guidance),
                timestampSeconds: 0
            ),
            [.turnLeft]
        )
        // Same guidance re-evaluated at 4 Hz emits nothing.
        XCTAssertTrue(
            policy.update(
                cueInputs(guidance: guidance),
                timestampSeconds: 0.25
            ).isEmpty
        )
    }

    func testTiltAndTrackingRecoveryGuidanceEmitCues() {
        var policy = ScanGuidanceCuePolicy()
        XCTAssertEqual(
            policy.update(
                cueInputs(
                    guidance: ScanMotionGuidance(
                        action: .tilt,
                        verticalDirection: .down
                    )
                ),
                timestampSeconds: 0
            ),
            [.tiltDown]
        )
        XCTAssertEqual(
            policy.update(
                cueInputs(
                    guidance: ScanMotionGuidance(
                        action: .tilt,
                        verticalDirection: .up
                    )
                ),
                timestampSeconds: 2
            ),
            [.tiltUp]
        )
        XCTAssertEqual(
            policy.update(
                cueInputs(
                    guidance: ScanMotionGuidance(
                        action: .trackingRecovery
                    )
                ),
                timestampSeconds: 4
            ),
            [.regainTracking]
        )
    }

    func testOneShotCuesRespectGlobalCooldown() {
        var policy = ScanGuidanceCuePolicy()
        XCTAssertEqual(
            policy.evidenceSaved(timestampSeconds: 10),
            .evidenceSaved
        )
        // Within the global cooldown the next event is suppressed.
        XCTAssertNil(policy.targetObserved(timestampSeconds: 10.5))
        XCTAssertEqual(
            policy.targetObserved(timestampSeconds: 12),
            .targetObserved
        )
    }

    // MARK: - #257 operator-declared regions

    func testDeclaredRegionExcludedFromGuidanceButNotObserved() {
        let key = SpatialCoverageCellKey(x: 2, z: 2)
        var tracker = ScanMotionGuidanceTracker(
            configuration: ScanMotionGuidanceConfiguration(
                minimumRepeatedWeakObservations: 1,
                spatialGuidanceActivationCoverageFraction: 0.0
            )
        )
        var declarations = OperatorRegionDeclarations()

        let spatialSummary = spatial(
            cameraX: 0, cameraZ: 0,
            region: region(
                key: key,
                observations: 3,
                diversity: 1,
                distance: .medium,
                classification: .weak
            )
        )
        let coverage = coverage(gap: nil)

        // Weak region is actionable before the declaration.
        let before = tracker.progress(
            coverage: coverage,
            spatialCoverage: spatialSummary
        )
        XCTAssertEqual(before.actionableWeakRegionCount, 1)

        XCTAssertTrue(
            declarations.declare(
                DeclaredCoverageRegion(
                    key: key,
                    reason: .inaccessible,
                    declaredAtSessionSeconds: 3
                )
            )
        )
        tracker.setDeclaredRegionKeys(declarations.declaredKeys)

        let after = tracker.progress(
            coverage: coverage,
            spatialCoverage: spatialSummary
        )
        // No longer actionable for guidance…
        XCTAssertEqual(after.actionableWeakRegionCount, 0)
        // …and still not counted as observed/resolved.
        XCTAssertEqual(
            spatialSummary.regions.first?.classification,
            .weak
        )

        // Revocation restores the region to guidance eligibility.
        XCTAssertTrue(declarations.revoke(key: key))
        tracker.setDeclaredRegionKeys(declarations.declaredKeys)
        let restored = tracker.progress(
            coverage: coverage,
            spatialCoverage: spatialSummary
        )
        XCTAssertEqual(restored.actionableWeakRegionCount, 1)
    }

    func testDeclarationsAreBoundedAndIdempotent() {
        var declarations = OperatorRegionDeclarations()
        for index in 0..<OperatorRegionDeclarations
            .maximumDeclarations
        {
            XCTAssertTrue(
                declarations.declare(
                    DeclaredCoverageRegion(
                        key: SpatialCoverageCellKey(
                            x: index, z: 0
                        ),
                        reason: .unsafe,
                        declaredAtSessionSeconds: 0
                    )
                )
            )
        }
        XCTAssertFalse(
            declarations.declare(
                DeclaredCoverageRegion(
                    key: SpatialCoverageCellKey(x: 999, z: 0),
                    reason: .unsafe,
                    declaredAtSessionSeconds: 0
                )
            )
        )
        // Re-declaring an existing key replaces it in place.
        XCTAssertTrue(
            declarations.declare(
                DeclaredCoverageRegion(
                    key: SpatialCoverageCellKey(x: 0, z: 0),
                    reason: .occludedFixedObject,
                    declaredAtSessionSeconds: 5
                )
            )
        )
        XCTAssertEqual(
            declarations.regions.count,
            OperatorRegionDeclarations.maximumDeclarations
        )
        XCTAssertEqual(
            declarations.region(
                at: SpatialCoverageCellKey(x: 0, z: 0)
            )?.reason,
            .occludedFixedObject
        )
    }

    // MARK: - #250 targeted object pass

    func testTargetedOrbitTracksBucketsAndCompletes() {
        var tracker = TargetedObjectScanTracker(
            target: ScanTargetAnchor(x: 0, y: 0, z: 0, radiusMeters: 0.75),
            requiredBucketCount: 2,
            minimumBucketDwellSeconds: 0.5
        )

        // Stationary on the anchor: same bucket dwell accumulates.
        var status = tracker.record(
            cameraX: 0.9, cameraZ: 0,
            timestampSeconds: 0,
            trackingState: .normal
        )
        XCTAssertEqual(status.observedBucketCount, 0)
        status = tracker.record(
            cameraX: 0.9, cameraZ: 0,
            timestampSeconds: 0.6,
            trackingState: .normal
        )
        XCTAssertEqual(status.observedBucketCount, 1)

        // Move ~90° around the target and dwell again → second bucket.
        status = tracker.record(
            cameraX: 0, cameraZ: 0.9,
            timestampSeconds: 2,
            trackingState: .normal
        )
        status = tracker.record(
            cameraX: 0, cameraZ: 0.9,
            timestampSeconds: 2.6,
            trackingState: .normal
        )
        XCTAssertEqual(status.observedBucketCount, 2)
        XCTAssertTrue(status.isComplete)
    }

    func testTargetedPassReportsOutOfRangeAndExpiry() {
        var tracker = TargetedObjectScanTracker(
            target: ScanTargetAnchor(x: 0, y: 0, z: 0, radiusMeters: 0.75),
            maximumDurationSeconds: 10,
            maximumRangeMeters: 2
        )
        var status = tracker.record(
            cameraX: 5, cameraZ: 0,
            timestampSeconds: 0,
            trackingState: .normal
        )
        XCTAssertTrue(status.outOfRange)

        status = tracker.record(
            cameraX: 0.9, cameraZ: 0,
            timestampSeconds: 11,
            trackingState: .normal
        )
        XCTAssertTrue(status.expired)
    }

    func testTargetedGuidanceSteersTowardWeakestAngle() {
        var tracker = TargetedObjectScanTracker(
            target: ScanTargetAnchor(x: 0, y: 0, z: 0, radiusMeters: 0.75)
        )
        _ = tracker.record(
            cameraX: 0.9, cameraZ: 0,
            timestampSeconds: 0,
            trackingState: .normal
        )
        _ = tracker.record(
            cameraX: 0.9, cameraZ: 0,
            timestampSeconds: 0.7,
            trackingState: .normal
        )
        // Too close later → retreat toward the anchor band.
        let status = tracker.record(
            cameraX: 0.2, cameraZ: 0,
            timestampSeconds: 2,
            trackingState: .normal
        )
        XCTAssertEqual(status.guidance, .retreat)
    }

    // MARK: - #273 loop-closure check

    func testLoopClosureVerdicts() {
        let policy = LoopClosureCheckPolicy()

        XCTAssertEqual(
            policy.assess(
                distanceToStartMeters: nil,
                headingResidualRadians: nil,
                referenceAvailable: false,
                trackingState: .normal
            ).verdict,
            .unavailable
        )
        XCTAssertEqual(
            policy.assess(
                distanceToStartMeters: 0.4,
                headingResidualRadians: 0.1,
                referenceAvailable: true,
                trackingState: .limited
            ).verdict,
            .unavailable
        )
        XCTAssertEqual(
            policy.assess(
                distanceToStartMeters: 2.0,
                headingResidualRadians: 0.1,
                referenceAvailable: true,
                trackingState: .normal
            ).verdict,
            .notAtStart
        )
        let closed = policy.assess(
            distanceToStartMeters: 0.3,
            headingResidualRadians: 0.2,
            referenceAvailable: true,
            trackingState: .normal
        )
        XCTAssertEqual(closed.verdict, .closed)
        XCTAssertEqual(closed.residualMeters, 0.3)

        let drifted = policy.assess(
            distanceToStartMeters: 0.3,
            headingResidualRadians: 1.2,
            referenceAvailable: true,
            trackingState: .normal
        )
        XCTAssertEqual(drifted.verdict, .inconsistent)
    }

    // MARK: - advisory notes → quality diagnostics

    func testAdvisoryNoteSeverityMapping() {
        XCTAssertEqual(
            CaptureAdvisoryNote(
                kind: .frameUsability,
                sessionTimestampSeconds: 1,
                detail: "status=unusable"
            ).qualityDiagnostic.severity,
            .warning
        )
        XCTAssertEqual(
            CaptureAdvisoryNote(
                kind: .declaredRegion,
                sessionTimestampSeconds: 1,
                detail: "cell_x=1 cell_z=0 reason=unsafe"
            ).qualityDiagnostic.severity,
            .info
        )
    }

    func testAdvisoryNoteDocumentRoundTrips() throws {
        let revisionID = CaptureRevisionID()
        let document = CaptureAdvisoryNoteDocument(
            captureRevisionID: revisionID,
            notes: [
                CaptureAdvisoryNote(
                    kind: .automaticKeyframe,
                    sessionTimestampSeconds: 4.2,
                    detail: "policy=auto_keyframe_v1"
                )
            ]
        )
        let data = try document.encoded()
        let decoded = try JSONDecoder().decode(
            CaptureAdvisoryNoteDocument.self,
            from: data
        )
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(
            document.schema, "htdt.capture.advisory_notes"
        )
    }

    func testStoreRecordsAdvisoryNotesAsDerivedPayload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .loopClosureCheck,
                sessionTimestampSeconds: 12,
                detail: "verdict=closed residual_m=0.2"
            )
        )

        // The payload exists, is declared, and integrity covers it.
        let payloadURL = root.appendingPathComponent(
            CaptureAdvisoryNoteDocument.path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: payloadURL.path
            )
        )

        let findings = await store.advisoryFindings
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(
            findings.first?.code, "loop_closure_check"
        )

        // The report surfaces the note as a diagnostic.
        let report = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertTrue(
            report.diagnostics.contains {
                $0.code == "loop_closure_check"
            }
        )
    }

    // MARK: - fixtures (mirroring ScanMotionGuidanceTests)

    private func coverage(
        gap: ScanCoverageGap?,
        tracking: TrackingQualityState = .normal
    ) -> ScanCoverageSummary {
        ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 0, count: 36),
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
                SpatialCoveragePoint2D(x: cameraX, z: cameraZ),
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
                minX: -6, maxX: 6, minZ: -6, maxZ: 6
            )
        )
    }

    private func region(
        key: SpatialCoverageCellKey,
        observations: Int,
        diversity: Int,
        distance: SpatialCoverageDistanceBucket,
        classification: SpatialCoverageClassification
    ) -> SpatialCoverageRegion {
        let mask: UInt16 =
            diversity <= 0
            ? 0
            : (UInt16(1) << UInt16(min(diversity, 8))) - 1

        return SpatialCoverageRegion(
            key: key,
            observationCount: observations,
            normalTrackingObservationCount: observations,
            limitedTrackingObservationCount: 0,
            lastObservedTimestampSeconds: Double(observations),
            viewAngleBucketMask: mask,
            elevationBucketMask: 0,
            latestDistanceBucket: distance,
            depthObservationCount: observations,
            meshSupportCount: observations,
            classification: classification
        )
    }
}
