import Foundation
import Testing
@testable import HTDTCaptureCore

private func archiveReadyQuality() -> CaptureQualityReport {
    CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements()
    )
}

private func makeFinalizedArchiveFixture(
    root: URL
) async throws -> FinalizedCaptureRevision {
    let staging = root.appendingPathComponent(
        "staging",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    let payload = staging.appendingPathComponent(
        "payload.bin"
    )
    try Data([1, 2, 3, 4, 5]).write(to: payload)

    let request = BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        captureSessionIDs: [CaptureSessionID()],
        coordinateSpaceIDs: [CoordinateSpaceID()],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "archive-test"
        ),
        payloads: [
            BundlePayloadDeclaration(
                path: "payload.bin",
                mediaType: "application/octet-stream",
                producer: "archive-test",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
        ],
        qualityReport: archiveReadyQuality()
    )

    return try await BundleRevisionFinalizer().finalize(
        stagingDirectory: staging,
        destinationDirectory: root.appendingPathComponent(
            "finalized",
            isDirectory: true
        ),
        request: request
    )
}

@Test
func storedZipExportPreservesLogicalBundleDigest() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let finalized = try await makeFinalizedArchiveFixture(
        root: root
    )
    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )

    let result = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: destination
    )

    #expect(result.archiveURL == destination)
    #expect(result.bundleDigest == finalized.bundleDigest)
    #expect(result.payloadCount == 1)
    #expect(result.entryCount == 2)

    let reopened =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: destination
        )
    #expect(reopened.bundleDigest == finalized.bundleDigest)
    #expect(reopened.payloadCount == 1)
}

@Test
func exportNeverOverwritesExistingArchive() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let finalized = try await makeFinalizedArchiveFixture(
        root: root
    )
    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )
    try Data("existing".utf8).write(to: destination)

    #expect(
        throws: CaptureBundleArchiveError.destinationAlreadyExists
    ) {
        try CaptureBundleArchiveExporter.export(
            finalizedDirectory: finalized.directory,
            destination: destination
        )
    }
    #expect(try Data(contentsOf: destination) == Data("existing".utf8))
}

@Test
func archiveValidatorRejectsPostExportTamper() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let finalized = try await makeFinalizedArchiveFixture(
        root: root
    )
    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: destination
    )

    let handle = try FileHandle(forWritingTo: destination)
    defer {
        try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0xff]))
    try handle.synchronize()

    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveValidator.validate(
            archive: destination
        )
    }
}

@Test
func exportRequiresProjectOwnedExtension() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    let finalized = try await makeFinalizedArchiveFixture(
        root: root
    )

    #expect(
        throws: CaptureBundleArchiveError.invalidDestinationExtension
    ) {
        try CaptureBundleArchiveExporter.export(
            finalizedDirectory: finalized.directory,
            destination: root.appendingPathComponent("capture.zip")
        )
    }
}
