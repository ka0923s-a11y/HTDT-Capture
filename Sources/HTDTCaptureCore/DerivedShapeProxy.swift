import Foundation

public enum DerivedShapeEvidenceKind: String, Codable, Sendable, Equatable {
    case mesh
    case sceneDepth = "scene_depth"
    case spatialObservation = "spatial_observation"
}

public struct DerivedPoint2D: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DerivedObservationPoint: Codable, Sendable, Equatable {
    public let position: DerivedPoint2D
    public let evidenceRef: String
    public let evidenceKind: DerivedShapeEvidenceKind
    public let verticalPositionMeters: Double?

    public init(
        position: DerivedPoint2D,
        evidenceRef: String,
        evidenceKind: DerivedShapeEvidenceKind,
        verticalPositionMeters: Double? = nil
    ) {
        self.position = position
        self.evidenceRef = evidenceRef
        self.evidenceKind = evidenceKind
        self.verticalPositionMeters = verticalPositionMeters
    }
}

public struct DerivedShapeObservation: Codable, Sendable, Equatable {
    public let coordinateSpaceID: CoordinateSpaceID
    public let points: [DerivedObservationPoint]
    public let sourceEvidenceRefs: [String]
    public let observationStartSeconds: Double?
    public let observationEndSeconds: Double?

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        points: [DerivedObservationPoint],
        sourceEvidenceRefs: [String]? = nil,
        observationStartSeconds: Double? = nil,
        observationEndSeconds: Double? = nil
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.points = points
        self.sourceEvidenceRefs =
            sourceEvidenceRefs
            ?? Array(Set(points.map(\.evidenceRef))).sorted()
        self.observationStartSeconds = observationStartSeconds
        self.observationEndSeconds = observationEndSeconds
    }
}

public protocol DerivedShapeObservationSource: Sendable {
    func derivedShapeObservation() throws -> DerivedShapeObservation?
}

public struct DerivedObservationRegion: Codable, Sendable, Equatable {
    public let coordinateSpaceID: CoordinateSpaceID
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double
    public let minZ: Double
    public let maxZ: Double

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double,
        minZ: Double,
        maxZ: Double
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.minX = min(minX, maxX)
        self.maxX = max(minX, maxX)
        self.minY = min(minY, maxY)
        self.maxY = max(minY, maxY)
        self.minZ = min(minZ, maxZ)
        self.maxZ = max(minZ, maxZ)
    }
}

public struct DerivedShapeFitMetrics: Codable, Sendable, Equatable {
    public let normalizedResidual: Double
    public let supportScore: Double
    public let fitScore: Double
    public let angularSupport: Double?

    public init(
        normalizedResidual: Double,
        supportScore: Double,
        fitScore: Double,
        angularSupport: Double? = nil
    ) {
        self.normalizedResidual = normalizedResidual
        self.supportScore = supportScore
        self.fitScore = fitScore
        self.angularSupport = angularSupport
    }
}

public struct DerivedOrientedRectangle: Codable, Sendable, Equatable {
    public let center: DerivedPoint2D
    public let width: Double
    public let depth: Double
    public let headingRadians: Double

    public init(
        center: DerivedPoint2D,
        width: Double,
        depth: Double,
        headingRadians: Double
    ) {
        self.center = center
        self.width = width
        self.depth = depth
        self.headingRadians = headingRadians
    }
}

public struct DerivedCircle: Codable, Sendable, Equatable {
    public let center: DerivedPoint2D
    public let radius: Double

    public init(center: DerivedPoint2D, radius: Double) {
        self.center = center
        self.radius = radius
    }
}

public struct DerivedEllipse: Codable, Sendable, Equatable {
    public let center: DerivedPoint2D
    public let semiMajorAxis: Double
    public let semiMinorAxis: Double
    public let headingRadians: Double

    public init(
        center: DerivedPoint2D,
        semiMajorAxis: Double,
        semiMinorAxis: Double,
        headingRadians: Double
    ) {
        self.center = center
        self.semiMajorAxis = semiMajorAxis
        self.semiMinorAxis = semiMinorAxis
        self.headingRadians = headingRadians
    }
}

public struct SupportedPolygonVertex: Codable, Sendable, Equatable {
    public let position: DerivedPoint2D
    public let supportEvidenceRefs: [String]

    public init(
        position: DerivedPoint2D,
        supportEvidenceRefs: [String]
    ) {
        self.position = position
        self.supportEvidenceRefs = supportEvidenceRefs
    }
}

public enum DerivedPolygonConcavityResolution:
    String,
    Codable,
    Sendable,
    Equatable
{
    case resolvedConvex = "resolved_convex"
    case resolvedConcave = "resolved_concave"
    case unresolved
}

public struct DerivedPolygon: Codable, Sendable, Equatable {
    public let vertices: [SupportedPolygonVertex]
    public let isConcave: Bool
    public let concavityResolution:
        DerivedPolygonConcavityResolution?

    public init(
        vertices: [SupportedPolygonVertex],
        isConcave: Bool,
        concavityResolution:
            DerivedPolygonConcavityResolution? = nil
    ) {
        self.vertices = vertices
        self.isConcave = isConcave
        self.concavityResolution = concavityResolution
    }
}

public enum DerivedFootprintGeometry: Codable, Sendable, Equatable {
    case orientedRectangle(DerivedOrientedRectangle)
    case circle(DerivedCircle)
    case ellipse(DerivedEllipse)
    case polygon(DerivedPolygon)
}

public enum DerivedShapeKind: String, Codable, Sendable, Equatable {
    case orientedRectangle = "oriented_rectangle"
    case circle
    case ellipse
    case polygon
}

public struct DerivedShapeCandidate: Codable, Sendable, Equatable {
    public let geometry: DerivedFootprintGeometry
    public let metrics: DerivedShapeFitMetrics

    public init(
        geometry: DerivedFootprintGeometry,
        metrics: DerivedShapeFitMetrics
    ) {
        self.geometry = geometry
        self.metrics = metrics
    }

    public var kind: DerivedShapeKind {
        switch geometry {
        case .orientedRectangle:
            return .orientedRectangle
        case .circle:
            return .circle
        case .ellipse:
            return .ellipse
        case .polygon:
            return .polygon
        }
    }
}

public enum DerivedShapeResolution: String, Codable, Sendable, Equatable {
    case resolved
    case insufficientEvidence = "insufficient_evidence"
    case ambiguousEvidence = "ambiguous_evidence"
}

public struct DerivedShapeProvenance: Codable, Sendable, Equatable {
    public let sourceEvidenceRefs: [String]
    public let sourceCoordinateSpaceID: CoordinateSpaceID
    public let derivationAlgorithm: String
    public let derivationVersion: String
    public let fitScore: Double?
    public let normalizedResidual: Double?
    public let observationStartSeconds: Double?
    public let observationEndSeconds: Double?

    public init(
        sourceEvidenceRefs: [String],
        sourceCoordinateSpaceID: CoordinateSpaceID,
        derivationAlgorithm: String,
        derivationVersion: String,
        fitScore: Double?,
        normalizedResidual: Double?,
        observationStartSeconds: Double?,
        observationEndSeconds: Double?
    ) {
        self.sourceEvidenceRefs = sourceEvidenceRefs
        self.sourceCoordinateSpaceID = sourceCoordinateSpaceID
        self.derivationAlgorithm = derivationAlgorithm
        self.derivationVersion = derivationVersion
        self.fitScore = fitScore
        self.normalizedResidual = normalizedResidual
        self.observationStartSeconds = observationStartSeconds
        self.observationEndSeconds = observationEndSeconds
    }
}

public struct DerivedShapeProxy: Codable, Sendable, Equatable {
    public let resolution: DerivedShapeResolution
    public let selected: DerivedShapeCandidate?
    public let candidates: [DerivedShapeCandidate]
    public let provenance: DerivedShapeProvenance
    public let observationSample: [DerivedObservationPoint]

    public init(
        resolution: DerivedShapeResolution,
        selected: DerivedShapeCandidate?,
        candidates: [DerivedShapeCandidate],
        provenance: DerivedShapeProvenance,
        observationSample: [DerivedObservationPoint]
    ) {
        self.resolution = resolution
        self.selected = selected
        self.candidates = candidates
        self.provenance = provenance
        self.observationSample = observationSample
    }
}

public struct DerivedWallChainProxy: Codable, Sendable, Equatable {
    public let vertices: [SupportedPolygonVertex]
    public let isClosed: Bool
    public let provenance: DerivedShapeProvenance

    public init(
        vertices: [SupportedPolygonVertex],
        isClosed: Bool,
        provenance: DerivedShapeProvenance
    ) {
        self.vertices = vertices
        self.isClosed = isClosed
        self.provenance = provenance
    }
}

public enum DerivedShapeDisagreementKind: String, Codable, Sendable, Equatable, Hashable {
    case shapeClass = "shape_class"
    case footprintExtent = "footprint_extent"
    case wallHeading = "wall_heading"
    case multiSegmentBoundary = "multi_segment_boundary"
}

public struct DerivedShapePreviewSnapshot: Codable, Sendable, Equatable {
    public let objectProxies: [DerivedShapeProxy]
    public let wallChain: DerivedWallChainProxy?
    public let supportAnalysis: DerivedSupportAnalysis?
    public let objectDecomposition: DerivedObjectDecomposition?
    public let disagreements: [DerivedShapeDisagreementKind]

    public init(
        objectProxies: [DerivedShapeProxy] = [],
        wallChain: DerivedWallChainProxy? = nil,
        supportAnalysis: DerivedSupportAnalysis? = nil,
        objectDecomposition: DerivedObjectDecomposition? = nil,
        disagreements: [DerivedShapeDisagreementKind] = []
    ) {
        self.objectProxies = objectProxies
        self.wallChain = wallChain
        self.supportAnalysis = supportAnalysis
        self.objectDecomposition = objectDecomposition
        self.disagreements = Array(Set(disagreements)).sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public static let empty = DerivedShapePreviewSnapshot()

    public var hasEvidence: Bool {
        !objectProxies.isEmpty
            || wallChain != nil
            || supportAnalysis != nil
            || objectDecomposition != nil
    }
}

public enum MeshDerivedShapeObservationError: Error, Sendable, Equatable {
    case mixedCoordinateSpaces
    case invalidVoxelSize
    case invalidMaximumPointCount
}

public enum MeshDerivedShapeObservationBuilder {
    public static func build(
        snapshots: [MeshAnchorSnapshot],
        allowedFaceClassifications: Set<UInt8>? = nil,
        region: DerivedObservationRegion? = nil,
        voxelSizeMeters: Double = 0.04,
        maxPoints: Int = 512
    ) throws -> DerivedShapeObservation? {
        guard voxelSizeMeters.isFinite, voxelSizeMeters > 0 else {
            throw MeshDerivedShapeObservationError.invalidVoxelSize
        }
        guard maxPoints > 0 else {
            throw MeshDerivedShapeObservationError.invalidMaximumPointCount
        }

        var coordinateSpaceID: CoordinateSpaceID?
        var edges: [MeshBoundaryEdgeKey: MeshBoundaryEdgeRecord] = [:]
        var fallbackPoints: [DerivedObservationPoint] = []
        var startTimestamp: Double?
        var endTimestamp: Double?

        let orderedSnapshots = snapshots.sorted {
            $0.anchorID.uuidString.lowercased()
                < $1.anchorID.uuidString.lowercased()
        }

        for snapshot in orderedSnapshots {
            if let region,
               snapshot.coordinateSpaceID != region.coordinateSpaceID
            {
                continue
            }

            if let coordinateSpaceID,
               coordinateSpaceID != snapshot.coordinateSpaceID
            {
                throw MeshDerivedShapeObservationError.mixedCoordinateSpaces
            }

            var contributed = false
            let geometry = snapshot.geometry
            let faceCount = geometry.faceCount

            for faceIndex in 0..<faceCount {
                if let allowedFaceClassifications {
                    guard let classifications = geometry.faceClassifications,
                          faceIndex < classifications.count,
                          allowedFaceClassifications.contains(
                            classifications[faceIndex]
                          )
                    else {
                        continue
                    }
                }

                let base = faceIndex * 3
                let indexA = geometry.triangleIndices[base]
                let indexB = geometry.triangleIndices[base + 1]
                let indexC = geometry.triangleIndices[base + 2]
                let pointA = worldPoint(
                    geometry.vertices[Int(indexA)],
                    transform: snapshot.worldFromAnchor
                )
                let pointB = worldPoint(
                    geometry.vertices[Int(indexB)],
                    transform: snapshot.worldFromAnchor
                )
                let pointC = worldPoint(
                    geometry.vertices[Int(indexC)],
                    transform: snapshot.worldFromAnchor
                )

                guard pointA.isFinite,
                      pointB.isFinite,
                      pointC.isFinite
                else {
                    continue
                }

                let centroid = MeshWorldPoint(
                    x: (pointA.x + pointB.x + pointC.x) / 3,
                    y: (pointA.y + pointB.y + pointC.y) / 3,
                    z: (pointA.z + pointB.z + pointC.z) / 3
                )
                if let region, !contains(region, centroid) {
                    continue
                }

                contributed = true
                let evidenceRef =
                    "mesh:"
                    + snapshot.anchorID.uuidString.lowercased()
                    + ":face:"
                    + String(faceIndex)

                let vertices: [(UInt32, MeshWorldPoint)] = [
                    (indexA, pointA),
                    (indexB, pointB),
                    (indexC, pointC),
                ]

                for (_, point) in vertices {
                    fallbackPoints.append(
                        DerivedObservationPoint(
                            position: DerivedPoint2D(
                                x: point.x,
                                y: point.z
                            ),
                            evidenceRef: evidenceRef,
                            evidenceKind: .mesh,
                            verticalPositionMeters: point.y
                        )
                    )
                }

                recordBoundaryEdge(
                    anchorID: snapshot.anchorID,
                    first: vertices[0],
                    second: vertices[1],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordBoundaryEdge(
                    anchorID: snapshot.anchorID,
                    first: vertices[1],
                    second: vertices[2],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordBoundaryEdge(
                    anchorID: snapshot.anchorID,
                    first: vertices[2],
                    second: vertices[0],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
            }

            if contributed {
                coordinateSpaceID = snapshot.coordinateSpaceID
                if let timestamp = snapshot.sessionTimestampSeconds,
                   timestamp.isFinite
                {
                    startTimestamp = min(
                        startTimestamp ?? timestamp,
                        timestamp
                    )
                    endTimestamp = max(
                        endTimestamp ?? timestamp,
                        timestamp
                    )
                }
            }
        }

        guard let coordinateSpaceID else {
            return nil
        }

        let boundaryPoints = edges
            .sorted { lhs, rhs in
                lhs.key.sortKey < rhs.key.sortKey
            }
            .filter { $0.value.count == 1 }
            .flatMap { entry in
                [
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: entry.value.first.x,
                            y: entry.value.first.z
                        ),
                        evidenceRef: entry.value.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: entry.value.first.y
                    ),
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: entry.value.second.x,
                            y: entry.value.second.z
                        ),
                        evidenceRef: entry.value.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: entry.value.second.y
                    ),
                ]
            }

        let rawPoints =
            boundaryPoints.count >= 8
            ? boundaryPoints
            : fallbackPoints

        let reduced = voxelReduce(
            rawPoints,
            voxelSizeMeters: voxelSizeMeters,
            maxPoints: maxPoints
        )
        guard !reduced.isEmpty else {
            return nil
        }

        return DerivedShapeObservation(
            coordinateSpaceID: coordinateSpaceID,
            points: reduced,
            sourceEvidenceRefs:
                Array(Set(reduced.map(\.evidenceRef))).sorted(),
            observationStartSeconds: startTimestamp,
            observationEndSeconds: endTimestamp
        )
    }

    private static func contains(
        _ region: DerivedObservationRegion,
        _ point: MeshWorldPoint
    ) -> Bool {
        point.x >= region.minX && point.x <= region.maxX
            && point.y >= region.minY && point.y <= region.maxY
            && point.z >= region.minZ && point.z <= region.maxZ
    }

    private static func worldPoint(
        _ point: Float3,
        transform: Matrix4x4F
    ) -> MeshWorldPoint {
        let m = transform.values
        let x = Double(point.x)
        let y = Double(point.y)
        let z = Double(point.z)

        return MeshWorldPoint(
            x: Double(m[0]) * x
                + Double(m[4]) * y
                + Double(m[8]) * z
                + Double(m[12]),
            y: Double(m[1]) * x
                + Double(m[5]) * y
                + Double(m[9]) * z
                + Double(m[13]),
            z: Double(m[2]) * x
                + Double(m[6]) * y
                + Double(m[10]) * z
                + Double(m[14])
        )
    }

    private static func recordBoundaryEdge(
        anchorID: UUID,
        first: (UInt32, MeshWorldPoint),
        second: (UInt32, MeshWorldPoint),
        evidenceRef: String,
        into edges: inout [MeshBoundaryEdgeKey: MeshBoundaryEdgeRecord]
    ) {
        let low = min(first.0, second.0)
        let high = max(first.0, second.0)
        let key = MeshBoundaryEdgeKey(
            anchorID: anchorID,
            lowVertexIndex: low,
            highVertexIndex: high
        )

        if var existing = edges[key] {
            existing.count += 1
            edges[key] = existing
            return
        }

        let lowPoint = first.0 == low ? first.1 : second.1
        let highPoint = first.0 == high ? first.1 : second.1
        edges[key] = MeshBoundaryEdgeRecord(
            count: 1,
            first: lowPoint,
            second: highPoint,
            evidenceRef: evidenceRef
        )
    }

    private static func voxelReduce(
        _ points: [DerivedObservationPoint],
        voxelSizeMeters: Double,
        maxPoints: Int
    ) -> [DerivedObservationPoint] {
        var cells: [DerivedVoxelKey: DerivedObservationPoint] = [:]

        for point in points {
            let key = DerivedVoxelKey(
                x: Int(floor(point.position.x / voxelSizeMeters)),
                y: Int(floor(point.position.y / voxelSizeMeters))
            )
            if let existing = cells[key] {
                if observationPointLess(point, existing) {
                    cells[key] = point
                }
            } else {
                cells[key] = point
            }
        }

        let ordered = cells.values.sorted(by: observationPointLess)
        guard ordered.count > maxPoints else {
            return ordered
        }

        let stride = Double(ordered.count) / Double(maxPoints)
        return (0..<maxPoints).map { index in
            ordered[Int(Double(index) * stride)]
        }
    }

    private static func observationPointLess(
        _ lhs: DerivedObservationPoint,
        _ rhs: DerivedObservationPoint
    ) -> Bool {
        if lhs.position.x != rhs.position.x {
            return lhs.position.x < rhs.position.x
        }
        if lhs.position.y != rhs.position.y {
            return lhs.position.y < rhs.position.y
        }
        return lhs.evidenceRef < rhs.evidenceRef
    }
}

public enum DerivedShapeProxyFitter {
    public static let algorithm = "htdt-derived-footprint-fit"
    public static let version = "1.2.0"

    public static func representativeHorizontalSliceObservation(
        from observation: DerivedShapeObservation,
        sliceHeightMeters: Double = 0.08,
        horizontalVoxelMeters: Double = 0.06,
        minimumPointCount: Int = 8
    ) -> DerivedShapeObservation {
        guard sliceHeightMeters.isFinite,
              sliceHeightMeters > 0,
              horizontalVoxelMeters.isFinite,
              horizontalVoxelMeters > 0,
              minimumPointCount > 0
        else {
            return observation
        }

        let points = observation.points.filter {
            guard let y = $0.verticalPositionMeters else {
                return false
            }
            return $0.position.x.isFinite
                && $0.position.y.isFinite
                && y.isFinite
        }
        guard points.count >= minimumPointCount else {
            return observation
        }

        struct SliceKey: Hashable {
            let value: Int
        }
        struct HorizontalCell: Hashable {
            let x: Int
            let z: Int
        }

        var pointsBySlice: [SliceKey: [DerivedObservationPoint]] = [:]
        var cellsBySlice: [SliceKey: Set<HorizontalCell>] = [:]

        for point in points {
            guard let y = point.verticalPositionMeters else {
                continue
            }
            let key = SliceKey(
                value: Int(floor(y / sliceHeightMeters))
            )
            pointsBySlice[key, default: []].append(point)
            cellsBySlice[key, default: []].insert(
                HorizontalCell(
                    x: Int(floor(point.position.x / horizontalVoxelMeters)),
                    z: Int(floor(point.position.y / horizontalVoxelMeters))
                )
            )
        }

        guard let bestKey = pointsBySlice.keys.max(by: { lhs, rhs in
            let lhsCells = cellsBySlice[lhs]?.count ?? 0
            let rhsCells = cellsBySlice[rhs]?.count ?? 0
            if lhsCells != rhsCells {
                return lhsCells < rhsCells
            }

            let lhsCount = pointsBySlice[lhs]?.count ?? 0
            let rhsCount = pointsBySlice[rhs]?.count ?? 0
            if lhsCount != rhsCount {
                return lhsCount < rhsCount
            }

            // Prefer the higher equally-supported band. Furniture tops and
            // seat/body surfaces are a better footprint authority than legs
            // or sparse lower supports.
            return lhs.value < rhs.value
        }),
        let selected = pointsBySlice[bestKey],
        selected.count >= minimumPointCount
        else {
            return observation
        }

        let ordered = selected.sorted(by: observationPointLess)
        return DerivedShapeObservation(
            coordinateSpaceID: observation.coordinateSpaceID,
            points: ordered,
            sourceEvidenceRefs:
                Array(Set(ordered.map(\.evidenceRef))).sorted(),
            observationStartSeconds:
                observation.observationStartSeconds,
            observationEndSeconds:
                observation.observationEndSeconds
        )
    }

    public static func horizontalProfileObservations(
        from observation: DerivedShapeObservation,
        sliceHeightMeters: Double = 0.08,
        horizontalVoxelMeters: Double = 0.06,
        minimumPointCount: Int = 8,
        minimumRelativeHorizontalSupport: Double = 0.45,
        minimumRelativeExtentDifference: Double = 0.14,
        maximumProfileCount: Int = 3
    ) -> [DerivedShapeObservation] {
        guard sliceHeightMeters.isFinite,
              sliceHeightMeters > 0,
              horizontalVoxelMeters.isFinite,
              horizontalVoxelMeters > 0,
              minimumPointCount > 0,
              minimumRelativeHorizontalSupport.isFinite,
              minimumRelativeHorizontalSupport > 0,
              minimumRelativeHorizontalSupport <= 1,
              minimumRelativeExtentDifference.isFinite,
              minimumRelativeExtentDifference > 0,
              maximumProfileCount > 0
        else {
            return [observation]
        }

        let points = observation.points.filter {
            guard let y = $0.verticalPositionMeters else {
                return false
            }
            return $0.position.x.isFinite
                && $0.position.y.isFinite
                && y.isFinite
        }
        guard points.count >= minimumPointCount else {
            return [observation]
        }

        struct SliceKey: Hashable {
            let value: Int
        }
        struct HorizontalCell: Hashable {
            let x: Int
            let z: Int
        }
        struct Bounds {
            let minX: Double
            let maxX: Double
            let minZ: Double
            let maxZ: Double

            var width: Double { max(0, maxX - minX) }
            var depth: Double { max(0, maxZ - minZ) }
            var centerX: Double { (minX + maxX) / 2 }
            var centerZ: Double { (minZ + maxZ) / 2 }
        }
        struct Candidate {
            let key: SliceKey
            let points: [DerivedObservationPoint]
            let cellCount: Int
            let bounds: Bounds
        }

        var pointsBySlice: [SliceKey: [DerivedObservationPoint]] = [:]
        var cellsBySlice: [SliceKey: Set<HorizontalCell>] = [:]

        for point in points {
            guard let y = point.verticalPositionMeters else {
                continue
            }
            let key = SliceKey(
                value: Int(floor(y / sliceHeightMeters))
            )
            pointsBySlice[key, default: []].append(point)
            cellsBySlice[key, default: []].insert(
                HorizontalCell(
                    x: Int(floor(point.position.x / horizontalVoxelMeters)),
                    z: Int(floor(point.position.y / horizontalVoxelMeters))
                )
            )
        }

        let bestCellCount =
            cellsBySlice.values.map(\.count).max() ?? 0
        guard bestCellCount > 0 else {
            return [observation]
        }
        let minimumCellCount = max(
            4,
            Int(
                ceil(
                    Double(bestCellCount)
                    * minimumRelativeHorizontalSupport
                )
            )
        )

        func bounds(
            _ slicePoints: [DerivedObservationPoint]
        ) -> Bounds? {
            guard let first = slicePoints.first else {
                return nil
            }
            var minX = first.position.x
            var maxX = first.position.x
            var minZ = first.position.y
            var maxZ = first.position.y
            for point in slicePoints.dropFirst() {
                minX = min(minX, point.position.x)
                maxX = max(maxX, point.position.x)
                minZ = min(minZ, point.position.y)
                maxZ = max(maxZ, point.position.y)
            }
            return Bounds(
                minX: minX,
                maxX: maxX,
                minZ: minZ,
                maxZ: maxZ
            )
        }

        var candidates: [Candidate] = []
        for key in pointsBySlice.keys {
            guard let slicePoints = pointsBySlice[key],
                  slicePoints.count >= minimumPointCount,
                  let cellCount = cellsBySlice[key]?.count,
                  cellCount >= minimumCellCount,
                  let sliceBounds = bounds(slicePoints)
            else {
                continue
            }
            candidates.append(
                Candidate(
                    key: key,
                    points: slicePoints.sorted(
                        by: observationPointLess
                    ),
                    cellCount: cellCount,
                    bounds: sliceBounds
                )
            )
        }

        candidates.sort {
            if $0.cellCount != $1.cellCount {
                return $0.cellCount > $1.cellCount
            }
            if $0.points.count != $1.points.count {
                return $0.points.count > $1.points.count
            }
            // Match the existing representative-slice behavior: when support
            // is equal, the higher furniture surface is the stronger profile.
            return $0.key.value > $1.key.value
        }

        func relativeDifference(
            _ lhs: Double,
            _ rhs: Double
        ) -> Double {
            abs(lhs - rhs) / max(max(lhs, rhs), 0.001)
        }

        func isMateriallyDifferent(
            _ lhs: Candidate,
            _ rhs: Candidate
        ) -> Bool {
            let widthDifference = relativeDifference(
                lhs.bounds.width,
                rhs.bounds.width
            )
            let depthDifference = relativeDifference(
                lhs.bounds.depth,
                rhs.bounds.depth
            )

            let referenceExtent = max(
                max(
                    max(lhs.bounds.width, lhs.bounds.depth),
                    max(rhs.bounds.width, rhs.bounds.depth)
                ),
                0.001
            )
            let centerShift = hypot(
                lhs.bounds.centerX - rhs.bounds.centerX,
                lhs.bounds.centerZ - rhs.bounds.centerZ
            ) / referenceExtent

            return widthDifference >= minimumRelativeExtentDifference
                || depthDifference >= minimumRelativeExtentDifference
                || centerShift >= minimumRelativeExtentDifference
        }

        var selected: [Candidate] = []
        for candidate in candidates {
            guard selected.count < maximumProfileCount else {
                break
            }

            if selected.isEmpty {
                selected.append(candidate)
                continue
            }

            let verticallySeparated = selected.allSatisfy {
                abs($0.key.value - candidate.key.value) >= 2
            }
            guard verticallySeparated,
                  selected.allSatisfy({
                      isMateriallyDifferent($0, candidate)
                  })
            else {
                continue
            }
            selected.append(candidate)
        }

        guard !selected.isEmpty else {
            return [representativeHorizontalSliceObservation(
                from: observation,
                sliceHeightMeters: sliceHeightMeters,
                horizontalVoxelMeters: horizontalVoxelMeters,
                minimumPointCount: minimumPointCount
            )]
        }

        return selected.map { candidate in
            DerivedShapeObservation(
                coordinateSpaceID: observation.coordinateSpaceID,
                points: candidate.points,
                sourceEvidenceRefs:
                    Array(
                        Set(candidate.points.map(\.evidenceRef))
                    ).sorted(),
                observationStartSeconds:
                    observation.observationStartSeconds,
                observationEndSeconds:
                    observation.observationEndSeconds
            )
        }
    }

    public static func boundaryObservation(
        from observation: DerivedShapeObservation,
        angularBinCount: Int = 48,
        minimumBoundaryPointCount: Int = 8
    ) -> DerivedShapeObservation {
        guard angularBinCount >= 8,
              minimumBoundaryPointCount >= 4
        else {
            return observation
        }

        let points = observation.points.filter {
            $0.position.x.isFinite && $0.position.y.isFinite
        }
        guard points.count >= minimumBoundaryPointCount else {
            return observation
        }

        let centerX =
            points.reduce(0.0) { $0 + $1.position.x }
            / Double(points.count)
        let centerY =
            points.reduce(0.0) { $0 + $1.position.y }
            / Double(points.count)

        var bins: [Int: (point: DerivedObservationPoint, radius2: Double)] = [:]
        bins.reserveCapacity(angularBinCount)

        for point in points {
            let dx = point.position.x - centerX
            let dy = point.position.y - centerY
            let radius2 = dx * dx + dy * dy
            guard radius2.isFinite, radius2 > 0 else {
                continue
            }

            var angle = atan2(dy, dx)
            if angle < 0 {
                angle += 2 * Double.pi
            }

            // Center the bins on the nominal ray directions. Without the
            // half-bin offset, numerically identical rays from multiple
            // depth rings can straddle a bin boundary and let an interior
            // sample replace the true outer boundary.
            let fullTurn = 2 * Double.pi
            let binWidth =
                fullTurn / Double(angularBinCount)
            let centeredAngle =
                (angle + binWidth / 2)
                    .truncatingRemainder(
                        dividingBy: fullTurn
                    )
            let rawIndex =
                Int(floor(centeredAngle / binWidth))
            let index = min(
                angularBinCount - 1,
                max(0, rawIndex)
            )

            if let existing = bins[index],
               existing.radius2 >= radius2
            {
                continue
            }
            bins[index] = (point, radius2)
        }

        let boundaryPoints = bins
            .sorted { $0.key < $1.key }
            .map { $0.value.point }

        guard boundaryPoints.count >= minimumBoundaryPointCount else {
            return observation
        }

        return DerivedShapeObservation(
            coordinateSpaceID: observation.coordinateSpaceID,
            points: boundaryPoints,
            sourceEvidenceRefs:
                Array(Set(boundaryPoints.map(\.evidenceRef))).sorted(),
            observationStartSeconds:
                observation.observationStartSeconds,
            observationEndSeconds:
                observation.observationEndSeconds
        )
    }

    public static func connectedComponents(
        in observation: DerivedShapeObservation,
        maxLinkDistance: Double = 0.30,
        minimumPointCount: Int = 8
    ) -> [DerivedShapeObservation] {
        guard maxLinkDistance.isFinite,
              maxLinkDistance > 0,
              minimumPointCount > 0
        else {
            return []
        }

        let points = observation.points.sorted(by: observationPointLess)
        var visited = Array(
            repeating: false,
            count: points.count
        )
        let thresholdSquared = maxLinkDistance * maxLinkDistance
        var components: [DerivedShapeObservation] = []

        for startIndex in points.indices where !visited[startIndex] {
            var queue = [startIndex]
            var cursor = 0
            visited[startIndex] = true
            var componentIndices: [Int] = []

            while cursor < queue.count {
                let currentIndex = queue[cursor]
                cursor += 1
                componentIndices.append(currentIndex)
                let current = points[currentIndex].position

                for candidateIndex in points.indices
                where !visited[candidateIndex]
                {
                    let candidate = points[candidateIndex].position
                    if distanceSquared(current, candidate)
                        <= thresholdSquared
                    {
                        visited[candidateIndex] = true
                        queue.append(candidateIndex)
                    }
                }
            }

            guard componentIndices.count >= minimumPointCount else {
                continue
            }

            let componentPoints = componentIndices
                .map { points[$0] }
                .sorted(by: observationPointLess)
            components.append(
                DerivedShapeObservation(
                    coordinateSpaceID: observation.coordinateSpaceID,
                    points: componentPoints,
                    sourceEvidenceRefs:
                        Array(
                            Set(componentPoints.map(\.evidenceRef))
                        ).sorted(),
                    observationStartSeconds:
                        observation.observationStartSeconds,
                    observationEndSeconds:
                        observation.observationEndSeconds
                )
            )
        }

        return components.sorted { lhs, rhs in
            if lhs.points.count != rhs.points.count {
                return lhs.points.count > rhs.points.count
            }
            guard let lhsFirst = lhs.points.first,
                  let rhsFirst = rhs.points.first
            else {
                return lhs.points.count > rhs.points.count
            }
            return observationPointLess(lhsFirst, rhsFirst)
        }
    }

    public static func fit(
        observation: DerivedShapeObservation
    ) -> DerivedShapeProxy {
        let points = observation.points
            .filter {
                $0.position.x.isFinite
                    && $0.position.y.isFinite
            }
            .sorted(by: observationPointLess)

        let sample = boundedSample(points, maximum: 96)
        guard points.count >= 8,
              spatialScale(points.map(\.position)) >= 0.08
        else {
            return unresolvedProxy(
                resolution: .insufficientEvidence,
                observation: observation,
                candidates: [],
                sample: sample
            )
        }

        let scale = spatialScale(points.map(\.position))
        var candidates: [DerivedShapeCandidate] = []

        if let rectangle = rectangleCandidate(
            points: points,
            scale: scale
        ) {
            candidates.append(rectangle)
        }
        if let circle = circleCandidate(
            points: points,
            scale: scale
        ) {
            candidates.append(circle)
        }
        if let ellipse = ellipseCandidate(
            points: points,
            scale: scale
        ) {
            candidates.append(ellipse)
        }
        if let polygon = polygonCandidate(
            points: points,
            scale: scale
        ) {
            candidates.append(polygon)
        }

        guard !candidates.isEmpty else {
            return unresolvedProxy(
                resolution: .insufficientEvidence,
                observation: observation,
                candidates: [],
                sample: sample
            )
        }

        let ranked = candidates.sorted {
            let lhs = selectionCost($0)
            let rhs = selectionCost($1)
            if abs(lhs - rhs) > 0.000_000_1 {
                return lhs < rhs
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }

        let footprintAngularSupport = angularSupport(
            points: points.map(\.position),
            center: meanPoint(points.map(\.position))
        )
        if footprintAngularSupport < 0.70 {
            return unresolvedProxy(
                resolution: .insufficientEvidence,
                observation: observation,
                candidates: candidates,
                sample: sample
            )
        }

        if hasCircleRectangleAmbiguity(candidates) {
            return unresolvedProxy(
                resolution: .ambiguousEvidence,
                observation: observation,
                candidates: candidates,
                sample: sample
            )
        }

        // Only apply the curved-shape preference after explicit
        // circle-vs-rectangle ambiguity has been ruled out. This preserves
        // fail-closed behavior for mixed / rounded-square evidence while
        // still allowing a well-supported smooth primitive to beat an
        // over-flexible polygon.
        if let curved = preferredCurvedCandidate(candidates) {
            return DerivedShapeProxy(
                resolution: .resolved,
                selected: curved,
                candidates: candidates,
                provenance: provenance(
                    observation: observation,
                    metrics: curved.metrics
                ),
                observationSample: sample
            )
        }

        guard let best = ranked.first,
              best.metrics.supportScore >= 0.60,
              best.metrics.normalizedResidual <= 0.085
        else {
            return unresolvedProxy(
                resolution: .insufficientEvidence,
                observation: observation,
                candidates: candidates,
                sample: sample
            )
        }

        if ranked.count > 1 {
            let margin =
                selectionCost(ranked[1]) - selectionCost(best)
            if margin < 0.004,
               best.metrics.normalizedResidual > 0.020
            {
                return unresolvedProxy(
                    resolution: .ambiguousEvidence,
                    observation: observation,
                    candidates: candidates,
                    sample: sample
                )
            }
        }

        return DerivedShapeProxy(
            resolution: .resolved,
            selected: best,
            candidates: candidates,
            provenance: provenance(
                observation: observation,
                metrics: best.metrics
            ),
            observationSample: sample
        )
    }

    public static func wallChain(
        observation: DerivedShapeObservation
    ) -> DerivedWallChainProxy? {
        let points = observation.points
            .filter {
                $0.position.x.isFinite
                    && $0.position.y.isFinite
            }
            .sorted(by: observationPointLess)
        guard points.count >= 3 else {
            return nil
        }
        let scale = spatialScale(points.map(\.position))
        guard let polygon = polygonCandidate(
            points: points,
            scale: scale
        ) else {
            return nil
        }
        guard case let .polygon(geometry) = polygon.geometry,
              geometry.vertices.count >= 3
        else {
            return nil
        }

        return DerivedWallChainProxy(
            vertices: geometry.vertices,
            isClosed: true,
            provenance: provenance(
                observation: observation,
                metrics: polygon.metrics
            )
        )
    }

    private static func unresolvedProxy(
        resolution: DerivedShapeResolution,
        observation: DerivedShapeObservation,
        candidates: [DerivedShapeCandidate],
        sample: [DerivedObservationPoint]
    ) -> DerivedShapeProxy {
        let best = candidates.min {
            selectionCost($0) < selectionCost($1)
        }
        return DerivedShapeProxy(
            resolution: resolution,
            selected: nil,
            candidates: candidates,
            provenance: provenance(
                observation: observation,
                metrics: best?.metrics
            ),
            observationSample: sample
        )
    }

    private static func provenance(
        observation: DerivedShapeObservation,
        metrics: DerivedShapeFitMetrics?
    ) -> DerivedShapeProvenance {
        DerivedShapeProvenance(
            sourceEvidenceRefs:
                observation.sourceEvidenceRefs.sorted(),
            sourceCoordinateSpaceID:
                observation.coordinateSpaceID,
            derivationAlgorithm: algorithm,
            derivationVersion: version,
            fitScore: metrics?.fitScore,
            normalizedResidual:
                metrics?.normalizedResidual,
            observationStartSeconds:
                observation.observationStartSeconds,
            observationEndSeconds:
                observation.observationEndSeconds
        )
    }

    private static func rectangleCandidate(
        points: [DerivedObservationPoint],
        scale: Double
    ) -> DerivedShapeCandidate? {
        let positions = points.map(\.position)
        let hull = convexHull(positions)
        guard hull.count >= 3 else {
            return nil
        }

        var best: (
            area: Double,
            angle: Double,
            minU: Double,
            maxU: Double,
            minV: Double,
            maxV: Double
        )?

        for index in hull.indices {
            let next = hull[(index + 1) % hull.count]
            let current = hull[index]
            let edgeX = next.x - current.x
            let edgeY = next.y - current.y
            guard hypot(edgeX, edgeY) > 0.000_001 else {
                continue
            }
            let angle = normalizeHalfTurn(atan2(edgeY, edgeX))
            let c = cos(angle)
            let s = sin(angle)
            var minU = Double.infinity
            var maxU = -Double.infinity
            var minV = Double.infinity
            var maxV = -Double.infinity

            for point in positions {
                let u = c * point.x + s * point.y
                let v = -s * point.x + c * point.y
                minU = min(minU, u)
                maxU = max(maxU, u)
                minV = min(minV, v)
                maxV = max(maxV, v)
            }

            let area = max(0, maxU - minU)
                * max(0, maxV - minV)
            if best == nil
                || area < best!.area - 0.000_000_1
                || (
                    abs(area - best!.area) <= 0.000_000_1
                    && angle < best!.angle
                )
            {
                best = (
                    area,
                    angle,
                    minU,
                    maxU,
                    minV,
                    maxV
                )
            }
        }

        guard let best else {
            return nil
        }

        let c = cos(best.angle)
        let s = sin(best.angle)
        let centerU = (best.minU + best.maxU) / 2
        let centerV = (best.minV + best.maxV) / 2
        let center = DerivedPoint2D(
            x: c * centerU - s * centerV,
            y: s * centerU + c * centerV
        )
        let width = best.maxU - best.minU
        let depth = best.maxV - best.minV
        guard width > 0.001, depth > 0.001 else {
            return nil
        }

        let rectangle = DerivedOrientedRectangle(
            center: center,
            width: width,
            depth: depth,
            headingRadians: best.angle
        )
        let metrics = fitMetrics(
            points: positions,
            scale: scale
        ) { point in
            rectangleDistance(point, rectangle)
        }

        return DerivedShapeCandidate(
            geometry: .orientedRectangle(rectangle),
            metrics: metrics
        )
    }

    private static func circleCandidate(
        points: [DerivedObservationPoint],
        scale: Double
    ) -> DerivedShapeCandidate? {
        let positions = points.map(\.position)
        let center = meanPoint(positions)
        let radii = positions.map {
            hypot($0.x - center.x, $0.y - center.y)
        }
        guard !radii.isEmpty else {
            return nil
        }
        let radius =
            radii.reduce(0, +) / Double(radii.count)
        guard radius > 0.001 else {
            return nil
        }

        let circle = DerivedCircle(
            center: center,
            radius: radius
        )
        let baseMetrics = fitMetrics(
            points: positions,
            scale: scale
        ) { point in
            abs(
                hypot(
                    point.x - center.x,
                    point.y - center.y
                ) - radius
            )
        }
        let metrics = DerivedShapeFitMetrics(
            normalizedResidual: baseMetrics.normalizedResidual,
            supportScore: baseMetrics.supportScore,
            fitScore: baseMetrics.fitScore,
            angularSupport: angularSupport(
                points: positions,
                center: center
            )
        )

        return DerivedShapeCandidate(
            geometry: .circle(circle),
            metrics: metrics
        )
    }

    private static func ellipseCandidate(
        points: [DerivedObservationPoint],
        scale: Double
    ) -> DerivedShapeCandidate? {
        let positions = points.map(\.position)
        let center = meanPoint(positions)
        guard positions.count >= 5 else {
            return nil
        }

        var xx = 0.0
        var yy = 0.0
        var xy = 0.0
        for point in positions {
            let dx = point.x - center.x
            let dy = point.y - center.y
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }
        let count = Double(positions.count)
        xx /= count
        yy /= count
        xy /= count

        var heading = 0.5 * atan2(2 * xy, xx - yy)
        let c = cos(heading)
        let s = sin(heading)
        var sumU2 = 0.0
        var sumV2 = 0.0

        for point in positions {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let u = c * dx + s * dy
            let v = -s * dx + c * dy
            sumU2 += u * u
            sumV2 += v * v
        }

        var semiA = sqrt(max(0, 2 * sumU2 / count))
        var semiB = sqrt(max(0, 2 * sumV2 / count))
        if semiB > semiA {
            swap(&semiA, &semiB)
            heading = normalizeHalfTurn(
                heading + Double.pi / 2
            )
        } else {
            heading = normalizeHalfTurn(heading)
        }

        guard semiA > 0.001, semiB > 0.001 else {
            return nil
        }

        let ellipse = DerivedEllipse(
            center: center,
            semiMajorAxis: semiA,
            semiMinorAxis: semiB,
            headingRadians: heading
        )
        let baseMetrics = fitMetrics(
            points: positions,
            scale: scale
        ) { point in
            ellipseDistance(point, ellipse)
        }
        let metrics = DerivedShapeFitMetrics(
            normalizedResidual: baseMetrics.normalizedResidual,
            supportScore: baseMetrics.supportScore,
            fitScore: baseMetrics.fitScore,
            angularSupport: angularSupport(
                points: positions,
                center: center
            )
        )

        return DerivedShapeCandidate(
            geometry: .ellipse(ellipse),
            metrics: metrics
        )
    }

    private static func polygonCandidate(
        points: [DerivedObservationPoint],
        scale: Double
    ) -> DerivedShapeCandidate? {
        let positions = points.map(\.position)
        var polygonPoints = concavePolygon(
            positions,
            scale: scale,
            maximumVertices: 12
        )
        guard polygonPoints.count >= 3 else {
            return nil
        }

        let detectedConcavity = polygonIsConcave(polygonPoints)
        let concavityResolution:
            DerivedPolygonConcavityResolution
        if detectedConcavity {
            polygonPoints = supportedConcavityPolygon(
                polygon: polygonPoints,
                points: points,
                scale: scale,
                maximumVertices: 12
            )
            if polygonIsConcave(polygonPoints) {
                concavityResolution = .resolvedConcave
            } else {
                polygonPoints = convexHull(positions)
                reduceVertexCount(
                    &polygonPoints,
                    maximumVertices: 12
                )
                concavityResolution = .unresolved
            }
        } else {
            concavityResolution = .resolvedConvex
        }

        let supportRadius = max(0.08, scale * 0.08)
        let supportedVertices = polygonPoints.map { vertex in
            SupportedPolygonVertex(
                position: vertex,
                supportEvidenceRefs:
                    nearestEvidenceRefs(
                        to: vertex,
                        points: points,
                        radius: supportRadius,
                        maximum: 4
                    )
            )
        }
        let polygon = DerivedPolygon(
            vertices: supportedVertices,
            isConcave: polygonIsConcave(polygonPoints),
            concavityResolution: concavityResolution
        )
        let metrics = fitMetrics(
            points: positions,
            scale: scale
        ) { point in
            polygonDistance(point, polygonPoints)
        }

        return DerivedShapeCandidate(
            geometry: .polygon(polygon),
            metrics: metrics
        )
    }

    private static func fitMetrics(
        points: [DerivedPoint2D],
        scale: Double,
        distance: (DerivedPoint2D) -> Double
    ) -> DerivedShapeFitMetrics {
        let safeScale = max(scale, 0.001)
        let normalized = points.map {
            max(0, distance($0)) / safeScale
        }
        let residual = sqrt(
            normalized.reduce(0) { $0 + $1 * $1 }
                / Double(max(normalized.count, 1))
        )
        let support =
            Double(normalized.filter { $0 <= 0.045 }.count)
            / Double(max(normalized.count, 1))
        let fitScore =
            max(0, 1 - min(1, residual / 0.08))
            * (0.5 + 0.5 * support)

        return DerivedShapeFitMetrics(
            normalizedResidual: residual,
            supportScore: support,
            fitScore: fitScore
        )
    }

    private static func preferredCurvedCandidate(
        _ candidates: [DerivedShapeCandidate]
    ) -> DerivedShapeCandidate? {
        let rectangle = candidates.first {
            $0.kind == .orientedRectangle
        }
        let polygon = candidates.first {
            $0.kind == .polygon
        }

        let curved = candidates.filter { candidate in
            guard candidate.kind == .circle
                    || candidate.kind == .ellipse,
                  candidate.metrics.supportScore >= 0.60,
                  candidate.metrics.normalizedResidual <= 0.052,
                  (candidate.metrics.angularSupport ?? 0) >= 0.80
            else {
                return false
            }

            // A genuinely straight-edged footprint should keep its simpler
            // straight-edge model when that fit is materially better.
            if let rectangle,
               rectangle.metrics.normalizedResidual + 0.015
                    < candidate.metrics.normalizedResidual
            {
                return false
            }

            if let polygon {
                if case let .polygon(geometry) = polygon.geometry,
                   geometry.vertices.count <= 6,
                   polygon.metrics.normalizedResidual
                        <= candidate.metrics.normalizedResidual + 0.010
                {
                    return false
                }

                // Flexible polygons will usually fit a sampled curve a little
                // better. Permit only a small residual gap; this favors a
                // credible smooth primitive without turning rounded squares,
                // polygons, or mixed circle/square evidence into circles.
                if candidate.metrics.normalizedResidual
                    > polygon.metrics.normalizedResidual + 0.020
                {
                    return false
                }
            }

            return true
        }
        guard !curved.isEmpty else {
            return nil
        }

        let circle = curved.first { $0.kind == .circle }
        let ellipse = curved.first { $0.kind == .ellipse }

        if let circle,
           let ellipse,
           case let .ellipse(ellipseGeometry) = ellipse.geometry
        {
            let axisRatio =
                ellipseGeometry.semiMajorAxis
                / max(ellipseGeometry.semiMinorAxis, 0.001)
            if axisRatio <= 1.18,
               selectionCost(circle)
                    <= selectionCost(ellipse) + 0.008
            {
                return circle
            }
        }

        return curved.min {
            let lhs = selectionCost($0)
            let rhs = selectionCost($1)
            if abs(lhs - rhs) > 0.000_000_1 {
                return lhs < rhs
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    private static func selectionCost(
        _ candidate: DerivedShapeCandidate
    ) -> Double {
        let complexityPenalty: Double
        switch candidate.geometry {
        case .circle:
            complexityPenalty = 0.008
        case .ellipse:
            complexityPenalty = 0.010
        case .orientedRectangle:
            complexityPenalty = 0.011
        case let .polygon(polygon):
            complexityPenalty =
                0.011
                + Double(max(0, polygon.vertices.count - 4))
                    * 0.001
        }

        return candidate.metrics.normalizedResidual
            + complexityPenalty
            + (1 - candidate.metrics.supportScore) * 0.018
    }

    private static func angularSupport(
        points: [DerivedPoint2D],
        center: DerivedPoint2D
    ) -> Double {
        guard points.count >= 3 else {
            return 0
        }

        let angles = points.map {
            var angle = atan2(
                $0.y - center.y,
                $0.x - center.x
            )
            if angle < 0 {
                angle += 2 * Double.pi
            }
            return angle
        }.sorted()

        guard let first = angles.first,
              let last = angles.last
        else {
            return 0
        }

        var largestGap =
            first + 2 * Double.pi - last
        for index in 1..<angles.count {
            largestGap = max(
                largestGap,
                angles[index] - angles[index - 1]
            )
        }

        return max(
            0,
            min(
                1,
                1 - largestGap / (2 * Double.pi)
            )
        )
    }

    private static func hasCircleRectangleAmbiguity(
        _ candidates: [DerivedShapeCandidate]
    ) -> Bool {
        guard let circle = candidates.first(where: {
            $0.kind == .circle
        }),
        let rectangle = candidates.first(where: {
            $0.kind == .orientedRectangle
        })
        else {
            return false
        }

        let circleCost = selectionCost(circle)
        let rectangleCost = selectionCost(rectangle)

        // Broad, strongly supported curved evidence must not be downgraded to
        // circle-vs-rectangle ambiguity merely because a bounding rectangle
        // can approximate a partial physical view. This is the common
        // multi-view round-table case. A material residual advantage is
        // required, so mixed circle/square and rounded-square evidence still
        // falls through to the fail-closed ambiguity path.
        let strongestCurved = candidates
            .filter {
                ($0.kind == .circle || $0.kind == .ellipse)
                    && $0.metrics.supportScore >= 0.60
                    && ($0.metrics.angularSupport ?? 0) >= 0.80
                    && $0.metrics.normalizedResidual <= 0.052
            }
            .min {
                $0.metrics.normalizedResidual
                    < $1.metrics.normalizedResidual
            }
        if let strongestCurved {
            let curvedAngularSupport =
                strongestCurved.metrics.angularSupport ?? 0
            let broadOccludedCurve =
                curvedAngularSupport >= 0.80
                    && curvedAngularSupport < 0.95
            let materiallyBetterCurve =
                strongestCurved.metrics.normalizedResidual + 0.008
                    < rectangle.metrics.normalizedResidual

            if broadOccludedCurve || materiallyBetterCurve {
                return false
            }
        }

        let bestResidual = min(
            circle.metrics.normalizedResidual,
            rectangle.metrics.normalizedResidual
        )
        let worstResidual = max(
            circle.metrics.normalizedResidual,
            rectangle.metrics.normalizedResidual
        )

        if let polygonCandidate = candidates.first(where: {
            $0.kind == .polygon
        }),
           case let .polygon(polygon) = polygonCandidate.geometry,
           polygon.vertices.count <= 6,
           polygonCandidate.metrics.normalizedResidual + 0.010
                < bestResidual
        {
            // A compact, strongly supported straight-edged polygon is better
            // evidence than a secondary circle-vs-rectangle ambiguity.
            return false
        }

        return circle.metrics.supportScore >= 0.35
            && rectangle.metrics.supportScore >= 0.35
            && abs(circleCost - rectangleCost) < 0.025
            && bestResidual > 0.018
            && worstResidual < 0.13
    }

    private static func rectangleDistance(
        _ point: DerivedPoint2D,
        _ rectangle: DerivedOrientedRectangle
    ) -> Double {
        let dx = point.x - rectangle.center.x
        let dy = point.y - rectangle.center.y
        let c = cos(rectangle.headingRadians)
        let s = sin(rectangle.headingRadians)
        let u = c * dx + s * dy
        let v = -s * dx + c * dy
        let halfWidth = rectangle.width / 2
        let halfDepth = rectangle.depth / 2
        return min(
            abs(abs(u) - halfWidth),
            abs(abs(v) - halfDepth)
        )
    }

    private static func ellipseDistance(
        _ point: DerivedPoint2D,
        _ ellipse: DerivedEllipse
    ) -> Double {
        let dx = point.x - ellipse.center.x
        let dy = point.y - ellipse.center.y
        let c = cos(ellipse.headingRadians)
        let s = sin(ellipse.headingRadians)
        let u = c * dx + s * dy
        let v = -s * dx + c * dy
        let normalizedRadius = sqrt(
            (u * u)
                / (
                    ellipse.semiMajorAxis
                    * ellipse.semiMajorAxis
                )
            + (v * v)
                / (
                    ellipse.semiMinorAxis
                    * ellipse.semiMinorAxis
                )
        )
        return abs(normalizedRadius - 1)
            * min(
                ellipse.semiMajorAxis,
                ellipse.semiMinorAxis
            )
    }

    private static func concavePolygon(
        _ points: [DerivedPoint2D],
        scale: Double,
        maximumVertices: Int
    ) -> [DerivedPoint2D] {
        let unique = uniquePoints(points)
        guard unique.count >= 3 else {
            return unique
        }

        var polygon = convexHull(unique)
        reduceVertexCount(
            &polygon,
            maximumVertices: maximumVertices
        )

        let threshold = max(0.025, scale * 0.04)
        while polygon.count < maximumVertices {
            var bestPoint: DerivedPoint2D?
            var bestDistance = threshold

            for point in unique {
                if polygon.contains(where: {
                    distanceSquared($0, point) < 0.000_000_01
                }) {
                    continue
                }
                let distance = polygonDistance(
                    point,
                    polygon
                )
                if distance > bestDistance + 0.000_000_1
                    || (
                        abs(distance - bestDistance)
                            <= 0.000_000_1
                        && bestPoint.map {
                            pointLess(point, $0)
                        } == true
                    )
                {
                    bestDistance = distance
                    bestPoint = point
                }
            }

            guard let bestPoint else {
                break
            }

            var insertionIndex = 0
            var nearestEdgeDistance = Double.infinity
            for index in polygon.indices {
                let next = (index + 1) % polygon.count
                let distance = pointSegmentDistance(
                    bestPoint,
                    polygon[index],
                    polygon[next]
                )
                if distance < nearestEdgeDistance {
                    nearestEdgeDistance = distance
                    insertionIndex = next
                }
            }
            polygon.insert(
                bestPoint,
                at: insertionIndex
            )
        }

        removeNearCollinearVertices(
            &polygon,
            tolerance: max(0.002, scale * 0.004)
        )
        reduceVertexCount(
            &polygon,
            maximumVertices: maximumVertices
        )
        return polygon
    }

    private static func convexHull(
        _ points: [DerivedPoint2D]
    ) -> [DerivedPoint2D] {
        let sorted = uniquePoints(points)
        guard sorted.count > 2 else {
            return sorted
        }

        var lower: [DerivedPoint2D] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(
                    lower[lower.count - 2],
                    lower[lower.count - 1],
                    point
                  ) <= 0
            {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [DerivedPoint2D] = []
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(
                    upper[upper.count - 2],
                    upper[upper.count - 1],
                    point
                  ) <= 0
            {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func uniquePoints(
        _ points: [DerivedPoint2D]
    ) -> [DerivedPoint2D] {
        let sorted = points.sorted(by: pointLess)
        var result: [DerivedPoint2D] = []
        for point in sorted {
            if let last = result.last,
               distanceSquared(last, point) < 0.000_000_000_001
            {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func reduceVertexCount(
        _ polygon: inout [DerivedPoint2D],
        maximumVertices: Int
    ) {
        while polygon.count > maximumVertices,
              polygon.count > 3
        {
            var removeIndex = 0
            var smallestArea = Double.infinity
            for index in polygon.indices {
                let previous =
                    polygon[
                        (index - 1 + polygon.count)
                        % polygon.count
                    ]
                let current = polygon[index]
                let next =
                    polygon[(index + 1) % polygon.count]
                let area = abs(cross(previous, current, next))
                if area < smallestArea {
                    smallestArea = area
                    removeIndex = index
                }
            }
            polygon.remove(at: removeIndex)
        }
    }

    private static func removeNearCollinearVertices(
        _ polygon: inout [DerivedPoint2D],
        tolerance: Double
    ) {
        var changed = true
        while changed, polygon.count > 3 {
            changed = false
            for index in polygon.indices {
                let previous =
                    polygon[
                        (index - 1 + polygon.count)
                        % polygon.count
                    ]
                let current = polygon[index]
                let next =
                    polygon[(index + 1) % polygon.count]
                if pointSegmentDistance(
                    current,
                    previous,
                    next
                ) <= tolerance
                {
                    polygon.remove(at: index)
                    changed = true
                    break
                }
            }
        }
    }

    private static func supportedConcavityPolygon(
        polygon: [DerivedPoint2D],
        points: [DerivedObservationPoint],
        scale: Double,
        maximumVertices: Int
    ) -> [DerivedPoint2D] {
        guard polygon.count >= 4 else {
            return polygon
        }

        var result = polygon
        let vertexRadius = max(0.10, scale * 0.10)
        let edgeRadius = max(0.10, scale * 0.08)
        var changed = true

        while changed, result.count > 3 {
            changed = false
            let signedArea = result.indices.reduce(0.0) {
                partial, index in
                let next = (index + 1) % result.count
                return partial
                    + result[index].x * result[next].y
                    - result[next].x * result[index].y
            }
            let orientation =
                signedArea >= 0 ? 1.0 : -1.0

            for index in result.indices {
                let previous =
                    result[
                        (index - 1 + result.count)
                        % result.count
                    ]
                let current = result[index]
                let next =
                    result[(index + 1) % result.count]
                let turn = cross(previous, current, next)
                guard turn * orientation
                    < -0.000_000_1
                else {
                    continue
                }

                if !reflexVertexIsSupported(
                    previous: previous,
                    current: current,
                    next: next,
                    points: points,
                    vertexRadius: vertexRadius,
                    edgeRadius: edgeRadius
                ) {
                    result.remove(at: index)
                    changed = true
                    break
                }
            }
        }

        removeNearCollinearVertices(
            &result,
            tolerance: max(0.002, scale * 0.004)
        )
        reduceVertexCount(
            &result,
            maximumVertices: maximumVertices
        )
        return result
    }

    private static func reflexVertexIsSupported(
        previous: DerivedPoint2D,
        current: DerivedPoint2D,
        next: DerivedPoint2D,
        points: [DerivedObservationPoint],
        vertexRadius: Double,
        edgeRadius: Double
    ) -> Bool {
        let nearbyCount = points.lazy.filter {
            hypot(
                $0.position.x - current.x,
                $0.position.y - current.y
            ) <= vertexRadius
        }.prefix(2).count
        guard nearbyCount >= 2 else {
            return false
        }

        let probes = [
            DerivedPoint2D(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            ),
            DerivedPoint2D(
                x: (current.x + next.x) / 2,
                y: (current.y + next.y) / 2
            ),
        ]

        return probes.allSatisfy { probe in
            points.contains {
                hypot(
                    $0.position.x - probe.x,
                    $0.position.y - probe.y
                ) <= edgeRadius
            }
        }
    }

    private static func polygonIsConcave(
        _ polygon: [DerivedPoint2D]
    ) -> Bool {
        guard polygon.count >= 4 else {
            return false
        }
        var sign = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let c = polygon[(index + 2) % polygon.count]
            let value = cross(a, b, c)
            if abs(value) < 0.000_000_1 {
                continue
            }
            if sign == 0 {
                sign = value
            } else if sign * value < 0 {
                return true
            }
        }
        return false
    }

    private static func polygonDistance(
        _ point: DerivedPoint2D,
        _ polygon: [DerivedPoint2D]
    ) -> Double {
        guard polygon.count >= 2 else {
            return Double.infinity
        }
        var best = Double.infinity
        for index in polygon.indices {
            let next = (index + 1) % polygon.count
            best = min(
                best,
                pointSegmentDistance(
                    point,
                    polygon[index],
                    polygon[next]
                )
            )
        }
        return best
    }

    private static func pointSegmentDistance(
        _ point: DerivedPoint2D,
        _ a: DerivedPoint2D,
        _ b: DerivedPoint2D
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.000_000_000_001 else {
            return hypot(
                point.x - a.x,
                point.y - a.y
            )
        }
        let t = max(
            0,
            min(
                1,
                (
                    (point.x - a.x) * dx
                    + (point.y - a.y) * dy
                ) / lengthSquared
            )
        )
        let projected = DerivedPoint2D(
            x: a.x + t * dx,
            y: a.y + t * dy
        )
        return hypot(
            point.x - projected.x,
            point.y - projected.y
        )
    }

    private static func nearestEvidenceRefs(
        to vertex: DerivedPoint2D,
        points: [DerivedObservationPoint],
        radius: Double,
        maximum: Int
    ) -> [String] {
        let nearby = points
            .map {
                (
                    ref: $0.evidenceRef,
                    distance:
                        hypot(
                            $0.position.x - vertex.x,
                            $0.position.y - vertex.y
                        )
                )
            }
            .filter { $0.distance <= radius }
            .sorted {
                if $0.distance != $1.distance {
                    return $0.distance < $1.distance
                }
                return $0.ref < $1.ref
            }

        var refs: [String] = []
        for item in nearby where !refs.contains(item.ref) {
            refs.append(item.ref)
            if refs.count == maximum {
                break
            }
        }

        if refs.isEmpty,
           let nearest = points.min(by: {
                let lhs =
                    distanceSquared($0.position, vertex)
                let rhs =
                    distanceSquared($1.position, vertex)
                if lhs != rhs {
                    return lhs < rhs
                }
                return $0.evidenceRef < $1.evidenceRef
           })
        {
            refs = [nearest.evidenceRef]
        }

        return refs
    }

    private static func spatialScale(
        _ points: [DerivedPoint2D]
    ) -> Double {
        guard let first = points.first else {
            return 0
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }

    private static func meanPoint(
        _ points: [DerivedPoint2D]
    ) -> DerivedPoint2D {
        let count = Double(max(points.count, 1))
        return DerivedPoint2D(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }

    private static func normalizeHalfTurn(
        _ angle: Double
    ) -> Double {
        var value = angle
        while value < -Double.pi / 2 {
            value += Double.pi
        }
        while value >= Double.pi / 2 {
            value -= Double.pi
        }
        return value
    }

    private static func cross(
        _ a: DerivedPoint2D,
        _ b: DerivedPoint2D,
        _ c: DerivedPoint2D
    ) -> Double {
        (b.x - a.x) * (c.y - a.y)
            - (b.y - a.y) * (c.x - a.x)
    }

    private static func pointLess(
        _ lhs: DerivedPoint2D,
        _ rhs: DerivedPoint2D
    ) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.y < rhs.y
    }

    private static func observationPointLess(
        _ lhs: DerivedObservationPoint,
        _ rhs: DerivedObservationPoint
    ) -> Bool {
        if pointLess(lhs.position, rhs.position) {
            return true
        }
        if lhs.position == rhs.position {
            return lhs.evidenceRef < rhs.evidenceRef
        }
        return false
    }

    private static func distanceSquared(
        _ lhs: DerivedPoint2D,
        _ rhs: DerivedPoint2D
    ) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func boundedSample(
        _ points: [DerivedObservationPoint],
        maximum: Int
    ) -> [DerivedObservationPoint] {
        guard points.count > maximum else {
            return points
        }
        let stride = Double(points.count) / Double(maximum)
        return (0..<maximum).map {
            points[Int(Double($0) * stride)]
        }
    }
}

public enum DerivedShapeDisagreementEvaluator {
    public static func evaluate(
        objectProxies: [DerivedShapeProxy],
        wallChain: DerivedWallChainProxy?
    ) -> [DerivedShapeDisagreementKind] {
        var results = Set<DerivedShapeDisagreementKind>()

        for proxy in objectProxies {
            guard let selected = proxy.selected,
                  selected.kind != .orientedRectangle,
                  let rectangle =
                    proxy.candidates.first(where: {
                        $0.kind == .orientedRectangle
                    })
            else {
                continue
            }

            let improvement =
                rectangle.metrics.normalizedResidual
                - selected.metrics.normalizedResidual
            if improvement > 0.012
                || (
                    selected.metrics.normalizedResidual < 0.05
                    && rectangle.metrics.normalizedResidual > 0.04
                )
            {
                results.insert(.shapeClass)
            }
        }

        if let wallChain {
            if wallChain.vertices.count > 4 {
                results.insert(.multiSegmentBoundary)
            }
            if hasNonOrthogonalCorner(wallChain) {
                results.insert(.wallHeading)
            }
        }

        return results.sorted {
            $0.rawValue < $1.rawValue
        }
    }

    private static func hasNonOrthogonalCorner(
        _ wallChain: DerivedWallChainProxy
    ) -> Bool {
        let points = wallChain.vertices.map(\.position)
        guard points.count >= 3 else {
            return false
        }

        for index in points.indices {
            let previous =
                points[
                    (index - 1 + points.count)
                    % points.count
                ]
            let current = points[index]
            let next =
                points[(index + 1) % points.count]

            let first = (
                x: previous.x - current.x,
                y: previous.y - current.y
            )
            let second = (
                x: next.x - current.x,
                y: next.y - current.y
            )
            let firstLength = hypot(first.x, first.y)
            let secondLength = hypot(second.x, second.y)
            guard firstLength > 0.01, secondLength > 0.01 else {
                continue
            }

            let cosine = max(
                -1,
                min(
                    1,
                    (
                        first.x * second.x
                        + first.y * second.y
                    ) / (firstLength * secondLength)
                )
            )
            let angle = acos(cosine)
            let deviation = min(
                abs(angle - Double.pi / 2),
                abs(angle - Double.pi)
            )
            if deviation > (12 * Double.pi / 180) {
                return true
            }
        }

        return false
    }
}

private struct MeshWorldPoint {
    let x: Double
    let y: Double
    let z: Double

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

private struct MeshBoundaryEdgeKey: Hashable {
    let anchorID: UUID
    let lowVertexIndex: UInt32
    let highVertexIndex: UInt32

    var sortKey: String {
        anchorID.uuidString.lowercased()
            + ":"
            + String(lowVertexIndex)
            + ":"
            + String(highVertexIndex)
    }
}

private struct MeshBoundaryEdgeRecord {
    var count: Int
    let first: MeshWorldPoint
    let second: MeshWorldPoint
    let evidenceRef: String
}

private struct DerivedVoxelKey: Hashable {
    let x: Int
    let y: Int
}
