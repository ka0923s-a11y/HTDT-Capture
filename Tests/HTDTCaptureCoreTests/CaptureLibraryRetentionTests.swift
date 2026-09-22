import Foundation
import Testing
@testable import HTDTCaptureCore

private func retentionTestQuality() -> CaptureQualityReport {
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

private func retentionTestRoot() throws -> URL {
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

/// Finalizes one fixture revision under `captureRoot` — needed
/// where the delete path must remove real bytes (issue #394).
@discardableResult
private func retentionFinalizeFixture(
    captureRoot: URL,
    seriesID: CaptureSeriesID,
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    finalizedAtUTC: String = "2026-09-21T00:01:00Z",
    createdAtUTC: String = "2026-09-19T00:00:00Z",
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
    try qualityEncoder.encode(retentionTestQuality()).write(
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
        createdAtUTC: createdAtUTC,
        finalizedAtUTC: finalizedAtUTC,
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "retention-test"
        ),
        payloads: foundationDeclarations + [
            BundlePayloadDeclaration(
                path: "payload.bin",
                mediaType: "application/octet-stream",
                producer: "retention-test",
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
        qualityReport: retentionTestQuality()
    )

    return try await BundleRevisionFinalizer().finalize(
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
}

/// A fabricated record for the pure-preview tests — byte counts
/// suffice; the planner never inspects directories it isn't asked
/// to delete (issue #394).
private func fabricateRecord(
    seriesID: CaptureSeriesID,
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    finalizedAtUTC: String,
    finalizedBytes: Int64 = 100,
    archiveBytes: Int64 = 50
) -> PersistedCaptureRecord {
    PersistedCaptureRecord(
        captureRevisionID: revisionID,
        captureSeriesID: seriesID,
        finalizedAtUTC: finalizedAtUTC,
        finalizedDirectory: URL(
            fileURLWithPath: "/nonexistent/finalized/"
                + revisionID.description
        ),
        finalizedValidation: nil,
        exportArchive: URL(
            fileURLWithPath: "/nonexistent/exports/"
                + revisionID.description + ".htdtcapture"
        ),
        exportValidation: nil,
        finalizedByteCount: finalizedBytes,
        exportArchiveByteCount: archiveBytes
    )
}

private func retentionDeliveryJob(
    revisionID: CaptureRevisionID,
    seriesID: CaptureSeriesID,
    state: HTDTDeliveryJobState = .queued
) -> HTDTDeliveryJob {
    HTDTDeliveryJob(
        deliveryJobID: "job-" + revisionID.description,
        captureRevisionID: revisionID,
        captureSeriesID: seriesID,
        bundleDigest: String(repeating: "a", count: 64),
        archiveSHA256: String(repeating: "b", count: 64),
        archiveByteCount: 50,
        payloadRelativePath:
            "delivery-queue/payloads/x.htdtcapture",
        destination: HTDTHandoffDestination(
            name: "receiver",
            kind: .shareSheet
        ),
        createdAtUTC: "2026-09-21T00:02:00Z",
        state: state
    )
}

private func retentionMission(
    recordID: String,
    revisionID: CaptureRevisionID
) -> HTDTMissionRecord {
    HTDTMissionRecord(
        recordID: recordID,
        missionID: "mission-1",
        missionKind: .initialSurvey,
        purpose: nil,
        payloadRelativePath: "mission-inbox/x.json",
        payloadSHA256: String(repeating: "c", count: 64),
        planID: "plan-1",
        planVersion: "1",
        planSHA256: String(repeating: "d", count: 64),
        projectRef: "proj",
        roomName: "room",
        issuedAtUTC: nil,
        importedAtUTC: "2026-09-21T00:03:00Z",
        lifecycle: .inProgress,
        associatedCaptureRevisionIDs: [revisionID.description]
    )
}

private func retentionReceipt(
    revisionID: CaptureRevisionID,
    seriesID: CaptureSeriesID,
    outcome: String = "delivered"
) -> HTDTHandoffReceipt {
    HTDTHandoffReceipt(
        receiptID: UUID().uuidString.lowercased(),
        captureRevisionID: revisionID,
        captureSeriesID: seriesID,
        bundleDigest: String(repeating: "e", count: 64),
        archiveSHA256: String(repeating: "f", count: 64),
        archiveByteCount: 50,
        destination: HTDTHandoffDestination(
            name: "receiver",
            kind: .shareSheet
        ),
        initiatedAtUTC: "2026-09-21T00:04:00Z",
        outcome: outcome
    )
}

@Test
func seriesPreviewKeepsLatestAndProtectedMarks() throws {
    let seriesID = CaptureSeriesID()
    let r1 = fabricateRecord(
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-20T00:00:00Z"
    )
    let r2 = fabricateRecord(
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-21T00:00:00Z"
    )
    let r3 = fabricateRecord(
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-22T00:00:00Z"
    )

    let metadata = CaptureLibraryMetadataDocument(
        revisionMarks: [
            r1.captureRevisionID.description: CaptureRevisionMark(
                milestone: true
            )
        ]
    )

    let preview = CaptureLibraryRetentionPlanner.seriesPreview(
        seriesID: seriesID,
        records: [r1, r2, r3],
        allRecords: [r1, r2, r3],
        metadata: metadata,
        deliveryJobs: [],
        missionRecords: [],
        receipts: []
    )

    #expect(preview.revisionCount == 3)
    let byID = Dictionary(
        uniqueKeysWithValues: preview.rows.map {
            ($0.captureRevisionID, $0)
        }
    )
    // Latest and milestone-marked keep; the older unmarked revision
    // is the delete candidate — never auto "keep latest only".
    #expect(byID[r3.captureRevisionID]?.recommendation == .keep)
    #expect(byID[r3.captureRevisionID]?.isLatest == true)
    #expect(byID[r1.captureRevisionID]?.recommendation == .keep)
    #expect(byID[r1.captureRevisionID]?.mark.milestone == true)
    #expect(
        byID[r2.captureRevisionID]?.recommendation
            == .deleteCandidate
    )
    #expect(byID[r1.captureRevisionID]?.blockers == [.protectedMark])
    // A protected revision is not deletable without the override.
    #expect(byID[r1.captureRevisionID]?.isDeletable == false)
    #expect(byID[r2.captureRevisionID]?.isDeletable == true)
    // Derived archive bytes stay countable separately.
    #expect(preview.totalDerivedArchiveBytes == 150)
    #expect(preview.totalFinalizedBytes == 300)
}

@Test
func deletionPreviewNamesBlockersAndWarnings() throws {
    let seriesID = CaptureSeriesID()
    let child = fabricateRecord(
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-22T00:00:00Z"
    )
    let parent = fabricateRecord(
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-21T00:00:00Z"
    )
    let job = retentionDeliveryJob(
        revisionID: parent.captureRevisionID,
        seriesID: seriesID
    )
    let mission = retentionMission(
        recordID: "rec-1",
        revisionID: parent.captureRevisionID
    )
    let receipt = retentionReceipt(
        revisionID: parent.captureRevisionID,
        seriesID: seriesID
    )

    let preview = CaptureLibraryRetentionPlanner.deletionPreview(
        records: [parent, child],
        allRecords: [parent, child],
        metadata: CaptureLibraryMetadataDocument(),
        deliveryJobs: [job],
        missionRecords: [mission],
        receipts: [receipt]
    )

    #expect(preview.revisionCount == 2)
    let parentOutcome = preview.outcomes.first {
        $0.captureRevisionID == parent.captureRevisionID
    }
    #expect(parentOutcome?.canDelete == false)
    #expect(
        parentOutcome?.blockers.contains(
            .pendingDeliveryJob("job-" + parent.captureRevisionID
                .description)
        ) == true
    )
    #expect(
        parentOutcome?.warnings.contains(
            .linkedToMission("rec-1")
        ) == true
    )
    #expect(
        parentOutcome?.warnings.contains(.handoffReceipts(1))
            == true
    )
    // A delivered receipt proves the bytes exist elsewhere — no
    // only-local-copy warning.
    #expect(
        parentOutcome?.warnings.contains(.onlyLocalCopy) == false
    )
    let childOutcome = preview.outcomes.first {
        $0.captureRevisionID == child.captureRevisionID
    }
    #expect(
        childOutcome?.warnings.contains(.onlyLocalCopy) == true
    )
}

@Test
func deleteSeriesRespectsProtectionAndBlockers() async throws {
    let root = try retentionTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let seriesID = CaptureSeriesID()
    // Two real finalized revisions: one protected, one free.
    let protected = try await retentionFinalizeFixture(
        captureRoot: root,
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-20T00:00:00Z"
    )
    let free = try await retentionFinalizeFixture(
        captureRoot: root,
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-21T00:00:00Z"
    )
    let blocked = try await retentionFinalizeFixture(
        captureRoot: root,
        seriesID: seriesID,
        finalizedAtUTC: "2026-09-22T00:00:00Z"
    )

    let store = CaptureLibraryMetadataStore(captureRoot: root)
    try store.updateRevisionMark(
        protected.captureRevisionID,
        mark: CaptureRevisionMark(milestone: true)
    )
    let job = retentionDeliveryJob(
        revisionID: blocked.captureRevisionID,
        seriesID: seriesID
    )

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let records = inventory.scan().captures
    #expect(records.count == 3)

    // Without the override: the protected revision is skipped, the
    // delivery-blocked revision is skipped, only the free one goes.
    let result = CaptureLibraryRetentionPlanner.deleteSeries(
        seriesID: seriesID,
        records: records,
        allRecords: records,
        inventory: inventory,
        metadataStore: store,
        deliveryJobs: [job],
        missionRecords: [],
        receipts: []
    )
    #expect(Set(result.deleted) == [free.captureRevisionID])
    #expect(
        result.skipped.contains {
            $0.captureRevisionID == protected.captureRevisionID
                && $0.blockers == [.protectedMark]
        }
    )
    #expect(
        result.skipped.contains {
            $0.captureRevisionID == blocked.captureRevisionID
                && $0.blockers.contains(.pendingDeliveryJob(
                    job.deliveryJobID
                ))
        }
    )
    #expect(
        inventory.scan().captures.count == 2
    )

    // With the explicit override the protected revision deletes;
    // the delivery-blocked one still refuses.
    let afterFirst = inventory.scan().captures
    let overridden = CaptureLibraryRetentionPlanner.deleteSeries(
        seriesID: seriesID,
        records: afterFirst,
        allRecords: afterFirst,
        inventory: inventory,
        metadataStore: store,
        deliveryJobs: [job],
        missionRecords: [],
        receipts: [],
        includeProtected: true
    )
    #expect(
        Set(overridden.deleted)
            == [protected.captureRevisionID]
    )
    #expect(
        overridden.skipped.contains {
            $0.captureRevisionID == blocked.captureRevisionID
        }
    )
    #expect(inventory.scan().captures.count == 1)
    #expect(
        inventory.scan().captures.first?.captureRevisionID
            == blocked.captureRevisionID
    )
}

@Test
func archivedSeriesStateRoundTripsThroughStore() throws {
    let root = try retentionTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = CaptureLibraryMetadataStore(captureRoot: root)
    let seriesID = CaptureSeriesID()
    try store.setSeriesState(
        seriesID,
        archived: true,
        archivedAtUTC: "2026-09-22T00:00:00Z"
    )
    var document = try store.load()
    #expect(
        document.seriesState(for: seriesID).archived == true
    )
    #expect(
        document.seriesState(for: seriesID).archivedAtUTC
            == "2026-09-22T00:00:00Z"
    )
    // Archiving drops nothing else: marks, names, notes survive.
    try store.updateRevisionMark(
        CaptureRevisionID(),
        mark: CaptureRevisionMark(favorite: true)
    )
    document = try store.load()
    #expect(document.revisionMarks.count == 1)

    // Unarchive clears the entry back to minimal.
    try store.setSeriesState(
        seriesID,
        archived: false,
        archivedAtUTC: nil
    )
    document = try store.load()
    #expect(
        document.seriesState(for: seriesID).archived == false
    )
    #expect(document.seriesStates.isEmpty)
}
