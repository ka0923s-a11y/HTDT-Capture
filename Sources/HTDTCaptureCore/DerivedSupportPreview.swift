import Foundation

public enum DerivedSupportAnalysisResolution: String, Codable, Sendable, Equatable {
    case separatedSupports = "separated_supports"
    case solidToFloor = "solid_to_floor"
    case floatingBodyUnresolved = "floating_body_unresolved"
    case insufficientHeightEvidence = "insufficient_height_evidence"
}

public enum DerivedLowerVolumeState: String, Codable, Sendable, Equatable {
    case sparseObservedSupports = "sparse_observed_supports"
    case solidToFloor = "solid_to_floor"
    case unresolved
}

public enum DerivedSupportElementKind: String, Codable, Sendable, Equatable {
    case leg
    case narrowColumn = "narrow_column"
    case pedestal
}

public enum DerivedSupportElementResolution: String, Codable, Sendable, Equatable {
    case resolved
    case uncertain
}

public struct DerivedSupportElement: Codable, Sendable, Equatable {
    public let kind: DerivedSupportElementKind
    public let center: DerivedPoint2D
    public let footprintRadius: Double
    public let minY: Double
    public let maxY: Double
    public let evidenceSupport: [String]
    public let confidence: Double
    public let resolution: DerivedSupportElementResolution

    public init(
        kind: DerivedSupportElementKind,
        center: DerivedPoint2D,
        footprintRadius: Double,
        minY: Double,
        maxY: Double,
        evidenceSupport: [String],
        confidence: Double,
        resolution: DerivedSupportElementResolution
    ) {
        self.kind = kind
        self.center = center
        self.footprintRadius = footprintRadius
        self.minY = minY
        self.maxY = maxY
        self.evidenceSupport = evidenceSupport
        self.confidence = confidence
        self.resolution = resolution
    }
}

public struct DerivedVerticalOccupancySlice: Codable, Sendable, Equatable {
    public let minY: Double
    public let maxY: Double
    public let occupiedColumnCount: Int
    public let occupancyRatioToBroadestSlice: Double
    public let evidenceSupport: [String]

    public init(
        minY: Double,
        maxY: Double,
        occupiedColumnCount: Int,
        occupancyRatioToBroadestSlice: Double,
        evidenceSupport: [String]
    ) {
        self.minY = minY
        self.maxY = maxY
        self.occupiedColumnCount = occupiedColumnCount
        self.occupancyRatioToBroadestSlice = occupancyRatioToBroadestSlice
        self.evidenceSupport = evidenceSupport
    }
}

public enum DerivedSupportAdvisoryKind: String, Codable, Sendable, Equatable {
    case observeLowerFurniture = "observe_lower_furniture"
    case observeLowerFurnitureFromAnotherAngle = "observe_lower_furniture_from_another_angle"
}

public struct DerivedSupportAdvisory: Codable, Sendable, Equatable {
    public let kind: DerivedSupportAdvisoryKind
    public let targetCenter: DerivedPoint2D?
    public let evidenceSupport: [String]

    public init(
        kind: DerivedSupportAdvisoryKind,
        targetCenter: DerivedPoint2D?,
        evidenceSupport: [String]
    ) {
        self.kind = kind
        self.targetCenter = targetCenter
        self.evidenceSupport = evidenceSupport
    }
}

public struct DerivedSupportAnalysis: Codable, Sendable, Equatable {
    public let resolution: DerivedSupportAnalysisResolution
    public let lowerVolumeState: DerivedLowerVolumeState
    public let bodyMinY: Double?
    public let bodyMaxY: Double?
    public let floorReferenceY: Double?
    public let supports: [DerivedSupportElement]
    public let verticalOccupancy: [DerivedVerticalOccupancySlice]
    public let advisories: [DerivedSupportAdvisory]
    public let sourceEvidenceRefs: [String]

    public init(
        resolution: DerivedSupportAnalysisResolution,
        lowerVolumeState: DerivedLowerVolumeState,
        bodyMinY: Double?,
        bodyMaxY: Double?,
        floorReferenceY: Double?,
        supports: [DerivedSupportElement],
        verticalOccupancy: [DerivedVerticalOccupancySlice],
        advisories: [DerivedSupportAdvisory],
        sourceEvidenceRefs: [String]
    ) {
        self.resolution = resolution
        self.lowerVolumeState = lowerVolumeState
        self.bodyMinY = bodyMinY
        self.bodyMaxY = bodyMaxY
        self.floorReferenceY = floorReferenceY
        self.supports = supports
        self.verticalOccupancy = verticalOccupancy
        self.advisories = advisories
        self.sourceEvidenceRefs = sourceEvidenceRefs
    }

    public var preservesOpenLowerVolume: Bool {
        lowerVolumeState == .sparseObservedSupports
    }
}

public enum DerivedSupportAnalyzer {
    public static let algorithm = "htdt-derived-support-analysis"
    public static let version = "1.0.0"

    public static func analyze(
        observation: DerivedShapeObservation,
        floorY: Double?,
        sliceHeightMeters: Double = 0.08,
        horizontalVoxelMeters: Double = 0.08,
        maxPoints: Int = 1_024
    ) -> DerivedSupportAnalysis {
        guard sliceHeightMeters.isFinite,
              sliceHeightMeters > 0,
              horizontalVoxelMeters.isFinite,
              horizontalVoxelMeters > 0,
              maxPoints > 0
        else {
            return insufficient(
                observation: observation,
                floorY: floorY,
                occupancy: []
            )
        }

        var points = observation.points.compactMap {
            supportPoint(from: $0)
        }
        points.sort(by: supportPointLess)
        if points.count > maxPoints {
            let stride = Double(points.count) / Double(maxPoints)
            points = (0..<maxPoints).map {
                points[Int(Double($0) * stride)]
            }
        }

        guard points.count >= 12,
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max(),
              maximumY - minimumY >= max(0.08, sliceHeightMeters)
        else {
            return insufficient(
                observation: observation,
                floorY: floorY,
                occupancy: []
            )
        }

        var cellsBySlice: [Int: Set<SupportCell>] = [:]
        var evidenceBySlice: [Int: Set<String>] = [:]
        var pointsBySlice: [Int: [SupportPoint]] = [:]

        for point in points {
            let slice = Int(floor((point.y - minimumY) / sliceHeightMeters))
            let cell = SupportCell(
                x: Int(floor(point.x / horizontalVoxelMeters)),
                z: Int(floor(point.z / horizontalVoxelMeters))
            )
            cellsBySlice[slice, default: []].insert(cell)
            evidenceBySlice[slice, default: []].insert(point.evidenceRef)
            pointsBySlice[slice, default: []].append(point)
        }

        let broadestCount = max(
            cellsBySlice.values.map(\.count).max() ?? 0,
            1
        )
        let occupancy = cellsBySlice.keys.sorted().map { slice in
            DerivedVerticalOccupancySlice(
                minY: minimumY + Double(slice) * sliceHeightMeters,
                maxY: minimumY + Double(slice + 1) * sliceHeightMeters,
                occupiedColumnCount: cellsBySlice[slice]?.count ?? 0,
                occupancyRatioToBroadestSlice:
                    Double(cellsBySlice[slice]?.count ?? 0)
                    / Double(broadestCount),
                evidenceSupport:
                    Array(evidenceBySlice[slice] ?? []).sorted()
            )
        }

        let broadThreshold = max(
            4,
            Int(ceil(Double(broadestCount) * 0.55))
        )
        let broadSlices = Set(
            cellsBySlice.compactMap { key, cells in
                cells.count >= broadThreshold ? key : nil
            }
        )
        guard var bodySlice = broadSlices.max() else {
            return insufficient(
                observation: observation,
                floorY: floorY,
                occupancy: occupancy
            )
        }

        var bodySlices: Set<Int> = [bodySlice]
        while broadSlices.contains(bodySlice - 1) {
            bodySlice -= 1
            bodySlices.insert(bodySlice)
        }

        let bodyPoints = bodySlices
            .sorted()
            .flatMap { pointsBySlice[$0] ?? [] }
        guard let bodyMinY = bodyPoints.map(\.y).min(),
              let bodyMaxY = bodyPoints.map(\.y).max()
        else {
            return insufficient(
                observation: observation,
                floorY: floorY,
                occupancy: occupancy
            )
        }

        let bodyMinX = bodyPoints.map(\.x).min() ?? 0
        let bodyMaxX = bodyPoints.map(\.x).max() ?? 0
        let bodyMinZ = bodyPoints.map(\.z).min() ?? 0
        let bodyMaxZ = bodyPoints.map(\.z).max() ?? 0
        let bodyScale = max(
            bodyMaxX - bodyMinX,
            bodyMaxZ - bodyMinZ,
            horizontalVoxelMeters * 2
        )
        let bodyCenter = DerivedPoint2D(
            x: (bodyMinX + bodyMaxX) / 2,
            y: (bodyMinZ + bodyMaxZ) / 2
        )

        if let floorY,
           floorY.isFinite,
           bodyMinY - floorY <= max(0.12, sliceHeightMeters * 1.5)
        {
            return DerivedSupportAnalysis(
                resolution: .solidToFloor,
                lowerVolumeState: .solidToFloor,
                bodyMinY: bodyMinY,
                bodyMaxY: bodyMaxY,
                floorReferenceY: floorY,
                supports: [],
                verticalOccupancy: occupancy,
                advisories: [],
                sourceEvidenceRefs: observation.sourceEvidenceRefs.sorted()
            )
        }

        let supportPoints = points.filter {
            $0.y < bodyMinY - sliceHeightMeters * 0.35
        }
        let clusters = horizontalClusters(
            supportPoints,
            maxLinkDistance:
                max(0.12, horizontalVoxelMeters * 2.0)
        )

        var provisional: [ProvisionalSupport] = []
        for cluster in clusters {
            guard cluster.count >= 3,
                  let minY = cluster.map(\.y).min(),
                  let maxY = cluster.map(\.y).max()
            else {
                continue
            }
            let verticalSpan = maxY - minY
            guard verticalSpan >= 0.04 else {
                continue
            }

            let centerX =
                cluster.reduce(0) { $0 + $1.x }
                / Double(cluster.count)
            let centerZ =
                cluster.reduce(0) { $0 + $1.z }
                / Double(cluster.count)
            let center = DerivedPoint2D(x: centerX, y: centerZ)
            let radius = cluster.map {
                hypot($0.x - centerX, $0.z - centerZ)
            }.max() ?? 0
            guard radius <= max(0.18, bodyScale * 0.32) else {
                continue
            }

            let connectionGap = bodyMinY - maxY
            guard connectionGap <= max(0.18, sliceHeightMeters * 2.5)
            else {
                continue
            }

            let countScore = min(1, Double(cluster.count) / 12.0)
            let spanScore = min(
                1,
                verticalSpan / max(0.18, bodyMinY - (floorY ?? minY))
            )
            let confidence = min(
                1,
                0.42 + 0.30 * countScore + 0.28 * spanScore
            )
            provisional.append(
                ProvisionalSupport(
                    center: center,
                    radius: max(radius, horizontalVoxelMeters * 0.35),
                    minY: minY,
                    maxY: maxY,
                    evidence:
                        Array(Set(cluster.map(\.evidenceRef))).sorted(),
                    confidence: confidence
                )
            )
        }

        provisional.sort {
            if $0.center.x != $1.center.x {
                return $0.center.x < $1.center.x
            }
            if $0.center.y != $1.center.y {
                return $0.center.y < $1.center.y
            }
            return $0.minY < $1.minY
        }

        let supports = provisional.enumerated().map { _, support in
            let kind: DerivedSupportElementKind
            if provisional.count > 1 {
                kind = .leg
            } else if support.radius > bodyScale * 0.10 {
                kind = .pedestal
            } else {
                kind = .narrowColumn
            }
            return DerivedSupportElement(
                kind: kind,
                center: support.center,
                footprintRadius: support.radius,
                minY: support.minY,
                maxY: support.maxY,
                evidenceSupport: support.evidence,
                confidence: support.confidence,
                resolution:
                    support.confidence >= 0.70
                    ? .resolved
                    : .uncertain
            )
        }

        if !supports.isEmpty {
            return DerivedSupportAnalysis(
                resolution: .separatedSupports,
                lowerVolumeState: .sparseObservedSupports,
                bodyMinY: bodyMinY,
                bodyMaxY: bodyMaxY,
                floorReferenceY: floorY,
                supports: supports,
                verticalOccupancy: occupancy,
                advisories:
                    supports.contains { $0.resolution == .uncertain }
                    ? [
                        DerivedSupportAdvisory(
                            kind:
                                .observeLowerFurnitureFromAnotherAngle,
                            targetCenter: bodyCenter,
                            evidenceSupport:
                                supports.flatMap(\.evidenceSupport)
                        )
                    ]
                    : [],
                sourceEvidenceRefs: observation.sourceEvidenceRefs.sorted()
            )
        }

        let unresolvedAdvisory = DerivedSupportAdvisory(
            kind: .observeLowerFurniture,
            targetCenter: bodyCenter,
            evidenceSupport: observation.sourceEvidenceRefs.sorted()
        )
        return DerivedSupportAnalysis(
            resolution:
                floorY == nil
                ? .insufficientHeightEvidence
                : .floatingBodyUnresolved,
            lowerVolumeState: .unresolved,
            bodyMinY: bodyMinY,
            bodyMaxY: bodyMaxY,
            floorReferenceY: floorY,
            supports: [],
            verticalOccupancy: occupancy,
            advisories: [unresolvedAdvisory],
            sourceEvidenceRefs: observation.sourceEvidenceRefs.sorted()
        )
    }

    private static func insufficient(
        observation: DerivedShapeObservation,
        floorY: Double?,
        occupancy: [DerivedVerticalOccupancySlice]
    ) -> DerivedSupportAnalysis {
        DerivedSupportAnalysis(
            resolution: .insufficientHeightEvidence,
            lowerVolumeState: .unresolved,
            bodyMinY: nil,
            bodyMaxY: nil,
            floorReferenceY: floorY,
            supports: [],
            verticalOccupancy: occupancy,
            advisories: [
                DerivedSupportAdvisory(
                    kind: .observeLowerFurnitureFromAnotherAngle,
                    targetCenter: nil,
                    evidenceSupport: observation.sourceEvidenceRefs.sorted()
                )
            ],
            sourceEvidenceRefs: observation.sourceEvidenceRefs.sorted()
        )
    }

    private static func supportPoint(
        from point: DerivedObservationPoint
    ) -> SupportPoint? {
        guard let y = point.verticalPositionMeters,
              point.position.x.isFinite,
              point.position.y.isFinite,
              y.isFinite
        else {
            return nil
        }
        return SupportPoint(
            x: point.position.x,
            y: y,
            z: point.position.y,
            evidenceRef: point.evidenceRef
        )
    }

    private static func horizontalClusters(
        _ points: [SupportPoint],
        maxLinkDistance: Double
    ) -> [[SupportPoint]] {
        guard !points.isEmpty else {
            return []
        }
        let thresholdSquared = maxLinkDistance * maxLinkDistance
        var visited = Array(repeating: false, count: points.count)
        var result: [[SupportPoint]] = []

        for start in points.indices where !visited[start] {
            var queue = [start]
            var cursor = 0
            visited[start] = true
            var cluster: [SupportPoint] = []

            while cursor < queue.count {
                let currentIndex = queue[cursor]
                cursor += 1
                let current = points[currentIndex]
                cluster.append(current)

                for candidateIndex in points.indices
                where !visited[candidateIndex]
                {
                    let candidate = points[candidateIndex]
                    let dx = current.x - candidate.x
                    let dz = current.z - candidate.z
                    if dx * dx + dz * dz <= thresholdSquared {
                        visited[candidateIndex] = true
                        queue.append(candidateIndex)
                    }
                }
            }
            result.append(cluster.sorted(by: supportPointLess))
        }

        return result
    }

    private static func supportPointLess(
        _ lhs: SupportPoint,
        _ rhs: SupportPoint
    ) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        if lhs.z != rhs.z {
            return lhs.z < rhs.z
        }
        if lhs.y != rhs.y {
            return lhs.y < rhs.y
        }
        return lhs.evidenceRef < rhs.evidenceRef
    }
}

private struct SupportCell: Hashable {
    let x: Int
    let z: Int
}

private struct SupportPoint: Sendable {
    let x: Double
    let y: Double
    let z: Double
    let evidenceRef: String
}

private struct ProvisionalSupport {
    let center: DerivedPoint2D
    let radius: Double
    let minY: Double
    let maxY: Double
    let evidence: [String]
    let confidence: Double
}
