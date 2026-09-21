import Foundation

public struct GeometrySelectionID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Which accepted geometry a post-scan selection landed on
/// (issue #282). Canonical sources are the committed mesh anchors and
/// RoomPlan objects; `derivedCandidate` selections are only possible
/// because the candidate was explicitly stored and labeled per #249.
public enum AcceptedGeometrySource: String, Codable, Sendable,
    Equatable
{
    case meshAnchor = "mesh_anchor"
    case roomPlanObject = "roomplan_object"
    case derivedCandidate = "derived_candidate"
}

public enum PostScanAuthoringError: Error, Sendable, Equatable {
    case emptyField
    case invalidRay
    case unknownSelection
    /// The selection was made against geometry that has since been
    /// superseded by a Continue-scanning pass — it must be re-picked.
    case staleSelection
    case unknownDerivedCandidate
    case candidateNotSelectable
    case coordinateSpaceMismatch
}

/// A world-space picking ray for post-scan authoring (issue #282).
public struct AcceptedGeometryRay: Sendable, Equatable {
    public let origin: Float3
    public let direction: Float3

    /// The direction is normalized on init; degenerate rays are
    /// rejected.
    public init(origin: Float3, direction: Float3) throws {
        guard origin.isFinite, direction.isFinite else {
            throw PostScanAuthoringError.invalidRay
        }
        let length = (direction.x * direction.x
            + direction.y * direction.y
            + direction.z * direction.z).squareRoot()
        guard length > 0 else {
            throw PostScanAuthoringError.invalidRay
        }
        self.origin = origin
        self.direction = Float3(
            direction.x / length,
            direction.y / length,
            direction.z / length
        )
    }
}

/// A single point selection on accepted geometry (issue #282). The
/// selection records the exact source it landed on plus the geometry
/// epoch it was made in so a Continue-scanning pass can invalidate it
/// explicitly instead of silently reprojecting.
public struct GeometrySelection: Sendable, Equatable {
    public let selectionID: GeometrySelectionID
    public let source: AcceptedGeometrySource
    public let coordinateSpaceID: CoordinateSpaceID
    /// Selected point in world coordinates of the bound space.
    public let positionWorld: Float3
    public let sourceMeshAnchorID: UUID?
    public let sourceRoomPlanObjectID: String?
    public let sourceDerivedCandidateID: DerivedGeometryCandidateID?
    public let sourceEvidenceRefs: [String]
    public let geometryEpoch: Int

    /// Canonical geometry (committed mesh / RoomPlan authority) vs
    /// derived candidates, which stay visibly distinct.
    public var isCanonicalSource: Bool {
        source != .derivedCandidate
    }
}

/// A RoomPlan object the platform surface made selectable (id +
/// semantic classification). On iOS the host supplies these from the
/// decoded `CapturedRoom`; core never decodes RoomPlan payloads.
public struct AcceptedRoomPlanObject: Sendable, Equatable {
    public let objectID: String
    public let semanticEntityID: String?
    /// Object center in world coordinates.
    public let positionWorld: Float3

    public init(
        objectID: String,
        semanticEntityID: String? = nil,
        positionWorld: Float3
    ) throws {
        guard !objectID.isEmpty else {
            throw PostScanAuthoringError.emptyField
        }
        guard positionWorld.isFinite else {
            throw PostScanAuthoringError.invalidRay
        }
        self.objectID = objectID
        self.semanticEntityID = semanticEntityID
        self.positionWorld = positionWorld
    }
}

/// Post-scan 3D authoring session (issue #282): places annotation
/// endpoints and measurement endpoints directly on the accepted
/// RoomPlan/mesh geometry — no live camera raycast required, so a
/// post-End AR continuity loss does not prevent geometry-backed
/// authoring.
///
/// Every selection is bound to a geometry epoch. When Continue
/// scanning produces replacement geometry, `noteGeometryChanged`
/// bumps the epoch and every earlier selection becomes explicitly
/// stale — `placementAuthority`/`endpointRef` then fail closed rather
/// than silently reproject onto geometry the operator never picked.
public struct PostScanGeometryAuthoringSession: Sendable, Equatable {
    public let coordinateSpaceID: CoordinateSpaceID
    public private(set) var geometryEpoch: Int
    private var meshAnchors: [MeshAnchorSnapshot]
    private var roomPlanObjects: [AcceptedRoomPlanObject]
    private var derivedCandidates: [DerivedGeometryCandidateRecord]
    private var selections: [GeometrySelectionID: GeometrySelection] = [:]
    private var staleSelectionIDs: Set<GeometrySelectionID> = []

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        meshAnchors: [MeshAnchorSnapshot] = [],
        roomPlanObjects: [AcceptedRoomPlanObject] = [],
        derivedCandidates: [DerivedGeometryCandidateRecord] = []
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.geometryEpoch = 0
        self.meshAnchors = meshAnchors.filter {
            $0.coordinateSpaceID == coordinateSpaceID
        }
        self.roomPlanObjects = roomPlanObjects
        // Derived candidates are only selectable when they were
        // explicitly stored (they arrive via the persisted #249
        // document) and resolved to a shape.
        self.derivedCandidates = derivedCandidates.filter {
            $0.coordinateSpaceID == coordinateSpaceID
        }
    }

    public func selection(
        _ id: GeometrySelectionID
    ) -> GeometrySelection? {
        selections[id]
    }

    public func isStale(_ id: GeometrySelectionID) -> Bool {
        staleSelectionIDs.contains(id)
    }

    /// Möller–Trumbore nearest-hit over every accepted mesh anchor.
    /// Returns the world-space hit as a geometry-bound selection.
    @discardableResult
    public mutating func hitTestMesh(
        ray: AcceptedGeometryRay
    ) -> GeometrySelection? {
        var best: (
            anchor: MeshAnchorSnapshot,
            point: Float3,
            distance: Float
        )?
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.worldFromAnchor.values
            for face in stride(
                from: 0,
                to: geometry.triangleIndices.count,
                by: 3
            ) {
                let i0 = Int(geometry.triangleIndices[face])
                let i1 = Int(geometry.triangleIndices[face + 1])
                let i2 = Int(geometry.triangleIndices[face + 2])
                let a = Self.transformPoint(
                    geometry.vertices[i0],
                    columnMajor: transform
                )
                let b = Self.transformPoint(
                    geometry.vertices[i1],
                    columnMajor: transform
                )
                let c = Self.transformPoint(
                    geometry.vertices[i2],
                    columnMajor: transform
                )
                guard let hit = Self.rayTriangle(
                    ray: ray,
                    a: a,
                    b: b,
                    c: c
                ) else { continue }
                if best == nil || hit.distance < best!.distance {
                    best = (anchor, hit.point, hit.distance)
                }
            }
        }
        guard let best else { return nil }
        let selection = GeometrySelection(
            selectionID: GeometrySelectionID(),
            source: .meshAnchor,
            coordinateSpaceID: coordinateSpaceID,
            positionWorld: best.point,
            sourceMeshAnchorID: best.anchor.anchorID,
            sourceRoomPlanObjectID: nil,
            sourceDerivedCandidateID: nil,
            sourceEvidenceRefs: [
                "mesh_anchor:\(best.anchor.anchorID.uuidString.lowercased())",
            ],
            geometryEpoch: geometryEpoch
        )
        selections[selection.selectionID] = selection
        return selection
    }

    /// Selects a RoomPlan object directly (e.g. tapped object in the
    /// post-scan model view). The point lands on the object's center.
    @discardableResult
    public mutating func selectRoomPlanObject(
        objectID: String
    ) throws -> GeometrySelection {
        guard let object = roomPlanObjects.first(where: {
            $0.objectID == objectID
        }) else {
            throw PostScanAuthoringError.emptyField
        }
        let selection = GeometrySelection(
            selectionID: GeometrySelectionID(),
            source: .roomPlanObject,
            coordinateSpaceID: coordinateSpaceID,
            positionWorld: object.positionWorld,
            sourceMeshAnchorID: nil,
            sourceRoomPlanObjectID: object.objectID,
            sourceDerivedCandidateID: nil,
            sourceEvidenceRefs: [
                "roomplan_object:\(object.objectID)",
            ],
            geometryEpoch: geometryEpoch
        )
        selections[selection.selectionID] = selection
        return selection
    }

    /// Selects a contour point on a persisted derived-geometry
    /// candidate (issue #282: derived geometry is selectable only
    /// because it was explicitly stored/labeled per #249).
    @discardableResult
    public mutating func selectDerivedCandidatePoint(
        candidateID: DerivedGeometryCandidateID,
        pointIndex: Int,
        heightMeters: Float = 0
    ) throws -> GeometrySelection {
        guard let record = derivedCandidates.first(where: {
            $0.candidateID == candidateID
        }) else {
            throw PostScanAuthoringError.unknownDerivedCandidate
        }
        guard record.resolution == .resolved,
              record.contourPoints.indices.contains(pointIndex)
        else {
            throw PostScanAuthoringError.candidateNotSelectable
        }
        let point = record.contourPoints[pointIndex]
        let selection = GeometrySelection(
            selectionID: GeometrySelectionID(),
            source: .derivedCandidate,
            coordinateSpaceID: coordinateSpaceID,
            positionWorld: Float3(
                Float(point.position.x),
                Float(point.verticalPositionMeters ?? 0)
                    + heightMeters,
                Float(point.position.y)
            ),
            sourceMeshAnchorID: nil,
            sourceRoomPlanObjectID: nil,
            sourceDerivedCandidateID: candidateID,
            sourceEvidenceRefs: [
                "derived_candidate:\(candidateID)",
            ],
            geometryEpoch: geometryEpoch
        )
        selections[selection.selectionID] = selection
        return selection
    }

    /// Produces the annotation placement authority for a selection.
    /// Stale selections (geometry changed since the pick) fail closed.
    public func placementAuthority(
        for selectionID: GeometrySelectionID
    ) throws -> AnnotationPlacementAuthority {
        let selection = try requireSelection(selectionID)
        let placement: PlacementProvenance
        switch selection.source {
        case .meshAnchor:
            placement = try PlacementProvenance(
                method: .meshHitTest,
                sourceMeshAnchorID: selection.sourceMeshAnchorID,
                sourceEvidenceRefs: selection.sourceEvidenceRefs
            )
        case .roomPlanObject:
            placement = try PlacementProvenance(
                method: .roomPlanBinding,
                sourceRoomPlanObjectID:
                    selection.sourceRoomPlanObjectID,
                sourceEvidenceRefs: selection.sourceEvidenceRefs
            )
        case .derivedCandidate:
            placement = try PlacementProvenance(
                method: .other,
                sourceEvidenceRefs: selection.sourceEvidenceRefs
            )
        }
        return try AnnotationPlacementAuthority(
            worldFromAnnotation: Matrix4x4F.translation(
                of: selection.positionWorld
            ),
            placement: placement,
            coordinateSpaceID: selection.coordinateSpaceID,
            evidenceRefs: selection.sourceEvidenceRefs
        )
    }

    /// The measurement endpoint ref for a selection (issue #282:
    /// endpoints reuse the same selection). The committed measurement
    /// then carries `coordinate_space_id` plus these refs.
    public func endpointRef(
        for selectionID: GeometrySelectionID
    ) throws -> String {
        let selection = try requireSelection(selectionID)
        return "geometry_point:\(selection.selectionID)"
    }

    /// Continue-scanning path: the accepted geometry changed. Every
    /// selection from the prior epoch becomes explicitly stale —
    /// authoring reuses are rejected until the operator re-picks.
    public mutating func noteGeometryChanged(
        meshAnchors: [MeshAnchorSnapshot],
        roomPlanObjects: [AcceptedRoomPlanObject] = [],
        derivedCandidates: [DerivedGeometryCandidateRecord] = []
    ) {
        geometryEpoch += 1
        staleSelectionIDs.formUnion(selections.keys)
        self.meshAnchors = meshAnchors.filter {
            $0.coordinateSpaceID == coordinateSpaceID
        }
        self.roomPlanObjects = roomPlanObjects
        self.derivedCandidates = derivedCandidates.filter {
            $0.coordinateSpaceID == coordinateSpaceID
        }
    }

    /// Drops a selection the operator abandoned.
    public mutating func discardSelection(
        _ id: GeometrySelectionID
    ) {
        selections.removeValue(forKey: id)
        staleSelectionIDs.remove(id)
    }

    private func requireSelection(
        _ id: GeometrySelectionID
    ) throws -> GeometrySelection {
        guard let selection = selections[id] else {
            throw PostScanAuthoringError.unknownSelection
        }
        guard !staleSelectionIDs.contains(id),
              selection.geometryEpoch == geometryEpoch
        else {
            throw PostScanAuthoringError.staleSelection
        }
        return selection
    }

    private static func transformPoint(
        _ point: Float3,
        columnMajor m: [Float]
    ) -> Float3 {
        Float3(
            m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12],
            m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13],
            m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14]
        )
    }

    /// Möller–Trumbore ray/triangle intersection. Returns the world
    /// hit point and ray distance for the nearest intersection.
    private static func rayTriangle(
        ray: AcceptedGeometryRay,
        a: Float3,
        b: Float3,
        c: Float3
    ) -> (point: Float3, distance: Float)? {
        let epsilon: Float = 1e-7
        let edge1 = Float3(b.x - a.x, b.y - a.y, b.z - a.z)
        let edge2 = Float3(c.x - a.x, c.y - a.y, c.z - a.z)
        let pvec = Float3(
            ray.direction.y * edge2.z - ray.direction.z * edge2.y,
            ray.direction.z * edge2.x - ray.direction.x * edge2.z,
            ray.direction.x * edge2.y - ray.direction.y * edge2.x
        )
        let determinant =
            edge1.x * pvec.x + edge1.y * pvec.y + edge1.z * pvec.z
        guard abs(determinant) > epsilon else { return nil }
        let inverse = 1 / determinant
        let tvec = Float3(
            ray.origin.x - a.x,
            ray.origin.y - a.y,
            ray.origin.z - a.z
        )
        let u = (tvec.x * pvec.x + tvec.y * pvec.y + tvec.z * pvec.z)
            * inverse
        guard u >= -epsilon, u <= 1 + epsilon else { return nil }
        let qvec = Float3(
            tvec.y * edge1.z - tvec.z * edge1.y,
            tvec.z * edge1.x - tvec.x * edge1.z,
            tvec.x * edge1.y - tvec.y * edge1.x
        )
        let v = (ray.direction.x * qvec.x
            + ray.direction.y * qvec.y
            + ray.direction.z * qvec.z) * inverse
        guard v >= -epsilon, u + v <= 1 + epsilon else { return nil }
        let distance = (edge2.x * qvec.x
            + edge2.y * qvec.y
            + edge2.z * qvec.z) * inverse
        guard distance > epsilon else { return nil }
        return (
            Float3(
                ray.origin.x + ray.direction.x * distance,
                ray.origin.y + ray.direction.y * distance,
                ray.origin.z + ray.direction.z * distance
            ),
            distance
        )
    }
}

private extension Matrix4x4F {
    static func translation(of point: Float3) -> Matrix4x4F {
        // Validated rigid transform: identity rotation plus the
        // selected world point as translation.
        // swiftlint:disable:next force_try
        try! Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            point.x, point.y, point.z, 1,
        ])
    }
}
