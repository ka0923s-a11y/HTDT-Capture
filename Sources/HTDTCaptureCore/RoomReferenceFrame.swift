import Foundation

/// A double-precision world-space vector used by the room reference
/// frame document (issue #232). Positions/directions observed from
/// ARKit arrive as Float but persist as Double so downstream HTDT
/// authoring keeps full precision.
public struct WorldPoint3D: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    public func distance(to other: WorldPoint3D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

/// How the operator established the frame's front direction
/// (issue #232).
public enum RoomFrameCaptureMethod: String, Codable, Sendable {
    /// The operator placed the device over the intended room origin,
    /// confirmed it, then aimed/positioned the device along the intended
    /// room front direction and confirmed again. Both samples are
    /// ordinary AR camera positions in the bound coordinate space.
    case operatorTwoPointPath = "operator_two_point_path"
}

/// The "up" authority of a v1 room reference frame (issue #232). The
/// frame only names origin and front; up is always inherited from the
/// AR gravity authority so the frame cannot redefine vertical.
public enum RoomFrameUpReference: String, Codable, Sendable {
    case arGravity = "ar_gravity"
}

public enum RoomReferenceFrameError: Error, Sendable, Equatable {
    case nonFiniteValue
    case degenerateFrontDirection
    case coordinateSpaceUnbound
    case invalidTimestamp
    case encodedDocumentMismatch
}

/// Canonical, user-confirmed room reference frame authority
/// (issue #232), persisted at
/// `session/room-reference-frame.json`. The document is typed and
/// versioned so HTDT consumes the room frame without parsing labels or
/// free-text annotations: `coordinate_space_id` binds it to the same
/// coordinate authority every entity/measurement/frame expresses, the
/// origin is the operator-confirmed room origin in that space, and
/// `front_direction` is a unit vector in that space pointing toward the
/// room front (screen/stage wall). `up_reference` states that vertical
/// stays AR gravity authority; nothing here re-derives up.
///
/// The frame is optional: a capture without it is still a valid bundle.
public struct RoomReferenceFrameDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.room-reference-frame"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    /// The coordinate space the frame is expressed in; must equal the
    /// working set's bound space at persist time.
    public let coordinateSpaceID: CoordinateSpaceID
    /// Operator-confirmed room origin, meters, in `coordinateSpaceID`.
    public let originMeters: WorldPoint3D
    /// Unit direction in `coordinateSpaceID` toward the room front.
    /// The builder normalizes the observed front-point direction onto
    /// the gravity-horizontal plane so a tilted device cannot record a
    /// vertical front.
    public let frontDirection: WorldPoint3D
    public let upReference: RoomFrameUpReference
    public let method: RoomFrameCaptureMethod
    /// Spatial evidence links the operator attached while capturing the
    /// frame (for example the end-boundary frame active at capture
    /// time); resolved against committed frame/mesh authority like
    /// annotation refs.
    public let evidenceRefs: [String]
    /// UTC timestamp of the operator's explicit confirmation.
    public let confirmedAtUTC: String

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        originMeters: WorldPoint3D,
        frontDirection: WorldPoint3D,
        upReference: RoomFrameUpReference = .arGravity,
        method: RoomFrameCaptureMethod = .operatorTwoPointPath,
        evidenceRefs: [String] = [],
        confirmedAtUTC: String
    ) throws {
        guard originMeters.isFinite, frontDirection.isFinite else {
            throw RoomReferenceFrameError.nonFiniteValue
        }
        let magnitude = frontDirection.distance(
            to: WorldPoint3D(x: 0, y: 0, z: 0)
        )
        guard magnitude > 1e-4, magnitude.isFinite else {
            throw RoomReferenceFrameError.degenerateFrontDirection
        }
        // Normalize to a unit vector so consumers never divide by a
        // stale magnitude.
        let normalized = WorldPoint3D(
            x: frontDirection.x / magnitude,
            y: frontDirection.y / magnitude,
            z: frontDirection.z / magnitude
        )
        guard SchemaTimestampText.isUTCTimestamp(confirmedAtUTC) else {
            throw RoomReferenceFrameError.invalidTimestamp
        }

        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.originMeters = originMeters
        self.frontDirection = normalized
        self.upReference = upReference
        self.method = method
        self.evidenceRefs = evidenceRefs
        self.confirmedAtUTC = confirmedAtUTC
    }

    /// Two-point capture convenience (issue #232): the operator confirms
    /// the device over the intended room origin, then confirms a second
    /// camera position lying toward the room front. The front direction
    /// is the origin→front displacement projected onto the
    /// gravity-horizontal plane, so vertical hand drift cannot tilt the
    /// recorded front.
    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        originMeters: WorldPoint3D,
        frontPointMeters: WorldPoint3D,
        evidenceRefs: [String] = [],
        confirmedAtUTC: String
    ) throws {
        let front = WorldPoint3D(
            x: frontPointMeters.x - originMeters.x,
            y: 0,
            z: frontPointMeters.z - originMeters.z
        )
        try self.init(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            originMeters: originMeters,
            frontDirection: front,
            evidenceRefs: evidenceRefs,
            confirmedAtUTC: confirmedAtUTC
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case originMeters = "origin_m"
        case frontDirection = "front_direction"
        case upReference = "up_reference"
        case method
        case evidenceRefs = "evidence_refs"
        case confirmedAtUTC = "confirmed_at"
    }
}

public struct RoomReferenceFramePackage: Sendable, Equatable {
    public static let path = "session/room-reference-frame.json"

    public let document: RoomReferenceFrameDocument
    public let data: Data

    public init(
        document: RoomReferenceFrameDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    /// User-confirmed authority recorded by the capture app; lineage to
    /// the session authority that produced the camera positions is
    /// expressed through `capture_session:` source refs.
    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "room_frame",
            provenanceClass: .userAnnotation,
            role: .canonical,
            sourceRefs: [
                "capture_session:"
                    + document.captureSessionID.description
            ]
        )
    }
}

public enum RoomReferenceFramePackageBuilder {
    public static func build(
        document: RoomReferenceFrameDocument
    ) throws -> RoomReferenceFramePackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)

        guard let decoded = try? JSONDecoder().decode(
            RoomReferenceFrameDocument.self,
            from: data
        ), decoded == document else {
            throw RoomReferenceFrameError.encodedDocumentMismatch
        }
        return RoomReferenceFramePackage(
            document: document,
            data: data
        )
    }
}
