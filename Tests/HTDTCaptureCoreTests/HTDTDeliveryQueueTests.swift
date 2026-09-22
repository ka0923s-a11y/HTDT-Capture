import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #387: durable delivery queue — enqueue pins bytes, attempts
/// are receipted, transient failures back off, semantic/pin failures
/// stop, and launch reconciliation never replays a mid-flight job
/// without its stable delivery id.
final class HTDTDeliveryQueueTests: XCTestCase {
    /// Scripted transport: each queued outcome is consumed in order;
    /// submissions are recorded so the test can assert the stable
    /// delivery id and pin traveled with every attempt.
    private actor ScriptedTransport: HTDTDeliveryTransport {
        enum Step {
            case accept(stagingRef: String?)
            case alreadyStaged
            case reject(detail: String)
            case transportError
            case httpStatus(Int)
            case pinMismatch
        }

        private var steps: [Step]
        private(set) var submissions:
            [(endpoint: URL, deliveryID: String?, pin: String?)]
            = []

        init(steps: [Step]) {
            self.steps = steps
        }

        func submit(
            archive: URL,
            archiveSHA256: EvidenceSHA256,
            archiveByteCount: Int64,
            captureRevisionID: CaptureRevisionID,
            bundleDigest: EvidenceSHA256,
            endpoint: URL,
            deliveryID: String?,
            pinnedIdentity: String?
        ) async throws -> HTDTIngestionResponse {
            submissions.append((
                endpoint: endpoint,
                deliveryID: deliveryID,
                pin: pinnedIdentity
            ))
            let step = steps.isEmpty
                ? Step.accept(stagingRef: nil)
                : steps.removeFirst()
            switch step {
            case .accept(let stagingRef):
                return HTDTIngestionResponse(
                    ingestionOutcome:
                        HTDTIngestionResponse.outcomeAccepted,
                    captureRevisionID:
                        captureRevisionID.description,
                    bundleDigest: bundleDigest.value,
                    stagingRef: stagingRef
                )
            case .alreadyStaged:
                return HTDTIngestionResponse(
                    ingestionOutcome:
                        HTDTIngestionResponse.outcomeAlreadyStaged,
                    captureRevisionID:
                        captureRevisionID.description,
                    bundleDigest: bundleDigest.value,
                    stagingRef: "st-9"
                )
            case .reject(let detail):
                return HTDTIngestionResponse(
                    ingestionOutcome:
                        HTDTIngestionResponse.outcomeRejected,
                    captureRevisionID:
                        captureRevisionID.description,
                    bundleDigest: bundleDigest.value,
                    detail: detail
                )
            case .transportError:
                throw HTDTHandoffError.transportFailed(
                    "simulated transport failure"
                )
            case .httpStatus(let code):
                throw HTDTHandoffError.endpointRejected(
                    statusCode: code
                )
            case .pinMismatch:
                throw HTDTHandoffError.pinnedIdentityMismatch
            }
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private struct Fixture {
        let archiveURL: URL
        let archiveSHA: EvidenceSHA256
        let archiveBytes: Int64
        let revisionID: CaptureRevisionID
        let seriesID: CaptureSeriesID
        let bundleDigest: EvidenceSHA256
        let destination: HTDTHandoffDestination
    }

    private func makeFixture(in root: URL) throws -> Fixture {
        let archiveURL = root.appendingPathComponent(
            "capture.htdtcapture"
        )
        let bytes = Data(
            (0..<4096).map { UInt8($0 % 251) }
        )
        try bytes.write(to: archiveURL)
        return Fixture(
            archiveURL: archiveURL,
            archiveSHA: EvidenceIntegrity.sha256(of: bytes),
            archiveBytes: Int64(bytes.count),
            revisionID: CaptureRevisionID(),
            seriesID: CaptureSeriesID(),
            bundleDigest: EvidenceIntegrity.sha256(
                of: Data("bundle".utf8)
            ),
            destination: HTDTHandoffDestination(
                name: "Stage Mac",
                kind: .endpoint,
                url: "https://receiver.local:8443/ingest"
            )
        )
    }

    func testEnqueuePersistsAndCopiesPayload() throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: ScriptedTransport(steps: [])
        )
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )
        XCTAssertEqual(job.state, .queued)
        XCTAssertEqual(job.attemptCount, 0)
        // The queue owns a payload copy that survives the original
        // export archive being deleted.
        let payloadURL = root.appendingPathComponent(
            job.payloadRelativePath
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: payloadURL.path)
        )
        XCTAssertEqual(
            try queue.jobs().count,
            1
        )
        // Reopening the store shows the job — persistence is real.
        let reloaded = HTDTDeliveryQueue(captureRoot: root)
        XCTAssertEqual(
            try reloaded.jobs().first?.deliveryJobID,
            job.deliveryJobID
        )
    }

    func testEnqueueRejectsWrongIdentity() throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let queue = HTDTDeliveryQueue(captureRoot: root)
        XCTAssertThrowsError(
            try queue.enqueue(
                captureRevisionID: fixture.revisionID,
                captureSeriesID: fixture.seriesID,
                bundleDigest: fixture.bundleDigest,
                archiveSHA256: EvidenceIntegrity.sha256(
                    of: Data("other".utf8)
                ),
                archiveByteCount: fixture.archiveBytes,
                archiveURL: fixture.archiveURL,
                destination: fixture.destination
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTDeliveryQueueError,
                .archiveIdentityMismatch
            )
        }
    }

    func testAcceptedDeliveryStagesAndReceipts() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(
            steps: [.accept(stagingRef: "st-42")]
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        let receiptStore = HTDTHandoffReceiptStore(
            captureRoot: root
        )
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination,
            missionRecordID: "mission-rec-1"
        )
        let jobs = await queue.processDueJobs(
            receiptStore: receiptStore
        )
        XCTAssertEqual(jobs.first?.state, .deliveredStaged)
        XCTAssertEqual(
            jobs.first?.serverStagingRef,
            "st-42"
        )

        let receipts = try receiptStore.receipts(
            for: fixture.revisionID
        )
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].outcome, "delivered")
        XCTAssertEqual(receipts[0].deliveryJobID, job.deliveryJobID)
        XCTAssertTrue(
            receipts[0].detail?.contains("staging_ref=st-42")
                == true
        )

        // The stable delivery id traveled with the submission —
        // a retry of the same job is idempotent at the receiver.
        let submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(
            submissions[0].deliveryID,
            job.deliveryJobID
        )
    }

    func testSemanticRejectionIsTerminal() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(
            steps: [.reject(detail: "bundle version unsupported")]
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        _ = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )
        let jobs = await queue.processDueJobs()
        XCTAssertEqual(jobs.first?.state, .rejected)
        XCTAssertTrue(jobs.first?.isTerminal == true)
        // Rejected jobs never retry — no blind resend of a
        // semantically refused bundle.
        let again = await queue.processDueJobs()
        XCTAssertEqual(again.first?.state, .rejected)
        let submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 1)
    }

    func testTransientFailureRetriesWithSameDeliveryID() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(
            steps: [.transportError, .alreadyStaged]
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )
        // First pass: transient error -> retry_wait with a future
        // nextAttempt and NO reprocessing in the same run.
        var now = "2026-09-22T00:00:00Z"
        var jobs = await queue.processDueJobs(nowUTC: now)
        XCTAssertEqual(jobs.first?.state, .retryWait)
        XCTAssertEqual(jobs.first?.attemptCount, 1)
        XCTAssertNotNil(jobs.first?.nextAttemptAtUTC)
        jobs = await queue.processDueJobs(nowUTC: now)
        var submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 1)

        // After the backoff elapses the retry runs with the same
        // delivery id; the receiver's already_staged resolves
        // idempotently into delivered_staged.
        now = "2026-09-22T01:00:00Z"
        jobs = await queue.processDueJobs(nowUTC: now)
        XCTAssertEqual(jobs.first?.state, .deliveredStaged)
        XCTAssertEqual(jobs.first?.attemptCount, 2)
        submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 2)
        XCTAssertEqual(
            submissions[1].deliveryID,
            job.deliveryJobID
        )
    }

    func testPinMismatchBlocksForOperatorDecision() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(steps: [.pinMismatch])
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        _ = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination,
            pairedDestinationID: "dest-1"
        )
        let jobs = await queue.processDueJobs()
        // A pinned-identity mismatch is never retried blindly — it
        // means the receiver's certificate changed since pairing.
        XCTAssertEqual(jobs.first?.state, .blocked)
        let submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 1)
    }

    func testLaunchReconcileReschedulesSendingJob() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(
            steps: [.accept(stagingRef: nil)]
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )

        // Forge the "app died mid-send" state: a persisted `sending`
        // job — private mutation is unavailable, so rewrite the
        // ledger file the same way the store writes it.
        var document = try queue.load()
        var sending = document.jobs[0]
        sending.state = .sending
        document.jobs[0] = sending
        let data = try JSONEncoder().encode(document)
        let tmp = queue.fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: queue.fileURL)
        try FileManager.default.moveItem(
            at: tmp,
            to: queue.fileURL
        )

        let reconciled = try queue.reconcileOnLaunch(
            nowUTC: "2026-09-22T00:00:00Z"
        )
        XCTAssertEqual(reconciled.first?.state, .retryWait)
        // The attempt count is NOT bumped by reconcile — the
        // in-flight attempt's outcome was unknown, so the retry
        // carries the same idempotency identity.
        XCTAssertEqual(
            reconciled.first?.attemptCount,
            job.attemptCount
        )

        // And the rescheduled job eventually completes.
        let jobs = await queue.processDueJobs(
            nowUTC: "2026-09-22T02:00:00Z"
        )
        XCTAssertEqual(jobs.first?.state, .deliveredStaged)
    }

    func testLaunchReconcileBlocksOnMissingPayload() throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let queue = HTDTDeliveryQueue(captureRoot: root)
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )
        try FileManager.default.removeItem(
            at: root.appendingPathComponent(job.payloadRelativePath)
        )
        let jobs = try queue.reconcileOnLaunch()
        XCTAssertEqual(jobs.first?.state, .blocked)
        XCTAssertEqual(jobs.first?.lastError, "payload_missing")
    }

    func testPauseResumeCancelAndPurge() async throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let transport = ScriptedTransport(
            steps: [.transportError]
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root,
            transport: transport
        )
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )

        // Pause blocks processing entirely.
        try queue.pause(jobID: job.deliveryJobID)
        var jobs = await queue.processDueJobs()
        XCTAssertEqual(jobs.first?.state, .paused)
        var submissions = await transport.submissions
        XCTAssertTrue(submissions.isEmpty)

        // Resume requeues; the attempt then runs.
        try queue.resume(jobID: job.deliveryJobID)
        jobs = await queue.processDueJobs()
        XCTAssertEqual(jobs.first?.state, .retryWait)
        submissions = await transport.submissions
        XCTAssertEqual(submissions.count, 1)

        // Cancel is terminal and drops the payload copy.
        try queue.cancel(jobID: job.deliveryJobID)
        XCTAssertEqual(
            try queue.jobs().first?.state,
            .cancelled
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    job.payloadRelativePath
                ).path
            )
        )
        // purgePayload refuses only while a job still needs bytes.
        XCTAssertThrowsError(
            try queue.purgePayload(jobID: "nope")
        )
    }

    func testPayloadPinningQuery() throws {
        let root = try makeRoot()
        let fixture = try makeFixture(in: root)
        let queue = HTDTDeliveryQueue(captureRoot: root)
        let job = try queue.enqueue(
            captureRevisionID: fixture.revisionID,
            captureSeriesID: fixture.seriesID,
            bundleDigest: fixture.bundleDigest,
            archiveSHA256: fixture.archiveSHA,
            archiveByteCount: fixture.archiveBytes,
            archiveURL: fixture.archiveURL,
            destination: fixture.destination
        )
        XCTAssertEqual(
            try queue.activeJobsPinningArchive(
                archiveSHA256: fixture.archiveSHA.value
            ).first?.deliveryJobID,
            job.deliveryJobID
        )
    }
}
