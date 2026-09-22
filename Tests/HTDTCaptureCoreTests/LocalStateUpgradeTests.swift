import Foundation
import Testing
@testable import HTDTCaptureCore

private func upgradeTestRoot() throws -> URL {
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

/// A v1.0.0 library-metadata document as the pre-#394 app wrote it —
/// `series` + `revisions` only, no lifecycle maps.
private func writeLegacyLibraryMetadata(
    into root: URL
) throws -> URL {
    let url = root.appendingPathComponent(
        "library-metadata.json",
        isDirectory: false
    )
    let json = """
        {
          "schema": "htdt.capture.library-metadata",
          "schema_version": "1.0.0",
          "series": {},
          "revisions": {}
        }
        """
    try json.data(using: .utf8)!.write(to: url)
    return url
}

@Test
func migratorUpgradesLegacyMetadataDocument() throws {
    let root = try upgradeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = try writeLegacyLibraryMetadata(into: root)
    let before = try Data(contentsOf: fileURL)

    let report = LocalStateMigrator.migrate(
        captureRoot: root,
        appVersion: "2.0.0",
        appBuild: "test-build",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    #expect(report.events.count == 1)
    let event = try #require(report.events.first)
    #expect(event.outcome == .migrated)
    #expect(event.fromVersion == "1.0.0")
    #expect(event.toVersion == "1.1.0")
    #expect(event.schemaID == "htdt.capture.library-metadata")
    #expect(event.recoveryCopyPath != nil)

    // The rewritten document carries the new version and still
    // loads through the store's fail-closed path.
    let loaded = try CaptureLibraryMetadataStore(
        captureRoot: root
    ).load()
    #expect(loaded.schemaVersion == "1.1.0")
    #expect(loaded.seriesStates.isEmpty)
    #expect(loaded.revisionMarks.isEmpty)

    // Pre-migration bytes survive under the recovery directory.
    let recovery = root.appendingPathComponent(
        "state-upgrade-recovery",
        isDirectory: true
    )
    let copies = try FileManager.default.contentsOfDirectory(
        at: recovery,
        includingPropertiesForKeys: nil
    )
    #expect(copies.count == 1)
    #expect(
        try Data(contentsOf: try #require(copies.first)) == before
    )
}

@Test
func migratorPreservesNewerUnknownVersion() throws {
    let root = try upgradeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // A document a newer app wrote — the migrator must leave every
    // byte exactly in place and never overwrite it.
    let fileURL = root.appendingPathComponent(
        "library-metadata.json",
        isDirectory: false
    )
    let newer = """
        {
          "schema": "htdt.capture.library-metadata",
          "schema_version": "9.9.9",
          "series": {},
          "revisions": {},
          "future_field": {"kept": true}
        }
        """
    try newer.data(using: .utf8)!.write(to: fileURL)
    let before = try Data(contentsOf: fileURL)

    let report = LocalStateMigrator.migrate(
        captureRoot: root,
        appVersion: "2.0.0",
        appBuild: "test-build",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    #expect(report.events.count == 1)
    #expect(
        report.events.first?.outcome == .preservedNewerVersion
    )
    #expect(report.preserved.count == 1)
    #expect(try Data(contentsOf: fileURL) == before)
}

@Test
func migratorPreservesUnreadableDocument() throws {
    let root = try upgradeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent(
        "handoff-receipts.json",
        isDirectory: false
    )
    let garbage = Data([0xde, 0xad, 0xbe, 0xef])
    try garbage.write(to: fileURL)

    let report = LocalStateMigrator.migrate(
        captureRoot: root,
        appVersion: "2.0.0",
        appBuild: "test-build",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    #expect(report.events.count == 1)
    #expect(
        report.events.first?.outcome == .preservedUnreadable
    )
    #expect(try Data(contentsOf: fileURL) == garbage)
}

@Test
func migratorLeavesCurrentVersionAlone() throws {
    let root = try upgradeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // Save through the store — already at the current version.
    let store = CaptureLibraryMetadataStore(captureRoot: root)
    try store.save(CaptureLibraryMetadataDocument())
    let fileURL = root.appendingPathComponent(
        "library-metadata.json",
        isDirectory: false
    )
    let before = try Data(contentsOf: fileURL)

    let report = LocalStateMigrator.migrate(
        captureRoot: root,
        appVersion: "2.0.0",
        appBuild: "test-build",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    // Silent on success: current-version documents emit no event.
    #expect(report.events.isEmpty)
    #expect(try Data(contentsOf: fileURL) == before)
}

@Test
func migratorJournalsEveryNonSilentEvent() throws {
    let root = try upgradeTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeLegacyLibraryMetadata(into: root)
    let garbage = Data([0x01, 0x02])
    try garbage.write(
        to: root.appendingPathComponent(
            "delivery-queue.json",
            isDirectory: false
        )
    )

    _ = LocalStateMigrator.migrate(
        captureRoot: root,
        appVersion: "2.0.0",
        appBuild: "test-build",
        nowUTC: "2026-09-22T00:00:00Z"
    )

    let journalURL = root.appendingPathComponent(
        "state-upgrade-journal.json",
        isDirectory: false
    )
    #expect(FileManager.default.fileExists(atPath: journalURL.path))
    let journal = try JSONDecoder().decode(
        LocalStateUpgradeJournal.self,
        from: Data(contentsOf: journalURL)
    )
    // One migrated + one preserved event journaled this run.
    #expect(journal.events.count == 2)
    #expect(
        Set(journal.events.map(\.outcome))
            == [.migrated, .preservedUnreadable]
    )
}
