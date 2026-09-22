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
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    /// The finalized bundle digest the archive was proven to carry.
    public let bundleDigest: String
    /// SHA-256 of the transmitted archive file bytes.
    public let archiveSHA256: String
    public let archiveByteCount: Int64
    public let destination: HTDTHandoffDestination
    /// When the handoff was initiated by the operator.
    public let initiatedAtUTC: String
    /// `delivered` when the destination accepted the bytes (endpoint
    /// ingestion acknowledged, or the share sheet completed);
    /// `failed` otherwise with `detail` naming the reason.
    public let outcome: String
    public let detail: String?

    public init(
        receiptID: String,
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        bundleDigest: String,
        archiveSHA256: String,
        archiveByteCount: Int64,
        destination: HTDTHandoffDestination,
        initiatedAtUTC: String,
        outcome: String,
        detail: String? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.bundleDigest = bundleDigest
        self.archiveSHA256 = archiveSHA256
        self.archiveByteCount = archiveByteCount
        self.destination = destination
        self.initiatedAtUTC = initiatedAtUTC
        self.outcome = outcome
        self.detail = detail
    }

    public var id: String { receiptID }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case captureRevisionID = "capture_revision_id"
        case captureSeriesID = "capture_series_id"
        case bundleDigest = "bundle_digest"
        case archiveSHA256 = "archive_sha256"
        case archiveByteCount = "archive_byte_count"
        case destination
        case initiatedAtUTC = "initiated_at"
        case outcome
        case detail
    }
}

public enum HTDTHandoffError: Error, Sendable, Equatable {
    case invalidEndpointURL
    case archiveIdentityMismatch
    case serverRejected(String)
    case malformedServerReceipt
    case transportFailed(String)
}

/// Server-side ingestion receipt returned by an HTDT endpoint. The
/// endpoint must echo the exact digest it ingested so the receipt can
/// never stand in for a different bundle (issue #225).
public struct HTDTIngestionResponse: Codable, Sendable, Equatable {
    public let ingestionOutcome: String
    public let captureRevisionID: String
    public let bundleDigest: String
    public let detail: String?
    /// Targeted repair/follow-up tasks the endpoint returns alongside
    /// the ingestion verdict (issue #321). Absent means no requested
    /// repairs. The plan must pin the same revision + bundle digest
    /// the receipt binds or it is refused as out-of-context.
    public let repairTaskPlan: HTDTRepairTaskPlan?

    public init(
        ingestionOutcome: String,
        captureRevisionID: String,
        bundleDigest: String,
        detail: String? = nil,
        repairTaskPlan: HTDTRepairTaskPlan? = nil
    ) {
        self.ingestionOutcome = ingestionOutcome
        self.captureRevisionID = captureRevisionID
        self.bundleDigest = bundleDigest
        self.detail = detail
        self.repairTaskPlan = repairTaskPlan
    }

    private enum CodingKeys: String, CodingKey {
        case ingestionOutcome = "ingestion_outcome"
        case captureRevisionID = "capture_revision_id"
        case bundleDigest = "bundle_digest"
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
    public static func buildRequest(
        endpoint: URL,
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256
    ) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil
        else {
            throw HTDTHandoffError.invalidEndpointURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/vnd.htdt.capture-bundle",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            captureRevisionID.description,
            forHTTPHeaderField: "X-HTDT-Capture-Revision-ID"
        )
        request.setValue(
            bundleDigest.value,
            forHTTPHeaderField: "X-HTDT-Bundle-Digest"
        )
        request.setValue(
            archiveSHA256.value,
            forHTTPHeaderField: "X-HTDT-Archive-SHA256"
        )
        request.setValue(
            String(archiveByteCount),
            forHTTPHeaderField: "X-HTDT-Archive-Bytes"
        )
        return request
    }

    /// Validates a server receipt: it must echo the exact revision and
    /// bundle digest that was sent, otherwise it is refused rather than
    /// recorded as a delivery of the wrong bundle.
    public static func validateServerReceipt(
        data: Data,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256
    ) throws -> HTDTIngestionResponse {
        guard let response = try? JSONDecoder().decode(
            HTDTIngestionResponse.self,
            from: data
        ) else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        guard response.captureRevisionID
                == captureRevisionID.description,
              response.bundleDigest == bundleDigest.value
        else {
            throw HTDTHandoffError.archiveIdentityMismatch
        }
        guard response.ingestionOutcome == "accepted"
                || response.ingestionOutcome == "rejected"
        else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        if let plan = response.repairTaskPlan {
            // A returned repair plan is only trusted when it pins the
            // exact revision + digest this handoff just delivered —
            // never a plan describing other bytes (#321).
            guard plan.sourceCaptureRevisionID
                    == captureRevisionID.description,
                  plan.sourceBundleDigest == bundleDigest.value
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
    public func submit(
        archive: URL,
        archiveSHA256: EvidenceSHA256,
        archiveByteCount: Int64,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        endpoint: URL,
        session: URLSession = .shared
    ) async throws -> HTDTIngestionResponse {
        let request = try HTDTHandoffRequestBuilder.buildRequest(
            endpoint: endpoint,
            archive: archive,
            archiveSHA256: archiveSHA256,
            archiveByteCount: archiveByteCount,
            captureRevisionID: captureRevisionID,
            bundleDigest: bundleDigest
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(
                for: request,
                fromFile: archive
            )
        } catch {
            throw HTDTHandoffError.transportFailed(
                String(describing: error)
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTDTHandoffError.malformedServerReceipt
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTDTHandoffError.serverRejected(
                "http_" + String(http.statusCode)
            )
        }
        return try HTDTHandoffRequestBuilder.validateServerReceipt(
            data: data,
            captureRevisionID: captureRevisionID,
            bundleDigest: bundleDigest
        )
    }
}

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
}
