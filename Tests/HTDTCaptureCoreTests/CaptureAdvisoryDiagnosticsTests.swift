import Foundation
import Testing
@testable import HTDTCaptureCore

private let advisorySpaceID = CoordinateSpaceID(
    rawValue: UUID(
        uuidString: "10000000-0000-4000-8000-00000000a001"
    )!
)
private let advisorySessionID = CaptureSessionID(
    rawValue: UUID(
        uuidString: "10000000-0000-4000-8000-00000000a002"
    )!
)

private func advisorySpeaker(
    role: String,
    space: CoordinateSpaceID
) throws -> CaptureAnnotationEntity {
    try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: space,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Speaker \(role)",
        placement: PlacementProvenance(method: .manualNumeric),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: ChannelRole(rawValue: role)!
    )
}

private func advisoryDistanceMeasurement(
    quantity: String,
    value: Double,
    endpoints: [String] = [],
    uncertainty: Double? = nil
) throws -> CaptureMeasurement {
    try CaptureMeasurement(
        quantityType: quantity,
        value: .scalar(value),
        unit: .meter,
        coordinateSpaceID: advisorySpaceID,
        endpointRefs: endpoints,
        acquisitionMethod: .tapeMeasure,
        statedUncertainty: uncertainty,
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement
    )
}

// MARK: - Task completeness (#259/#217)

@Test
func taskCompletenessWithoutProfileIsExplicit() {
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: nil,
        annotations: [],
        measurements: []
    )
    #expect(report.evaluationState == .noProfileSelected)
    #expect(!report.overallSatisfied)
}

@Test
func taskCompletenessEmptyProfileIsValidButNotMisleading() {
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: .geometryOnly,
        annotations: [],
        measurements: []
    )
    #expect(report.evaluationState == .noRequirementsConfigured)
    #expect(report.overallSatisfied)
    #expect(report.outcomes.isEmpty)
}

@Test
func taskCompletenessEnforcesExactCount() throws {
    let profile = CaptureTaskProfile(
        identifier: "test",
        title: "Test",
        requirements: [
            CaptureTaskRequirement(
                identifier: "primary_mlp",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: "listening_position"
                ),
                minimumCount: 1,
                maximumCount: 1,
                allowsSkippedOutcome: false
            )
        ]
    )
    let mlp = try CaptureAnnotationEntity(
        type: .listeningPosition,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .earCenter,
        label: "MLP",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let second = try CaptureAnnotationEntity(
        type: .listeningPosition,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .earCenter,
        label: "MLP 2",
        placement: PlacementProvenance(method: .manualNumeric)
    )

    let missing = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [], measurements: []
    )
    #expect(missing.outcomes.first?.status == .missing)
    #expect(missing.requiredUnsatisfiedCount == 1)

    let satisfied = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [mlp], measurements: []
    )
    #expect(satisfied.outcomes.first?.status == .satisfied)
    #expect(satisfied.overallSatisfied)

    let over = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [mlp, second], measurements: []
    )
    #expect(over.outcomes.first?.status == .overMaximum)
    #expect(!over.overallSatisfied)
}

@Test
func taskCompletenessMinimumCounts() throws {
    let profile = CaptureTaskProfile(
        identifier: "subs",
        title: "Subs",
        requirements: [
            CaptureTaskRequirement(
                identifier: "subwoofers",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole,
                    value: "LFE"
                ),
                minimumCount: 2,
                allowsSkippedOutcome: false
            )
        ]
    )
    let sub = try CaptureAnnotationEntity(
        type: .subwoofer,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Sub",
        placement: PlacementProvenance(method: .manualNumeric),
        channelRole: .lfe
    )
    let secondSub = try CaptureAnnotationEntity(
        type: .subwoofer,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Sub 2",
        placement: PlacementProvenance(method: .manualNumeric),
        channelRole: .lfe
    )

    let partial = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [sub], measurements: []
    )
    #expect(partial.outcomes.first?.status == .partial)
    #expect(!partial.overallSatisfied)

    let satisfied = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [sub, secondSub], measurements: []
    )
    #expect(satisfied.overallSatisfied)
}

@Test
func taskCompletenessEndpointPairConstraint() throws {
    let profile = CaptureTaskProfile(
        identifier: "mlp_distances",
        title: "Speaker-MLP distances",
        requirements: [
            CaptureTaskRequirement(
                identifier: "speaker_l_to_mlp",
                match: CaptureTaskMatch(
                    kind: .measurementEndpointPair,
                    value: "distance",
                    endpointRefs: ["annotation:L", "annotation:MLP"]
                ),
                minimumCount: 1,
                allowsSkippedOutcome: false
            )
        ]
    )
    let wrongPair = try advisoryDistanceMeasurement(
        quantity: "distance", value: 2.0,
        endpoints: ["annotation:R", "annotation:MLP"]
    )
    let rightPair = try advisoryDistanceMeasurement(
        quantity: "distance", value: 2.0,
        endpoints: ["annotation:MLP", "annotation:L"]
    )

    let missing = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [], measurements: [wrongPair]
    )
    #expect(missing.outcomes.first?.status == .missing)

    // Endpoint order is not significant — the pair is a set.
    let satisfied = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [], measurements: [rightPair]
    )
    #expect(satisfied.overallSatisfied)
}

@Test
func taskCompletenessOptionalAndSkippedOutcomes() throws {
    let profile = CaptureTaskProfile(
        identifier: "mixed",
        title: "Mixed",
        requirements: [
            CaptureTaskRequirement(
                identifier: "required_role",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole, value: "L"
                ),
                minimumCount: 1,
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "optional_role",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole, value: "SBL"
                ),
                minimumCount: 1,
                isOptional: true,
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "skippable",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole, value: "SBR"
                ),
                minimumCount: 1,
                allowsSkippedOutcome: true
            ),
        ]
    )
    let speaker = try advisorySpeaker(role: "L", space: advisorySpaceID)
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile,
        annotations: [speaker],
        measurements: [],
        skippedRequirementIDs: ["skippable"]
    )
    let statuses = Dictionary(
        uniqueKeysWithValues: report.outcomes.map {
            ($0.requirement.identifier, $0.status)
        }
    )
    #expect(statuses["required_role"] == .satisfied)
    #expect(statuses["optional_role"] == .optionalAbsent)
    #expect(statuses["skippable"] == .skipped)
    #expect(report.overallSatisfied)
}

@Test
func taskCompletenessAlternativeGroups() throws {
    let profile = CaptureTaskProfile(
        identifier: "screen",
        title: "Screen",
        requirements: [
            CaptureTaskRequirement(
                identifier: "display",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType, value: "display"
                ),
                minimumCount: 1,
                alternativeGroup: "screen_presence",
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "projection",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: "projection_screen"
                ),
                minimumCount: 1,
                alternativeGroup: "screen_presence",
                allowsSkippedOutcome: false
            ),
        ]
    )
    let display = try CaptureAnnotationEntity(
        type: .display,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "TV",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile, annotations: [display], measurements: []
    )
    let statuses = Dictionary(
        uniqueKeysWithValues: report.outcomes.map {
            ($0.requirement.identifier, $0.status)
        }
    )
    #expect(statuses["display"] == .satisfied)
    #expect(statuses["projection"] == .satisfiedByAlternative)
    #expect(report.overallSatisfied)
}

@Test
func duplicateRecordsDoNotSatisfyUnrelatedRequirements() throws {
    let profile = CaptureTaskProfile(
        identifier: "stereo",
        title: "Stereo",
        requirements: [
            CaptureTaskRequirement(
                identifier: "left",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole, value: "L"
                ),
                minimumCount: 1,
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "right",
                match: CaptureTaskMatch(
                    kind: .annotationChannelRole, value: "R"
                ),
                minimumCount: 1,
                allowsSkippedOutcome: false
            ),
        ]
    )
    let leftA = try advisorySpeaker(role: "L", space: advisorySpaceID)
    let leftB = try advisorySpeaker(role: "L", space: advisorySpaceID)
    let report = CaptureTaskCompletenessEvaluator.evaluate(
        profile: profile,
        annotations: [leftA, leftB],
        measurements: []
    )
    let statuses = Dictionary(
        uniqueKeysWithValues: report.outcomes.map {
            ($0.requirement.identifier, $0.status)
        }
    )
    #expect(statuses["left"] == .satisfied)
    #expect(statuses["right"] == .missing)
    #expect(!report.overallSatisfied)
}

// MARK: - Conflict analysis (#229)

@Test
func conflictAnalysisUnavailableWhenCollectionsMissing() throws {
    let report = CaptureConflictAnalyzer.analyze(
        measurements: nil,
        annotations: nil,
        roomMetadata: nil
    )
    #expect(report.status == .unavailable)

    let analyzed = CaptureConflictAnalyzer.analyze(
        measurements: [],
        annotations: [],
        roomMetadata: nil
    )
    // Analyzed-but-empty is distinguishable from unavailable.
    #expect(analyzed.status == .analyzed)
    #expect(analyzed.conflicts.isEmpty)
}

@Test
func sameQuantityConflictingMeasurementsAreSurfaced() throws {
    let a = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.20,
        endpoints: ["wall:a", "wall:b"]
    )
    let b = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.35,
        endpoints: ["wall:a", "wall:b"]
    )
    let report = CaptureConflictAnalyzer.analyze(
        measurements: [a, b],
        annotations: [],
        roomMetadata: nil
    )
    #expect(report.status == .analyzed)
    let conflict = try #require(
        report.conflicts.first {
            $0.kind == .sameQuantityValueDisagreement
        }
    )
    // Both candidates survive side-by-side; nothing auto-resolved.
    #expect(conflict.candidates.count == 2)
}

@Test
func sameQuantityWithinToleranceIsNotAConflict() throws {
    let a = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.200,
        endpoints: ["wall:a", "wall:b"], uncertainty: 0.01
    )
    let b = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.210,
        endpoints: ["wall:a", "wall:b"], uncertainty: 0.01
    )
    let report = CaptureConflictAnalyzer.analyze(
        measurements: [a, b],
        annotations: [],
        roomMetadata: nil
    )
    #expect(
        !report.conflicts.contains {
            $0.kind == .sameQuantityValueDisagreement
        }
    )
}

@Test
func displayWithoutOrientationIsAConflict() throws {
    let display = try CaptureAnnotationEntity(
        type: .display,
        coordinateSpaceID: advisorySpaceID,
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "TV",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let report = CaptureConflictAnalyzer.analyze(
        measurements: [],
        annotations: [display],
        roomMetadata: nil
    )
    #expect(
        report.conflicts.contains {
            $0.kind == .annotationOrientationMissing
        }
    )
}

@Test
func measurementWithoutEndpointBindingIsAConflict() throws {
    let measurement = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.2
    )
    let report = CaptureConflictAnalyzer.analyze(
        measurements: [measurement],
        annotations: [],
        roomMetadata: nil
    )
    #expect(
        report.conflicts.contains {
            $0.kind == .endpointBindingMissing
        }
    )
}

private func roomMetadataWithDimensions(
    x: Double, y: Double, z: Double
) throws -> CapturedRoomMetadataDocument {
    let runtime = CaptureRuntimeProvenance(
        osVersion: "test-os",
        appVersion: "0.1.0",
        appBuild: "test"
    )
    let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
        data: Data(#"{"raw":true}"#.utf8),
        captureSessionID: advisorySessionID,
        coordinateSpaceID: advisorySpaceID,
        runtime: runtime
    )
    let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
        data: Data(#"{"processed":true}"#.utf8),
        to: raw
    )
    return try CapturedRoomMetadataDocument(
        captureRevisionID: CaptureRevisionID(),
        raw: raw.descriptor,
        processed: lineage.processed?.descriptor,
        summary: CapturedRoomContentSummary(
            dimensionsMeters: try CapturedRoomDimensionsSummary(
                xMeters: x, yMeters: y, zMeters: z
            )
        )
    )
}

@Test
func roomPlanDimensionDisagreementIsSurfaced() throws {
    let roomMetadata = try roomMetadataWithDimensions(
        x: 4.0, y: 2.5, z: 5.0
    )
    let conflicting = try advisoryDistanceMeasurement(
        quantity: "room_width", value: 4.8
    )
    let matching = try advisoryDistanceMeasurement(
        quantity: "room_length", value: 5.02
    )
    let report = CaptureConflictAnalyzer.analyze(
        measurements: [conflicting, matching],
        annotations: [],
        roomMetadata: roomMetadata
    )
    let disagreements = report.conflicts.filter {
        $0.kind == .roomPlanDimensionDisagreement
    }
    // 4.8 vs RoomPlan 4.0 exceeds tolerance; 5.02 vs 5.0 does not.
    #expect(disagreements.count == 1)
    #expect(disagreements.first?.candidates.count == 2)
}

// MARK: - RoomPlan ↔ mesh consistency (#277)

private func simpleMeshGeometry(
    classification: UInt8 = 1
) throws -> MeshGeometryPayload {
    try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        triangleIndices: [0, 1, 2],
        faceClassifications: [classification]
    )
}

@Test
func meshConsistencyAbsentVsSharedAuthority() throws {
    var emptyProfile = MeshGeometryProfile()
    let noMesh = RoomPlanMeshConsistencyAnalyzer.analyze(
        meshProfile: emptyProfile,
        roomMetadata: nil,
        meshCoordinateSpaceID: nil,
        roomPlanCoordinateSpaceID: nil
    )
    #expect(noMesh.status == .meshEvidenceAbsent)

    let geometry = try simpleMeshGeometry()
    emptyProfile.record(
        worldFromAnchor: .identity, geometry: geometry
    )
    let noRoomPlan = RoomPlanMeshConsistencyAnalyzer.analyze(
        meshProfile: emptyProfile,
        roomMetadata: nil,
        meshCoordinateSpaceID: advisorySpaceID,
        roomPlanCoordinateSpaceID: advisorySpaceID
    )
    #expect(noRoomPlan.status == .roomPlanSummaryAbsent)

    let roomMetadata = try roomMetadataWithDimensions(
        x: 4.0, y: 2.5, z: 5.0
    )
    let unshared = RoomPlanMeshConsistencyAnalyzer.analyze(
        meshProfile: emptyProfile,
        roomMetadata: roomMetadata,
        meshCoordinateSpaceID: advisorySpaceID,
        roomPlanCoordinateSpaceID: CoordinateSpaceID()
    )
    // Different coordinate authority: analysis refuses to compare
    // instead of guessing (#277).
    #expect(unshared.status == .authorityUnshared)

    let analyzed = RoomPlanMeshConsistencyAnalyzer.analyze(
        meshProfile: emptyProfile,
        roomMetadata: roomMetadata,
        meshCoordinateSpaceID: advisorySpaceID,
        roomPlanCoordinateSpaceID: advisorySpaceID
    )
    #expect(analyzed.status == .analyzed)
    // Mesh unit cube vs 4.0×2.5×5.0 room: every axis exceeds the 0.25m
    // advisory tolerance so all three are discrepant.
    #expect(analyzed.discrepantAxes == ["x", "y", "z"])
    #expect(analyzed.wallFaceCount == 1)
}

// MARK: - Benchmark binding (#285)

@Test
func benchmarkReferenceValidationEnforcesImmutability() {
    #expect(
        BenchmarkReferenceValidator.isValid(
            "htdt.benchmark.iphone15pro-lidar@1.0.0"
        )
    )
    #expect(
        BenchmarkReferenceValidator.isValid(
            "htdt.benchmark.iphone15pro-lidar@1.0"
        ) == false
    )
    #expect(
        BenchmarkReferenceValidator.isValid(
            "htdt.benchmark.iphone15pro-lidar"
        ) == false
    )
    #expect(
        BenchmarkReferenceValidator.isValid(
            "htdt.benchmark.iphone15pro-lidar@latest"
        ) == false
    )
}

@Test
func benchmarkCompatibilityPredicatesAllMustMatch() {
    let context = BenchmarkBindingContext(
        appVersion: "1.2.0",
        deviceClass: "iPhone17,2",
        osMajorVersion: 26,
        captureMode: "roomplan_mesh",
        rulesetVersion: "1.2.0",
        bundleSchemaVersion: "1.0.0"
    )
    let matching = BenchmarkCompatibilityRule(
        reference: "htdt.benchmark.lidar@1.0.0",
        deviceClass: "iPhone17,2",
        osMajorMinimum: 26,
        captureMode: "roomplan_mesh",
        rulesetVersion: "1.2.0"
    )
    #expect(matching.matches(context))

    // A mismatched device class means the benchmark evidence cannot
    // bind silently.
    let wrongDevice = BenchmarkCompatibilityRule(
        reference: "htdt.benchmark.ipad@1.0.0",
        deviceClass: "iPad14,1"
    )
    #expect(!wrongDevice.matches(context))

    // OS bounds are inclusive and versioned.
    let osRule = BenchmarkCompatibilityRule(
        reference: "htdt.benchmark.os26@1.0.0",
        osMajorMinimum: 26,
        osMajorMaximum: 26
    )
    #expect(osRule.matches(context))
    #expect(
        !osRule.matches(
            BenchmarkBindingContext(
                appVersion: context.appVersion,
                deviceClass: context.deviceClass,
                osMajorVersion: 27,
                captureMode: context.captureMode,
                rulesetVersion: context.rulesetVersion,
                bundleSchemaVersion: context.bundleSchemaVersion
            )
        )
    )
}

@Test
func benchmarkAuthorityEmptyByDefault() {
    #expect(BenchmarkReferenceAuthority.publishedRules.isEmpty)
    // With no published rules a production capture binds an explicit
    // empty list rather than inheriting stale evidence (#285).
    #expect(
        BenchmarkReferenceAuthority.compatibleReferences(
            context: BenchmarkBindingContext(
                appVersion: "1.0.0",
                deviceClass: "iPhone17,2",
                osMajorVersion: 26,
                captureMode: "roomplan_mesh",
                rulesetVersion: "1.2.0",
                bundleSchemaVersion: "1.0.0"
            )
        ).isEmpty
    )
}

// MARK: - RoomPlan guidance history (#260)

@Test
func guidanceTrackerDeduplicatesConsecutiveInstructions() {
    var tracker = RoomPlanGuidanceTracker()
    tracker.record(
        RoomPlanGuidanceObservation(
            instruction: "moveCloseToWall", sessionTimestampSeconds: 1
        )
    )
    tracker.record(
        RoomPlanGuidanceObservation(
            instruction: "moveCloseToWall", sessionTimestampSeconds: 2
        )
    )
    tracker.record(
        RoomPlanGuidanceObservation(
            instruction: "slowDown", sessionTimestampSeconds: 3
        )
    )
    tracker.record(
        RoomPlanGuidanceObservation(
            instruction: "moveCloseToWall", sessionTimestampSeconds: 4
        )
    )
    let history = tracker.history()
    #expect(history.source == .roomPlanDelegate)
    #expect(history.transitions.count == 3)
    #expect(history.transitions[0].count == 2)
    #expect(history.transitions[0].firstSessionTimestampSeconds == 1)
    #expect(history.transitions[0].lastSessionTimestampSeconds == 2)
    #expect(history.transitions[1].instruction == "slowDown")
    // Non-consecutive repeats start a new transition rather than
    // mutating the earlier span.
    #expect(history.transitions[2].count == 1)
}

@Test
func guidanceTrackerBoundsHistory() {
    var tracker = RoomPlanGuidanceTracker()
    for index in 0 ..< (RoomPlanGuidanceTracker.transitionLimit + 10) {
        tracker.record(
            RoomPlanGuidanceObservation(
                instruction: "instruction_\(index)",
                sessionTimestampSeconds: Double(index)
            )
        )
    }
    let history = tracker.history()
    #expect(
        history.transitions.count
            == RoomPlanGuidanceTracker.transitionLimit
    )
    #expect(history.truncated)
}

// MARK: - Mesh lifecycle diagnostics (#268)

@Test
func meshLifecycleTrackerSummarizesStability() {
    var tracker = MeshAnchorLifecycleTracker()
    let a = UUID()
    let b = UUID()
    tracker.record(.added, anchorID: a, sessionTimestampSeconds: 1)
    tracker.record(.added, anchorID: b, sessionTimestampSeconds: 2)
    tracker.record(.updated, anchorID: a, sessionTimestampSeconds: 3)
    tracker.record(.updated, anchorID: a, sessionTimestampSeconds: 4)
    tracker.record(.removed, anchorID: b, sessionTimestampSeconds: 5)
    let summary = tracker.summary(endSessionTimestampSeconds: 10)
    #expect(summary.addedCount == 2)
    #expect(summary.updatedCount == 2)
    #expect(summary.removedCount == 1)
    #expect(summary.uniqueAnchorsObserved == 2)
    #expect(summary.finalActiveAnchors == 1)
    // Last update at t=4, end at t=10 → 6s since last mesh activity.
    #expect(summary.secondsSinceLastUpdate == 6)
    #expect(summary.anchorsUpdatedOnceCount == 0)
    #expect(summary.anchorsUpdatedTwoToFourCount == 1)
    #expect(summary.anchorsNeverUpdatedCount == 1)
}

// MARK: - Depth sufficiency (#284)

@Test
func depthAccumulatorCountsValidAndConfidentSamples() throws {
    var accumulator = DepthSufficiencyAccumulator()
    // 8x8 frame: all valid, half confident.
    let depth = try DepthMapPayload(
        width: 8,
        height: 8,
        valuesMeters: Array(repeating: 2.0, count: 64)
    )
    let confidence = try ConfidenceMapPayload(
        width: 8,
        height: 8,
        values: Array(repeating: 2, count: 32)
            + Array(repeating: 0, count: 32)
    )
    accumulator.record(depth: depth, confidence: confidence)
    let summary = try #require(accumulator.summary)
    #expect(summary.framesAnalyzed == 1)
    #expect(summary.validSamples == 64)
    #expect(summary.validFraction == 1.0)
    #expect(summary.bestFrameSpatialCoverageFraction == 1.0)
    #expect(summary.confidentValidSamples == 32)
    #expect(summary.lowConfidenceValidSamples == 32)
    #expect(summary.confidentFraction == 0.5)
}

@Test
func depthSufficiencyPolicyRejectsSinglePixel() throws {
    var accumulator = DepthSufficiencyAccumulator()
    // One valid pixel in a 10x10 frame — the pre-#284 floor.
    accumulator.record(
        depth: try DepthMapPayload(
            width: 10,
            height: 10,
            valuesMeters: [1.0] + Array(repeating: -1, count: 99),
            validityMask: [1] + Array(repeating: 1, count: 99)
        ),
        confidence: nil
    )
    let policy = DepthFallbackSufficiencyPolicy()
    let failures = policy.failures(for: accumulator.summary)
    #expect(failures.contains(.validSamplesBelowMinimum))
    #expect(failures.contains(.confidenceEvidenceMissing))
}

@Test
func depthSufficiencyPolicyRejectsLowConfidenceOnly() throws {
    var accumulator = DepthSufficiencyAccumulator()
    accumulator.record(
        depth: try DepthMapPayload(
            width: 32,
            height: 32,
            valuesMeters: Array(repeating: 2.0, count: 1024)
        ),
        confidence: try ConfidenceMapPayload(
            width: 32,
            height: 32,
            values: Array(repeating: 0, count: 1024)
        )
    )
    let failures = DepthFallbackSufficiencyPolicy().failures(
        for: accumulator.summary
    )
    #expect(failures.contains(.confidentFractionBelowMinimum))
}

// MARK: - Store integration (#223, #285, #259)

private func advisoryFramePackage() throws -> FrameEvidencePackage {
    let frameID = EvidenceFrameID()
    let pixel = Data([1, 2, 3, 4])
    let descriptor = try FrameEvidenceDescriptor(
        frameID: frameID,
        captureSessionID: advisorySessionID,
        coordinateSpaceID: advisorySpaceID,
        sessionTimestampSeconds: 1,
        worldFromCamera: .identity,
        intrinsics: try CameraIntrinsics3x3(
            values: [1, 0, 0, 0, 1, 0, 0, 0, 1]
        ),
        imageWidth: 1,
        imageHeight: 1,
        pixelFormatFourCC: 0,
        pixelRelativePath:
            "evidence/frames/\(frameID).pixelbin",
        pixelByteCount: pixel.count,
        pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
        depthStatus: .unavailable,
        depth: nil
    )
    return try FrameEvidencePackageBuilder.build(
        descriptor: descriptor,
        pixelPayload: pixel,
        depthPayload: nil,
        confidencePayload: nil
    )
}

private func advisoryEndContext() -> CaptureEndCoverageSummary {
    CaptureEndCoverageSummary(
        algorithm: "advisory-scan-coverage",
        algorithmVersion: "1.0.0",
        endSessionTimestampSeconds: 42,
        sectorCount: 12,
        minimumSamplesPerCell: 2,
        cellSampleCounts: Array(repeating: 2, count: 36),
        coverageFraction: 0.9,
        pitchBandFractions: ["lower": 0.8, "mid": 1.0, "upper": 0.7],
        weakCells: ["2/upper"],
        latestTrackingState: .normal,
        latestTrackingReason: nil,
        latestMeshAnchorCount: 4,
        latestHasSceneDepth: true,
        spatialCellSizeMeters: 0.5,
        observedRegionCount: 10,
        weakRegionCount: 2,
        displayUnknownRegionCount: 1,
        usesDepthFallback: false,
        meshAvailabilityState: "anchorsObserved",
        weakRegionKeys: ["1,2"],
        geometryEvidenceMode: "mesh_and_depth",
        movementCapability: "walking",
        guidanceCompletedAttempts: 1,
        guidanceMaximumAttempts: 3,
        actionableWeakRegionCount: 2,
        saturatedWeakRegionCount: 0,
        guidanceComplete: false
    )
}

@Test
func sealedWorkingSetPersistsAdvisoryPayload() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try CaptureWorkingSetStore(rootDirectory: root)
    try await store.persistFramePackage(try advisoryFramePackage())
    await store.recordRoomPlanGuidanceInstruction(
        RoomPlanGuidanceObservation(
            instruction: "moveCloseToWall",
            sessionTimestampSeconds: 3
        )
    )
    await store.recordMeshAnchorLifecycle(
        .added, anchorID: UUID(), sessionTimestampSeconds: 2
    )
    await store.recordAdvisoryEndContext(advisoryEndContext())
    try await store.persistAnnotationPackage(
        try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .listeningPosition,
                    coordinateSpaceID: advisorySpaceID,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .earCenter,
                    label: "MLP",
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    )
                )
            ]
        )
    )
    // Commit both authority collections so conflict analysis is
    // analyzed-empty rather than unavailable (#229).
    try await store.persistMeasurementPackage(
        try MeasurementEvidencePackageBuilder.build(measurements: [])
    )
    try await store.recordTaskProfile(
        .roomAndListeningPosition,
        skippedRequirementIDs: []
    )
    try await store.recordBenchmarkReferences(
        ["htdt.benchmark.fixture@1.0.0"]
    )

    let sealed = try await store.sealForFinalization(
        requirements: CaptureQualityRequirements(
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )
    #expect(sealed.qualityReport.readyForHTDTIngestion)
    // #285: bound refs flow into the canonical quality report.
    #expect(
        sealed.qualityReport.benchmarkRefs
            == ["htdt.benchmark.fixture@1.0.0"]
    )

    let declaration = try #require(
        sealed.snapshot.payloadDeclarations.first {
            $0.path == "quality/capture-advisory.json"
        }
    )
    #expect(declaration.provenanceClass == .captureAppDerived)
    #expect(declaration.role == .derived)

    let advisoryURL = root.appendingPathComponent(
        "quality/capture-advisory.json"
    )
    #expect(FileManager.default.fileExists(atPath: advisoryURL.path))
    let persisted = try JSONDecoder().decode(
        CaptureAdvisoryReport.self,
        from: Data(contentsOf: advisoryURL)
    )
    #expect(persisted.authority == "capture_app_derived")
    #expect(persisted.endCoverage?.coverageFraction == 0.9)
    #expect(persisted.endCoverage?.weakCells == ["2/upper"])
    #expect(
        persisted.roomPlanGuidance?.transitions.first?.instruction
            == "moveCloseToWall"
    )
    #expect(persisted.meshLifecycle?.addedCount == 1)
    #expect(
        persisted.taskCompleteness?.evaluationState == .evaluated
    )
    #expect(
        persisted.taskCompleteness?.overallSatisfied == true
    )
    #expect(persisted.conflicts?.status == .analyzed)
    #expect(persisted.captureSessionID != nil)

    // Unseal removes the advisory payload with the quality report.
    try await store.unseal()
    #expect(
        !FileManager.default.fileExists(atPath: advisoryURL.path)
    )
    let qualityURL = root.appendingPathComponent(
        "quality/capture-quality.json"
    )
    #expect(!FileManager.default.fileExists(atPath: qualityURL.path))
}

@Test
func advisoryEvaluationBeforeSealReflectsRecordedState() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try CaptureWorkingSetStore(rootDirectory: root)
    try await store.persistFramePackage(try advisoryFramePackage())
    try await store.persistAnnotationPackage(
        try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .listeningPosition,
                    coordinateSpaceID: advisorySpaceID,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .earCenter,
                    label: "MLP",
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    )
                )
            ]
        )
    )
    try await store.recordTaskProfile(
        .roomAndListeningPosition
    )
    let advisory = try #require(
        await store.evaluateAdvisoryDiagnostics()
    )
    #expect(advisory.taskCompleteness?.overallSatisfied == true)
    // RoomPlan guidance defaults to an explicit unavailable source
    // rather than looking like a clean session (#260).
    #expect(advisory.roomPlanGuidance?.source == .unavailable)
}

@Test
func recordBenchmarkReferencesRejectsNonVersioned() async throws {
    let store = try CaptureWorkingSetStore(
        rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    await #expect(throws: CaptureWorkingSetError.self) {
        try await store.recordBenchmarkReferences(
            ["htdt.benchmark.unversioned"]
        )
    }
}

@Test
func recordTaskProfileRejectsEmptyIdentifiers() async throws {
    let store = try CaptureWorkingSetStore(
        rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    await #expect(throws: CaptureWorkingSetError.self) {
        try await store.recordTaskProfile(
            CaptureTaskProfile(
                identifier: "",
                title: "Bad",
                requirements: []
            )
        )
    }
    await #expect(throws: CaptureWorkingSetError.self) {
        try await store.recordTaskProfile(
            CaptureTaskProfile(
                identifier: "ok",
                title: "Bad",
                requirements: [
                    CaptureTaskRequirement(
                        identifier: "",
                        match: CaptureTaskMatch(
                            kind: .annotationEntityType,
                            value: "speaker"
                        ),
                        minimumCount: 1,
                        allowsSkippedOutcome: false
                    ),
                ]
            )
        )
    }
}
