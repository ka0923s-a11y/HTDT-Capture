import Foundation

/// A world-space hit against the active/persisted ARKit mesh
/// reconstruction (#246). Carries the exact mesh anchor identity so the
/// placement provenance keeps `source_mesh_anchor_id` populated.
public struct MeshRaycastHit: Sendable, Equatable {
    public let meshAnchorID: UUID
    public let distanceMeters: Float
    public let positionWorld: Float3
    /// Index of the hit triangle inside the anchor's geometry payload.
    public let triangleIndex: Int

    public init(
        meshAnchorID: UUID,
        distanceMeters: Float,
        positionWorld: Float3,
        triangleIndex: Int
    ) {
        self.meshAnchorID = meshAnchorID
        self.distanceMeters = distanceMeters
        self.positionWorld = positionWorld
        self.triangleIndex = triangleIndex
    }
}

/// Pure ray/triangle intersection over mesh-anchor snapshots (#246).
/// Works identically on live `ARMeshAnchor` snapshots materialized by
/// the platform and on persisted `mesh/geometry/*.meshbin` payloads
/// decoded for Review diagnostics — the geometry contract is the same.
public enum MeshRaycast {
    /// Nearest hit across `anchors`, or nil when the ray misses every
    /// mesh surface within `maxDistanceMeters`.
    public static func nearestHit(
        ray: SpatialRay,
        anchors: [MeshAnchorSnapshot],
        maxDistanceMeters: Float = 15
    ) -> MeshRaycastHit? {
        var best: MeshRaycastHit?
        var bestDistance = maxDistanceMeters

        for anchor in anchors {
            // Cheap world-space AABB prefilter: a ray that misses the
            // anchor's bounds cannot hit its triangles.
            let bounds = SpatialAxisBounds(
                vertices: anchor.geometry.vertices,
                worldFromAnchor: anchor.worldFromAnchor
            )
            guard
                bounds.contains(ray.origin)
                    || bounds.raycastEntryDistance(ray) != nil
            else {
                continue
            }

            // Intersect in anchor-local space: transform the ray by the
            // inverse rigid transform so triangle math stays in the
            // payload's native coordinates.
            let localFromWorld = anchor.worldFromAnchor.invertedRigid()
            let localOrigin = localFromWorld.applying(to: ray.origin)
            let localDirection =
                localFromWorld.applying(toDirection: ray.direction)
            guard let localRay = try? SpatialRay(
                origin: localOrigin,
                direction: localDirection
            ) else {
                continue
            }

            let vertices = anchor.geometry.vertices
            let indices = anchor.geometry.triangleIndices
            let faceCount = indices.count / 3
            for face in 0..<faceCount {
                let base = face * 3
                let a = vertices[Int(indices[base])]
                let b = vertices[Int(indices[base + 1])]
                let c = vertices[Int(indices[base + 2])]
                guard let t = RayTriangleIntersection.intersect(
                    ray: localRay,
                    a: a,
                    b: b,
                    c: c,
                    maxDistance: bestDistance
                ) else {
                    continue
                }
                // Rigid transforms preserve distances, so `t` is
                // already a world-space distance.
                let world = ray.origin + ray.direction * t
                best = MeshRaycastHit(
                    meshAnchorID: anchor.anchorID,
                    distanceMeters: t,
                    positionWorld: world,
                    triangleIndex: face
                )
                bestDistance = t
            }
        }
        return best
    }
}
