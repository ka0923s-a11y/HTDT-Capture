import Foundation
import Testing
@testable import HTDTCaptureCore

private func transferTestQuality() -> CaptureQualityReport {
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

private func transferTestRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

/// Finalizes one fixture revision under `captureRoot` and writes its
/// export archive into `exports/` — the same shape the host leaves
/// on disk (issue #378 test fixture).
@discardableResult
private func transferFinalizeFixture(
    captureRoot: URL,
    seriesID: CaptureSeriesID,
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    finalizedAtUTC: String = "2026-09-21T00:01:00Z",
    parentRevisionID: CaptureRevisionID? = nil,
    payload: Data = Data([1, 2, 3, 4, 5])
) async throws -> FinalizedCaptureRevision {
    let staging = captureRoot
        .appendingPathComponent(
            "staging-" + UUID().uuidString.lowercased(),
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: staging,
        withIntermediateDirectories: true
    )
    try payload.write(
        to: staging.appendingPathComponent(
            "payload.bin",
            isDirectory: false
        )
    )
    let qualityDirectory = staging.appendingPathComponent(
        "quality",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: qualityDirectory,
        withIntermediateDirectories: true
    )
    let qualityEncoder = JSONEncoder()
    qualityEncoder.outputFormatting = [.sortedKeys]
    try qualityEncoder.encode(transferTestQuality()).write(
        to: qualityDirectory.appendingPathComponent(
            "capture-quality.json"
        )
    )
    let foundationDeclarations =
        try BundleValidationFixture.stageFoundationPayloads(
            in: staging
        )

    let request = BundleFinalizationRequest(
        captureSeriesID: seriesID,
        captureRevisionID: revisionID,
        parentRevisionID: parentRevisionID,
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
        finalizedAtUTC: finalizedAtUTC,
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "transfer-test"
        ),
        payloads: foundationDeclarations + [
            BundlePayloadDeclaration(
                path: "payload.bin",
                mediaType: "application/octet-stream",
                producer: "transfer-test",
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
        qualityReport: transferTestQuality()
    )

    let finalized = try await BundleRevisionFinalizer().finalize(
        stagingDirectory: staging,
        destinationDirectory: captureRoot
            .appendingPathComponent(
                "finalized",
                isDirectory: true
            )
            .appendingPathComponent(
                revisionID.description,
                isDirectory: true
            ),
        request: request
    )
    let archiveDestination = captureRoot
        .appendingPathComponent("exports", isDirectory: true)
        .appendingPathComponent(
            revisionID.description + ".htdtcapture",
            isDirectory: false
        )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: archiveDestination
    )
    return finalized
}

private func transferReceipt(
    revisionID: CaptureRevisionID,
    seriesID: CaptureSeriesID,
    receiptID: String = UUID().uuidString.lowercased(),
    bundleDigest: String,
    archiveSHA256: String,
    archiveByteCount: Int64
) -> HTDTHandoffReceipt {
    HTDTHandoffReceipt(
        receiptID: receiptID,
        captureRevisionID: revisionID,
        captureSeriesID: seriesID,
        bundleDigest: bundleDigest,
        archiveSHA256: archiveSHA256,
        archiveByteCount: archiveByteCount,
        destination: HTDTHandoffDestination(
            name: "receiver",
            kind: .shareSheet
        ),
        initiatedAtUTC: "2026-09-21T00:02:00Z",
        outcome: "delivered"
    )
}

@Test
func libraryPackageExportRoundTripsEveryArchive() async throws {
    let source = try transferTestRoot()
    let destination = try transferTestRoot()
    defer {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: destination)
    }

    let seriesA = CaptureSeriesID()
    let seriesB = CaptureSeriesID()
    let r1 = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesA,
        payload: Data([1])
    )
    let r2 = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesA,
        finalizedAtUTC: "2026-09-21T01:01:00Z",
        parentRevisionID: r1.captureRevisionID,
        payload: Data([2])
    )
    let r3 = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesB,
        payload: Data([3])
    )

    let records = PersistedCaptureInventory(
        captureRoot: source
    ).scan().captures
    #expect(records.count == 3)

    let receipt = transferReceipt(
        revisionID: r1.captureRevisionID,
        seriesID: seriesA,
        bundleDigest: r1.bundleDigest.description,
        archiveSHA256: "unused",
        archiveByteCount: 0
    )

    let packageURL = destination.appendingPathComponent(
        "library.htdtcapturelibrary",
        isDirectory: false
    )
    let result = try CaptureLibraryPackageExporter.export(
        records: records,
        scope: .all,
        metadata: CaptureLibraryMetadataDocument(
            series: [
                seriesA.description: CaptureLibraryEntryMetadata(
                    displayName: "Theater A",
                    note: nil
                )
            ]
        ),
        receipts: [receipt],
        destination: packageURL,
        appVersion: "1.0.0",
        appBuild: "test",
        nowUTC: "2026-09-22T00:00:00Z"
    )
    #expect(result.revisionCount == 3)

    // The package reads back: manifest validates and names every
    // archive member it carries.
    let validated = try CaptureLibraryPackageReader.validate(
        archive: packageURL
    )
    #expect(validated.manifest.revisions.count == 3)
    #expect(
        Set(validated.manifest.revisions.map {
            $0.captureRevisionID
        })
            == Set(
                [
                    r1.captureRevisionID,
                    r2.captureRevisionID,
                    r3.captureRevisionID,
                ].map(\.description)
            )
    )

    // Staged preview on a fresh device: all three are importable.
    let staging = destination.appendingPathComponent(
        "library-import-staging/test",
        isDirectory: true
    )
    let preview = try CaptureLibraryImporter.preview(
        package: packageURL,
        captureRoot: destination,
        localRecords: [],
        stagingDirectory: staging
    )
    #expect(preview.importableCount == 3)
    #expect(preview.receiptsToAppend == 1)
    #expect(preview.metadataAdoptions == 1)

    let commit = try CaptureLibraryImporter.commit(
        preview: preview,
        captureRoot: destination
    )
    #expect(commit.imported.count == 3)
    #expect(commit.conflicts.isEmpty)
    #expect(commit.failed.isEmpty)

    // Imported bytes validate under the same inventory scan.
    let imported = PersistedCaptureInventory(
        captureRoot: destination
    ).scan().captures
    #expect(imported.count == 3)
    #expect(
        imported.contains {
            $0.captureRevisionID == r1.captureRevisionID
                && $0.finalizedDirectory != nil
                && $0.exportArchive != nil
        }
    )
}

@Test
func libraryImportIsIdempotentAndNeverRewritesIdentity() async throws {
    let source = try transferTestRoot()
    let target = try transferTestRoot()
    defer {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: target)
    }

    let seriesID = CaptureSeriesID()
    let finalized = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesID
    )
    let sourceRecords = PersistedCaptureInventory(
        captureRoot: source
    ).scan().captures

    let packageURL = target.appendingPathComponent(
        "library.htdtcapturelibrary",
        isDirectory: false
    )
    _ = try CaptureLibraryPackageExporter.export(
        records: sourceRecords,
        scope: .all,
        metadata: CaptureLibraryMetadataDocument(),
        receipts: [],
        destination: packageURL,
        appVersion: "1.0.0",
        appBuild: "test",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    // First commit imports; the second preview classifies the same
    // bytes as an exact duplicate, not a rewrite.
    let firstStaging = target.appendingPathComponent(
        "staging-1",
        isDirectory: true
    )
    let first = try CaptureLibraryImporter.preview(
        package: packageURL,
        captureRoot: target,
        localRecords: [],
        stagingDirectory: firstStaging
    )
    _ = try CaptureLibraryImporter.commit(
        preview: first,
        captureRoot: target
    )

    let localRecords = PersistedCaptureInventory(
        captureRoot: target
    ).scan().captures
    let secondStaging = target.appendingPathComponent(
        "staging-2",
        isDirectory: true
    )
    let second = try CaptureLibraryImporter.preview(
        package: packageURL,
        captureRoot: target,
        localRecords: localRecords,
        stagingDirectory: secondStaging
    )
    #expect(second.importableCount == 0)
    #expect(
        second.entries.first?.disposition == .duplicate
    )
    let secondCommit = try CaptureLibraryImporter.commit(
        preview: second,
        captureRoot: target
    )
    #expect(secondCommit.duplicates.count == 1)
    #expect(secondCommit.imported.isEmpty)

    // A same-ID package carrying different bytes is a hard
    // conflict — the local record is never overwritten.
    let other = try transferTestRoot()
    defer { try? FileManager.default.removeItem(at: other) }
    _ = try await transferFinalizeFixture(
        captureRoot: other,
        seriesID: seriesID,
        revisionID: finalized.captureRevisionID,
        payload: Data([9, 9, 9, 9, 9, 9, 9, 9])
    )
    let otherRecords = PersistedCaptureInventory(
        captureRoot: other
    ).scan().captures
    let conflictPackage = other.appendingPathComponent(
        "library.htdtcapturelibrary",
        isDirectory: false
    )
    _ = try CaptureLibraryPackageExporter.export(
        records: otherRecords,
        scope: .all,
        metadata: CaptureLibraryMetadataDocument(),
        receipts: [],
        destination: conflictPackage,
        appVersion: "1.0.0",
        appBuild: "test",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    let conflictStaging = target.appendingPathComponent(
        "staging-3",
        isDirectory: true
    )
    let conflictPreview = try CaptureLibraryImporter.preview(
        package: conflictPackage,
        captureRoot: target,
        localRecords: localRecords,
        stagingDirectory: conflictStaging
    )
    #expect(
        conflictPreview.entries.first?.disposition == .conflict
    )
    let conflictCommit = try CaptureLibraryImporter.commit(
        preview: conflictPreview,
        captureRoot: target
    )
    #expect(conflictCommit.conflicts.count == 1)
    #expect(conflictCommit.imported.isEmpty)
}

@Test
func libraryExportScopeFiltersBySeriesAndRevision() async throws {
    let source = try transferTestRoot()
    defer { try? FileManager.default.removeItem(at: source) }

    let seriesA = CaptureSeriesID()
    let seriesB = CaptureSeriesID()
    let r1 = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesA
    )
    _ = try await transferFinalizeFixture(
        captureRoot: source,
        seriesID: seriesB,
        payload: Data([9])
    )

    let records = PersistedCaptureInventory(
        captureRoot: source
    ).scan().captures

    let seriesPackage = source.appendingPathComponent(
        "series.htdtcapturelibrary",
        isDirectory: false
    )
    let scoped = try CaptureLibraryPackageExporter.export(
        records: records,
        scope: .series([seriesA]),
        metadata: CaptureLibraryMetadataDocument(),
        receipts: [],
        destination: seriesPackage,
        appVersion: "1.0.0",
        appBuild: "test",
        nowUTC: "2026-09-22T00:00:00Z"
    )
    #expect(scoped.revisionCount == 1)
    #expect(scoped.skippedRevisions.isEmpty)
    let scopedManifest = try CaptureLibraryPackageReader.validate(
        archive: seriesPackage
    ).manifest
    #expect(
        scopedManifest.revisions.allSatisfy {
            $0.captureSeriesID == seriesA.description
        }
    )

    let revisionPackage = source.appendingPathComponent(
        "rev.htdtcapturelibrary",
        isDirectory: false
    )
    let single = try CaptureLibraryPackageExporter.export(
        records: records,
        scope: .revisions([r1.captureRevisionID]),
        metadata: CaptureLibraryMetadataDocument(),
        receipts: [],
        destination: revisionPackage,
        appVersion: "1.0.0",
        appBuild: "test",
        nowUTC: "2026-09-22T00:00:00Z"
    )
    #expect(single.revisionCount == 1)
}
