import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #375: field notes — operator-authored supplemental context
/// bound to the scan/revision, never structured authority. Covers
/// validation, lifecycle (resolve/supersede), collection views, the
/// parent/child diff, and working-set persistence.
final class CaptureFieldNoteTests: XCTestCase {
    private let revisionID = CaptureRevisionID(
        rawValue: UUID(
            uuidString: "20000000-0000-4000-8000-000000000001"
        )!
    )

    private func makeNote(
        text: String = "speaker grille paint chipped",
        category: CaptureFieldNoteCategory = .init(
            rawValue: "equipment_state"
        ),
        needsAttention: Bool = false,
        bindingRefs: [String] = [],
        evidenceRefs: [String] = [],
        createdAtUTC: String = "2026-09-22T00:00:01Z"
    ) throws -> CaptureFieldNote {
        try CaptureFieldNote(
            captureRevisionID: revisionID,
            createdAtUTC: createdAtUTC,
            sessionTimestampSeconds: 12.5,
            category: category,
            text: text,
            needsAttention: needsAttention,
            bindingRefs: bindingRefs,
            evidenceRefs: evidenceRefs
        )
    }

    func testCategoryAcceptsWellKnownAndExtensionTokens() throws {
        XCTAssertNoThrow(
            try CaptureFieldNoteCategory(token: "equipment_state")
        )
        XCTAssertThrowsError(
            try CaptureFieldNoteCategory(token: "not_a_token")
        ) { error in
            XCTAssertEqual(
                error as? CaptureFieldNoteError,
                .invalidCategoryToken("not_a_token")
            )
        }
        let custom = try CaptureFieldNoteCategory(token: "x_rigging")
        XCTAssertTrue(custom.isExtension)
        XCTAssertEqual(
            CaptureFieldNoteCategory(rawValue: "x_rigging"),
            custom
        )
    }

    func testNoteValidationBoundsAndRefs() throws {
        XCTAssertThrowsError(try makeNote(text: "   ")) { error in
            XCTAssertEqual(
                error as? CaptureFieldNoteError, .emptyText
            )
        }
        XCTAssertThrowsError(
            try makeNote(
                text: String(repeating: "a", count: 4001)
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureFieldNoteError,
                .textTooLong(4001)
            )
        }
        // `frame:` is an evidence ref, not a binding ref.
        XCTAssertThrowsError(
            try makeNote(bindingRefs: ["frame:\(UUID())"])
        ) { error in
            guard case .invalidBindingRef =
                error as? CaptureFieldNoteError
            else {
                return XCTFail("expected invalidBindingRef")
            }
        }
        XCTAssertNoThrow(
            try makeNote(
                bindingRefs: [
                    "equipment:projector",
                    "task_item:verify-mounts",
                ],
                evidenceRefs: [
                    "frame:\(UUID().uuidString.lowercased())"
                ]
            )
        )
    }

    func testLifecycleIsTerminal() throws {
        let note = try makeNote()
        XCTAssertFalse(note.isTerminal)

        let resolved = try note.resolving()
        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertNotNil(resolved.resolvedAtUTC)
        XCTAssertTrue(resolved.isTerminal)
        XCTAssertThrowsError(try resolved.resolving()) { error in
            XCTAssertEqual(
                error as? CaptureFieldNoteError,
                .noteAlreadyTerminal
            )
        }

        let replacement = try makeNote(text: "corrected text")
        let superseded = try note.superseding(
            by: replacement.noteID
        )
        XCTAssertEqual(superseded.status, .superseded)
        XCTAssertEqual(
            superseded.supersededByNoteID, replacement.noteID
        )
        XCTAssertTrue(superseded.isTerminal)
        XCTAssertThrowsError(
            try note.superseding(by: note.noteID)
        ) { error in
            XCTAssertEqual(
                error as? CaptureFieldNoteError,
                .selfSupersession
            )
        }
    }

    func testCollectionViews() throws {
        let older = try makeNote(
            createdAtUTC: "2026-09-22T00:00:01Z"
        )
        let newer = try makeNote(
            category: .init(rawValue: "obstruction"),
            needsAttention: true,
            createdAtUTC: "2026-09-22T00:00:02Z"
        )
        let resolved = try makeNote(
            createdAtUTC: "2026-09-22T00:00:03Z"
        ).resolving()
        let collection = CaptureFieldNoteCollection(
            notes: [newer, older, resolved]
        )

        XCTAssertEqual(
            collection.chronological.map(\.noteID),
            [older.noteID, newer.noteID, resolved.noteID]
        )
        XCTAssertEqual(
            collection.unresolvedAttention.map(\.noteID),
            [newer.noteID]
        )
        XCTAssertEqual(
            collection.active.map(\.noteID),
            [older.noteID, newer.noteID]
        )
        let grouped = Dictionary(
            collection.grouped().map {
                ($0.0.rawValue, $0.1.map(\.noteID))
            },
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(
            grouped["equipment_state"],
            [older.noteID, resolved.noteID]
        )
        XCTAssertEqual(
            grouped["obstruction"],
            [newer.noteID]
        )
    }

    func testDiffClassifiesAddedSupersededResolved() throws {
        let kept = try makeNote(
            createdAtUTC: "2026-09-22T00:00:01Z"
        )
        let toResolve = try makeNote(
            createdAtUTC: "2026-09-22T00:00:02Z"
        )
        let toSupersede = try makeNote(
            createdAtUTC: "2026-09-22T00:00:03Z"
        )
        let parent = CaptureFieldNoteCollection(
            notes: [kept, toResolve, toSupersede]
        )

        let replacement = try CaptureFieldNote(
            captureRevisionID: revisionID,
            createdAtUTC: "2026-09-22T00:00:04Z",
            category: .init(rawValue: "equipment_state"),
            text: "fixed",
            supersedesNoteID: toSupersede.noteID
        )
        let added = try makeNote(
            createdAtUTC: "2026-09-22T00:00:05Z"
        )
        let child = CaptureFieldNoteCollection(
            notes: [
                kept,
                try toResolve.resolving(),
                try toSupersede.superseding(by: replacement.noteID),
                replacement,
                added,
            ]
        )
        let diff = CaptureFieldNoteDiff.compare(
            parent: parent,
            child: child
        )
        XCTAssertEqual(
            diff.added.map(\.noteID), [added.noteID]
        )
        XCTAssertEqual(
            diff.superseding.map(\.noteID),
            [replacement.noteID]
        )
        XCTAssertEqual(
            diff.superseded.map(\.noteID), [toSupersede.noteID]
        )
        XCTAssertEqual(
            diff.resolved.map(\.noteID), [toResolve.noteID]
        )
        XCTAssertEqual(
            diff.carried.map(\.noteID),
            [kept.noteID, toSupersede.noteID]
        )
    }

    // MARK: - Working-set persistence

    private func makeStore() async throws -> (
        root: URL, store: CaptureWorkingSetStore
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString, isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        return (
            root, try CaptureWorkingSetStore(rootDirectory: root)
        )
    }

    func testStorePersistsNotesAcrossReopen() async throws {
        let (root, store) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let note = try CaptureFieldNote(
            captureRevisionID: await store.identity
                .captureRevisionID,
            createdAtUTC: "2026-09-22T00:00:01Z",
            category: .init(rawValue: "equipment_state"),
            text: "speaker grille paint chipped"
        )
        try await store.recordFieldNote(note)

        // The committed document survives on disk at the reserved
        // path and decodes under the same revision identity.
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                CaptureFieldNoteDocument.path
            )
        )
        let document = try JSONDecoder().decode(
            CaptureFieldNoteDocument.self, from: data
        )
        let revision = await store.identity.captureRevisionID
        XCTAssertEqual(document.captureRevisionID, revision)
        XCTAssertEqual(document.notes, [note])
    }

    func testStoreResolveAndSupersede() async throws {
        let (root, store) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let revision = await store.identity.captureRevisionID
        func note(_ text: String, _ at: String) throws
            -> CaptureFieldNote
        {
            try CaptureFieldNote(
                captureRevisionID: revision,
                createdAtUTC: at,
                category: .init(rawValue: "equipment_state"),
                text: text
            )
        }

        let first = try note("first", "2026-09-22T00:00:01Z")
        try await store.recordFieldNote(first)
        try await store.resolveFieldNote(first.noteID)
        // A resolved note is terminal — supersession is refused.
        let replacement = try CaptureFieldNote(
            captureRevisionID: revision,
            createdAtUTC: "2026-09-22T00:00:05Z",
            category: .init(rawValue: "equipment_state"),
            text: "clarified",
            supersedesNoteID: first.noteID
        )
        do {
            try await store.supersedeFieldNote(
                first.noteID, replacement: replacement
            )
            XCTFail("superseding a resolved note must throw")
        } catch {
            XCTAssertEqual(
                error as? CaptureFieldNoteError,
                .noteAlreadyTerminal
            )
        }

        let second = try note("second", "2026-09-22T00:00:06Z")
        try await store.recordFieldNote(second)
        let secondReplacement = try CaptureFieldNote(
            captureRevisionID: revision,
            createdAtUTC: "2026-09-22T00:00:07Z",
            category: .init(rawValue: "equipment_state"),
            text: "clarified",
            supersedesNoteID: second.noteID
        )
        try await store.supersedeFieldNote(
            second.noteID, replacement: secondReplacement
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.fieldNotes.count, 3)
        let original = snapshot.fieldNotes.first {
            $0.noteID == second.noteID
        }
        XCTAssertEqual(original?.status, .superseded)
        XCTAssertEqual(
            original?.supersededByNoteID,
            secondReplacement.noteID
        )
    }
}
