import Foundation

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
        guard !equipmentID.isEmpty, !equipmentVersion.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.equipmentID = equipmentID
        self.equipmentVersion = equipmentVersion
        self.equipmentHash = equipmentHash
    }

    private enum CodingKeys: String, CodingKey {
        case equipmentID = "equipment_id"
        case equipmentVersion = "equipment_version"
        case equipmentHash = "equipment_hash"
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
}

public struct AcousticCenterOffsetAuthority: Codable, Sendable, Equatable {
    public let offsetLocalMeters: SpatialVector3F
    public let authorityRef: String

    public init(
        offsetLocalMeters: SpatialVector3F,
        authorityRef: String
    ) throws {
        guard !authorityRef.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.offsetLocalMeters = offsetLocalMeters
        self.authorityRef = authorityRef
    }

    private enum CodingKeys: String, CodingKey {
        case offsetLocalMeters = "offset_local_m"
        case authorityRef = "authority_ref"
    }
}

public struct PlacementProvenance: Codable, Sendable, Equatable {
    public let method: PlacementMethod
    public let sourceSemanticEntityID: String?
    public let sourceMeshAnchorID: UUID?
    public let sourceRoomPlanObjectID: String?
    public let sourceEvidenceRefs: [String]

    public init(
        method: PlacementMethod,
        sourceSemanticEntityID: String? = nil,
        sourceMeshAnchorID: UUID? = nil,
        sourceRoomPlanObjectID: String? = nil,
        sourceEvidenceRefs: [String] = []
    ) throws {
        let normalizedEvidence = Array(Set(sourceEvidenceRefs)).sorted()
        guard normalizedEvidence.count == sourceEvidenceRefs.count else {
            throw AnnotationModelError.duplicateEvidenceReference
        }

        switch method {
        case .raycast, .meshHitTest:
            guard sourceMeshAnchorID != nil
                    || sourceSemanticEntityID != nil
                    || !sourceEvidenceRefs.isEmpty
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
        self.sourceSemanticEntityID = sourceSemanticEntityID
        self.sourceMeshAnchorID = sourceMeshAnchorID
        self.sourceRoomPlanObjectID = sourceRoomPlanObjectID
        self.sourceEvidenceRefs = sourceEvidenceRefs
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case sourceSemanticEntityID = "source_semantic_entity_id"
        case sourceMeshAnchorID = "source_mesh_anchor_id"
        case sourceRoomPlanObjectID = "source_roomplan_object_id"
        case sourceEvidenceRefs = "source_evidence_refs"
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
        guard !label.isEmpty else {
            throw AnnotationModelError.emptyLabel
        }
        let uniqueEvidence = Set(evidenceRefs)
        guard uniqueEvidence.count == evidenceRefs.count else {
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

        self.entityID = entityID
        self.type = type
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromAnnotation = worldFromAnnotation
        self.referencePointSemantics = referencePointSemantics
        self.label = label
        self.provenanceClass = provenanceClass
        self.verificationState = verificationState
        self.placement = placement
        self.orientation = orientation
        self.channelRole = channelRole
        self.acousticCenter = acousticCenter
        self.equipmentRef = equipmentRef
        self.evidenceRefs = evidenceRefs
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
}

public struct CaptureAnnotationCollection: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let entities: [CaptureAnnotationEntity]

    public init(entities: [CaptureAnnotationEntity]) throws {
        let ids = entities.map(\.entityID)
        guard Set(ids).count == ids.count else {
            throw AnnotationModelError.duplicateEntityID
        }
        self.schema = "htdt.capture.entities"
        self.schemaVersion = "1.0.0"
        self.entities = entities
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case entities
    }
}
