import Foundation

public enum ExternalAuthorityDependencyError:
    Error,
    Sendable,
    Equatable
{
    case emptyField
    case duplicateDependency
    case unsupportedSchema
    case invalidTimestamp
}

/// Closed vocabulary of external authority kinds a capture bundle may
/// depend on (#337). The manifest mechanism is generic — a new
/// authority type extends this enum and reuses the whole declaration/
/// resolution/reporting contract — but the vocabulary itself is
/// versioned, so a bundle never silently accepts an authority kind the
/// reader does not understand.
public enum ExternalAuthorityDependencyKind:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    /// HTDT equipment-catalog definition a committed
    /// `equipment_ref` resolves against.
    case equipmentDefinition = "equipment_definition"
    /// Versioned layout profile a `role_binding` resolves against
    /// (#315).
    case layoutProfile = "layout_profile"
    /// Imported capture task plan (#240).
    case taskPlan = "task_plan"
    /// Calibration asset authority (#331).
    case calibrationAsset = "calibration_asset"
    /// Manufacturer documentation authority (#275).
    case manufacturerDocumentation = "manufacturer_documentation"
    /// Floor-plan authority (#322).
    case floorPlan = "floor_plan"
    /// Tolerance-profile authority (#293).
    case toleranceProfile = "tolerance_profile"
}

/// Portable identity hints that let another HTDT instance resolve the
/// same authority without transferring a whole catalog (#337). For an
/// equipment definition this is the make/model/serial-keyed lookup
/// context plus the source catalog identity (#302) it was selected
/// under — enough to locate the identical definition on a remote
/// instance and to prove hash equality before trusting it.
public struct ExternalAuthorityResolutionContext:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let manufacturer: String?
    public let model: String?
    /// Serial/asset tag recorded on the physical unit — a lookup hint,
    /// never proof of identity (#345 keeps it a hint).
    public let serialOrAssetTag: String?
    /// Backend-assigned snapshot ID of the source catalog, when known.
    public let catalogSnapshotID: String?
    /// Semantic content digest of the source catalog (#302) — the
    /// portable pin a receiving instance can match its own catalog
    /// against.
    public let catalogContentSHA256: EvidenceSHA256?
    /// Source catalog's operator-facing label — display only.
    public let catalogLabel: String?

    public init(
        manufacturer: String? = nil,
        model: String? = nil,
        serialOrAssetTag: String? = nil,
        catalogSnapshotID: String? = nil,
        catalogContentSHA256: EvidenceSHA256? = nil,
        catalogLabel: String? = nil
    ) throws {
        let normalized = [
            manufacturer,
            model,
            serialOrAssetTag,
            catalogSnapshotID,
            catalogLabel,
        ].map { SchemaOwnedText.nfc($0) }
        guard normalized.allSatisfy({ !($0?.isEmpty ?? false) }) else {
            throw ExternalAuthorityDependencyError.emptyField
        }
        self.manufacturer = normalized[0]
        self.model = normalized[1]
        self.serialOrAssetTag = normalized[2]
        self.catalogSnapshotID = normalized[3]
        self.catalogContentSHA256 = catalogContentSHA256
        self.catalogLabel = normalized[4]
    }
}

/// One declared external authority dependency (#337).
///
/// Every field that identifies the authority is exact: `authority_id`,
/// `authority_version`, and `authority_sha256` name the precise
/// versioned object the capture depends on — a matching ID at a
/// different hash is a hard rejection, never an upgrade. `required`
/// says whether an unresolved lookup degrades the capture's declared
/// capability; `resolution_context` carries the portable hints a
/// receiving instance uses to locate the authority; `embedded_ref`
/// points at a bundle-embedded copy when the payload ships inside the
/// archive.
public struct ExternalAuthorityDependency:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let kind: ExternalAuthorityDependencyKind
    /// Exact authority identity key (equipment definition ID, profile
    /// ID, plan ID, asset ID — the namespace `kind` defines).
    public let authorityID: String
    /// Exact authority version token.
    public let authorityVersion: String
    /// Content hash pinning the authority's exact version.
    public let authoritySHA256: EvidenceSHA256
    /// True when failing to resolve the authority degrades the
    /// capture's declared capability; false for optional enrichments.
    public let required: Bool
    /// Bundle-local refs that consume this authority (entity IDs,
    /// document paths) — traceability, not a resolution key.
    public let boundEntityRefs: [String]
    /// What capability is lost when the dependency stays unresolved —
    /// a stable human/consumer token (e.g. `model_lookup`).
    public let capabilityLoss: String?
    public let resolutionContext: ExternalAuthorityResolutionContext?
    /// `path:<bundle path>` of a bundle-embedded authority copy, when
    /// the payload ships inside the archive.
    public let embeddedRef: String?

    /// Stable dedup key — same authority depended on twice collapses
    /// into one declaration.
    public var identityKey: String {
        kind.rawValue + "␀" + authorityID + "␀" + authorityVersion
    }

    public init(
        kind: ExternalAuthorityDependencyKind,
        authorityID: String,
        authorityVersion: String,
        authoritySHA256: EvidenceSHA256,
        required: Bool,
        boundEntityRefs: [String] = [],
        capabilityLoss: String? = nil,
        resolutionContext: ExternalAuthorityResolutionContext? = nil,
        embeddedRef: String? = nil
    ) throws {
        let id = SchemaOwnedText.nfc(authorityID)
        let version = SchemaOwnedText.nfc(authorityVersion)
        let capability = SchemaOwnedText.nfc(capabilityLoss)
        let refs = SchemaOwnedText.nfc(boundEntityRefs)
        guard !id.isEmpty, !version.isEmpty,
              !(capability?.isEmpty ?? false),
              refs.allSatisfy({ !$0.isEmpty })
        else {
            throw ExternalAuthorityDependencyError.emptyField
        }
        if let embeddedRef {
            guard embeddedRef.hasPrefix("path:"),
                  embeddedRef.count > 5
            else {
                throw ExternalAuthorityDependencyError.emptyField
            }
        }
        self.kind = kind
        self.authorityID = id
        self.authorityVersion = version
        self.authoritySHA256 = authoritySHA256
        self.required = required
        self.boundEntityRefs = refs
        self.capabilityLoss = capability
        self.resolutionContext = resolutionContext
        self.embeddedRef = embeddedRef
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case authorityID = "authority_id"
        case authorityVersion = "authority_version"
        case authoritySHA256 = "authority_sha256"
        case required
        case boundEntityRefs = "bound_entity_refs"
        case capabilityLoss = "capability_loss"
        case resolutionContext = "resolution_context"
        case embeddedRef = "embedded_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(
                ExternalAuthorityDependencyKind.self,
                forKey: .kind
            ),
            authorityID: container.decode(
                String.self,
                forKey: .authorityID
            ),
            authorityVersion: container.decode(
                String.self,
                forKey: .authorityVersion
            ),
            authoritySHA256: container.decode(
                EvidenceSHA256.self,
                forKey: .authoritySHA256
            ),
            required: container.decode(Bool.self, forKey: .required),
            boundEntityRefs: container.decodeIfPresent(
                [String].self,
                forKey: .boundEntityRefs
            ) ?? [],
            capabilityLoss: container.decodeIfPresent(
                String.self,
                forKey: .capabilityLoss
            ),
            resolutionContext: container.decodeIfPresent(
                ExternalAuthorityResolutionContext.self,
                forKey: .resolutionContext
            ),
            embeddedRef: container.decodeIfPresent(
                String.self,
                forKey: .embeddedRef
            )
        )
    }
}

/// The bundle-level declaration of every external authority the
/// capture depends on (#337), persisted at
/// `derived/authority-dependencies.json`.
///
/// Bundle-local `source_refs` describe provenance *inside* the
/// archive; this manifest is the separate layer describing
/// dependencies on authorities *outside* the archive — catalogs,
/// profiles, plans, assets. Any consumer enumerates unresolved
/// dependencies generically and fails a capability deterministically
/// when a `required` dependency cannot be satisfied, while bundle
/// integrity itself still passes with optional dependencies
/// unresolved.
public struct ExternalAuthorityDependencyManifest:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.authority-dependencies"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let generatedAtUTC: String
    public let dependencies: [ExternalAuthorityDependency]

    public init(
        generatedAtUTC: String,
        dependencies: [ExternalAuthorityDependency]
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(generatedAtUTC) else {
            throw ExternalAuthorityDependencyError.invalidTimestamp
        }
        var seen = Set<String>()
        for dependency in dependencies {
            guard seen.insert(dependency.identityKey).inserted else {
                throw ExternalAuthorityDependencyError
                    .duplicateDependency
            }
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.generatedAtUTC = generatedAtUTC
        self.dependencies = dependencies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schemaName)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersionValue
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw ExternalAuthorityDependencyError.unsupportedSchema
        }
        try self.init(
            generatedAtUTC: container.decode(
                String.self,
                forKey: .generatedAtUTC
            ),
            dependencies: container.decode(
                [ExternalAuthorityDependency].self,
                forKey: .dependencies
            )
        )
    }

    /// Dependencies not satisfiable from `availableKeys` — the generic
    /// "unresolved external authorities" enumeration (#337). A key is
    /// the dependency's `identityKey`.
    public func unresolved(
        availableKeys: Set<String>
    ) -> [ExternalAuthorityDependency] {
        dependencies.filter { !availableKeys.contains($0.identityKey) }
    }

    /// Required dependencies that stay unresolved — the capture loses
    /// their declared capability deterministically (#337).
    public func capabilityFailures(
        availableKeys: Set<String>
    ) -> [ExternalAuthorityDependency] {
        unresolved(availableKeys: availableKeys).filter(\.required)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case generatedAtUTC = "generated_at"
        case dependencies
    }
}

/// Bundle-persisted wrapper for the dependency manifest (#337) —
/// `capture_app_derived` provenance, `derived` role, encoded once into
/// `data` so persistence writes exactly the bytes that were declared.
public struct ExternalAuthorityDependencyPackage:
    Sendable,
    Equatable
{
    public static let path = "derived/authority-dependencies.json"

    public let manifest: ExternalAuthorityDependencyManifest
    public let data: Data
    /// Manifest `source_refs`: the entity collection the declared
    /// dependencies were read from, plus every bundle-embedded
    /// authority copy the manifest references.
    public let sourceRefs: [String]

    public init(
        manifest: ExternalAuthorityDependencyManifest,
        extraSourceRefs: [String] = []
    ) throws {
        var refs = Set<String>(
            ["path:" + AnnotationEvidencePackage.path]
        )
        refs.formUnion(
            manifest.dependencies.compactMap(\.embeddedRef)
        )
        refs.formUnion(extraSourceRefs)
        self.manifest = manifest
        self.sourceRefs = refs.sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        self.data = try encoder.encode(manifest)
    }

    public var declaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: sourceRefs
        )
    }
}

/// Derives the dependency declarations from committed annotation
/// content (#337): one `equipment_definition` per distinct
/// `equipment_ref` identity, one `layout_profile` per distinct
/// `role_binding` profile, each pinned by exact ID/version/hash.
public enum ExternalAuthorityDependencyBuilder {
    /// Equipment-definition dependencies, deduplicated on the exact
    /// `(id, version)` identity — and carrying the definition's
    /// semantic hash so a same-ID/different-hash resolution on a
    /// remote instance is a hard reject, not an upgrade.
    ///
    /// `identityRecords` supplies per-entity serial hints for the
    /// portable resolution context; `catalog` supplies the source
    /// catalog identity (#302).
    public static func equipmentDependencies(
        entities: [CaptureAnnotationEntity],
        catalog: HTDTEquipmentCatalogSnapshot?,
        identityRecords: [EquipmentIdentityRecord] = []
    ) throws -> [ExternalAuthorityDependency] {
        var entitiesByRef: [String: [String]] = [:]
        for entity in entities {
            guard let ref = entity.equipmentRef else { continue }
            let key = ref.equipmentID + "␀" + ref.equipmentVersion
            entitiesByRef[key, default: []].append(
                entity.entityID.description
            )
        }
        var serialByEntity: [String: String] = [:]
        for record in identityRecords {
            if let serial = record.serialOrAssetTag {
                serialByEntity[record.entityID.description] = serial
            }
        }
        var result: [ExternalAuthorityDependency] = []
        for (key, entityIDs) in entitiesByRef.sorted(by: {
            $0.key < $1.key
        }) {
            let parts = key.components(separatedBy: "␀")
            let definitionID = parts[0]
            let version = parts[1]
            // The exact pinned definition must come from the adopted
            // catalog — a ref whose tuple is absent from the active
            // catalog still declares a dependency (with the ref's own
            // hash) so a receiving instance sees the exact demand.
            let catalogEntry = catalog?.definitions.first {
                $0.definitionID == definitionID && $0.version == version
            }
            let serial = entityIDs.lazy.compactMap {
                serialByEntity[$0]
            }.sorted().first
            let context = try ExternalAuthorityResolutionContext(
                manufacturer: catalogEntry?.manufacturer,
                model: catalogEntry?.model,
                serialOrAssetTag: serial,
                catalogSnapshotID:
                    catalog?.catalogContext?.catalogSnapshotID,
                catalogContentSHA256: catalog?.contentSHA256,
                catalogLabel: catalog?.catalogContext?.catalogLabel
            )
            let hash = catalogEntry?.semanticSHA256
                ?? entities.compactMap(\.equipmentRef).first {
                    $0.equipmentID == definitionID
                        && $0.equipmentVersion == version
                }?.equipmentHash
            guard let hash else { continue }
            result.append(
                try ExternalAuthorityDependency(
                    kind: .equipmentDefinition,
                    authorityID: definitionID,
                    authorityVersion: version,
                    authoritySHA256: hash,
                    required: true,
                    boundEntityRefs: entityIDs.sorted(),
                    capabilityLoss: "model_lookup",
                    resolutionContext: context
                )
            )
        }
        return result
    }

    /// Layout-profile dependencies declared by entity role bindings
    /// (#337 + #315): one dependency per distinct
    /// `(profile_id, profile_version)` the committed entities bind to.
    public static func layoutProfileDependencies(
        entities: [CaptureAnnotationEntity]
    ) throws -> [ExternalAuthorityDependency] {
        var byProfile: [String: (binding: SpeakerRoleBinding, refs: [String])] = [:]
        for entity in entities {
            guard let binding = entity.roleBinding else { continue }
            let key = binding.profileID + "␀" + binding.profileVersion
            if var entry = byProfile[key] {
                entry.refs.append(entity.entityID.description)
                byProfile[key] = entry
            } else {
                byProfile[key] = (
                    binding: binding,
                    refs: [entity.entityID.description]
                )
            }
        }
        var result: [ExternalAuthorityDependency] = []
        for (key, entry) in byProfile.sorted(by: { $0.key < $1.key }) {
            // The profile's content hash is known only when the profile
            // is a built-in vocabulary; for external profiles the pin
            // is the exact (id, version) pair and the hash is declared
            // as the profile reference digest the binding established.
            let profile = SpeakerLayoutProfiles.all.first {
                $0.profileID == entry.binding.profileID
                    && $0.profileVersion
                        == entry.binding.profileVersion
            }
            result.append(
                try ExternalAuthorityDependency(
                    kind: .layoutProfile,
                    authorityID: entry.binding.profileID,
                    authorityVersion: entry.binding.profileVersion,
                    authoritySHA256: profile?.contentSHA256
                        ?? ExternalAuthorityDependencyBuilder
                            .profileReferenceDigest(
                                profileID: entry.binding.profileID,
                                profileVersion:
                                    entry.binding.profileVersion
                            ),
                    required: true,
                    boundEntityRefs: entry.refs.sorted(),
                    capabilityLoss: "role_resolution"
                )
            )
        }
        return result
    }

    /// Task-plan dependency for a bundle created under an imported
    /// plan (#240/#337).
    public static func taskPlanDependency(
        plan: HTDTCaptureTaskPlan,
        planSHA256: EvidenceSHA256
    ) throws -> ExternalAuthorityDependency {
        try ExternalAuthorityDependency(
            kind: .taskPlan,
            authorityID: plan.planID,
            authorityVersion: plan.planVersion,
            authoritySHA256: planSHA256,
            required: false,
            capabilityLoss: "task_provenance"
        )
    }

    /// Deterministic digest for a profile identified only by
    /// ID/version — keeps the manifest byte-stable even when the
    /// profile body is not locally available.
    public static func profileReferenceDigest(
        profileID: String,
        profileVersion: String
    ) -> EvidenceSHA256 {
        let canonical = try? CanonicalJSON.encode(
            .object([
                "profile_id": .string(profileID),
                "profile_version": .string(profileVersion),
            ])
        )
        return EvidenceIntegrity.sha256(of: canonical ?? Data())
    }

    /// Assembles the whole manifest for a committed session.
    public static func manifest(
        entities: [CaptureAnnotationEntity],
        catalog: HTDTEquipmentCatalogSnapshot?,
        identityRecords: [EquipmentIdentityRecord] = [],
        taskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanSHA256: EvidenceSHA256? = nil,
        generatedAtUTC: String
    ) throws -> ExternalAuthorityDependencyManifest {
        var dependencies = try equipmentDependencies(
            entities: entities,
            catalog: catalog,
            identityRecords: identityRecords
        )
        dependencies.append(
            contentsOf: try layoutProfileDependencies(
                entities: entities
            )
        )
        if let taskPlan, let taskPlanSHA256 {
            dependencies.append(
                try taskPlanDependency(
                    plan: taskPlan,
                    planSHA256: taskPlanSHA256
                )
            )
        }
        return try ExternalAuthorityDependencyManifest(
            generatedAtUTC: generatedAtUTC,
            dependencies: dependencies
        )
    }
}
