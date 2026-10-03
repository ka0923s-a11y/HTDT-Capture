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
    case invalidCatalogTimestamp
}

/// Closed `identity_kind` token set of the HTDT equipment-catalog v1
/// entry contract (`Literal['manufacturer', 'user_defined']` in the
/// backend model). Unknown values must fail catalog import rather than
/// be mapped onto a supported kind (legacy bolph71656-ai/HTDT-Capture#201).
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
    /// bypassing validation (legacy bolph71656-ai/HTDT-Capture#201).
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

    public func equipmentReference(
        authorityVersion: String
    ) throws -> HTDTEquipmentReference {
        try HTDTEquipmentReference(
            equipmentID: definitionID,
            equipmentVersion: version,
            equipmentHash: semanticSHA256,
            authorityVersion: authorityVersion
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

/// Optional catalog-level source identity on a snapshot (legacy bolph71656-ai/HTDT-Capture#302).
///
/// The v1 entry contract pins every definition by exact
/// ID/version/SHA-256; this context answers the separate question
/// "which catalog is this?" — which HTDT project/instance produced it,
/// when it was generated, and which snapshot/label the backend gave
/// it. Every field is optional so a snapshot written before the
/// contract existed remains readable; absent context is surfaced to
/// the operator as unknown/legacy rather than inferred.
public struct HTDTEquipmentCatalogContext:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    /// Backend-assigned snapshot identifier, when the source export
    /// carries one.
    public let catalogSnapshotID: String?
    /// Human-facing catalog name (display only — never identity).
    public let catalogLabel: String?
    /// Optional backend-declared catalog version token.
    public let catalogVersion: String?
    /// UTC generation timestamp of the source export.
    public let generatedAtUTC: String?
    /// HTDT project/workspace the export was produced for.
    public let sourceProjectRef: String?
    /// HTDT backend/instance the export came from.
    public let sourceInstanceRef: String?

    public init(
        catalogSnapshotID: String? = nil,
        catalogLabel: String? = nil,
        catalogVersion: String? = nil,
        generatedAtUTC: String? = nil,
        sourceProjectRef: String? = nil,
        sourceInstanceRef: String? = nil
    ) throws {
        let normalized = [
            catalogSnapshotID,
            catalogLabel,
            catalogVersion,
            sourceProjectRef,
            sourceInstanceRef,
        ].map { SchemaOwnedText.nfc($0) }
        guard normalized.allSatisfy({ !($0?.isEmpty ?? false) }) else {
            throw HTDTEquipmentCatalogError.emptyDisplayMetadata
        }
        if let generatedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(generatedAtUTC)
            else {
                throw HTDTEquipmentCatalogError.invalidCatalogTimestamp
            }
        }
        self.catalogSnapshotID = normalized[0]
        self.catalogLabel = normalized[1]
        self.catalogVersion = normalized[2]
        self.generatedAtUTC = generatedAtUTC
        self.sourceProjectRef = normalized[3]
        self.sourceInstanceRef = normalized[4]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            catalogSnapshotID: container.decodeIfPresent(
                String.self,
                forKey: .catalogSnapshotID
            ),
            catalogLabel: container.decodeIfPresent(
                String.self,
                forKey: .catalogLabel
            ),
            catalogVersion: container.decodeIfPresent(
                String.self,
                forKey: .catalogVersion
            ),
            generatedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .generatedAtUTC
            ),
            sourceProjectRef: container.decodeIfPresent(
                String.self,
                forKey: .sourceProjectRef
            ),
            sourceInstanceRef: container.decodeIfPresent(
                String.self,
                forKey: .sourceInstanceRef
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case catalogSnapshotID = "snapshot_id"
        case catalogLabel = "label"
        case catalogVersion = "catalog_version"
        case generatedAtUTC = "generated_at"
        case sourceProjectRef = "source_project"
        case sourceInstanceRef = "source_instance"
    }
}

/// The operator-visible identity of a catalog snapshot (legacy bolph71656-ai/HTDT-Capture#302): the
/// declared context fields plus the semantic content digest, which is
/// always computable even for legacy snapshots with no context block.
/// The stable key — backend snapshot ID when present, content digest
/// otherwise — is what a task plan pins when it demands an exact
/// catalog.
public struct HTDTEquipmentCatalogIdentity:
    Sendable,
    Equatable,
    Hashable
{
    public let snapshotID: String?
    /// Semantic digest over authority version + sorted definitions.
    /// Definition order and JSON formatting never change it.
    public let contentSHA256: EvidenceSHA256
    public let label: String?
    public let catalogVersion: String?
    public let generatedAtUTC: String?
    public let sourceProjectRef: String?
    public let sourceInstanceRef: String?
    public let definitionCount: Int
    /// True when the snapshot carried no context block — the stored
    /// file predates the identity contract, so source/freshness are
    /// explicitly unknown rather than fabricated.
    public let isLegacy: Bool

    /// Stable identity key for pinning and the active-catalog pointer:
    /// backend snapshot ID when declared, else the content digest.
    public var stableKey: String {
        snapshotID ?? contentSHA256.description
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
    /// Source/project identity of this snapshot (legacy bolph71656-ai/HTDT-Capture#302); nil on imports
    /// that predate the context contract.
    public let catalogContext: HTDTEquipmentCatalogContext?
    public let definitions: [HTDTEquipmentCatalogEntry]

    public init(
        definitions: [HTDTEquipmentCatalogEntry],
        catalogContext: HTDTEquipmentCatalogContext? = nil
    ) throws {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.authorityVersion = Self.expectedAuthorityVersion
        self.catalogContext = catalogContext
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
        let catalogContext = try container.decodeIfPresent(
            HTDTEquipmentCatalogContext.self,
            forKey: .catalogContext
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
        self.catalogContext = catalogContext
        self.definitions = definitions
    }

    /// Annotation types this snapshot's catalog may attach to (legacy bolph71656-ai/HTDT-Capture#237).
    /// Nil/unknown authority versions are surfaced as
    /// `unknownAuthorityVersion` by `HTDTEquipmentCompatibility.check`.
    public var compatibleAnnotationTypes: Set<AnnotationEntityType> {
        HTDTEquipmentCompatibility.compatibleTypes(
            authorityVersion: authorityVersion
        ) ?? []
    }

    /// Semantic digest over the authority version plus every
    /// definition tuple, independent of definition ordering and of any
    /// JSON formatting in the source file (legacy bolph71656-ai/HTDT-Capture#302): two snapshots with
    /// identical content have identical digests even when their bytes
    /// differ, so the digest is the portable pin a task plan can demand.
    public var contentSHA256: EvidenceSHA256 {
        let sortedDefinitions = definitions.sorted {
            $0.selectionKey < $1.selectionKey
        }
        let entries = sortedDefinitions.map {
            entry -> CanonicalJSONValue in
            var object: [String: CanonicalJSONValue] = [
                "definition_id": .string(entry.definitionID),
                "identity_kind": .string(
                    entry.identityKind.rawValue
                ),
                "semantic_sha256": .string(
                    entry.semanticSHA256.description
                ),
                "version": .string(entry.version),
            ]
            if let manufacturer = entry.manufacturer {
                object["manufacturer"] = .string(manufacturer)
            }
            if let model = entry.model {
                object["model"] = .string(model)
            }
            if let userLabel = entry.userLabel {
                object["user_label"] = .string(userLabel)
            }
            return .object(object)
        }
        let canonical = try? CanonicalJSON.encode(
            .object([
                "authority_version": .string(authorityVersion),
                "definitions": .array(entries),
            ])
        )
        return EvidenceIntegrity.sha256(of: canonical ?? Data())
    }

    /// The operator-visible catalog identity (legacy bolph71656-ai/HTDT-Capture#302): declared context
    /// when present, content digest always.
    public var identity: HTDTEquipmentCatalogIdentity {
        HTDTEquipmentCatalogIdentity(
            snapshotID: catalogContext?.catalogSnapshotID,
            contentSHA256: contentSHA256,
            label: catalogContext?.catalogLabel,
            catalogVersion: catalogContext?.catalogVersion,
            generatedAtUTC: catalogContext?.generatedAtUTC,
            sourceProjectRef: catalogContext?.sourceProjectRef,
            sourceInstanceRef: catalogContext?.sourceInstanceRef,
            definitionCount: definitions.count,
            isLegacy: catalogContext == nil
        )
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
        try container.encodeIfPresent(
            catalogContext,
            forKey: .catalogContext
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
        case catalogContext = "catalog"
        case definitions
    }
}

/// Versioned taxonomy mapping catalog `authority_version` strings to
/// the annotation types that may carry those references (legacy bolph71656-ai/HTDT-Capture#237).
///
/// `o100c-equipment-definition-1` is the acoustic-source equipment
/// catalog — its exact tuples are compatible with `speaker` and
/// `subwoofer` entities only. Future equipment classes (projector,
/// display, AV electronics, ...) extend this map with their own
/// authority versions rather than widening the existing one.
public enum HTDTEquipmentCompatibility {
    /// Compatible annotation types for a catalog authority version,
    /// or nil when the version is unknown to this build's taxonomy.
    public static func compatibleTypes(
        authorityVersion: String
    ) -> Set<AnnotationEntityType>? {
        switch authorityVersion {
        case HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion:
            return [.speaker, .subwoofer]
        default:
            return nil
        }
    }

    public static func check(
        reference: HTDTEquipmentReference,
        entityType: AnnotationEntityType
    ) -> EquipmentReferenceCompatibility {
        guard let types = compatibleTypes(
            authorityVersion: reference.resolvedAuthorityVersion
        ) else {
            return .unknownAuthorityVersion
        }
        return types.contains(entityType) ? .compatible : .incompatible
    }
}

/// Durable app-local mirror of the last validated HTDT
/// equipment-catalog snapshot (legacy bolph71656-ai/HTDT-Capture#211).
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

/// Multi-catalog store for the app-local equipment-catalog mirror
/// (legacy bolph71656-ai/HTDT-Capture#302). Replaces the single `imported-equipment-catalog.json`
/// slot: every imported snapshot is validated, stored under the SHA-256
/// of its exact bytes, and only becomes the selection context through
/// an explicit activation — two project/backend catalogs coexist and
/// importing a new one never silently overwrites the active choice.
///
/// Activation pointer: `active-catalog` inside the library directory
/// holds the content key of the selected snapshot. When the pointer is
/// absent and exactly one snapshot is stored, that one is active —
/// preserving the pre-legacy bolph71656-ai/HTDT-Capture#302 "last imported catalog" behavior. A
/// `HTDTEquipmentCatalogCache` single file at `legacyFileURL` is
/// migrated into the library on first read so its context (absent by
/// definition) reads as unknown/legacy instead of vanishing.
public struct HTDTEquipmentCatalogLibrary: Sendable {
    /// One stored snapshot plus the content key under which it is filed.
    public struct StoredCatalog: Sendable, Equatable {
        /// SHA-256 of the stored bytes — the file name and the pointer
        /// value. Byte identity, deliberately distinct from the
        /// snapshot's semantic `contentSHA256`.
        public let contentKey: String
        public let snapshot: HTDTEquipmentCatalogSnapshot
        public let fileURL: URL
    }

    public let directory: URL
    /// Pre-legacy bolph71656-ai/HTDT-Capture#302 single-slot cache migrated on first access; nil
    /// disables migration.
    public let legacyFileURL: URL?

    private static let pointerFileName = "active-catalog"

    public init(directory: URL, legacyFileURL: URL? = nil) {
        self.directory = directory
        self.legacyFileURL = legacyFileURL
    }

    private var pointerFileURL: URL {
        directory.appendingPathComponent(
            Self.pointerFileName,
            isDirectory: false
        )
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(
            key + ".json",
            isDirectory: false
        )
    }

    /// Validates `data` through the snapshot decoder and stores those
    /// exact bytes under their content key, atomically. Importing does
    /// not change the active selection — call `setActive` explicitly.
    /// Returns the stored descriptor.
    @discardableResult
    public func store(
        _ data: Data
    ) throws -> StoredCatalog {
        let snapshot = try JSONDecoder().decode(
            HTDTEquipmentCatalogSnapshot.self,
            from: data
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let key = EvidenceIntegrity.sha256(of: data).description
        let target = fileURL(forKey: key)
        try data.write(to: target, options: .atomic)
        return StoredCatalog(
            contentKey: key,
            snapshot: snapshot,
            fileURL: target
        )
    }

    /// Imports `data` and makes it the active catalog in one call —
    /// the explicit "select this catalog" path for fresh imports.
    @discardableResult
    public func storeAndActivate(
        _ data: Data
    ) throws -> StoredCatalog {
        let stored = try store(data)
        try setActive(contentKey: stored.contentKey)
        return stored
    }

    /// Every valid stored snapshot, keyed deterministically. Files that
    /// fail validation are removed rather than surfaced — the library
    /// never offers a snapshot the decoder would reject at import.
    public func list() -> [StoredCatalog] {
        migrateLegacyIfNeeded()
        guard
            let names = try? FileManager.default.contentsOfDirectory(
                atPath: directory.path
            )
        else {
            return []
        }
        var result: [StoredCatalog] = []
        for name in names {
            guard name.hasSuffix(".json"),
                  name != Self.pointerFileName
            else {
                continue
            }
            let url = fileURL(forKey: String(name.dropLast(5)))
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            guard let snapshot = try? JSONDecoder().decode(
                HTDTEquipmentCatalogSnapshot.self,
                from: data
            ) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            result.append(
                StoredCatalog(
                    contentKey: EvidenceIntegrity.sha256(of: data)
                        .description,
                    snapshot: snapshot,
                    fileURL: url
                )
            )
        }
        return result.sorted { $0.contentKey < $1.contentKey }
    }

    /// The content key the operator last activated, or nil when no
    /// explicit selection has ever been recorded.
    public func activeContentKey() -> String? {
        migrateLegacyIfNeeded()
        guard let data = try? Data(contentsOf: pointerFileURL),
              let key = String(
                  data: data,
                  encoding: .utf8
              )?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            return nil
        }
        return key
    }

    /// Makes the stored catalog `contentKey` the active selection.
    /// Throws when the key does not name a stored catalog — an
    /// activation can never point at absent bytes.
    public func setActive(contentKey: String) throws {
        guard list().contains(where: {
            $0.contentKey == contentKey
        }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(contentKey.utf8).write(
            to: pointerFileURL,
            options: .atomic
        )
    }

    /// The active stored snapshot: the pointer's catalog when present
    /// and valid, otherwise the single stored catalog (legacy
    /// last-imported behavior), otherwise nil.
    public func active() -> StoredCatalog? {
        migrateLegacyIfNeeded()
        let all = list()
        if let key = activeContentKey(),
           let match = all.first(where: { $0.contentKey == key })
        {
            return match
        }
        // A stale pointer (catalog removed) falls back only when the
        // library is unambiguous — never silently switches between two
        // project catalogs.
        if all.count == 1 {
            return all.first
        }
        return nil
    }

    /// Removes a stored catalog; a stale pointer to it is cleared so
    /// the next read never names absent bytes.
    public func remove(contentKey: String) throws {
        let target = fileURL(forKey: contentKey)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        if activeContentKey() == contentKey {
            try? FileManager.default.removeItem(
                at: pointerFileURL
            )
        }
    }

    /// Folds a readable pre-legacy bolph71656-ai/HTDT-Capture#302 single-slot cache into the library
    /// and activates it. Invalid legacy bytes are discarded by the
    /// single-slot cache's own load() rule — they are never imported.
    private func migrateLegacyIfNeeded() {
        guard let legacyFileURL,
              FileManager.default.fileExists(
                  atPath: legacyFileURL.path
              )
        else {
            return
        }
        let legacyCache = HTDTEquipmentCatalogCache(
            fileURL: legacyFileURL
        )
        guard let data = try? Data(contentsOf: legacyFileURL),
              (try? JSONDecoder().decode(
                  HTDTEquipmentCatalogSnapshot.self,
                  from: data
              )) != nil,
              let stored = try? store(data)
        else {
            // Not valid snapshot bytes — remove like the single-slot
            // cache would so a corrupt file cannot wedge migration.
            if legacyCache.load() == nil {
                try? FileManager.default.removeItem(
                    at: legacyFileURL
                )
            }
            return
        }
        // Remove the legacy file before activating: `setActive` reads
        // the listing, which would re-enter this migration while the
        // source still exists.
        try? FileManager.default.removeItem(at: legacyFileURL)
        try? setActive(contentKey: stored.contentKey)
    }
}
