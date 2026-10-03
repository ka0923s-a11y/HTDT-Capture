import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeOrphanCaptureRoot() throws -> URL {
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

private func makeWorkingRevision(
    captureRoot: URL,
    revisionID: CaptureRevisionID = CaptureRevisionID(),
    payloadBytes: Int = 16
) throws -> URL {
    let directory = captureRoot
        .appendingPathComponent("working", isDirectory: true)
        .appendingPathComponent(
            revisionID.description,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    if payloadBytes > 0 {
        try Data(repeating: 0xAB, count: payloadBytes).write(
            to: directory.appendingPathComponent(
                "partial.bin",
                isDirectory: false
            )
        )
    }
    return directory
}

@Test
func scanSurfacesAbandonedWorkingRevision() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let revisionID = CaptureRevisionID()
    let directory = try makeWorkingRevision(
        captureRoot: root,
        revisionID: revisionID
    )

    let result = PersistedCaptureInventory(captureRoot: root).scan()
    #expect(result.captures.isEmpty)
    #expect(result.quarantinedArtifacts.isEmpty)
    #expect(result.orphanedWorkingArtifacts.count == 1)

    let orphan = try #require(
        result.orphanedWorkingArtifacts.first
    )
    #expect(orphan.kind == .abandonedRevision)
    #expect(
        orphan.url.resolvingSymlinksInPath()
            == directory.resolvingSymlinksInPath()
    )
    #expect(orphan.retainedBytes == 16)
}

@Test
func scanNeverOrphansTheActiveRevision() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let active = CaptureRevisionID()
    let abandoned = CaptureRevisionID()
    try makeWorkingRevision(
        captureRoot: root,
        revisionID: active
    )
    try makeWorkingRevision(
        captureRoot: root,
        revisionID: abandoned
    )

    let result = PersistedCaptureInventory(captureRoot: root)
        .scan(activeRevisionID: active)
    #expect(result.orphanedWorkingArtifacts.count == 1)
    #expect(
        result.orphanedWorkingArtifacts.first?.url
            .lastPathComponent == abandoned.description
    )
}

@Test
func scanListsStaleWriterTempFiles() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )
    let temp = working.appendingPathComponent(
        ".tmp-0123456789abcdef",
        isDirectory: false
    )
    try Data([1, 2, 3]).write(to: temp)

    let result = PersistedCaptureInventory(captureRoot: root).scan()
    #expect(result.orphanedWorkingArtifacts.count == 1)
    #expect(
        result.orphanedWorkingArtifacts.first?.kind
            == .staleWriterTempFile
    )
    #expect(
        result.orphanedWorkingArtifacts.first?.retainedBytes == 3
    )
}

@Test
func scanQuarantinesUnprovenWorkingDirectories() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // A directory inside working/ that is not a canonical revision
    // UUID has no ownership proof: it is surfaced as quarantined, never
    // offered as a deletable orphan.
    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    let stray = working.appendingPathComponent(
        "not-a-revision",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: stray,
        withIntermediateDirectories: true
    )
    try Data([0x00]).write(
        to: stray.appendingPathComponent(
            "payload.bin",
            isDirectory: false
        )
    )

    let result = PersistedCaptureInventory(captureRoot: root).scan()
    #expect(result.orphanedWorkingArtifacts.isEmpty)
    #expect(result.quarantinedArtifacts.count == 1)
    #expect(
        result.quarantinedArtifacts.first?.kind
            == .unexpectedItem
    )
    #expect(
        result.quarantinedArtifacts.first?.reason
            .range(of: "ownership proof") != nil
    )
}

@Test
func scanQuarantinesUnrecognizedWorkingFiles() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )
    try Data([0x01]).write(
        to: working.appendingPathComponent(
            "notes.txt",
            isDirectory: false
        )
    )

    let result = PersistedCaptureInventory(captureRoot: root).scan()
    #expect(result.orphanedWorkingArtifacts.isEmpty)
    #expect(result.quarantinedArtifacts.count == 1)
}

@Test
func removeWorkingOrphanDeletesProvenRevision() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let directory = try makeWorkingRevision(captureRoot: root)
    let inventory = PersistedCaptureInventory(captureRoot: root)
    let orphan = try #require(
        inventory.scan().orphanedWorkingArtifacts.first
    )

    try inventory.removeWorkingOrphan(orphan)
    #expect(
        !FileManager.default.fileExists(atPath: directory.path)
    )
    #expect(
        inventory.scan().orphanedWorkingArtifacts.isEmpty
    )
}

@Test
func removeWorkingOrphanRefusesUnprovenPaths() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )

    // A non-UUID directory inside working/ is never recursively
    // deleted without ownership proof.
    let strayDirectory = working.appendingPathComponent(
        "foreign-directory",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: strayDirectory,
        withIntermediateDirectories: true
    )
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeWorkingOrphanLocation
    ) {
        try inventory.removeWorkingOrphan(
            PersistedCaptureWorkingOrphan(
                kind: .abandonedRevision,
                url: strayDirectory,
                retainedBytes: 0
            )
        )
    }
    #expect(
        FileManager.default.fileExists(
            atPath: strayDirectory.path
        )
    )

    // A regular file without the .tmp- marker is refused even when a
    // caller claims the writer-temp kind.
    let strayFile = working.appendingPathComponent(
        "foreign.bin",
        isDirectory: false
    )
    try Data([0x01]).write(to: strayFile)
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeWorkingOrphanLocation
    ) {
        try inventory.removeWorkingOrphan(
            PersistedCaptureWorkingOrphan(
                kind: .staleWriterTempFile,
                url: strayFile,
                retainedBytes: 1
            )
        )
    }
    #expect(
        FileManager.default.fileExists(atPath: strayFile.path)
    )

    // Anything outside the working root is refused outright.
    let outside = root.appendingPathComponent(
        "outside.txt",
        isDirectory: false
    )
    try Data([0x02]).write(to: outside)
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeWorkingOrphanLocation
    ) {
        try inventory.removeWorkingOrphan(
            PersistedCaptureWorkingOrphan(
                kind: .abandonedRevision,
                url: outside,
                retainedBytes: 1
            )
        )
    }
    #expect(
        FileManager.default.fileExists(atPath: outside.path)
    )
}

@Test
func removeWorkingOrphanRefusesSymlinkEscape() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )

    // A UUID-named symlink that resolves outside the working root can
    // never prove direct-child ownership after resolution.
    let outside = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: outside) }
    let link = working.appendingPathComponent(
        CaptureRevisionID().description,
        isDirectory: true
    )
    try FileManager.default.createSymbolicLink(
        at: link,
        withDestinationURL: outside
    )

    let inventory = PersistedCaptureInventory(captureRoot: root)
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeWorkingOrphanLocation
    ) {
        try inventory.removeWorkingOrphan(
            PersistedCaptureWorkingOrphan(
                kind: .abandonedRevision,
                url: link,
                retainedBytes: 0
            )
        )
    }
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test
func removeArtifactAllowsWorkingLeafButNotUnprovenDirectory() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )

    // Leaf items inside the working root are removable through the
    // quarantine path.
    let stray = working.appendingPathComponent(
        "stray.partial",
        isDirectory: false
    )
    try Data([0x01]).write(to: stray)
    try inventory.removeArtifact(
        PersistedCaptureQuarantinedArtifact(
            kind: .unexpectedItem,
            url: stray,
            reason: "unrecognized item inside the working root"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: stray.path))

    // A directory without canonical UUID ownership proof is refused.
    let unproven = working.appendingPathComponent(
        "unproven",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: unproven,
        withIntermediateDirectories: true
    )
    #expect(
        throws: PersistedCaptureInventoryError
            .unsafeArtifactLocation
    ) {
        try inventory.removeArtifact(
            PersistedCaptureQuarantinedArtifact(
                kind: .unexpectedItem,
                url: unproven,
                reason: "unrecognized directory"
            )
        )
    }
    #expect(
        FileManager.default.fileExists(atPath: unproven.path)
    )
}

@Test
func canRemoveArtifactAgreesWithRemoveArtifact() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let inventory = PersistedCaptureInventory(captureRoot: root)
    let working = root.appendingPathComponent(
        "working",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: working,
        withIntermediateDirectories: true
    )
    func artifact(_ url: URL) -> PersistedCaptureQuarantinedArtifact {
        PersistedCaptureQuarantinedArtifact(
            kind: .unexpectedItem,
            url: url,
            reason: "probe"
        )
    }

    let leaf = working.appendingPathComponent(
        "stray.partial",
        isDirectory: false
    )
    try Data([0x01]).write(to: leaf)
    #expect(inventory.canRemoveArtifact(artifact(leaf)))

    let revisionDir = working.appendingPathComponent(
        UUID().uuidString.lowercased(),
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: revisionDir,
        withIntermediateDirectories: true
    )
    #expect(inventory.canRemoveArtifact(artifact(revisionDir)))

    let rollbackDir = working.appendingPathComponent(
        ".rollback-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: rollbackDir,
        withIntermediateDirectories: true
    )
    #expect(inventory.canRemoveArtifact(artifact(rollbackDir)))

    let unproven = working.appendingPathComponent(
        "unproven",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: unproven,
        withIntermediateDirectories: true
    )
    #expect(!inventory.canRemoveArtifact(artifact(unproven)))

    let outside = root.appendingPathComponent(
        "outside.txt",
        isDirectory: false
    )
    try Data([0x02]).write(to: outside)
    #expect(!inventory.canRemoveArtifact(artifact(outside)))
}

@Test
func storagePolicyExcludesOnlyTheWorkingRootFromBackup() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let captureRoot = root.appendingPathComponent(
        "HTDTCapture",
        isDirectory: true
    )
    let failures = CaptureStoragePolicy
        .applyCaptureRootPolicy(captureRoot: captureRoot)
    #expect(failures.isEmpty)

    func excluded(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        return values.isExcludedFromBackup == true
    }

    // Transient working data is excluded; user-facing finalized and
    // exported artifacts deliberately are not (legacy bolph71656-ai/HTDT-Capture#136 policy).
    let workingExcluded = try excluded(
        captureRoot.appendingPathComponent(
            "working",
            isDirectory: true
        )
    )
    let finalizedExcluded = try excluded(
        captureRoot.appendingPathComponent(
            "finalized",
            isDirectory: true
        )
    )
    let exportsExcluded = try excluded(
        captureRoot.appendingPathComponent(
            "exports",
            isDirectory: true
        )
    )
    let captureRootExcluded = try excluded(captureRoot)
    #expect(workingExcluded)
    #expect(!finalizedExcluded)
    #expect(!exportsExcluded)
    #expect(!captureRootExcluded)

    // The policy is idempotent.
    #expect(
        CaptureStoragePolicy
            .applyCaptureRootPolicy(captureRoot: captureRoot)
            .isEmpty
    )
}

@Test
func storagePolicyMarksNewWorkingRevision() throws {
    let root = try makeOrphanCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let revisionRoot = try makeWorkingRevision(
        captureRoot: root,
        payloadBytes: 0
    )
    try CaptureStoragePolicy.applyWorkingRevisionPolicy(
        revisionRoot: revisionRoot
    )
    let revisionExcluded = try revisionRoot.resourceValues(
        forKeys: [.isExcludedFromBackupKey]
    ).isExcludedFromBackup
    #expect(revisionExcluded == true)

    // File-protection application is exercised on platforms that
    // support it; elsewhere it is a documented no-op and must not
    // throw.
    try CaptureStoragePolicy.applyFileProtection(to: revisionRoot)
}
