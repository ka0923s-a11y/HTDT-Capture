import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#389: the Support & Diagnostics package — a bounded,
/// privacy-reviewed export independent of any capture bundle. Covers
/// the correlation tag, payload shape, privacy preview, health
/// summary, endpoint verdict mapping, and the forbidden-content
/// scan.
final class SupportDiagnosticsTests: XCTestCase {
    private let environment = SupportDiagnosticsEnvironment(
        appName: "HTDT Capture",
        appVersion: "1.4.2",
        appBuild: "r1234",
        deviceModelFamily: "iPad",
        osFamilyAndVersion: "iPadOS 18.2",
        emittedSchemaIDs: ["htdt.capture.bundle"]
    )
    private let capabilities = DiagnosticsCapabilitySummary(
        roomPlanEligible: true,
        sceneReconstructionEligible: true,
        lidarDepthAvailable: true,
        smoothedDepthAvailable: false,
        meshAnchoringAvailable: true
    )

    func testCorrelationIDFormatAndRoundTrip() throws {
        let id = DiagnosticsCorrelationID()
        XCTAssertEqual(id.code.count, 4)
        XCTAssertTrue(
            id.code.allSatisfy {
                $0.isHexDigit && $0.uppercased() == String($0)
            }
        )
        XCTAssertEqual(id.displayTag, "[diag \(id.code)]")
        XCTAssertThrowsError(
            try DiagnosticsCorrelationID(code: "zz")
        ) { error in
            XCTAssertEqual(
                error as? SupportDiagnosticsError,
                .invalidCorrelationID("zz")
            )
        }
        XCTAssertNoThrow(
            try DiagnosticsCorrelationID(code: "A1F0")
        )
    }

    func testCollectProducesJsonAndTextWithCorrelationTag() throws {
        let package = try SupportDiagnosticsCollector.collect(
            environment: environment,
            capabilities: capabilities,
            resourceEvents: [],
            storagePreflightVerdict: .sufficient,
            persistedCaptureCount: 3,
            quarantinedArtifactCount: 1,
            orphanedWorkingArtifactCount: 2,
            lastValidationFailureClass: "disk_full",
            endpointVerdict: nil,
            endpointCheckedAtUTC: nil,
            correlationID: try DiagnosticsCorrelationID(
                code: "BEEF"
            )
        )
        XCTAssertEqual(
            package.correlationID.displayTag, "[diag BEEF]"
        )
        XCTAssertEqual(
            package.jsonFilename,
            "support-diagnostics-BEEF.json"
        )
        XCTAssertEqual(
            package.textFilename,
            "support-diagnostics-BEEF.txt"
        )
        XCTAssertFalse(package.jsonPayload.isEmpty)
        XCTAssertFalse(package.textPayload.isEmpty)
        let report = try JSONDecoder().decode(
            SupportDiagnosticsReport.self,
            from: package.jsonPayload
        )
        XCTAssertEqual(report.appVersion, "1.4.2")
        XCTAssertEqual(report.captureHealth.persistedCaptureCount, 3)
        XCTAssertEqual(
            report.endpointReachability.verdictClass,
            "not_checked"
        )
        XCTAssertNil(
            report.endpointReachability.lastCheckedAtUTC
        )
    }

    func testPrivacyPreviewEnumeratesEveryCategory() throws {
        let package = try SupportDiagnosticsCollector.collect(
            environment: environment,
            capabilities: capabilities,
            resourceEvents: [],
            storagePreflightVerdict: .unknown,
            persistedCaptureCount: 0,
            quarantinedArtifactCount: 0,
            orphanedWorkingArtifactCount: 0,
            lastValidationFailureClass: nil,
            endpointVerdict: nil,
            endpointCheckedAtUTC: nil
        )
        XCTAssertEqual(
            package.privacyPreview.map(\.category),
            SupportDiagnosticsPrivacyCategory.allCases
        )
        XCTAssertTrue(
            package.privacyPreview.allSatisfy(\.included)
        )
        for row in package.privacyPreview {
            XCTAssertFalse(row.contentsSummary.isEmpty)
        }
    }

    func testResourceSummaryCountsNeverDetails() throws {
        let events = [
            CaptureResourceEvent(
                kind: .storagePressure,
                severity: .warning,
                detail: "free_bytes=100"
            ),
            CaptureResourceEvent(
                kind: .thermalPressure,
                severity: .error,
                detail: "state=serious"
            ),
            CaptureResourceEvent(
                kind: .thermalPressure,
                severity: .info,
                detail: "state=nominal"
            ),
        ]
        let summary = SupportDiagnosticsCollector.resourceSummary(
            events: events
        )
        XCTAssertEqual(summary.totalEvents, 3)
        XCTAssertEqual(
            summary.byKind["storage_pressure"], 1
        )
        XCTAssertEqual(
            summary.byKind["thermal_pressure"], 2
        )
        XCTAssertEqual(summary.thermalPressureStops, 1)
        // Counts only — event detail text (which can name user
        // content) is never summarized into the report.
    }

    func testEndpointReachabilityVerdictClasses() {
        XCTAssertEqual(
            SupportDiagnosticsCollector.endpointReachability(
                verdict: nil, checkedAtUTC: nil
            ).verdictClass,
            "not_checked"
        )
        XCTAssertEqual(
            SupportDiagnosticsCollector.endpointReachability(
                verdict: .compatible, checkedAtUTC: "t"
            ).verdictClass,
            "compatible"
        )
        XCTAssertEqual(
            SupportDiagnosticsCollector.endpointReachability(
                verdict: .compatibleWithOmissions([]),
                checkedAtUTC: "t"
            ).verdictClass,
            "compatible_with_omissions"
        )
        XCTAssertEqual(
            SupportDiagnosticsCollector.endpointReachability(
                verdict: .incompatible([]), checkedAtUTC: "t"
            ).verdictClass,
            "incompatible"
        )
        XCTAssertEqual(
            SupportDiagnosticsCollector.endpointReachability(
                verdict: .unknown(reason: "offline"),
                checkedAtUTC: "t"
            ).verdictClass,
            "unreachable"
        )
    }

    func testForbiddenContentScanRejectsCapturePaths() {
        // A report that leaks capture-tree paths, digest keys, or
        // credential-shaped keys is refused before export — no
        // partial package leaves the device.
        let forbidden: [String] = [
            #"{"path": "evidence/frames/abc.json"}"#,
            #"{"sha256": "deadbeef"}"#,
            #"{"serial_number": "X123"}"#,
            #"{"password": "hunter2"}"#,
            #"{"token": "tok_123"}"#,
            #"{"root": "/Users/name/Library"}"#,
        ]
        for payload in forbidden {
            XCTAssertThrowsError(
                try SupportDiagnosticsCollector
                    .forbiddenContentScan(
                        Data(payload.utf8)
                    ),
                "expected rejection: \(payload)"
            ) { error in
                guard case .privacyReviewFailed =
                    error as? SupportDiagnosticsError
                else {
                    return XCTFail("expected privacyReviewFailed")
                }
            }
        }
        XCTAssertNoThrow(
            try SupportDiagnosticsCollector
                .forbiddenContentScan(
                    Data(#"{"app_version":"1.0.0"}"#.utf8)
                )
        )
    }

    func testCollectRejectsSerialInEnvironment() {
        // The environment block flows through the same forbidden
        // scan — a serial-shaped key or capture path anywhere in the
        // JSON trips the review.
        XCTAssertThrowsError(
            try SupportDiagnosticsCollector.collect(
                environment: SupportDiagnosticsEnvironment(
                    appName: "HTDT Capture",
                    appVersion: "1.0",
                    appBuild: "0",
                    deviceModelFamily: "iPad",
                    osFamilyAndVersion: "iPadOS 18",
                    emittedSchemaIDs: [
                        "evidence/frames/x.json"
                    ]
                ),
                capabilities: capabilities,
                resourceEvents: [],
                storagePreflightVerdict: .unknown,
                persistedCaptureCount: 0,
                quarantinedArtifactCount: 0,
                orphanedWorkingArtifactCount: 0,
                lastValidationFailureClass: nil,
                endpointVerdict: nil,
                endpointCheckedAtUTC: nil
            )
        ) { error in
            guard case .privacyReviewFailed =
                error as? SupportDiagnosticsError
            else {
                return XCTFail("expected privacyReviewFailed")
            }
        }
    }
}
