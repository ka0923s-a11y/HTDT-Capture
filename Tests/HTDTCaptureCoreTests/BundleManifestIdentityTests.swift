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

@Test
func manifestRejectsSelfParentRevision() {
    let revision = CaptureRevisionID()
    #expect(throws: BundleManifestError.selfParentRevision) {
        _ = try identityManifest(
            revisionID: revision,
            parentRevisionID: revision
        )
    }
}

@Test
func manifestAcceptsNullAndDistinctParents() throws {
    let revision = CaptureRevisionID()
    _ = try identityManifest(revisionID: revision)
    _ = try identityManifest(
        revisionID: revision,
        parentRevisionID: CaptureRevisionID()
    )
}

@Test
func manifestDecodingRejectsSelfParentRevision() {
    let json = identityManifestJSON(
        revisionID: "10000000-0000-4000-8000-000000000004",
        parentRevisionIDJSON: "\"10000000-0000-4000-8000-000000000004\""
    )
    #expect(throws: BundleManifestError.selfParentRevision) {
        _ = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func manifestDecodingAcceptsNullAndDistinctParents() throws {
    for parentJSON in [
        "null",
        "\"10000000-0000-4000-8000-00000000000e\"",
    ] {
        let json = identityManifestJSON(
            revisionID: "10000000-0000-4000-8000-000000000004",
            parentRevisionIDJSON: parentJSON
        )
        _ = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func revisionVectorsMatchSharedContract() throws {
    let document = try identityVectorDocument(
        "revision-vectors.json",
        as: RevisionVectorDocument.self
    )
    #expect(!document.vectors.isEmpty)

    for vector in document.vectors {
        let revision = try #require(
            CaptureRevisionID(
                canonicalString: vector.captureRevisionID
            ),
            "\(vector.name)"
        )
        let parent = vector.parentRevisionID.flatMap {
            CaptureRevisionID(canonicalString: $0)
        }
        if vector.valid {
            _ = try identityManifest(
                revisionID: revision,
                parentRevisionID: parent
            )
        } else {
            #expect(throws: BundleManifestError.self) {
                _ = try identityManifest(
                    revisionID: revision,
                    parentRevisionID: parent
                )
            }
        }
    }
}

@Test
func manifestRejectsMalformedSourceRefNamespace() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: ["opaque-token"]
    )
    #expect(
        throws: BundleManifestError.malformedSourceRef(
            "payloads/a.bin",
            "opaque-token"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsEmptySourceRef() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: [""]
    )
    #expect(
        throws: BundleManifestError.malformedSourceRef(
            "payloads/a.bin",
            ""
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsDuplicateSourceRef() throws {
    let bravo = try identityEntry(
        "payloads/b.bin",
        sha256:
            "3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d"
    )
    let alpha = try identityEntry(
        "payloads/a.bin",
        sourceRefs: [
            "path:payloads/b.bin",
            "path:payloads/b.bin",
        ]
    )
    #expect(
        throws: BundleManifestError.duplicateSourceRef(
            "payloads/a.bin",
            "path:payloads/b.bin"
        )
    ) {
        _ = try identityManifest(files: [alpha, bravo])
    }
}

@Test
func manifestRejectsDanglingPathSourceRef() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: ["path:payloads/missing.bin"]
    )
    #expect(
        throws: BundleManifestError.unresolvedSourceRefPath(
            "payloads/a.bin",
            "path:payloads/missing.bin"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsEscapingPathSourceRef() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: ["path:../escape.bin"]
    )
    #expect(
        throws: BundleManifestError.malformedSourceRef(
            "payloads/a.bin",
            "path:../escape.bin"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsSelfDigestSourceRef() throws {
    let digest =
        "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
    let entry = try identityEntry(
        "payloads/a.bin",
        sha256: digest,
        sourceRefs: ["sha256:\(digest)"]
    )
    #expect(
        throws: BundleManifestError.selfReferencingSourceRef(
            "payloads/a.bin",
            "sha256:\(digest)"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsDanglingDigestSourceRef() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: [
            "sha256:2e7d2c03a9507ae265ecf5b5356885a53393a2029d241394997265a1a25aefc6"
        ]
    )
    #expect(
        throws: BundleManifestError.unresolvedSourceRefDigest(
            "payloads/a.bin",
            "sha256:2e7d2c03a9507ae265ecf5b5356885a53393a2029d241394997265a1a25aefc6"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsUnknownCaptureSessionSourceRef() throws {
    let entry = try identityEntry(
        "payloads/a.bin",
        sourceRefs: [
            "capture_session:10000000-0000-4000-8000-0000000000bb"
        ]
    )
    #expect(
        throws: BundleManifestError.unknownSourceRefSession(
            "payloads/a.bin",
            "capture_session:10000000-0000-4000-8000-0000000000bb"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsDerivedEntryWithoutSourceRefs() throws {
    let entry = try identityEntry(
        "previews/a.heic",
        mediaType: "image/heic",
        role: .derived
    )
    #expect(
        throws: BundleManifestError.derivedEntryMissingSourceRefs(
            "previews/a.heic"
        )
    ) {
        _ = try identityManifest(files: [entry])
    }
}

@Test
func manifestRejectsSourceRefPathCycle() throws {
    let alpha = try identityEntry(
        "payloads/a.bin",
        sourceRefs: ["path:payloads/b.bin"]
    )
    let bravo = try identityEntry(
        "payloads/b.bin",
        sha256:
            "3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d",
        sourceRefs: ["path:payloads/a.bin"]
    )
    #expect(
        throws: BundleManifestError.cyclicSourceRefPath(
            "payloads/b.bin",
            "path:payloads/a.bin"
        )
    ) {
        _ = try identityManifest(files: [alpha, bravo])
    }
}

@Test
func manifestDecodingRejectsMalformedSourceRef() {
    let json = identityManifestJSON(
        revisionID: "10000000-0000-4000-8000-000000000004",
        parentRevisionIDJSON: "null",
        filesJSON: """
            {
              "path": "payloads/a.bin",
              "bytes": 1,
              "media_type": "application/octet-stream",
              "sha256": "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
              "producer": "test",
              "provenance_class": "capture_app_derived",
              "role": "canonical",
              "source_refs": ["foo:bar"]
            }
            """
    )
    #expect(
        throws: BundleManifestError.malformedSourceRef(
            "payloads/a.bin",
            "foo:bar"
        )
    ) {
        _ = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(json.utf8)
        )
    }
}
