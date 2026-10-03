import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func publishedRulesetBindsToOneCanonicalRequirementSet() throws {
    let canonical = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    #expect(canonical.rulesetVersion == "1.1.0")
    #expect(canonical.requireCompletedRoomPlan)
    #expect(canonical.minimumActiveMeshAnchors == 1)
    #expect(canonical.allowDepthEvidenceAsMeshFallback)
    #expect(canonical.minimumEvidenceFrames == 1)
    #expect(!canonical.requireDepthEvidence)
    #expect(canonical.requiredAnnotationKeys.isEmpty)
    #expect(canonical.requiredMeasurementQuantityTypes.isEmpty)
    #expect(canonical.requireIntegrityPass)

    // Every lookup of the same published identity returns the same
    // requirement set.
    #expect(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
            == canonical
    )
}

@Test
func publishedRulesetCannotCarryArbitraryThresholds() throws {
    let canonical = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    // Constructing requirements under a published version pins every
    // gate parameter to the registry entry; caller-supplied thresholds
    // cannot diverge while claiming "1.1.0".
    let attempted = CaptureQualityRequirements(
        rulesetVersion: "1.1.0",
        requireCompletedRoomPlan: false,
        minimumActiveMeshAnchors: 99,
        allowDepthEvidenceAsMeshFallback: false,
        minimumEvidenceFrames: 42,
        requireDepthEvidence: true,
        requiredAnnotationKeys: ["speaker:L"],
        requiredMeasurementQuantityTypes: ["room_width"],
        requireIntegrityPass: false
    )
    #expect(attempted == canonical)
    #expect(attempted.minimumActiveMeshAnchors == 1)
    #expect(attempted.allowDepthEvidenceAsMeshFallback)
    #expect(attempted.requireIntegrityPass)
}

@Test
func unpublishedRulesetKeepsExplicitParameters() {
    #expect(
        CaptureQualityRequirements.forRuleset(version: "9.9.9-exp")
            == nil
    )
    let experimental = CaptureQualityRequirements(
        rulesetVersion: "9.9.9-exp",
        requireCompletedRoomPlan: false,
        minimumActiveMeshAnchors: 42,
        minimumEvidenceFrames: 0,
        requireIntegrityPass: false
    )
    #expect(experimental.rulesetVersion == "9.9.9-exp")
    #expect(experimental.minimumActiveMeshAnchors == 42)
    #expect(!experimental.requireCompletedRoomPlan)
    #expect(!experimental.requireIntegrityPass)

    // The default unversioned-style ruleset is unchanged.
    let legacy = CaptureQualityRequirements(
        rulesetVersion: "1.0.0")
    #expect(legacy.rulesetVersion == "1.0.0")
    #expect(legacy.minimumActiveMeshAnchors == 1)
    #expect(!legacy.allowDepthEvidenceAsMeshFallback)
}

@Test
func persistedRulesetIdentityRemainsInterpretable() throws {
    // A bundle persisting ruleset_version "1.1.0" resolves to the
    // canonical gate semantics through the registry.
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(report.rulesetVersion == "1.1.0")
    // 1.1.0 allows the bounded depth fallback, so this is ready.
    #expect(report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "mesh_depth_fallback"
        }
    )
}

@Test
func publishedRulesetVersionsAreEnumeratedDeterministically() {
    #expect(
        CaptureQualityRequirements.publishedRulesetVersions
            == ["1.0.0", "1.1.0", "1.2.0"]
    )
}

@Test
func ruleset12AddsVersionedPoliciesWithoutRedefining11() throws {
    let ruleset11 = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    let ruleset12 = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    // 1.1.0 keeps the binary ever-unavailable rule and the non-empty
    // depth fallback; the new policies exist only under 1.2.0 (legacy bolph71656-ai/HTDT-Capture#242,
    // legacy bolph71656-ai/HTDT-Capture#284).
    #expect(ruleset11.trackingRecoveryPolicy == nil)
    #expect(ruleset11.depthFallbackSufficiencyPolicy == nil)
    #expect(ruleset12.trackingRecoveryPolicy != nil)
    #expect(ruleset12.depthFallbackSufficiencyPolicy != nil)
    #expect(
        ruleset12.minimumActiveMeshAnchors
            == ruleset11.minimumActiveMeshAnchors
    )
    #expect(
        ruleset12.allowDepthEvidenceAsMeshFallback
            == ruleset11.allowDepthEvidenceAsMeshFallback
    )
}

@Test
func unrecoveredTrackingUnavailableStaysAnError() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 0,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 10,
                    state: .unavailable
                ),
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_unrecovered"
        }
    )
}

@Test
func recoveredTrackingUnavailableBecomesWarning() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 0,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 5,
                    state: .unavailable
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 12,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 40,
                    state: .normal
                ),
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_recovered"
                && $0.severity == .warning
        }
    )
    #expect(
        !report.diagnostics.contains {
            $0.code.hasPrefix("tracking_unavailable")
                && $0.severity == .error
        }
    )
}

@Test
func trackingUnavailableStillRecoveringFailsClosed() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 0,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 10,
                    state: .unavailable
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 15,
                    state: .normal
                ),
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    // 5s of stable normal < the 10s minimum — recovery not yet proven.
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_recovering"
        }
    )
}

@Test
func extendedRecoveredTrackingUnavailableStaysAnError() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 0,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 5,
                    state: .unavailable
                ),
                // Compacted intervals keep first/last samples, so the
                // span end is a second unavailable event.
                TrackingQualityEvent(
                    sessionTimestampSeconds: 90,
                    state: .unavailable
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 95,
                    state: .normal
                ),
                TrackingQualityEvent(
                    sessionTimestampSeconds: 130,
                    state: .normal
                ),
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    // 85s unavailable > the 20s recoverable ceiling.
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_extended"
        }
    )
}

@Test
func coordinateDiscontinuityAlwaysFails() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 0,
                    state: .normal
                )
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            coordinateDiscontinuityCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_coordinate_discontinuity"
        }
    )
}

@Test
func ruleset11KeepsBinaryTrackingUnavailableRule() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    let events: [TrackingQualityEvent] = [
        TrackingQualityEvent(
            sessionTimestampSeconds: 0,
            state: .normal
        ),
        TrackingQualityEvent(
            sessionTimestampSeconds: 5,
            state: .unavailable
        ),
        TrackingQualityEvent(
            sessionTimestampSeconds: 12,
            state: .normal
        ),
        TrackingQualityEvent(
            sessionTimestampSeconds: 40,
            state: .normal
        ),
    ]
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: events,
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    // Legacy 1.1.0 semantics preserved: any unavailable event is an
    // error even when tracking recovered (legacy bolph71656-ai/HTDT-Capture#242 versioning rule).
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_observed"
                && $0.severity == .error
        }
    )
    #expect(
        !report.diagnostics.contains {
            $0.code == "tracking_unavailable_recovered"
        }
    )
}

@Test
func depthFallbackRequiresSufficiencyUnder12() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    // Depth fallback allowed, but only a one-pixel payload was
    // retained — under 1.2.0 the sufficiency policy fails closed.
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            depthSufficiency: DepthEvidenceSufficiency(
                framesAnalyzed: 1,
                framesWithUsableSamples: 1,
                totalSamples: 10_000,
                validSamples: 1,
                validFraction: 0.0001,
                bestFrameValidFraction: 0.0001,
                bestFrameSpatialCoverageFraction: 0.0625,
                unionSpatialCoverageFraction: 0.0625,
                minDepthMeters: 1.0,
                maxDepthMeters: 1.0,
                lowConfidenceValidSamples: 0,
                confidenceUnobservedValidSamples: 0,
                confidentValidSamples: 1,
                confidentFraction: 1.0
            ),
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "depth_fallback_insufficient"
                && $0.severity == .error
        }
    )
    #expect(
        !report.diagnostics.contains {
            $0.code == "mesh_depth_fallback"
        }
    )
}

@Test
func depthFallbackSufficiencySatisfiesGate() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.2.0")
    )
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            depthSufficiency: DepthEvidenceSufficiency(
                framesAnalyzed: 2,
                framesWithUsableSamples: 2,
                totalSamples: 80_000,
                validSamples: 40_000,
                validFraction: 0.5,
                bestFrameValidFraction: 0.5,
                bestFrameSpatialCoverageFraction: 0.8,
                unionSpatialCoverageFraction: 0.9,
                minDepthMeters: 0.5,
                maxDepthMeters: 4.0,
                lowConfidenceValidSamples: 2_000,
                confidenceUnobservedValidSamples: 0,
                confidentValidSamples: 36_000,
                confidentFraction: 0.9
            ),
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "mesh_depth_fallback"
                && $0.severity == .info
        }
    )
}

@Test
func ruleset11DepthFallbackStillAcceptsOnePixel() throws {
    let requirements = try #require(
        CaptureQualityRequirements.forRuleset(version: "1.1.0")
    )
    // Legacy semantics preserved for 1.1.0 reports already persisted:
    // usableDepthSampleCount > 0 satisfies the fallback (legacy bolph71656-ai/HTDT-Capture#284).
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            depthSufficiency: nil,
            integrityStatus: .pass
        ),
        requirements: requirements
    )
    #expect(report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "mesh_depth_fallback"
        }
    )
}
