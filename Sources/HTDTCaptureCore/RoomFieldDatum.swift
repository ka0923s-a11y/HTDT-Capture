import Foundation

public enum RoomFieldDatumError: Error, Sendable, Equatable {
    case emptyRef
    case emptyField
    case nonFiniteValue
    case degenerateDirection
    case duplicateEvidenceReference
    case nonOrthonormalBasis
    case encodedDocumentMismatch
}

/// Where the field datum's origin point comes from (issue bolph71656-ai/HTDT-Capture#232
/// refinement). The set is bounded so the persisted record names an
/// install-meaningful anchor, never an arbitrary point.
public enum RoomFieldDatumOriginKind:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Exact captured room corner/vertex.
    case roomCorner = "room_corner"
    /// Point or midpoint on an explicitly selected wall.
    case wallPoint = "wall_point"
    /// Surveyed/reference point recorded as capture evidence.
    case surveyedPoint = "surveyed_point"
    /// Screen or reference point intentionally chosen by the operator.
    case screenPoint = "screen_point"
    /// The confirmed room reference frame's origin reused as the datum
    /// origin.
    case roomFrameOrigin = "room_frame_origin"
}

/// What defines the field datum's horizontal +Y (front) axis
/// (issue bolph71656-ai/HTDT-Capture#232 refinement).
public enum RoomFieldDatumAxisKind:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Two surveyed/reference points defining the axis.
    case twoSurveyedPoints = "two_surveyed_points"
    /// A selected wall's direction.
    case wallDirection = "wall_direction"
    /// The confirmed room reference frame's front direction.
    case roomFrameFront = "room_frame_front"
    /// A screen/reference direction intentionally chosen by the
    /// operator.
    case screenDirection = "screen_direction"
}

/// Which explicit Z=0 reference the field frame uses (issue bolph71656-ai/HTDT-Capture#232
/// refinement): the finished-floor plane, or a riser/platform top as
/// the alternate explicit vertical zero.
public enum RoomFieldDatumVerticalKind:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Finished-floor plane is field Z = 0.
    case finishedFloor = "finished_floor"
    /// Riser/platform top is field Z = 0.
    case platformTop = "platform_top"
}

/// The datum origin: a bounded kind, the source evidence token it was
/// resolved from, and the resolved position in the bound coordinate
/// space, meters.
public struct RoomFieldDatumOrigin: Codable, Sendable, Equatable {
    public let kind: RoomFieldDatumOriginKind
    /// Source token the point was resolved from (e.g.
    /// `room_reference_frame`, `entity:<id>`, `user:<uuid>`,
    /// `roomplan:wall:<id>`).
    public let ref: String
    /// Resolved point in `coordinate_space_id` meters.
    public let pointMeters: WorldPoint3D

    public init(
        kind: RoomFieldDatumOriginKind,
        ref: String,
        pointMeters: WorldPoint3D
    ) throws {
        guard !ref.isEmpty else {
            throw RoomFieldDatumError.emptyRef
        }
        guard pointMeters.isFinite else {
            throw RoomFieldDatumError.nonFiniteValue
        }
        self.kind = kind
        self.ref = ref
        self.pointMeters = pointMeters
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case ref
        case pointMeters = "point_m"
    }
}

/// The datum's front-axis declaration: a bounded kind, the tokens that
/// defined it, and the resolved unit direction in the bound coordinate
/// space.
public struct RoomFieldDatumAxis: Codable, Sendable, Equatable {
    public let kind: RoomFieldDatumAxisKind
    /// Axis-defining evidence tokens (e.g. the two surveyed points, the
    /// selected wall, or `room_reference_frame`).
    public let refs: [String]
    /// Resolved unit direction on the gravity-horizontal plane,
    /// `coordinate_space_id`.
    public let directionMeters: WorldPoint3D

    public init(
        kind: RoomFieldDatumAxisKind,
        refs: [String],
        directionMeters: WorldPoint3D
    ) throws {
        guard !refs.isEmpty,
              refs.allSatisfy({ !$0.isEmpty })
        else {
            throw RoomFieldDatumError.emptyRef
        }
        guard Set(refs).count == refs.count else {
            throw RoomFieldDatumError.duplicateEvidenceReference
        }
        guard directionMeters.isFinite,
              directionMeters.distanceSquared(to: .zero) > 0
        else {
            throw RoomFieldDatumError.degenerateDirection
        }
        self.kind = kind
        self.refs = refs
        self.directionMeters = directionMeters
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case refs
        case directionMeters = "direction_m"
    }
}

/// The vertical datum: where field Z = 0 sits in the bound coordinate
/// space (issue bolph71656-ai/HTDT-Capture#232 refinement). `zeroElevationMeters` is the
/// capture-space elevation of the finished floor or platform top —
/// always explicit, never inferred from the datum origin's height.
public struct RoomFieldDatumVertical: Codable, Sendable, Equatable {
    public let kind: RoomFieldDatumVerticalKind
    /// Token the elevation was resolved from (e.g. a wall ref, a
    /// platform entity, or `user:<uuid>` for an operator-stated value).
    public let ref: String
    /// Capture-space elevation that maps to field Z = 0, meters.
    public let zeroElevationMeters: Double

    public init(
        kind: RoomFieldDatumVerticalKind,
        ref: String,
        zeroElevationMeters: Double
    ) throws {
        guard !ref.isEmpty else {
            throw RoomFieldDatumError.emptyRef
        }
        guard zeroElevationMeters.isFinite else {
            throw RoomFieldDatumError.nonFiniteValue
        }
        self.kind = kind
        self.ref = ref
        self.zeroElevationMeters = zeroElevationMeters
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case ref
        case zeroElevationMeters = "zero_elevation_m"
    }
}

/// The exact `T_field_from_capture_world` rigid transform, stored as a
/// field-space orthonormal basis expressed in capture-space
/// coordinates plus the field origin's capture-space position. Units
/// and handedness are pinned by `units`/`axisConvention` on the
/// document — this record is evidence for later HTDT alignment, not a
/// scene transform in itself.
public struct RoomFieldDatumTransform: Codable, Sendable, Equatable {
    public let originMeters: WorldPoint3D
    public let xAxis: WorldPoint3D
    public let yAxis: WorldPoint3D
    public let zAxis: WorldPoint3D

    public init(
        originMeters: WorldPoint3D,
        xAxis: WorldPoint3D,
        yAxis: WorldPoint3D,
        zAxis: WorldPoint3D
    ) throws {
        for vector in [originMeters, xAxis, yAxis, zAxis]
            where !vector.isFinite
        {
            throw RoomFieldDatumError.nonFiniteValue
        }
        let axes = [xAxis, yAxis, zAxis]
        let tolerance = 1e-4
        for axis in axes {
            let lengthSquared = axis.distanceSquared(to: .zero)
            guard abs(lengthSquared - 1) < tolerance else {
                throw RoomFieldDatumError.nonOrthonormalBasis
            }
        }
        for i in axes.indices {
            for j in axes.indices where i < j {
                guard abs(axes[i].dot(axes[j])) < tolerance else {
                    throw RoomFieldDatumError.nonOrthonormalBasis
                }
            }
        }
        self.originMeters = originMeters
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    private enum CodingKeys: String, CodingKey {
        case originMeters = "origin_m"
        case xAxis = "x_axis"
        case yAxis = "y_axis"
        case zAxis = "z_axis"
    }
}

/// The capture-world → field promotion reference (issue bolph71656-ai/HTDT-Capture#232). One
/// record per revision, persisted at `session/room-field-datum.json`:
/// it binds a physical install datum — origin, front axis, and an
/// explicit vertical zero — into the capture's coordinate space, with
/// the exact transform plus the evidence it was declared from. It is
/// promotion *reference*, not `T_scene_from_capture_world`: the
/// capture coordinate space is an implementation detail of capture,
/// and HTDT Scene grounding happens downstream against this record.
public struct RoomFieldDatumDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.room-field-datum"
    public static let schemaVersion = "1.0.0"
    /// SI units of every length in this document.
    public static let units = "m"
    /// Right-handed field axes: +Y is the declared front, +Z is up.
    public static let axisConvention = "y_front_z_up"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    /// The capture coordinate space every position/direction is
    /// expressed in. Never conflated with the HTDT scene frame.
    public let coordinateSpaceID: CoordinateSpaceID
    public let origin: RoomFieldDatumOrigin
    public let axis: RoomFieldDatumAxis
    public let verticalDatum: RoomFieldDatumVertical
    /// The exact promotion transform. `origin_m.y` equals
    /// `vertical_datum.zero_elevation_m` — the vertical datum pins
    /// where field Z = 0 lands in capture space.
    public let fieldFromCaptureWorld: RoomFieldDatumTransform
    public let units: String
    public let axisConvention: String
    /// Uncertainty on the declared geometry, meters, when the
    /// construction method provides one.
    public let uncertaintyMeters: Double?
    /// Construction residual, meters, when the method provides one
    /// (e.g. the surveyed-points fit residual).
    public let residualMeters: Double?
    /// Spatial evidence links (`path:`/`frame:`/`mesh_anchor:`) the
    /// declaration was made against.
    public let sourceEvidenceRefs: [String]
    public let confirmedAtUTC: String

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        origin: RoomFieldDatumOrigin,
        axis: RoomFieldDatumAxis,
        verticalDatum: RoomFieldDatumVertical,
        fieldFromCaptureWorld: RoomFieldDatumTransform,
        uncertaintyMeters: Double? = nil,
        residualMeters: Double? = nil,
        sourceEvidenceRefs: [String] = [],
        confirmedAtUTC: String
    ) throws {
        for value in [uncertaintyMeters, residualMeters] {
            if let value {
                guard value.isFinite, value >= 0 else {
                    throw RoomFieldDatumError.nonFiniteValue
                }
            }
        }
        guard confirmedAtUTC.hasSuffix("Z") else {
            throw RoomFieldDatumError.emptyField
        }
        guard abs(
            fieldFromCaptureWorld.originMeters.y
                - verticalDatum.zeroElevationMeters
        ) < 1e-6 else {
            // The transform origin must sit exactly on the declared
            // vertical zero — a discrepancy would silently misplace the
            // field frame's Z = 0.
            throw RoomFieldDatumError.nonOrthonormalBasis
        }
        guard Set(sourceEvidenceRefs).count
                == sourceEvidenceRefs.count,
              sourceEvidenceRefs.allSatisfy({ !$0.isEmpty })
        else {
            throw RoomFieldDatumError.duplicateEvidenceReference
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.origin = origin
        self.axis = axis
        self.verticalDatum = verticalDatum
        self.fieldFromCaptureWorld = fieldFromCaptureWorld
        self.units = Self.units
        self.axisConvention = Self.axisConvention
        self.uncertaintyMeters = uncertaintyMeters
        self.residualMeters = residualMeters
        self.sourceEvidenceRefs = sourceEvidenceRefs
        self.confirmedAtUTC = confirmedAtUTC
    }

    /// Every reference token the datum depends on, for staleness
    /// evaluation and evidence-link bookkeeping.
    public var referenceTokens: [String] {
        [origin.ref] + axis.refs + [verticalDatum.ref]
            + sourceEvidenceRefs
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case origin
        case axis
        case verticalDatum = "vertical_datum"
        case fieldFromCaptureWorld = "T_field_from_capture_world"
        case units
        case axisConvention = "axis_convention"
        case uncertaintyMeters = "uncertainty_m"
        case residualMeters = "residual_m"
        case sourceEvidenceRefs = "source_evidence_refs"
        case confirmedAtUTC = "confirmed_at"
    }
}

public struct RoomFieldDatumPackage: Sendable, Equatable {
    public static let path = "session/room-field-datum.json"

    public let document: RoomFieldDatumDocument
    public let data: Data

    public init(document: RoomFieldDatumDocument, data: Data) {
        self.document = document
        self.data = data
    }

    /// Operator-declared install datum: user authority, canonical
    /// payload, lineage edge to the bound session.
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

public enum RoomFieldDatumPackageBuilder {
    /// Builds the canonical datum document. The field basis is
    /// derived, never free-stated: +Z is the capture space's gravity
    /// vertical (+Y, matching the room-frame convention), +Y is the
    /// declared front direction projected onto the horizontal plane,
    /// +X completes the right-handed frame. The transform origin is
    /// the declared origin point re-leveled to the vertical datum's
    /// zero elevation so field Z = 0 lands exactly where declared.
    public static func build(
        document: RoomFieldDatumDocument
    ) throws -> RoomFieldDatumPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard let decoded = try? JSONDecoder().decode(
            RoomFieldDatumDocument.self,
            from: data
        ), decoded == document else {
            throw RoomFieldDatumError.encodedDocumentMismatch
        }
        return RoomFieldDatumPackage(
            document: document,
            data: data
        )
    }

    /// Resolves the transform for a declaration: front is projected
    /// onto the gravity-horizontal plane (capture +Y is vertical, as
    /// with the room reference frame), +X is `+Y × +Z`.
    public static func fieldTransform(
        origin: RoomFieldDatumOrigin,
        axis: RoomFieldDatumAxis,
        verticalDatum: RoomFieldDatumVertical
    ) throws -> RoomFieldDatumTransform {
        let zAxis = WorldPoint3D(x: 0, y: 1, z: 0)
        let front = axis.directionMeters
        let horizontal = WorldPoint3D(
            x: front.x,
            y: 0,
            z: front.z
        )
        let length = horizontal.distance(to: .zero)
        guard length > 1e-9 else {
            throw RoomFieldDatumError.degenerateDirection
        }
        // `-0.0` serializes as `-0`, which is not canonical JSON —
        // persist every axis component as +0.0.
        func nonzero(_ v: Double) -> Double {
            v == 0 ? 0 : v
        }
        let yAxis = WorldPoint3D(
            x: nonzero(horizontal.x / length),
            y: 0,
            z: nonzero(horizontal.z / length)
        )
        // +X = +Y (front) × +Z (up), right-handed.
        let xAxis = WorldPoint3D(
            x: nonzero(
                yAxis.y * zAxis.z - yAxis.z * zAxis.y
            ),
            y: nonzero(
                yAxis.z * zAxis.x - yAxis.x * zAxis.z
            ),
            z: nonzero(
                yAxis.x * zAxis.y - yAxis.y * zAxis.x
            )
        )
        return try RoomFieldDatumTransform(
            originMeters: WorldPoint3D(
                x: origin.pointMeters.x,
                y: verticalDatum.zeroElevationMeters,
                z: origin.pointMeters.z
            ),
            xAxis: xAxis,
            yAxis: yAxis,
            zAxis: zAxis
        )
    }
}

/// Whether a persisted datum still resolves against a revision's
/// evidence (issue bolph71656-ai/HTDT-Capture#232 staleness). A referenced wall/corner/platform
/// that the revision no longer carries must surface as unresolved —
/// the datum stays historical rather than silently rebinding.
public enum RoomFieldDatumStaleness: Sendable, Equatable {
    /// Every reference token resolves in the evaluated universe.
    case current
    /// These tokens could not be resolved.
    case stale(unresolvedRefs: [String])
}

/// The reference universe a datum is evaluated against (issue bolph71656-ai/HTDT-Capture#232
/// staleness). `tokens` carries enumerable identities —
/// `path:`/`frame:`/`entity:`/`measurement:`/`opening:`/
/// `mesh_anchor:`/`reference_target:` tokens and `room_reference_frame`
/// when the room frame is committed. `roomPlanPayload` is the raw
/// `roomplan/captured-room.json` bytes so `roomplan:<kind>:<uuid>`
/// tokens resolve at surface-id level on any platform.
public struct RoomFieldDatumReferenceUniverse: Sendable, Equatable {
    public var tokens: Set<String>
    public var roomPlanPayload: Data?

    public init(
        tokens: Set<String> = [],
        roomPlanPayload: Data? = nil
    ) {
        self.tokens = tokens
        self.roomPlanPayload = roomPlanPayload
    }

    /// True when the token resolves inside this universe.
    public func resolves(_ ref: String) -> Bool {
        // `user:` tokens are operator-resolved positions stored
        // verbatim in the datum document — they never depend on
        // revision content.
        if ref.hasPrefix("user:") { return true }
        if tokens.contains(ref) { return true }
        if ref.hasPrefix("roomplan:"),
           let payload = roomPlanPayload,
           let uuidText = ref.split(separator: ":").last,
           !uuidText.isEmpty
        {
            // RoomPlan encodes UUIDs uppercase while `roomplan:` tokens
            // are lowercased — accept either spelling.
            let lowered = String(uuidText).lowercased()
            let uppered = String(uuidText).uppercased()
            return payload.range(of: Data(lowered.utf8)) != nil
                || payload.range(of: Data(uppered.utf8)) != nil
        }
        return false
    }
}

public enum RoomFieldDatumStalenessEvaluator {
    /// Evaluates a datum against a revision's reference universe. A
    /// token that cannot be enumerated resolves conservatively —
    /// stale rather than silently rebound.
    public static func evaluate(
        datum: RoomFieldDatumDocument,
        universe: RoomFieldDatumReferenceUniverse
    ) -> RoomFieldDatumStaleness {
        var missing: [String] = []
        var seen = Set<String>()
        for ref in datum.referenceTokens
        where !universe.resolves(ref) {
            if seen.insert(ref).inserted {
                missing.append(ref)
            }
        }
        return missing.isEmpty
            ? .current
            : .stale(unresolvedRefs: missing)
    }
}
