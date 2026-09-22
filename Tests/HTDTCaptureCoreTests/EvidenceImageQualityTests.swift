import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Evidence image quality preflight (#407): the shared advisory
/// assessment contract and the deterministic still-image checks.
final class EvidenceImageQualityTests: XCTestCase {
    private let stamp = "2026-03-01T12:00:00Z"
    private let evaluator = EvidenceImageQualityEvaluator()

    private func base(
        mean: Double = 0.5,
        clipped: Double = 0.01,
        dark: Double = 0.05,
        gradient: Double = 0.02,
        exposure: Double? = nil
    ) -> FrameUsabilityMetrics {
        FrameUsabilityMetrics(
            meanLuminance: mean,
            clippedFraction: clipped,
            darkFraction: dark,
            gradientEnergy: gradient,
            exposureSeconds: exposure
        )
    }

    private func assess(
        base: FrameUsabilityMetrics? = nil,
        task: EvidenceImageTaskMetrics? = nil,
        profile: EvidenceImageQualityProfile = .equipmentLabel
    ) throws -> EvidenceImageQualityAssessment {
        try evaluator.assess(
            base: base ?? self.base(),
            task: task,
            profile: profile,
            evidenceRef: "path:evidence/frames/f1.png",
            createdAtUTC: stamp
        )
    }

    // MARK: - #407 domain verdicts

    func testCleanImageIsUsable() throws {
        let assessment = try assess(
            task: EvidenceImageTaskMetrics(
                subjectRegionFraction: 0.2,
                subjectGlareFraction: 0.01,
                subjectTouchesFrameEdge: false,
                textLegibility: 0.9,
                barcodeDetected: true
            )
        )
        XCTAssertEqual(assessment.status, .usable)
        XCTAssertEqual(assessment.sharpness, .pass)
        XCTAssertEqual(assessment.exposure, .pass)
        XCTAssertEqual(assessment.glare, .pass)
        XCTAssertEqual(assessment.framing, .pass)
        XCTAssertEqual(assessment.legibility, .pass)
        XCTAssertTrue(assessment.reasons.isEmpty)
        XCTAssertEqual(
            assessment.authorityClass,
            .captureDerivedDiagnostic
        )
        XCTAssertEqual(
            assessment.algorithmVersion,
            EvidenceImageQualityEvaluator.algorithmVersion
        )
    }

    func testBlurAndExposureWarnings() throws {
        let blurry = try assess(
            base: base(gradient: 0.001)
        )
        XCTAssertEqual(blurry.sharpness, .warning)
        XCTAssertEqual(blurry.status, .suspect)
        XCTAssertTrue(blurry.reasons.contains(.blurSuspected))

        let dark = try assess(base: base(mean: 0.02, dark: 0.85))
        XCTAssertEqual(dark.exposure, .warning)
        XCTAssertTrue(dark.reasons.contains(.imageTooDark))

        let clipped = try assess(base: base(clipped: 0.8))
        XCTAssertEqual(clipped.exposure, .warning)
        XCTAssertTrue(
            clipped.reasons.contains(.imageOverexposed)
        )
    }

    func testGlareAndFramingWarnings() throws {
        let glared = try assess(
            task: EvidenceImageTaskMetrics(
                subjectRegionFraction: 0.2,
                subjectGlareFraction: 0.4
            )
        )
        XCTAssertEqual(glared.glare, .warning)
        XCTAssertTrue(glared.reasons.contains(.glareOverSubject))
        XCTAssertEqual(glared.status, .suspect)

        let tiny = try assess(
            task: EvidenceImageTaskMetrics(
                subjectRegionFraction: 0.002
            )
        )
        XCTAssertEqual(tiny.framing, .warning)
        XCTAssertTrue(tiny.reasons.contains(.subjectTooSmall))

        let cropped = try assess(
            task: EvidenceImageTaskMetrics(
                subjectRegionFraction: 0.2,
                subjectTouchesFrameEdge: true
            )
        )
        XCTAssertEqual(cropped.framing, .warning)
        XCTAssertTrue(cropped.reasons.contains(.subjectCropped))
    }

    func testLegibilityWarnings() throws {
        let unreadable = try assess(
            task: EvidenceImageTaskMetrics(textLegibility: 0.1)
        )
        XCTAssertEqual(unreadable.legibility, .warning)
        XCTAssertTrue(
            unreadable.reasons.contains(.textUnreadable)
        )

        let noBarcode = try assess(
            task: EvidenceImageTaskMetrics(
                textLegibility: 0.9,
                barcodeDetected: false
            )
        )
        XCTAssertEqual(noBarcode.legibility, .warning)
        XCTAssertTrue(
            noBarcode.reasons.contains(.barcodeUndetected)
        )
    }

    // MARK: - #407 profile scoping and unknown honesty

    func testMissingMetricsNeverPass() throws {
        // Label profile requires legibility: absent signals are
        // reported unknown, never passed (#407 §14).
        let noSignals = try assess()
        XCTAssertEqual(noSignals.legibility, .unknown)
        XCTAssertEqual(noSignals.glare, .unknown)
        XCTAssertEqual(noSignals.framing, .unknown)
        XCTAssertEqual(noSignals.status, .usable)

        // A fully unavailable probe reports unknown + reason.
        let unavailable = try evaluator.assess(
            base: nil,
            task: nil,
            profile: .generalPhoto,
            evidenceRef: "path:evidence/frames/f1.png",
            createdAtUTC: stamp
        )
        XCTAssertEqual(unavailable.status, .unknown)
        XCTAssertEqual(unavailable.sharpness, .unknown)
        XCTAssertEqual(unavailable.exposure, .unknown)
        XCTAssertTrue(
            unavailable.reasons.contains(.assessmentUnavailable)
        )
    }

    func testProfilesScopeEvaluatedDomains() throws {
        // General photo: no subject-legibility requirement.
        let general = try assess(
            profile: .generalPhoto
        )
        XCTAssertNil(general.legibility)
        XCTAssertNil(general.framing)
        XCTAssertNil(general.glare)
        XCTAssertEqual(general.status, .usable)

        // Wiring evidence evaluates legibility only when the task
        // supplied signals.
        let wiring = try assess(profile: .wiringEvidence)
        XCTAssertNil(wiring.legibility)
        let wired = try assess(
            task: EvidenceImageTaskMetrics(textLegibility: 0.2),
            profile: .wiringEvidence
        )
        XCTAssertEqual(wired.legibility, .warning)
    }

    // MARK: - #407/#405 contract and persistence

    func testAssessmentCodableRoundTrip() throws {
        let assessment = try assess(
            task: EvidenceImageTaskMetrics(
                subjectRegionFraction: 0.05,
                textLegibility: 0.9
            )
        )
        let data = try JSONEncoder().encode(assessment)
        let decoded = try JSONDecoder().decode(
            EvidenceImageQualityAssessment.self,
            from: data
        )
        XCTAssertEqual(decoded, assessment)
        XCTAssertEqual(
            decoded.schema,
            EvidenceImageQualityAssessment.expectedSchema
        )
        XCTAssertEqual(
            decoded.assessmentVersion,
            EvidenceImageQualityAssessment
                .expectedAssessmentVersion
        )
    }

    func testScanResultCarriesOptionalImageQuality() throws {
        let quality = try assess()
        let result = EquipmentLabelScanResult(
            algorithm: "vision",
            algorithmVersion: "vision-label-scan-v1",
            evidenceRef: "path:evidence/frames/f1.png",
            candidates: [],
            rawObservations: [],
            imageQuality: quality
        )
        // Distinct from recognition confidence, catalog match and
        // operator confirmation (#407 §8): attached as advisory
        // metadata only.
        XCTAssertEqual(result.imageQuality, quality)
        XCTAssertNil(
            EquipmentLabelScanResult(
                algorithm: "vision",
                algorithmVersion: "vision-label-scan-v1",
                evidenceRef: "path:evidence/frames/f1.png",
                candidates: [],
                rawObservations: []
            ).imageQuality
        )
    }

    // MARK: - #405 cross-product authority classes

    func testAuthorityClassOwnership() {
        XCTAssertEqual(
            CaptureAuthorityClass.allCases.count,
            6
        )
        XCTAssertFalse(
            CaptureAuthorityClass.projectAuthority
                .isCaptureAuthored
        )
        XCTAssertTrue(
            CaptureAuthorityClass.observed.isCaptureAuthored
        )
        XCTAssertEqual(
            CaptureAuthorityClass.projectAuthority
                .canonicalOwnerAfterPromotion,
            "htdt"
        )
        XCTAssertEqual(
            CaptureAuthorityClass.importedReference
                .canonicalOwnerAfterPromotion,
            "htdt"
        )
        XCTAssertEqual(
            CaptureAuthorityClass.fieldReconciliation
                .canonicalOwnerAfterPromotion,
            "capture_field_record"
        )
        XCTAssertEqual(
            CaptureAuthorityClass.captureDerivedDiagnostic
                .canonicalOwnerAfterPromotion,
            "capture_field_record"
        )
        // Wire spellings are stable tokens.
        XCTAssertEqual(
            CaptureAuthorityClass.operatorAttested.rawValue,
            "operator_attested"
        )
        XCTAssertEqual(
            CaptureAuthorityClass.captureDerivedDiagnostic.rawValue,
            "capture_derived_diagnostic"
        )
        XCTAssertEqual(
            CaptureAuthorityClass.fieldReconciliation.rawValue,
            "field_reconciliation"
        )
    }
}
