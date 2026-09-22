import Foundation

public struct OperatorProfileID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// An optional app-local author/operator profile (issue #310). It is
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
/// `derived/operator-profiles.json` payload (issue #310). Author
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
        sourceRefs: [String] = [AnnotationEvidencePackage.path]
    ) throws {
        self.document = document
        self.sourceRefs = sourceRefs.sorted()
        self.data = try FieldAuthorityCoding.encoder().encode(document)
    }
}
