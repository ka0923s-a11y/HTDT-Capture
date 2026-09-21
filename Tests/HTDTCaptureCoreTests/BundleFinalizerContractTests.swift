import Foundation
import Testing
@testable import HTDTCaptureCore

private let contractQualityPath = "quality/capture-quality.json"

private func contractQualityReport(
    evidenceFrameCount: Int = 1
) -> CaptureQualityReport {
    CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: evidenceFrameCount,
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements()
    )
}

private func contractQualityDeclaration()
    -> BundlePayloadDeclaration
{
    BundlePayloadDeclaration(
        path: contractQualityPath,
        mediaType: "application/json",
        producer: "capture_quality",
        provenanceClass: .captureAppDerived,
        role: .canonical
    )
}

private func encodeQualityPayload(
    _ report: CaptureQualityReport
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(report)
}

private struct ContractStagingArea {
    let root: URL
    let staging: URL
    let destination: URL
}

private func makeContractStagingArea(
    fileManager: FileManager = .default
) throws -> ContractStagingArea {
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    let staging = root.appendingPathComponent(
        "staging",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    // #194: finalized bundles carry the foundation payload set; stage
    // it up front so every request built for this area validates.
    _ = try BundleValidationFixture.stageFoundationPayloads(
        in: staging
    )
    return ContractStagingArea(
        root: root,
        staging: staging,
        destination: root.appendingPathComponent(
            "finalized",
            isDirectory: true
        )
    )
}

private func stageQualityPayload(
    _ data: Data,
    in staging: URL,
    fileManager: FileManager = .default
) throws {
    try fileManager.createDirectory(
        at: staging.appendingPathComponent(
            "quality",
            isDirectory: true
        ),
        withIntermediateDirectories: true
    )
    try data.write(
        to: staging.appendingPathComponent(
            contractQualityPath
        )
    )
}

private func makeContractRequest(
    quality: CaptureQualityReport,
    payloads: [BundlePayloadDeclaration]
        = [contractQualityDeclaration()]
) -> BundleFinalizationRequest {
    BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        // Identity arrays must match the fixture session document so
        // the #194 grounding check holds.
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
        createdAtUTC: "2026-09-21T00:00:00Z",
        finalizedAtUTC: "2026-09-21T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "test"
        ),
        payloads: BundleValidationFixture
            .foundationPayloadDeclarations() + payloads,
        qualityReport: quality
    )
}

private func manifestURL(in staging: URL) -> URL {
    staging.appendingPathComponent(
        "manifest.json",
        isDirectory: false
    )
}

@Test
func finalizerSealsIdenticalStagedQualityPayload() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    let finalized = try await BundleRevisionFinalizer().finalize(
        stagingDirectory: area.staging,
        destinationDirectory: area.destination,
        request: makeContractRequest(quality: quality)
    )

    #expect(finalized.directory == area.destination)
    #expect(
        fileManager.fileExists(
            atPath: area.destination
                .appendingPathComponent("manifest.json")
                .path
        )
    )
}

@Test
func finalizerRejectsStaleStagedQualityPayload() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    try stageQualityPayload(
        encodeQualityPayload(
            contractQualityReport(evidenceFrameCount: 2)
        ),
        in: area.staging
    )
    let request = makeContractRequest(
        quality: contractQualityReport(evidenceFrameCount: 1)
    )

    await #expect(
        throws: BundleFinalizationError.qualityPayloadMismatch
    ) {
        try await BundleRevisionFinalizer().finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: request
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
    #expect(
        !fileManager.fileExists(atPath: area.destination.path)
    )
}

@Test
func finalizerRejectsNonReadyStagedQualityPayload() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let unready = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(),
        requirements: CaptureQualityRequirements()
    )
    #expect(!unready.readyForHTDTIngestion)
    try stageQualityPayload(
        encodeQualityPayload(unready),
        in: area.staging
    )

    await #expect(
        throws: BundleFinalizationError.qualityPayloadMismatch
    ) {
        try await BundleRevisionFinalizer().finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(
                quality: contractQualityReport()
            )
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
}

@Test
func finalizerRejectsMalformedQualityPayload() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    try stageQualityPayload(
        Data("{ not json".utf8),
        in: area.staging
    )

    await #expect(
        throws: BundleFinalizationError.qualityPayloadUnreadable
    ) {
        try await BundleRevisionFinalizer().finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(
                quality: contractQualityReport()
            )
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
}

@Test
func finalizerRejectsMissingQualityPayloadDeclaration() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    await #expect(
        throws: BundleFinalizationError.qualityPayloadMissing
    ) {
        try await BundleRevisionFinalizer().finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(
                quality: contractQualityReport(),
                payloads: []
            )
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
}

@Test
func finalizerRejectsDeclaredButAbsentQualityPayload() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    do {
        _ = try await BundleRevisionFinalizer().finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(
                quality: contractQualityReport()
            )
        )
        Issue.record(
            "expected stagedPayloadSetMismatch for absent quality file"
        )
    } catch let error as BundleFinalizationError {
        guard case .stagedPayloadSetMismatch = error else {
            Issue.record(
                "expected stagedPayloadSetMismatch, got \(error)"
            )
            return
        }
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
}

@Test
func finalizerAllowsProvenSameVolumeIdentity() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    let finalizer = BundleRevisionFinalizer(
        volumeIdentity: { _ in "vol-1" }
    )
    let finalized = try await finalizer.finalize(
        stagingDirectory: area.staging,
        destinationDirectory: area.destination,
        request: makeContractRequest(quality: quality)
    )
    #expect(finalized.directory == area.destination)
    #expect(
        fileManager.fileExists(
            atPath: area.destination
                .appendingPathComponent("manifest.json")
                .path
        )
    )
}

@Test
func finalizerRejectsMismatchedVolumeIdentity() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    let finalizer = BundleRevisionFinalizer(
        volumeIdentity: { url in
            url.lastPathComponent == "staging" ? "vol-a" : "vol-b"
        }
    )
    await #expect(
        throws: BundleFinalizationError.crossVolumePromotionForbidden
    ) {
        try await finalizer.finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(quality: quality)
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
    #expect(
        !fileManager.fileExists(atPath: area.destination.path)
    )
}

@Test
func finalizerRejectsUnknownVolumeIdentity() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    let finalizer = BundleRevisionFinalizer(
        volumeIdentity: { _ in nil }
    )
    await #expect(
        throws: BundleFinalizationError.crossVolumePromotionForbidden
    ) {
        try await finalizer.finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(quality: quality)
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
    #expect(
        !fileManager.fileExists(atPath: area.destination.path)
    )
}

@Test
func finalizerRejectsPartiallyUnknownVolumeIdentity() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    // Only the staging side resolves; the destination parent identity
    // stays unknown, which must not prove a same-volume rename.
    let finalizer = BundleRevisionFinalizer(
        volumeIdentity: { url in
            url.lastPathComponent == "staging" ? "vol-1" : nil
        }
    )
    await #expect(
        throws: BundleFinalizationError.crossVolumePromotionForbidden
    ) {
        try await finalizer.finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(quality: quality)
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
    #expect(
        !fileManager.fileExists(atPath: area.destination.path)
    )
}

@Test
func finalizerRejectsUnreadableVolumeIdentity() async throws {
    let fileManager = FileManager.default
    let area = try makeContractStagingArea(
        fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: area.root) }

    let quality = contractQualityReport()
    try stageQualityPayload(
        encodeQualityPayload(quality),
        in: area.staging
    )

    let finalizer = BundleRevisionFinalizer(
        volumeIdentity: { _ in
            throw BundleFilesystemError.invalidRoot
        }
    )
    await #expect(
        throws: BundleFinalizationError.crossVolumePromotionForbidden
    ) {
        try await finalizer.finalize(
            stagingDirectory: area.staging,
            destinationDirectory: area.destination,
            request: makeContractRequest(quality: quality)
        )
    }
    #expect(
        !fileManager.fileExists(
            atPath: manifestURL(in: area.staging).path
        )
    )
    #expect(fileManager.fileExists(atPath: area.staging.path))
    #expect(
        !fileManager.fileExists(atPath: area.destination.path)
    )
}
