import Foundation

public enum HTDTEquipmentCatalogError:
    Error,
    Sendable,
    Equatable
{
    case unsupportedSchema
    case unsupportedAuthorityVersion
    case duplicateDefinitionIdentity
    case duplicateSemanticHash
    case emptyIdentity
    case unsupportedIdentityKind
    case emptyDisplayMetadata
}

/// Closed `identity_kind` token set of the HTDT equipment-catalog v1
/// entry contract (`Literal['manufacturer', 'user_defined']` in the
/// backend model). Unknown values must fail catalog import rather than
/// be mapped onto a supported kind (#201).
public enum HTDTEquipmentIdentityKind:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable
{
    case manufacturer
    case userDefined = "user_defined"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw HTDTEquipmentCatalogError.unsupportedIdentityKind
        }
        self = value
    }
}

public struct HTDTEquipmentCatalogEntry:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let definitionID: String
    public let version: String
    public let semanticSHA256: EvidenceSHA256
    public let identityKind: HTDTEquipmentIdentityKind
    public let manufacturer: String?
    public let model: String?
    public let userLabel: String?

    /// Enforces the exact HTDT equipment-catalog v1 entry contract:
    /// `definition_id` and `version` are `min_length=1` strings,
    /// `identity_kind` is the closed manufacturer/user-defined token
    /// set, and each optional display field is `min_length=1` when
    /// present — the same constraints the backend pydantic model
    /// applies. Values are kept byte-exact; this entry is an exact
    /// selection tuple, not text to normalize.
    public init(
        definitionID: String,
        version: String,
        semanticSHA256: EvidenceSHA256,
        identityKind: HTDTEquipmentIdentityKind,
        manufacturer: String? = nil,
        model: String? = nil,
        userLabel: String? = nil
    ) throws {
        guard !definitionID.isEmpty,
              !version.isEmpty
        else {
            throw HTDTEquipmentCatalogError.emptyIdentity
        }
        guard !(manufacturer?.isEmpty ?? false),
              !(model?.isEmpty ?? false),
              !(userLabel?.isEmpty ?? false)
        else {
            throw HTDTEquipmentCatalogError.emptyDisplayMetadata
        }
        self.definitionID = definitionID
        self.version = version
        self.semanticSHA256 = semanticSHA256
        self.identityKind = identityKind
        self.manufacturer = manufacturer
        self.model = model
        self.userLabel = userLabel
    }

    /// Untrusted catalog JSON must satisfy the same per-entry
    /// invariants as the explicit initializer; routing every decoded
    /// entry through `init(...)` keeps synthesized decoding from
    /// bypassing validation (#201).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            definitionID: container.decode(
                String.self,
                forKey: .definitionID
            ),
            version: container.decode(String.self, forKey: .version),
            semanticSHA256: container.decode(
                EvidenceSHA256.self,
                forKey: .semanticSHA256
            ),
            identityKind: container.decode(
                HTDTEquipmentIdentityKind.self,
                forKey: .identityKind
            ),
            manufacturer: container.decodeIfPresent(
                String.self,
                forKey: .manufacturer
            ),
            model: container.decodeIfPresent(
                String.self,
                forKey: .model
            ),
            userLabel: container.decodeIfPresent(
                String.self,
                forKey: .userLabel
            )
        )
    }

    public var selectionKey: String {
        definitionID
            + "\u{0}"
            + version
            + "\u{0}"
            + semanticSHA256.description
    }

    public var displayName: String {
        if let manufacturer, let model {
            return manufacturer + " " + model
        }
        if let userLabel {
            return userLabel
        }
        return definitionID
    }

    public func equipmentReference()
        throws -> HTDTEquipmentReference
    {
        try HTDTEquipmentReference(
            equipmentID: definitionID,
            equipmentVersion: version,
            equipmentHash: semanticSHA256
        )
    }

    private enum CodingKeys: String, CodingKey {
        case definitionID = "definition_id"
        case version
        case semanticSHA256 = "semantic_sha256"
        case identityKind = "identity_kind"
        case manufacturer
        case model
        case userLabel = "user_label"
    }
}

public struct HTDTEquipmentCatalogSnapshot:
    Codable,
    Sendable,
    Equatable
{
    public static let expectedSchema =
        "htdt.equipment.catalog-snapshot"
    public static let expectedSchemaVersion = 1
    public static let expectedAuthorityVersion =
        "o100c-equipment-definition-1"

    public let schema: String
    public let schemaVersion: Int
    public let authorityVersion: String
    public let definitions: [HTDTEquipmentCatalogEntry]

    public init(
        definitions: [HTDTEquipmentCatalogEntry]
    ) throws {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.authorityVersion = Self.expectedAuthorityVersion
        self.definitions = definitions
        try Self.validate(definitions)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let schema = try container.decode(
            String.self,
            forKey: .schema
        )
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        let authorityVersion = try container.decode(
            String.self,
            forKey: .authorityVersion
        )
        let definitions = try container.decode(
            [HTDTEquipmentCatalogEntry].self,
            forKey: .definitions
        )

        guard
            schema == Self.expectedSchema,
            schemaVersion == Self.expectedSchemaVersion
        else {
            throw HTDTEquipmentCatalogError.unsupportedSchema
        }
        guard authorityVersion
                == Self.expectedAuthorityVersion
        else {
            throw HTDTEquipmentCatalogError
                .unsupportedAuthorityVersion
        }
        try Self.validate(definitions)

        self.schema = schema
        self.schemaVersion = schemaVersion
        self.authorityVersion = authorityVersion
        self.definitions = definitions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(schema, forKey: .schema)
        try container.encode(
            schemaVersion,
            forKey: .schemaVersion
        )
        try container.encode(
            authorityVersion,
            forKey: .authorityVersion
        )
        try container.encode(
            definitions,
            forKey: .definitions
        )
    }

    private static func validate(
        _ definitions: [HTDTEquipmentCatalogEntry]
    ) throws {
        let identities = definitions.map {
            $0.definitionID + "\u{0}" + $0.version
        }
        guard Set(identities).count == identities.count else {
            throw HTDTEquipmentCatalogError
                .duplicateDefinitionIdentity
        }
        let hashes = definitions.map(\.semanticSHA256)
        guard Set(hashes).count == hashes.count else {
            throw HTDTEquipmentCatalogError
                .duplicateSemanticHash
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case authorityVersion = "authority_version"
        case definitions
    }
}
