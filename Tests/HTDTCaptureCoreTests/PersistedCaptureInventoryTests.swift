import Foundation
import Testing
@testable import HTDTCaptureCore

private func inventoryTestQuality() -> CaptureQualityReport {
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

private func makeCaptureRoot() throws -> URL {
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

@discardableResult
private func finalizeFixture(
    captureRoot: URL,
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    finalizedAtUTC: String = "2026-09-21T00:01:00Z",
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
    try qualityEncoder.encode(inventoryTestQuality()).write(
        to: qualityDirectory.appendingPathComponent(
            "capture-quality.json"
        )
    )
    // #194: finalized bundles carry the foundation payload set.
    let foundationDeclarations =
        try BundleValidationFixture.stageFoundationPayloads(
            in: staging
        )

    let request = BundleFinalizationRequest(
        captureSeriesID: CaptureSeriesID(),
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
        createdAtUTC: "2026-09-21T00:00:00Z",
        finalizedAtUTC: finalizedAtUTC,
        app: BundleAppIdentity(
            version: "0.1.0",
            build: "inventory-test"
        ),
        payloads: foundationDeclarations + [
            BundlePayloadDeclaration(
                path: "payload.bin",
                mediaType: "application/octet-stream",
                producer: "inventory-test",
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
        qualityReport: inventoryTestQuality()
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

@discardableResult
private func exportFixture(
    finalized: FinalizedCaptureRevision,
    captureRoot: URL
) throws -> URL {
    let destination = captureRoot
        .appendingPathComponent("exports", isDirectory: true)
        .appendingPathComponent(
            finalized.captureRevisionID.description
                + ".htdtcapture",
            isDirectory: false
        )
    _ = try CaptureBundleArchiveExporter.export(
        finalizedDirectory: finalized.directory,
        destination: destination
    )
    return destination
}

@Test
func inventoryAdoptsValidatedFinalizedRevision() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let inventory = PersistedCaptureInventory(captureRoot: root)

    let result = inventory.scan()
    #expect(result.enumerationFailures.isEmpty)
    #expect(result.quarantinedArtifacts.isEmpty)
    #expect(result.captures.count == 1)

    let record = try #require(result.captures.first)
    #expect(
        record.captureRevisionID == finalized.captureRevisionID
    )
    #expect(record.finalizedDirectory == finalized.directory)
    #expect(
        record.finalizedValidation?.bundleDigest
            == finalized.bundleDigest
    )
    #expect(record.exportArchive == nil)
    #expect(record.canOpen)
}

@Test
func inventoryBindsIdentityToManifestNotDirectoryName()
    async throws
{
    // A validated bundle stored under a non-canonical directory name
    // is quarantined, never adopted under name-derived authority.
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let misplaced = root
        .appendingPathComponent("finalized", isDirectory: true)
        .appendingPathComponent(
            "not-the-revision-name",
            isDirectory: true
        )
    try FileManager.default.moveItem(
        at: finalized.directory,
        to: misplaced
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(result.captures.isEmpty)
    #expect(result.quarantinedArtifacts.count == 1)
    #expect(
        result.quarantinedArtifacts.first?.kind
            == .finalizedDirectory
    )
    #expect(
        result.quarantinedArtifacts.first?.url
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
            == misplaced
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
    )
}

@Test
func inventoryQuarantinesTamperedPayload() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    try Data([9, 9, 9]).write(
        to: finalized.directory.appendingPathComponent(
            "payload.bin",
            isDirectory: false
        )
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(result.captures.isEmpty)
    #expect(result.quarantinedArtifacts.count == 1)
    #expect(
        result.quarantinedArtifacts.first?.kind
            == .finalizedDirectory
    )
    #expect(
        result.quarantinedArtifacts.first?.reason
            .range(of: "validation failed") != nil
    )
}

@Test
func inventoryAttachesMatchingValidatedArchive() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let archive = try exportFixture(
        finalized: finalized,
        captureRoot: root
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(result.quarantinedArtifacts.isEmpty)
    let record = try #require(result.captures.first)
    #expect(record.exportArchive?.path == archive.path)
    #expect(
        record.exportValidation?.bundleDigest
            == finalized.bundleDigest
    )
    #expect(record.canOpen)
}

@Test
func inventoryQuarantinesArchiveWithForeignName() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let revisionA = CaptureRevisionID()
    let finalizedA = try await finalizeFixture(
        captureRoot: root,
        revisionID: revisionA
    )
    let finalizedB = try await finalizeFixture(captureRoot: root)
    let archiveB = try exportFixture(
        finalized: finalizedB,
        captureRoot: root
    )

    // An archive for revision B stored under revision A's canonical
    // archive name is misplaced; it is quarantined, not adopted.
    let misplaced = archiveB
        .deletingLastPathComponent()
        .appendingPathComponent(
            revisionA.description + ".htdtcapture",
            isDirectory: false
        )
    try FileManager.default.moveItem(
        at: archiveB,
        to: misplaced
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(result.captures.count == 2)
    let recordA = result.captures.first {
        $0.captureRevisionID == revisionA
    }
    #expect(recordA?.exportArchive == nil)
    #expect(result.quarantinedArtifacts.count == 1)
    #expect(
        result.quarantinedArtifacts.first?.kind
            == .exportArchive
    )
}

@Test
func inventoryReportsPartialExportArtifacts() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    try await finalizeFixture(captureRoot: root)
    let exports = root.appendingPathComponent(
        "exports",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: exports,
        withIntermediateDirectories: true
    )
    let partial = exports.appendingPathComponent(
        ".stale.htdtcapture.tmp-0123456789",
        isDirectory: false
    )
    try Data([0x50, 0x4b]).write(to: partial)

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(result.captures.count == 1)
    #expect(result.quarantinedArtifacts.count == 1)
    #expect(
        result.quarantinedArtifacts.first?.kind
            == .unexpectedItem
    )
}

@Test
func inventoryListsExportOnlyArchive() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let archive = try exportFixture(
        finalized: finalized,
        captureRoot: root
    )
    try FileManager.default.removeItem(at: finalized.directory)

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    let record = try #require(result.captures.first)
    #expect(record.finalizedDirectory == nil)
    #expect(record.exportArchive?.path == archive.path)
    #expect(!record.canOpen)
}

@Test
func inventoryListsMultipleRevisionsNewestFirst() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let older = try await finalizeFixture(
        captureRoot: root,
        finalizedAtUTC: "2026-09-21T00:01:00Z"
    )
    let newer = try await finalizeFixture(
        captureRoot: root,
        finalizedAtUTC: "2026-09-21T00:02:00Z"
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan()
    #expect(
        result.captures.map(\.captureRevisionID)
            == [
                newer.captureRevisionID,
                older.captureRevisionID,
            ]
    )
}

@Test
func validatedRecordReconfirmsIdentity() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let inventory = PersistedCaptureInventory(captureRoot: root)

    let record = inventory.validatedRecord(
        captureRevisionID: finalized.captureRevisionID
    )
    #expect(
        record?.captureRevisionID == finalized.captureRevisionID
    )
    #expect(
        record?.finalizedValidation?.bundleDigest
            == finalized.bundleDigest
    )

    // Once the bundle no longer validates, nothing is adopted.
    try FileManager.default.removeItem(
        at: finalized.directory.appendingPathComponent(
            "payload.bin",
            isDirectory: false
        )
    )
    #expect(
        inventory.validatedRecord(
            captureRevisionID: finalized.captureRevisionID
        ) == nil
    )
}

@Test
func validatedRecordDropsStaleExportSlot() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let archive = try exportFixture(
        finalized: finalized,
        captureRoot: root
    )

    // A corrupted archive must not block adoption of the finalized
    // revision; it simply leaves no export slot.
    try Data([0x50, 0x4b, 0x99]).write(to: archive)

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let record = try #require(
        inventory.validatedRecord(
            captureRevisionID: finalized.captureRevisionID
        )
    )
    #expect(record.finalizedDirectory != nil)
    #expect(record.exportArchive == nil)
}

@Test
func deleteCaptureRemovesFinalizedDirectoryAndExport()
    async throws
{
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)
    let archive = try exportFixture(
        finalized: finalized,
        captureRoot: root
    )

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let result = inventory.deleteCapture(
        captureRevisionID: finalized.captureRevisionID
    )

    #expect(result.succeeded)
    #expect(result.remaining.isEmpty)
    #expect(result.removed.count == 2)
    #expect(
        !FileManager.default.fileExists(
            atPath: finalized.directory.path
        )
    )
    #expect(
        !FileManager.default.fileExists(atPath: archive.path)
    )
    #expect(inventory.scan().captures.isEmpty)
}

@Test
func deleteCaptureRemovesFinalizedOnlyRevision() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let finalized = try await finalizeFixture(captureRoot: root)

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let result = inventory.deleteCapture(
        captureRevisionID: finalized.captureRevisionID
    )

    // A missing archive is fine: the transaction is still complete.
    #expect(result.succeeded)
    #expect(result.removed.count == 1)
    #expect(
        !FileManager.default.fileExists(
            atPath: finalized.directory.path
        )
    )
}

@Test
func deleteCaptureRefusesUnprovenIdentity() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let revisionA = CaptureRevisionID()
    let finalizedB = try await finalizeFixture(captureRoot: root)

    // A directory named like revision A but whose manifest declares
    // revision B is never proven to belong to A, so nothing is
    // deleted.
    let impostor = root
        .appendingPathComponent("finalized", isDirectory: true)
        .appendingPathComponent(
            revisionA.description,
            isDirectory: true
        )
    try FileManager.default.moveItem(
        at: finalizedB.directory,
        to: impostor
    )

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let result = inventory.deleteCapture(
        captureRevisionID: revisionA
    )

    #expect(!result.succeeded)
    #expect(result.removed.isEmpty)
    #expect(result.remaining.count == 1)
    #expect(
        FileManager.default.fileExists(atPath: impostor.path)
    )
}

@Test
func deleteCapturePreservesOtherRevisions() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // A sibling revision is never touched by another revision's
    // deletion transaction.
    let keep = try await finalizeFixture(captureRoot: root)
    let drop = try await finalizeFixture(captureRoot: root)

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let result = inventory.deleteCapture(
        captureRevisionID: drop.captureRevisionID
    )

    #expect(result.succeeded)
    #expect(
        FileManager.default.fileExists(
            atPath: keep.directory.path
        )
    )
    #expect(
        inventory.scan().captures.map(\.captureRevisionID)
            == [keep.captureRevisionID]
    )
}

@Test
func deleteCaptureReportsUnremovableSlot() async throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // A plain file occupying the finalized slot cannot be proven to
    // belong to the revision; it stays and is reported precisely.
    let revisionID = CaptureRevisionID()
    let finalized = root.appendingPathComponent(
        "finalized",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: finalized,
        withIntermediateDirectories: true
    )
    let slot = finalized.appendingPathComponent(
        revisionID.description,
        isDirectory: false
    )
    try Data([0x00]).write(to: slot)

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let result = inventory.deleteCapture(
        captureRevisionID: revisionID
    )

    #expect(!result.succeeded)
    #expect(result.removed.isEmpty)
    #expect(
        result.remaining.first?.url.path == slot.path
    )
    #expect(FileManager.default.fileExists(atPath: slot.path))
}

@Test
func removeArtifactDeletesOnlyInsideCaptureRoots() throws {
    let root = try makeCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let inventory = PersistedCaptureInventory(captureRoot: root)

    let exports = root.appendingPathComponent(
        "exports",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: exports,
        withIntermediateDirectories: true
    )
    let stray = exports.appendingPathComponent(
        "partial.tmp",
        isDirectory: false
    )
    try Data([0x01]).write(to: stray)

    try inventory.removeArtifact(
        PersistedCaptureQuarantinedArtifact(
            kind: .unexpectedItem,
            url: stray,
            reason: "partial export artifact"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: stray.path))

    // A fabricated artifact outside the app-owned roots is refused.
    let outside = root.appendingPathComponent(
        "outside.txt",
        isDirectory: false
    )
    try Data([0x02]).write(to: outside)
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeArtifactLocation
    ) {
        try inventory.removeArtifact(
            PersistedCaptureQuarantinedArtifact(
                kind: .unexpectedItem,
                url: outside,
                reason: "forged"
            )
        )
    }
    #expect(
        FileManager.default.fileExists(atPath: outside.path)
    )

    // A traversal-style artifact URL is refused as well.
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeArtifactLocation
    ) {
        try inventory.removeArtifact(
            PersistedCaptureQuarantinedArtifact(
                kind: .unexpectedItem,
                url: exports.appendingPathComponent(
                    "../outside.txt"
                ),
                reason: "forged"
            )
        )
    }
    #expect(
        FileManager.default.fileExists(atPath: outside.path)
    )
}

@Test
func persistedAdoptionReachesFinalizedFromIdle() throws {
    var machine = CaptureStateMachine()
    try machine.apply(.adoptFinalized)
    #expect(machine.state == .finalized)

    // An adopted capture that already has a validated archive reuses
    // the normal export transition.
    try machine.apply(.export)
    #expect(machine.state == .exported)

    try machine.apply(.reset)
    #expect(machine.state == .idle)
}

@Test
func persistedAdoptionIsRejectedOutsideIdle() {
    var machine = CaptureStateMachine(state: .scanning)
    #expect(throws: CaptureStateMachineError.self) {
        try machine.apply(.adoptFinalized)
    }
    #expect(machine.state == .scanning)
}
