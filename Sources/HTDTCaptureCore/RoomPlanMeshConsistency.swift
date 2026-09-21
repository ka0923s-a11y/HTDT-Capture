import Foundation

/// Bounded world-space geometry profile accumulated while mesh geometry
/// is committed (#277). Stores only aggregate extents and face-class
/// counts — never vertex buffers — so advisory evaluation stays cheap.
public struct MeshGeometryProfile: Sendable, Equatable {
    public private(set) var anchorCount = 0
    public private(set) var vertexCount = 0
    public private(set) var faceCount = 0
    /// Face counts keyed by ARMeshClassification raw value.
    public private(set) var faceClassificationCounts: [Int: Int] = [:]
    public private(set) var minimumX: Double?
    public private(set) var maximumX: Double?
    public private(set) var minimumY: Double?
    public private(set) var maximumY: Double?
    public private(set) var minimumZ: Double?
    public private(set) var maximumZ: Double?

    public init() {}

    public var isEmpty: Bool { anchorCount == 0 }

    /// World-space extent across all committed anchors, derived from
    /// each anchor's world transform applied to its local vertex bounds.
    public var worldExtentMeters: (x: Double, y: Double, z: Double)? {
        guard let minimumX, let maximumX, let minimumY, let maximumY,
              let minimumZ, let maximumZ
        else { return nil }
        return (
            maximumX - minimumX,
            maximumY - minimumY,
            maximumZ - minimumZ
        )
    }

    public mutating func record(
        worldFromAnchor: Matrix4x4F,
        geometry: MeshGeometryPayload
    ) {
        anchorCount += 1
        vertexCount += geometry.vertices.count
        faceCount += geometry.faceCount
        if let classifications = geometry.faceClassifications {
            for raw in classifications {
                faceClassificationCounts[Int(raw), default: 0] += 1
            }
        }
        guard let bounds = localBounds(of: geometry.vertices) else {
            return
        }
        // Transform the local AABB's 8 corners into world space.
        // Matrix4x4F is column-major: columns 0-2 are the rotation
        // basis and column 3 is translation.
        let m = worldFromAnchor.values
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let worldX =
                        m[0] * x + m[4] * y + m[8] * z + m[12]
                    let worldY =
                        m[1] * x + m[5] * y + m[9] * z + m[13]
                    let worldZ =
                        m[2] * x + m[6] * y + m[10] * z + m[14]
                    accumulate(
                        x: Double(worldX), y: Double(worldY),
                        z: Double(worldZ)
                    )
                }
            }
        }
    }

    private mutating func accumulate(x: Double, y: Double, z: Double) {
        guard x.isFinite, y.isFinite, z.isFinite else { return }
        minimumX = min(minimumX ?? x, x)
        maximumX = max(maximumX ?? x, x)
        minimumY = min(minimumY ?? y, y)
        maximumY = max(maximumY ?? y, y)
        minimumZ = min(minimumZ ?? z, z)
        maximumZ = max(maximumZ ?? z, z)
    }

    private func localBounds(
        of vertices: [Float3]
    ) -> (min: Float3, max: Float3)? {
        guard let first = vertices.first else { return nil }
        var minimum = first
        var maximum = first
        for vertex in vertices {
            guard vertex.x.isFinite, vertex.y.isFinite,
                  vertex.z.isFinite
            else { continue }
            minimum = Float3(
                min(minimum.x, vertex.x),
                min(minimum.y, vertex.y),
                min(minimum.z, vertex.z)
            )
            maximum = Float3(
                max(maximum.x, vertex.x),
                max(maximum.y, vertex.y),
                max(maximum.z, vertex.z)
            )
        }
        return (minimum, maximum)
    }
}

public enum RoomPlanMeshConsistencyStatus: String, Sendable, Equatable,
    Codable
{
    case analyzed
    case meshEvidenceAbsent = "mesh_evidence_absent"
    case roomPlanSummaryAbsent = "roomplan_summary_absent"
    /// Mesh or RoomPlan evidence exists but they do not share a
    /// coordinate authority, so no comparison was possible.
    case authorityUnshared = "authority_unshared"
}

public struct RoomPlanMeshConsistencyReport: Sendable, Equatable, Codable {
    /// Extent residuals beyond this distance are reported as
    /// discrepant. Advisory only.
    public static let advisoryExtentToleranceMeters = 0.25

    public let status: RoomPlanMeshConsistencyStatus
    public let toleranceMeters: Double
    public let meshWorldExtentMeters: [String: Double]?
    public let roomPlanExtentMeters: [String: Double]?
    public let extentResidualMeters: [String: Double]?
    public let discrepantAxes: [String]
    /// Mesh faces classified as floor/wall/ceiling — support evidence
    /// for the RoomPlan shell existing at the observed scale.
    public let floorFaceCount: Int
    public let wallFaceCount: Int
    public let ceilingFaceCount: Int


    public init(
        status: RoomPlanMeshConsistencyStatus,
        toleranceMeters: Double,
        meshWorldExtentMeters: [String: Double]?,
        roomPlanExtentMeters: [String: Double]?,
        extentResidualMeters: [String: Double]?,
        discrepantAxes: [String],
        floorFaceCount: Int,
        wallFaceCount: Int,
        ceilingFaceCount: Int
    ) {
        self.status = status
        self.toleranceMeters = toleranceMeters
        self.meshWorldExtentMeters = meshWorldExtentMeters
        self.roomPlanExtentMeters = roomPlanExtentMeters
        self.extentResidualMeters = extentResidualMeters
        self.discrepantAxes = discrepantAxes
        self.floorFaceCount = floorFaceCount
        self.wallFaceCount = wallFaceCount
        self.ceilingFaceCount = ceilingFaceCount
    }


    enum CodingKeys: String, CodingKey {
        case status
        case toleranceMeters = "tolerance_meters"
        case meshWorldExtentMeters = "mesh_world_extent_meters"
        case roomPlanExtentMeters = "roomplan_extent_meters"
        case extentResidualMeters = "extent_residual_meters"
        case discrepantAxes = "discrepant_axes"
        case floorFaceCount = "floor_face_count"
        case wallFaceCount = "wall_face_count"
        case ceilingFaceCount = "ceiling_face_count"
    }
}

/// Advisory RoomPlan-vs-mesh extent/scale comparison (#277). Both
/// inputs come from the same capture session and coordinate space, so
/// the comparison only runs on same-authority evidence. Nothing is
/// fused or rewritten; "unknown" surfaces as an absent section, never
/// as a conflict.
public enum RoomPlanMeshConsistencyAnalyzer {
    // ARMeshClassification raw values.
    private static let wallClassification = 1
    private static let floorClassification = 2
    private static let ceilingClassification = 3

    public static func analyze(
        meshProfile: MeshGeometryProfile,
        roomMetadata: CapturedRoomMetadataDocument?,
        meshCoordinateSpaceID: CoordinateSpaceID?,
        roomPlanCoordinateSpaceID: CoordinateSpaceID?,
        toleranceMeters: Double =
            RoomPlanMeshConsistencyReport.advisoryExtentToleranceMeters
    ) -> RoomPlanMeshConsistencyReport {
        guard !meshProfile.isEmpty, meshProfile.worldExtentMeters != nil
        else {
            return report(
                .meshEvidenceAbsent, tolerance: toleranceMeters,
                mesh: meshProfile
            )
        }
        guard let roomMetadata,
              let dimensions = roomMetadata.summary?.dimensionsMeters
        else {
            return report(
                .roomPlanSummaryAbsent, tolerance: toleranceMeters,
                mesh: meshProfile
            )
        }
        guard let meshSpace = meshCoordinateSpaceID,
              let roomSpace = roomPlanCoordinateSpaceID,
              meshSpace == roomSpace
        else {
            return report(
                .authorityUnshared, tolerance: toleranceMeters,
                mesh: meshProfile
            )
        }

        let meshExtent = meshProfile.worldExtentMeters!
        let roomExtent: [String: Double] = [
            "x": dimensions.xMeters,
            "y": dimensions.yMeters,
            "z": dimensions.zMeters,
        ]
        let meshDict: [String: Double] = [
            "x": meshExtent.x, "y": meshExtent.y, "z": meshExtent.z,
        ]
        var residuals: [String: Double] = [:]
        var discrepant: [String] = []
        for axis in ["x", "y", "z"] {
            let residual = abs(meshDict[axis]! - roomExtent[axis]!)
            residuals[axis] = residual
            if residual > toleranceMeters {
                discrepant.append(axis)
            }
        }
        return RoomPlanMeshConsistencyReport(
            status: .analyzed,
            toleranceMeters: toleranceMeters,
            meshWorldExtentMeters: meshDict,
            roomPlanExtentMeters: roomExtent,
            extentResidualMeters: residuals,
            discrepantAxes: discrepant,
            floorFaceCount: meshProfile.faceClassificationCounts[
                floorClassification
            ] ?? 0,
            wallFaceCount: meshProfile.faceClassificationCounts[
                wallClassification
            ] ?? 0,
            ceilingFaceCount: meshProfile.faceClassificationCounts[
                ceilingClassification
            ] ?? 0
        )
    }

    private static func report(
        _ status: RoomPlanMeshConsistencyStatus,
        tolerance: Double,
        mesh: MeshGeometryProfile
    ) -> RoomPlanMeshConsistencyReport {
        RoomPlanMeshConsistencyReport(
            status: status,
            toleranceMeters: tolerance,
            meshWorldExtentMeters: nil,
            roomPlanExtentMeters: nil,
            extentResidualMeters: nil,
            discrepantAxes: [],
            floorFaceCount: mesh.faceClassificationCounts[
                floorClassification
            ] ?? 0,
            wallFaceCount: mesh.faceClassificationCounts[
                wallClassification
            ] ?? 0,
            ceilingFaceCount: mesh.faceClassificationCounts[
                ceilingClassification
            ] ?? 0
        )
    }
}
