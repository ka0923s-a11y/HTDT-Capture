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
    case listeningPosition = "listening_position"
    case seat
    case acousticTreatment = "acoustic_treatment"
    case equipmentRack = "equipment_rack"
    case referencePoint = "reference_point"
    case custom
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
}

public struct HTDTEquipmentReference: Codable, Sendable, Equatable {
    public let equipmentID: String
    public let equipmentVersion: String
    public let equipmentHash: EvidenceSHA256

    public init(
        equipmentID: String,
        equipmentVersion: String,
        equipmentHash: EvidenceSHA256
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(equipmentID)
        let normalizedVersion = SchemaOwnedText.nfc(equipmentVersion)
        guard !normalizedID.isEmpty, !normalizedVersion.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.equipmentID = normalizedID
        self.equipmentVersion = normalizedVersion
        self.equipmentHash = equipmentHash
    }

    private enum CodingKeys: String, CodingKey {
        case equipmentID = "equipment_id"
        case equipmentVersion = "equipment_version"
        case equipmentHash = "equipment_hash"
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
        evidenceRefs: [String] = []
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
            )
        )
    }
}

public struct CaptureAnnotationCollection: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.entities"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let entities: [CaptureAnnotationEntity]

    public init(entities: [CaptureAnnotationEntity]) throws {
        let ids = entities.map(\.entityID)
        guard Set(ids).count == ids.count else {
            throw AnnotationModelError.duplicateEntityID
        }
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.entities = entities
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case entities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported annotation collection schema"
            )
        }
        try self.init(
            entities: container.decode(
                [CaptureAnnotationEntity].self,
                forKey: .entities
            )
        )
    }
}
