import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #277: the bounded camera-source preflight must be advisory
/// only — never surface an advisory without a stable frame, never
/// invent a smudge reading, and gate Stage-B low-light on the
/// evaluation-enabled policy flag.
final class CameraSourcePreflightAssessmentTests: XCTestCase {
    private let policy = CameraSourcePreflightPolicy()

    func test_noStableFrame_neverAdvises() {
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: false,
            smudgeConfidence: 0.99,
            ambientIntensityLumens: 10,
            sampledTimestampSeconds: nil,
            visionRequestRevision: nil
        )
        XCTAssertNil(
            CameraSourcePreflightAssessment.assess(
                outcome: outcome,
                policy: policy
            )
        )
    }

    func test_smudgeAboveThreshold_advises() {
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: 0.7,
            ambientIntensityLumens: nil,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: "detect_lens_smudge_request"
        )
        let advisory = CameraSourcePreflightAssessment.assess(
            outcome: outcome,
            policy: policy
        )
        XCTAssertEqual(advisory?.smudgeSuspected, true)
        XCTAssertEqual(advisory?.smudgeConfidence, 0.7)
        XCTAssertEqual(advisory?.lowLightSuspected, false)
    }

    func test_smudgeBelowThreshold_noAdvisory() {
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: 0.2,
            ambientIntensityLumens: 500,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: nil
        )
        XCTAssertNil(
            CameraSourcePreflightAssessment.assess(
                outcome: outcome,
                policy: policy
            )
        )
    }

    func test_missingSmudgeReading_noSmudgeAdvisory() {
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: nil,
            ambientIntensityLumens: 500,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: nil
        )
        XCTAssertNil(
            CameraSourcePreflightAssessment.assess(
                outcome: outcome,
                policy: policy
            )
        )
    }

    func test_lowLight_stageB_disabledByDefault() {
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: 0.1,
            ambientIntensityLumens: 5,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: nil
        )
        // Default policy keeps the experimental low-light lane off —
        // a dark scene alone never produces an advisory.
        XCTAssertNil(
            CameraSourcePreflightAssessment.assess(
                outcome: outcome,
                policy: policy
            )
        )
    }

    func test_lowLight_stageB_enabled_advises() {
        var enabled = CameraSourcePreflightPolicy()
        enabled = CameraSourcePreflightPolicy(
            lowLightAdvisoryEnabled: true
        )
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: 0.1,
            ambientIntensityLumens: 5,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: nil
        )
        let advisory = CameraSourcePreflightAssessment.assess(
            outcome: outcome,
            policy: enabled
        )
        XCTAssertEqual(advisory?.lowLightSuspected, true)
        XCTAssertEqual(advisory?.smudgeSuspected, false)
        XCTAssertEqual(advisory?.ambientIntensityLumens, 5)
    }

    func test_combinedFindings_shareOneCard() {
        let enabled = CameraSourcePreflightPolicy(
            lowLightAdvisoryEnabled: true
        )
        let outcome = CameraSourcePreflightOutcome(
            stableFrameAcquired: true,
            smudgeConfidence: 0.9,
            ambientIntensityLumens: 5,
            sampledTimestampSeconds: 1.25,
            visionRequestRevision: nil
        )
        let advisory = CameraSourcePreflightAssessment.assess(
            outcome: outcome,
            policy: enabled
        )
        XCTAssertEqual(advisory?.smudgeSuspected, true)
        XCTAssertEqual(advisory?.lowLightSuspected, true)
    }

    func test_preflightNoteKind_encodesWireName() throws {
        let note = CaptureAdvisoryNote(
            kind: .sourceQualityPreflight,
            sessionTimestampSeconds: 2.5,
            detail: "policy_rev=v1 smudge_confidence=0.800"
        )
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder()
            .decode(CaptureAdvisoryNote.self, from: data)
        XCTAssertEqual(decoded.kind, .sourceQualityPreflight)
        XCTAssertEqual(
            decoded.qualityDiagnostic.code,
            "source_quality_preflight"
        )
        XCTAssertEqual(
            decoded.qualityDiagnostic.severity,
            .info
        )
    }
}
