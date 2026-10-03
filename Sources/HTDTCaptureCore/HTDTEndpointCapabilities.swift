import Foundation

/// Errors raised while fetching an endpoint's capability document
/// (issue bolph71656-ai/HTDT-Capture#374). All failures fail closed for the preflight verdict —
/// the queue never treats an unverifiable receiver as compatible.
public enum HTDTCapabilityFetchError: Error, Sendable, Equatable {
    case invalidEndpointURL
    case transportFailed(String)
    case endpointRejected(statusCode: Int)
    case malformedDocument
    /// The document exceeded the bounded read size — a capability
    /// endpoint is a small descriptor, not a bulk transfer.
    case documentTooLarge
}

/// A capability a paired/configured HTDT receiver advertises over
/// HTTPS before any archive bytes move (issue bolph71656-ai/HTDT-Capture#374). The endpoint
/// answers this small document so the sender can decide — with a
/// precise, human-readable gap list — whether the bundle it is about
/// to send is supported, partially deferrable, or doomed.
public struct HTDTEndpointCapabilityDocument:
    Codable, Sendable, Equatable
{
    public static let schema = "htdt.endpoint-capabilities"
    public static let schemaVersion = "1.0.0"

    /// Handoff wire protocol this app speaks.
    public static let handoffProtocol = "1"

    public let schema: String
    public let schemaVersion: String
    /// Display/instance identity of the answering receiver.
    public let endpointIdentity: String
    /// Handoff protocol versions the receiver accepts (e.g. ["1"]).
    public let handoffProtocolVersions: [String]
    /// Bundle manifest schema versions the receiver parses.
    public let acceptedBundleSchemaVersions: [String]
    /// Payload schemas (by `CaptureBundleSchemaRegistry` schema name)
    /// the receiver can promote, with the versions it supports.
    public let acceptedPayloadSchemas:
        [HTDTAcceptedPayloadSchema]
    /// Authority families (`SemanticTaskKind` tokens) the receiver
    /// can promote rather than merely stage.
    public let supportedAuthorityFamilies: [String]
    /// Maximum archive size in bytes the receiver accepts; nil means
    /// unbounded.
    public let maxArchiveBytes: Int64?
    /// Whether the receiver records and returns mission receipts —
    /// required when the send is bound to a mission envelope (legacy bolph71656-ai/HTDT-Capture#386).
    public let missionReceiptsSupported: Bool
    /// Equipment-catalog identity keys the receiver already knows —
    /// a catalog the receiver does not recognize lands as a staged
    /// gap, not a hard failure.
    public let equipmentCatalogsRecognized: [String]
    /// Per-artifact-family capabilities (legacy bolph71656-ai/HTDT-Capture#423 §5, legacy bolph71656-ai/HTDT-Capture#422 §capability
    /// handshake): which artifact kinds the receiver accepts, with
    /// the schema versions and byte ceiling it stages for each.
    /// Absent on a legacy document means capture-bundle only —
    /// interpreted by `acceptedKinds`, never rewritten.
    public let acceptedArtifactKinds: [HTDTArtifactKindCapability]?
    /// Direction capability (legacy bolph71656-ai/HTDT-Capture#422): whether the receiver serves
    /// pending Mission packages to paired Capture identities for
    /// the receive leg. Absent = false (legacy receivers never
    /// offer Mission pulls).
    public let missionPackagesServed: Bool
    /// Project the receiver declares itself bound to, if any.
    public let projectRef: String?
    /// When true, staged captures require manual promotion review —
    /// surfaced to the operator rather than assumed automatic.
    public let manualReviewRequired: Bool

    public init(
        endpointIdentity: String,
        handoffProtocolVersions: [String],
        acceptedBundleSchemaVersions: [String],
        acceptedPayloadSchemas: [HTDTAcceptedPayloadSchema] = [],
        supportedAuthorityFamilies: [String] = [],
        maxArchiveBytes: Int64? = nil,
        missionReceiptsSupported: Bool = false,
        acceptedArtifactKinds: [HTDTArtifactKindCapability]? = nil,
        missionPackagesServed: Bool = false,
        equipmentCatalogsRecognized: [String] = [],
        projectRef: String? = nil,
        manualReviewRequired: Bool = false
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.endpointIdentity = endpointIdentity
        self.handoffProtocolVersions = handoffProtocolVersions
        self.acceptedBundleSchemaVersions = acceptedBundleSchemaVersions
        self.acceptedPayloadSchemas = acceptedPayloadSchemas
        self.supportedAuthorityFamilies = supportedAuthorityFamilies
        self.maxArchiveBytes = maxArchiveBytes
        self.missionReceiptsSupported = missionReceiptsSupported
        self.acceptedArtifactKinds = acceptedArtifactKinds
        self.missionPackagesServed = missionPackagesServed
        self.equipmentCatalogsRecognized = equipmentCatalogsRecognized
        self.projectRef = projectRef
        self.manualReviewRequired = manualReviewRequired
    }

    /// Resolved per-kind capabilities: an explicit list when the
    /// receiver advertises one, otherwise the legacy default —
    /// `capture_bundle` only (issue bolph71656-ai/HTDT-Capture#423 §14 backward compat: a
    /// capture-only receiver stays usable for `.htdtcapture` and is
    /// preflighted as unsupported for field returns).
    public var acceptedKinds: [HTDTArtifactKindCapability] {
        acceptedArtifactKinds ?? [
            HTDTArtifactKindCapability(
                artifactKind: HTDTDeliverableKind.captureBundle.rawValue
            )
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case endpointIdentity = "endpoint_identity"
        case handoffProtocolVersions = "handoff_protocol_versions"
        case acceptedBundleSchemaVersions =
            "accepted_bundle_schema_versions"
        case acceptedPayloadSchemas = "accepted_payload_schemas"
        case supportedAuthorityFamilies = "supported_authority_families"
        case maxArchiveBytes = "max_archive_bytes"
        case missionReceiptsSupported = "mission_receipts_supported"
        case acceptedArtifactKinds = "accepted_artifact_kinds"
        case missionPackagesServed = "mission_packages_served"
        case equipmentCatalogsRecognized =
            "equipment_catalogs_recognized"
        case projectRef = "project_ref"
        case manualReviewRequired = "manual_review_required"
    }
}

/// One artifact-family admission entry in the capability document
/// (legacy bolph71656-ai/HTDT-Capture#423 §5): the receiver stages this kind, within this schema
/// range and byte ceiling.
public struct HTDTArtifactKindCapability:
    Codable, Sendable, Equatable
{
    /// `HTDTDeliverableKind` raw value (e.g. `capture_bundle`,
    /// `field_return`).
    public let artifactKind: String
    /// Artifact document schema versions the receiver parses; an
    /// empty list means any version stages without promotion.
    public let acceptedSchemaVersions: [String]
    /// Byte ceiling for this artifact family; nil falls back to the
    /// document-wide `max_archive_bytes`.
    public let maxArchiveBytes: Int64?

    public init(
        artifactKind: String,
        acceptedSchemaVersions: [String] = [],
        maxArchiveBytes: Int64? = nil
    ) {
        self.artifactKind = artifactKind
        self.acceptedSchemaVersions = acceptedSchemaVersions
        self.maxArchiveBytes = maxArchiveBytes
    }

    private enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case acceptedSchemaVersions = "accepted_schema_versions"
        case maxArchiveBytes = "max_archive_bytes"
    }
}

/// One payload-schema admission entry in the capability document.
public struct HTDTAcceptedPayloadSchema:
    Codable, Sendable, Equatable
{
    public let schema: String
    public let versions: [String]

    public init(schema: String, versions: [String]) {
        self.schema = schema
        self.versions = versions
    }
}

/// A fetched capability document plus when it was fetched — a cached
/// snapshot is always labeled with its fetch time and never presented
/// as live receiver state (issue bolph71656-ai/HTDT-Capture#374).
public struct HTDTEndpointCapabilitySnapshot:
    Codable, Sendable, Equatable
{
    public let document: HTDTEndpointCapabilityDocument
    public let fetchedAtUTC: String

    public init(
        document: HTDTEndpointCapabilityDocument,
        fetchedAtUTC: String
    ) {
        self.document = document
        self.fetchedAtUTC = fetchedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case document
        case fetchedAtUTC = "fetched_at"
    }
}

/// What the sender knows about the bundle it is about to transfer,
/// assembled without opening any archive bytes (issue bolph71656-ai/HTDT-Capture#374).
public struct HTDTBundleInventory: Sendable, Equatable {
    /// Bundle manifest `schema_version` of the archive being sent.
    public var bundleSchemaVersion: String
    /// Registry schema names for every payload the manifest declares.
    public var payloadSchemaNames: [String]
    /// Authority families (`SemanticTaskKind` tokens) present with at
    /// least one record in the bundle's authority collection.
    public var authorityFamilies: [String]
    /// Identity keys of equipment catalogs the bundle carries.
    public var equipmentCatalogKeys: [String]
    /// Byte size of the `.htdtcapture` archive file.
    public var archiveByteCount: Int64
    /// Project binding asserted by the capture, if recorded.
    public var projectRef: String?

    public init(
        bundleSchemaVersion: String,
        payloadSchemaNames: [String],
        authorityFamilies: [String],
        equipmentCatalogKeys: [String] = [],
        archiveByteCount: Int64,
        projectRef: String? = nil
    ) {
        self.bundleSchemaVersion = bundleSchemaVersion
        self.payloadSchemaNames = payloadSchemaNames
        self.authorityFamilies = authorityFamilies
        self.equipmentCatalogKeys = equipmentCatalogKeys
        self.archiveByteCount = archiveByteCount
        self.projectRef = projectRef
    }

    /// Inventory derived from a validated bundle manifest. Payload
    /// schema names come from `CaptureBundleSchemaRegistry`; payload
    /// contents are never opened or repackaged for preflight.
    public init(
        manifest: BundleManifest,
        authorities: TheaterAuthorityCollection,
        equipmentCatalogKeys: [String] = [],
        archiveByteCount: Int64,
        projectRef: String? = nil
    ) {
        var schemas = Set<String>()
        for file in manifest.files {
            if let name = CaptureBundleSchemaRegistry.schemaName(
                forPath: file.path
            ) {
                schemas.insert(name)
            }
        }
        self.init(
            bundleSchemaVersion: manifest.schemaVersion,
            payloadSchemaNames: schemas.sorted(),
            authorityFamilies: authorities.presentAuthorityFamilies(),
            equipmentCatalogKeys: equipmentCatalogKeys,
            archiveByteCount: archiveByteCount,
            projectRef: projectRef
        )
    }
}

/// One concrete way a receiver falls short of what the sender needs
/// (issue bolph71656-ai/HTDT-Capture#374). `subject` names the schema/family/protocol; `detail`
/// is the operator-facing explanation.
public struct HTDTCompatibilityGap: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// Hard failure — the receiver cannot accept this transfer.
        case unsupportedBundleVersion = "unsupported_bundle_version"
        case unsupportedHandoffProtocol =
            "unsupported_handoff_protocol"
        case archiveTooLarge = "archive_too_large"
        case missionReceiptsUnsupported =
            "mission_receipts_unsupported"
        /// Omission — receiver stages the bytes but cannot promote
        /// this content yet; reported precisely, never stripped.
        case unsupportedPayloadSchema = "unsupported_payload_schema"
        case unsupportedAuthorityFamily =
            "unsupported_authority_family"
        case unrecognizedEquipmentCatalog =
            "unrecognized_equipment_catalog"
        case projectRefMismatch = "project_ref_mismatch"
        /// Hard failure — the receiver cannot stage this artifact
        /// family at all (legacy bolph71656-ai/HTDT-Capture#423 §5): e.g. a field return aimed at a
        /// capture-only receiver. The Send button is disabled with
        /// this explanation; Share remains.
        case unsupportedArtifactKind = "unsupported_artifact_kind"
    }

    public let kind: Kind
    public let subject: String
    public let detail: String

    public init(kind: Kind, subject: String, detail: String) {
        self.kind = kind
        self.subject = subject
        self.detail = detail
    }
}

/// Verdict of the legacy bolph71656-ai/HTDT-Capture#374 preflight handshake. Hard failures block the
/// send with a precise list; omissions permit the send while naming
/// exactly what the receiver will stage-but-not-promote; `unknown`
/// means the endpoint gave no verifiable capability document.
public enum HTDTCompatibilityVerdict: Sendable, Equatable {
    case compatible
    case compatibleWithOmissions([HTDTCompatibilityGap])
    case incompatible([HTDTCompatibilityGap])
    /// Endpoint unreachable, no capability endpoint, or an
    /// undecodable document. `reason` is operator-facing.
    case unknown(reason: String)

    /// True when the send may proceed (possibly with named
    /// omissions).
    public var sendPermitted: Bool {
        switch self {
        case .compatible, .compatibleWithOmissions:
            return true
        case .incompatible, .unknown:
            return false
        }
    }
}

/// Declared inside a mission envelope (legacy bolph71656-ai/HTDT-Capture#386): the minimum receiver
/// capability a capture run for this mission requires. Surfaced
/// before scanning starts so an operator never captures a long
/// mission the chosen receiver cannot ingest (issue bolph71656-ai/HTDT-Capture#374).
public struct HTDTMissionReceiverRequirement:
    Codable, Sendable, Equatable
{
    /// Required `project_ref` on the destination, if any.
    public let destinationProjectRef: String?
    /// Minimum handoff protocol version (string compare on the
    /// advertised list; nil means any).
    public let minHandoffProtocol: String?
    /// Authority families the receiver must promote.
    public let requiredAuthorityFamilies: [String]
    /// Payload schemas the receiver must promote.
    public let requiredPayloadSchemas: [String]
    /// True when the mission requires mission-receipt support.
    public let requireMissionReceipts: Bool

    public init(
        destinationProjectRef: String? = nil,
        minHandoffProtocol: String? = nil,
        requiredAuthorityFamilies: [String] = [],
        requiredPayloadSchemas: [String] = [],
        requireMissionReceipts: Bool = false
    ) {
        self.destinationProjectRef = destinationProjectRef
        self.minHandoffProtocol = minHandoffProtocol
        self.requiredAuthorityFamilies = requiredAuthorityFamilies
        self.requiredPayloadSchemas = requiredPayloadSchemas
        self.requireMissionReceipts = requireMissionReceipts
    }

    private enum CodingKeys: String, CodingKey {
        case destinationProjectRef = "destination_project_ref"
        case minHandoffProtocol = "min_handoff_protocol"
        case requiredAuthorityFamilies = "required_authority_families"
        case requiredPayloadSchemas = "required_payload_schemas"
        case requireMissionReceipts = "require_mission_receipts"
    }
}

/// Pure preflight classifier (issue bolph71656-ai/HTDT-Capture#374): no I/O, fully unit
/// testable. Bundle requirements split into hard gaps (block the
/// send) and deferrable omissions (stage-only content) — the send
/// never repackages or strips content to fit.
public enum HTDTCompatibilityChecker {
    /// Preflight a bundle against a capability document.
    /// `requiresMissionReceipts` is set for queue jobs bound to a
    /// mission receipt expectation (legacy bolph71656-ai/HTDT-Capture#386/legacy bolph71656-ai/HTDT-Capture#387).
    public static func check(
        inventory: HTDTBundleInventory,
        capabilities: HTDTEndpointCapabilityDocument,
        requiresMissionReceipts: Bool = false
    ) -> HTDTCompatibilityVerdict {
        var hard: [HTDTCompatibilityGap] = []
        var omissions: [HTDTCompatibilityGap] = []

        if !capabilities.handoffProtocolVersions.contains(
            HTDTEndpointCapabilityDocument.handoffProtocol
        ) {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedHandoffProtocol,
                subject: HTDTEndpointCapabilityDocument.handoffProtocol,
                detail: "Receiver does not accept handoff protocol "
                    + HTDTEndpointCapabilityDocument.handoffProtocol
            ))
        }
        // Artifact-kind admission (legacy bolph71656-ai/HTDT-Capture#423 §5): a receiver that
        // enumerates accepted_artifact_kinds without a
        // capture_bundle entry cannot stage captures at all.
        let kindAdmission = capabilities.acceptedKinds.first {
            $0.artifactKind
                == HTDTDeliverableKind.captureBundle.rawValue
        }
        if kindAdmission == nil {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedArtifactKind,
                subject: HTDTDeliverableKind.captureBundle.rawValue,
                detail: "Receiver does not accept "
                    + HTDTDeliverableKind.captureBundle.displayName
            ))
        }
        if !capabilities.acceptedBundleSchemaVersions.contains(
            inventory.bundleSchemaVersion
        ) {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedBundleVersion,
                subject: inventory.bundleSchemaVersion,
                detail: "Receiver does not accept bundle schema "
                    + "version " + inventory.bundleSchemaVersion
            ))
        }
        if let admission = kindAdmission,
           !admission.acceptedSchemaVersions.isEmpty,
           !admission.acceptedSchemaVersions
               .contains(inventory.bundleSchemaVersion)
        {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedArtifactKind,
                subject: inventory.bundleSchemaVersion,
                detail: "Receiver does not accept "
                    + HTDTDeliverableKind.captureBundle.displayName
                    + " schema " + inventory.bundleSchemaVersion
            ))
        }
        let byteCeiling = kindAdmission?.maxArchiveBytes
            ?? capabilities.maxArchiveBytes
        if let maxBytes = byteCeiling,
           inventory.archiveByteCount > maxBytes
        {
            hard.append(HTDTCompatibilityGap(
                kind: .archiveTooLarge,
                subject: String(inventory.archiveByteCount),
                detail: "Archive exceeds receiver limit of "
                    + String(maxBytes) + " bytes"
            ))
        }
        if requiresMissionReceipts,
           !capabilities.missionReceiptsSupported
        {
            hard.append(HTDTCompatibilityGap(
                kind: .missionReceiptsUnsupported,
                subject: "mission_receipts",
                detail: "Mission-bound delivery requires mission "
                    + "receipt support the receiver does not advertise"
            ))
        }

        let acceptedSchemas = Dictionary(
            capabilities.acceptedPayloadSchemas.map {
                ($0.schema, $0.versions)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for name in inventory.payloadSchemaNames
        where acceptedSchemas[name] == nil {
            omissions.append(HTDTCompatibilityGap(
                kind: .unsupportedPayloadSchema,
                subject: name,
                detail: "Receiver stages but cannot promote payload "
                    + "schema " + name
            ))
        }
        for family in inventory.authorityFamilies
        where !capabilities.supportedAuthorityFamilies
            .contains(family)
        {
            omissions.append(HTDTCompatibilityGap(
                kind: .unsupportedAuthorityFamily,
                subject: family,
                detail: "Receiver stages but cannot promote authority "
                    + "family " + family
            ))
        }
        for key in inventory.equipmentCatalogKeys
        where !capabilities.equipmentCatalogsRecognized.contains(key)
        {
            omissions.append(HTDTCompatibilityGap(
                kind: .unrecognizedEquipmentCatalog,
                subject: key,
                detail: "Receiver does not recognize equipment "
                    + "catalog " + key
            ))
        }
        if let receiverProject = capabilities.projectRef,
           let captureProject = inventory.projectRef,
           receiverProject != captureProject
        {
            omissions.append(HTDTCompatibilityGap(
                kind: .projectRefMismatch,
                subject: captureProject,
                detail: "Receiver is bound to project "
                    + receiverProject + " but the capture declares "
                    + captureProject
            ))
        }

        if !hard.isEmpty {
            return .incompatible(hard + omissions)
        }
        if !omissions.isEmpty {
            return .compatibleWithOmissions(omissions)
        }
        return .compatible
    }

    /// Artifact-kind preflight (legacy bolph71656-ai/HTDT-Capture#423 §5): whether the receiver
    /// stages this artifact family at all. `capture_bundle` keeps
    /// the full bundle check above; other kinds run only the
    /// kind/schema/size admission — never a bundle-manifest
    /// requirement against non-bundle bytes.
    public static func checkDeliverable(
        deliverable: HTDTDeliverableIdentity,
        archiveByteCount: Int64,
        capabilities: HTDTEndpointCapabilityDocument,
        requiresMissionReceipts: Bool = false
    ) -> HTDTCompatibilityVerdict {
        var hard: [HTDTCompatibilityGap] = []
        if !capabilities.handoffProtocolVersions.contains(
            HTDTEndpointCapabilityDocument.handoffProtocol
        ) {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedHandoffProtocol,
                subject: HTDTEndpointCapabilityDocument.handoffProtocol,
                detail: "Receiver does not accept handoff protocol "
                    + HTDTEndpointCapabilityDocument.handoffProtocol
            ))
        }
        let kindAdmission = capabilities.acceptedKinds.first {
            $0.artifactKind == deliverable.artifactKind.rawValue
        }
        guard let kindAdmission else {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedArtifactKind,
                subject: deliverable.artifactKind.rawValue,
                detail: "Receiver does not accept "
                    + deliverable.artifactKind.displayName
            ))
            return .incompatible(hard)
        }
        if let schemaVersion = deliverable.schemaVersion,
           !kindAdmission.acceptedSchemaVersions.isEmpty,
           !kindAdmission.acceptedSchemaVersions
               .contains(schemaVersion)
        {
            hard.append(HTDTCompatibilityGap(
                kind: .unsupportedArtifactKind,
                subject: schemaVersion,
                detail: "Receiver does not accept "
                    + deliverable.artifactKind.displayName
                    + " schema " + schemaVersion
            ))
        }
        let byteCeiling = kindAdmission.maxArchiveBytes
            ?? capabilities.maxArchiveBytes
        if let maxBytes = byteCeiling,
           archiveByteCount > maxBytes
        {
            hard.append(HTDTCompatibilityGap(
                kind: .archiveTooLarge,
                subject: String(archiveByteCount),
                detail: "Archive exceeds receiver limit of "
                    + String(maxBytes) + " bytes"
            ))
        }
        if requiresMissionReceipts,
           !capabilities.missionReceiptsSupported
        {
            hard.append(HTDTCompatibilityGap(
                kind: .missionReceiptsUnsupported,
                subject: "mission_receipts",
                detail: "Mission-bound delivery requires mission "
                    + "receipt support the receiver does not advertise"
            ))
        }
        return hard.isEmpty ? .compatible : .incompatible(hard)
    }

    /// Preflight a mission's declared minimum receiver requirement —
    /// run before scanning starts (legacy bolph71656-ai/HTDT-Capture#386/legacy bolph71656-ai/HTDT-Capture#374). Every requirement is
    /// hard: a mission whose receiver cannot meet it must be refused
    /// rather than captured-then-rejected.
    public static func checkMissionRequirement(
        _ requirement: HTDTMissionReceiverRequirement,
        capabilities: HTDTEndpointCapabilityDocument
    ) -> HTDTCompatibilityVerdict {
        var gaps: [HTDTCompatibilityGap] = []
        if let minProtocol = requirement.minHandoffProtocol,
           !capabilities.handoffProtocolVersions
               .contains(minProtocol)
        {
            gaps.append(HTDTCompatibilityGap(
                kind: .unsupportedHandoffProtocol,
                subject: minProtocol,
                detail: "Mission requires handoff protocol "
                    + minProtocol
            ))
        }
        if requirement.requireMissionReceipts,
           !capabilities.missionReceiptsSupported
        {
            gaps.append(HTDTCompatibilityGap(
                kind: .missionReceiptsUnsupported,
                subject: "mission_receipts",
                detail: "Mission requires mission receipt support"
            ))
        }
        if let requiredProject = requirement.destinationProjectRef,
           capabilities.projectRef != requiredProject
        {
            gaps.append(HTDTCompatibilityGap(
                kind: .projectRefMismatch,
                subject: requiredProject,
                detail: "Mission requires a receiver bound to project "
                    + requiredProject
            ))
        }
        let acceptedSchemas = Set(
            capabilities.acceptedPayloadSchemas.map(\.schema)
        )
        for name in requirement.requiredPayloadSchemas
        where !acceptedSchemas.contains(name) {
            gaps.append(HTDTCompatibilityGap(
                kind: .unsupportedPayloadSchema,
                subject: name,
                detail: "Mission requires payload schema " + name
            ))
        }
        for family in requirement.requiredAuthorityFamilies
        where !capabilities.supportedAuthorityFamilies
            .contains(family)
        {
            gaps.append(HTDTCompatibilityGap(
                kind: .unsupportedAuthorityFamily,
                subject: family,
                detail: "Mission requires authority family " + family
            ))
        }
        return gaps.isEmpty ? .compatible : .incompatible(gaps)
    }
}

/// Fetches an endpoint's `htdt.endpoint-capabilities` document over
/// HTTPS with a bounded read (issue bolph71656-ai/HTDT-Capture#374). When the destination was
/// QR-paired, the same pin is enforced for the capability fetch as
/// for the archive upload.
public struct HTDTCapabilityClient: Sendable {
    /// Capability documents are small descriptors — anything larger
    /// is refused rather than parsed.
    public static let maxDocumentBytes = 256 * 1024

    public init() {}

    public func fetch(
        endpoint: URL,
        pinnedIdentity: String? = nil,
        session: URLSession = .shared
    ) async throws -> HTDTEndpointCapabilitySnapshot {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil
        else {
            throw HTDTCapabilityFetchError.invalidEndpointURL
        }
        let transport = pinnedIdentity.map {
            HTDTIdentityPinningSession.session(pinnedIdentity: $0)
        } ?? session
        let request = URLRequest(url: endpoint)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw HTDTCapabilityFetchError.transportFailed(
                String(describing: error)
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTDTCapabilityFetchError.malformedDocument
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTDTCapabilityFetchError.endpointRejected(
                statusCode: http.statusCode
            )
        }
        guard data.count <= Self.maxDocumentBytes else {
            throw HTDTCapabilityFetchError.documentTooLarge
        }
        guard let document = try? JSONDecoder().decode(
            HTDTEndpointCapabilityDocument.self,
            from: data
        ), document.schema == HTDTEndpointCapabilityDocument.schema
        else {
            throw HTDTCapabilityFetchError.malformedDocument
        }
        return HTDTEndpointCapabilitySnapshot(
            document: document,
            fetchedAtUTC: BundleTimestamp.utcString(from: Date())
        )
    }
}

extension TheaterAuthorityCollection {
    /// Authority families with at least one record — the
    /// `SemanticTaskKind` tokens a receiver must be able to promote
    /// for a full-fidelity ingestion (issue bolph71656-ai/HTDT-Capture#374).
    public func presentAuthorityFamilies() -> [String] {
        var families: [String] = []
        if !surfaceSemantics.isEmpty {
            families.append(SemanticTaskKind.surfaceSemantics.rawValue)
        }
        if !surfaceConstructions.isEmpty {
            families.append(
                SemanticTaskKind.surfaceConstruction.rawValue
            )
        }
        if !problemSurfaces.isEmpty {
            families.append(SemanticTaskKind.problemSurface.rawValue)
        }
        if !constructionFeatures.isEmpty {
            families.append(
                SemanticTaskKind.constructionFeature.rawValue
            )
        }
        if !roomStateObservations.isEmpty {
            families.append(
                SemanticTaskKind.roomStateObservation.rawValue
            )
        }
        if !roomStateSnapshots.isEmpty {
            families.append(
                SemanticTaskKind.roomStateSnapshot.rawValue
            )
        }
        if !inventoryItems.isEmpty {
            families.append(SemanticTaskKind.inventoryItem.rawValue)
        }
        if !furnitureSemantics.isEmpty {
            families.append(
                SemanticTaskKind.furnitureSemantics.rawValue
            )
        }
        if !speakerInstallations.isEmpty {
            families.append(
                SemanticTaskKind.speakerInstallation.rawValue
            )
        }
        if !screenSemantics.isEmpty {
            families.append(SemanticTaskKind.screenSemantics.rawValue)
        }
        if !seatLayouts.isEmpty {
            families.append(SemanticTaskKind.seatLayout.rawValue)
        }
        if !routingVerifications.isEmpty {
            families.append(
                SemanticTaskKind.routingVerification.rawValue
            )
        }
        if !projectorCommissionings.isEmpty {
            families.append(
                SemanticTaskKind.projectorCommissioning.rawValue
            )
        }
        if !installationAlignments.isEmpty {
            families.append(
                SemanticTaskKind.installationAlignment.rawValue
            )
        }
        return families
    }
}
