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
        requirements: CaptureQualityRequirements(
            rulesetVersion: "1.0.0")
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
    // #194: finalized bundles carry the foundation payload set.
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
            build: "archive-test"
        ),
        payloads: foundationDeclarations + [
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
    // payload.bin + quality + session×3 foundation (#194)
    #expect(result.payloadCount == 5)
    #expect(result.entryCount == 6)

    let reopened =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: destination
        )
    #expect(reopened.bundleDigest == finalized.bundleDigest)
    #expect(reopened.payloadCount == 5)
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
    // #194: finalized bundles carry the foundation payload set.
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
            build: "archive-import-test"
        ),
        payloads: foundationDeclarations + [
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
    #expect(result.payloadCount == 5)
    #expect(result.entryCount == 6)
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

// MARK: - ZIP entry-flag acceptance matrix

/// Walks a stored archive's local and central headers, rewriting each
/// entry's general-purpose flag field through `transform`. Used to
/// reproduce tool-produced archives whose entries carry flag 0 for
/// pure-ASCII names (Python's zipfile emits exactly that).
private func rewritingUtf8Flags(
    _ data: Data,
    transform: (_ entryIndex: Int, _ flags: UInt16) -> UInt16
) -> Data {
    var result = data
    func le16(_ offset: Int) -> Int {
        Int(result[offset]) | (Int(result[offset + 1]) << 8)
    }
    func le32(_ offset: Int) -> UInt32 {
        UInt32(result[offset])
            | (UInt32(result[offset + 1]) << 8)
            | (UInt32(result[offset + 2]) << 16)
            | (UInt32(result[offset + 3]) << 24)
    }
    func put16(_ value: UInt16, at offset: Int) {
        result[offset] = UInt8(value & 0xff)
        result[offset + 1] = UInt8(value >> 8)
    }

    var cursor = 0
    var index = 0
    // Local headers: flags at +6, name length at +26, extra length at
    // +28, uncompressed size at +18.
    while cursor + 30 <= result.count {
        let signature = le32(cursor)
        if signature == 0x02014b50 {
            break
        }
        guard signature == 0x04034b50 else {
            break
        }
        put16(
            transform(index, UInt16(le16(cursor + 6))),
            at: cursor + 6
        )
        let nameLength = le16(cursor + 26)
        let extraLength = le16(cursor + 28)
        let size = Int(le32(cursor + 18))
        cursor += 30 + nameLength + extraLength + size
        index += 1
    }
    // Central headers: flags at +8, name length at +28, extra length
    // at +30, comment length at +32.
    index = 0
    while cursor + 46 <= result.count {
        guard le32(cursor) == 0x02014b50 else {
            break
        }
        put16(
            transform(index, UInt16(le16(cursor + 8))),
            at: cursor + 8
        )
        let nameLength = le16(cursor + 28)
        let extraLength = le16(cursor + 30)
        let commentLength = le16(cursor + 32)
        cursor += 46 + nameLength + extraLength + commentLength
        index += 1
    }
    return result
}

@Test
func archiveValidatorAcceptsToolProducedClearFlagArchive()
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

    // The strict-flag archive still validates.
    let strictReport =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: archive
        )
    #expect(strictReport.bundleDigest == finalized.bundleDigest)

    // Python's zipfile leaves bit 11 clear for pure-ASCII names —
    // exactly what a tool-produced archive carries.
    let cleared = rewritingUtf8Flags(
        try Data(contentsOf: archive)
    ) { _, _ in
        0
    }
    try cleared.write(to: archive)

    let reopened =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: archive
        )
    #expect(reopened.bundleDigest == strictReport.bundleDigest)
    #expect(reopened.payloadCount == 5)
}

@Test
func archiveValidatorAcceptsMixedUtf8Flags() async throws {
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

    let mixed = rewritingUtf8Flags(
        try Data(contentsOf: archive)
    ) { index, flags in
        index == 0 ? 0 : flags
    }
    try mixed.write(to: archive)

    let reopened =
        try StoredCaptureBundleArchiveValidator.validate(
            archive: archive
        )
    #expect(reopened.bundleDigest == finalized.bundleDigest)
}

@Test
func archiveValidatorRejectsClearFlagOnNonAsciiName()
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

    // Rename payload.bin's header names to an equal-length NFC
    // non-ASCII name, then clear every entry flag: a non-ASCII name
    // still requires the UTF-8 flag even though pure-ASCII entries
    // no longer do.
    let original = try Data(contentsOf: archive)
    let occurrences = occurrenceRanges(
        of: Data("payload.bin".utf8),
        in: original
    )
    #expect(occurrences.count == 3)
    var hostile = replacingOccurrences(
        original,
        of: "payload.bin",
        at: [1, 2],
        with: "paylo\u{00E9}.bin"
    )
    hostile = rewritingUtf8Flags(hostile) { _, _ in
        0
    }
    try hostile.write(to: archive)

    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveValidator.validate(
            archive: archive
        )
    }
}

@Test
func archiveValidatorStillRejectsForeignFlagBits() async throws {
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

    // A data-descriptor bit stays rejected: only flag 0 (ASCII) or
    // 0x0800 are accepted.
    let hostile = rewritingUtf8Flags(
        try Data(contentsOf: archive)
    ) { index, flags in
        index == 0 ? 0x0808 : flags
    }
    try hostile.write(to: archive)

    #expect(throws: CaptureBundleArchiveError.self) {
        _ = try StoredCaptureBundleArchiveValidator.validate(
            archive: archive
        )
    }
}

// MARK: - Existing-archive export recovery (#118)

/// The deterministic export destination is a derived transport wrapper:
/// a validated archive carrying the finalized revision's digest is
/// recovered idempotently, while a corrupt or mismatched artifact is
/// removed and rebuilt once from the immutable finalized directory.
/// These tests pin the recover-vs-rebuild decision for the valid-
/// existing and invalid-existing cases.
@Test
func existingValidatedArchiveWithMatchingDigestRecovers()
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
    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: destination
    )

    #expect(
        ExistingExportArchiveClassifier.disposition(
            at: destination,
            expectedBundleDigest: finalized.bundleDigest
        ) == .recoverValidated
    )
}

@Test
func existingValidArchiveWithMismatchedDigestMustRebuild()
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
    // A second finalized revision needs its own staging/finalized
    // directories; the fixture derives them from the given root.
    let otherRoot = root.appendingPathComponent(
        "other",
        isDirectory: true
    )
    let otherRevision = try await makeFinalizedArchiveFixture(
        root: otherRoot
    )
    #expect(otherRevision.bundleDigest != finalized.bundleDigest)

    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: destination
    )

    // A structurally valid archive that belongs to a different
    // finalized revision is not reusable for this destination.
    #expect(
        ExistingExportArchiveClassifier.disposition(
            at: destination,
            expectedBundleDigest: otherRevision.bundleDigest
        ) == .rebuild
    )
}

@Test
func corruptExistingArchiveMustRebuild() async throws {
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
    try Data("not-an-archive".utf8).write(to: destination)

    #expect(
        ExistingExportArchiveClassifier.disposition(
            at: destination,
            expectedBundleDigest: finalized.bundleDigest
        ) == .rebuild
    )
}

@Test
func truncatedExistingArchiveMustRebuild() async throws {
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

    // Simulate an interrupted earlier export: only part of the stored
    // archive reached the deterministic path.
    let complete = try Data(contentsOf: destination)
    try complete.prefix(complete.count / 2).write(to: destination)

    #expect(
        ExistingExportArchiveClassifier.disposition(
            at: destination,
            expectedBundleDigest: finalized.bundleDigest
        ) == .rebuild
    )
}

@Test
func missingExistingArchiveMustRebuild() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let destination = root.appendingPathComponent(
        "capture.htdtcapture"
    )
    let anyDigest = try EvidenceSHA256(
        String(repeating: "a", count: 64)
    )

    #expect(
        ExistingExportArchiveClassifier.disposition(
            at: destination,
            expectedBundleDigest: anyDigest
        ) == .rebuild
    )
}

@Test
func storedArchiveReaderExtractsSingleEntry() async throws {
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

    // STORED entries sit uncompressed after their local header —
    // a single small payload (like a frame preview, issue #219) can
    // be read without walking or decompressing the package.
    #expect(
        StoredCaptureBundleArchiveReader.readEntry(
            archive: destination,
            path: "payload.bin"
        ) == Data([1, 2, 3, 4, 5])
    )
    #expect(
        StoredCaptureBundleArchiveReader.readEntry(
            archive: destination,
            path: "does-not-exist.bin"
        ) == nil
    )
}
