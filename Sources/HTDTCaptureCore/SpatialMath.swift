import Foundation

/// Rigid-transform helpers shared by the annotation workspace's
/// placement probing, mesh hit-testing and plausibility evaluation.
/// `Matrix4x4F` is always a world-space pose (`T_world_from_*`); these
/// helpers assume that rigid contract and are not a general linear-
/// algebra API.
extension Matrix4x4F {
    /// World-space translation column (elements 12...14).
    public var translationWorld: Float3 {
        Float3(values[12], values[13], values[14])
    }

    /// Apply the rigid transform to a point.
    public func applying(to point: Float3) -> Float3 {
        Float3(
            values[0] * point.x + values[4] * point.y
                + values[8] * point.z + values[12],
            values[1] * point.x + values[5] * point.y
                + values[9] * point.z + values[13],
            values[2] * point.x + values[6] * point.y
                + values[10] * point.z + values[14]
        )
    }

    /// Apply the rotation basis to a direction (no translation).
    public func applying(toDirection direction: Float3) -> Float3 {
        Float3(
            values[0] * direction.x + values[4] * direction.y
                + values[8] * direction.z,
            values[1] * direction.x + values[5] * direction.y
                + values[9] * direction.z,
            values[2] * direction.x + values[6] * direction.y
                + values[10] * direction.z
        )
    }

    /// Inverse of a rigid transform (`R^T` + translated rotation). The
    /// initializer contract already guarantees an orthonormal basis,
    /// so transpose is exact.
    public func invertedRigid() throws -> Matrix4x4F {
        let t = translationWorld
        // worldFromLocal inverse: rotation transposed, translation
        // is -R^T * t.
        let tx = -(values[0] * t.x + values[1] * t.y + values[2] * t.z)
        let ty = -(values[4] * t.x + values[5] * t.y + values[6] * t.z)
        let tz = -(values[8] * t.x + values[9] * t.y + values[10] * t.z)
        // The rigid contract keeps the transpose within the validating
        // initializer's tolerances, but a finite-yet-extreme stored
        // translation can still overflow the rotated translation column,
        // so callers handle the throw instead of trapping here.
        return try Matrix4x4F(values: [
            values[0], values[4], values[8], 0,
            values[1], values[5], values[9], 0,
            values[2], values[6], values[10], 0,
            tx, ty, tz, 1,
        ])
    }
}

/// `floor` → `Int` for coordinates that can be non-finite or outside
/// the `Int` range: `.isFinite` filters elsewhere only reject NaN and
/// ±inf, so corrupted bundle data (e.g. `1e300`) or an overflowed
/// difference of finite coordinates still reaches these conversions.
/// Non-finite maps to `0`; out-of-range saturates at `Int.max`/`Int.min`.
@inline(__always)
public func floorToIntClamped(_ value: Double) -> Int {
    guard value.isFinite else {
        return 0
    }
    let floored = value.rounded(.down)
    if floored >= Double(Int.max) {
        return Int.max
    }
    if floored <= Double(Int.min) {
        return Int.min
    }
    return Int(floored)
}

extension Float3 {
    public static func + (a: Float3, b: Float3) -> Float3 {
        Float3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    public static func - (a: Float3, b: Float3) -> Float3 {
        Float3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    public static func * (a: Float3, s: Float) -> Float3 {
        Float3(a.x * s, a.y * s, a.z * s)
    }

    public func dot(_ other: Float3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Float3) -> Float3 {
        Float3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public var length: Float {
        (x * x + y * y + z * z).squareRoot()
    }
}

/// A world-space ray in the capture coordinate space.
public struct SpatialRay: Sendable, Equatable {
    public let origin: Float3
    /// Unit-length world-space direction.
    public let direction: Float3

    public init(origin: Float3, direction: Float3) throws {
        guard origin.isFinite, direction.isFinite else {
            throw AnnotationModelError.invalidAxis
        }
        let magnitude = direction.length
        guard magnitude.isFinite, magnitude > 0.001 else {
            throw AnnotationModelError.invalidAxis
        }
        self.origin = origin
        self.direction = direction * (1 / magnitude)
    }
}

/// Axis-aligned bounds used for mesh/object prefiltering and the
/// advisory spatial-plausibility checks (#246/#247).
public struct SpatialAxisBounds:
    Codable, Sendable, Equatable
{
    public let minimum: Float3
    public let maximum: Float3

    public init(minimum: Float3, maximum: Float3) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Axis bounds of a vertex set transformed to world space.
    public init(
        vertices: [Float3],
        worldFromAnchor: Matrix4x4F
    ) {
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
        for vertex in vertices {
            let world = worldFromAnchor.applying(to: vertex)
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
        self.init(minimum: lo, maximum: hi)
    }

    public var union: (SpatialAxisBounds) -> SpatialAxisBounds {
        { other in
            SpatialAxisBounds(
                minimum: Float3(
                    min(minimum.x, other.minimum.x),
                    min(minimum.y, other.minimum.y),
                    min(minimum.z, other.minimum.z)
                ),
                maximum: Float3(
                    max(maximum.x, other.maximum.x),
                    max(maximum.y, other.maximum.y),
                    max(maximum.z, other.maximum.z)
                )
            )
        }
    }

    /// Whether `point` lies inside the bounds inflated by `margin` on
    /// every axis.
    public func contains(
        _ point: Float3,
        margin: Float = 0
    ) -> Bool {
        point.x >= minimum.x - margin
            && point.x <= maximum.x + margin
            && point.y >= minimum.y - margin
            && point.y <= maximum.y + margin
            && point.z >= minimum.z - margin
            && point.z <= maximum.z + margin
    }

    /// Distance from `point` to the bounds surface; 0 when inside.
    public func distanceOutside(_ point: Float3) -> Float {
        let dx = max(
            minimum.x - point.x,
            max(0, point.x - maximum.x)
        )
        let dy = max(
            minimum.y - point.y,
            max(0, point.y - maximum.y)
        )
        let dz = max(
            minimum.z - point.z,
            max(0, point.z - maximum.z)
        )
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Slab-method ray intersection. Returns the entry distance
    /// (>= 0) when the ray crosses the bounds, else nil.
    public func raycastEntryDistance(_ ray: SpatialRay) -> Float? {
        var tMin: Float = 0
        var tMax: Float = .greatestFiniteMagnitude
        for (origin, direction, lo, hi) in [
            (ray.origin.x, ray.direction.x, minimum.x, maximum.x),
            (ray.origin.y, ray.direction.y, minimum.y, maximum.y),
            (ray.origin.z, ray.direction.z, minimum.z, maximum.z),
        ] {
            if abs(direction) < 1e-8 {
                guard origin >= lo, origin <= hi else {
                    return nil
                }
                continue
            }
            var t0 = (lo - origin) / direction
            var t1 = (hi - origin) / direction
            if t0 > t1 { swap(&t0, &t1) }
            tMin = max(tMin, t0)
            tMax = min(tMax, t1)
            guard tMin <= tMax else {
                return nil
            }
        }
        return tMin
    }
}

/// Möller–Trumbore ray/triangle intersection. Returns the ray distance
/// `t` when the ray hits the triangle within `maxDistance`.
public enum RayTriangleIntersection {
    public static func intersect(
        ray: SpatialRay,
        a: Float3,
        b: Float3,
        c: Float3,
        maxDistance: Float
    ) -> Float? {
        let edge1 = b - a
        let edge2 = c - a
        let p = ray.direction.cross(edge2)
        let determinant = edge1.dot(p)
        // Non-culling: accept hits from either face orientation.
        guard abs(determinant) > 1e-9 else {
            return nil
        }
        let invDeterminant = 1 / determinant
        let s = ray.origin - a
        let u = s.dot(p) * invDeterminant
        guard u >= -1e-6, u <= 1 + 1e-6 else {
            return nil
        }
        let q = s.cross(edge1)
        let v = ray.direction.dot(q) * invDeterminant
        guard v >= -1e-6, u + v <= 1 + 1e-6 else {
            return nil
        }
        let t = edge2.dot(q) * invDeterminant
        guard t > 0, t <= maxDistance else {
            return nil
        }
        return t
    }
}
