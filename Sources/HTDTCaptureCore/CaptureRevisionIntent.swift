import Foundation

/// Versioned vocabulary for how a capture revision relates to its
/// parent (issue bolph71656-ai/HTDT-Capture#319). The kind is declared at `revision/intent.json`
/// in every non-root bundle — a plain "revised" flag can never express
/// whether the child re-observed the room or only corrected records.
public enum CaptureRevisionKind: String, Codable, Sendable {
    /// First revision of a series: no parent, all authority fresh.
    case initialCapture = "initial_capture"
    /// Child produced by rescanning the room: fresh coordinate space,
    /// fresh sensor evidence, parent retained as lineage only.
    case physicalRescan = "physical_rescan"
    /// Child produced without rescanning: parent's sensor evidence is
    /// reused byte-for-byte, parent's capture-session and coordinate-
    /// space identities are carried forward, and only semantic records
    /// (annotations, measurements, equipment identity) may differ.
    case semanticCorrection = "semantic_correction"
    /// Child produced by deriving records from the parent's evidence
    /// without operator re-attestation (a review-time recompute). v1
    /// reserves the kind; no builder emits it yet.
    case derivedReview = "derived_review"
}

public enum CaptureRevisionIntentError: Error, Sendable, Equatable {
    case nonRootWithoutParent
    case nonInitialWithoutDigest
    case invalidTimestamp
    case unboundedRefList
    case encodedDocumentMismatch
}

/// One record link in a semantic diff: the canonical payload path plus
/// the record identity inside it (entity id, measurement id, ...).
public struct CaptureRevisionRecordRef:
    Codable,
    Sendable,
    Equatable
{
    /// Bundle path of the semantic payload (`annotations/entities.json`
    /// etc.) — never an evidence/session path.
    public let payloadPath: String
    /// Stable record identifier within the payload.
    public let recordID: String

    public init(payloadPath: String, recordID: String) throws {
        let path = SchemaOwnedText.nfc(payloadPath)
        let id = SchemaOwnedText.nfc(recordID)
        guard !path.isEmpty, !id.isEmpty else {
            throw CaptureRevisionIntentError.unboundedRefList
        }
        self.payloadPath = path
        self.recordID = id
    }

    private enum CodingKeys: String, CodingKey {
        case payloadPath = "payload_path"
        case recordID = "record_id"
    }
}

/// Persisted `revision/intent.json` (issue bolph71656-ai/HTDT-Capture#319): the child revision's
/// declared relationship to its parent — kind, the parent's exact
/// bundle digest, which capture-session/coordinate-space authorities
/// were reused, and the semantic diff (added/changed/superseded
/// records plus reused evidence refs) the correction performed.
public struct CaptureRevisionIntentDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.revision-intent"
    public static let schemaVersion = "1.0.0"
    /// Bounded record-ref lists keep the intent document from becoming
    /// an unbounded audit log; a correction touching more records is
    /// still valid — it summarizes the first N links deterministically.
    public static let maximumRecordRefs = 256

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    /// Null only for `initial_capture` roots.
    public let parentRevisionID: CaptureRevisionID?
    /// SHA-256 of the parent bundle's canonical `manifest.json` bytes —
    /// the exact authority this revision derives from. Null for
    /// `initial_capture`; required for every child kind.
    public let parentBundleSHA256: String?
    public let revisionKind: CaptureRevisionKind
    /// `capture_session_id` authorities carried forward from the parent
    /// (semantic kinds only — a physical rescan lists none).
    public let reusedCaptureSessionIDs: [CaptureSessionID]
    /// `coordinate_space_id` authorities carried forward from the
    /// parent (semantic kinds only).
    public let reusedCoordinateSpaceIDs: [CoordinateSpaceID]
    /// Semantic records this revision adds (new entity ids, ...).
    public let addedRecordRefs: [CaptureRevisionRecordRef]
    /// Semantic records present in the parent whose content changed.
    public let changedRecordRefs: [CaptureRevisionRecordRef]
    /// Parent semantic records removed/superseded by this revision.
    public let supersededRecordRefs: [CaptureRevisionRecordRef]
    /// `path:` refs of parent payloads reused byte-for-byte beyond the
    /// verbatim copy set — primarily the semantic documents re-sealed
    /// unchanged. Bounded by `maximumRecordRefs` path entries.
    public let reusedEvidenceRefs: [String]
    /// Operator note explaining why the correction was made.
    public let correctionNote: String?
    public let createdAtUTC: String

    public init(
        captureRevisionID: CaptureRevisionID,
        parentRevisionID: CaptureRevisionID?,
        parentBundleSHA256: String?,
        revisionKind: CaptureRevisionKind,
        reusedCaptureSessionIDs: [CaptureSessionID] = [],
        reusedCoordinateSpaceIDs: [CoordinateSpaceID] = [],
        addedRecordRefs: [CaptureRevisionRecordRef] = [],
        changedRecordRefs: [CaptureRevisionRecordRef] = [],
        supersededRecordRefs: [CaptureRevisionRecordRef] = [],
        reusedEvidenceRefs: [String] = [],
        correctionNote: String? = nil,
        createdAtUTC: String
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(createdAtUTC) else {
            throw CaptureRevisionIntentError.invalidTimestamp
        }
        if revisionKind == .initialCapture {
            guard parentRevisionID == nil else {
                throw CaptureRevisionIntentError
                    .nonRootWithoutParent
            }
        } else {
            guard parentRevisionID != nil else {
                throw CaptureRevisionIntentError
                    .nonRootWithoutParent
            }
            guard let digest = parentBundleSHA256,
                  (try? EvidenceSHA256(digest)) != nil
            else {
                throw CaptureRevisionIntentError
                    .nonInitialWithoutDigest
            }
        }
        if let digest = parentBundleSHA256 {
            _ = try EvidenceSHA256(digest)
        }
        guard addedRecordRefs.count
                <= Self.maximumRecordRefs,
              changedRecordRefs.count <= Self.maximumRecordRefs,
              supersededRecordRefs.count <= Self.maximumRecordRefs,
              reusedEvidenceRefs.count <= Self.maximumRecordRefs
        else {
            throw CaptureRevisionIntentError.unboundedRefList
        }
        let normalizedNote = SchemaOwnedText
            .nfc(correctionNote)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.parentRevisionID = parentRevisionID
        self.parentBundleSHA256 = parentBundleSHA256
        self.revisionKind = revisionKind
        self.reusedCaptureSessionIDs = reusedCaptureSessionIDs
        self.reusedCoordinateSpaceIDs = reusedCoordinateSpaceIDs
        self.addedRecordRefs = addedRecordRefs
        self.changedRecordRefs = changedRecordRefs
        self.supersededRecordRefs = supersededRecordRefs
        self.reusedEvidenceRefs = reusedEvidenceRefs.sorted()
        self.correctionNote =
            normalizedNote?.isEmpty == true ? nil : normalizedNote
        self.createdAtUTC = createdAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case parentRevisionID = "parent_revision_id"
        case parentBundleSHA256 = "parent_bundle_sha256"
        case revisionKind = "revision_kind"
        case reusedCaptureSessionIDs = "reused_capture_session_ids"
        case reusedCoordinateSpaceIDs = "reused_coordinate_space_ids"
        case addedRecordRefs = "added_record_refs"
        case changedRecordRefs = "changed_record_refs"
        case supersededRecordRefs = "superseded_record_refs"
        case reusedEvidenceRefs = "reused_evidence_refs"
        case correctionNote = "correction_note"
        case createdAtUTC = "created_at"
    }
}

/// Encoded `revision/intent.json` ready for staging (issue bolph71656-ai/HTDT-Capture#319).
public struct CaptureRevisionIntentPackage: Sendable, Equatable {
    public static let path = "revision/intent.json"

    public let document: CaptureRevisionIntentDocument
    public let data: Data

    public init(document: CaptureRevisionIntentDocument, data: Data) {
        self.document = document
        self.data = data
    }

    public var payloadDeclaration: BundlePayloadDeclaration {
        let sessionRefs = document.reusedCaptureSessionIDs
            .sorted { $0.description < $1.description }
            .map { "capture_session:" + $0.description }
        return BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical,
            sourceRefs: sessionRefs.isEmpty ? nil : sessionRefs
        )
    }
}

public enum CaptureRevisionIntentPackageBuilder {
    public static func build(
        document: CaptureRevisionIntentDocument
    ) throws -> CaptureRevisionIntentPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)

        guard let decoded = try? JSONDecoder().decode(
            CaptureRevisionIntentDocument.self,
            from: data
        ), decoded == document else {
            throw CaptureRevisionIntentError
                .encodedDocumentMismatch
        }
        return CaptureRevisionIntentPackage(
            document: document,
            data: data
        )
    }
}
