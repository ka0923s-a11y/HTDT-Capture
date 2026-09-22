import Foundation
import Testing
@testable import HTDTCaptureCore

private func makePolicyCaptureRoot() throws -> URL {
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

/// Filesystem truth for `isExcludedFromBackup` (#305): the
/// `com.apple.metadata:com_apple_backup_excludeItem` extended
/// attribute is what platform backup honors. `URL.resourceValues`
/// can serve a stale in-memory value, so assertions read the
/// attribute itself.
private func backupExcluded(_ url: URL) throws -> Bool {
    url.path.withCString {
        getxattr(
            $0,
            "com.apple.metadata:com_apple_backup_excludeItem",
            nil,
            0,
            0,
            0
        ) >= 0
    }
}

// MARK: - #305: finalized backup policy

@Test
func finalizedBackupPolicyMarksRootsAndChildren() throws {
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let captureRoot = root.appendingPathComponent(
        "HTDTCapture",
        isDirectory: true
    )
    let finalizedRevision = captureRoot
        .appendingPathComponent("finalized", isDirectory: true)
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    let exportArchive = captureRoot
        .appendingPathComponent("exports", isDirectory: true)
        .appendingPathComponent(
            UUID().uuidString + ".htdtcapture",
            isDirectory: false
        )
    try FileManager.default.createDirectory(
        at: finalizedRevision,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: exportArchive.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("archive".utf8).write(to: exportArchive)

    let failures = CaptureStoragePolicy.applyFinalizedBackupPolicy(
        captureRoot: captureRoot,
        policy: .excludedFromBackup
    )
    #expect(failures.isEmpty)

    // Directory roots and every artifact inside them carry the
    // policy — including export archives, which are files.
    #expect(
        try backupExcluded(
            captureRoot.appendingPathComponent(
                "finalized",
                isDirectory: true
            )
        )
    )
    #expect(try backupExcluded(finalizedRevision))
    #expect(
        try backupExcluded(
            captureRoot.appendingPathComponent(
                "exports",
                isDirectory: true
            )
        )
    )
    #expect(try backupExcluded(exportArchive))
}

@Test
func backupEligiblePolicyClearsCarriedOverExclusion() throws {
    // The same-volume rename from working/ into finalized/ preserves
    // the working directory's backup-exclusion flag. The eligible
    // policy must explicitly write `false`, not merely skip marking.
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let captureRoot = root.appendingPathComponent(
        "HTDTCapture",
        isDirectory: true
    )
    let finalizedRevision = captureRoot
        .appendingPathComponent("finalized", isDirectory: true)
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: finalizedRevision,
        withIntermediateDirectories: true
    )
    // Simulate the flag carried over by a rename from working/.
    try CaptureStoragePolicy.applyWorkingRevisionPolicy(
        revisionRoot: finalizedRevision
    )
    #expect(try backupExcluded(finalizedRevision))

    let failures = CaptureStoragePolicy.applyFinalizedBackupPolicy(
        captureRoot: captureRoot,
        policy: .backupEligible
    )
    #expect(failures.isEmpty)
    #expect(try !backupExcluded(finalizedRevision))
}

@Test
func finalizedRevisionPolicyMarksSingleDirectory() throws {
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let revision = root.appendingPathComponent(
        "revision",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: revision,
        withIntermediateDirectories: true
    )

    try CaptureStoragePolicy.applyFinalizedRevisionPolicy(
        revisionRoot: revision,
        policy: .excludedFromBackup
    )
    #expect(try backupExcluded(revision))

    // Switching back restores backup eligibility — the policy is
    // user-selectable, not one-way.
    try CaptureStoragePolicy.applyFinalizedRevisionPolicy(
        revisionRoot: revision,
        policy: .backupEligible
    )
    #expect(try !backupExcluded(revision))
}

@Test
func exportArchivePolicyMarksSingleFile() throws {
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let archive = root.appendingPathComponent(
        "share.htdtcapture",
        isDirectory: false
    )
    try Data("archive".utf8).write(to: archive)

    try CaptureStoragePolicy.applyExportArchivePolicy(
        archiveURL: archive,
        policy: .excludedFromBackup
    )
    #expect(try backupExcluded(archive))

    try CaptureStoragePolicy.applyExportArchivePolicy(
        archiveURL: archive,
        policy: .backupEligible
    )
    #expect(try !backupExcluded(archive))
}

@Test
func captureRootPolicyAppliesSelectedFinalizedPolicy() throws {
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let captureRoot = root.appendingPathComponent(
        "HTDTCapture",
        isDirectory: true
    )
    let failures = CaptureStoragePolicy.applyCaptureRootPolicy(
        captureRoot: captureRoot,
        finalizedBackupPolicy: .excludedFromBackup
    )
    #expect(failures.isEmpty)

    // Working stays excluded regardless; finalized/exports follow the
    // selected policy.
    #expect(
        try backupExcluded(
            captureRoot.appendingPathComponent(
                "working",
                isDirectory: true
            )
        )
    )
    #expect(
        try backupExcluded(
            captureRoot.appendingPathComponent(
                "finalized",
                isDirectory: true
            )
        )
    )
    #expect(
        try backupExcluded(
            captureRoot.appendingPathComponent(
                "exports",
                isDirectory: true
            )
        )
    )
    #expect(try !backupExcluded(captureRoot))
}

@Test
func captureRootPolicyDefaultKeepsFinalizedBackupEligible() throws {
    let root = try makePolicyCaptureRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let captureRoot = root.appendingPathComponent(
        "HTDTCapture",
        isDirectory: true
    )
    let finalizedRevision = captureRoot
        .appendingPathComponent("finalized", isDirectory: true)
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: finalizedRevision,
        withIntermediateDirectories: true
    )
    // Carried-over working flag must be normalized even with the
    // default policy — this is the rename bug #305 fixes.
    try CaptureStoragePolicy.applyWorkingRevisionPolicy(
        revisionRoot: finalizedRevision
    )

    let failures = CaptureStoragePolicy
        .applyCaptureRootPolicy(captureRoot: captureRoot)
    #expect(failures.isEmpty)
    #expect(try !backupExcluded(finalizedRevision))
}
