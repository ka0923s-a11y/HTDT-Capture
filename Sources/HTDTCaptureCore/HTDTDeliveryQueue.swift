import Foundation

extension BundleTimestamp {
    /// Parses a `utcString` back to a Date for backoff arithmetic.
    public static func date(from utcString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = formatter.date(from: utcString) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        fractional.timeZone = TimeZone(secondsFromGMT: 0)
        return fractional.date(from: utcString)
    }
}

/// Lifecycle of one durable delivery job (issue #387). `delivered`
/// means *staged at the receiver* — never promoted to a pipeline
/// stage the receiver did not report.
public enum HTDTDeliveryJobState: String, Codable, Sendable {
    /// Durable and waiting for its first/next attempt.
    case queued
    /// Attempt in flight. On app relaunch this state is reconciled
    /// back to `retryWait` — the app never claims an interrupted
    /// upload finished.
    case sending
    /// Waiting out the retry backoff before the next attempt.
    case retryWait = "retry_wait"
    /// Operator-paused; stays until manually resumed.
    case paused
    /// Needs an operator decision: destination identity changed
    /// (pin mismatch), payload missing/mutated, or the endpoint is
    /// not a valid HTTPS receiver.
    case blocked
    /// Receiver accepted the bytes for staging. Distinct from
    /// pipeline "promotion" — staging is all the sender can claim.
    case deliveredStaged = "delivered_staged"
    /// Receiver rejected the bundle semantically — terminal; never
    /// auto-retried.
    case rejected
    /// Operator cancelled before delivery — terminal.
    case cancelled
    /// Retry budget exhausted — terminal until manually re-enqueued.
    case failed
}

/// A durable, per-archive delivery job (issue #387). The job is
/// persisted *before* any bytes move, pins the archive identity it
/// was created from (digest + byte count), owns a private copy of
/// the payload under `delivery-queue/payloads/`, and is idempotent
/// at the receiver via the stable `deliveryJobID` sent as
/// `X-HTDT-Delivery-ID`.
public struct HTDTDeliveryJob: Codable, Sendable, Equatable, Identifiable {
    /// Stable job identity — also the idempotency key the receiver
    /// uses to recognize a retried delivery as the same one.
    public let deliveryJobID: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    /// Digest the validated export was proven to carry.
    public let bundleDigest: String
    /// SHA-256 and size of the archive bytes at enqueue time; the
    /// queue-owned payload copy is re-verified against these before
    /// every attempt.
    public let archiveSHA256: String
    public let archiveByteCount: Int64
    /// Queue-owned payload, relative to the capture root
    /// (`delivery-queue/payloads/<job id>.htdtcapture`). The copy is
    /// what actually uploads, so deleting the operator-visible export
    /// never mutates an in-flight send.
    public let payloadRelativePath: String
    /// Original export filename, for display only.
    public let sourceArchiveName: String?
    public let destination: HTDTHandoffDestination
    /// Paired receiver's destination id when the job targets a
    /// QR-paired endpoint (#379); its pin is applied at send time.
    public let pairedDestinationID: String?
    /// Mission record this delivery satisfies (#386), if any.
    public let missionRecordID: String?
    /// Compatibility summary recorded at enqueue/preflight time so
    /// the queue row can show why a send was allowed to proceed with
    /// named omissions (#374).
    public let compatibilitySummary: String?
    public let createdAtUTC: String
    public var lastAttemptAtUTC: String?
    /// UTC timestamp before which a `retry_wait` job must not run.
    public var nextAttemptAtUTC: String?
    public var attemptCount: Int
    public var state: HTDTDeliveryJobState
    /// Machine-readable classification of the last failure, e.g.
    /// `transport`, `http_5xx`, `semantic_rejected`, `pin_mismatch`.
    public var lastError: String?
    /// Operator-facing detail of the last failure/decision.
    public var lastErrorDetail: String?
    /// Last appended receipt id for audit cross-reference.
    public var lastReceiptID: String?
    /// Receiver-reported staging slot once delivered.
    public var serverStagingRef: String?

    public init(
        deliveryJobID: String,
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        bundleDigest: String,
        archiveSHA256: String,
        archiveByteCount: Int64,
        payloadRelativePath: String,
        sourceArchiveName: String? = nil,
        destination: HTDTHandoffDestination,
        pairedDestinationID: String? = nil,
        missionRecordID: String? = nil,
        compatibilitySummary: String? = nil,
        createdAtUTC: String,
        lastAttemptAtUTC: String? = nil,
        nextAttemptAtUTC: String? = nil,
        attemptCount: Int = 0,
        state: HTDTDeliveryJobState = .queued,
        lastError: String? = nil,
        lastErrorDetail: String? = nil,
        lastReceiptID: String? = nil,
        serverStagingRef: String? = nil
    ) {
        self.deliveryJobID = deliveryJobID
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.bundleDigest = bundleDigest
        self.archiveSHA256 = archiveSHA256
        self.archiveByteCount = archiveByteCount
        self.payloadRelativePath = payloadRelativePath
        self.sourceArchiveName = sourceArchiveName
        self.destination = destination
        self.pairedDestinationID = pairedDestinationID
        self.missionRecordID = missionRecordID
        self.compatibilitySummary = compatibilitySummary
        self.createdAtUTC = createdAtUTC
        self.lastAttemptAtUTC = lastAttemptAtUTC
        self.nextAttemptAtUTC = nextAttemptAtUTC
        self.attemptCount = attemptCount
        self.state = state
        self.lastError = lastError
        self.lastErrorDetail = lastErrorDetail
        self.lastReceiptID = lastReceiptID
        self.serverStagingRef = serverStagingRef
    }

    public var id: String { deliveryJobID }

    /// Terminal states — the job keeps its record and receipts but
    /// will never move again without an explicit operator action.
    public var isTerminal: Bool {
        switch state {
        case .deliveredStaged, .rejected, .cancelled, .failed:
            return true
        case .queued, .sending, .retryWait, .paused, .blocked:
            return false
        }
    }

    /// True while the job still needs its queue-owned payload copy —
    /// the archive the export-delete flow must not silently orphan
    /// mid-flight (#387).
    public var needsPayload: Bool {
        switch state {
        case .queued, .sending, .retryWait, .paused, .blocked:
            return true
        case .deliveredStaged, .rejected, .cancelled, .failed:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case deliveryJobID = "delivery_job_id"
        case captureRevisionID = "capture_revision_id"
        case captureSeriesID = "capture_series_id"
        case bundleDigest = "bundle_digest"
        case archiveSHA256 = "archive_sha256"
        case archiveByteCount = "archive_byte_count"
        case payloadRelativePath = "payload_relative_path"
        case sourceArchiveName = "source_archive_name"
        case destination
        case pairedDestinationID = "paired_destination_id"
        case missionRecordID = "mission_record_id"
        case compatibilitySummary = "compatibility_summary"
        case createdAtUTC = "created_at"
        case lastAttemptAtUTC = "last_attempt_at"
        case nextAttemptAtUTC = "next_attempt_at"
        case attemptCount = "attempt_count"
        case state
        case lastError = "last_error"
        case lastErrorDetail = "last_error_detail"
        case lastReceiptID = "last_receipt_id"
        case serverStagingRef = "server_staging_ref"
    }
}

/// Retry classification (issue #387): transient transport and
/// receiver-busy statuses back off and retry; semantic rejections,
/// identity failures and receipt mismatches never retry blindly.
public struct HTDTDeliveryRetryPolicy: Sendable, Equatable {
    public var baseIntervalSeconds: TimeInterval = 30
    public var backoffMultiplier: Double = 2
    public var maxIntervalSeconds: TimeInterval = 1800
    /// Total attempts before the job is declared `failed`.
    public var maxAttempts: Int = 8

    public init() {}

    /// Exponential backoff for attempt `attempt` (1-based).
    public func nextAttemptDelay(after attempt: Int) -> TimeInterval {
        let factor = pow(
            backoffMultiplier,
            Double(max(attempt - 1, 0))
        )
        return min(
            baseIntervalSeconds * factor,
            maxIntervalSeconds
        )
    }

    /// True when the error is plausibly transient — connection
    /// failures and HTTP 5xx / 408 / 429. Semantic rejections
    /// (`serverRejected`), TLS/pin mismatches, digest mismatches and
    /// malformed receipts are permanent until an operator acts.
    public static func isRetryable(_ error: Error) -> Bool {
        guard let handoff = error as? HTDTHandoffError else {
            // URLSession-level failures are transient by definition.
            return true
        }
        switch handoff {
        case .transportFailed:
            return true
        case .endpointRejected(let statusCode):
            return statusCode >= 500
                || statusCode == 408
                || statusCode == 429
        case .invalidEndpointURL,
             .archiveIdentityMismatch,
             .serverRejected,
             .malformedServerReceipt,
             .pinnedIdentityMismatch:
            return false
        }
    }

    /// Machine-readable classification for `HTDTDeliveryJob.lastError`.
    public static func errorKind(_ error: Error) -> String {
        guard let handoff = error as? HTDTHandoffError else {
            return "transport"
        }
        switch handoff {
        case .transportFailed: return "transport"
        case .endpointRejected(let statusCode):
            if statusCode >= 500 || statusCode == 408
                || statusCode == 429
            {
                return "http_transient"
            }
            return "http_rejected"
        case .invalidEndpointURL: return "invalid_endpoint"
        case .archiveIdentityMismatch: return "identity_mismatch"
        case .serverRejected: return "semantic_rejected"
        case .malformedServerReceipt: return "malformed_receipt"
        case .pinnedIdentityMismatch: return "pin_mismatch"
        }
    }

    /// Errors that strand the job in `blocked` rather than `failed` —
    /// operator-decision states where the fix is re-pairing or fixing
    /// the destination, not giving up or retrying.
    public static func isOperatorDecision(_ error: Error) -> Bool {
        guard let handoff = error as? HTDTHandoffError else {
            return false
        }
        switch handoff {
        case .invalidEndpointURL, .pinnedIdentityMismatch:
            return true
        case .transportFailed, .endpointRejected,
             .archiveIdentityMismatch, .serverRejected,
             .malformedServerReceipt:
            return false
        }
    }
}

/// Transport seam for delivery attempts — `HTDTHandoffClient` in
/// production, a stub in tests. Keeps the queue engine free of
/// URLSession so resume/retry policy is testable offline (#387).
public protocol HTDTDeliveryTransport: Sendable {
    func submit(
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        endpoint: URL,
        deliveryID: String?,
        pinnedIdentity: String?
    ) async throws -> HTDTIngestionResponse
}

public struct HTDTHandoffDeliveryTransport: HTDTDeliveryTransport {
    public init() {}

    public func submit(
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        endpoint: URL,
        deliveryID: String?,
        pinnedIdentity: String?
    ) async throws -> HTDTIngestionResponse {
        try await HTDTHandoffClient().submit(
            archive: archive,
            archiveSHA256: archiveSHA256,
            archiveByteCount: archiveByteCount,
            captureRevisionID: captureRevisionID,
            bundleDigest: bundleDigest,
            endpoint: endpoint,
            deliveryID: deliveryID,
            pinnedIdentity: pinnedIdentity
        )
    }
}

/// Errors raised by queue management itself (distinct from per-attempt
/// `HTDTHandoffError`s recorded on the job).
public enum HTDTDeliveryQueueError: Error, Sendable, Equatable {
    /// The export archive is missing, unreadable, or its identity does
    /// not match what the caller claims — the queue refuses to create
    /// a job that would pin the wrong bytes.
    case archiveIdentityMismatch
    case archiveNotFound(String)
    case unknownJob(String)
    /// The job exists but is in a state the requested transition does
    /// not allow (e.g. retrying a delivered job).
    case invalidJobState(String)
    /// The persisted queue document is missing required invariants.
    case unreadableDocument
}

/// Durable delivery queue (issue #387):
/// `<captureRoot>/delivery-queue.json` holds the job ledger and
/// `<captureRoot>/delivery-queue/payloads/` holds queue-owned archive
/// copies. Every mutation is persisted via the same atomic
/// temp+replace write as the other capture-root stores, so a kill or
/// crash mid-send leaves the ledger consistent.
public struct HTDTDeliveryQueue: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.delivery-queue"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var jobs: [HTDTDeliveryJob]

        public init(jobs: [HTDTDeliveryJob] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.jobs = jobs
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case jobs
        }
    }

    public let captureRoot: URL
    public let transport: any HTDTDeliveryTransport
    public let retryPolicy: HTDTDeliveryRetryPolicy

    public var fileURL: URL {
        captureRoot.appendingPathComponent(
            "delivery-queue.json",
            isDirectory: false
        )
    }

    public var payloadDirectory: URL {
        captureRoot.appendingPathComponent(
            "delivery-queue/payloads",
            isDirectory: true
        )
    }

    public init(
        captureRoot: URL,
        transport: any HTDTDeliveryTransport =
            HTDTHandoffDeliveryTransport(),
        retryPolicy: HTDTDeliveryRetryPolicy = HTDTDeliveryRetryPolicy()
    ) {
        self.captureRoot = captureRoot
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    public func load() throws -> Document {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return Document()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                Document.self,
                from: data
              ),
              document.schema == Document.schema,
              document.schemaVersion == Document.schemaVersion
        else {
            throw HTDTDeliveryQueueError.unreadableDocument
        }
        return document
    }

    public func jobs() throws -> [HTDTDeliveryJob] {
        try load().jobs
    }

    public func job(id: String) throws -> HTDTDeliveryJob? {
        try load().jobs.first { $0.deliveryJobID == id }
    }

    /// Enqueue a finalized archive for delivery. The archive's
    /// identity is verified (sha256 + byte count), the payload is
    /// copied into queue-owned storage, and only then is the durable
    /// job record persisted — so a crash between steps can never
    /// produce a job pointing at bytes that were never staged.
    @discardableResult
    public func enqueue(
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        bundleDigest: EvidenceSHA256,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        archiveURL: URL,
        destination: HTDTHandoffDestination,
        pairedDestinationID: String? = nil,
        missionRecordID: String? = nil,
        compatibilitySummary: String? = nil,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> HTDTDeliveryJob {
        guard FileManager.default.fileExists(
            atPath: archiveURL.path
        ) else {
            throw HTDTDeliveryQueueError.archiveNotFound(
                archiveURL.lastPathComponent
            )
        }
        let (digest, byteCount) = try BundleFileReader.sha256(
            archiveURL,
            maxBytes: Int64.max
        )
        guard digest == archiveSHA256,
              byteCount == archiveByteCount
        else {
            throw HTDTDeliveryQueueError.archiveIdentityMismatch
        }
        let jobID = UUID().uuidString.lowercased()
        let payloadRelativePath =
            "delivery-queue/payloads/" + jobID + ".htdtcapture"
        let payloadURL = captureRoot.appendingPathComponent(
            payloadRelativePath,
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: payloadDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: archiveURL,
            to: payloadURL
        )
        let job = HTDTDeliveryJob(
            deliveryJobID: jobID,
            captureRevisionID: captureRevisionID,
            captureSeriesID: captureSeriesID,
            bundleDigest: bundleDigest.value,
            archiveSHA256: archiveSHA256.value,
            archiveByteCount: archiveByteCount,
            payloadRelativePath: payloadRelativePath,
            sourceArchiveName: archiveURL.lastPathComponent,
            destination: destination,
            pairedDestinationID: pairedDestinationID,
            missionRecordID: missionRecordID,
            compatibilitySummary: compatibilitySummary,
            createdAtUTC: nowUTC
        )
        var document = try load()
        document.jobs.append(job)
        try save(document)
        return job
    }

    /// On app launch: any job that was `sending` when the app last
    /// exited is reconciled to `retry_wait` — the attempt outcome is
    /// unknown, and re-sending the same delivery id is idempotent at
    /// the receiver. Jobs whose queue-owned payload vanished or no
    /// longer matches its pinned identity are `blocked` for operator
    /// review rather than sent.
    @discardableResult
    public func reconcileOnLaunch(
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> [HTDTDeliveryJob] {
        var document = try load()
        var changed = false
        for index in document.jobs.indices {
            var job = document.jobs[index]
            let payloadURL = captureRoot.appendingPathComponent(
                job.payloadRelativePath,
                isDirectory: false
            )
            if job.needsPayload {
                guard FileManager.default.fileExists(
                    atPath: payloadURL.path
                ) else {
                    job.state = .blocked
                    job.lastError = "payload_missing"
                    job.lastErrorDetail =
                        "The queued archive copy was removed."
                    job.nextAttemptAtUTC = nil
                    document.jobs[index] = job
                    changed = true
                    continue
                }
                let identity = try? BundleFileReader.sha256(
                    payloadURL,
                    maxBytes: Int64.max
                )
                guard let identity,
                      identity.digest.value == job.archiveSHA256,
                      identity.byteCount == job.archiveByteCount
                else {
                    job.state = .blocked
                    job.lastError = "payload_mutated"
                    job.lastErrorDetail =
                        "The queued archive copy no longer matches "
                        + "the pinned identity."
                    job.nextAttemptAtUTC = nil
                    document.jobs[index] = job
                    changed = true
                    continue
                }
            }
            if job.state == .sending {
                job.state = .retryWait
                job.nextAttemptAtUTC = nextAttemptUTC(
                    after: job.attemptCount,
                    from: nowUTC
                )
                job.lastErrorDetail =
                    "App exited mid-transfer; retry scheduled."
                document.jobs[index] = job
                changed = true
            }
        }
        if changed {
            try save(document)
        }
        return document.jobs
    }

    /// Runs every due job once: `queued`, and `retry_wait` whose
    /// backoff elapsed. Each attempt re-verifies the pinned payload
    /// identity before sending, sends the stable delivery id for
    /// idempotency, applies the receiver pin when the destination is
    /// paired, and appends an `HTDTHandoffReceipt` for the attempt.
    /// Returns the updated job list.
    @discardableResult
    public func processDueJobs(
        receiptStore: HTDTHandoffReceiptStore? = nil,
        nowUTC: String = BundleTimestamp.utcString(from: Date()),
        onRepairPlan: ((HTDTRepairTaskPlan, String?) -> Void)? = nil
    ) async -> [HTDTDeliveryJob] {
        var document: Document
        do {
            document = try load()
        } catch {
            return []
        }
        for index in document.jobs.indices {
            var job = document.jobs[index]
            let due: Bool
            switch job.state {
            case .queued:
                due = true
            case .retryWait:
                due = job.nextAttemptAtUTC == nil
                    || job.nextAttemptAtUTC! <= nowUTC
            case .sending, .paused, .blocked, .deliveredStaged,
                 .rejected, .cancelled, .failed:
                due = false
            }
            guard due else { continue }

            let payloadURL = captureRoot.appendingPathComponent(
                job.payloadRelativePath,
                isDirectory: false
            )
            job.state = .sending
            job.attemptCount += 1
            job.lastAttemptAtUTC = nowUTC
            job.nextAttemptAtUTC = nil
            document.jobs[index] = job
            try? save(document)

            let result = await attempt(job: job, payloadURL: payloadURL)
            job = document.jobs[index]
            job = apply(
                result: result,
                to: job,
                nowUTC: nowUTC
            )
            document.jobs[index] = job
            try? save(document)
            var receiptID: String? = nil
            if let receiptStore,
               let receipt = result.receipt(for: job)
            {
                try? receiptStore.append(receipt)
                receiptID = receipt.receiptID
            }
            if let plan = result.response?.repairTaskPlan {
                // #321: surface a returned repair plan alongside the
                // receipt id so the caller can bind the audit link.
                onRepairPlan?(plan, receiptID)
            }
        }
        return document.jobs
    }

    /// Operator controls (issue #387): retry skips the remaining
    /// backoff, pause halts a retryable job, resume requeues it,
    /// cancel marks it terminal and drops the queue-owned payload.
    public func retryNow(jobID: String) throws {
        try mutate(jobID: jobID) { job in
            guard !job.isTerminal, job.state != .sending else {
                throw HTDTDeliveryQueueError.invalidJobState(
                    "retry requires a non-terminal, idle job"
                )
            }
            job.state = .queued
            job.nextAttemptAtUTC = nil
            job.lastError = nil
            job.lastErrorDetail = nil
        }
    }

    public func pause(jobID: String) throws {
        try mutate(jobID: jobID) { job in
            guard job.state == .queued || job.state == .retryWait else {
                throw HTDTDeliveryQueueError.invalidJobState(
                    "pause requires a queued or waiting job"
                )
            }
            job.state = .paused
            job.nextAttemptAtUTC = nil
        }
    }

    public func resume(jobID: String) throws {
        try mutate(jobID: jobID) { job in
            guard job.state == .paused || job.state == .blocked else {
                throw HTDTDeliveryQueueError.invalidJobState(
                    "resume requires a paused or blocked job"
                )
            }
            job.state = .queued
            job.lastError = nil
            job.lastErrorDetail = nil
        }
    }

    public func cancel(jobID: String) throws {
        var document = try load()
        guard let index = document.jobs.firstIndex(where: {
            $0.deliveryJobID == jobID
        }) else {
            throw HTDTDeliveryQueueError.unknownJob(jobID)
        }
        var job = document.jobs[index]
        guard !job.isTerminal else {
            throw HTDTDeliveryQueueError.invalidJobState(
                "job already terminal"
            )
        }
        job.state = .cancelled
        job.nextAttemptAtUTC = nil
        document.jobs[index] = job
        try save(document)
        removePayload(for: job)
    }

    /// Deletes the queue-owned payload copy of a terminal or
    /// delivered job; refuses for jobs that still need it.
    public func purgePayload(jobID: String) throws {
        guard let job = try job(id: jobID) else {
            throw HTDTDeliveryQueueError.unknownJob(jobID)
        }
        guard !job.needsPayload else {
            throw HTDTDeliveryQueueError.invalidJobState(
                "job still needs its payload"
            )
        }
        removePayload(for: job)
    }

    /// Non-terminal jobs that still pin the given archive digest —
    /// the export-delete flow surfaces these instead of silently
    /// deleting bytes a pending send depends on (#387).
    public func activeJobsPinningArchive(
        archiveSHA256: String
    ) throws -> [HTDTDeliveryJob] {
        try load().jobs.filter {
            $0.archiveSHA256 == archiveSHA256 && $0.needsPayload
        }
    }

    /// Jobs that must keep a queue payload; their original export may
    /// already have been deleted.
    public func pendingJobs() throws -> [HTDTDeliveryJob] {
        try load().jobs.filter { !$0.isTerminal }
    }

    // MARK: - Attempt execution

    private struct AttemptResult {
        let response: HTDTIngestionResponse?
        let error: Error?
        let receiptOutcome: String
        let receiptDetail: String?

        init(
            response: HTDTIngestionResponse?,
            error: Error?,
            receiptOutcome: String,
            receiptDetail: String?
        ) {
            self.response = response
            self.error = error
            self.receiptOutcome = receiptOutcome
            self.receiptDetail = receiptDetail
        }

        func receipt(for job: HTDTDeliveryJob) -> HTDTHandoffReceipt? {
            HTDTHandoffReceipt(
                receiptID: UUID().uuidString.lowercased(),
                captureRevisionID: job.captureRevisionID,
                captureSeriesID: job.captureSeriesID,
                bundleDigest: job.bundleDigest,
                archiveSHA256: job.archiveSHA256,
                archiveByteCount: job.archiveByteCount,
                destination: job.destination,
                initiatedAtUTC: job.lastAttemptAtUTC
                    ?? BundleTimestamp.utcString(from: Date()),
                outcome: receiptOutcome,
                detail: receiptDetail,
                pairedDestinationID: job.pairedDestinationID,
                deliveryJobID: job.deliveryJobID
            )
        }
    }

    private func attempt(
        job: HTDTDeliveryJob,
        payloadURL: URL
    ) async -> AttemptResult {
        // Re-verify the pinned identity before every attempt — the
        // queue sends only the bytes it recorded (#387).
        guard let (digest, byteCount) = try? BundleFileReader.sha256(
            payloadURL,
            maxBytes: Int64.max
        ), digest.value == job.archiveSHA256,
            byteCount == job.archiveByteCount
        else {
            return AttemptResult(
                response: nil,
                error: HTDTDeliveryQueueError.archiveIdentityMismatch,
                receiptOutcome: "failed",
                receiptDetail: "queued payload failed identity check"
            )
        }
        guard let endpointText = job.destination.url,
              let endpoint = URL(string: endpointText)
        else {
            return AttemptResult(
                response: nil,
                error: HTDTHandoffError.invalidEndpointURL,
                receiptOutcome: "failed",
                receiptDetail: "destination has no HTTPS endpoint"
            )
        }
        var pinnedIdentity: String?
        if job.pairedDestinationID != nil {
            pinnedIdentity = try? PairedHTDTDestinationStore(
                captureRoot: captureRoot
            ).load().destinations.first {
                $0.destinationID == job.pairedDestinationID
            }?.pinnedIdentity
        }
        do {
            let response = try await transport.submit(
                archive: payloadURL,
                archiveSHA256: digest,
                archiveByteCount: byteCount,
                captureRevisionID: job.captureRevisionID,
                bundleDigest: try EvidenceSHA256(job.bundleDigest),
                endpoint: endpoint,
                deliveryID: job.deliveryJobID,
                pinnedIdentity: pinnedIdentity
            )
            var detailParts: [String] = []
            if response.ingestionOutcome
                == HTDTIngestionResponse.outcomeAlreadyStaged
            {
                detailParts.append("already_staged")
            }
            if let stagingRef = response.stagingRef {
                detailParts.append("staging_ref=" + stagingRef)
            }
            if let detail = response.detail {
                detailParts.append(detail)
            }
            return AttemptResult(
                response: response,
                error: nil,
                receiptOutcome: response.ingestionOutcome
                    == HTDTIngestionResponse.outcomeRejected
                    ? "failed" : "delivered",
                receiptDetail: detailParts.isEmpty
                    ? nil : detailParts.joined(separator: " ")
            )
        } catch {
            return AttemptResult(
                response: nil,
                error: error,
                receiptOutcome: "failed",
                receiptDetail: String(describing: error)
            )
        }
    }

    /// Classifies the attempt into the job's next state (issue #387):
    /// `delivered_staged` only on an explicit receiver ack — never a
    /// promotion claim; semantic rejection terminal; transient errors
    /// re-schedule within the retry budget; pin/endpoint problems
    /// block for an operator decision.
    private func apply(
        result: AttemptResult,
        to job: HTDTDeliveryJob,
        nowUTC: String
    ) -> HTDTDeliveryJob {
        var job = job
        if let response = result.response {
            switch response.ingestionOutcome {
            case HTDTIngestionResponse.outcomeAccepted,
                 HTDTIngestionResponse.outcomeAlreadyStaged:
                job.state = .deliveredStaged
                job.serverStagingRef = response.stagingRef
                job.lastError = nil
                job.lastErrorDetail = response.ingestionOutcome
                    == HTDTIngestionResponse.outcomeAlreadyStaged
                    ? "Receiver already held this exact delivery."
                    : nil
            case HTDTIngestionResponse.outcomeRejected:
                job.state = .rejected
                job.lastError = "semantic_rejected"
                job.lastErrorDetail = response.detail
            default:
                job.state = .failed
                job.lastError = "malformed_receipt"
                job.lastErrorDetail =
                    "Receiver returned an unknown outcome."
            }
            return job
        }
        guard let error = result.error else {
            job.state = .failed
            job.lastError = "unknown"
            return job
        }
        if let queueError = error as? HTDTDeliveryQueueError,
           queueError == .archiveIdentityMismatch
        {
            job.state = .blocked
            job.lastError = "payload_mutated"
            job.lastErrorDetail =
                "The queued archive copy no longer matches the "
                + "pinned identity."
            return job
        }
        if HTDTDeliveryRetryPolicy.isOperatorDecision(error) {
            job.state = .blocked
            job.lastError = HTDTDeliveryRetryPolicy.errorKind(error)
            job.lastErrorDetail = String(describing: error)
            return job
        }
        if HTDTDeliveryRetryPolicy.isRetryable(error) {
            job.lastError = HTDTDeliveryRetryPolicy.errorKind(error)
            job.lastErrorDetail = String(describing: error)
            if job.attemptCount >= retryPolicy.maxAttempts {
                job.state = .failed
                job.nextAttemptAtUTC = nil
            } else {
                job.state = .retryWait
                job.nextAttemptAtUTC = nextAttemptUTC(
                    after: job.attemptCount,
                    from: nowUTC
                )
            }
            return job
        }
        job.state = .failed
        job.lastError = HTDTDeliveryRetryPolicy.errorKind(error)
        job.lastErrorDetail = String(describing: error)
        return job
    }

    private func nextAttemptUTC(
        after attempt: Int,
        from nowUTC: String
    ) -> String {
        let delay = retryPolicy.nextAttemptDelay(after: attempt)
        let base = BundleTimestamp.date(from: nowUTC) ?? Date()
        return BundleTimestamp.utcString(
            from: base.addingTimeInterval(delay)
        )
    }

    private func mutate(
        jobID: String,
        _ body: (inout HTDTDeliveryJob) throws -> Void
    ) throws {
        var document = try load()
        guard let index = document.jobs.firstIndex(where: {
            $0.deliveryJobID == jobID
        }) else {
            throw HTDTDeliveryQueueError.unknownJob(jobID)
        }
        var job = document.jobs[index]
        try body(&job)
        document.jobs[index] = job
        try save(document)
    }

    private func removePayload(for job: HTDTDeliveryJob) {
        let payloadURL = captureRoot.appendingPathComponent(
            job.payloadRelativePath,
            isDirectory: false
        )
        try? FileManager.default.removeItem(at: payloadURL)
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }
}
