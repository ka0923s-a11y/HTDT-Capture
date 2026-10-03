import Foundation

public enum RoomFieldDatumAuthoringError:
    Error,
    Sendable,
    Equatable
{
    case entityNotFound
    case entityHasNoOrientation
    case measurementNotFound
    case measurementEndpointsUnresolvable
    case roomFrameMissing
    case degenerateDirection
    case invalidOperandKind
    case missingStatedValue
}

/// Bounded operand for the datum origin (issue bolph71656-ai/HTDT-Capture#232): every pick maps
/// to an install-meaningful source — the confirmed room frame, an
/// authored entity position, or an operator-stated point — so the
/// persisted record names real evidence, never an arbitrary vector.
public enum RoomFieldDatumOriginOperand: Sendable, Equatable {
    /// Reuse the confirmed room reference frame's origin.
    case roomFrame
    /// An authored entity's resolved position; the kind records what
    /// the point semantically is (room corner, wall point, surveyed
    /// or screen point).
    case entity(AnnotationEntityID, RoomFieldDatumOriginKind)
    /// An operator-stated capture-space position (a `user:` ref — the
    /// point is stored verbatim and never goes stale).
    case statedPoint(RoomFieldDatumOriginKind)
}

/// Bounded operand for the datum's horizontal front axis.
public enum RoomFieldDatumAxisOperand: Sendable, Equatable {
    /// Reuse the confirmed room reference frame's front direction.
    case roomFrameFront
    /// A single entity's captured facing (wall or screen direction).
    case entityFacing(AnnotationEntityID, RoomFieldDatumAxisKind)
    /// Two authored entities treated as surveyed/reference points; the
    /// axis runs from the first position toward the second.
    case twoSurveyedEntities(AnnotationEntityID, AnnotationEntityID)
    /// A measurement whose `entity:` endpoint refs resolve to two
    /// entities; the measurement token is kept alongside the endpoint
    /// tokens so the axis traces to the recorded geometry.
    case measuredDirection(MeasurementID)
    /// An operator-stated capture-space direction (`user:` ref).
    case statedDirection(RoomFieldDatumAxisKind)
}

/// Bounded operand for the vertical datum (issue bolph71656-ai/HTDT-Capture#232): which
/// elevation maps to field Z = 0, and where that elevation was
/// declared from.
public enum RoomFieldDatumVerticalOperand: Sendable, Equatable {
    /// Operator-stated elevation meters (`user:` ref).
    case stated(RoomFieldDatumVerticalKind, Double)
    /// The room frame origin's elevation as the zero level.
    case fromRoomFrame(RoomFieldDatumVerticalKind)
    /// An entity's capture-space elevation (floor/platform entity).
    case fromEntity(RoomFieldDatumVerticalKind, AnnotationEntityID)
}

/// Everything the bounded authoring UI submits to the host (legacy bolph71656-ai/HTDT-Capture#232):
/// the three operands plus the free values only `statedPoint` /
/// `statedDirection` operands consume.
public struct RoomFieldDatumAuthoringRequest:
    Sendable,
    Equatable
{
    public var origin: RoomFieldDatumOriginOperand
    /// Required when `origin == .statedPoint`; ignored otherwise.
    public var statedOriginMeters: WorldPoint3D?
    public var axis: RoomFieldDatumAxisOperand
    /// Required when `axis == .statedDirection`; ignored otherwise.
    public var statedDirectionMeters: WorldPoint3D?
    public var vertical: RoomFieldDatumVerticalOperand

    public init(
        origin: RoomFieldDatumOriginOperand,
        statedOriginMeters: WorldPoint3D? = nil,
        axis: RoomFieldDatumAxisOperand,
        statedDirectionMeters: WorldPoint3D? = nil,
        vertical: RoomFieldDatumVerticalOperand
    ) {
        self.origin = origin
        self.statedOriginMeters = statedOriginMeters
        self.axis = axis
        self.statedDirectionMeters = statedDirectionMeters
        self.vertical = vertical
    }
}

/// The resolved datum triple — what `RoomFieldDatumDocument` stores —
/// plus the evidence tokens the declaration was made against.
public struct RoomFieldDatumResolution: Sendable, Equatable {
    public let origin: RoomFieldDatumOrigin
    public let axis: RoomFieldDatumAxis
    public let verticalDatum: RoomFieldDatumVertical
    /// Operand tokens in declaration order, deduplicated — safe to
    /// persist verbatim as `source_evidence_refs`.
    public let sourceEvidenceRefs: [String]

    public init(
        origin: RoomFieldDatumOrigin,
        axis: RoomFieldDatumAxis,
        verticalDatum: RoomFieldDatumVertical,
        sourceEvidenceRefs: [String]
    ) {
        self.origin = origin
        self.axis = axis
        self.verticalDatum = verticalDatum
        self.sourceEvidenceRefs = sourceEvidenceRefs
    }
}

/// Resolves bounded operand picks into a datum declaration against
/// the working set's committed entities/measurements/room frame
/// (issue bolph71656-ai/HTDT-Capture#232). Resolution is pure and testable: UI supplies the
/// operands, the host supplies the workspace data, and the caller
/// builds + commits the document.
public enum RoomFieldDatumAuthoring {
    private static func statedRef() -> String {
        "user:" + UUID().uuidString.lowercased()
    }

    /// The reference token for an entity operand — matches the
    /// staleness universe's `entity:<id>` token form.
    public static func entityRef(
        _ id: AnnotationEntityID
    ) -> String {
        "entity:" + id.description
    }

    /// The reference token for a measurement operand.
    public static func measurementRef(
        _ id: MeasurementID
    ) -> String {
        "measurement:" + id.description
    }

    private static func worldPoint(
        _ entity: CaptureAnnotationEntity
    ) -> WorldPoint3D {
        let t = entity.worldFromAnnotation.translationWorld
        return WorldPoint3D(
            x: Double(t.x),
            y: Double(t.y),
            z: Double(t.z)
        )
    }

    /// Projects `v` onto the gravity-horizontal plane (+Y is vertical
    /// in the capture space) and normalizes; throws
    /// `degenerateDirection` when the horizontal component vanishes.
    private static func horizontalUnit(
        _ v: WorldPoint3D
    ) throws -> WorldPoint3D {
        let length = (v.x * v.x + v.z * v.z).squareRoot()
        guard length > 1e-9 else {
            throw RoomFieldDatumAuthoringError.degenerateDirection
        }
        return WorldPoint3D(
            x: v.x / length,
            y: 0,
            z: v.z / length
        )
    }

    public static func resolve(
        origin originOperand: RoomFieldDatumOriginOperand,
        statedOriginMeters: WorldPoint3D? = nil,
        axis axisOperand: RoomFieldDatumAxisOperand,
        statedDirectionMeters: WorldPoint3D? = nil,
        vertical verticalOperand: RoomFieldDatumVerticalOperand,
        entities: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        roomReferenceFrame: RoomReferenceFrameDocument?
    ) throws -> RoomFieldDatumResolution {
        func entity(
            _ id: AnnotationEntityID
        ) throws -> CaptureAnnotationEntity {
            guard let match = entities.first(where: {
                $0.entityID == id
            }) else {
                throw RoomFieldDatumAuthoringError.entityNotFound
            }
            return match
        }
        func requireFrame(
        ) throws -> RoomReferenceFrameDocument {
            guard let frame = roomReferenceFrame else {
                throw RoomFieldDatumAuthoringError.roomFrameMissing
            }
            return frame
        }

        var refs: [String] = []
        func record(_ token: String) {
            if !refs.contains(token) { refs.append(token) }
        }

        let origin: RoomFieldDatumOrigin
        switch originOperand {
        case .roomFrame:
            let frame = try requireFrame()
            origin = try RoomFieldDatumOrigin(
                kind: .roomFrameOrigin,
                ref: "room_reference_frame",
                pointMeters: frame.originMeters
            )
            record("room_reference_frame")
        case let .entity(id, kind):
            guard kind != .roomFrameOrigin else {
                throw RoomFieldDatumAuthoringError.invalidOperandKind
            }
            let match = try entity(id)
            let ref = entityRef(match.entityID)
            origin = try RoomFieldDatumOrigin(
                kind: kind,
                ref: ref,
                pointMeters: worldPoint(match)
            )
            record(ref)
        case let .statedPoint(kind):
            guard kind != .roomFrameOrigin,
                  let point = statedOriginMeters
            else {
                throw kind == .roomFrameOrigin
                    ? RoomFieldDatumAuthoringError.invalidOperandKind
                    : RoomFieldDatumAuthoringError.missingStatedValue
            }
            let ref = statedRef()
            origin = try RoomFieldDatumOrigin(
                kind: kind,
                ref: ref,
                pointMeters: point
            )
            record(ref)
        }

        let axis: RoomFieldDatumAxis
        switch axisOperand {
        case .roomFrameFront:
            let frame = try requireFrame()
            axis = try RoomFieldDatumAxis(
                kind: .roomFrameFront,
                refs: ["room_reference_frame"],
                directionMeters: try horizontalUnit(
                    frame.frontDirection
                )
            )
            record("room_reference_frame")
        case let .entityFacing(id, kind):
            guard kind == .wallDirection
                    || kind == .screenDirection
            else {
                throw RoomFieldDatumAuthoringError.invalidOperandKind
            }
            let match = try entity(id)
            guard let orientation = match.orientation else {
                throw RoomFieldDatumAuthoringError
                    .entityHasNoOrientation
            }
            let front = orientation.frontAxisLocal
            let ref = entityRef(match.entityID)
            axis = try RoomFieldDatumAxis(
                kind: kind,
                refs: [ref],
                directionMeters: try horizontalUnit(
                    WorldPoint3D(
                        x: Double(front.x),
                        y: Double(front.y),
                        z: Double(front.z)
                    )
                )
            )
            record(ref)
        case let .twoSurveyedEntities(a, b):
            let first = try entity(a)
            let second = try entity(b)
            let pa = worldPoint(first)
            let pb = worldPoint(second)
            let direction = try horizontalUnit(
                WorldPoint3D(
                    x: pb.x - pa.x,
                    y: 0,
                    z: pb.z - pa.z
                )
            )
            let refA = entityRef(first.entityID)
            let refB = entityRef(second.entityID)
            axis = try RoomFieldDatumAxis(
                kind: .twoSurveyedPoints,
                refs: [refA, refB],
                directionMeters: direction
            )
            record(refA)
            record(refB)
        case let .measuredDirection(measurementID):
            guard let measurement = measurements.first(where: {
                $0.measurementID == measurementID
            }) else {
                throw RoomFieldDatumAuthoringError.measurementNotFound
            }
            // The axis endpoints are the measurement's first two
            // `entity:` endpoint refs — positions must resolve to
            // committed entities, never re-entered numbers.
            let endpoints = measurement.endpointRefs.compactMap {
                ref -> AnnotationEntityID? in
                guard ref.hasPrefix("entity:") else { return nil }
                return AnnotationEntityID(
                    canonicalString: String(ref.dropFirst(7))
                )
            }
            guard endpoints.count >= 2,
                  let first = try? entity(endpoints[0]),
                  let second = try? entity(endpoints[1])
            else {
                throw RoomFieldDatumAuthoringError
                    .measurementEndpointsUnresolvable
            }
            let pa = worldPoint(first)
            let pb = worldPoint(second)
            let direction = try horizontalUnit(
                WorldPoint3D(
                    x: pb.x - pa.x,
                    y: 0,
                    z: pb.z - pa.z
                )
            )
            let measurementToken = measurementRef(
                measurement.measurementID
            )
            let refA = entityRef(first.entityID)
            let refB = entityRef(second.entityID)
            axis = try RoomFieldDatumAxis(
                kind: .twoSurveyedPoints,
                refs: [measurementToken, refA, refB],
                directionMeters: direction
            )
            record(measurementToken)
            record(refA)
            record(refB)
        case let .statedDirection(kind):
            guard kind == .wallDirection
                    || kind == .screenDirection,
                  let stated = statedDirectionMeters
            else {
                throw kind == .roomFrameFront
                    || kind == .twoSurveyedPoints
                    ? RoomFieldDatumAuthoringError.invalidOperandKind
                    : RoomFieldDatumAuthoringError.missingStatedValue
            }
            let ref = statedRef()
            axis = try RoomFieldDatumAxis(
                kind: kind,
                refs: [ref],
                directionMeters: try horizontalUnit(stated)
            )
            record(ref)
        }

        let verticalDatum: RoomFieldDatumVertical
        switch verticalOperand {
        case let .stated(kind, zero):
            let ref = statedRef()
            verticalDatum = try RoomFieldDatumVertical(
                kind: kind,
                ref: ref,
                zeroElevationMeters: zero
            )
            record(ref)
        case let .fromRoomFrame(kind):
            let frame = try requireFrame()
            verticalDatum = try RoomFieldDatumVertical(
                kind: kind,
                ref: "room_reference_frame",
                zeroElevationMeters: frame.originMeters.y
            )
            record("room_reference_frame")
        case let .fromEntity(kind, id):
            let match = try entity(id)
            let ref = entityRef(match.entityID)
            verticalDatum = try RoomFieldDatumVertical(
                kind: kind,
                ref: ref,
                zeroElevationMeters: worldPoint(match).y
            )
            record(ref)
        }

        return RoomFieldDatumResolution(
            origin: origin,
            axis: axis,
            verticalDatum: verticalDatum,
            sourceEvidenceRefs: refs
        )
    }
}
