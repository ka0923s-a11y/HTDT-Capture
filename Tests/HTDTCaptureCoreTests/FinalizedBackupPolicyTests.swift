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

/// Filesystem truth for `isExcludedFromBackup` (legacy bolph71656-ai/HTDT-Capture#305): the
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

/// Under full-suite parallel load the backup-exclusion xattr write
/// can take a few milliseconds to become visible to a subsequent
/// `getxattr`; poll briefly instead of asserting on a single read.
private func backupExcludedEventually(
    _ url: URL,
    _ expected: Bool
) throws -> Bool {
    var result = try backupExcluded(url)
    var attempts = 0
    while result != expected, attempts < 500 {
        Thread.sleep(forTimeInterval: 0.002)
        result = try backupExcluded(url)
        attempts += 1
    }
    return result == expected
}

// MARK: - legacy bolph71656-ai/HTDT-Capture#305: finalized backup policy

@Test(.serialized)
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
    #expect(try backupExcludedEventually(captureRoot.appendingPathComponent("finalized", isDirectory: true), true))
    #expect(try backupExcludedEventually(finalizedRevision, true))
    #expect(try backupExcludedEventually(captureRoot.appendingPathComponent("exports", isDirectory: true), true))
    #expect(try backupExcludedEventually(exportArchive, true))
}

@Test(.serialized)
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
    #expect(try backupExcludedEventually(finalizedRevision, true))

    let failures = CaptureStoragePolicy.applyFinalizedBackupPolicy(
        captureRoot: captureRoot,
        policy: .backupEligible
    )
    #expect(failures.isEmpty)
    #expect(try backupExcludedEventually(finalizedRevision, false))
}

@Test(.serialized)
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
    #expect(try backupExcludedEventually(revision, true))

    // Switching back restores backup eligibility — the policy is
    // user-selectable, not one-way.
    try CaptureStoragePolicy.applyFinalizedRevisionPolicy(
        revisionRoot: revision,
        policy: .backupEligible
    )
    #expect(try backupExcludedEventually(revision, false))
}

@Test(.serialized)
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
    #expect(try backupExcludedEventually(archive, true))

    try CaptureStoragePolicy.applyExportArchivePolicy(
        archiveURL: archive,
        policy: .backupEligible
    )
    #expect(try backupExcludedEventually(archive, false))
}

@Test(.serialized)
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
    #expect(try backupExcludedEventually(captureRoot.appendingPathComponent("working", isDirectory: true), true))
    #expect(try backupExcludedEventually(captureRoot.appendingPathComponent("finalized", isDirectory: true), true))
    #expect(try backupExcludedEventually(captureRoot.appendingPathComponent("exports", isDirectory: true), true))
    #expect(try backupExcludedEventually(captureRoot, false))
}

@Test(.serialized)
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
    // default policy — this is the rename bug legacy bolph71656-ai/HTDT-Capture#305 fixes.
    try CaptureStoragePolicy.applyWorkingRevisionPolicy(
        revisionRoot: finalizedRevision
    )

    let failures = CaptureStoragePolicy
        .applyCaptureRootPolicy(captureRoot: captureRoot)
    #expect(failures.isEmpty)
    #expect(try backupExcludedEventually(finalizedRevision, false))
}
