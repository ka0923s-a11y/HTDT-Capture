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
    let legacy = CaptureQualityRequirements()
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
            == ["1.1.0"]
    )
}
