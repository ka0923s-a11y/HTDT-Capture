import Foundation

/// Canonicalization for schema-owned text. The capture-bundle JSON
/// contract requires every emitted string to be NFC-normalized so that
/// canonically equivalent user input produces identical authority bytes.
/// Token/identifier types with stricter ASCII rules keep their own
/// validation and never pass through here.
enum SchemaOwnedText {
    static func nfc(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
    }

    static func nfc(_ value: String?) -> String? {
        value.map(nfc)
    }

    static func nfc(_ values: [String]) -> [String] {
        values.map(nfc)
    }

    static func nfc(_ values: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(values.count)
        // Sort by the original key so that keys colliding after
        // normalization resolve deterministically.
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            result[nfc(key)] = nfc(value)
        }
        return result
    }
}

public struct AnnotationEntityID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum AnnotationEntityType: String, Codable, Sendable, CaseIterable {
    case speaker
    case subwoofer
    case display
    case projectionScreen = "projection_screen"
    case projector
    case listeningPosition = "listening_position"
    case seat
    case acousticTreatment = "acoustic_treatment"
    case equipmentRack = "equipment_rack"
    case referencePoint = "reference_point"
    /// An acoustic measurement microphone/capsule reference point used
    /// for a measurement campaign; distinct from `listening_position`
    /// even when they spatially coincide (issue #271).
    case measurementPoint = "measurement_point"
    case custom

    /// The reference-point semantics the manual builder assigns when
    /// the caller does not name the point actually authored (#291).
    public var defaultReferenceSemantics: ReferencePointSemantics {
        switch self {
        case .speaker, .subwoofer:
            return .cabinetReferencePoint
        case .display:
            return .displayCenter
        case .projectionScreen:
            return .screenCenter
        case .projector:
            return .projectorBodyReference
        case .listeningPosition:
            return .earCenter
        case .seat:
            return .seatReferencePoint
        case .measurementPoint:
            return .microphoneCapsule
        case .acousticTreatment, .equipmentRack,
             .referencePoint, .custom:
            return .userReferencePoint
        }
    }

    /// The semantics tokens a point of this type may claim. `nil`
    /// means unrestricted (`.custom`); an empty intersection is
    /// impossible because every entry contains the default. Acoustic
    /// center is deliberately absent: it is governed by the separate
    /// `acoustic_center` authority (#234) and is never a placement
    /// label.
    public var allowedReferenceSemantics: Set<ReferencePointSemantics>? {
        switch self {
        case .speaker, .subwoofer:
            return [.cabinetReferencePoint, .userReferencePoint]
        case .display:
            return [.displayCenter, .userReferencePoint]
        case .projectionScreen:
            return [.screenCenter, .userReferencePoint]
        case .projector:
            return [
                .projectorBodyReference,
                .projectorLensCenter,
                .userReferencePoint,
            ]
        case .listeningPosition:
            return [.earCenter, .seatReferencePoint,
                    .userReferencePoint]
        case .seat:
            return [.seatReferencePoint, .userReferencePoint]
        case .equipmentRack:
            return [.cabinetReferencePoint, .userReferencePoint]
        case .measurementPoint:
            return [.microphoneCapsule, .userReferencePoint]
        case .acousticTreatment, .referencePoint:
            return [.userReferencePoint]
        case .custom:
            return nil
        }
    }

    /// Whether a captured body/plane orientation may be attached to
    /// this type (#230, #244). Pure point authorities — listening
    /// positions and reference points — have no orientation semantics
    /// in v1.
    public var supportsOrientationAuthority: Bool {
        switch self {
        case .listeningPosition, .referencePoint:
            return false
        case .speaker, .subwoofer, .display, .projectionScreen,
             .projector, .seat, .acousticTreatment, .equipmentRack,
             .measurementPoint, .custom:
            return true
        }
    }
}

public enum AnnotationProvenanceClass: String, Codable, Sendable {
    case userAnnotation = "user_annotation"
    case importedReference = "imported_reference"
    case captureAppDerived = "capture_app_derived"
}

public enum AnnotationVerificationState: String, Codable, Sendable {
    case unverified
    case userAttested = "user_attested"
    case evidenceLinked = "evidence_linked"
}

public enum PlacementMethod: String, Codable, Sendable {
    case manualNumeric = "manual_numeric"
    case raycast
    case meshHitTest = "mesh_hit_test"
    case roomPlanBinding = "roomplan_binding"
    case importedReference = "imported_reference"
    case other
}

public struct ReferencePointSemantics: RawRepresentable, Codable, Hashable,
    Sendable, CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue == rawValue.lowercased(),
              rawValue.allSatisfy({
                  $0.isASCII
                      && ($0.isLetter || $0.isNumber || $0 == "_")
              })
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
                debugDescription: "Invalid reference-point semantics token"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let cabinetReferencePoint =
        Self(rawValue: "cabinet_reference_point")!
    public static let acousticCenter =
        Self(rawValue: "acoustic_center")!
    public static let earCenter =
        Self(rawValue: "ear_center")!
    public static let screenCenter =
        Self(rawValue: "screen_center")!
    public static let displayCenter =
        Self(rawValue: "display_center")!
    public static let seatReferencePoint =
        Self(rawValue: "seat_reference_point")!
    public static let userReferencePoint =
        Self(rawValue: "user_reference_point")!
    /// Projector body/cabinet reference point (#230). The projector
    /// type keeps the body point distinct from the optical/lens
    /// reference so downstream HTDT does not conflate mount placement
    /// with the lens position.
    public static let projectorBodyReference =
        Self(rawValue: "projector_body_reference")!
    public static let projectorLensCenter =
        Self(rawValue: "projector_lens_center")!
    public static let microphoneCapsule =
        Self(rawValue: "microphone_capsule")!

    /// The standard tokens defined by this contract version — the
    /// namespace-policy authority for #344.
    public static let standardSet: Set<String> = [
        "cabinet_reference_point", "acoustic_center", "ear_center",
        "screen_center", "display_center", "seat_reference_point",
        "user_reference_point", "projector_body_reference",
        "projector_lens_center", "microphone_capsule",
    ]
}

public struct HTDTEquipmentReference: Codable, Sendable, Equatable {
    public let equipmentID: String
    public let equipmentVersion: String
    public let equipmentHash: EvidenceSHA256
    /// Which equipment-catalog authority contract this tuple was
    /// selected under (#237). `nil` means a v1 bundle written before
    /// the versioned taxonomy existed and is interpreted as the
    /// acoustic-source catalog contract
    /// (`HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion`).
    public let authorityVersion: String?

    /// The catalog contract a legacy (unversioned) tuple resolves to.
    public static let legacyAuthorityVersion =
        HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion

    public init(
        equipmentID: String,
        equipmentVersion: String,
        equipmentHash: EvidenceSHA256,
        authorityVersion: String? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(equipmentID)
        let normalizedVersion = SchemaOwnedText.nfc(equipmentVersion)
        guard !normalizedID.isEmpty, !normalizedVersion.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        let normalizedAuthority = SchemaOwnedText.nfc(authorityVersion)
        guard !(normalizedAuthority?.isEmpty ?? false) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.equipmentID = normalizedID
        self.equipmentVersion = normalizedVersion
        self.equipmentHash = equipmentHash
        self.authorityVersion = normalizedAuthority
    }

    /// The effective catalog authority version for this reference.
    public var resolvedAuthorityVersion: String {
        authorityVersion ?? Self.legacyAuthorityVersion
    }

    private enum CodingKeys: String, CodingKey {
        case equipmentID = "equipment_id"
        case equipmentVersion = "equipment_version"
        case equipmentHash = "equipment_hash"
        case authorityVersion = "authority_version"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            equipmentID: container.decode(String.self, forKey: .equipmentID),
            equipmentVersion: container.decode(
                String.self,
                forKey: .equipmentVersion
            ),
            equipmentHash: container.decode(
                EvidenceSHA256.self,
                forKey: .equipmentHash
            ),
            authorityVersion: container.decodeIfPresent(
                String.self,
                forKey: .authorityVersion
            )
        )
    }
}

public enum AnnotationModelError: Error, Sendable, Equatable {
    case emptyLabel
    case emptyReferenceSemantics
    case invalidAxis
    case nonOrthogonalAxes
    case speakerOrientationRequired
    case speakerChannelRoleRequired
    case acousticCenterAuthorityRequired
    case emptyAuthorityReference
    case duplicateEntityID
    case duplicateEvidenceReference
    case invalidPlacementReference
    case missingEvidenceLink
    case invalidTimestamp
    case invalidEnvelope
    case invalidUncertainty
    case invalidReferencePointAuthority
    case invalidAuthorityComponent
    case incompatibleListeningRole
    case incompatibleEquipmentReference
    case unknownEquipmentAuthority
    case invalidReferencePointSemantics
    /// Lineage fields are contradictory or malformed (#303).
    case invalidEntityLineage
    /// An open-vocabulary token is neither standard nor custom-scoped
    /// (#344) — rejected on v1.1.0+ payloads.
    case unscopedCustomToken
    /// The document claims a schema_version this contract does not
    /// support (#332).
    case unsupportedSchemaVersion
    /// A semantic relation record violates the shared graph invariants
    /// (#333).
    case invalidSemanticRelation
}

public struct SpatialVector3F: Codable, Sendable, Equatable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) throws {
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw AnnotationModelError.invalidAxis
        }
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Float {
        sqrt(x * x + y * y + z * z)
    }

    public static func unit(
        _ x: Float,
        _ y: Float,
        _ z: Float
    ) throws -> SpatialVector3F {
        let value = try SpatialVector3F(x, y, z)
        guard abs(value.magnitude - 1) <= 0.001 else {
            throw AnnotationModelError.invalidAxis
        }
        return value
    }

    private enum CodingError: Error {
        case wrongElementCount
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Float] = []
        while !container.isAtEnd {
            values.append(try container.decode(Float.self))
        }
        guard values.count == 3 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected exactly three vector components"
            )
        }
        try self.init(values[0], values[1], values[2])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

public struct OrientationAxes: Codable, Sendable, Equatable {
    public let frontAxisLocal: SpatialVector3F
    public let upAxisLocal: SpatialVector3F

    public init(
        frontAxisLocal: SpatialVector3F,
        upAxisLocal: SpatialVector3F
    ) throws {
        guard abs(frontAxisLocal.magnitude - 1) <= 0.001,
              abs(upAxisLocal.magnitude - 1) <= 0.001
        else {
            throw AnnotationModelError.invalidAxis
        }
        let dot =
            frontAxisLocal.x * upAxisLocal.x
            + frontAxisLocal.y * upAxisLocal.y
            + frontAxisLocal.z * upAxisLocal.z
        guard abs(dot) <= 0.001 else {
            throw AnnotationModelError.nonOrthogonalAxes
        }
        self.frontAxisLocal = frontAxisLocal
        self.upAxisLocal = upAxisLocal
    }

    private enum CodingKeys: String, CodingKey {
        case frontAxisLocal = "front_axis_local"
        case upAxisLocal = "up_axis_local"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            frontAxisLocal: container.decode(
                SpatialVector3F.self,
                forKey: .frontAxisLocal
            ),
            upAxisLocal: container.decode(
                SpatialVector3F.self,
                forKey: .upAxisLocal
            )
        )
    }
}

public struct AcousticCenterOffsetAuthority: Codable, Sendable, Equatable {
    public let offsetLocalMeters: SpatialVector3F
    public let authorityRef: String

    public init(
        offsetLocalMeters: SpatialVector3F,
        authorityRef: String
    ) throws {
        let normalizedRef = SchemaOwnedText.nfc(authorityRef)
        guard !normalizedRef.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.offsetLocalMeters = offsetLocalMeters
        self.authorityRef = normalizedRef
    }

    private enum CodingKeys: String, CodingKey {
        case offsetLocalMeters = "offset_local_m"
        case authorityRef = "authority_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            offsetLocalMeters: container.decode(
                SpatialVector3F.self,
                forKey: .offsetLocalMeters
            ),
            authorityRef: container.decode(String.self, forKey: .authorityRef)
        )
    }
}

/// Bounded raycast hit provenance supplied by the platform/host when a
/// placement is produced by an AR raycast. Keeps the raycast target
/// classification and hit result so that, for example, an
/// `estimatedPlane` fallback remains distinguishable from a hit on
/// existing plane geometry after serialization.
public struct RaycastPlacementProvenance: Codable, Sendable, Equatable {
    /// Raycast target classification reported by the host
    /// (e.g. `"existing_plane_geometry"`, `"estimated_plane"`).
    public let targetType: String
    /// Distance from the ray origin to the hit, in meters.
    public let hitDistanceMeters: Double?
    /// Identifier of the anchor associated with the hit, when the host
    /// provided one.
    public let hitAnchorIdentifier: UUID?
    /// Final world transform of the hit result, when captured.
    public let hitTransform: Matrix4x4F?

    public init(
        targetType: String,
        hitDistanceMeters: Double? = nil,
        hitAnchorIdentifier: UUID? = nil,
        hitTransform: Matrix4x4F? = nil
    ) throws {
        let normalizedTarget = SchemaOwnedText.nfc(targetType)
        guard !normalizedTarget.isEmpty else {
            throw AnnotationModelError.invalidPlacementReference
        }
        if let hitDistanceMeters {
            guard hitDistanceMeters.isFinite, hitDistanceMeters >= 0
            else {
                throw AnnotationModelError.invalidPlacementReference
            }
        }
        self.targetType = normalizedTarget
        self.hitDistanceMeters = hitDistanceMeters
        self.hitAnchorIdentifier = hitAnchorIdentifier
        self.hitTransform = hitTransform
    }

    private enum CodingKeys: String, CodingKey {
        case targetType = "target_type"
        case hitDistanceMeters = "hit_distance_m"
        case hitAnchorIdentifier = "hit_anchor_id"
        case hitTransform = "T_world_from_hit"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetType: container.decode(String.self, forKey: .targetType),
            hitDistanceMeters: container.decodeIfPresent(
                Double.self,
                forKey: .hitDistanceMeters
            ),
            hitAnchorIdentifier: container.decodeIfPresent(
                UUID.self,
                forKey: .hitAnchorIdentifier
            ),
            hitTransform: container.decodeIfPresent(
                Matrix4x4F.self,
                forKey: .hitTransform
            )
        )
    }
}

public struct PlacementProvenance: Codable, Sendable, Equatable {
    public let method: PlacementMethod
    public let sourceSemanticEntityID: String?
    public let sourceMeshAnchorID: UUID?
    public let sourceRoomPlanObjectID: String?
    public let sourceEvidenceRefs: [String]
    public let raycast: RaycastPlacementProvenance?

    public init(
        method: PlacementMethod,
        sourceSemanticEntityID: String? = nil,
        sourceMeshAnchorID: UUID? = nil,
        sourceRoomPlanObjectID: String? = nil,
        sourceEvidenceRefs: [String] = [],
        raycast: RaycastPlacementProvenance? = nil
    ) throws {
        let normalizedEvidence = SchemaOwnedText.nfc(sourceEvidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        // Raycast hit provenance is only meaningful for the raycast
        // placement method.
        guard raycast == nil || method == .raycast else {
            throw AnnotationModelError.invalidPlacementReference
        }

        switch method {
        case .raycast, .meshHitTest:
            guard sourceMeshAnchorID != nil
                    || sourceSemanticEntityID != nil
                    || !normalizedEvidence.isEmpty
            else {
                throw AnnotationModelError.invalidPlacementReference
            }
        case .roomPlanBinding:
            guard sourceRoomPlanObjectID != nil
                    || sourceSemanticEntityID != nil
            else {
                throw AnnotationModelError.invalidPlacementReference
            }
        case .manualNumeric, .importedReference, .other:
            break
        }

        self.method = method
        self.sourceSemanticEntityID =
            SchemaOwnedText.nfc(sourceSemanticEntityID)
        self.sourceMeshAnchorID = sourceMeshAnchorID
        self.sourceRoomPlanObjectID =
            SchemaOwnedText.nfc(sourceRoomPlanObjectID)
        self.sourceEvidenceRefs = normalizedEvidence
        self.raycast = raycast
    }

    /// Whether the placement carries at least one source/evidence
    /// reference of an allowed kind.
    public var hasSourceReference: Bool {
        sourceSemanticEntityID != nil
            || sourceMeshAnchorID != nil
            || sourceRoomPlanObjectID != nil
            || !sourceEvidenceRefs.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case sourceSemanticEntityID = "source_semantic_entity_id"
        case sourceMeshAnchorID = "source_mesh_anchor_id"
        case sourceRoomPlanObjectID = "source_roomplan_object_id"
        case sourceEvidenceRefs = "source_evidence_refs"
        case raycast
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            method: container.decode(PlacementMethod.self, forKey: .method),
            sourceSemanticEntityID: container.decodeIfPresent(
                String.self,
                forKey: .sourceSemanticEntityID
            ),
            sourceMeshAnchorID: container.decodeIfPresent(
                UUID.self,
                forKey: .sourceMeshAnchorID
            ),
            sourceRoomPlanObjectID: container.decodeIfPresent(
                String.self,
                forKey: .sourceRoomPlanObjectID
            ),
            sourceEvidenceRefs: container.decode(
                [String].self,
                forKey: .sourceEvidenceRefs
            ),
            raycast: container.decodeIfPresent(
                RaycastPlacementProvenance.self,
                forKey: .raycast
            )
        )
    }
}

public struct ChannelRole: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue == rawValue.uppercased(),
              rawValue.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
              })
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
                debugDescription: "Invalid channel-role token"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let left = Self(rawValue: "L")!
    public static let center = Self(rawValue: "C")!
    public static let right = Self(rawValue: "R")!
    public static let surroundLeft = Self(rawValue: "SL")!
    public static let surroundRight = Self(rawValue: "SR")!
    public static let surroundBackLeft = Self(rawValue: "SBL")!
    public static let surroundBackRight = Self(rawValue: "SBR")!
    public static let lfe = Self(rawValue: "LFE")!
    public static let topFrontLeft = Self(rawValue: "TFL")!
    public static let topFrontRight = Self(rawValue: "TFR")!
    public static let topMiddleLeft = Self(rawValue: "TML")!
    public static let topMiddleRight = Self(rawValue: "TMR")!
    public static let topRearLeft = Self(rawValue: "TRL")!
    public static let topRearRight = Self(rawValue: "TRR")!
    /// Convenience tokens for multi-subwoofer topology (#244). The
    /// token set stays open — any `[A-Z0-9_]+` role is valid — so no
    /// particular AVR naming convention is baked into the schema.
    public static let lfe1 = Self(rawValue: "LFE1")!
    public static let lfe2 = Self(rawValue: "LFE2")!
    public static let lfe3 = Self(rawValue: "LFE3")!
    public static let lfe4 = Self(rawValue: "LFE4")!

    /// The standard tokens defined by this contract version — the
    /// namespace-policy authority for #344.
    public static let standardSet: Set<String> = [
        "L", "C", "R", "SL", "SR", "SBL", "SBR", "LFE",
        "TFL", "TFR", "TML", "TMR", "TRL", "TRR",
        "LFE1", "LFE2", "LFE3", "LFE4",
    ]
}

/// Typed listening-position role (#243). A `listening_position`
/// annotation's acoustic intent is machine-readable without parsing
/// the human label; a nil role on a stored entity means the record
/// predates role semantics (legacy/unknown).
public enum ListeningPositionRole:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Hashable
{
    /// The primary optimization/listening point (MLP).
    case primary
    /// Any additional listener position.
    case secondary
    /// A position captured only as a measurement reference.
    case measurementReference = "measurement_reference"
}

/// Where the numbers in `SpatialUncertaintyAuthority` come from
/// (#258). User/instrument-stated tolerances must remain distinct
/// from app-estimated quality; the app never fabricates a numeric
/// uncertainty from ARKit APIs.
public enum SpatialUncertaintyBasis: String, Codable, Sendable {
    case userStated = "user_stated"
    case instrumentStated = "instrument_stated"
    case appEstimated = "app_estimated"
    case other
}

/// Optional quantitative uncertainty for an annotation's spatial
/// authority (#258). Every component is independently optional; at
/// least one must be present. Absence is explicitly unknown, never
/// zero.
public struct SpatialUncertaintyAuthority: Codable, Sendable, Equatable {
    /// Isotropic position tolerance in meters.
    public let isotropicMeters: Double?
    /// Per-axis position uncertainty in meters.
    public let perAxisMeters: SpatialVector3F?
    /// Orientation/aim uncertainty in radians.
    public let angularRadians: Double?
    public let basis: SpatialUncertaintyBasis
    /// Evidence supporting the stated uncertainty (e.g. an instrument
    /// specification or a calibration record).
    public let sourceEvidenceRefs: [String]

    public init(
        isotropicMeters: Double? = nil,
        perAxisMeters: SpatialVector3F? = nil,
        angularRadians: Double? = nil,
        basis: SpatialUncertaintyBasis,
        sourceEvidenceRefs: [String] = []
    ) throws {
        guard isotropicMeters != nil || perAxisMeters != nil
                || angularRadians != nil
        else {
            throw AnnotationModelError.invalidUncertainty
        }
        if let value = isotropicMeters {
            guard value.isFinite, value >= 0 else {
                throw AnnotationModelError.invalidUncertainty
            }
        }
        if let value = angularRadians {
            guard value.isFinite, value >= 0 else {
                throw AnnotationModelError.invalidUncertainty
            }
        }
        if let perAxisMeters {
            for component in [perAxisMeters.x, perAxisMeters.y,
                              perAxisMeters.z] {
                guard component >= 0 else {
                    throw AnnotationModelError.invalidUncertainty
                }
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(sourceEvidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        self.isotropicMeters = isotropicMeters
        self.perAxisMeters = perAxisMeters
        self.angularRadians = angularRadians
        self.basis = basis
        self.sourceEvidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case isotropicMeters = "isotropic_m"
        case perAxisMeters = "per_axis_m"
        case angularRadians = "angular_rad"
        case basis
        case sourceEvidenceRefs = "source_evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isotropicMeters: container.decodeIfPresent(
                Double.self,
                forKey: .isotropicMeters
            ),
            perAxisMeters: container.decodeIfPresent(
                SpatialVector3F.self,
                forKey: .perAxisMeters
            ),
            angularRadians: container.decodeIfPresent(
                Double.self,
                forKey: .angularRadians
            ),
            basis: container.decode(
                SpatialUncertaintyBasis.self,
                forKey: .basis
            ),
            sourceEvidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .sourceEvidenceRefs
            ) ?? []
        )
    }
}

/// Provenance of an entity's physical envelope dimensions (#230).
/// Manually measured dimensions must stay distinct from
/// catalog-derived ones so a confident-looking size can never
/// silently pose as measured authority.
public enum EnvelopeProvenance: String, Codable, Sendable {
    case userMeasured = "user_measured"
    case equipmentCatalogDerived = "equipment_catalog_derived"
    case roomPlanDerived = "roomplan_derived"
    case importedReference = "imported_reference"
    case other
}

/// Bounded physical-envelope authority for an annotation (#230):
/// width/height/depth where applicable, each independently optional,
/// with explicit provenance. Never inferred by the app — only
/// operator-measured, catalog-derived, imported, or otherwise
/// sourced values are recorded.
public struct EntityPhysicalEnvelope: Codable, Sendable, Equatable {
    public let widthMeters: Double?
    public let heightMeters: Double?
    public let depthMeters: Double?
    public let provenance: EnvelopeProvenance
    public let sourceEvidenceRefs: [String]

    public init(
        widthMeters: Double? = nil,
        heightMeters: Double? = nil,
        depthMeters: Double? = nil,
        provenance: EnvelopeProvenance,
        sourceEvidenceRefs: [String] = []
    ) throws {
        guard widthMeters != nil || heightMeters != nil
                || depthMeters != nil
        else {
            throw AnnotationModelError.invalidEnvelope
        }
        for value in [widthMeters, heightMeters, depthMeters] {
            if let value {
                guard value.isFinite, value > 0 else {
                    throw AnnotationModelError.invalidEnvelope
                }
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(sourceEvidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.depthMeters = depthMeters
        self.provenance = provenance
        self.sourceEvidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case widthMeters = "width_m"
        case heightMeters = "height_m"
        case depthMeters = "depth_m"
        case provenance
        case sourceEvidenceRefs = "source_evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            widthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .widthMeters
            ),
            heightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .heightMeters
            ),
            depthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .depthMeters
            ),
            provenance: container.decode(
                EnvelopeProvenance.self,
                forKey: .provenance
            ),
            sourceEvidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .sourceEvidenceRefs
            ) ?? []
        )
    }
}

/// How the authored reference point was actually constructed (#291).
/// The contract distinguishes a surface hit that merely exists from a
/// semantic point the operator explicitly confirmed or constructed —
/// an `ear_center` cannot silently coincide with an arbitrary wall or
/// furniture hit.
public enum ReferencePointConstruction:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Hashable
{
    /// The entered/bound position IS the semantic point (manual
    /// numeric entry or a semantic-object binding).
    case directPlacement = "direct_placement"
    /// The operator explicitly confirms the surface hit is the
    /// claimed semantic point.
    case surfaceHitConfirmed = "surface_hit_confirmed"
    /// The semantic point was constructed from a surface hit plus an
    /// explicit offset (e.g. ear center above a seat hit).
    case offsetFromSurface = "offset_from_surface"
    /// The point arrives from an imported reference authority.
    case importedReference = "imported_reference"
}

/// Authority record for the entity's reference point (#291): how the
/// semantic point was constructed, the applied offset when derived
/// from a surface, and the evidence that supports the construction.
public struct ReferencePointAuthority: Codable, Sendable, Equatable {
    public let construction: ReferencePointConstruction
    /// World-frame offset applied to the source placement to obtain
    /// the semantic point. Required for `offset_from_surface`,
    /// meaningless (and rejected) otherwise.
    public let offsetMeters: SpatialVector3F?
    public let sourceEvidenceRefs: [String]

    public init(
        construction: ReferencePointConstruction,
        offsetMeters: SpatialVector3F? = nil,
        sourceEvidenceRefs: [String] = []
    ) throws {
        switch construction {
        case .offsetFromSurface:
            guard offsetMeters != nil else {
                throw AnnotationModelError.invalidReferencePointAuthority
            }
        case .directPlacement, .surfaceHitConfirmed,
             .importedReference:
            guard offsetMeters == nil else {
                throw AnnotationModelError.invalidReferencePointAuthority
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(sourceEvidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        self.construction = construction
        self.offsetMeters = offsetMeters
        self.sourceEvidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case construction
        case offsetMeters = "offset_m"
        case sourceEvidenceRefs = "source_evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            construction: container.decode(
                ReferencePointConstruction.self,
                forKey: .construction
            ),
            offsetMeters: container.decodeIfPresent(
                SpatialVector3F.self,
                forKey: .offsetMeters
            ),
            sourceEvidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .sourceEvidenceRefs
            ) ?? []
        )
    }
}

/// Verification state plus the exact evidence/source for one
/// component of an annotation's authority (#263).
public struct AnnotationComponentAuthority: Codable, Sendable, Equatable {
    public let state: AnnotationVerificationState
    public let evidenceRefs: [String]
    /// Optional reference to the authority source (e.g. an
    /// `equipment:<id>` or `measurement:<id>` style token).
    public let sourceRef: String?

    public init(
        state: AnnotationVerificationState,
        evidenceRefs: [String] = [],
        sourceRef: String? = nil
    ) throws {
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        let normalizedSource = SchemaOwnedText.nfc(sourceRef)
        guard !(normalizedSource?.isEmpty ?? false) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        // `evidence_linked` is a provenance claim: it requires at
        // least one evidence or source reference, matching the
        // entity-level rule.
        if state == .evidenceLinked {
            guard !normalizedEvidence.isEmpty
                    || normalizedSource != nil
            else {
                throw AnnotationModelError.missingEvidenceLink
            }
        }
        self.state = state
        self.evidenceRefs = normalizedEvidence
        self.sourceRef = normalizedSource
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case evidenceRefs = "evidence_refs"
        case sourceRef = "source_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            state: container.decode(
                AnnotationVerificationState.self,
                forKey: .state
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? [],
            sourceRef: container.decodeIfPresent(
                String.self,
                forKey: .sourceRef
            )
        )
    }
}

/// Per-component authority for an annotation (#263). The aggregate
/// `verification_state` stays as the legacy summary; this record says
/// which fields are actually evidence-backed so a mixed record can
/// never overstate itself. Components not listed carry the legacy
/// aggregate's claim.
public struct AnnotationAuthorityComponents:
    Codable,
    Sendable,
    Equatable
{
    /// Position/placement verification. Always present when the
    /// record exists — every entity has a placement method.
    public let placement: AnnotationComponentAuthority
    /// Present iff the entity carries an orientation.
    public let orientation: AnnotationComponentAuthority?
    /// Present iff the entity carries an equipment reference —
    /// captures how the entity/equipment match was verified.
    public let equipment: AnnotationComponentAuthority?
    /// Present iff the entity carries an explicit reference-point
    /// construction record.
    public let referencePoint: AnnotationComponentAuthority?
    /// Verification of semantic assignments (channel role, listening
    /// role, label attestation). Optional.
    public let semanticRole: AnnotationComponentAuthority?

    public init(
        placement: AnnotationComponentAuthority,
        orientation: AnnotationComponentAuthority? = nil,
        equipment: AnnotationComponentAuthority? = nil,
        referencePoint: AnnotationComponentAuthority? = nil,
        semanticRole: AnnotationComponentAuthority? = nil
    ) {
        self.placement = placement
        self.orientation = orientation
        self.equipment = equipment
        self.referencePoint = referencePoint
        self.semanticRole = semanticRole
    }

    /// Every component in field order.
    public var all: [AnnotationComponentAuthority] {
        [placement, orientation, equipment, referencePoint,
         semanticRole].compactMap { $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case orientation
        case equipment
        case referencePoint = "reference_point"
        case semanticRole = "semantic_role"
    }
}

/// Versioned lifecycle metadata for an annotation (#267): when the
/// entity was authored, last revised, and — when known — spatially
/// observed, plus supersedure. All timestamps are canonical UTC
/// RFC3339 text (`SchemaTimestampText`); nothing is fabricated for
/// imported or legacy records.
public struct AnnotationLifecycle: Codable, Sendable, Equatable {
    /// When this entity record was authored locally.
    public let createdAtUTC: String
    /// When this entity was last revised, if ever.
    public let updatedAtUTC: String?
    /// When the spatial authority was observed, when known (e.g. the
    /// capture time of an evidence-linked raycast).
    public let observedAtUTC: String?
    /// The source record's own creation time for imported records —
    /// distinguishable from the local import/edit time.
    public let sourceCreatedAtUTC: String?
    /// The entity this record supersedes, when a correction replaces
    /// an earlier record rather than editing it in place.
    public let supersedesEntityID: AnnotationEntityID?

    public init(
        createdAtUTC: String,
        updatedAtUTC: String? = nil,
        observedAtUTC: String? = nil,
        sourceCreatedAtUTC: String? = nil,
        supersedesEntityID: AnnotationEntityID? = nil
    ) throws {
        for value in [createdAtUTC, updatedAtUTC, observedAtUTC,
                      sourceCreatedAtUTC].compactMap({ $0 }) {
            guard SchemaTimestampText.isUTCTimestamp(value) else {
                throw AnnotationModelError.invalidTimestamp
            }
        }
        self.createdAtUTC = SchemaOwnedText.nfc(createdAtUTC)
        self.updatedAtUTC = SchemaOwnedText.nfc(updatedAtUTC)
        self.observedAtUTC = SchemaOwnedText.nfc(observedAtUTC)
        self.sourceCreatedAtUTC = SchemaOwnedText.nfc(sourceCreatedAtUTC)
        self.supersedesEntityID = supersedesEntityID
    }

    /// A copy with `updated_at_utc` set — used when a pre-finalization
    /// correction revises the same conceptual entity.
    public func revised(at updatedAtUTC: String) throws
        -> AnnotationLifecycle
    {
        try AnnotationLifecycle(
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            observedAtUTC: observedAtUTC,
            sourceCreatedAtUTC: sourceCreatedAtUTC,
            supersedesEntityID: supersedesEntityID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case createdAtUTC = "created_at_utc"
        case updatedAtUTC = "updated_at_utc"
        case observedAtUTC = "observed_at_utc"
        case sourceCreatedAtUTC = "source_created_at_utc"
        case supersedesEntityID = "supersedes_entity_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            createdAtUTC: container.decode(
                String.self,
                forKey: .createdAtUTC
            ),
            updatedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .updatedAtUTC
            ),
            observedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .observedAtUTC
            ),
            sourceCreatedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .sourceCreatedAtUTC
            ),
            supersedesEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .supersedesEntityID
            )
        )
    }
}

/// A pointer to an entity record committed in an earlier capture
/// revision of the same capture series (#303). Cross-revision lineage
/// never inlines the parent's pose or evidence — it is identity
/// linkage only.
public struct EntityLineageReference: Codable, Sendable, Equatable {
    public let captureRevisionID: CaptureRevisionID
    public let entityID: AnnotationEntityID

    public init(
        captureRevisionID: CaptureRevisionID,
        entityID: AnnotationEntityID
    ) {
        self.captureRevisionID = captureRevisionID
        self.entityID = entityID
    }

    private enum CodingKeys: String, CodingKey {
        case captureRevisionID = "capture_revision_id"
        case entityID = "entity_id"
    }
}

/// How this entity record relates to the parent revision's record
/// (#303).
public enum EntityLineageRelation: String, Codable, Sendable {
    /// The same physical object re-observed — e.g. the same loudspeaker
    /// re-measured in a later revision.
    case samePhysicalEntity = "same_physical_entity"
    /// A different physical object replaced the parent's (equipment
    /// swap) — the new record deliberately carries a distinct physical
    /// identity.
    case replacedEntity = "replaced_entity"
    /// A new entity with no parent-revision counterpart.
    case newEntity = "new_entity"
    /// Linkage was requested but the original correspondence cannot be
    /// proven — legacy revisions decode here.
    case relationUnknown = "relation_unknown"
}

/// Cross-revision entity lineage (#303). Every record is revision-
/// local; `lineage` links it back to the record it carries forward
/// without copying pose or evidence from the parent revision.
public struct AnnotationEntityLineage: Codable, Sendable, Equatable {
    /// Optional stable physical-identity token scoped to the capture
    /// series — two records sharing a `stable_entity_id` claim the
    /// same physical object across revisions. Not an `entity_id`:
    /// `entity_id` is always revision-local.
    public let stableEntityID: String?
    /// The relation claim. `same_physical_entity` and
    /// `replaced_entity` require `parent_entity_ref`; `new_entity` and
    /// `relation_unknown` forbid it.
    public let relation: EntityLineageRelation
    /// The parent revision's record this one supersedes or continues,
    /// as required by `relation`.
    public let parentEntityRef: EntityLineageReference?

    public init(
        stableEntityID: String? = nil,
        relation: EntityLineageRelation,
        parentEntityRef: EntityLineageReference? = nil
    ) throws {
        let normalized = SchemaOwnedText.nfc(stableEntityID)
        if let normalized {
            guard !normalized.isEmpty else {
                throw AnnotationModelError.invalidEntityLineage
            }
        }
        switch relation {
        case .samePhysicalEntity, .replacedEntity:
            guard parentEntityRef != nil else {
                throw AnnotationModelError.invalidEntityLineage
            }
        case .newEntity, .relationUnknown:
            guard parentEntityRef == nil else {
                throw AnnotationModelError.invalidEntityLineage
            }
        }
        self.stableEntityID = normalized
        self.relation = relation
        self.parentEntityRef = parentEntityRef
    }

    private enum CodingKeys: String, CodingKey {
        case stableEntityID = "stable_entity_id"
        case relation
        case parentEntityRef = "parent_entity_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            stableEntityID: container.decodeIfPresent(
                String.self,
                forKey: .stableEntityID
            ),
            relation: container.decode(
                EntityLineageRelation.self,
                forKey: .relation
            ),
            parentEntityRef: container.decodeIfPresent(
                EntityLineageReference.self,
                forKey: .parentEntityRef
            )
        )
    }
}

/// How an entity's `equipment_ref` relates to the annotation type
/// (#237). The check is driven by the versioned catalog taxonomy, not
/// by label text.
public enum EquipmentReferenceCompatibility: String, Sendable,
    Equatable
{
    /// No `equipment_ref` is attached.
    case noReference = "no_reference"
    /// The annotation type may carry a reference under the
    /// reference's catalog authority version.
    case compatible
    /// The catalog authority version is not in the known taxonomy —
    /// compatibility cannot be proven either way.
    case unknownAuthorityVersion = "unknown_authority_version"
    /// The annotation type may not carry this catalog's references.
    case incompatible
}

public struct CaptureAnnotationEntity: Codable, Sendable, Equatable {
    public let entityID: AnnotationEntityID
    public let type: AnnotationEntityType
    public let coordinateSpaceID: CoordinateSpaceID
    public let worldFromAnnotation: Matrix4x4F
    public let referencePointSemantics: ReferencePointSemantics
    public let label: String
    public let provenanceClass: AnnotationProvenanceClass
    public let verificationState: AnnotationVerificationState
    public let placement: PlacementProvenance
    public let orientation: OrientationAxes?
    public let channelRole: ChannelRole?
    public let acousticCenter: AcousticCenterOffsetAuthority?
    public let equipmentRef: HTDTEquipmentReference?
    public let evidenceRefs: [String]
    /// Physical envelope authority (#230); nil for point-only records.
    public let physicalEnvelope: EntityPhysicalEnvelope?
    /// Typed listening-position role (#243); only meaningful on
    /// `listening_position`. Nil on a stored entity = legacy/unknown.
    public let listeningRole: ListeningPositionRole?
    /// Optional quantitative uncertainty authority (#258).
    public let uncertainty: SpatialUncertaintyAuthority?
    /// Per-component verification detail (#263); nil on v1 records
    /// written before component authority existed.
    public let authority: AnnotationAuthorityComponents?
    /// Creation/revision lifecycle metadata (#267).
    public let lifecycle: AnnotationLifecycle?
    /// How the reference point itself was authored/confirmed (#291).
    public let referencePoint: ReferencePointAuthority?
    /// Optional cross-revision identity/lineage linkage (#303). Nil on
    /// legacy records means the lineage was never asserted — consumers
    /// read it as `relation_unknown`, never as `same_physical_entity`.
    public let lineage: AnnotationEntityLineage?
    /// Optional app-local author/operator binding (issue #310):
    /// `operator_id` from `derived/operator-profiles.json`. Optional
    /// and explicit — anonymous records remain valid.
    public let authorOperatorID: OperatorProfileID?

    public init(
        entityID: AnnotationEntityID = AnnotationEntityID(),
        type: AnnotationEntityType,
        coordinateSpaceID: CoordinateSpaceID,
        worldFromAnnotation: Matrix4x4F,
        referencePointSemantics: ReferencePointSemantics,
        label: String,
        provenanceClass: AnnotationProvenanceClass = .userAnnotation,
        verificationState: AnnotationVerificationState = .unverified,
        placement: PlacementProvenance,
        orientation: OrientationAxes? = nil,
        channelRole: ChannelRole? = nil,
        acousticCenter: AcousticCenterOffsetAuthority? = nil,
        equipmentRef: HTDTEquipmentReference? = nil,
        evidenceRefs: [String] = [],
        physicalEnvelope: EntityPhysicalEnvelope? = nil,
        listeningRole: ListeningPositionRole? = nil,
        uncertainty: SpatialUncertaintyAuthority? = nil,
        authority: AnnotationAuthorityComponents? = nil,
        lifecycle: AnnotationLifecycle? = nil,
        referencePoint: ReferencePointAuthority? = nil,
        lineage: AnnotationEntityLineage? = nil,
        authorOperatorID: OperatorProfileID? = nil
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)
        guard !normalizedLabel.isEmpty else {
            throw AnnotationModelError.emptyLabel
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }

        if type == .speaker {
            guard orientation != nil else {
                throw AnnotationModelError.speakerOrientationRequired
            }
            guard channelRole != nil else {
                throw AnnotationModelError.speakerChannelRoleRequired
            }
        }

        // `listening_role` is typed authority for listening positions
        // only (#243); on any other type it is a contradiction.
        guard listeningRole == nil || type == .listeningPosition else {
            throw AnnotationModelError.incompatibleListeningRole
        }

        // A reference-point construction record must be coherent with
        // the placement method that produced the position (#291): a
        // surface-derived placement may only carry surface-aware
        // constructions, and `direct_placement` never applies to a
        // surface hit.
        if let referencePoint {
            let surfaceDerived =
                placement.method == .raycast
                    || placement.method == .meshHitTest
            switch referencePoint.construction {
            case .surfaceHitConfirmed, .offsetFromSurface:
                guard surfaceDerived else {
                    throw AnnotationModelError
                        .invalidReferencePointAuthority
                }
            case .directPlacement:
                guard !surfaceDerived else {
                    throw AnnotationModelError
                        .invalidReferencePointAuthority
                }
            case .importedReference:
                break
            }
        }

        // When a component-authority record exists it must describe
        // the fields actually present: a component is required exactly
        // when the corresponding field carries authority (#263).
        if let authority {
            guard (authority.orientation != nil) == (orientation != nil),
                  (authority.equipment != nil) == (equipmentRef != nil),
                  (authority.referencePoint != nil)
                        == (referencePoint != nil),
                  (authority.semanticRole != nil)
                        == (channelRole != nil || listeningRole != nil)
            else {
                throw AnnotationModelError.invalidAuthorityComponent
            }
        }

        // `evidence_linked` is a provenance claim: it requires at least
        // one evidence or placement source reference.
        if verificationState == .evidenceLinked {
            guard !normalizedEvidence.isEmpty
                    || placement.hasSourceReference
            else {
                throw AnnotationModelError.missingEvidenceLink
            }
        }

        self.entityID = entityID
        self.type = type
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromAnnotation = worldFromAnnotation
        self.referencePointSemantics = referencePointSemantics
        self.label = normalizedLabel
        self.provenanceClass = provenanceClass
        self.verificationState = verificationState
        self.placement = placement
        self.orientation = orientation
        self.channelRole = channelRole
        self.acousticCenter = acousticCenter
        self.equipmentRef = equipmentRef
        self.evidenceRefs = normalizedEvidence
        self.physicalEnvelope = physicalEnvelope
        self.listeningRole = listeningRole
        self.uncertainty = uncertainty
        self.authority = authority
        self.lifecycle = lifecycle
        self.referencePoint = referencePoint
        self.lineage = lineage
        self.authorOperatorID = authorOperatorID
    }

    /// A copy of this entity with `author_operator_id` set to
    /// `operatorID` — the workspace stamps the selected operator
    /// profile onto newly authored records (issue #310).
    public func withAuthorOperator(
        _ operatorID: OperatorProfileID?
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            entityID: entityID,
            type: type,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnnotation: worldFromAnnotation,
            referencePointSemantics: referencePointSemantics,
            label: label,
            provenanceClass: provenanceClass,
            verificationState: verificationState,
            placement: placement,
            orientation: orientation,
            channelRole: channelRole,
            acousticCenter: acousticCenter,
            equipmentRef: equipmentRef,
            evidenceRefs: evidenceRefs,
            physicalEnvelope: physicalEnvelope,
            listeningRole: listeningRole,
            uncertainty: uncertainty,
            authority: authority,
            lifecycle: lifecycle,
            referencePoint: referencePoint,
            authorOperatorID: operatorID
        )
    }

    /// Compatibility between this entity's `equipment_ref` and its
    /// annotation type under the reference's catalog authority
    /// version (#237). Legacy records carrying an incompatible tuple
    /// remain readable; the mismatch is surfaced here and in
    /// `AnnotationContractReview` rather than silently ignored.
    public var equipmentCompatibility: EquipmentReferenceCompatibility {
        guard let equipmentRef else {
            return .noReference
        }
        return HTDTEquipmentCompatibility.check(
            reference: equipmentRef,
            entityType: type
        )
    }

    /// Every spatial authority claim introduced by the v1.1 contract
    /// fields, for coordinate-space congruence checks: component
    /// evidence, reference-point construction sources, envelope and
    /// uncertainty sources.
    public var contractEvidenceRefs: [String] {
        var refs = authority?.all.flatMap(\.evidenceRefs) ?? []
        refs.append(
            contentsOf: referencePoint?.sourceEvidenceRefs ?? []
        )
        refs.append(
            contentsOf: physicalEnvelope?.sourceEvidenceRefs ?? []
        )
        refs.append(
            contentsOf: uncertainty?.sourceEvidenceRefs ?? []
        )
        return refs
    }

    /// A copy of this entity with `updated_at_utc` stamped into its
    /// lifecycle — a revision of the same conceptual entity keeps its
    /// `entity_id` and creation time (#267).
    public func revised(at updatedAtUTC: String) throws
        -> CaptureAnnotationEntity
    {
        let base = try lifecycle
            ?? AnnotationLifecycle(createdAtUTC: updatedAtUTC)
        return try CaptureAnnotationEntity(
            entityID: entityID,
            type: type,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnnotation: worldFromAnnotation,
            referencePointSemantics: referencePointSemantics,
            label: label,
            provenanceClass: provenanceClass,
            verificationState: verificationState,
            placement: placement,
            orientation: orientation,
            channelRole: channelRole,
            acousticCenter: acousticCenter,
            equipmentRef: equipmentRef,
            evidenceRefs: evidenceRefs,
            physicalEnvelope: physicalEnvelope,
            listeningRole: listeningRole,
            uncertainty: uncertainty,
            authority: authority,
            lifecycle: base.revised(at: updatedAtUTC),
            referencePoint: referencePoint,
            lineage: lineage,
            authorOperatorID: authorOperatorID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case type
        case coordinateSpaceID = "coordinate_space_id"
        case worldFromAnnotation = "T_world_from_annotation"
        case referencePointSemantics = "reference_point_semantics"
        case label
        case provenanceClass = "provenance_class"
        case verificationState = "verification_state"
        case placement
        case orientation
        case channelRole = "channel_role"
        case acousticCenter = "acoustic_center"
        case equipmentRef = "equipment_ref"
        case evidenceRefs = "evidence_refs"
        case physicalEnvelope = "physical_envelope"
        case listeningRole = "listening_role"
        case uncertainty
        case authority
        case lifecycle
        case referencePoint = "reference_point"
        case lineage
        case authorOperatorID = "author_operator_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            entityID: container.decode(
                AnnotationEntityID.self,
                forKey: .entityID
            ),
            type: container.decode(
                AnnotationEntityType.self,
                forKey: .type
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            worldFromAnnotation: container.decode(
                Matrix4x4F.self,
                forKey: .worldFromAnnotation
            ),
            referencePointSemantics: container.decode(
                ReferencePointSemantics.self,
                forKey: .referencePointSemantics
            ),
            label: container.decode(String.self, forKey: .label),
            provenanceClass: container.decode(
                AnnotationProvenanceClass.self,
                forKey: .provenanceClass
            ),
            verificationState: container.decode(
                AnnotationVerificationState.self,
                forKey: .verificationState
            ),
            placement: container.decode(
                PlacementProvenance.self,
                forKey: .placement
            ),
            orientation: container.decodeIfPresent(
                OrientationAxes.self,
                forKey: .orientation
            ),
            channelRole: container.decodeIfPresent(
                ChannelRole.self,
                forKey: .channelRole
            ),
            acousticCenter: container.decodeIfPresent(
                AcousticCenterOffsetAuthority.self,
                forKey: .acousticCenter
            ),
            equipmentRef: container.decodeIfPresent(
                HTDTEquipmentReference.self,
                forKey: .equipmentRef
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            ),
            physicalEnvelope: container.decodeIfPresent(
                EntityPhysicalEnvelope.self,
                forKey: .physicalEnvelope
            ),
            listeningRole: container.decodeIfPresent(
                ListeningPositionRole.self,
                forKey: .listeningRole
            ),
            uncertainty: container.decodeIfPresent(
                SpatialUncertaintyAuthority.self,
                forKey: .uncertainty
            ),
            authority: container.decodeIfPresent(
                AnnotationAuthorityComponents.self,
                forKey: .authority
            ),
            lifecycle: container.decodeIfPresent(
                AnnotationLifecycle.self,
                forKey: .lifecycle
            ),
            referencePoint: container.decodeIfPresent(
                ReferencePointAuthority.self,
                forKey: .referencePoint
            ),
            lineage: container.decodeIfPresent(
                AnnotationEntityLineage.self,
                forKey: .lineage
            ),
            authorOperatorID: container.decodeIfPresent(
                OperatorProfileID.self,
                forKey: .authorOperatorID
            )
        )
    }
}

/// A semantic contract problem on a stored annotation, surfaced for
/// reconciliation in Review and available to downstream ingestion
/// (#237, #243, #244, #291). Findings never mutate or block the
/// record — legacy bundles stay readable — but a mismatch is never
/// silently ignored.
public struct AnnotationContractFinding:
    Sendable,
    Equatable,
    Hashable
{
    public enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    public enum Code: String, Sendable {
        /// `equipment_ref` cannot be carried by this annotation type
        /// under its catalog authority version (#237).
        case incompatibleEquipmentReference =
            "incompatible_equipment_reference"
        /// The `equipment_ref` claims a catalog authority version the
        /// taxonomy does not know (#237).
        case unknownEquipmentAuthority =
            "unknown_equipment_authority"
        /// More than one `listening_position` claims `primary`
        /// (#243).
        case duplicatePrimaryListeningPosition =
            "duplicate_primary_listening_position"
        /// A `listening_position` carries no typed role — the record
        /// is readable but its acoustic intent is label-derived only
        /// (#243).
        case listeningRoleMissing = "listening_role_missing"
        /// Two entities of the same type claim the same channel role
        /// (#244).
        case duplicateChannelRole = "duplicate_channel_role"
        /// A surface-derived placement has no explicit reference-point
        /// construction record, so the semantic point cannot be proven
        /// (#291). Expected on records written before the field
        /// existed — surfaces as a warning.
        case unverifiedReferencePointSemantics =
            "unverified_reference_point_semantics"
        /// An open-vocabulary token is neither standard nor
        /// custom-scoped — a custom token authored before the #344
        /// namespace policy whose original meaning cannot be proven
        /// from the pinned vocabulary. Never an error: the record is
        /// readable; the token can never silently become standard.
        case legacyCustomUnscopedToken = "legacy_custom_unscoped"
    }

    public let entityID: AnnotationEntityID
    public let code: Code
    public let severity: Severity
    public let detail: String

    public init(
        entityID: AnnotationEntityID,
        code: Code,
        severity: Severity,
        detail: String
    ) {
        self.entityID = entityID
        self.code = code
        self.severity = severity
        self.detail = detail
    }
}

/// Cross-entity semantic checks over a committed (or staged)
/// annotation collection.
public enum AnnotationContractReview {
    public static func findings(
        in entities: [CaptureAnnotationEntity]
    ) -> [AnnotationContractFinding] {
        var findings: [AnnotationContractFinding] = []
        var primaries = 0
        var rolesByTypeAndRole:
            [String: [CaptureAnnotationEntity]] = [:]

        for entity in entities {
            switch entity.equipmentCompatibility {
            case .noReference, .compatible:
                break
            case .unknownAuthorityVersion:
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .unknownEquipmentAuthority,
                        severity: .warning,
                        detail: "equipment_ref authority version "
                            + (entity.equipmentRef?.authorityVersion
                                ?? "legacy")
                            + " is not in the known catalog taxonomy"
                    )
                )
            case .incompatible:
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .incompatibleEquipmentReference,
                        severity: .error,
                        detail: entity.type.rawValue
                            + " cannot carry an equipment reference "
                            + "from this catalog contract"
                    )
                )
            }

            if entity.type == .listeningPosition {
                switch entity.listeningRole {
                case .primary:
                    primaries += 1
                    if primaries > 1 {
                        findings.append(
                            AnnotationContractFinding(
                                entityID: entity.entityID,
                                code:
                                    .duplicatePrimaryListeningPosition,
                                severity: .warning,
                                detail:
                                    "multiple listening positions "
                                    + "claim the primary role"
                            )
                        )
                    }
                case .secondary, .measurementReference:
                    break
                case nil:
                    findings.append(
                        AnnotationContractFinding(
                            entityID: entity.entityID,
                            code: .listeningRoleMissing,
                            severity: .info,
                            detail:
                                "listening position has no typed role; "
                                + "label only"
                        )
                    )
                }
            }

            if let role = entity.channelRole {
                let key =
                    entity.type.rawValue + "\u{0}" + role.rawValue
                rolesByTypeAndRole[key, default: []].append(entity)
            }

            // #344 namespace policy: an unscoped token that is not in
            // the pinned standard vocabulary is a legacy custom — it
            // remains readable but can never be interpreted as a
            // standard token.
            if let role = entity.channelRole,
               OpenTokenPolicy.classify(
                   role.rawValue,
                   vocabulary: .channelRole
               ) == .legacyCustomUnscoped
            {
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .legacyCustomUnscopedToken,
                        severity: .info,
                        detail: "channel_role \(role.rawValue) is an "
                            + "unscoped custom token; meaning is "
                            + "deployment-defined"
                    )
                )
            }
            if OpenTokenPolicy.classify(
                entity.referencePointSemantics.rawValue,
                vocabulary: .referencePointSemantics
            ) == .legacyCustomUnscoped {
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .legacyCustomUnscopedToken,
                        severity: .info,
                        detail: "reference_point_semantics "
                            + entity.referencePointSemantics.rawValue
                            + " is an unscoped custom token; meaning "
                            + "is deployment-defined"
                    )
                )
            }

            // A surface-derived placement without a construction
            // record means the semantic reference point was never
            // explicitly confirmed (#291).
            if entity.referencePoint == nil,
               entity.placement.method == .raycast
                   || entity.placement.method == .meshHitTest
            {
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .unverifiedReferencePointSemantics,
                        severity: .warning,
                        detail: placementMethodText(entity)
                            + " placement has no explicit "
                            + "reference-point construction"
                    )
                )
            }
        }

        for (_, grouped) in rolesByTypeAndRole
            where grouped.count > 1
        {
            let role = grouped[0].channelRole!.rawValue
            let type = grouped[0].type.rawValue
            for entity in grouped {
                findings.append(
                    AnnotationContractFinding(
                        entityID: entity.entityID,
                        code: .duplicateChannelRole,
                        severity: .warning,
                        detail: "duplicate " + type
                            + " channel role " + role
                    )
                )
            }
        }

        return findings.sorted {
            ($0.severity.rawValue, $0.code.rawValue,
             $0.entityID.rawValue.uuidString)
                < ($1.severity.rawValue, $1.code.rawValue,
                   $1.entityID.rawValue.uuidString)
        }
    }

    private static func placementMethodText(
        _ entity: CaptureAnnotationEntity
    ) -> String {
        entity.placement.method.rawValue
    }
}

public struct CaptureAnnotationCollection: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.entities"
    /// The payload version this build emits (#332). v1.1.0 adds the
    /// shared typed relation graph (#333), entity lineage (#303), and
    /// the open-token namespace policy (#344).
    public static let expectedSchemaVersion = "1.1.0"
    /// Every payload version this build can decode (#332): 1.0.0
    /// records are legacy — lineage is unknown and unscoped tokens
    /// classify `legacy_custom_unscoped`.
    public static let supportedSchemaVersions: [String] = [
        "1.0.0", "1.1.0",
    ]

    public let schema: String
    public let schemaVersion: String
    public let entities: [CaptureAnnotationEntity]
    /// Typed semantic relations between entities in this revision
    /// (#333). Always emitted on v1.1.0 (possibly empty); absent on
    /// v1.0.0 payloads.
    public let relations: [CaptureSemanticRelation]

    public init(
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation] = []
    ) throws {
        try self.init(
            entities: entities,
            relations: relations,
            declaredSchemaVersion: Self.expectedSchemaVersion
        )
    }

    /// Validates a collection under the contract pinned to
    /// `declaredSchemaVersion`: the open-token namespace policy applies
    /// to every version after 1.0.0; v1.0.0 payloads keep legacy
    /// unscoped tokens readable.
    init(
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation],
        declaredSchemaVersion: String
    ) throws {
        let ids = entities.map(\.entityID)
        guard Set(ids).count == ids.count else {
            throw AnnotationModelError.duplicateEntityID
        }
        try Self.validateRelationGraph(
            entities: entities,
            relations: relations
        )
        if declaredSchemaVersion != "1.0.0" {
            try Self.validateTokenNamespaces(
                entities: entities,
                relations: relations
            )
        }
        self.schema = Self.expectedSchema
        self.schemaVersion = declaredSchemaVersion
        self.entities = entities
        self.relations = relations
    }

    /// Semantic contract findings across the committed collection —
    /// duplicate roles, incompatible equipment references, unproven
    /// reference-point semantics, unscoped legacy tokens
    /// (#237, #243, #244, #291, #344).
    public func contractFindings() -> [AnnotationContractFinding] {
        AnnotationContractReview.findings(in: entities)
    }

    /// Relations whose subject or object endpoint references
    /// `entityID` — surfaced before deleting or editing a staged
    /// entity so dependent relations are never silently orphaned
    /// (#333).
    public func relationsTouching(
        entityID: AnnotationEntityID
    ) -> [CaptureSemanticRelation] {
        relations.filter { $0.references(entityID: entityID) }
    }

    /// Open-token namespace policy (#344): standard tokens or
    /// custom-scoped tokens only. Unscoped non-standard tokens are
    /// legacy and never appear on wire-legal v1.1.0 payloads.
    private static func validateTokenNamespaces(
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation]
    ) throws {
        for entity in entities {
            if let role = entity.channelRole,
               !OpenTokenPolicy.isWireLegal(
                   role.rawValue,
                   vocabulary: .channelRole
               )
            {
                throw AnnotationModelError.unscopedCustomToken
            }
            if !OpenTokenPolicy.isWireLegal(
                entity.referencePointSemantics.rawValue,
                vocabulary: .referencePointSemantics
            ) {
                throw AnnotationModelError.unscopedCustomToken
            }
        }
        for relation in relations
        where !OpenTokenPolicy.isWireLegal(
            relation.relationType.rawValue,
            vocabulary: .relationType
        ) {
            throw AnnotationModelError.unscopedCustomToken
        }
    }

    /// Shared relation-graph invariants (#333): unique ids, no
    /// duplicate (type, subject, object) tuples, entity endpoints
    /// resolve inside the same revision, external endpoints are
    /// explicitly namespaced, and the endpoint-type policy holds.
    private static func validateRelationGraph(
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation]
    ) throws {
        let entityTypes = Dictionary(
            uniqueKeysWithValues: entities.map {
                ($0.entityID, $0.type)
            }
        )
        var seenIDs = Set<SemanticRelationID>()
        var seenTuples = Set<String>()
        for relation in relations {
            guard seenIDs.insert(relation.relationID).inserted else {
                throw SemanticRelationGraphError.duplicateRelationID
            }
            let endpoints = [relation.subjectRef]
                + relation.objectRefs
            for endpoint in endpoints {
                if let entityID = endpoint.entityID {
                    guard entityTypes[entityID] != nil else {
                        throw SemanticRelationGraphError
                            .danglingEntityReference
                    }
                } else if endpoint.externalRef == nil {
                    throw SemanticRelationGraphError.danglingEntityReference
                }
            }
            let subjectType = relation.subjectRef.entityID
                .flatMap { entityTypes[$0] }
            for objectRef in relation.objectRefs {
                let objectType = objectRef.entityID
                    .flatMap { entityTypes[$0] }
                guard SemanticRelationPolicy.allows(
                    relation.relationType,
                    subjectType: subjectType,
                    objectType: objectType
                )
                else {
                    throw SemanticRelationGraphError
                        .disallowedEndpointCombination
                }
                let tuple = relation.relationType.rawValue
                    + "\u{0}" + relation.subjectRef.rawValue
                    + "\u{0}" + objectRef.rawValue
                guard seenTuples.insert(tuple).inserted else {
                    throw SemanticRelationGraphError.duplicateRelation
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case entities
        case relations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported annotation collection schema"
            )
        }
        guard Self.supportedSchemaVersions.contains(schemaVersion)
        else {
            throw AnnotationModelError.unsupportedSchemaVersion
        }
        try self.init(
            entities: container.decode(
                [CaptureAnnotationEntity].self,
                forKey: .entities
            ),
            relations: container.decodeIfPresent(
                [CaptureSemanticRelation].self,
                forKey: .relations
            ) ?? [],
            declaredSchemaVersion: schemaVersion
        )
    }
}
