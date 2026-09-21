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

private func stageQualityPayload(
    in staging: URL
) throws -> BundlePayloadDeclaration {
    let qualityDirectory = staging.appendingPathComponent(
        "quality",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: qualityDirectory,
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(archiveReadyQuality()).write(
        to: qualityDirectory.appendingPathComponent(
            "capture-quality.json"
        )
    )
    return BundlePayloadDeclaration(
        path: "quality/capture-quality.json",
        mediaType: "application/json",
        producer: "capture_quality",
        provenanceClass: .captureAppDerived,
        role: .canonical
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
    let qualityDeclaration = try stageQualityPayload(in: staging)

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
            qualityDeclaration,
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
    #expect(result.payloadCount == 2)
    #expect(result.entryCount == 3)

    let reopened =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: destination
        )
    #expect(reopened.bundleDigest == finalized.bundleDigest)
    #expect(reopened.payloadCount == 2)
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


private func archiveURL(
    root: URL,
    finalized: FinalizedCaptureRevision
) throws -> URL {
    let url = root.appendingPathComponent(
        UUID().uuidString + ".htdtcapture"
    )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: url
    )
    return url
}

private func occurrenceRanges(
    of needle: Data,
    in haystack: Data
) -> [Range<Data.Index>] {
    var result: [Range<Data.Index>] = []
    var start = haystack.startIndex
    while start < haystack.endIndex,
          let range = haystack.range(
            of: needle,
            options: [],
            in: start..<haystack.endIndex
          )
    {
        result.append(range)
        start = range.upperBound
    }
    return result
}

private func replacingOccurrences(
    _ data: Data,
    of needle: String,
    at indexes: [Int],
    with replacement: String
) -> Data {
    let source = Data(needle.utf8)
    let target = Data(replacement.utf8)
    precondition(source.count == target.count)

    var result = data
    let ranges = occurrenceRanges(
        of: source,
        in: data
    )
    for index in indexes {
        result.replaceSubrange(
            ranges[index],
            with: target
        )
    }
    return result
}

private func makeTwoPayloadFinalizedFixture(
    root: URL
) async throws -> FinalizedCaptureRevision {
    let staging = root.appendingPathComponent(
        "two-payload-staging",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    try Data([1]).write(
        to: staging.appendingPathComponent("alpha.bin")
    )
    try Data([2]).write(
        to: staging.appendingPathComponent("bravo.bin")
    )
    let qualityDeclaration = try stageQualityPayload(in: staging)

    let request = BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        captureSessionIDs: [CaptureSessionID()],
        coordinateSpaceIDs: [CoordinateSpaceID()],
        createdAtUTC: "2026-09-20T00:00:00Z",
        finalizedAtUTC: "2026-09-20T00:01:00Z",
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "archive-import-test"
        ),
        payloads: [
            BundlePayloadDeclaration(
                path: "alpha.bin",
                mediaType: "application/octet-stream",
                producer: "archive-test",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            BundlePayloadDeclaration(
                path: "bravo.bin",
                mediaType: "application/octet-stream",
                producer: "archive-test",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            qualityDeclaration,
        ],
        qualityReport: archiveReadyQuality()
    )

    return try await BundleRevisionFinalizer().finalize(
        stagingDirectory: staging,
        destinationDirectory: root.appendingPathComponent(
            "two-payload-finalized",
            isDirectory: true
        ),
        request: request
    )
}

@Test
func storedArchiveImportStagesRevalidatesAndPreservesDigest()
    async throws
{
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
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    let imported = root.appendingPathComponent(
        "imported",
        isDirectory: true
    )

    let result =
        try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: imported
        )

    #expect(result.directoryURL == imported)
    #expect(result.bundleDigest == finalized.bundleDigest)
    #expect(result.payloadCount == 2)
    #expect(result.entryCount == 3)
    #expect(
        try Data(
            contentsOf:
                imported.appendingPathComponent("payload.bin")
        ) == Data([1, 2, 3, 4, 5])
    )
    let reopened = try BundleDirectoryValidator.validate(
        root: imported
    )
    #expect(reopened.bundleDigest == finalized.bundleDigest)
}

@Test
func storedArchiveImportNeverOverwritesDestination()
    async throws
{
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
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    let imported = root.appendingPathComponent(
        "imported",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: imported,
        withIntermediateDirectories: true
    )
    let sentinel = imported.appendingPathComponent(
        "sentinel"
    )
    try Data("keep".utf8).write(to: sentinel)

    #expect(
        throws: CaptureBundleArchiveError.destinationAlreadyExists
    ) {
        _ = try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: imported
        )
    }
    #expect(
        try Data(contentsOf: sentinel) == Data("keep".utf8)
    )
}

@Test
func storedArchiveImportRejectsTraversalBeforeExtraction()
    async throws
{
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
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    let original = try Data(contentsOf: archive)
    let occurrences = occurrenceRanges(
        of: Data("payload.bin".utf8),
        in: original
    )
    #expect(occurrences.count == 3)

    let hostile = replacingOccurrences(
        original,
        of: "payload.bin",
        at: [1, 2],
        with: "../evil.bin"
    )
    try hostile.write(to: archive)

    let imported = root.appendingPathComponent(
        "imported",
        isDirectory: true
    )
    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: imported
        )
    }
    #expect(
        !FileManager.default.fileExists(
            atPath: imported.path
        )
    )
    #expect(
        !FileManager.default.fileExists(
            atPath:
                root.appendingPathComponent("evil.bin").path
        )
    )
}

@Test
func storedArchiveImportRejectsCaseCollision()
    async throws
{
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let finalized =
        try await makeTwoPayloadFinalizedFixture(root: root)
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    let original = try Data(contentsOf: archive)
    let bravo = occurrenceRanges(
        of: Data("bravo.bin".utf8),
        in: original
    )
    #expect(bravo.count == 3)

    let hostile = replacingOccurrences(
        original,
        of: "bravo.bin",
        at: [1, 2],
        with: "ALPHA.bin"
    )
    try hostile.write(to: archive)

    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: root.appendingPathComponent(
                "imported",
                isDirectory: true
            )
        )
    }
}

@Test
func storedArchiveImportRejectsCompressedMethod()
    async throws
{
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
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    var hostile = try Data(contentsOf: archive)
    #expect(hostile.count > 9)
    hostile[8] = 8
    hostile[9] = 0
    try hostile.write(to: archive)

    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: root.appendingPathComponent(
                "imported",
                isDirectory: true
            )
        )
    }
}

@Test
func storedArchiveImportAppliesExpandedSizeLimits()
    async throws
{
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
    let archive = try archiveURL(
        root: root,
        finalized: finalized
    )
    let limits = BundleFilesystemLimits(
        maxEntries: 10,
        maxFileBytes: 1,
        maxTotalBytes: 1024
    )

    #expect(throws: BundleFilesystemError.self) {
        _ = try StoredCaptureBundleArchiveImporter.importArchive(
            archive: archive,
            destination: root.appendingPathComponent(
                "imported",
                isDirectory: true
            ),
            limits: limits
        )
    }
}
