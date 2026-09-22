import Foundation

/// Stable identity of one field note (issue #375). A note keeps this
/// identity for the life of the capture revision it belongs to —
/// corrections after finalization arrive as a *new* note on a later
/// revision that supersedes this one, never an in-place rewrite.
public struct CaptureFieldNoteID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Field-note errors (issue #375). Model-level validation failures are
/// typed so callers can distinguish malformed input from store-state
/// rejections (seal/consumed stay on `CaptureWorkingSetError`).
public enum CaptureFieldNoteError: Error, Sendable, Equatable {
    /// `text` normalized to empty.
    case emptyText
    /// `text` exceeded the bounded note length (utf8 byte count).
    case textTooLong(Int)
    /// Category token is not `[a-z0-9_]+`, or a non-standard token
    /// without the `x_` extension namespace.
    case invalidCategoryToken(String)
    /// A `binding_refs` token failed the shared binding-ref grammar.
    case invalidBindingRef(String)
    /// An `evidence_refs` token failed the shared evidence-ref grammar.
    case invalidEvidenceRef(String)
    /// A spatial position carried non-finite components.
    case invalidSpatialPosition
    /// `supersedes_note_id` names the note itself.
    case selfSupersession
    /// The note a supersede/resolve targeted is not in the collection.
    case unknownNoteID
    /// The note a supersede/resolve targeted is already terminal.
    case noteAlreadyTerminal
    /// The replacement note does not mark the note it supersedes.
    case supersessionNotDeclared
    /// The collection is at its deterministic bound.
    case collectionBoundExceeded
}

/// The typed category of a field note (issue #375). The well-known set
/// covers the issue's vocabulary; deployment-specific categories use
/// the `x_` extension namespace so free text can never smuggle itself
/// into the machine-enumerated slot. Decoding accepts any lowercase
/// token so a document written by a newer build still loads; *authoring*
/// is what enforces the extension namespace.
public struct CaptureFieldNoteCategory:
    Codable, Sendable, Equatable, Hashable
{
    public static let roomCondition = Self("room_condition")
    public static let obstruction = Self("obstruction")
    public static let equipmentState = Self("equipment_state")
    public static let geometryCaveat = Self("geometry_caveat")
    public static let measurementCaveat = Self("measurement_caveat")
    public static let followUp = Self("follow_up")
    public static let installationObservation =
        Self("installation_observation")
    public static let general = Self("general")

    /// The normalized lowercase token persisted on the wire.
    public let rawValue: String

    /// Constructs a category for authoring: a well-known token, or a
    /// deployment extension in the `x_` namespace.
    public init(token: String) throws {
        guard FieldAuthorityGrammar.isLowercaseToken(token) else {
            throw CaptureFieldNoteError.invalidCategoryToken(token)
        }
        guard Self.wellKnownTokens.contains(token)
                || token.hasPrefix("x_")
        else {
            throw CaptureFieldNoteError.invalidCategoryToken(token)
        }
        self.rawValue = token
    }

    /// Internal well-known/decoder path — never validates beyond the
    /// lowercase-token shape so forward-compatibility holds.
    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Lenient memberwise surface for already-normalized tokens.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// True when the token is a deployment extension rather than part
    /// of the standard vocabulary.
    public var isExtension: Bool {
        !Self.wellKnownTokens.contains(rawValue)
    }

    public static let wellKnownTokens: Set<String> = [
        "room_condition",
        "obstruction",
        "equipment_state",
        "geometry_caveat",
        "measurement_caveat",
        "follow_up",
        "installation_observation",
        "general",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard FieldAuthorityGrammar.isLowercaseToken(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "field note category must be [a-z0-9_]+"
            )
        }
        self.rawValue = rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Optional severity marker on a field note (issue #375). Orthogonal
/// to `needs_attention`: severity grades what the note describes, the
/// flag requests operator review before finalization.
public enum CaptureFieldNoteSeverity: String, Codable, Sendable {
    case observation
    case concern
    case hazard
}

/// How the note's text was produced (issue #375). Dictation stores the
/// transcribed text only — audio is never retained, so the bundle
/// carries no voice payload.
public enum CaptureFieldNoteAuthoringMethod:
    String, Codable, Sendable, CaseIterable
{
    case typed
    case dictated
}

/// Lifecycle of a field note (issue #375). `active` is the recording
/// state; `resolved` marks a follow-up handled; `superseded` marks a
/// note replaced by a newer one (the replacement records the link via
/// `supersedes_note_id`). Terminal states never reopen.
public enum CaptureFieldNoteStatus: String, Codable, Sendable {
    case active
    case resolved
    case superseded
}

/// The optional spatial anchor of a field note (issue #375). A point
/// is only meaningful in a named coordinate space; when the recording
/// device cannot produce one the position is absent rather than
/// fabricated.
public struct CaptureFieldNoteSpatialPosition:
    Codable, Sendable, Equatable
{
    public let coordinateSpaceID: CoordinateSpaceID
    public let pointMeters: WorldPoint3D

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        pointMeters: WorldPoint3D
    ) throws {
        guard pointMeters.isFinite else {
            throw CaptureFieldNoteError.invalidSpatialPosition
        }
        self.coordinateSpaceID = coordinateSpaceID
        self.pointMeters = pointMeters
    }

    private enum CodingKeys: String, CodingKey {
        case coordinateSpaceID = "coordinate_space_id"
        case pointMeters = "point_meters"
    }
}

/// One operator field note bound to a capture revision (issue #375).
///
/// A note is supplemental context bound to exact authorities through
/// `binding_refs` (`entity:`, `measurement:`, `surface:`,
/// `task_item:`, `inventory_item:`, `wiring_route:`,
/// `settings_observation:`, `instrument:`, `operator:`, `equipment:`,
/// `commissioning_check:`, `mesh_anchor:`, `path:`) and `evidence_refs`
/// (`frame:`, `field_evidence:`, `path:`, `sha256:`) — the shared
/// binding/evidence-ref grammar the field-authority family already
/// validates. Notes never become structured authority: they describe
/// the capture context and stay advisory on ingest.
///
/// Post-finalization corrections arrive on a later revision as a new
/// note whose `supersedes_note_id` names this one; the superseded note
/// keeps its bytes and gains `superseded_by_note_id` + status
/// `superseded`, so the lineage survives audit.
public struct CaptureFieldNote: Codable, Sendable, Equatable, Identifiable {
    /// Bounded free-text ceiling (UTF-8 bytes). A note is a sentence
    /// or two of scan context; larger prose belongs in evidence.
    public static let maxTextUTF8Bytes = 4000

    public let noteID: CaptureFieldNoteID
    /// The revision this note belongs to — the authority carrier.
    public let captureRevisionID: CaptureRevisionID
    /// The scan session the note was recorded under, when one was
    /// bound; nil for a note authored before/without a session.
    public let captureSessionID: CaptureSessionID?
    /// RFC 3339 UTC creation timestamp.
    public let createdAtUTC: String
    /// Session-clock seconds when recorded mid-scan; nil for notes
    /// authored in Review without a live clock.
    public let sessionTimestampSeconds: Double?
    public let category: CaptureFieldNoteCategory
    /// Operator-authored free text (NFC, trimmed, non-empty).
    public let text: String
    /// Optional severity marker.
    public let severity: CaptureFieldNoteSeverity?
    /// Needs-attention flag: surfaces the note in Review before
    /// Finalize without ever auto-blocking it.
    public let needsAttention: Bool
    /// Structured bindings to revision authorities (see grammar above).
    public let bindingRefs: [String]
    /// Scan-frame / evidence-asset references.
    public let evidenceRefs: [String]
    /// Optional spatial anchor in a named coordinate space.
    public let spatialPosition: CaptureFieldNoteSpatialPosition?
    public let authoringMethod: CaptureFieldNoteAuthoringMethod
    /// Recording operator when profile authority exists; nil is
    /// anonymous, never fabricated.
    public let operatorID: OperatorProfileID?
    public let status: CaptureFieldNoteStatus
    /// The earlier note this one supersedes (nil when original).
    public let supersedesNoteID: CaptureFieldNoteID?
    /// The note that superseded this one (set only on terminal notes).
    public let supersededByNoteID: CaptureFieldNoteID?
    /// When a `resolved`/`superseded` note reached its terminal state.
    public let resolvedAtUTC: String?

    public init(
        noteID: CaptureFieldNoteID = CaptureFieldNoteID(),
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID? = nil,
        createdAtUTC: String = BundleTimestamp.utcString(from: Date()),
        sessionTimestampSeconds: Double? = nil,
        category: CaptureFieldNoteCategory,
        text: String,
        severity: CaptureFieldNoteSeverity? = nil,
        needsAttention: Bool = false,
        bindingRefs: [String] = [],
        evidenceRefs: [String] = [],
        spatialPosition: CaptureFieldNoteSpatialPosition? = nil,
        authoringMethod: CaptureFieldNoteAuthoringMethod = .typed,
        operatorID: OperatorProfileID? = nil,
        status: CaptureFieldNoteStatus = .active,
        supersedesNoteID: CaptureFieldNoteID? = nil,
        supersededByNoteID: CaptureFieldNoteID? = nil,
        resolvedAtUTC: String? = nil
    ) throws {
        let normalizedText = SchemaOwnedText.nfc(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !normalizedText.isEmpty else {
            throw CaptureFieldNoteError.emptyText
        }
        guard normalizedText.utf8.count <= Self.maxTextUTF8Bytes else {
            throw CaptureFieldNoteError.textTooLong(
                normalizedText.utf8.count
            )
        }
        let normalizedBindings = SchemaOwnedText.nfc(bindingRefs)
        for ref in normalizedBindings {
            guard FieldAuthorityGrammar.isBindingRef(ref) else {
                throw CaptureFieldNoteError.invalidBindingRef(ref)
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        for ref in normalizedEvidence {
            guard FieldAuthorityGrammar.isEvidenceRef(ref) else {
                throw CaptureFieldNoteError.invalidEvidenceRef(ref)
            }
        }
        if let supersedesNoteID, supersedesNoteID == noteID {
            throw CaptureFieldNoteError.selfSupersession
        }
        if let seconds = sessionTimestampSeconds, !seconds.isFinite {
            throw CaptureFieldNoteError.invalidSpatialPosition
        }
        self.noteID = noteID
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.createdAtUTC = createdAtUTC
        self.sessionTimestampSeconds =
            sessionTimestampSeconds.map { max(0, $0) }
        self.category = category
        self.text = normalizedText
        self.severity = severity
        self.needsAttention = needsAttention
        self.bindingRefs = normalizedBindings
        self.evidenceRefs = normalizedEvidence
        self.spatialPosition = spatialPosition
        self.authoringMethod = authoringMethod
        self.operatorID = operatorID
        self.status = status
        self.supersedesNoteID = supersedesNoteID
        self.supersededByNoteID = supersededByNoteID
        self.resolvedAtUTC = resolvedAtUTC
    }

    public var id: CaptureFieldNoteID { noteID }

    /// Terminal notes never mutate again.
    public var isTerminal: Bool {
        status != .active
    }

    /// Copy of this note marked `resolved` (a terminal lifecycle
    /// transition, never a rewrite of the recorded content).
    public func resolving(
        resolvedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> CaptureFieldNote {
        guard status == .active else {
            throw CaptureFieldNoteError.noteAlreadyTerminal
        }
        return try CaptureFieldNote(
            noteID: noteID,
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            createdAtUTC: createdAtUTC,
            sessionTimestampSeconds: sessionTimestampSeconds,
            category: category,
            text: text,
            severity: severity,
            needsAttention: needsAttention,
            bindingRefs: bindingRefs,
            evidenceRefs: evidenceRefs,
            spatialPosition: spatialPosition,
            authoringMethod: authoringMethod,
            operatorID: operatorID,
            status: .resolved,
            supersedesNoteID: supersedesNoteID,
            supersededByNoteID: supersededByNoteID,
            resolvedAtUTC: resolvedAtUTC
        )
    }

    /// Copy of this note marked `superseded` by `replacementID`.
    public func superseding(
        by replacementID: CaptureFieldNoteID,
        resolvedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> CaptureFieldNote {
        guard status == .active else {
            throw CaptureFieldNoteError.noteAlreadyTerminal
        }
        guard replacementID != noteID else {
            throw CaptureFieldNoteError.selfSupersession
        }
        return try CaptureFieldNote(
            noteID: noteID,
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            createdAtUTC: createdAtUTC,
            sessionTimestampSeconds: sessionTimestampSeconds,
            category: category,
            text: text,
            severity: severity,
            needsAttention: needsAttention,
            bindingRefs: bindingRefs,
            evidenceRefs: evidenceRefs,
            spatialPosition: spatialPosition,
            authoringMethod: authoringMethod,
            operatorID: operatorID,
            status: .superseded,
            supersedesNoteID: supersedesNoteID,
            supersededByNoteID: replacementID,
            resolvedAtUTC: resolvedAtUTC
        )
    }

    private enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case createdAtUTC = "created_at"
        case sessionTimestampSeconds = "session_timestamp_seconds"
        case category
        case text
        case severity
        case needsAttention = "needs_attention"
        case bindingRefs = "binding_refs"
        case evidenceRefs = "evidence_refs"
        case spatialPosition = "spatial_position"
        case authoringMethod = "authoring_method"
        case operatorID = "operator_id"
        case status
        case supersedesNoteID = "supersedes_note_id"
        case supersededByNoteID = "superseded_by_note_id"
        case resolvedAtUTC = "resolved_at"
    }

    /// Copy of this note bound to `sessionID` — used by the working
    /// set when a note recorded before the session foundation commit
    /// is replayed against a now-known session authority.
    public func withSessionBinding(
        _ sessionID: CaptureSessionID
    ) throws -> CaptureFieldNote {
        if let existing = captureSessionID {
            guard existing == sessionID else {
                throw CaptureFieldNoteError.invalidBindingRef(
                    sessionID.description
                )
            }
            return self
        }
        return try CaptureFieldNote(
            noteID: noteID,
            captureRevisionID: captureRevisionID,
            captureSessionID: sessionID,
            createdAtUTC: createdAtUTC,
            sessionTimestampSeconds: sessionTimestampSeconds,
            category: category,
            text: text,
            severity: severity,
            needsAttention: needsAttention,
            bindingRefs: bindingRefs,
            evidenceRefs: evidenceRefs,
            spatialPosition: spatialPosition,
            authoringMethod: authoringMethod,
            operatorID: operatorID,
            status: status,
            supersedesNoteID: supersedesNoteID,
            supersededByNoteID: supersededByNoteID,
            resolvedAtUTC: resolvedAtUTC
        )
    }
}

/// The persisted field-notes document (issue #375), written to
/// `session/field-notes.json` inside the working set and carried into
/// the finalized bundle as a canonical `user_annotation` payload —
/// operator-authored context that survives finalize/export/import.
/// Bundles captured before this feature simply lack the file; readers
/// treat its absence as an empty collection.
public struct CaptureFieldNoteDocument: Codable, Sendable, Equatable {
    public static let path = "session/field-notes.json"
    public static let schemaName = "htdt.capture.field_notes"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID?
    public let updatedAtUTC: String
    public let notes: [CaptureFieldNote]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID? = nil,
        updatedAtUTC: String = BundleTimestamp.utcString(from: Date()),
        notes: [CaptureFieldNote]
    ) {
        self.schema = Self.schemaName
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.updatedAtUTC = updatedAtUTC
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case updatedAtUTC = "updated_at"
        case notes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws
        -> CaptureFieldNoteDocument
    {
        try JSONDecoder().decode(CaptureFieldNoteDocument.self, from: data)
    }
}

/// Read helpers over a note collection (issue #375): chronological and
/// category views for the library, plus the pre-finalization
/// needs-attention surfacing Review uses.
public struct CaptureFieldNoteCollection: Sendable, Equatable {
    public let notes: [CaptureFieldNote]

    public init(notes: [CaptureFieldNote] = []) {
        self.notes = notes
    }

    /// Chronological order: creation timestamp, then note id for a
    /// stable total order on ties.
    public var chronological: [CaptureFieldNote] {
        notes.sorted {
            ($0.createdAtUTC, $0.noteID.rawValue.uuidString)
                < ($1.createdAtUTC, $1.noteID.rawValue.uuidString)
        }
    }

    /// Category-grouped view for the library's category browsing.
    public func grouped(
        byCategory ordering: [CaptureFieldNoteCategory]? = nil
    ) -> [(CaptureFieldNoteCategory, [CaptureFieldNote])] {
        var groups: [String: [CaptureFieldNote]] = [:]
        for note in notes {
            groups[note.category.rawValue, default: []].append(note)
        }
        var order: [String] = []
        if let ordering {
            for category in ordering
            where groups[category.rawValue] != nil {
                order.append(category.rawValue)
            }
        }
        order.append(contentsOf: groups.keys.sorted().filter {
            !order.contains($0)
        })
        return order.compactMap { key in
            guard let members = groups[key] else { return nil }
            return (
                CaptureFieldNoteCategory(rawValue: key),
                members.sorted {
                    ($0.createdAtUTC, $0.noteID.rawValue.uuidString)
                        < ($1.createdAtUTC, $1.noteID.rawValue.uuidString)
                }
            )
        }
    }

    /// Active notes flagged for attention — surfaced in Review before
    /// Finalize; they never auto-block finalization.
    public var unresolvedAttention: [CaptureFieldNote] {
        chronological.filter {
            $0.needsAttention && $0.status == .active
        }
    }

    /// Non-terminal notes (the live collection a Review shows by
    /// default).
    public var active: [CaptureFieldNote] {
        chronological.filter { $0.status == .active }
    }

    public func note(_ id: CaptureFieldNoteID)
        -> CaptureFieldNote?
    {
        notes.first { $0.noteID == id }
    }
}

/// Parent↔child comparison of two field-note collections (issue #375):
/// which notes were added on the child, resolved on the child, or
/// superseded by a child note. Differences key on note identity — a
/// note id present on both sides but terminal on the child reports as
/// resolved/superseded, not added-or-removed.
public struct CaptureFieldNoteDiff: Sendable, Equatable {
    /// Notes present only on the child (authored on this revision).
    public let added: [CaptureFieldNote]
    /// Child notes superseding a parent note (the replacements).
    public let superseding: [CaptureFieldNote]
    /// Parent notes the child superseded.
    public let superseded: [CaptureFieldNote]
    /// Notes active on the parent and resolved on the child.
    public let resolved: [CaptureFieldNote]
    /// Parent notes unchanged on the child.
    public let carried: [CaptureFieldNote]

    public init(
        added: [CaptureFieldNote],
        superseding: [CaptureFieldNote],
        superseded: [CaptureFieldNote],
        resolved: [CaptureFieldNote],
        carried: [CaptureFieldNote]
    ) {
        self.added = added
        self.superseding = superseding
        self.superseded = superseded
        self.resolved = resolved
        self.carried = carried
    }

    /// An empty diff — the convenience default when the parent carried
    /// no field notes at all.
    public static let empty = CaptureFieldNoteDiff(
        added: [],
        superseding: [],
        superseded: [],
        resolved: [],
        carried: []
    )

    public static func compare(
        parent: CaptureFieldNoteCollection,
        child: CaptureFieldNoteCollection
    ) -> CaptureFieldNoteDiff {
        let parentByID = Dictionary(
            parent.notes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let childByID = Dictionary(
            child.notes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var added: [CaptureFieldNote] = []
        var superseding: [CaptureFieldNote] = []
        var superseded: [CaptureFieldNote] = []
        var resolved: [CaptureFieldNote] = []
        var carried: [CaptureFieldNote] = []
        for note in child.notes {
            guard let prior = parentByID[note.noteID] else {
                if let supersedes = note.supersedesNoteID,
                   let old = parentByID[supersedes]
                {
                    superseding.append(note)
                    superseded.append(old)
                } else {
                    added.append(note)
                }
                continue
            }
            if prior.status == .active, note.status == .resolved {
                resolved.append(note)
            } else {
                carried.append(prior)
            }
        }
        // A parent note superseded by a child replacement reports once,
        // on the replacement — ids absent on the child that are not
        // supersession targets stay carried (the child's collection
        // keeps superseded notes, so absence means unknown lineage).
        return CaptureFieldNoteDiff(
            added: added,
            superseding: superseding,
            superseded: superseded,
            resolved: resolved,
            carried: carried
        )
    }
}
