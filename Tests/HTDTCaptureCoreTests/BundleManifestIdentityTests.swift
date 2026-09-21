import Foundation
import Testing
@testable import HTDTCaptureCore

private struct IdentifierVectorDocument: Decodable {
    struct Vector: Decodable {
        let name: String
        let text: String
        let valid: Bool
    }

    let vectors: [Vector]
}

private struct RevisionVectorDocument: Decodable {
    struct Vector: Decodable {
        let name: String
        let captureRevisionID: String
        let parentRevisionID: String?
        let valid: Bool

        private enum CodingKeys: String, CodingKey {
            case name
            case captureRevisionID = "capture_revision_id"
            case parentRevisionID = "parent_revision_id"
            case valid
        }
    }

    let vectors: [Vector]
}

private struct SourceRefVectorDocument: Decodable {
    struct FileEntry: Decodable {
        let path: String
        let bytes: Int
        let mediaType: String
        let sha256: String
        let producer: String
        let provenanceClass: BundleProvenanceClass
        let role: BundleFileRole
        let sourceRefs: [String]?

        private enum CodingKeys: String, CodingKey {
            case path
            case bytes
            case mediaType = "media_type"
            case sha256
            case producer
            case provenanceClass = "provenance_class"
            case role
            case sourceRefs = "source_refs"
        }
    }

    struct Vector: Decodable {
        let name: String
        let captureSessionIDs: [String]
        let files: [FileEntry]
        let valid: Bool

        private enum CodingKeys: String, CodingKey {
            case name
            case captureSessionIDs = "capture_session_ids"
            case files
            case valid
        }
    }

    let vectors: [Vector]
}

private func identityVectorDocument<T: Decodable>(
    _ name: String,
    as type: T.Type
) throws -> T {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let vectorURL = repoRoot
        .appendingPathComponent("schemas")
        .appendingPathComponent("capture-bundle-v1")
        .appendingPathComponent(name)
    return try JSONDecoder().decode(
        T.self,
        from: Data(contentsOf: vectorURL)
    )
}

private func identityManifest(
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    parentRevisionID: CaptureRevisionID? = nil,
    sessionIDs: [CaptureSessionID] = [CaptureSessionID()],
    files: [BundleFileEntry] = []
) throws -> BundleManifest {
    try BundleManifest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: revisionID,
        parentRevisionID: parentRevisionID,
        captureSessionIDs: sessionIDs,
        coordinateSpaceIDs: [CoordinateSpaceID()],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "test",
            build: "test"
        ),
        files: files
    )
}

private func identityEntry(
    _ path: String,
    sha256: String =
        "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
    mediaType: String = "application/octet-stream",
    producer: String = "test",
    provenanceClass: BundleProvenanceClass = .captureAppDerived,
    role: BundleFileRole = .canonical,
    sourceRefs: [String]? = nil
) throws -> BundleFileEntry {
    try BundleFileEntry(
        path: path,
        bytes: 1,
        mediaType: mediaType,
        sha256: EvidenceSHA256(sha256),
        producer: producer,
        provenanceClass: provenanceClass,
        role: role,
        sourceRefs: sourceRefs
    )
}

private func identityManifestJSON(
    revisionID: String,
    parentRevisionIDJSON: String,
    filesJSON: String = ""
) -> String {
    """
    {
      "schema": "htdt.capture.bundle",
      "schema_version": "1.0.0",
      "capture_series_id": "10000000-0000-4000-8000-000000000001",
      "capture_revision_id": "\(revisionID)",
      "parent_revision_id": \(parentRevisionIDJSON),
      "capture_session_ids": [
        "10000000-0000-4000-8000-000000000002"
      ],
      "coordinate_space_ids": [
        "10000000-0000-4000-8000-000000000003"
      ],
      "created_at": "2026-09-20T00:00:00Z",
      "finalized_at": "2026-09-20T00:01:00Z",
      "app": {
        "name": "HTDT-Capture",
        "version": "test",
        "build": "test"
      },
      "files": [\(filesJSON)]
    }
    """
}

@Test
func captureIdentifiersMatchSharedVectors() throws {
    let document = try identityVectorDocument(
        "identifier-vectors.json",
        as: IdentifierVectorDocument.self
    )
    #expect(!document.vectors.isEmpty)

    for vector in document.vectors {
        #expect(
            (CaptureSeriesID(canonicalString: vector.text) != nil)
                == vector.valid,
            "\(vector.name)"
        )
        #expect(
            (CaptureRevisionID(canonicalString: vector.text) != nil)
                == vector.valid,
            "\(vector.name)"
        )
        #expect(
            (CaptureSessionID(canonicalString: vector.text) != nil)
                == vector.valid,
            "\(vector.name)"
        )
        #expect(
            (CoordinateSpaceID(canonicalString: vector.text) != nil)
                == vector.valid,
            "\(vector.name)"
        )
    }
}

@Test
func validatingRawValueRejectsNonV4Identifiers() throws {
    let v4 = try #require(
        UUID(uuidString: "88fdaaa8-4c86-411e-a8b7-7ad951788a63")
    )
    let v1 = try #require(
        UUID(uuidString: "2bb9cc24-b56a-11f1-8b22-e86538ed3a2e")
    )
    #expect(CaptureSessionID(validatingRawValue: v4) != nil)
    #expect(CaptureSessionID(validatingRawValue: v1) == nil)
    #expect(CaptureRevisionID(validatingRawValue: v1) == nil)

    // init(rawValue:) stays the unchecked RawRepresentable hook, so the
    // manifest initializer must still screen non-v4 UUIDs that arrive
    // through it.
    #expect(
        throws: BundleManifestError.invalidUUIDv4(
            v1.uuidString.lowercased()
        )
    ) {
        _ = try identityManifest(
            sessionIDs: [CaptureSessionID(rawValue: v1)]
        )
    }
}

@Test
func generatedIdentifiersRoundTripAsV4() {
    let identifier = CaptureSessionID()
    #expect(
        CaptureSessionID(canonicalString: identifier.description)
            == identifier
    )
}

@Test
func identifierDecodingRejectsNonV4() {
    let json = Data(
        "\"2bb9cc24-b56a-11f1-8b22-e86538ed3a2e\"".utf8
    )
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            CaptureSessionID.self,
            from: json
        )
    }
}
