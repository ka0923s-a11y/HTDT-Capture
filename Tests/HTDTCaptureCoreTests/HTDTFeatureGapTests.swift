import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issues #458/#462: the app-local operator roster store and the
/// delivery-queue filters — small workflow-completeness gaps closed
/// in the feature-gap pass.
final class HTDTFeatureGapTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func makeJob(
        state: HTDTDeliveryJobState
    ) -> HTDTDeliveryJob {
        HTDTDeliveryJob(
            deliveryJobID: "job-\(state.rawValue)",
            archiveSHA256: "aa",
            archiveByteCount: 1,
            payloadRelativePath: "delivery-queue/payloads/x",
            destination: HTDTHandoffDestination(
                name: "HTDT Mac",
                kind: .endpoint,
                url: "https://receiver.local"
            ),
            createdAtUTC: "2026-09-21T00:00:00Z",
            state: state
        )
    }

    // MARK: - Operator roster (#458)

    func testRosterMissingFileLoadsEmpty() throws {
        let root = try makeRoot()
        let store = HTDTOperatorProfileRosterStore(
            captureRoot: root
        )
        XCTAssertTrue(try store.load().operators.isEmpty)
    }

    func testRosterUpsertReplaceAndRemove() throws {
        let root = try makeRoot()
        let store = HTDTOperatorProfileRosterStore(
            captureRoot: root
        )
        let original = try OperatorProfile(
            displayName: "Aya",
            organization: "Install Co"
        )
        _ = try store.upsert(original)
        _ = try store.upsert(
            try OperatorProfile(displayName: "Ben")
        )
        XCTAssertEqual(try store.load().operators.count, 2)

        // Upsert under the same operator_id replaces, never
        // duplicates.
        let edited = try OperatorProfile(
            operatorID: original.operatorID,
            displayName: "Aya K."
        )
        _ = try store.upsert(edited)
        XCTAssertEqual(try store.load().operators.count, 2)
        XCTAssertTrue(
            try store.load().operators.contains {
                $0.operatorID == original.operatorID
                    && $0.displayName == "Aya K."
            }
        )

        _ = try store.remove(operatorID: original.operatorID)
        let remaining = try store.load().operators
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].displayName, "Ben")

        // Persistence survives a store reopen.
        let reopened = HTDTOperatorProfileRosterStore(
            captureRoot: root
        )
        XCTAssertEqual(
            try reopened.load().operators.count,
            1
        )
    }

    func testRosterCorruptFileIsSurfaced() throws {
        let root = try makeRoot()
        let store = HTDTOperatorProfileRosterStore(
            captureRoot: root
        )
        try Data("{ not json".utf8).write(
            to: store.fileURL,
            options: .atomic
        )
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(
                error as? HTDTOperatorRosterError,
                .unreadableRoster
            )
        }
    }

    // MARK: - Delivery queue filters (#462)

    func testQueueFilterMatchesJobStates() throws {
        for state in [
            HTDTDeliveryJobState.queued, .sending, .retryWait,
            .paused, .blocked,
        ] {
            let job = makeJob(state: state)
            XCTAssertTrue(HTDTDeliveryQueueFilter.all.matches(job))
            XCTAssertTrue(HTDTDeliveryQueueFilter.active.matches(job))
            XCTAssertFalse(
                HTDTDeliveryQueueFilter.delivered.matches(job)
            )
        }
        // Attention means an operator decision: blocked or failed.
        XCTAssertTrue(
            HTDTDeliveryQueueFilter.attention.matches(
                makeJob(state: .blocked)
            )
        )
        XCTAssertTrue(
            HTDTDeliveryQueueFilter.attention.matches(
                makeJob(state: .failed)
            )
        )
        XCTAssertFalse(
            HTDTDeliveryQueueFilter.attention.matches(
                makeJob(state: .queued)
            )
        )
        // Terminal-but-fine states are neither active nor attention.
        for state in [
            HTDTDeliveryJobState.deliveredStaged, .rejected,
            .cancelled, .failed,
        ] {
            XCTAssertFalse(
                HTDTDeliveryQueueFilter.active.matches(
                    makeJob(state: state)
                )
            )
        }
        XCTAssertTrue(
            HTDTDeliveryQueueFilter.delivered.matches(
                makeJob(state: .deliveredStaged)
            )
        )
    }
}
