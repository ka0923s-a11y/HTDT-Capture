import Foundation
import Testing
@testable import HTDTCaptureCore

/// Scan copilot tests (#272). The binding guarantees exercised here:
/// the context stays bounded and versioned; the validator accepts
/// zero unsafe-movement or finish-class suggestions; and every
/// model-path failure resolves to the deterministic baseline.
private func copilotDiagnostic(
    _ index: Int,
    code: String = "tracking_limited",
    severity: QualityDiagnosticSeverity = .warning
) -> ScanCopilotDiagnosticItem {
    ScanCopilotDiagnosticItem(
        id: "d\(index)",
        code: code,
        severity: severity,
        summary: "diagnostic \(index)"
    )
}

private func scanningContext(
    movementCapability: ScanMovementCapability = .unrestricted,
    trackingState: TrackingQualityState? = .normal,
    directionCoverageFraction: Double = 0.5,
    weakRegions: Int = 0,
    candidateTargetIDs: [String] = [],
    endScanAvailable: Bool = false,
    diagnostics: [ScanCopilotDiagnosticItem] = []
) -> ScanCopilotContext {
    ScanCopilotContext(
        stage: .scanning,
        trackingState: trackingState,
        trackingReason: nil,
        directionCoverageFraction: directionCoverageFraction,
        guidanceComplete: false,
        guidanceCompletionSource: nil,
        movementCapability: movementCapability,
        weakRegionKeys: candidateTargetIDs,
        actionableWeakRegionCount: weakRegions,
        saturatedWeakRegionCount: 0,
        remoteWeakRegionCount: 0,
        lowLightActive: false,
        unresolvedRevisitFlagIDs: [],
        targetScanState: nil,
        candidateTargetIDs: candidateTargetIDs,
        missingTaskItemCount: 0,
        resourcePressureKinds: [],
        endScanAvailable: endScanAvailable,
        diagnostics: diagnostics
    )
}

// MARK: - Context bounds + versioning

@Test
func contextCarriesFixedSchemaAndVersion() throws {
    let context = scanningContext()
    #expect(context.schema == "htdt.capture.scan_copilot_context")
    #expect(context.schemaVersion == "1.0.0")
    let encoded = try JSONEncoder().encode(context)
    let decoded = try JSONDecoder().decode(
        ScanCopilotContext.self,
        from: encoded
    )
    #expect(decoded == context)
}

@Test
func contextCapsEveryBoundedField() {
    let longText = String(repeating: "x", count: 500)
    let context = ScanCopilotContext(
        stage: .scanning,
        trackingReason: longText,
        weakRegionKeys: (0..<32).map { "r\($0)" },
        unresolvedRevisitFlagIDs: (0..<32).map { "f\($0)" },
        candidateTargetIDs: (0..<32).map { "t\($0)" },
        resourcePressureKinds: (0..<32).map { "k\($0)" },
        diagnostics: (0..<32).map { copilotDiagnostic($0) }
    )
    #expect(
        context.diagnostics.count
            == ScanCopilotContext.maximumDiagnostics
    )
    #expect(
        context.weakRegionKeys.count
            == ScanCopilotContext.maximumCandidateIDs
    )
    #expect(
        context.unresolvedRevisitFlagIDs.count
            == ScanCopilotContext.maximumCandidateIDs
    )
    #expect(
        context.candidateTargetIDs.count
            == ScanCopilotContext.maximumCandidateIDs
    )
    #expect(
        context.resourcePressureKinds.count
            == ScanCopilotContext.maximumReasonCodes
    )
    #expect(
        (context.trackingReason?.count ?? 0)
            <= ScanCopilotContext.maximumFieldCharacters
    )
    #expect(
        context.diagnostics.allSatisfy {
            $0.summary.count
                <= ScanCopilotContext.maximumFieldCharacters
        }
    )
}

@Test
func contextClampsFractionAndCounts() {
    let context = ScanCopilotContext(
        stage: .scanning,
        directionCoverageFraction: .infinity,
        actionableWeakRegionCount: -4,
        saturatedWeakRegionCount: -2,
        remoteWeakRegionCount: -1,
        missingTaskItemCount: -9
    )
    #expect(context.directionCoverageFraction == 0)
    #expect(context.actionableWeakRegionCount == 0)
    #expect(context.saturatedWeakRegionCount == 0)
    #expect(context.remoteWeakRegionCount == 0)
    #expect(context.missingTaskItemCount == 0)
}

@Test
func contextDigestIsStableAndStateSensitive() {
    let first = scanningContext(directionCoverageFraction: 0.4)
    let same = scanningContext(directionCoverageFraction: 0.4)
    let different = scanningContext(directionCoverageFraction: 0.7)
    #expect(first.contextDigest == same.contextDigest)
    #expect(first.contextDigest != different.contextDigest)
    #expect(first.contextDigest.count == 16)
}

@Test
func reducedContextShrinksListsButKeepsFindings() {
    let context = ScanCopilotContext(
        stage: .scanning,
        weakRegionKeys: (0..<8).map { "r\($0)" },
        actionableWeakRegionCount: 8,
        candidateTargetIDs: (0..<8).map { "r\($0)" },
        diagnostics: (0..<8).map { copilotDiagnostic($0) }
    )
    let reduced = context.reduced()
    #expect(reduced.diagnostics.count == 4)
    #expect(reduced.weakRegionKeys.count == 4)
    #expect(reduced.candidateTargetIDs.count == 4)
    // Counts stay authoritative — reduction never erases findings.
    #expect(reduced.actionableWeakRegionCount == 8)
}

// MARK: - Validator: hard rejections

@Test
func validatorRejectsMovementWhenConstrained() {
    let context = scanningContext(
        movementCapability: .safetyConstrained,
        weakRegions: 3,
        candidateTargetIDs: ["r0"],
        diagnostics: [
            copilotDiagnostic(0, code: "coverage_weak_region")
        ]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "move_to_gap",
        templateID: "move_closer",
        priorityID: "normal",
        targetID: "r0",
        reasonCodes: ["weak_region"],
        sourceDiagnosticIDs: ["d0"]
    )
    let (suggestion, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(suggestion == nil)
    #expect(violations.contains(.movementNotQualified))
}

@Test
func validatorRejectsMovementWhenStationaryOnly() {
    let context = scanningContext(
        movementCapability: .stationaryOnly,
        weakRegions: 2,
        candidateTargetIDs: ["r0"]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "move_to_gap",
        templateID: "revisit_area",
        priorityID: "normal"
    )
    let (_, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(violations.contains(.movementNotQualified))
}

@Test
func validatorRejectsRescanTargetWhenConstrained() {
    let context = ScanCopilotContext(
        stage: .scanning,
        movementCapability: .safetyConstrained,
        targetScanState: "stalled",
        candidateTargetIDs: ["target0"]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "rescan_target",
        templateID: "rescan_target",
        priorityID: "normal",
        targetID: "target0",
        reasonCodes: ["target_scan_incomplete"]
    )
    let (suggestion, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(suggestion == nil)
    #expect(violations.contains(.movementNotQualified))
}

@Test
func validatorRejectsFinishSemantics() {
    // The review/finish class is only permitted when the normal
    // review affordance is available.
    let context = scanningContext(endScanAvailable: false)
    let draft = ScanCopilotModelDraft(
        actionID: "review",
        templateID: "review_flagged_items",
        priorityID: "normal"
    )
    let (suggestion, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(suggestion == nil)
    #expect(violations.contains(.finishNotPermitted))
}

@Test
func validatorRejectsUnknownActionAndTemplate() {
    let context = scanningContext()
    let badAction = ScanCopilotModelDraft(
        actionID: "finish_capture_now",
        templateID: "keep_scanning",
        priorityID: "high"
    )
    #expect(
        ScanCopilotValidator.violations(
            draft: badAction, context: context
        ).contains(.unknownAction)
    )
    let badTemplate = ScanCopilotModelDraft(
        actionID: "hold",
        templateID: "delete_all_annotations",
        priorityID: "high"
    )
    #expect(
        ScanCopilotValidator.violations(
            draft: badTemplate, context: context
        ).contains(.unknownTemplate)
    )
}

@Test
func validatorRejectsUnsupportedReasonAndUnknownIDs() {
    let context = scanningContext(
        diagnostics: [copilotDiagnostic(0)]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "hold",
        templateID: "hold_steady",
        priorityID: "normal",
        targetID: "not_a_candidate",
        reasonCodes: ["low_light", "invented_reason"],
        sourceDiagnosticIDs: ["d0", "d99"]
    )
    let (_, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(violations.contains(.unknownReasonCode))
    #expect(violations.contains(.reasonNotSupported))
    #expect(violations.contains(.unknownTargetID))
    #expect(violations.contains(.unknownDiagnosticID))
}

@Test
func validatorRejectsStaleContextDigest() {
    let context = scanningContext()
    let draft = ScanCopilotModelDraft(
        actionID: "hold",
        templateID: "hold_steady",
        priorityID: "normal",
        contextDigest: "0000000000000000"
    )
    #expect(
        ScanCopilotValidator.violations(
            draft: draft, context: context
        ).contains(.staleContext)
    )
}

@Test
func validatorRejectsNoActionOverBlockingDiagnostics() {
    let context = scanningContext(
        diagnostics: [
            copilotDiagnostic(0, severity: .error)
        ]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "no_action",
        templateID: "scan_on_track",
        priorityID: "low"
    )
    #expect(
        ScanCopilotValidator.violations(
            draft: draft, context: context
        ).contains(.actionNotSupported)
    )
}

@Test
func validatorAcceptsConformingDraft() {
    let context = scanningContext(
        weakRegions: 2,
        candidateTargetIDs: ["r0", "r1"],
        diagnostics: [
            copilotDiagnostic(0, code: "coverage_weak_region")
        ]
    )
    let draft = ScanCopilotModelDraft(
        actionID: "move_to_gap",
        templateID: "revisit_area",
        priorityID: "normal",
        targetID: "r1",
        reasonCodes: ["weak_region"],
        sourceDiagnosticIDs: ["d0"],
        contextDigest: context.contextDigest
    )
    let (suggestion, violations) = ScanCopilotValidator.validate(
        draft: draft,
        context: context
    )
    #expect(violations.isEmpty)
    #expect(suggestion?.action == .moveToGap)
    #expect(suggestion?.template == .revisitArea)
    #expect(suggestion?.targetID == "r1")
    #expect(suggestion?.contextDigest == context.contextDigest)
}

// MARK: - Engine: availability-gated fallback

private struct ScriptedCopilot: ScanCopilotModelProducing {
    let outcome: ScanCopilotModelOutcome

    func suggest(
        context: ScanCopilotContext
    ) async -> ScanCopilotModelOutcome {
        outcome
    }
}

@Test
func engineWithoutModelIsDeterministic() async {
    let context = scanningContext(weakRegions: 2)
    let engine = ScanCopilotEngine(model: nil)
    let resolution = await engine.resolve(context: context)
    #expect(resolution.source == .deterministicBaseline)
    #expect(
        resolution.suggestion
            == ScanCopilotBaseline.suggest(context: context)
    )
    #expect(resolution.provenance == nil)
}

@Test
func engineFallsBackWhenModelUnavailable() async {
    let context = scanningContext(weakRegions: 2)
    let engine = ScanCopilotEngine(
        model: ScriptedCopilot(
            outcome: ScanCopilotModelOutcome(
                draft: nil,
                failure: .modelUnavailable,
                provenance: nil
            )
        )
    )
    let resolution = await engine.resolve(context: context)
    #expect(resolution.source == .modelUnavailableFallback)
    #expect(resolution.modelFailure == .modelUnavailable)
    #expect(
        resolution.suggestion
            == ScanCopilotBaseline.suggest(context: context)
    )
}

@Test
func engineFallsBackWhenModelDraftRejected() async {
    let context = scanningContext(
        movementCapability: .stationaryOnly,
        weakRegions: 2
    )
    // Model asks for movement while the deterministic policy
    // forbids translation — validator must reject and the engine
    // must surface the deterministic baseline instead.
    let engine = ScanCopilotEngine(
        model: ScriptedCopilot(
            outcome: ScanCopilotModelOutcome(
                draft: ScanCopilotModelDraft(
                    actionID: "move_to_gap",
                    templateID: "move_closer",
                    priorityID: "high"
                ),
                failure: nil,
                provenance: nil
            )
        )
    )
    let resolution = await engine.resolve(context: context)
    #expect(resolution.source == .modelRejectedFallback)
    #expect(
        resolution.validatorViolations.contains(.movementNotQualified)
    )
    // Baseline never suggests movement under constraints either.
    #expect(!resolution.suggestion.action.requiresMovementQualification)
}

@Test
func engineSurfacesValidatedModelPick() async {
    let context = scanningContext(weakRegions: 2)
    let provenance = ScanCopilotModelProvenance(
        modelVariantDisplayName: "core3",
        osVersion: "Version 27.0",
        localeIdentifier: "en_US",
        contextSizeLimit: 4096,
        inputTokenCount: 240,
        outputTokenCount: 30,
        promptRevision: scanCopilotPromptRevision
    )
    let engine = ScanCopilotEngine(
        model: ScriptedCopilot(
            outcome: ScanCopilotModelOutcome(
                draft: ScanCopilotModelDraft(
                    actionID: "move_to_gap",
                    templateID: "revisit_area",
                    priorityID: "normal",
                    reasonCodes: ["weak_region"]
                ),
                failure: nil,
                provenance: provenance
            )
        )
    )
    let resolution = await engine.resolve(context: context)
    #expect(resolution.source == .modelValidated)
    #expect(resolution.suggestion.action == .moveToGap)
    #expect(resolution.provenance == provenance)
}

// MARK: - Baseline

@Test
func baselineNeverSuggestsMovementUnderConstraints() {
    for capability in [
        ScanMovementCapability.stationaryOnly,
        .safetyConstrained,
    ] {
        let context = ScanCopilotContext(
            stage: .scanning,
            trackingState: .normal,
            directionCoverageFraction: 0.4,
            movementCapability: capability,
            weakRegionKeys: ["r0"],
            actionableWeakRegionCount: 3,
            candidateTargetIDs: ["r0"]
        )
        let suggestion = ScanCopilotBaseline.suggest(context: context)
        #expect(
            !suggestion.action.requiresMovementQualification
        )
        #expect(
            ScanCopilotValidator.violations(
                draft: ScanCopilotModelDraft(
                    actionID: suggestion.action.rawValue,
                    templateID: suggestion.template.rawValue,
                    priorityID: suggestion.priority.rawValue,
                    targetID: suggestion.targetID,
                    reasonCodes: suggestion.reasonCodes
                        .map(\.rawValue),
                    sourceDiagnosticIDs: suggestion
                        .sourceDiagnosticIDs,
                    contextDigest: context.contextDigest
                ),
                context: context
            ).isEmpty
        )
    }
}

@Test
func baselinePassesValidatorAcrossStates() {
    // The deterministic arm must always produce a suggestion its own
    // validator would accept — otherwise the fallback path could
    // surface something the validator itself rejects.
    let contexts: [ScanCopilotContext] = [
        scanningContext(),
        scanningContext(trackingState: .limited),
        scanningContext(trackingState: .unavailable),
        scanningContext(weakRegions: 4, candidateTargetIDs: ["r0"]),
        scanningContext(
            movementCapability: .stationaryOnly,
            weakRegions: 4
        ),
        ScanCopilotContext(
            stage: .review,
            missingTaskItemCount: 2
        ),
        ScanCopilotContext(
            stage: .review,
            unresolvedRevisitFlagIDs: ["f0"]
        ),
        ScanCopilotContext(
            stage: .scanning,
            resourcePressureKinds: ["thermal_pressure"]
        ),
        ScanCopilotContext(
            stage: .scanning,
            lowLightActive: true
        ),
        ScanCopilotContext(
            stage: .scanning,
            targetScanState: "stalled",
            candidateTargetIDs: ["target0"]
        ),
    ]
    for context in contexts {
        let suggestion = ScanCopilotBaseline.suggest(context: context)
        let draft = ScanCopilotModelDraft(
            actionID: suggestion.action.rawValue,
            templateID: suggestion.template.rawValue,
            priorityID: suggestion.priority.rawValue,
            targetID: suggestion.targetID,
            reasonCodes: suggestion.reasonCodes.map(\.rawValue),
            sourceDiagnosticIDs: suggestion.sourceDiagnosticIDs,
            contextDigest: context.contextDigest
        )
        #expect(
            ScanCopilotValidator.violations(
                draft: draft, context: context
            ).isEmpty,
            "baseline suggestion rejected in context \(context)"
        )
    }
}

@Test
func baselinePrioritizesTrackingThenResources() {
    let trackingContext = ScanCopilotContext(
        stage: .scanning,
        trackingState: .limited
    )
    #expect(
        ScanCopilotBaseline.suggest(context: trackingContext).action
            == .waitForTracking
    )
    let pressureContext = ScanCopilotContext(
        stage: .scanning,
        trackingState: .normal,
        resourcePressureKinds: ["thermal_pressure"]
    )
    #expect(
        ScanCopilotBaseline.suggest(context: pressureContext).action
            == .reduceWorkload
    )
}
