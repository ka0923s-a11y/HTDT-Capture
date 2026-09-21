import Foundation

/// App-local library metadata for the capture library (issue #219):
/// operator-assigned room/project names and freeform notes keyed by the
/// capture identity. This file lives at `<captureRoot>/library-metadata.json`
/// — deliberately outside `finalized/`, `exports/`, and `working/` — so it
/// is never part of the canonical bundle, never hashed into a bundle
/// digest, and never inventoried or quarantined by
/// `PersistedCaptureInventory`.
public struct CaptureLibraryEntryMetadata:
    Codable,
    Sendable,
    Equatable
{
    /// Operator-assigned room or project name; nil when unnamed.
    public let displayName: String?
    /// Freeform operator note; nil when unset.
    public let note: String?

    public init(displayName: String? = nil, note: String? = nil) {
        self.displayName = displayName
        self.note = note
    }

    public var isEmpty: Bool {
        (displayName?.isEmpty ?? true) && (note?.isEmpty ?? true)
    }
}

/// Versioned wire document for `library-metadata.json`.
public struct CaptureLibraryMetadataDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.library-metadata"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// Series-level metadata keyed by the canonical capture_series_id.
    public let series: [String: CaptureLibraryEntryMetadata]
    /// Revision-level notes keyed by the canonical capture_revision_id.
    public let revisions: [String: CaptureLibraryEntryMetadata]

    public init(
        series: [String: CaptureLibraryEntryMetadata] = [:],
        revisions: [String: CaptureLibraryEntryMetadata] = [:]
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.series = series
        self.revisions = revisions
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case series
        case revisions
    }
}

public enum CaptureLibraryMetadataError: Error, Sendable, Equatable {
    case unreadableDocument
    case schemaMismatch
}

/// Reads and writes the app-local library metadata document. Writes are
/// atomic (same-directory temporary + replace) so an interrupted save
/// never leaves a half-written document; a missing file reads as an
/// empty document, and a corrupt file fails closed instead of silently
/// dropping operator-entered names.
public struct CaptureLibraryMetadataStore: Sendable {
    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "library-metadata.json",
            isDirectory: false
        )
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CaptureLibraryMetadataDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return CaptureLibraryMetadataDocument()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                CaptureLibraryMetadataDocument.self,
                from: data
              )
        else {
            throw CaptureLibraryMetadataError.unreadableDocument
        }
        guard document.schema
                == CaptureLibraryMetadataDocument.schema,
              document.schemaVersion
                == CaptureLibraryMetadataDocument.schemaVersion
        else {
            throw CaptureLibraryMetadataError.schemaMismatch
        }
        return document
    }

    public func save(
        _ document: CaptureLibraryMetadataDocument
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

    /// Updates one series entry in place; an entry whose name and note
    /// are both cleared is removed so the document stays minimal.
    public func updateSeries(
        _ seriesID: CaptureSeriesID,
        displayName: String?,
        note: String?
    ) throws {
        var document = try load()
        var series = document.series
        let key = seriesID.description
        let entry = CaptureLibraryEntryMetadata(
            displayName: displayName,
            note: note
        )
        if entry.isEmpty {
            series.removeValue(forKey: key)
        } else {
            series[key] = entry
        }
        try save(
            CaptureLibraryMetadataDocument(
                series: series,
                revisions: document.revisions
            )
        )
    }

    public func updateRevision(
        _ revisionID: CaptureRevisionID,
        displayName: String?,
        note: String?
    ) throws {
        var document = try load()
        var revisions = document.revisions
        let key = revisionID.description
        let entry = CaptureLibraryEntryMetadata(
            displayName: displayName,
            note: note
        )
        if entry.isEmpty {
            revisions.removeValue(forKey: key)
        } else {
            revisions[key] = entry
        }
        try save(
            CaptureLibraryMetadataDocument(
                series: document.series,
                revisions: revisions
            )
        )
    }

    public func seriesMetadata(
        for seriesID: CaptureSeriesID
    ) throws -> CaptureLibraryEntryMetadata? {
        try load().series[seriesID.description]
    }

    public func revisionMetadata(
        for revisionID: CaptureRevisionID
    ) throws -> CaptureLibraryEntryMetadata? {
        try load().revisions[revisionID.description]
    }
}

/// One capture series in the library: all revisions sharing a
/// `capture_series_id`, ordered oldest-to-newest by the validated
/// `finalized_at` timestamp (issue #219 series grouping).
public struct CaptureSeriesGroup:
    Sendable,
    Equatable,
    Identifiable
{
    public let captureSeriesID: CaptureSeriesID
    public let revisions: [PersistedCaptureRecord]
    public let metadata: CaptureLibraryEntryMetadata?

    public init(
        captureSeriesID: CaptureSeriesID,
        revisions: [PersistedCaptureRecord],
        metadata: CaptureLibraryEntryMetadata?
    ) {
        self.captureSeriesID = captureSeriesID
        self.revisions = revisions
        self.metadata = metadata
    }

    public var id: CaptureSeriesID { captureSeriesID }

    /// Operator-assigned name, or nil so the caller falls back to a
    /// stable identifier-derived label (never a random display name).
    public var displayName: String? {
        metadata?.displayName
    }

    public var latestRevision: PersistedCaptureRecord? {
        revisions.last
    }
}

public enum CaptureSeriesGrouper {
    /// Groups validated records by series identity, sorts revisions by
    /// `finalized_at` (then revision id for deterministic ordering), and
    /// sorts series by their newest revision so recent work lists first.
    public static func group(
        records: [PersistedCaptureRecord],
        metadata: CaptureLibraryMetadataDocument
    ) -> [CaptureSeriesGroup] {
        var bySeries: [CaptureSeriesID: [PersistedCaptureRecord]] = [:]
        for record in records {
            bySeries[record.captureSeriesID, default: []].append(record)
        }
        var groups: [CaptureSeriesGroup] = []
        groups.reserveCapacity(bySeries.count)
        for (seriesID, seriesRecords) in bySeries {
            let sorted = seriesRecords.sorted {
                if $0.finalizedAtUTC != $1.finalizedAtUTC {
                    return $0.finalizedAtUTC < $1.finalizedAtUTC
                }
                return $0.captureRevisionID.description
                    < $1.captureRevisionID.description
            }
            groups.append(
                CaptureSeriesGroup(
                    captureSeriesID: seriesID,
                    revisions: sorted,
                    metadata: metadata.series[seriesID.description]
                )
            )
        }
        return groups.sorted {
            let lhsKey =
                $0.latestRevision?.finalizedAtUTC ?? ""
            let rhsKey =
                $1.latestRevision?.finalizedAtUTC ?? ""
            if lhsKey != rhsKey {
                return lhsKey > rhsKey
            }
            return $0.captureSeriesID.description
                < $1.captureSeriesID.description
        }
    }

    /// Case-insensitive substring match over the operator-assigned name,
    /// note, and canonical identifiers (issue #219 search).
    public static func matches(
        group: CaptureSeriesGroup,
        revisionNotes: [String: CaptureLibraryEntryMetadata],
        query: String
    ) -> Bool {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return true
        }
        let needle = trimmed.lowercased()
        if group.displayName?.lowercased().contains(needle) == true {
            return true
        }
        if group.metadata?.note?.lowercased().contains(needle) == true {
            return true
        }
        if group.captureSeriesID.description.contains(needle) {
            return true
        }
        for revision in group.revisions {
            if revision.captureRevisionID.description
                .contains(needle)
            {
                return true
            }
            if revisionNotes[
                revision.captureRevisionID.description
            ]?.note?.lowercased().contains(needle) == true {
                return true
            }
        }
        return false
    }
}
