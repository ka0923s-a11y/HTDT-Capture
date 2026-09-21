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
    public let identityKind: String
    public let manufacturer: String?
    public let model: String?
    public let userLabel: String?

    public init(
        definitionID: String,
        version: String,
        semanticSHA256: EvidenceSHA256,
        identityKind: String,
        manufacturer: String? = nil,
        model: String? = nil,
        userLabel: String? = nil
    ) throws {
        guard !definitionID.isEmpty,
              !version.isEmpty,
              !identityKind.isEmpty
        else {
            throw HTDTEquipmentCatalogError.emptyIdentity
        }
        self.definitionID = definitionID
        self.version = version
        self.semanticSHA256 = semanticSHA256
        self.identityKind = identityKind
        self.manufacturer = manufacturer
        self.model = model
        self.userLabel = userLabel
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

/// Durable app-local mirror of the last validated HTDT
/// equipment-catalog snapshot (#211).
///
/// The catalog is operator reference context for exact equipment
/// selection — it is never capture-bundle authority — so it is stored
/// as a single app-owned JSON file outside the bundle roots. Every
/// reload runs through the validating snapshot decoder: an unsupported
/// schema or authority version is dropped rather than silently
/// substituted, and annotation authority already committed inside a
/// capture stays valid because it stores only exact equipment tuples.
public struct HTDTEquipmentCatalogCache: Sendable {
    /// The app-owned file holding the imported catalog bytes.
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Validates `data` through the snapshot decoder and, only on
    /// success, writes those exact bytes atomically. Returns the
    /// validated snapshot. An invalid candidate throws before any
    /// write, so a rejected import never replaces the stored snapshot.
    @discardableResult
    public func store(
        _ data: Data
    ) throws -> HTDTEquipmentCatalogSnapshot {
        let snapshot = try JSONDecoder().decode(
            HTDTEquipmentCatalogSnapshot.self,
            from: data
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        return snapshot
    }

    /// Returns the cached snapshot only while it still validates.
    /// A missing file is a clean miss; a corrupt or now-unsupported
    /// file is removed so a stale snapshot is never silently reused —
    /// the caller then requires an explicit re-import.
    public func load() -> HTDTEquipmentCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(
            HTDTEquipmentCatalogSnapshot.self,
            from: data
        ) else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return snapshot
    }
}
