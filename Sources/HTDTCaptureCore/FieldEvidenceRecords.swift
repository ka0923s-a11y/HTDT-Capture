import Foundation

public struct FieldEvidenceID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// The typed purpose of a field-evidence record (issue #300). The kind
/// is machine-enumerated authority, never a display label.
public enum FieldEvidenceKind: String, Codable, Sendable, CaseIterable {
    case installationPhoto = "installation_photo"
    case dimensionVerification = "dimension_verification"
    case equipmentIdentity = "equipment_identity"
    case routingVerification = "routing_verification"
    case microphoneSetup = "microphone_setup"
    case treatmentInstallation = "treatment_installation"
    case generalNote = "general_note"
    case externalDocument = "external_document"
}

/// Media types the field-evidence asset store accepts. Canonical
/// extensions are fixed per media type so a path's bytes, declared
/// media type, and filename extension can never disagree.
public enum FieldEvidenceMediaType: String, Codable, Sendable {
    case heic = "image/heic"
    case jpeg = "image/jpeg"
    case png = "image/png"
    case pdf = "application/pdf"
    case binary = "application/octet-stream"

    public var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .pdf: return "pdf"
        case .binary: return "bin"
        }
    }

    /// Captured close-up photos may only be image payloads.
    public var isCaptureEligible: Bool {
        switch self {
        case .heic, .jpeg, .png:
            return true
        case .pdf, .binary:
            return false
        }
    }
}

/// Bundle-path conventions for field-evidence binary assets
/// (issues #300/#314). Captured close-ups and imported documents live
/// under separate directories so provenance is pinned by the manifest
/// binding alone — a path under `captured/` can never masquerade as an
/// imported document or carry spatial authority.
public enum FieldEvidenceAssetPaths {
    public static let capturedDirectory = "evidence/field/captured"
    public static let importedDirectory = "evidence/field/imported"

    public static func captured(
        evidenceID: FieldEvidenceID,
        mediaType: FieldEvidenceMediaType
    ) -> String {
        capturedDirectory + "/" + evidenceID.description + "."
            + mediaType.fileExtension
    }

    public static func imported(
        evidenceID: FieldEvidenceID,
        mediaType: FieldEvidenceMediaType
    ) -> String {
        importedDirectory + "/" + evidenceID.description + "."
            + mediaType.fileExtension
    }
}

/// How the asset bytes (or absence of them) entered the capture
/// (issue #300). A linked scan frame keeps its canonical frame path —
/// bytes are never duplicated; a captured close-up is a dedicated
/// non-spatial photo (issue #314); an imported file keeps its exact
/// bytes and hash; `authored_note` marks asset-free text records.
public enum FieldEvidenceAcquisition: String, Codable, Sendable {
    case linkedFrame = "linked_frame"
    case capturedInApp = "captured_in_app"
    case importedFile = "imported_file"
    case authoredNote = "authored_note"
}

/// The asset a field-evidence record points at (issue #300). Exactly
/// one of three variants, discriminated by `kind`:
/// - `canonical_frame`: wraps an existing `evidence/frames/<id>`
///   descriptor without duplicating its bytes;
/// - `captured_photo`: a dedicated close-up photo persisted under
///   `evidence/field/captured/` — image evidence only, explicitly
///   without spatial authority (issue #314);
/// - `imported_file`: an external document/photo imported verbatim
///   under `evidence/field/imported/`, retaining exact bytes, SHA-256,
///   media type and original filename.
public struct FieldEvidenceAsset: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case canonicalFrame = "canonical_frame"
        case capturedPhoto = "captured_photo"
        case importedFile = "imported_file"
    }

    public let kind: Kind
    /// `path:evidence/frames/<uuid>.json` (or `frame:<uuid>`) —
    /// `canonical_frame` only.
    public let frameRef: String?
    /// Bundle path under `evidence/field/` — captured/imported only.
    public let assetPath: String?
    public let sha256: EvidenceSHA256?
    public let mediaType: FieldEvidenceMediaType?
    /// Source filename for imported assets; never for captured.
    public let originalFilename: String?
    /// Captured-image pixel dimensions, when recorded.
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public static func canonicalFrame(frameRef: String) throws
        -> FieldEvidenceAsset
    {
        try FieldEvidenceAsset(
            kind: .canonicalFrame,
            frameRef: frameRef
        )
    }

    public static func capturedPhoto(
        assetPath: String,
        sha256: EvidenceSHA256,
        mediaType: FieldEvidenceMediaType,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) throws -> FieldEvidenceAsset {
        try FieldEvidenceAsset(
            kind: .capturedPhoto,
            assetPath: assetPath,
            sha256: sha256,
            mediaType: mediaType,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    public static func importedFile(
        assetPath: String,
        sha256: EvidenceSHA256,
        mediaType: FieldEvidenceMediaType,
        originalFilename: String
    ) throws -> FieldEvidenceAsset {
        try FieldEvidenceAsset(
            kind: .importedFile,
            assetPath: assetPath,
            sha256: sha256,
            mediaType: mediaType,
            originalFilename: originalFilename
        )
    }

    private init(
        kind: Kind,
        frameRef: String? = nil,
        assetPath: String? = nil,
        sha256: EvidenceSHA256? = nil,
        mediaType: FieldEvidenceMediaType? = nil,
        originalFilename: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) throws {
        let normalizedFrameRef = SchemaOwnedText.nfc(frameRef)
        let normalizedPath = SchemaOwnedText.nfc(assetPath)
        switch kind {
        case .canonicalFrame:
            guard let ref = normalizedFrameRef,
                  Self.isCanonicalFrameRef(ref),
                  normalizedPath == nil,
                  sha256 == nil,
                  mediaType == nil,
                  originalFilename == nil,
                  pixelWidth == nil,
                  pixelHeight == nil
            else {
                throw FieldAuthorityModelError.missingAssetAuthority
            }
        case .capturedPhoto, .importedFile:
            guard let path = normalizedPath,
                  let mediaType,
                  sha256 != nil,
                  normalizedFrameRef == nil
            else {
                throw FieldAuthorityModelError.missingAssetAuthority
            }
            guard mediaType.fileExtension
                == Self.pathExtension(path)
            else {
                throw FieldAuthorityModelError.invalidAssetPath(path)
            }
            if kind == .capturedPhoto {
                guard mediaType.isCaptureEligible,
                      Self.hasCanonicalStem(
                          path,
                          directory: FieldEvidenceAssetPaths
                              .capturedDirectory
                      ),
                      originalFilename == nil
                else {
                    throw FieldAuthorityModelError
                        .invalidAssetPath(path)
                }
            } else {
                let name = originalFilename?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard Self.hasCanonicalStem(
                    path,
                    directory: FieldEvidenceAssetPaths.importedDirectory
                ), let name, !name.isEmpty else {
                    throw FieldAuthorityModelError
                        .invalidAssetPath(path)
                }
            }
        }
        if let pixelWidth, pixelWidth <= 0 {
            throw FieldAuthorityModelError.missingAssetAuthority
        }
        if let pixelHeight, pixelHeight <= 0 {
            throw FieldAuthorityModelError.missingAssetAuthority
        }
        self.kind = kind
        self.frameRef = normalizedFrameRef
        self.assetPath = normalizedPath
        self.sha256 = sha256
        self.mediaType = mediaType
        self.originalFilename = SchemaOwnedText.nfc(originalFilename)
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// A captured close-up or imported file carries no spatial
    /// authority — only a `canonical_frame` asset refers to a real
    /// ARKit observation. This distinction is machine-readable via
    /// `kind` and `asset_path` (issue #314).
    public var carriesSpatialAuthority: Bool {
        kind == .canonicalFrame
    }

    /// The bundle path the asset's bytes live at, when the record owns
    /// binary payload (captured/imported). `nil` for linked frames.
    public var payloadPath: String? {
        assetPath
    }

    /// The frame `path:` ref for `canonical_frame` assets — normalized
    /// so both `frame:<id>` and `path:` forms resolve to the same
    /// declared descriptor.
    public var canonicalFramePathRef: String? {
        guard kind == .canonicalFrame,
              let frameRef
        else {
            return nil
        }
        if frameRef.hasPrefix("frame:") {
            let id = String(frameRef.dropFirst("frame:".count))
            return "path:evidence/frames/" + id + ".json"
        }
        return frameRef
    }

    static func isCanonicalFrameRef(_ ref: String) -> Bool {
        let idText: String
        if ref.hasPrefix("frame:") {
            idText = String(ref.dropFirst("frame:".count))
        } else if ref.hasPrefix("path:evidence/frames/"),
                  ref.hasSuffix(".json")
        {
            let name = ref.dropFirst("path:evidence/frames/".count)
                .dropLast(".json".count)
            idText = String(name)
        } else {
            return false
        }
        return UUID(canonicalUUIDv4Text: idText) != nil
    }

    /// The asset filename stem must be a canonical UUIDv4 — the same
    /// canonical-name rule the patterned manifest bindings enforce on
    /// `evidence/field/...` payload paths.
    static func hasCanonicalStem(
        _ path: String,
        directory: String
    ) -> Bool {
        guard path.hasPrefix(directory + "/") else {
            return false
        }
        let name = String(path.dropFirst(directory.count + 1))
        guard !name.contains("/"),
              let dot = name.lastIndex(of: ".")
        else {
            return false
        }
        return UUID(canonicalUUIDv4Text: String(name[..<dot])) != nil
    }

    static func pathExtension(_ path: String) -> String? {
        guard let dot = path.lastIndex(of: ".") else {
            return nil
        }
        return String(path[path.index(after: dot)...])
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case frameRef = "frame_ref"
        case assetPath = "asset_path"
        case sha256
        case mediaType = "media_type"
        case originalFilename = "original_filename"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
    }
}

/// One typed field-evidence record bound to exact authorities of the
/// revision it was collected for (issues #300/#314). `target_refs`
/// names the exact bindings — `entity:<uuid>` annotations,
/// `measurement:<uuid>` measurements, `capture_revision:<uuid>` /
/// `capture_session:<uuid>` scope, `inventory_item:<uuid>`,
/// `task_item:<id>` / `commissioning_check:<id>` task bindings, and
/// `wiring_route:` / `settings_observation:` / `instrument:` /
/// `field_evidence:` doc authorities — using the shared binding-ref
/// grammar. Evidence records describe reality; they never become
/// position, material, or equipment truth.
public struct FieldEvidenceRecord: Codable, Sendable, Equatable {
    public let evidenceID: FieldEvidenceID
    public let kind: FieldEvidenceKind
    /// Short operator-authored description (required, NFC).
    public let title: String
    /// Optional longer free-text note.
    public let note: String?
    public let targetRefs: [String]
    public let asset: FieldEvidenceAsset?
    public let acquisition: FieldEvidenceAcquisition
    /// Revision this evidence was collected for.
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    /// Optional author binding to `derived/operator-profiles.json`
    /// (issue #310).
    public let operatorID: OperatorProfileID?
    /// Optional explicitly authored observation — only ever present
    /// when the operator typed it, never inferred.
    public let observedValue: Double?
    public let observedUnit: MeasurementUnit?
    public let observedValueText: String?

    public init(
        evidenceID: FieldEvidenceID = FieldEvidenceID(),
        kind: FieldEvidenceKind,
        title: String,
        note: String? = nil,
        targetRefs: [String],
        asset: FieldEvidenceAsset?,
        captureRevisionID: CaptureRevisionID,
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date()),
        operatorID: OperatorProfileID? = nil,
        observedValue: Double? = nil,
        observedUnit: MeasurementUnit? = nil,
        observedValueText: String? = nil
    ) throws {
        let normalizedTitle = SchemaOwnedText.nfc(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw FieldAuthorityModelError.emptyField("title")
        }
        let normalizedTargets = SchemaOwnedText.nfc(targetRefs)
        guard !normalizedTargets.isEmpty,
              normalizedTargets.allSatisfy(
                  FieldAuthorityGrammar.isBindingRef
              ),
              Set(normalizedTargets).count == normalizedTargets.count
        else {
            throw FieldAuthorityModelError.unboundReference(
                normalizedTargets.first {
                    !FieldAuthorityGrammar.isBindingRef($0)
                } ?? "target_refs"
            )
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        let acquisition: FieldEvidenceAcquisition
        switch asset?.kind {
        case .canonicalFrame:
            acquisition = .linkedFrame
        case .capturedPhoto:
            acquisition = .capturedInApp
        case .importedFile:
            acquisition = .importedFile
        case nil:
            acquisition = .authoredNote
        }
        // An explicit observation keeps value+unit paired; free text
        // may stand alone for non-numeric observations.
        if observedValue != nil {
            guard observedValue?.isFinite == true,
                  observedUnit != nil
            else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        } else {
            guard observedUnit == nil else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        }
        self.evidenceID = evidenceID
        self.kind = kind
        self.title = normalizedTitle
        self.note = SchemaOwnedText.nfc(note)
        self.targetRefs = normalizedTargets
        self.asset = asset
        self.acquisition = acquisition
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.operatorID = operatorID
        self.observedValue = observedValue
        self.observedUnit = observedUnit
        self.observedValueText = SchemaOwnedText.nfc(observedValueText)
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case kind
        case title
        case note
        case targetRefs = "target_refs"
        case asset
        case acquisition
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case operatorID = "operator_id"
        case observedValue = "observed_value"
        case observedUnit = "observed_unit"
        case observedValueText = "observed_value_text"
    }
}

/// The derived `derived/field-evidence.json` payload (issue #300):
/// the revision's committed set of typed field-evidence records.
/// Every record's `capture_revision_id` must equal the document's
/// bound revision.
public struct FieldEvidenceDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.field-evidence"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    public let records: [FieldEvidenceRecord]

    public init(
        captureRevisionID: CaptureRevisionID,
        records: [FieldEvidenceRecord],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let ids = records.map(\.evidenceID)
        guard Set(ids).count == ids.count else {
            throw FieldAuthorityModelError
                .duplicateRecord("evidence_id")
        }
        guard records.allSatisfy({
            $0.captureRevisionID == captureRevisionID
        }) else {
            throw FieldAuthorityModelError
                .unboundReference("capture_revision_id")
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case records
    }
}

/// A binary asset payload committed with the field-evidence document —
/// one captured close-up photo or one imported file, byte-exact with a
/// fixed manifest declaration derived from its path (#300/#314).
public struct FieldEvidenceAssetPayload: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let declaration: BundlePayloadDeclaration

    public init(path: String, data: Data) throws {
        try BundleLogicalPath.validate(path)
        guard !data.isEmpty else {
            throw FieldAuthorityModelError.invalidAssetPath(path)
        }
        let binding = BundleReservedPaths.binding(for: path)
        guard let binding else {
            throw FieldAuthorityModelError.invalidAssetPath(path)
        }
        self.path = path
        self.data = data
        self.declaration = BundlePayloadDeclaration(
            path: path,
            mediaType: binding.mediaType,
            producer: binding.producer,
            provenanceClass: binding.provenanceClass,
            role: binding.role,
            sourceRefs: []
        )
    }
}

/// Encoded `FieldEvidenceDocument` ready for the working-set store.
/// Manifest `source_refs` are the sorted union of every referenced
/// canonical collection plus every asset payload path and linked frame
/// descriptor — a derived-role declaration must name what it derives
/// from.
public struct FieldEvidencePackage: Sendable, Equatable {
    public static let path = "derived/field-evidence.json"

    public let document: FieldEvidenceDocument
    public let data: Data
    public let sourceRefs: [String]

    public init(document: FieldEvidenceDocument) throws {
        var refs = Set<String>()
        var bindsEntities = false
        var bindsMeasurements = false
        var bindsOperators = false
        for record in document.records {
            if let pathRef = record.asset?.canonicalFramePathRef {
                refs.insert(pathRef)
            }
            if let payloadPath = record.asset?.payloadPath {
                refs.insert("path:" + payloadPath)
            }
            if record.operatorID != nil {
                bindsOperators = true
            }
            for target in record.targetRefs {
                if target.hasPrefix("entity:") {
                    bindsEntities = true
                } else if target.hasPrefix("measurement:") {
                    bindsMeasurements = true
                } else if target.hasPrefix("instrument:") {
                    refs.insert(InstrumentProfilePackage.sourceRef)
                } else if target.hasPrefix("wiring_route:") {
                    refs.insert(AsBuiltWiringPackage.sourceRef)
                } else if target.hasPrefix("settings_observation:") {
                    refs.insert(InstalledSettingsPackage.sourceRef)
                } else if target.hasPrefix("operator:") {
                    bindsOperators = true
                } else if target.hasPrefix("inventory_item:") {
                    refs.insert("path:" + TheaterAuthorityPackage.path)
                }
            }
        }
        if bindsEntities {
            refs.insert("path:" + AnnotationEvidencePackage.path)
        }
        if bindsMeasurements {
            refs.insert("path:" + MeasurementEvidencePackage.path)
        }
        if bindsOperators {
            refs.insert("path:" + OperatorProfilePackage.path)
        }
        // A derived payload always names at least one source; a pure
        // revision-scoped record set still derives from the session.
        if refs.isEmpty {
            refs.insert(
                "path:session/capture-session.json"
            )
        }
        self.document = document
        self.sourceRefs = refs.sorted()
        self.data = try FieldAuthorityCoding.encoder()
            .encode(document)
    }
}
