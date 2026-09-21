import Foundation
import Testing
@testable import HTDTCaptureCore

private struct LifecycleVectorDocument: Decodable {
    struct Vector: Decodable {
        let name: String
        let createdAt: String
        let finalizedAt: String
        let valid: Bool

        private enum CodingKeys: String, CodingKey {
            case name
            case createdAt = "created_at"
            case finalizedAt = "finalized_at"
            case valid
        }
    }

    let vectors: [Vector]
}

private func lifecycleVectorDocument() throws -> LifecycleVectorDocument {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let vectorURL = repoRoot
        .appendingPathComponent("schemas")
        .appendingPathComponent("capture-bundle-v1")
        .appendingPathComponent(
            "manifest-lifecycle-vectors.json"
        )
    return try JSONDecoder().decode(
        LifecycleVectorDocument.self,
        from: Data(contentsOf: vectorURL)
    )
}

private func lifecycleManifest(
    createdAt: String,
    finalizedAt: String
) throws -> BundleManifest {
    try BundleManifest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        parentRevisionID: nil,
        captureSessionIDs: [CaptureSessionID()],
        coordinateSpaceIDs: [CoordinateSpaceID()],
        createdAtUTC: createdAt,
        finalizedAtUTC: finalizedAt,
        app: BundleAppIdentity(
            version: "test",
            build: "test"
        ),
        files: []
    )
}

@Test
func manifestLifecycleOrderingMatchesSharedVectors() throws {
    let document = try lifecycleVectorDocument()
    #expect(!document.vectors.isEmpty)

    for vector in document.vectors {
        if vector.valid {
            _ = try lifecycleManifest(
                createdAt: vector.createdAt,
                finalizedAt: vector.finalizedAt
            )
        } else {
            #expect(throws: BundleManifestError.self) {
                _ = try lifecycleManifest(
                    createdAt: vector.createdAt,
                    finalizedAt: vector.finalizedAt
                )
            }
        }
    }
}

@Test
func manifestRejectsFinalizedBeforeCreated() {
    #expect(
        throws: BundleManifestError.finalizedBeforeCreated(
            "2026-09-20T00:00:01Z",
            "2026-09-20T00:00:00Z"
        )
    ) {
        _ = try lifecycleManifest(
            createdAt: "2026-09-20T00:00:01Z",
            finalizedAt: "2026-09-20T00:00:00Z"
        )
    }
}

@Test
func manifestAcceptsEqualLifecycleInstants() throws {
    _ = try lifecycleManifest(
        createdAt: "2026-09-20T00:00:00Z",
        finalizedAt: "2026-09-20T00:00:00Z"
    )
    // Whole-second and fractional-zero strings differ but denote the
    // same instant; ordering must compare instants, not raw text.
    _ = try lifecycleManifest(
        createdAt: "2026-09-20T00:00:00Z",
        finalizedAt: "2026-09-20T00:00:00.000Z"
    )
}

@Test
func decodedManifestRejectsReversedLifecycle() {
    let json = """
        {
          "schema": "htdt.capture.bundle",
          "schema_version": "1.0.0",
          "capture_series_id": "00000000-0000-4000-8000-000000000001",
          "capture_revision_id": "00000000-0000-4000-8000-000000000002",
          "parent_revision_id": null,
          "capture_session_ids": [
            "00000000-0000-4000-8000-000000000003"
          ],
          "coordinate_space_ids": [
            "00000000-0000-4000-8000-000000000004"
          ],
          "created_at": "2026-09-20T00:00:01Z",
          "finalized_at": "2026-09-20T00:00:00Z",
          "app": {
            "name": "HTDT-Capture",
            "version": "test",
            "build": "test"
          },
          "files": []
        }
        """
    #expect(throws: BundleManifestError.self) {
        _ = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(json.utf8)
        )
    }
}
