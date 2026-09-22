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

/// The operator's explicit branch choice for a forked capture series
/// (issue #396). App-local metadata — never part of any bundle — so an
/// automatic update is impossible: only the operator's explicit action
/// writes it, and a stored choice that no longer names a current graph
/// head is ignored rather than silently re-pointed.
public struct CaptureSeriesPreferredHead:
    Codable,
    Sendable,
    Equatable
{
    /// Canonical capture_revision_id text of the preferred head.
    public let preferredHeadRevisionID: String
    /// When the operator made the selection (UTC timestamp text).
    public let selectedAtUTC: String
    /// Optional operator note carried beside the selection.
    public let note: String?

    public init(
        preferredHeadRevisionID: String,
        selectedAtUTC: String,
        note: String? = nil
    ) {
        self.preferredHeadRevisionID = preferredHeadRevisionID
        self.selectedAtUTC = selectedAtUTC
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case preferredHeadRevisionID = "preferred_head_revision_id"
        case selectedAtUTC = "selected_at"
        case note
    }
}

/// Series-level retention lifecycle state (issue #394): `archived`
/// removes a finished series from the default library view without
/// touching a single canonical byte — revisions, receipts, mission
/// links and metadata all stay durable, and the series remains
/// searchable under the Archived group.
public struct CaptureSeriesLibraryState:
    Codable,
    Sendable,
    Equatable
{
    public let archived: Bool
    /// When the operator archived the series; nil while active.
    public let archivedAtUTC: String?

    public init(
        archived: Bool = false,
        archivedAtUTC: String? = nil
    ) {
        self.archived = archived
        self.archivedAtUTC = archivedAtUTC
    }

    public static let active = CaptureSeriesLibraryState()

    /// An unarchived series has no durable lifecycle content, so it
    /// is dropped from the document like an empty metadata entry.
    public var isEmpty: Bool { !archived }

    private enum CodingKeys: String, CodingKey {
        case archived
        case archivedAtUTC = "archived_at_utc"
    }
}

/// Operator-importance marks on one revision (issue #394). A marked
/// revision is still deletable, but only through the explicit
/// protected-override path — retention previews always recommend
/// keeping it.
public struct CaptureRevisionMark:
    Codable,
    Sendable,
    Equatable
{
    /// A named point worth keeping (a delivery milestone, an as-built
    /// record); always recommended for retention.
    public var milestone: Bool
    /// Never auto-cleaned: the revision must stay inspectable on this
    /// device until the operator clears the mark.
    public var keepLocal: Bool
    /// Personal preference marker.
    public var favorite: Bool
    /// Pinned for later work; retention surfaces it as protected.
    public var pinned: Bool

    public init(
        milestone: Bool = false,
        keepLocal: Bool = false,
        favorite: Bool = false,
        pinned: Bool = false
    ) {
        self.milestone = milestone
        self.keepLocal = keepLocal
        self.favorite = favorite
        self.pinned = pinned
    }

    public var isProtected: Bool {
        milestone || keepLocal || favorite || pinned
    }

    public var isEmpty: Bool { !isProtected }

    private enum CodingKeys: String, CodingKey {
        case milestone
        case keepLocal = "keep_local"
        case favorite
        case pinned
    }
}

/// Versioned wire document for `library-metadata.json`. v1.1.0 adds
/// the retention-lifecycle maps (issue #394); `supportedReadVersions`
/// names the versions this build can still open — v1.0.0 documents
/// migrate forward through `LocalStateMigrator` before the store
/// reads them (#390). `preferred_heads` (#396) decodes optionally so
/// documents written before the field existed still open.
public struct CaptureLibraryMetadataDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.library-metadata"
    public static let schemaVersion = "1.1.0"
    public static let supportedReadVersions = ["1.0.0", "1.1.0"]

    public let schema: String
    public let schemaVersion: String
    /// Series-level metadata keyed by the canonical capture_series_id.
    public let series: [String: CaptureLibraryEntryMetadata]
    /// Revision-level notes keyed by the canonical capture_revision_id.
    public let revisions: [String: CaptureLibraryEntryMetadata]
    /// Series lifecycle state keyed by the canonical
    /// capture_series_id; absent entries are active (#394).
    public let seriesStates: [String: CaptureSeriesLibraryState]
    /// Revision importance marks keyed by the canonical
    /// capture_revision_id; absent entries are unmarked (#394).
    public let revisionMarks: [String: CaptureRevisionMark]
    /// Operator-chosen preferred head per series, keyed by the
    /// canonical capture_series_id (issue #396). Absent in documents
    /// written before the field existed — decode is optional.
    public let preferredHeads:
        [String: CaptureSeriesPreferredHead]

    public init(
        series: [String: CaptureLibraryEntryMetadata] = [:],
        revisions: [String: CaptureLibraryEntryMetadata] = [:],
        seriesStates: [String: CaptureSeriesLibraryState] = [:],
        revisionMarks: [String: CaptureRevisionMark] = [:],
        preferredHeads:
            [String: CaptureSeriesPreferredHead] = [:]
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.series = series
        self.revisions = revisions
        self.seriesStates = seriesStates
        self.revisionMarks = revisionMarks
        self.preferredHeads = preferredHeads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        series = try container.decode(
            [String: CaptureLibraryEntryMetadata].self,
            forKey: .series
        )
        revisions = try container.decode(
            [String: CaptureLibraryEntryMetadata].self,
            forKey: .revisions
        )
        // The v1.0.0 document predates the lifecycle maps; absent keys
        // decode as empty so a supported read-version document still
        // opens before the migration step rewrites it (#390). The
        // preferred-head map (#396) follows the same convention.
        seriesStates = try container.decodeIfPresent(
            [String: CaptureSeriesLibraryState].self,
            forKey: .seriesStates
        ) ?? [:]
        revisionMarks = try container.decodeIfPresent(
            [String: CaptureRevisionMark].self,
            forKey: .revisionMarks
        ) ?? [:]
        preferredHeads = try container.decodeIfPresent(
            [String: CaptureSeriesPreferredHead].self,
            forKey: .preferredHeads
        ) ?? [:]
    }

    /// The lifecycle state of one series; `.active` when unrecorded.
    public func seriesState(
        for seriesID: CaptureSeriesID
    ) -> CaptureSeriesLibraryState {
        seriesStates[seriesID.description] ?? .active
    }

    /// The importance marks of one revision; empty when unrecorded.
    public func revisionMark(
        for revisionID: CaptureRevisionID
    ) -> CaptureRevisionMark {
        revisionMarks[revisionID.description] ?? CaptureRevisionMark()
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case series
        case revisions
        case seriesStates = "series_states"
        case revisionMarks = "revision_marks"
        case preferredHeads = "preferred_heads"
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
              CaptureLibraryMetadataDocument.supportedReadVersions
                .contains(document.schemaVersion)
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
                revisions: document.revisions,
                seriesStates: document.seriesStates,
                revisionMarks: document.revisionMarks,
                preferredHeads: document.preferredHeads
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
                revisions: revisions,
                seriesStates: document.seriesStates,
                revisionMarks: document.revisionMarks,
                preferredHeads: document.preferredHeads
            )
        )
    }

    /// Records the operator's explicit preferred head for a forked
    /// series (issue #396): app-local metadata only, never written to
    /// a bundle. The caller is responsible for validating that
    /// `revisionID` is a current head of the series' revision graph —
    /// stale selections are ignored at read time.
    public func updatePreferredHead(
        _ seriesID: CaptureSeriesID,
        revisionID: CaptureRevisionID,
        note: String? = nil,
        selectedAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws {
        var document = try load()
        var heads = document.preferredHeads
        heads[seriesID.description] = CaptureSeriesPreferredHead(
            preferredHeadRevisionID: revisionID.description,
            selectedAtUTC: selectedAtUTC,
            note: note
        )
        try save(
            CaptureLibraryMetadataDocument(
                series: document.series,
                revisions: document.revisions,
                seriesStates: document.seriesStates,
                revisionMarks: document.revisionMarks,
                preferredHeads: heads
            )
        )
    }

    /// Clears a series' explicit preferred head — reverting to
    /// per-head presentation with no branch favored.
    public func clearPreferredHead(
        _ seriesID: CaptureSeriesID
    ) throws {
        var document = try load()
        var heads = document.preferredHeads
        heads.removeValue(forKey: seriesID.description)
        try save(
            CaptureLibraryMetadataDocument(
                series: document.series,
                revisions: document.revisions,
                seriesStates: document.seriesStates,
                revisionMarks: document.revisionMarks,
                preferredHeads: heads
            )
        )
    }

    /// Sets the retention lifecycle of one series (issue #394): the
    /// archived timestamp is stamped by the caller; clearing back to
    /// active drops the entry so the document stays minimal.
    public func setSeriesState(
        _ seriesID: CaptureSeriesID,
        archived: Bool,
        archivedAtUTC: String?
    ) throws {
        var document = try load()
        var states = document.seriesStates
        let key = seriesID.description
        let state = CaptureSeriesLibraryState(
            archived: archived,
            archivedAtUTC: archivedAtUTC
        )
        if state.isEmpty {
            states.removeValue(forKey: key)
        } else {
            states[key] = state
        }
        try save(
            CaptureLibraryMetadataDocument(
                series: document.series,
                revisions: document.revisions,
                seriesStates: states,
                revisionMarks: document.revisionMarks,
                preferredHeads: document.preferredHeads
            )
        )
    }

    /// Replaces the importance marks of one revision (issue #394);
    /// an empty mark set is removed like an empty metadata entry.
    public func updateRevisionMark(
        _ revisionID: CaptureRevisionID,
        mark: CaptureRevisionMark
    ) throws {
        var document = try load()
        var marks = document.revisionMarks
        let key = revisionID.description
        if mark.isEmpty {
            marks.removeValue(forKey: key)
        } else {
            marks[key] = mark
        }
        try save(
            CaptureLibraryMetadataDocument(
                series: document.series,
                revisions: document.revisions,
                seriesStates: document.seriesStates,
                revisionMarks: marks,
                preferredHeads: document.preferredHeads
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
    /// The read-side lineage graph for this series (issue #396):
    /// declared parent edges, roots, heads, and lineage diagnostics.
    public let revisionGraph: CaptureSeriesRevisionGraph
    /// The operator's stored preferred-head choice, unvalidated —
    /// `effectivePreferredHeadID` applies the graph check.
    public let storedPreferredHead: CaptureSeriesPreferredHead?

    public init(
        captureSeriesID: CaptureSeriesID,
        revisions: [PersistedCaptureRecord],
        metadata: CaptureLibraryEntryMetadata?,
        revisionGraph: CaptureSeriesRevisionGraph? = nil,
        storedPreferredHead: CaptureSeriesPreferredHead? = nil
    ) {
        self.captureSeriesID = captureSeriesID
        self.revisions = revisions
        self.metadata = metadata
        self.revisionGraph = revisionGraph
            ?? CaptureSeriesRevisionGraph(
                allRecords: revisions,
                captureSeriesID: captureSeriesID
            )
        self.storedPreferredHead = storedPreferredHead
    }

    public var id: CaptureSeriesID { captureSeriesID }

    /// Operator-assigned name, or nil so the caller falls back to a
    /// stable identifier-derived label (never a random display name).
    public var displayName: String? {
        metadata?.displayName
    }

    /// The newest finalized revision by timestamp. Chronology only —
    /// in a branched series this is NOT a leadership claim; use
    /// `preferredRevision`/`headRevisions` for selection semantics.
    public var latestRevision: PersistedCaptureRecord? {
        revisions.last
    }

    /// The stored preferred head validated against the live graph:
    /// a selection that names a revision which is no longer a head
    /// (or no longer present) is ignored rather than silently
    /// re-pointed at another tip.
    public var effectivePreferredHeadID: CaptureRevisionID? {
        guard let stored = storedPreferredHead,
              let id = CaptureRevisionID(
                  canonicalString: stored.preferredHeadRevisionID
              ),
              revisionGraph.heads.contains(id)
        else {
            return nil
        }
        return id
    }

    /// The head records in graph display order (finalizedAtUTC, id).
    public var headRevisions: [PersistedCaptureRecord] {
        revisionGraph.heads.compactMap { head in
            revisions.first {
                $0.captureRevisionID == head
            }
        }
    }

    /// The operator-selected head when it still resolves, else the
    /// single head when the series is linear — nil when the series is
    /// branched with no valid preference, so callers never substitute
    /// "newest" for "selected".
    public var preferredRevision: PersistedCaptureRecord? {
        if let preferred = effectivePreferredHeadID {
            return revisions.first {
                $0.captureRevisionID == preferred
            }
        }
        guard revisionGraph.hasSingleHead else {
            return nil
        }
        return headRevisions.first
    }

    /// True when more than one branch tip exists — the "Latest"
    /// presentation must not be used.
    public var isBranched: Bool {
        revisionGraph.isBranched
    }

    /// Representative-preview candidates for the library row (issue
    /// #411): the head the row presents first (`preferredRevision`,
    /// when it resolves), then every other revision newest-first —
    /// filtered to those whose validated manifest declares at least
    /// one `evidence/frames/*.preview.heic` entry. The ordering IS
    /// the policy: presented head preferred, then the most recent
    /// revision in the series that retains a preview; an empty result
    /// means the semantic placeholder. This is pure metadata ordering
    /// over the scan-time validation, so no file I/O ever runs here;
    /// the caller resolves bytes lazily and may skip a candidate whose
    /// payload turns out unreadable.
    public var representativePreviewCandidates:
        [PersistedCaptureRecord]
    {
        let preferred = preferredRevision
        var ordered: [PersistedCaptureRecord] = []
        if let preferred {
            ordered.append(preferred)
        }
        ordered.append(
            contentsOf: revisions.reversed().filter {
                $0.captureRevisionID != preferred?.captureRevisionID
            }
        )
        return ordered.filter {
            !$0.declaredPreviewPaths.isEmpty
        }
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
                    metadata: metadata.series[seriesID.description],
                    revisionGraph: CaptureSeriesRevisionGraph(
                        allRecords: records,
                        captureSeriesID: seriesID
                    ),
                    storedPreferredHead: metadata.preferredHeads[
                        seriesID.description
                    ]
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
