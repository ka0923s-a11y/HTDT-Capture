import Foundation

/// A RoomPlan-recognized object or surface an annotation can bind to
/// (#246). Decoded from the persisted processed `CapturedRoom`
/// (`roomplan/captured-room.json`) by the platform layer; identity is
/// the RoomPlan object/surface identifier, never re-derived here.
public struct RoomPlanBindableObject: Sendable, Equatable, Identifiable {
    /// Stable RoomPlan identifier string, persisted verbatim into
    /// `PlacementProvenance.sourceRoomPlanObjectID`.
    public let identifier: String
    /// RoomPlan category name (e.g. `"sofa"`, `"wall"`, `"storage"`),
    /// used only for display and class filtering.
    public let category: String
    /// Whether this entry describes a structural surface (wall, floor,
    /// door, window, opening) rather than a furniture object.
    public let isSurface: Bool
    /// World-space pose of the object's local frame.
    public let worldFromObject: Matrix4x4F
    /// Object-space extents (RoomPlan `dimensions`), meters.
    public let dimensionsMeters: Float3

    public init(
        identifier: String,
        category: String,
        isSurface: Bool,
        worldFromObject: Matrix4x4F,
        dimensionsMeters: Float3
    ) {
        self.identifier = identifier
        self.category = category
        self.isSurface = isSurface
        self.worldFromObject = worldFromObject
        self.dimensionsMeters = dimensionsMeters
    }

    public var id: String { identifier }

    /// Object center in world space.
    public var centerWorld: Float3 {
        worldFromObject.translationWorld
    }

    /// Axis bounds of the object's bounding box in world space. RoomPlan
    /// boxes may be rotated, so this is the world-space hull of the OBB
    /// corners — intentionally conservative.
    public var worldBounds: SpatialAxisBounds {
        let half = Float3(
            dimensionsMeters.x / 2,
            dimensionsMeters.y / 2,
            dimensionsMeters.z / 2
        )
        var lo = Float3(
            .greatestFiniteMagnitude,
            .greatestFiniteMagnitude,
            .greatestFiniteMagnitude
        )
        var hi = Float3(
            -.greatestFiniteMagnitude,
            -.greatestFiniteMagnitude,
            -.greatestFiniteMagnitude
        )
        for sx in [-half.x, half.x] {
            for sy in [-half.y, half.y] {
                for sz in [-half.z, half.z] {
                    let world = worldFromObject.applying(
                        to: Float3(sx, sy, sz)
                    )
                    lo = Float3(
                        min(lo.x, world.x),
                        min(lo.y, world.y),
                        min(lo.z, world.z)
                    )
                    hi = Float3(
                        max(hi.x, world.x),
                        max(hi.y, world.y),
                        max(hi.z, world.z)
                    )
                }
            }
        }
        return SpatialAxisBounds(minimum: lo, maximum: hi)
    }

    /// Distance from the ray origin to the ray's nearest intersection
    /// with the object's bounding box in object space, or nil when the
    /// ray misses the box.
    public func raycastEntryDistance(_ ray: SpatialRay) -> Float? {
        guard
            let localFromWorld =
                try? worldFromObject.invertedRigid(),
            let localRay = try? SpatialRay(
            origin: localFromWorld.applying(to: ray.origin),
            direction: localFromWorld.applying(toDirection: ray.direction)
        ) else {
            return nil
        }
        let half = Float3(
            abs(dimensionsMeters.x) / 2,
            abs(dimensionsMeters.y) / 2,
            abs(dimensionsMeters.z) / 2
        )
        return SpatialAxisBounds(
            minimum: Float3(-half.x, -half.y, -half.z),
            maximum: Float3(half.x, half.y, half.z)
        ).raycastEntryDistance(localRay)
    }
}

/// A world-space hit against a RoomPlan-recognized object or surface.
public struct RoomPlanObjectHit: Sendable, Equatable {
    public let object: RoomPlanBindableObject
    public let distanceMeters: Float
    public let positionWorld: Float3

    public init(
        object: RoomPlanBindableObject,
        distanceMeters: Float,
        positionWorld: Float3
    ) {
        self.object = object
        self.distanceMeters = distanceMeters
        self.positionWorld = positionWorld
    }
}

/// Nearest-hit raycasting over the bindable RoomPlan object set (#246).
/// The hit position anchors the annotation; the object's stable
/// identifier populates `source_roomplan_object_id` so the binding is
/// auditable against the persisted `CapturedRoom`.
public enum RoomPlanObjectRaycast {
    public static func nearestHit(
        ray: SpatialRay,
        objects: [RoomPlanBindableObject],
        maxDistanceMeters: Float = 15
    ) -> RoomPlanObjectHit? {
        var best: RoomPlanObjectHit?
        var bestDistance = maxDistanceMeters
        for object in objects {
            guard let distance = object.raycastEntryDistance(ray),
                  distance <= bestDistance
            else {
                continue
            }
            best = RoomPlanObjectHit(
                object: object,
                distanceMeters: distance,
                positionWorld: ray.origin + ray.direction * distance
            )
            bestDistance = distance
        }
        return best
    }
}
