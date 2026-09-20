import Foundation
import XCTest
@testable import HTDTCaptureCore

final class RoomPlanArtifactLineageTests: XCTestCase {
    func testRawEvidenceExistsIndependentlyOfPostprocessing() throws {
        let rawBytes = Data(#"{"raw":"roomplan"}"#.utf8)
        let sessionID = CaptureSessionID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000003"
            )!
        )
        let coordinateID = CoordinateSpaceID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000004"
            )!
        )
        let runtime = CaptureRuntimeProvenance(
            osVersion: "test-os",
            appVersion: "0.1.0",
            appBuild: "test"
        )

        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: rawBytes,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: runtime
        )

        XCTAssertEqual(
            raw.descriptor.relativePath,
            "roomplan/captured-room-data.json"
        )
        XCTAssertEqual(raw.descriptor.byteCount, rawBytes.count)
        XCTAssertEqual(
            raw.descriptor.sha256,
            EvidenceIntegrity.sha256(of: rawBytes)
        )
        XCTAssertEqual(raw.descriptor.captureSessionID, sessionID)
        XCTAssertEqual(raw.descriptor.coordinateSpaceID, coordinateID)
    }

    func testProcessedEvidenceIsHashBoundToExactRawEvidence() throws {
        let rawBytes = Data(#"{"raw":"roomplan"}"#.utf8)
        let processedBytes = Data(#"{"processed":"room"}"#.utf8)
        let runtime = CaptureRuntimeProvenance(
            osVersion: "test-os",
            appVersion: "0.1.0",
            appBuild: "test"
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: rawBytes,
            captureSessionID: CaptureSessionID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000003"
                )!
            ),
            coordinateSpaceID: CoordinateSpaceID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000004"
                )!
            ),
            runtime: runtime
        )

        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: processedBytes,
            to: raw,
            capturedRoomVersion: "test-roomplan"
        )

        let processed = try XCTUnwrap(lineage.processed)
        XCTAssertEqual(
            processed.descriptor.relativePath,
            "roomplan/captured-room.json"
        )
        XCTAssertEqual(
            processed.descriptor.sourceRawSHA256,
            raw.descriptor.sha256
        )
        XCTAssertEqual(
            processed.descriptor.sha256,
            EvidenceIntegrity.sha256(of: processedBytes)
        )
        XCTAssertEqual(
            processed.descriptor.captureSessionID,
            raw.descriptor.captureSessionID
        )
        XCTAssertEqual(
            processed.descriptor.coordinateSpaceID,
            raw.descriptor.coordinateSpaceID
        )
    }
}
