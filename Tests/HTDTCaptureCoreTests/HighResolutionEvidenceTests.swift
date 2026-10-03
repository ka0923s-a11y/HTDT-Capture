import XCTest
@testable import HTDTCaptureCore

/// #275: bounded high-resolution evidence — the wire contracts that
/// survive into the bundle (purpose enum + advisory kind) are pinned
/// here; the ARKit request surface itself is iOS-only and covered by
/// the lane-B physical evaluation.
final class HighResolutionEvidenceTests: XCTestCase {

    func test_highResolutionStillNote_encodesWireName() throws {
        let note = CaptureAdvisoryNote(
            kind: .highResolutionStill,
            sessionTimestampSeconds: 4.0,
            detail:
                "outcome=captured purpose=review_evidence "
                + "HTDT.evidence.source=high_resolution"
        )
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder()
            .decode(CaptureAdvisoryNote.self, from: data)
        XCTAssertEqual(decoded.kind, .highResolutionStill)
        XCTAssertEqual(
            decoded.qualityDiagnostic.code,
            "high_resolution_still"
        )
        XCTAssertEqual(
            decoded.qualityDiagnostic.severity,
            .info
        )
    }

    func test_highQualityEvidencePurpose_wireNames() throws {
        let cases:
            [HighQualityEvidencePurpose: String] = [
                .equipmentLabel: "equipment_label",
                .targetedObject: "targeted_object",
                .referenceFixture: "reference_fixture",
                .reviewEvidence: "review_evidence",
            ]
        for (purpose, raw) in cases {
            XCTAssertEqual(purpose.rawValue, raw)
            let data = try JSONEncoder().encode(purpose)
            let decoded = try JSONDecoder()
                .decode(HighQualityEvidencePurpose.self, from: data)
            XCTAssertEqual(decoded, purpose)
        }
    }
}
