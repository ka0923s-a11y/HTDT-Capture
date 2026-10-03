import Foundation
import Testing
@testable import HTDTCaptureCore

private func fixtureID<T: CaptureIdentifier>(
    _ text: String,
    as type: T.Type
) -> T {
    T(rawValue: UUID(uuidString: text)!)
}

private func readyQualityReport() -> CaptureQualityReport {
    CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 1,
                    state: .normal
                )
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 2,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            annotationKeysPresent: [
                "speaker:L",
                "speaker:C",
                "speaker:R",
                "listening_position:MLP",
            ],
            measurementQuantityTypesPresent: ["room_width"],
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requiredAnnotationKeys: [
                "speaker:L",
                "speaker:C",
                "speaker:R",
                "listening_position:MLP",
            ],
            requiredMeasurementQuantityTypes: ["room_width"]
        )
    )
}

private struct CollisionVectorDocument: Decodable {
    struct Vector: Decodable {
        let left: String
        let right: String
        let collisionKey: String

        private enum CodingKeys: String, CodingKey {
            case left
            case right
            case collisionKey = "collision_key"
        }
    }

    let vectors: [Vector]
}

@Test
func swiftPathCollisionKeyMatchesSharedV1Vectors() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let vectorURL = repoRoot
        .appendingPathComponent("schemas")
        .appendingPathComponent("capture-bundle-v1")
        .appendingPathComponent(
            "path-collision-vectors.json"
        )
    let document = try JSONDecoder().decode(
        CollisionVectorDocument.self,
        from: Data(contentsOf: vectorURL)
    )

    for vector in document.vectors {
        #expect(
            BundleLogicalPath.collisionKey(vector.left)
                == vector.collisionKey
        )
        #expect(
            BundleLogicalPath.collisionKey(vector.right)
                == vector.collisionKey
        )
    }
}

@Test
func manifestRejectsMalformedUTCDateTime() throws {
    let ids = (
        series: CaptureSeriesID(),
        revision: CaptureRevisionID(),
        session: CaptureSessionID(),
        coordinate: CoordinateSpaceID()
    )

    #expect(throws: BundleManifestError.self) {
        _ = try BundleManifest(
            captureSeriesID: ids.series,
            captureRevisionID: ids.revision,
            parentRevisionID: nil,
            captureSessionIDs: [ids.session],
            coordinateSpaceIDs: [ids.coordinate],
            createdAtUTC: "not-a-dateTgarbageZ",
            finalizedAtUTC: "2026-09-20T12:34:56Z",
            app: BundleAppIdentity(
                version: "test",
                build: "test"
            ),
            files: []
        )
    }

    _ = try BundleManifest(
        captureSeriesID: ids.series,
        captureRevisionID: ids.revision,
        parentRevisionID: nil,
        captureSessionIDs: [ids.session],
        coordinateSpaceIDs: [ids.coordinate],
        createdAtUTC: "2026-09-20T12:34:56.123Z",
        finalizedAtUTC: "2026-09-20T12:35:00Z",
        app: BundleAppIdentity(
            version: "test",
            build: "test"
        ),
        files: []
    )
}

@Test
func manifestRejectsUnicodeCaseFoldCollision() throws {
    let digest = try EvidenceSHA256(
        String(repeating: "0", count: 64)
    )
    let entries = [
        BundleFileEntry(
            path: "Straße/payload.bin",
            bytes: 1,
            mediaType: "application/octet-stream",
            sha256: digest,
            producer: "test",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        BundleFileEntry(
            path: "STRASSE/payload.bin",
            bytes: 1,
            mediaType: "application/octet-stream",
            sha256: digest,
            producer: "test",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
    ]

    #expect(throws: BundleManifestError.self) {
        _ = try BundleManifest(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: CaptureRevisionID(),
            parentRevisionID: nil,
            captureSessionIDs: [CaptureSessionID()],
            coordinateSpaceIDs: [CoordinateSpaceID()],
            createdAtUTC: "2026-09-20T00:00:00Z",
            finalizedAtUTC: "2026-09-20T00:00:01Z",
            app: BundleAppIdentity(
                version: "test",
                build: "test"
            ),
            files: entries
        )
    }
}

@Test
func canonicalJSONMatchesPhase0Vector() throws {
    let value: CanonicalJSONValue = .object([
        "z": .null,
        "é": .boolean(true),
        "a": .integer(1),
    ])
    let encoded = try CanonicalJSON.encode(value)
    #expect(
        encoded
            == Data("{\"a\":1,\"z\":null,\"é\":true}".utf8)
    )
}

@Test
func swiftManifestMatchesFrozenPhase0Digest() throws {
    let entries = try [
        BundleFileEntry(
            path: "annotations/entities.json",
            bytes: 73,
            mediaType: "application/json",
            sha256: EvidenceSHA256(
                "0fec71bd7f0f7b8d030e8d11328e30709d49af1eab0fe78ae7a51b28c87b7aaa"
            ),
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical
        ),
        BundleFileEntry(
            path: "annotations/measurements.json",
            bytes: 81,
            mediaType: "application/json",
            sha256: EvidenceSHA256(
                "f6b30c04b49fd835cf2aebe91de4ec8f892966d3336c397d74549f885824d790"
            ),
            producer: "measurement",
            provenanceClass: .userAttestedMeasurement,
            role: .canonical
        ),
        BundleFileEntry(
            path: "quality/capture-quality.json",
            bytes: 117,
            mediaType: "application/json",
            sha256: EvidenceSHA256(
                "c5de750ff7cfe636cc8ccc32c1b89892a743d63d3bd30f1f7f840a624807c97c"
            ),
            producer: "capture_quality",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        BundleFileEntry(
            path: "session/capture-session.json",
            bytes: 179,
            mediaType: "application/json",
            sha256: EvidenceSHA256(
                "2710620632970157c75f3aabd7195f586cf0a4ff6a7e87984375629fe493b4cf"
            ),
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
    ]

    let manifest = try BundleManifest(
        captureSeriesID: fixtureID(
            "00000000-0000-4000-8000-000000000001",
            as: CaptureSeriesID.self
        ),
        captureRevisionID: fixtureID(
            "00000000-0000-4000-8000-000000000002",
            as: CaptureRevisionID.self
        ),
        parentRevisionID: nil,
        captureSessionIDs: [
            fixtureID(
                "00000000-0000-4000-8000-000000000003",
                as: CaptureSessionID.self
            ),
        ],
        coordinateSpaceIDs: [
            fixtureID(
                "00000000-0000-4000-8000-000000000004",
                as: CoordinateSpaceID.self
            ),
        ],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:00:00Z",
        app: BundleAppIdentity(
            version: "0.0.0-phase0",
            build: "phase0-fixture"
        ),
        files: entries
    )

    let digest = EvidenceIntegrity.sha256(
        of: try manifest.canonicalBytes()
    )
    #expect(
        digest.description
            == "1e29f755ce8f3557de60fa45f2c01a81936d3eca8db510cae795ba58170f035f"
    )
}

@Test
func incompleteCaptureProducesConcreteDiagnostics() {
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .running,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 0,
            integrityStatus: .notChecked
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireDepthEvidence: true,
            requiredAnnotationKeys: ["speaker:L"],
            requiredMeasurementQuantityTypes: ["room_width"]
        )
    )

    #expect(!report.readyForHTDTIngestion)
    let codes = Set(report.diagnostics.map(\.code))
    #expect(codes.contains("roomplan_not_completed"))
    #expect(codes.contains("insufficient_mesh_anchors"))
    #expect(codes.contains("insufficient_evidence_frames"))
    #expect(codes.contains("depth_evidence_missing"))
    #expect(codes.contains("annotation_missing"))
    #expect(codes.contains("measurement_missing"))
    #expect(codes.contains("integrity_not_checked"))
}

@Test
func readyCaptureHasNoErrorDiagnostics() {
    let report = readyQualityReport()
    #expect(report.readyForHTDTIngestion)
    #expect(
        !report.diagnostics.contains {
            $0.severity == .error
        }
    )
}

@Test
func finalizationIsAtomicValidatedAndNoOverwrite() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let staging = root.appendingPathComponent(
        "staging",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    let qualityDirectory = staging.appendingPathComponent(
        "quality",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: qualityDirectory,
        withIntermediateDirectories: true
    )

    let quality = readyQualityReport()
    let qualityEncoder = JSONEncoder()
    qualityEncoder.outputFormatting = [.sortedKeys]
    let qualityData = try qualityEncoder.encode(quality)
    try qualityData.write(
        to: qualityDirectory.appendingPathComponent(
            "capture-quality.json"
        )
    )

    // legacy bolph71656-ai/HTDT-Capture#194: a finalized v1 bundle carries the foundation payload set;
    // the manifest identity arrays must match the staged session doc.
    let foundationDeclarations =
        try BundleValidationFixture.stageFoundationPayloads(
            in: staging
        )

    let destination = root.appendingPathComponent(
        "finalized",
        isDirectory: true
    )
    let seriesID = CaptureSeriesID()
    let revisionID = CaptureRevisionID()
    let sessionID = CaptureSessionID(
        canonicalString: BundleValidationFixture.sessionUUID
    )!
    let spaceID = CoordinateSpaceID(
        canonicalString: BundleValidationFixture.spaceUUID
    )!

    let request = BundleFinalizationRequest(
        captureSeriesID: seriesID,
        captureRevisionID: revisionID,
        captureSessionIDs: [sessionID],
        coordinateSpaceIDs: [spaceID],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "test"
        ),
        payloads: foundationDeclarations + [
            BundlePayloadDeclaration(
                path: "quality/capture-quality.json",
                mediaType: "application/json",
                producer: "capture_quality",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
        ],
        qualityReport: quality
    )

    let finalizer = BundleRevisionFinalizer()
    let finalized = try await finalizer.finalize(
        stagingDirectory: staging,
        destinationDirectory: destination,
        request: request
    )

    #expect(finalized.directory == destination)
    #expect(
        fileManager.fileExists(
            atPath: destination
                .appendingPathComponent("manifest.json")
                .path
        )
    )
    #expect(!fileManager.fileExists(atPath: staging.path))

    let validation = try BundleDirectoryValidator.validate(
        root: destination
    )
    #expect(validation.bundleDigest == finalized.bundleDigest)
    // quality + session×3 foundation payloads (legacy bolph71656-ai/HTDT-Capture#194)
    #expect(validation.payloadCount == 4)

    let secondStaging = root.appendingPathComponent(
        "staging-2",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: secondStaging,
        withIntermediateDirectories: true
    )
    await #expect(throws: BundleFinalizationError.self) {
        try await finalizer.finalize(
            stagingDirectory: secondStaging,
            destinationDirectory: destination,
            request: request
        )
    }
}

@Test
func finalizerRejectsUnreadyQualityBeforeWritingManifest() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let staging = root.appendingPathComponent(
        "staging",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )

    let quality = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "1.0.0")
    )
    let request = BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        captureSessionIDs: [CaptureSessionID()],
        coordinateSpaceIDs: [CoordinateSpaceID()],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "test"
        ),
        payloads: [],
        qualityReport: quality
    )

    let finalizer = BundleRevisionFinalizer()
    await #expect(throws: BundleFinalizationError.self) {
        try await finalizer.finalize(
            stagingDirectory: staging,
            destinationDirectory: root.appendingPathComponent("finalized"),
            request: request
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: staging
                .appendingPathComponent("manifest.json")
                .path
        )
    )
}

@Test
func validatorDetectsTamperAfterFinalization() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let staging = root.appendingPathComponent(
        "staging",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    let payloadURL = staging.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payloadURL)

    let qualityDirectory = staging.appendingPathComponent(
        "quality",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: qualityDirectory,
        withIntermediateDirectories: true
    )
    let quality = readyQualityReport()
    let qualityEncoder = JSONEncoder()
    qualityEncoder.outputFormatting = [.sortedKeys]
    try qualityEncoder.encode(quality).write(
        to: qualityDirectory.appendingPathComponent(
            "capture-quality.json"
        )
    )

    let foundationDeclarations =
        try BundleValidationFixture.stageFoundationPayloads(
            in: staging
        )
    let request = BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        captureSessionIDs: [
            CaptureSessionID(
                canonicalString: BundleValidationFixture.sessionUUID
            )!
        ],
        coordinateSpaceIDs: [
            CoordinateSpaceID(
                canonicalString: BundleValidationFixture.spaceUUID
            )!
        ],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "test"
        ),
        payloads: foundationDeclarations + [
            BundlePayloadDeclaration(
                path: "payload.bin",
                mediaType: "application/octet-stream",
                producer: "test",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            BundlePayloadDeclaration(
                path: "quality/capture-quality.json",
                mediaType: "application/json",
                producer: "capture_quality",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
        ],
        qualityReport: quality
    )

    let destination = root.appendingPathComponent(
        "finalized",
        isDirectory: true
    )
    _ = try await BundleRevisionFinalizer().finalize(
        stagingDirectory: staging,
        destinationDirectory: destination,
        request: request
    )

    let finalizedPayload = destination.appendingPathComponent(
        "payload.bin"
    )
    var tampered = try Data(contentsOf: finalizedPayload)
    tampered.append(4)
    try tampered.write(to: finalizedPayload)

    #expect(throws: BundleDirectoryValidationError.self) {
        _ = try BundleDirectoryValidator.validate(root: destination)
    }
}
