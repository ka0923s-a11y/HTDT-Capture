import Foundation

/// Identity of a typed semantic relation record (issue #333).
public struct SemanticRelationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Open `relation_type` vocabulary (#333, namespaced per #344).
/// Standard types encode the families the contract itself defines;
/// deployments may add custom types under the reserved `x_` prefix
/// which can never collide with future standard vocabulary.
public struct SemanticRelationType:
    RawRepresentable,
    Codable,
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        guard SchemaOwnedText.nfc(rawValue) == rawValue,
              rawValue.range(
                  of: #"^[a-z0-9_]+$"#,
                  options: .regularExpression
              ) != nil
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid relation_type token"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// One entity rests on / is mounted to another entity or an
    /// external surface authority (e.g. speaker on stand, projector on
    /// ceiling mount).
    public static let mountedOn = Self(rawValue: "mounted_on")!
    /// A device physically housed in an equipment_rack entity.
    public static let memberOfRack = Self(rawValue: "member_of_rack")!
    /// A listening position serves as the reference point for a seat.
    public static let listenerPointForSeat =
        Self(rawValue: "listener_point_for_seat")!
    /// A reference point (e.g. eye point) belongs to a seat.
    public static let eyePointForSeat =
        Self(rawValue: "eye_point_for_seat")!
    /// Supported-by riser/platform grouping (e.g. sub on riser).
    public static let supportedBy = Self(rawValue: "supported_by")!
    /// Loudspeaker positioned behind a projection_screen.
    public static let behindScreen = Self(rawValue: "behind_screen")!
    /// A physical run/edge terminates at a point or surface (e.g.
    /// cable route, acoustic tube).
    public static let terminatesAt = Self(rawValue: "terminates_at")!
    /// Observed as-built entity corresponds to a planned HTDT target.
    public static let correspondsToPlannedTarget =
        Self(rawValue: "corresponds_to_planned_target")!
    /// Logical channel/role binding between a physical source and a
    /// logical topology node (the object is an external topology ref).
    public static let logicalRoleBinding =
        Self(rawValue: "logical_role_binding")!
    /// A logical/declared channel routes to a physical loudspeaker —
    /// subject may be an external topology reference.
    public static let routesToPhysicalSource =
        Self(rawValue: "routes_to_physical_source")!

    /// The standard tokens defined by this contract version. The set
    /// is pinned per contract — a later contract may add tokens but
    /// never redefines or removes an existing one (#344).
    public static let standardSet: Set<String> = [
        "mounted_on", "member_of_rack", "listener_point_for_seat",
        "eye_point_for_seat", "supported_by", "behind_screen",
        "terminates_at", "corresponds_to_planned_target",
        "logical_role_binding", "routes_to_physical_source",
    ]
}

/// Reference to a relation endpoint (#333). Endpoints are either
/// entities committed in the same capture revision (a bare canonical
/// `AnnotationEntityID` UUID) or an explicitly namespaced external /
/// reference authority written `namespace:reference` (e.g.
/// `htdt_topology:L`, `stand:vendor-x42`). This keeps referential
/// integrity checkable: either the ref resolves inside the revision,
/// or it declares the authority that owns it.
public struct SemanticRelationEndpoint:
    RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    /// The entity this endpoint references, when it is a same-revision
    /// entity reference.
    public var entityID: AnnotationEntityID? {
        AnnotationEntityID(canonicalString: rawValue)
    }

    /// `(namespace, reference)` when this endpoint is an external
    /// authority reference.
    public var externalRef: (namespace: String, reference: String)? {
        guard entityID == nil,
              let colon = rawValue.firstIndex(of: ":")
        else { return nil }
        let ns = String(rawValue[..<colon])
        let ref = String(rawValue[rawValue.index(after: colon)...])
        return (ns, ref)
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(entityID: AnnotationEntityID) {
        self.rawValue = entityID.description
    }

    /// Parse an endpoint: a bare canonical UUIDv4 entity reference, or
    /// a `namespace:reference` external authority token.
    public init?(validating rawValue: String) {
        if AnnotationEntityID(canonicalString: rawValue) != nil {
            self.rawValue = rawValue
            return
        }
        guard rawValue.range(
            of: #"^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.:/-]*$"#,
            options: .regularExpression
        ) != nil,
              SchemaOwnedText.nfc(rawValue) == rawValue
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// External authority endpoint.
    public init?(externalNamespace namespace: String, reference: String) {
        let raw = "\(namespace):\(reference)"
        guard let value = SemanticRelationEndpoint(validating: raw),
              value.entityID == nil
        else { return nil }
        self = value
    }

    public var description: String { rawValue }
}

public enum SemanticRelationError: Error, Equatable {
    case emptyField
    case invalidEndpoint
    case tooManyObjects
    case tooManyAttributes
    case invalidTimestamp
    case selfReferentialRelation
}

/// A typed entity-to-entity (or entity-to-external-authority) relation
/// (#333). Replaces the previous ad-hoc coupling fields with a shared,
/// versioned record: the same reference/provenance model serves the
/// whole relation family — physical mounting, rack membership,
/// listener/seat pairing, planned↔observed correspondence, and logical
/// topology binding.
///
/// The relation carries its own `provenance_class` /
/// `verification_state` / `evidence_refs`: relation provenance is
/// deliberately independent from the provenance of either endpoint —
/// e.g. an imported reference plan can assert a relation between two
/// user-annotated entities.
public struct CaptureSemanticRelation: Codable, Sendable, Equatable {
    public let relationID: SemanticRelationID
    public let relationType: SemanticRelationType
    public let subjectRef: SemanticRelationEndpoint
    /// 1...16 object endpoints — one-to-many relations (e.g. a rack
    /// containing several devices) stay representable.
    public let objectRefs: [SemanticRelationEndpoint]
    public let provenanceClass: AnnotationProvenanceClass
    public let verificationState: AnnotationVerificationState
    public let evidenceRefs: [String]
    public let createdAtUTC: String?
    public let updatedAtUTC: String?
    /// Bounded optional attributes: small scalar annotations owned by
    /// the relation (e.g. `{"orientation": "firing_up"}`). Max 16
    /// entries, non-empty keys/values, NFC.
    public let attributes: [String: String]

    public static let maxObjectRefs = 16
    public static let maxAttributes = 16

    public init(
        relationID: SemanticRelationID = .init(),
        relationType: SemanticRelationType,
        subjectRef: SemanticRelationEndpoint,
        objectRefs: [SemanticRelationEndpoint],
        provenanceClass: AnnotationProvenanceClass,
        verificationState: AnnotationVerificationState,
        evidenceRefs: [String] = [],
        createdAtUTC: String? = nil,
        updatedAtUTC: String? = nil,
        attributes: [String: String] = [:]
    ) throws {
        guard !objectRefs.isEmpty else {
            throw SemanticRelationError.emptyField
        }
        guard objectRefs.count <= Self.maxObjectRefs else {
            throw SemanticRelationError.tooManyObjects
        }
        guard attributes.count <= Self.maxAttributes,
              attributes.allSatisfy({
                  !$0.key.isEmpty && !$0.value.isEmpty
                      && SchemaOwnedText.nfc($0.key) == $0.key
                      && SchemaOwnedText.nfc($0.value) == $0.value
              })
        else {
            throw SemanticRelationError.tooManyAttributes
        }
        if let createdAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(createdAtUTC)
            else { throw SemanticRelationError.invalidTimestamp }
        }
        if let updatedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(updatedAtUTC)
            else { throw SemanticRelationError.invalidTimestamp }
        }
        // A relation is between two endpoints — self-links carry no
        // semantics.
        guard !objectRefs.contains(subjectRef) else {
            throw SemanticRelationError.selfReferentialRelation
        }
        self.relationID = relationID
        self.relationType = relationType
        self.subjectRef = subjectRef
        self.objectRefs = objectRefs
        self.provenanceClass = provenanceClass
        self.verificationState = verificationState
        self.evidenceRefs = SchemaOwnedText.nfc(evidenceRefs)
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
        self.attributes = attributes
    }

    private enum CodingKeys: String, CodingKey {
        case relationID = "relation_id"
        case relationType = "relation_type"
        case subjectRef = "subject_ref"
        case objectRefs = "object_refs"
        case provenanceClass = "provenance_class"
        case verificationState = "verification_state"
        case evidenceRefs = "evidence_refs"
        case createdAtUTC = "created_at_utc"
        case updatedAtUTC = "updated_at_utc"
        case attributes
    }
}

public enum SemanticRelationGraphError: Error, Equatable {
    /// Two relations share an id.
    case duplicateRelationID
    /// Two relations carry the same (type, subject, object) tuple.
    case duplicateRelation
    /// An entity endpoint does not resolve to an entity in the same
    /// revision.
    case danglingEntityReference
    /// The relation type does not allow this endpoint combination.
    case disallowedEndpointCombination
    /// A non-standard relation type is not custom-scoped (#344).
    case unscopedCustomRelationType
}

/// Entity-type combination policy for the standard relation types
/// (#333): each known type bounds subject/object roles; custom `x_`
/// types are open. Endpoint entities are looked up in the same
/// revision; external endpoints are accepted only where the type
/// permits.
public enum SemanticRelationPolicy {
    /// Whether `relationType` permits a relation whose subject resolves
    /// to `subjectType` (nil = external endpoint) and whose object
    /// resolves to `objectType` (nil = external endpoint).
    public static func allows(
        _ relationType: SemanticRelationType,
        subjectType: AnnotationEntityType?,
        objectType: AnnotationEntityType?
    ) -> Bool {
        switch relationType.rawValue {
        case "mounted_on":
            // Equipment/fixtures mount onto entities or surfaces.
            // Subject is the mounted device; object may be any entity
            // or an external surface authority.
            let subjects: Set<AnnotationEntityType> = [
                .speaker, .subwoofer, .display, .projector,
                .acousticTreatment, .custom,
            ]
            return subjectType.map(subjects.contains) ?? false
        case "member_of_rack":
            // Only rack-housed devices; object must be the rack itself.
            guard objectType == .equipmentRack else { return false }
            let subjects: Set<AnnotationEntityType> = [
                .speaker, .subwoofer, .display, .projector, .custom,
            ]
            return subjectType.map(subjects.contains) ?? false
        case "listener_point_for_seat":
            let subjects: Set<AnnotationEntityType> = [
                .listeningPosition, .measurementPoint,
            ]
            return subjectType.map(subjects.contains) ?? false
                && objectType == .seat
        case "eye_point_for_seat":
            let subjects: Set<AnnotationEntityType> = [
                .referencePoint, .listeningPosition,
            ]
            return subjectType.map(subjects.contains) ?? false
                && objectType == .seat
        case "supported_by":
            // Riser/platform support: subject is any physical entity,
            // object is the supporting entity or an external surface.
            return subjectType != nil && objectType != nil
        case "behind_screen":
            let subjects: Set<AnnotationEntityType> = [
                .speaker, .subwoofer,
            ]
            return subjectType.map(subjects.contains) ?? false
                && objectType == .projectionScreen
        case "terminates_at":
            return subjectType != nil && objectType != nil
        case "corresponds_to_planned_target":
            // Observed entity corresponds to a planned target — the
            // target is typically an external HTDT authority ref.
            return subjectType != nil
        case "logical_role_binding":
            // A logical channel/role binds to a physical source; the
            // object is an external topology ref or a loudspeaker.
            let subjects: Set<AnnotationEntityType> = [
                .speaker, .subwoofer,
            ]
            return subjectType.map(subjects.contains) ?? false
        case "routes_to_physical_source":
            // Subject may be an external topology ref; object must be
            // the physical loudspeaker.
            let objects: Set<AnnotationEntityType> = [
                .speaker, .subwoofer,
            ]
            return objectType.map(objects.contains) ?? false
        default:
            // Custom-scoped relation types are open (#344).
            return true
        }
    }
}

extension CaptureSemanticRelation {
    /// Whether this relation references `entityID` at any endpoint —
    /// used to surface dependent relations before an entity delete or
    /// edit commits (#333).
    public func references(entityID: AnnotationEntityID) -> Bool {
        subjectRef.entityID == entityID
            || objectRefs.contains { $0.entityID == entityID }
    }
}
