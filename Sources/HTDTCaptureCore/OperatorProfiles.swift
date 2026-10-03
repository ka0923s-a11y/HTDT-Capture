import Foundation

public struct OperatorProfileID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// An optional app-local author/operator profile (issue bolph71656-ai/HTDT-Capture#310). It is
/// explicit identity metadata: created and named by the operator,
/// stored under a stable identifier, and carried on user-attested
/// records. It is never an account, a login, or something inferred —
/// records without an author binding stay anonymous and valid.
public struct OperatorProfile: Codable, Sendable, Equatable {
    public let operatorID: OperatorProfileID
    /// Operator-entered display name (never a login credential).
    public let displayName: String
    /// Optional free-text organization label.
    public let organization: String?
    /// Optional free-text role label (e.g. "installer", "calibrator").
    public let role: String?
    public let createdAtUTC: String

    public init(
        operatorID: OperatorProfileID = OperatorProfileID(),
        displayName: String,
        organization: String? = nil,
        role: String? = nil,
        createdAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let normalizedName = SchemaOwnedText.nfc(displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw FieldAuthorityModelError.emptyField("display_name")
        }
        guard SchemaTimestampText.isUTCTimestamp(createdAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(createdAtUTC)
        }
        let normalizedOrganization = SchemaOwnedText
            .nfc(organization)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRole = SchemaOwnedText.nfc(role)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.operatorID = operatorID
        self.displayName = normalizedName
        self.organization =
            normalizedOrganization?.isEmpty == true
                ? nil : normalizedOrganization
        self.role =
            normalizedRole?.isEmpty == true ? nil : normalizedRole
        self.createdAtUTC = createdAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case operatorID = "operator_id"
        case displayName = "display_name"
        case organization
        case role
        case createdAtUTC = "created_at_utc"
    }
}

/// The revision-scoped operator registry persisted as the derived
/// `derived/operator-profiles.json` payload (issue bolph71656-ai/HTDT-Capture#310). Author
/// bindings on annotations, measurements, field evidence, settings
/// observations, wiring routes and identity attestations reference
/// `operator_id` values defined here.
public struct OperatorProfileDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.operator-profiles"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    public let operators: [OperatorProfile]

    public init(
        captureRevisionID: CaptureRevisionID,
        operators: [OperatorProfile],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let ids = operators.map(\.operatorID)
        guard Set(ids).count == ids.count else {
            throw FieldAuthorityModelError.duplicateRecord("operator_id")
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.operators = operators
    }

    public func contains(_ id: OperatorProfileID) -> Bool {
        operators.contains { $0.operatorID == id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case operators
    }
}

/// App-local operator roster (issue bolph71656-ai/HTDT-Capture#458): profiles the operator has
/// saved once, reused across captures instead of being re-typed at
/// every Author attestation. The roster is app-owned identity
/// metadata — it lives beside the equipment catalog at the capture
/// root, never inside a bundle; bundles only carry the profiles an
/// Author action actually committed.
public struct HTDTOperatorProfileRoster: Codable, Sendable, Equatable {
    public static let schema = "htdt.app.operator-roster"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public var updatedAtUTC: String
    public var operators: [OperatorProfile]

    public init(
        operators: [OperatorProfile],
        updatedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let ids = operators.map(\.operatorID)
        guard Set(ids).count == ids.count else {
            throw FieldAuthorityModelError.duplicateRecord("operator_id")
        }
        guard SchemaTimestampText.isUTCTimestamp(updatedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(updatedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.updatedAtUTC = updatedAtUTC
        self.operators = operators
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case updatedAtUTC = "updated_at_utc"
        case operators
    }
}

public enum HTDTOperatorRosterError: Error, Sendable, Equatable {
    /// The file exists but fails schema/JSON validation — surfaced to
    /// the caller rather than silently wiped, matching the mission
    /// inbox's unreadable-document stance.
    case unreadableRoster
}

/// File-backed store for the app-local operator roster (legacy bolph71656-ai/HTDT-Capture#458).
/// `load` treats a missing file as an empty roster and a corrupt one
/// as an error — the operator's saved identities are never silently
/// dropped. Writes are atomic via a tmp file + move.
public struct HTDTOperatorProfileRosterStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// App-local slot directly under the capture root — outside
    /// `finalized/`, `exports/` and `working/`, so the persisted-
    /// capture inventory never classifies it as a capture artifact.
    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "operator-roster.json",
            isDirectory: false
        )
    }

    public func load() throws -> HTDTOperatorProfileRoster {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return try HTDTOperatorProfileRoster(operators: [])
        }
        guard let data = try? Data(contentsOf: fileURL),
              let roster = try? JSONDecoder().decode(
                HTDTOperatorProfileRoster.self,
                from: data
              ),
              roster.schemaName
                == HTDTOperatorProfileRoster.schema,
              roster.schemaVersionValue
                == HTDTOperatorProfileRoster.schemaVersion
        else {
            throw HTDTOperatorRosterError.unreadableRoster
        }
        return roster
    }

    /// Adds or replaces the profile under its `operator_id` — saving
    /// an Author attestation refreshes the roster's remembered
    /// identity for that operator.
    @discardableResult
    public func upsert(
        _ profile: OperatorProfile
    ) throws -> HTDTOperatorProfileRoster {
        var operators = (try load().operators).filter {
            $0.operatorID != profile.operatorID
        }
        operators.append(profile)
        let roster = try HTDTOperatorProfileRoster(
            operators: operators
        )
        try save(roster)
        return roster
    }

    @discardableResult
    public func remove(
        operatorID: OperatorProfileID
    ) throws -> HTDTOperatorProfileRoster {
        let operators = (try load().operators).filter {
            $0.operatorID != operatorID
        }
        let roster = try HTDTOperatorProfileRoster(
            operators: operators
        )
        try save(roster)
        return roster
    }

    private func save(
        _ roster: HTDTOperatorProfileRoster
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try FieldAuthorityCoding.encoder().encode(roster)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(
            at: temporary,
            to: fileURL
        )
    }
}

/// Encoded `OperatorProfileDocument` ready for the working-set store.
public struct OperatorProfilePackage: Sendable, Equatable {
    public static let path = "derived/operator-profiles.json"

    public let document: OperatorProfileDocument
    public let data: Data
    /// Manifest `source_refs` (derived-role payloads require at least
    /// one): the canonical collections that carry author bindings.
    public let sourceRefs: [String]

    public init(
        document: OperatorProfileDocument,
        sourceRefs: [String] = ["path:" + AnnotationEvidencePackage.path]
    ) throws {
        self.document = document
        self.sourceRefs = sourceRefs.sorted()
        self.data = try FieldAuthorityCoding.encoder().encode(document)
    }
}
