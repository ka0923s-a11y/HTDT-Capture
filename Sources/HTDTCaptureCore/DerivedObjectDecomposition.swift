import Foundation

public enum DerivedObjectDecompositionState: String, Codable, Sendable, Equatable {
    case resolved
    case possibleMultipleComponents = "possible_multiple_components"
    case unresolvedDecomposition = "unresolved_decomposition"
}

public struct DerivedVerticalExtent: Codable, Sendable, Equatable {
    public let minY: Double
    public let maxY: Double
    public let centroidY: Double
    public let verticalExtent: Double

    public init(minY: Double, maxY: Double, centroidY: Double) {
        self.minY = minY
        self.maxY = maxY
        self.centroidY = centroidY
        self.verticalExtent = max(0, maxY - minY)
    }
}

public struct DerivedObjectComponentCandidate: Codable, Sendable, Equatable {
    public let id: String
    public let observation: DerivedShapeObservation
    public let verticalExtent: DerivedVerticalExtent?
    public let pointCount: Int
    public let heightOrder: Int

    public init(
        id: String,
        observation: DerivedShapeObservation,
        verticalExtent: DerivedVerticalExtent?,
        pointCount: Int,
        heightOrder: Int
    ) {
        self.id = id
        self.observation = observation
        self.verticalExtent = verticalExtent
        self.pointCount = pointCount
        self.heightOrder = heightOrder
    }
}

public enum DerivedObjectSupportRelationKind: String, Codable, Sendable, Equatable {
    case supports
}

public struct DerivedObjectSupportRelation: Codable, Sendable, Equatable {
    public let lowerComponentID: String
    public let upperComponentID: String
    public let kind: DerivedObjectSupportRelationKind
    public let verticalGapMeters: Double
    public let horizontalOverlapRatio: Double

    public init(
        lowerComponentID: String,
        upperComponentID: String,
        kind: DerivedObjectSupportRelationKind = .supports,
        verticalGapMeters: Double,
        horizontalOverlapRatio: Double
    ) {
        self.lowerComponentID = lowerComponentID
        self.upperComponentID = upperComponentID
        self.kind = kind
        self.verticalGapMeters = verticalGapMeters
        self.horizontalOverlapRatio = horizontalOverlapRatio
    }
}

public enum DerivedObjectReobservationReason: String, Codable, Sendable, Equatable {
    case insufficientVerticalEvidence = "insufficient_vertical_evidence"
    case ambiguousDecomposition = "ambiguous_decomposition"
    case boundedAnalysisLimit = "bounded_analysis_limit"
}

public struct DerivedObjectReobservationAdvisory: Codable, Sendable, Equatable {
    public let reason: DerivedObjectReobservationReason
    public let region: DerivedObservationRegion?

    public init(
        reason: DerivedObjectReobservationReason,
        region: DerivedObservationRegion? = nil
    ) {
        self.reason = reason
        self.region = region
    }
}

public struct DerivedObjectDecomposition: Codable, Sendable, Equatable {
    public let state: DerivedObjectDecompositionState
    public let components: [DerivedObjectComponentCandidate]
    public let supportRelations: [DerivedObjectSupportRelation]
    public let unassignedPointCount: Int
    public let inputWasCapped: Bool
    public let reobservationAdvisory: DerivedObjectReobservationAdvisory?

    public init(
        state: DerivedObjectDecompositionState,
        components: [DerivedObjectComponentCandidate],
        supportRelations: [DerivedObjectSupportRelation] = [],
        unassignedPointCount: Int = 0,
        inputWasCapped: Bool = false,
        reobservationAdvisory: DerivedObjectReobservationAdvisory? = nil
    ) {
        self.state = state
        self.components = components
        self.supportRelations = supportRelations
        self.unassignedPointCount = unassignedPointCount
        self.inputWasCapped = inputWasCapped
        self.reobservationAdvisory = reobservationAdvisory
    }

    public static let empty = DerivedObjectDecomposition(
        state: .unresolvedDecomposition,
        components: []
    )
}

public struct DerivedObjectDecompositionConfiguration: Sendable, Equatable {
    public let maxHorizontalLinkMeters: Double
    public let maxVerticalLinkMeters: Double
    public let sameEvidenceHorizontalBonusMeters: Double
    public let minimumCoreNeighborCount: Int
    public let minimumComponentPointCount: Int
    public let maximumInputPointCount: Int
    public let maximumComponentCount: Int
    public let ambiguousNoiseFraction: Double
    public let supportMaximumGapMeters: Double
    public let supportMinimumOverlapRatio: Double

    public init(
        maxHorizontalLinkMeters: Double = 0.22,
        maxVerticalLinkMeters: Double = 0.16,
        sameEvidenceHorizontalBonusMeters: Double = 0.06,
        minimumCoreNeighborCount: Int = 4,
        minimumComponentPointCount: Int = 8,
        maximumInputPointCount: Int = 512,
        maximumComponentCount: Int = 6,
        ambiguousNoiseFraction: Double = 0.20,
        supportMaximumGapMeters: Double = 0.18,
        supportMinimumOverlapRatio: Double = 0.18
    ) {
        self.maxHorizontalLinkMeters = maxHorizontalLinkMeters
        self.maxVerticalLinkMeters = maxVerticalLinkMeters
        self.sameEvidenceHorizontalBonusMeters = sameEvidenceHorizontalBonusMeters
        self.minimumCoreNeighborCount = minimumCoreNeighborCount
        self.minimumComponentPointCount = minimumComponentPointCount
        self.maximumInputPointCount = maximumInputPointCount
        self.maximumComponentCount = maximumComponentCount
        self.ambiguousNoiseFraction = ambiguousNoiseFraction
        self.supportMaximumGapMeters = supportMaximumGapMeters
        self.supportMinimumOverlapRatio = supportMinimumOverlapRatio
    }

    public static let livePreview = DerivedObjectDecompositionConfiguration()
}

public enum DerivedObjectDecomposer {
    public static let algorithm = "htdt-derived-object-decomposition"
    public static let version = "1.0.0"

    public static func decompose(
        observation: DerivedShapeObservation,
        configuration: DerivedObjectDecompositionConfiguration = .livePreview
    ) -> DerivedObjectDecomposition {
        guard configuration.maxHorizontalLinkMeters.isFinite,
              configuration.maxHorizontalLinkMeters > 0,
              configuration.maxVerticalLinkMeters.isFinite,
              configuration.maxVerticalLinkMeters > 0,
              configuration.minimumCoreNeighborCount > 1,
              configuration.minimumComponentPointCount > 0,
              configuration.maximumInputPointCount > 0,
              configuration.maximumComponentCount > 0
        else {
            return unresolved(
                observation: observation,
                reason: .ambiguousDecomposition
            )
        }

        let ordered = observation.points
            .filter {
                $0.position.x.isFinite
                    && $0.position.y.isFinite
            }
            .sorted(by: pointLess)

        guard ordered.count >= configuration.minimumComponentPointCount else {
            return unresolved(
                observation: observation,
                reason: .insufficientVerticalEvidence
            )
        }

        let bounded = boundedSample(
            ordered,
            maximum: configuration.maximumInputPointCount
        )
        let inputWasCapped = bounded.count < ordered.count
        let points3D = bounded.filter {
            guard let y = $0.verticalY else {
                return false
            }
            return y.isFinite
        }

        let verticalCoverage =
            Double(points3D.count) / Double(max(1, bounded.count))
        guard points3D.count >= configuration.minimumComponentPointCount,
              verticalCoverage >= 0.75
        else {
            return unresolved(
                observation: DerivedShapeObservation(
                    coordinateSpaceID: observation.coordinateSpaceID,
                    points: bounded,
                    sourceEvidenceRefs: observation.sourceEvidenceRefs,
                    observationStartSeconds: observation.observationStartSeconds,
                    observationEndSeconds: observation.observationEndSeconds
                ),
                reason: .insufficientVerticalEvidence,
                inputWasCapped: inputWasCapped
            )
        }

        let neighbors = neighborGraph(
            points3D,
            configuration: configuration
        )
        let labels = densityLabels(
            neighbors: neighbors,
            minimumCoreNeighborCount:
                configuration.minimumCoreNeighborCount
        )

        let grouped = Dictionary(grouping: points3D.indices) {
            labels[$0]
        }

        var rawComponents: [[DerivedObservationPoint]] = grouped
            .filter { key, indices in
                key >= 0
                    && indices.count
                        >= configuration.minimumComponentPointCount
            }
            .map { _, indices in
                indices.map { points3D[$0] }.sorted(by: pointLess)
            }

        rawComponents.sort(by: componentLess)

        let unassignedPointCount =
            points3D.indices.filter {
                labels[$0] < 0
                    || (grouped[labels[$0]]?.count ?? 0)
                        < configuration.minimumComponentPointCount
            }.count

        guard !rawComponents.isEmpty else {
            return unresolved(
                observation: DerivedShapeObservation(
                    coordinateSpaceID: observation.coordinateSpaceID,
                    points: bounded,
                    sourceEvidenceRefs: observation.sourceEvidenceRefs,
                    observationStartSeconds: observation.observationStartSeconds,
                    observationEndSeconds: observation.observationEndSeconds
                ),
                reason: .ambiguousDecomposition,
                inputWasCapped: inputWasCapped
            )
        }

        let componentLimitExceeded =
            rawComponents.count > configuration.maximumComponentCount
        if componentLimitExceeded {
            rawComponents = Array(
                rawComponents.prefix(configuration.maximumComponentCount)
            )
        }

        let componentRecords = rawComponents.enumerated().map {
            index, componentPoints in
            let componentObservation = DerivedShapeObservation(
                coordinateSpaceID: observation.coordinateSpaceID,
                points: componentPoints,
                sourceEvidenceRefs:
                    Array(Set(componentPoints.map(\.evidenceRef))).sorted(),
                observationStartSeconds:
                    observation.observationStartSeconds,
                observationEndSeconds:
                    observation.observationEndSeconds
            )
            return DerivedObjectComponentCandidate(
                id: "component-" + String(index + 1),
                observation: componentObservation,
                verticalExtent: verticalExtent(componentPoints),
                pointCount: componentPoints.count,
                heightOrder: index
            )
        }

        let noiseFraction =
            Double(unassignedPointCount)
            / Double(max(1, points3D.count))
        let isAmbiguous =
            inputWasCapped
            || componentLimitExceeded
            || noiseFraction > configuration.ambiguousNoiseFraction

        let state: DerivedObjectDecompositionState =
            isAmbiguous
            ? .possibleMultipleComponents
            : .resolved

        let advisoryReason: DerivedObjectReobservationReason? =
            componentLimitExceeded || inputWasCapped
            ? .boundedAnalysisLimit
            : (isAmbiguous ? .ambiguousDecomposition : nil)

        return DerivedObjectDecomposition(
            state: state,
            components: componentRecords,
            supportRelations: supportRelations(
                componentRecords,
                configuration: configuration
            ),
            unassignedPointCount: unassignedPointCount,
            inputWasCapped: inputWasCapped,
            reobservationAdvisory: advisoryReason.map {
                DerivedObjectReobservationAdvisory(
                    reason: $0,
                    region: observationRegion(
                        coordinateSpaceID: observation.coordinateSpaceID,
                        points: points3D
                    )
                )
            }
        )
    }

    private static func unresolved(
        observation: DerivedShapeObservation,
        reason: DerivedObjectReobservationReason,
        inputWasCapped: Bool = false
    ) -> DerivedObjectDecomposition {
        let valid = observation.points.filter {
            $0.position.x.isFinite
                && $0.position.y.isFinite
        }
        let height = verticalExtent(valid)
        let component = valid.isEmpty
            ? []
            : [
                DerivedObjectComponentCandidate(
                    id: "component-unresolved",
                    observation: observation,
                    verticalExtent: height,
                    pointCount: valid.count,
                    heightOrder: 0
                )
            ]

        return DerivedObjectDecomposition(
            state: .unresolvedDecomposition,
            components: component,
            unassignedPointCount: valid.count,
            inputWasCapped: inputWasCapped,
            reobservationAdvisory:
                DerivedObjectReobservationAdvisory(
                    reason: reason,
                    region: observationRegion(
                        coordinateSpaceID: observation.coordinateSpaceID,
                        points: valid
                    )
                )
        )
    }

    private static func neighborGraph(
        _ points: [DerivedObservationPoint],
        configuration: DerivedObjectDecompositionConfiguration
    ) -> [[Int]] {
        var result = Array(repeating: [Int](), count: points.count)

        for firstIndex in points.indices {
            result[firstIndex].append(firstIndex)
            guard firstIndex + 1 < points.count else {
                continue
            }

            for secondIndex in (firstIndex + 1)..<points.count {
                let first = points[firstIndex]
                let second = points[secondIndex]
                guard let firstY = first.verticalY,
                      let secondY = second.verticalY
                else {
                    continue
                }

                let verticalDistance = abs(firstY - secondY)
                guard verticalDistance
                        <= configuration.maxVerticalLinkMeters
                else {
                    continue
                }

                let dx = first.position.x - second.position.x
                let dz = first.position.y - second.position.y
                let horizontalDistanceSquared = dx * dx + dz * dz
                var horizontalLimit =
                    configuration.maxHorizontalLinkMeters

                // Points backed by the same observed mesh element are stronger
                // connectivity evidence than proximity alone. This is only a
                // bounded bonus; it never overrides vertical separation.
                if first.evidenceRef == second.evidenceRef {
                    horizontalLimit +=
                        configuration.sameEvidenceHorizontalBonusMeters
                }

                if horizontalDistanceSquared
                    <= horizontalLimit * horizontalLimit
                {
                    result[firstIndex].append(secondIndex)
                    result[secondIndex].append(firstIndex)
                }
            }
        }

        return result
    }

    private static func densityLabels(
        neighbors: [[Int]],
        minimumCoreNeighborCount: Int
    ) -> [Int] {
        let unvisited = -2
        let noise = -1
        var labels = Array(repeating: unvisited, count: neighbors.count)
        var clusterID = 0

        for start in neighbors.indices {
            guard labels[start] == unvisited else {
                continue
            }

            guard neighbors[start].count >= minimumCoreNeighborCount else {
                labels[start] = noise
                continue
            }

            labels[start] = clusterID
            var queue = neighbors[start].sorted()
            var cursor = 0

            while cursor < queue.count {
                let candidate = queue[cursor]
                cursor += 1

                if labels[candidate] == noise {
                    labels[candidate] = clusterID
                }
                guard labels[candidate] == unvisited else {
                    continue
                }

                labels[candidate] = clusterID
                if neighbors[candidate].count
                    >= minimumCoreNeighborCount
                {
                    for neighbor in neighbors[candidate].sorted()
                    where !queue.contains(neighbor) {
                        queue.append(neighbor)
                    }
                }
            }

            clusterID += 1
        }

        return labels
    }

    private static func verticalExtent(
        _ points: [DerivedObservationPoint]
    ) -> DerivedVerticalExtent? {
        let heights = points.compactMap(\.verticalY).filter(\.isFinite)
        guard let minY = heights.min(),
              let maxY = heights.max(),
              !heights.isEmpty
        else {
            return nil
        }
        let centroid = heights.reduce(0, +) / Double(heights.count)
        return DerivedVerticalExtent(
            minY: minY,
            maxY: maxY,
            centroidY: centroid
        )
    }

    private static func supportRelations(
        _ components: [DerivedObjectComponentCandidate],
        configuration: DerivedObjectDecompositionConfiguration
    ) -> [DerivedObjectSupportRelation] {
        var relations: [DerivedObjectSupportRelation] = []

        for lowerIndex in components.indices {
            guard let lowerHeight =
                    components[lowerIndex].verticalExtent
            else {
                continue
            }

            for upperIndex in components.indices
            where upperIndex != lowerIndex
            {
                guard let upperHeight =
                        components[upperIndex].verticalExtent,
                      lowerHeight.centroidY < upperHeight.centroidY
                else {
                    continue
                }

                let gap = upperHeight.minY - lowerHeight.maxY
                guard gap >= -0.04,
                      gap <= configuration.supportMaximumGapMeters
                else {
                    continue
                }

                let overlap = footprintOverlapRatio(
                    components[lowerIndex].observation.points,
                    components[upperIndex].observation.points
                )
                guard overlap
                        >= configuration.supportMinimumOverlapRatio
                else {
                    continue
                }

                relations.append(
                    DerivedObjectSupportRelation(
                        lowerComponentID:
                            components[lowerIndex].id,
                        upperComponentID:
                            components[upperIndex].id,
                        verticalGapMeters: gap,
                        horizontalOverlapRatio: overlap
                    )
                )
            }
        }

        return relations.sorted {
            if $0.lowerComponentID != $1.lowerComponentID {
                return $0.lowerComponentID < $1.lowerComponentID
            }
            return $0.upperComponentID < $1.upperComponentID
        }
    }

    private static func footprintOverlapRatio(
        _ lhs: [DerivedObservationPoint],
        _ rhs: [DerivedObservationPoint]
    ) -> Double {
        guard let a = footprintBounds(lhs),
              let b = footprintBounds(rhs)
        else {
            return 0
        }

        let overlapX = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let overlapZ = max(0, min(a.maxZ, b.maxZ) - max(a.minZ, b.minZ))
        let overlapArea = overlapX * overlapZ
        let aArea = max(0, a.maxX - a.minX) * max(0, a.maxZ - a.minZ)
        let bArea = max(0, b.maxX - b.minX) * max(0, b.maxZ - b.minZ)
        let denominator = min(aArea, bArea)
        guard denominator > 0.000_1 else {
            return 0
        }
        return min(1, overlapArea / denominator)
    }

    private static func footprintBounds(
        _ points: [DerivedObservationPoint]
    ) -> FootprintBounds? {
        guard let first = points.first else {
            return nil
        }
        var minX = first.position.x
        var maxX = first.position.x
        var minZ = first.position.y
        var maxZ = first.position.y

        for point in points.dropFirst() {
            minX = min(minX, point.position.x)
            maxX = max(maxX, point.position.x)
            minZ = min(minZ, point.position.y)
            maxZ = max(maxZ, point.position.y)
        }

        return FootprintBounds(
            minX: minX,
            maxX: maxX,
            minZ: minZ,
            maxZ: maxZ
        )
    }

    private static func observationRegion(
        coordinateSpaceID: CoordinateSpaceID,
        points: [DerivedObservationPoint]
    ) -> DerivedObservationRegion? {
        let valid3D = points.compactMap {
            point -> (Double, Double, Double)? in
            guard let y = point.verticalY,
                  y.isFinite
            else {
                return nil
            }
            return (point.position.x, y, point.position.y)
        }
        guard let first = valid3D.first else {
            return nil
        }

        var minX = first.0
        var maxX = first.0
        var minY = first.1
        var maxY = first.1
        var minZ = first.2
        var maxZ = first.2
        for point in valid3D.dropFirst() {
            minX = min(minX, point.0)
            maxX = max(maxX, point.0)
            minY = min(minY, point.1)
            maxY = max(maxY, point.1)
            minZ = min(minZ, point.2)
            maxZ = max(maxZ, point.2)
        }

        return DerivedObservationRegion(
            coordinateSpaceID: coordinateSpaceID,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            minZ: minZ,
            maxZ: maxZ
        )
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

    private static func pointLess(
        _ lhs: DerivedObservationPoint,
        _ rhs: DerivedObservationPoint
    ) -> Bool {
        if lhs.position.x != rhs.position.x {
            return lhs.position.x < rhs.position.x
        }
        if lhs.position.y != rhs.position.y {
            return lhs.position.y < rhs.position.y
        }
        if lhs.verticalY != rhs.verticalY {
            return (lhs.verticalY ?? -.infinity)
                < (rhs.verticalY ?? -.infinity)
        }
        return lhs.evidenceRef < rhs.evidenceRef
    }

    private static func componentLess(
        _ lhs: [DerivedObservationPoint],
        _ rhs: [DerivedObservationPoint]
    ) -> Bool {
        let lhsHeight = verticalExtent(lhs)?.centroidY ?? -.infinity
        let rhsHeight = verticalExtent(rhs)?.centroidY ?? -.infinity
        if lhsHeight != rhsHeight {
            return lhsHeight < rhsHeight
        }
        guard let lhsFirst = lhs.first,
              let rhsFirst = rhs.first
        else {
            return lhs.count > rhs.count
        }
        return pointLess(lhsFirst, rhsFirst)
    }
}

private struct FootprintBounds {
    let minX: Double
    let maxX: Double
    let minZ: Double
    let maxZ: Double
}
