import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a `.htdtcapture` handoff was directed (issue #225). The
/// destination is explicit — the operator picks it per send — and the
/// receipt binds the exact bundle that was transferred.
public enum HTDTHandoffDestinationKind:
    String,
    Codable,
    Sendable
{
    /// The iOS share sheet / file handoff. The transfer is the same
    /// byte-identical archive; the receipt records that the operator
    /// chose this destination explicitly.
    case shareSheet = "share_sheet"
    /// A configured remote endpoint that ingests the archive and
    /// returns an ingestion receipt.
    case endpoint = "endpoint"
}

public struct HTDTHandoffDestination:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    /// Operator-facing destination name shown in the picker.
    public let name: String
    public let kind: HTDTHandoffDestinationKind
    /// Endpoint URL for `.endpoint` destinations; https only.
    public let url: String?

    public init(
        name: String,
        kind: HTDTHandoffDestinationKind,
        url: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.url = url
    }

    public var id: String { name + "|" + (url ?? "") }
}

/// A durable, per-revision record of one handoff attempt (issue #225).
/// App-local — never part of the bundle — so a retry can re-send the
/// identical archive bytes without weakening the digest binding.
public struct HTDTHandoffReceipt:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    public static let schema = "htdt.capture.handoff-receipt"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// Unique receipt id (UUIDv4) for this attempt.
    public let receiptID: String
    /// Capture-specific identity — present for `capture_bundle`
    /// artifacts, nil for field returns (issue #423: never a fake
    /// revision id; the artifact fields below carry the identity).
    public let captureRevisionID: CaptureRevisionID?
    public let captureSeriesID: CaptureSeriesID?
    /// The finalized bundle digest the archive was proven to carry;
    /// nil for non-capture artifacts.
    public let bundleDigest: String?
    /// Typed artifact identity (#423): artifact family, artifact id
    /// and semantic/root digest echoed with the transfer.
    public let artifactKind: String?
    public let artifactID: String?
    public let artifactDigest: String?
    /// SHA-256 of the transmitted archive file bytes.
    public let archiveSHA256: String
    public let archiveByteCount: Int64
    public let destination: HTDTHandoffDestination
    /// When the handoff was initiated by the operator.
    public let initiatedAtUTC: String
    /// `delivered` when the destination accepted the bytes (endpoint
    /// ingestion acknowledged, or the share sheet completed an
    /// activity); `cancelled` when the share sheet was dismissed
    /// without one; `failed` otherwise with `detail` naming the
    /// reason.
    public let outcome: String
    public let detail: String?
    /// Paired receiver identity the send was bound to (#379); nil for
    /// share-sheet or legacy raw-endpoint handoffs.
    public let pairedDestinationID: String?
    /// Delivery-queue job that produced this attempt (#387); nil for
    /// direct sends.
    public let deliveryJobID: String?

    public init(
        receiptID: String,
        captureRevisionID: CaptureRevisionID? = nil,
        captureSeriesID: CaptureSeriesID? = nil,
        bundleDigest: String? = nil,
        artifactKind: String? = nil,
        artifactID: String? = nil,
        artifactDigest: String? = nil,
        archiveSHA256: String,
        archiveByteCount: Int64,
        destination: HTDTHandoffDestination,
        initiatedAtUTC: String,
        outcome: String,
        detail: String? = nil,
        pairedDestinationID: String? = nil,
        deliveryJobID: String? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.bundleDigest = bundleDigest
        self.artifactKind = artifactKind
        self.artifactID = artifactID
        self.artifactDigest = artifactDigest
        self.archiveSHA256 = archiveSHA256
        self.archiveByteCount = archiveByteCount
        self.destination = destination
        self.initiatedAtUTC = initiatedAtUTC
        self.outcome = outcome
        self.detail = detail
        self.pairedDestinationID = pairedDestinationID
        self.deliveryJobID = deliveryJobID
    }

    public var id: String { receiptID }

    /// Identity text of the artifact this receipt covers — the
    /// generic artifact id when present (#423), else the legacy
    /// capture revision id.
    public var artifactIDText: String? {
        artifactID ?? captureRevisionID?.description
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case captureRevisionID = "capture_revision_id"
        case captureSeriesID = "capture_series_id"
        case bundleDigest = "bundle_digest"
        case artifactKind = "artifact_kind"
        case artifactID = "artifact_id"
        case artifactDigest = "artifact_digest"
        case archiveSHA256 = "archive_sha256"
        case archiveByteCount = "archive_byte_count"
        case destination
        case initiatedAtUTC = "initiated_at"
        case outcome
        case detail
        case pairedDestinationID = "paired_destination_id"
        case deliveryJobID = "delivery_job_id"
    }
}

/// The operator-level result of the system share sheet used for a
/// share-sheet handoff (#225). Only `completed` means the archive
/// bytes left the device — a dismissal without a finished activity is
/// `cancelled`, and an activity-level error is `failed` carrying the
/// reported description.
public enum HTDTShareSheetOutcome: Sendable, Equatable {
    case completed
    case cancelled
    case failed(String)
}

public enum HTDTHandoffError: Error, Sendable, Equatable {
    case invalidEndpointURL
    case archiveIdentityMismatch
    case serverRejected(String)
    /// Non-2xx HTTP status from the endpoint. The status code drives
    /// delivery-queue retry classification (#387): 5xx/408/429 are
    /// transient, other 4xx are semantic rejections.
    case endpointRejected(statusCode: Int)
    case malformedServerReceipt
    case transportFailed(String)
    /// The receiver's presented TLS identity did not match the
    /// identity pinned during the pairing ceremony (#379).
    case pinnedIdentityMismatch
}

/// Server-side ingestion receipt returned by an HTDT endpoint. The
/// endpoint must echo the exact digest it ingested so the receipt can
/// never stand in for a different bundle (issue #225).
public struct HTDTIngestionResponse: Codable, Sendable, Equatable {
    /// Endpoint accepted the bytes for staging.
    public static let outcomeAccepted = "accepted"
    /// Endpoint rejected the bundle semantically.
    public static let outcomeRejected = "rejected"
    /// Endpoint already holds this exact digest — a retry resolved to
    /// the same staging identity, so duplicate deliveries are
    /// idempotent (issue #387).
    public static let outcomeAlreadyStaged = "already_staged"

    public let ingestionOutcome: String
    /// Legacy Capture echo (#225) — required for `capture_bundle`
    /// receipts, may be absent on artifact-aware (#423) receivers
    /// that answer only the generic artifact fields.
    public let captureRevisionID: String?
    public let bundleDigest: String?
    /// Generic artifact echo (#423): the receiver repeats the exact
    /// artifact kind/id/digest it staged. A generic HTTP 200 without
    /// the echoed identity is never success (#423 §6).
    public let artifactKind: String?
    public let artifactID: String?
    public let artifactDigest: String?
    /// Server-side staging/receipt identity when the receiver reports
    /// one; nil for receivers that do not name their staging slot
    /// (issue #387).
    public let stagingRef: String?
    public let detail: String?
    /// Targeted repair/follow-up tasks the endpoint returns alongside
    /// the ingestion verdict (issue #321). Absent means no requested
    /// repairs. The plan must pin the same revision + bundle digest
    /// the receipt binds or it is refused as out-of-context.
    public let repairTaskPlan: HTDTRepairTaskPlan?

    public init(
        ingestionOutcome: String,
        captureRevisionID: String? = nil,
        bundleDigest: String? = nil,
        artifactKind: String? = nil,
        artifactID: String? = nil,
        artifactDigest: String? = nil,
        stagingRef: String? = nil,
        detail: String? = nil,
        repairTaskPlan: HTDTRepairTaskPlan? = nil
    ) {
        self.ingestionOutcome = ingestionOutcome
        self.captureRevisionID = captureRevisionID
        self.bundleDigest = bundleDigest
        self.artifactKind = artifactKind
        self.artifactID = artifactID
        self.artifactDigest = artifactDigest
        self.stagingRef = stagingRef
        self.detail = detail
        self.repairTaskPlan = repairTaskPlan
    }

    private enum CodingKeys: String, CodingKey {
        case ingestionOutcome = "ingestion_outcome"
        case captureRevisionID = "capture_revision_id"
        case bundleDigest = "bundle_digest"
        case artifactKind = "artifact_kind"
        case artifactID = "artifact_id"
        case artifactDigest = "artifact_digest"
        case stagingRef = "staging_ref"
        case detail
        case repairTaskPlan = "repair_task_plan"
    }
}

/// Builds the digest-preserving HTTP request and validates the returned
/// receipt (issue #225). Split from `HTDTHandoffClient` so the wire
/// contract is unit-testable without network access.
public enum HTDTHandoffRequestBuilder {
    /// POST of the raw archive bytes with the identity headers an HTDT
    /// endpoint binds to the received bytes. The body is the exact
    /// archive file — never a re-serialized or transformed copy.
    ///
    /// #423: the versioned generic handoff envelope —
    /// `X-HTDT-Artifact-Kind` / `-ID` / `-Digest` always travel; the
    /// legacy Capture headers (`X-HTDT-Capture-Revision-ID`,
    /// `X-HTDT-Bundle-Digest`) are still sent for `capture_bundle` so
    /// Capture-only receivers keep working during migration. A field
    /// return never travels under `X-HTDT-Capture-Revision-ID`.
    public static func buildRequest(
        endpoint: URL,
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        deliverable: HTDTDeliverableIdentity,
        deliveryID: String? = nil
    ) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil
        else {
            throw HTDTHandoffError.invalidEndpointURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        switch deliverable.artifactKind {
        case .captureBundle:
            request.setValue(
                "application/vnd.htdt.capture-bundle",
                forHTTPHeaderField: "Content-Type"
            )
        case .fieldReturn:
            request.setValue(
                "application/vnd.htdt.field-return",
                forHTTPHeaderField: "Content-Type"
            )
        }
        request.setValue(
            deliverable.artifactKind.rawValue,
            forHTTPHeaderField: "X-HTDT-Artifact-Kind"
        )
        request.setValue(
            deliverable.artifactID,
            forHTTPHeaderField: "X-HTDT-Artifact-ID"
        )
        request.setValue(
            deliverable.semanticDigest,
            forHTTPHeaderField: "X-HTDT-Artifact-Digest"
        )
        if deliverable.artifactKind == .captureBundle {
            // Legacy Capture headers preserved during migration —
            // receivers that know only the #225 contract still
            // resolve the same identity (#423 §4/§14).
            request.setValue(
                deliverable.artifactID,
                forHTTPHeaderField: "X-HTDT-Capture-Revision-ID"
            )
            request.setValue(
                deliverable.semanticDigest,
                forHTTPHeaderField: "X-HTDT-Bundle-Digest"
            )
        }
        request.setValue(
            archiveSHA256.value,
            forHTTPHeaderField: "X-HTDT-Archive-SHA256"
        )
        request.setValue(
            String(archiveByteCount),
            forHTTPHeaderField: "X-HTDT-Archive-Bytes"
        )
        if let deliveryID {
            // Idempotency key (#387): every retry of one delivery job
            // carries the same identity so the receiver treats
            // duplicates idempotently.
            request.setValue(
                deliveryID,
                forHTTPHeaderField: "X-HTDT-Delivery-ID"
            )
        }
        return request
    }

    /// Validates a server receipt against the deliverable that was
    /// sent (#423 §6). For `capture_bundle` the legacy revision +
    /// bundle-digest echo remains authoritative (artifact fields may
    /// add to it); for `field_return` the artifact kind/id/digest must
    /// echo exactly — a generic HTTP 200 is never success.
    public static func validateServerReceipt(
        data: Data,
        deliverable: HTDTDeliverableIdentity
    ) throws -> HTDTIngestionResponse {
        guard let response = try? JSONDecoder().decode(
            HTDTIngestionResponse.self,
            from: data
        ) else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        switch deliverable.artifactKind {
        case .captureBundle:
            let legacyEcho = response.captureRevisionID
                == deliverable.artifactID
                && response.bundleDigest
                    == deliverable.semanticDigest
            let artifactEcho = response.artifactID
                == deliverable.artifactID
                && response.artifactDigest
                    == deliverable.semanticDigest
                && (response.artifactKind == nil
                    || response.artifactKind
                        == HTDTDeliverableKind.captureBundle.rawValue)
            guard legacyEcho || artifactEcho else {
                throw HTDTHandoffError.archiveIdentityMismatch
            }
        case .fieldReturn:
            guard response.artifactKind
                    == HTDTDeliverableKind.fieldReturn.rawValue,
                  response.artifactID == deliverable.artifactID,
                  response.artifactDigest
                    == deliverable.semanticDigest
            else {
                throw HTDTHandoffError.archiveIdentityMismatch
            }
        }
        guard response.ingestionOutcome
                == HTDTIngestionResponse.outcomeAccepted
                || response.ingestionOutcome
                    == HTDTIngestionResponse.outcomeRejected
                || response.ingestionOutcome
                    == HTDTIngestionResponse.outcomeAlreadyStaged
        else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        if let plan = response.repairTaskPlan {
            // A returned repair plan is only trusted when it pins the
            // exact revision + digest this handoff just delivered —
            // never a plan describing other bytes (#321).
            guard plan.sourceCaptureRevisionID
                    == deliverable.artifactID,
                  plan.sourceBundleDigest
                    == deliverable.semanticDigest
            else {
                throw HTDTHandoffError.archiveIdentityMismatch
            }
        }
        return response
    }
}

/// Sends a `.htdtcapture` archive to a configured endpoint
/// (issue #225). Only the validated archive file moves — the digest
/// binding is preserved end-to-end because the transmitted bytes are
/// the archive file itself.
public struct HTDTHandoffClient: Sendable {
    public init() {}

    /// Uploads `archive` to `endpoint` and returns the validated
    /// server-side ingestion response. The caller records the
    /// `HTDTHandoffReceipt`.
    ///
    /// `deliveryID` is the delivery-queue idempotency key (#387); every
    /// retry of one queued job sends the same value so a receiver that
    /// already staged those bytes answers `already_staged` instead of
    /// ingesting a duplicate.
    ///
    /// `pinnedIdentity` ("sha256:<64hex>" of the receiver's leaf TLS
    /// certificate, from #379 pairing) switches the upload onto a
    /// session that accepts only that certificate. TLS verification is
    /// never disabled globally — the pin replaces CA trust only for
    /// this paired destination's exact certificate.
    public func submit(
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        deliverable: HTDTDeliverableIdentity,
        endpoint: URL,
        deliveryID: String? = nil,
        pinnedIdentity: String? = nil,
        session: URLSession = .shared
    ) async throws -> HTDTIngestionResponse {
        let request = try HTDTHandoffRequestBuilder.buildRequest(
            endpoint: endpoint,
            archive: archive,
            archiveSHA256: archiveSHA256,
            archiveByteCount: archiveByteCount,
            deliverable: deliverable,
            deliveryID: deliveryID
        )
        let transport = pinnedIdentity.map {
            HTDTIdentityPinningSession.session(pinnedIdentity: $0)
        } ?? session
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.upload(
                for: request,
                fromFile: archive
            )
        } catch let error as HTDTHandoffError {
            throw error
        } catch {
            throw HTDTHandoffError.transportFailed(
                String(describing: error)
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTDTHandoffError.endpointRejected(
                statusCode: http.statusCode
            )
        }
        return try HTDTHandoffRequestBuilder.validateServerReceipt(
            data: data,
            deliverable: deliverable
        )
    }
}

/// Builds a URLSession whose server-trust evaluation is pinned to the
/// exact leaf certificate recorded during #379 QR pairing. The pin is
/// scoped to this session only — it never relaxes TLS validation for
/// other destinations, and a certificate that does not match the pin is
/// refused even if it would validate under normal CA rules.
public enum HTDTIdentityPinningSession {
    public static func session(pinnedIdentity: String) -> URLSession {
        URLSession(
            configuration: .ephemeral,
            delegate: HTDTIdentityPinningDelegate(
                pinnedIdentity: pinnedIdentity
            ),
            delegateQueue: nil
        )
    }
}

#if canImport(Security)
import Security

public final class HTDTIdentityPinningDelegate: NSObject,
    URLSessionDelegate, @unchecked Sendable
{
    public let pinnedIdentity: String

    public init(pinnedIdentity: String) {
        self.pinnedIdentity = pinnedIdentity
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let chain = SecTrustCopyCertificateChain(trust)
                as? [SecCertificate],
              let leaf = chain.first
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let leafDigest = EvidenceIntegrity.sha256(
            of: SecCertificateCopyData(leaf) as Data
        ).value
        guard HTDTPinnedIdentity.digestText(pinnedIdentity)
                == leafDigest
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#else

public final class HTDTIdentityPinningDelegate: NSObject,
    URLSessionDelegate, @unchecked Sendable
{
    public let pinnedIdentity: String

    public init(pinnedIdentity: String) {
        self.pinnedIdentity = pinnedIdentity
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
#endif

/// App-local ledger of handoff receipts (issue #225):
/// `<captureRoot>/handoff-receipts.json`. Read-modify-write is atomic
/// through the same temp+replace write used by the library metadata
/// store.
public struct HTDTHandoffReceiptStore: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.handoff-receipts"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public let receipts: [HTDTHandoffReceipt]

        public init(receipts: [HTDTHandoffReceipt] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.receipts = receipts
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case receipts
        }
    }

    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "handoff-receipts.json",
            isDirectory: false
        )
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
            throw CaptureLibraryMetadataError.unreadableDocument
        }
        return document
    }

    /// Appends a receipt; receipts are never rewritten or removed so
    /// the audit trail is append-only.
    public func append(_ receipt: HTDTHandoffReceipt) throws {
        var document = try load()
        let updated = Document(
            receipts: document.receipts + [receipt]
        )
        _ = document
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(updated)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: fileURL
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Receipts for one revision, oldest first.
    public func receipts(
        for captureRevisionID: CaptureRevisionID
    ) throws -> [HTDTHandoffReceipt] {
        try load().receipts.filter {
            $0.captureRevisionID == captureRevisionID
        }
    }

    /// Receipts for one artifact id of any family (#423) — matches
    /// both the generic `artifact_id` and the legacy revision field.
    public func receipts(
        forArtifactID artifactID: String
    ) throws -> [HTDTHandoffReceipt] {
        try load().receipts.filter {
            $0.artifactID == artifactID
                || $0.captureRevisionID?.description == artifactID
        }
    }
}
