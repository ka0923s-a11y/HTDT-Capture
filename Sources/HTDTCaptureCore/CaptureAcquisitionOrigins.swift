import Foundation

/// How the on-disk copy of a capture revision reached this device
/// (issue #317). The kind is app-local provenance — the immutable
/// bundle itself deliberately does not mark device-vs-external origin,
/// so the library keeps it beside the bundle, never inside it. An
/// imported bundle's manifest `app` identity is reported separately as
/// *declared* producer metadata and is never treated as verified.
public enum CaptureAcquisitionOriginKind:
    String,
    Codable,
    Sendable,
    Equatable
{
    /// Finalized on this device by this app's capture pipeline.
    case createdOnThisDevice = "created_on_this_device"
    /// Brought in through the `.htdtcapture` file-import path.
    case importedFile = "imported_file"
    /// Received through an HTDT-authored exchange/handoff path.
    /// Distinct from `importedFile`: the transport, not just the
    /// evidence of foreign origin, is recorded.
    case receivedFromHTDT = "received_from_htdt"
    /// Arrived through any other sharing path the host observed
    /// (AirDrop-style share, manual file placement, ...).
    case sharedOther = "shared_other"
    /// Predates origin tracking: a validated capture whose provenance
    /// this app never recorded. The UI must not guess — it labels the
    /// capture "origin unknown".
    case legacyUnknown = "legacy_unknown"
}

/// Transport channel that carried the bundle (issue #317), recorded
/// separately from the origin kind so a future transport does not need
/// a new kind.
public enum CaptureAcquisitionTransport:
    String,
    Codable,
    Sendable,
    Equatable
{
    case localCapture = "local_capture"
    case fileImport = "file_import"
    case htdtExchange = "htdt_exchange"
    case other = "other"
    case unknown = "unknown"
}

/// One revision's acquisition record (issue #317).
public struct CaptureAcquisitionOriginRecord:
    Codable,
    Sendable,
    Equatable
{
    /// The validated manifest revision identity — the join key.
    public let captureRevisionID: CaptureRevisionID
    public let kind: CaptureAcquisitionOriginKind
    public let transport: CaptureAcquisitionTransport
    /// UTC timestamp the acquisition happened on this device.
    public let acquiredAtUTC: String
    /// Original filename/transport label when known (e.g. the imported
    /// `.htdtcapture` name); nil otherwise.
    public let originalFilename: String?
    /// Optional operator/context label (e.g. project or sender name);
    /// never interpreted.
    public let sourceLabel: String?
    /// SHA-256 of the acquired bundle's manifest bytes — binds this
    /// record to the exact bundle bytes observed at acquisition time,
    /// so a re-import of different bytes is distinguishable.
    public let bundleDigestSHA256: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        kind: CaptureAcquisitionOriginKind,
        transport: CaptureAcquisitionTransport,
        acquiredAtUTC: String,
        originalFilename: String? = nil,
        sourceLabel: String? = nil,
        bundleDigestSHA256: String? = nil
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(acquiredAtUTC) else {
            throw CaptureAcquisitionOriginError.invalidTimestamp
        }
        let normalizedFilename = SchemaOwnedText
            .nfc(originalFilename)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = SchemaOwnedText
            .nfc(sourceLabel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let digest = bundleDigestSHA256 {
            _ = try EvidenceSHA256(digest)
        }
        self.captureRevisionID = captureRevisionID
        self.kind = kind
        self.transport = transport
        self.acquiredAtUTC = acquiredAtUTC
        self.originalFilename =
            normalizedFilename?.isEmpty == true
                ? nil
                : normalizedFilename
        self.sourceLabel =
            normalizedLabel?.isEmpty == true
                ? nil
                : normalizedLabel
        self.bundleDigestSHA256 = bundleDigestSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case captureRevisionID = "capture_revision_id"
        case kind
        case transport
        case acquiredAtUTC = "acquired_at"
        case originalFilename = "original_filename"
        case sourceLabel = "source_label"
        case bundleDigestSHA256 = "bundle_digest_sha256"
    }
}

/// Versioned wire document for `capture-origins.json` (issue #317).
public struct CaptureAcquisitionOriginDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.acquisition-origins"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// One record per revision identity. Recording the same revision a
    /// second time only ever happens for an identical record — a
    /// conflicting re-record is rejected by the store.
    public let entries: [CaptureAcquisitionOriginRecord]

    public init(
        entries: [CaptureAcquisitionOriginRecord] = []
    ) throws {
        var seen = Set<String>()
        for entry in entries {
            let key = entry.captureRevisionID.description
            guard seen.insert(key).inserted else {
                throw CaptureAcquisitionOriginError
                    .duplicateRevisionEntry
            }
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case entries
    }
}

public enum CaptureAcquisitionOriginError:
    Error,
    Sendable,
    Equatable
{
    case unreadableDocument
    case schemaMismatch
    case invalidTimestamp
    case duplicateRevisionEntry
    /// A conflicting origin was already recorded for the revision —
    /// the first observed provenance is authoritative and a later
    /// contradicting claim is rejected instead of rewriting history.
    case conflictingOrigin(CaptureRevisionID)
}

/// Reads and writes `<captureRoot>/capture-origins.json` (issue #317):
/// app-local acquisition provenance keyed by validated revision
/// identity, deliberately outside `finalized/`, `exports/`, and
/// `working/` so it is never part of the canonical bundle, never
/// hashed into a bundle digest, and never inventoried or quarantined
/// by `PersistedCaptureInventory`. Writes are atomic (same-directory
/// temporary + replace); a missing file reads as an empty document,
/// and a corrupt file fails closed.
public struct CaptureAcquisitionOriginStore: Sendable {
    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "capture-origins.json",
            isDirectory: false
        )
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CaptureAcquisitionOriginDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return try CaptureAcquisitionOriginDocument()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                CaptureAcquisitionOriginDocument.self,
                from: data
              )
        else {
            throw CaptureAcquisitionOriginError.unreadableDocument
        }
        guard document.schema
                == CaptureAcquisitionOriginDocument.schema,
              document.schemaVersion
                == CaptureAcquisitionOriginDocument.schemaVersion
        else {
            throw CaptureAcquisitionOriginError.schemaMismatch
        }
        return document
    }

    public func save(
        _ document: CaptureAcquisitionOriginDocument
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(document)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .atomic)
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

    /// Records an acquisition. An identical record for the same
    /// revision is a no-op; a conflicting one fails closed — the first
    /// observed provenance is authoritative (issue #317).
    public func record(
        _ record: CaptureAcquisitionOriginRecord
    ) throws {
        let document = try load()
        if let existing = document.entries.first(where: {
            $0.captureRevisionID == record.captureRevisionID
        }) {
            if existing == record {
                return
            }
            throw CaptureAcquisitionOriginError.conflictingOrigin(
                record.captureRevisionID
            )
        }
        try save(
            CaptureAcquisitionOriginDocument(
                entries: document.entries + [record]
            )
        )
    }

    /// Writes a record only when none exists yet; never throws on a
    /// conflict. Used by inventory backfill, where `legacy_unknown` is
    /// deliberately weaker than any recorded provenance.
    public func recordIfAbsent(
        _ record: CaptureAcquisitionOriginRecord
    ) throws {
        let document = try load()
        if document.entries.contains(where: {
            $0.captureRevisionID == record.captureRevisionID
        }) {
            return
        }
        try save(
            CaptureAcquisitionOriginDocument(
                entries: document.entries + [record]
            )
        )
    }

    /// Atomically fills missing entries for a batch of revisions
    /// (inventory scan backfill): one read + one write.
    public func recordIfAbsent(
        _ records: [CaptureAcquisitionOriginRecord]
    ) throws {
        let document = try load()
        let known = Set(
            document.entries.map {
                $0.captureRevisionID.description
            }
        )
        let additions = records.filter {
            !known.contains($0.captureRevisionID.description)
        }
        guard !additions.isEmpty else { return }
        try save(
            CaptureAcquisitionOriginDocument(
                entries: document.entries + additions
            )
        )
    }

    public func origin(
        for revisionID: CaptureRevisionID
    ) throws -> CaptureAcquisitionOriginRecord? {
        try load().entries.first {
            $0.captureRevisionID == revisionID
        }
    }
}
