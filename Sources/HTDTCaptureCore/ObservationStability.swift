import Foundation

public enum ObservationConfidenceState:
    String,
    Sendable,
    Equatable
{
    case provisional
    case accumulating
    case wellObserved = "well_observed"
}

public enum ObservationRecheckReason:
    String,
    Sendable,
    Equatable
{
    case supportingEvidenceWeak = "supporting_evidence_weak"
    case supportingEvidenceDropped = "supporting_evidence_dropped"
}

public struct ObservationStabilitySummary:
    Sendable,
    Equatable
{
    public let sectorCount: Int
    public let referenceYawRadians: Double?
    public let currentSectorIndex: Int?
    public let state: ObservationConfidenceState
    public let stabilityScore: Double
    public let normalObservationCount: Int
    public let viewAngleDiversityCount: Int
    public let depthSupportFraction: Double
    public let meshSupportFraction: Double
    public let movementConsistencyFraction: Double
    public let recheckReason: ObservationRecheckReason?

    public init(
        sectorCount: Int,
        referenceYawRadians: Double?,
        currentSectorIndex: Int?,
        state: ObservationConfidenceState,
        stabilityScore: Double,
        normalObservationCount: Int,
        viewAngleDiversityCount: Int,
        depthSupportFraction: Double,
        meshSupportFraction: Double,
        movementConsistencyFraction: Double,
        recheckReason: ObservationRecheckReason?
    ) {
        self.sectorCount = sectorCount
        self.referenceYawRadians = referenceYawRadians
        self.currentSectorIndex = currentSectorIndex
        self.state = state
        self.stabilityScore = stabilityScore
        self.normalObservationCount = normalObservationCount
        self.viewAngleDiversityCount = viewAngleDiversityCount
        self.depthSupportFraction = depthSupportFraction
        self.meshSupportFraction = meshSupportFraction
        self.movementConsistencyFraction = movementConsistencyFraction
        self.recheckReason = recheckReason
    }

    public static var empty: ObservationStabilitySummary {
        ObservationStabilitySummary(
            sectorCount: 12,
            referenceYawRadians: nil,
            currentSectorIndex: nil,
            state: .provisional,
            stabilityScore: 0,
            normalObservationCount: 0,
            viewAngleDiversityCount: 0,
            depthSupportFraction: 0,
            meshSupportFraction: 0,
            movementConsistencyFraction: 0,
            recheckReason: nil
        )
    }

    public var recheckSuggested: Bool {
        recheckReason != nil
    }
}

/// Ephemeral scanner guidance derived from live AR observation evidence.
///
/// This tracker deliberately does not describe whether a RoomPlan surface is
/// geometrically correct. It describes how repeatedly and diversely HTDT has
/// observed the current look direction. The result is not persisted as
/// measurement truth or promoted into the Capture Bundle schema.
public struct ObservationStabilityTracker: Sendable {
    public let sectorCount: Int

    private struct RegionEvidence: Sendable {
        var normalObservationCount = 0
        var depthSupportCount = 0
        var meshSupportCount = 0
        var viewAngleMask: UInt16 = 0
        var movementTransitionCount = 0
        var consistentMovementCount = 0
        var previousPosition: ScanCameraPosition?
        var consecutiveWeakSupportCount = 0
        var reachedWellObserved = false
    }

    private var referenceYawRadians: Double?
    private var currentSectorIndex: Int?
    private var regions: [RegionEvidence]

    public init(sectorCount: Int = 12) {
        precondition(sectorCount > 0)
        self.sectorCount = sectorCount
        self.regions = Array(
            repeating: RegionEvidence(),
            count: sectorCount
        )
    }

    @discardableResult
    public mutating func record(
        _ sample: ScanCoverageSample
    ) -> ObservationStabilitySummary {
        guard sample.yawRadians.isFinite,
              sample.pitchRadians.isFinite
        else {
            return summary()
        }

        if referenceYawRadians == nil,
           sample.trackingState == .normal
        {
            referenceYawRadians = sample.yawRadians
        }

        guard let referenceYawRadians else {
            return summary()
        }

        let relativeYaw = Self.normalizeSignedRadians(
            sample.yawRadians - referenceYawRadians
        )
        let sectorIndex = sectorIndex(
            relativeYawRadians: relativeYaw
        )
        currentSectorIndex = sectorIndex

        guard sample.trackingState == .normal else {
            return summary()
        }

        var region = regions[sectorIndex]
        region.normalObservationCount += 1

        if sample.hasSceneDepth {
            region.depthSupportCount += 1
        }
        if sample.activeMeshAnchorCount > 0 {
            region.meshSupportCount += 1
        }

        let bucket = viewAngleBucket(
            relativeYawRadians: relativeYaw,
            pitchRadians: sample.pitchRadians,
            sectorIndex: sectorIndex
        )
        region.viewAngleMask |= UInt16(1 << bucket)

        if let position = sample.cameraPosition {
            if let previous = region.previousPosition {
                let distance = Self.distance(
                    from: previous,
                    to: position
                )
                if distance.isFinite {
                    region.movementTransitionCount += 1
                    if distance >= 0.02, distance <= 0.75 {
                        region.consistentMovementCount += 1
                    }
                }
            }
            region.previousPosition = position
        }

        if !sample.hasSceneDepth,
           sample.activeMeshAnchorCount == 0
        {
            region.consecutiveWeakSupportCount += 1
        } else {
            region.consecutiveWeakSupportCount = 0
        }

        if Self.isWellObserved(region) {
            region.reachedWellObserved = true
        }

        regions[sectorIndex] = region
        return summary()
    }

    public func summary() -> ObservationStabilitySummary {
        guard let currentSectorIndex,
              regions.indices.contains(currentSectorIndex)
        else {
            return ObservationStabilitySummary(
                sectorCount: sectorCount,
                referenceYawRadians: referenceYawRadians,
                currentSectorIndex: nil,
                state: .provisional,
                stabilityScore: 0,
                normalObservationCount: 0,
                viewAngleDiversityCount: 0,
                depthSupportFraction: 0,
                meshSupportFraction: 0,
                movementConsistencyFraction: 0,
                recheckReason: nil
            )
        }

        let region = regions[currentSectorIndex]
        let normalCount = region.normalObservationCount
        let diversityCount = region.viewAngleMask.nonzeroBitCount
        let depthFraction = Self.fraction(
            region.depthSupportCount,
            normalCount
        )
        let meshFraction = Self.fraction(
            region.meshSupportCount,
            normalCount
        )
        let movementFraction = Self.fraction(
            region.consistentMovementCount,
            region.movementTransitionCount
        )

        let repeatScore = min(
            Double(normalCount) / 8.0,
            1.0
        )
        let diversityScore = min(
            Double(diversityCount) / 3.0,
            1.0
        )
        let stabilityScore =
            repeatScore * 0.25
            + diversityScore * 0.25
            + depthFraction * 0.20
            + meshFraction * 0.15
            + movementFraction * 0.15

        let state: ObservationConfidenceState
        if normalCount < 3 {
            state = .provisional
        } else if Self.isWellObserved(region),
                  stabilityScore >= 0.68
        {
            state = .wellObserved
        } else {
            state = .accumulating
        }

        let recheckReason: ObservationRecheckReason?
        if region.reachedWellObserved,
           region.consecutiveWeakSupportCount >= 6
        {
            recheckReason = .supportingEvidenceDropped
        } else if normalCount >= 10,
                  diversityCount >= 3,
                  region.consistentMovementCount >= 2,
                  (depthFraction < 0.35 || meshFraction < 0.35)
        {
            recheckReason = .supportingEvidenceWeak
        } else {
            recheckReason = nil
        }

        return ObservationStabilitySummary(
            sectorCount: sectorCount,
            referenceYawRadians: referenceYawRadians,
            currentSectorIndex: currentSectorIndex,
            state: state,
            stabilityScore: min(max(stabilityScore, 0), 1),
            normalObservationCount: normalCount,
            viewAngleDiversityCount: diversityCount,
            depthSupportFraction: depthFraction,
            meshSupportFraction: meshFraction,
            movementConsistencyFraction: movementFraction,
            recheckReason: recheckReason
        )
    }

    private static func isWellObserved(
        _ region: RegionEvidence
    ) -> Bool {
        region.normalObservationCount >= 8
        && region.viewAngleMask.nonzeroBitCount >= 3
        && region.depthSupportCount >= 4
        && region.meshSupportCount >= 4
        && region.consistentMovementCount >= 2
    }

    private func sectorIndex(
        relativeYawRadians: Double
    ) -> Int {
        let fullTurn = 2 * Double.pi
        let width = fullTurn / Double(sectorCount)
        let shifted = Self.normalizePositiveRadians(
            relativeYawRadians + width / 2
        )
        return Int(floor(shifted / width)) % sectorCount
    }

    private func viewAngleBucket(
        relativeYawRadians: Double,
        pitchRadians: Double,
        sectorIndex: Int
    ) -> Int {
        let fullTurn = 2 * Double.pi
        let width = fullTurn / Double(sectorCount)
        var center = Double(sectorIndex) * width
        if center > Double.pi {
            center -= fullTurn
        }
        let offset = Self.normalizeSignedRadians(
            relativeYawRadians - center
        )

        let horizontalBand: Int
        if offset < -width / 6 {
            horizontalBand = 0
        } else if offset > width / 6 {
            horizontalBand = 2
        } else {
            horizontalBand = 1
        }

        let pitchThreshold = 20 * Double.pi / 180
        let verticalBand: Int
        if pitchRadians < -pitchThreshold {
            verticalBand = 0
        } else if pitchRadians > pitchThreshold {
            verticalBand = 2
        } else {
            verticalBand = 1
        }

        return verticalBand * 3 + horizontalBand
    }

    private static func distance(
        from lhs: ScanCameraPosition,
        to rhs: ScanCameraPosition
    ) -> Double {
        let dx = rhs.x - lhs.x
        let dy = rhs.y - lhs.y
        let dz = rhs.z - lhs.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static func fraction(
        _ numerator: Int,
        _ denominator: Int
    ) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return min(
            max(
                Double(numerator) / Double(denominator),
                0
            ),
            1
        )
    }

    private static func normalizeSignedRadians(
        _ value: Double
    ) -> Double {
        let fullTurn = 2 * Double.pi
        var normalized = value.truncatingRemainder(
            dividingBy: fullTurn
        )
        if normalized <= -Double.pi {
            normalized += fullTurn
        } else if normalized > Double.pi {
            normalized -= fullTurn
        }
        return normalized
    }

    private static func normalizePositiveRadians(
        _ value: Double
    ) -> Double {
        let fullTurn = 2 * Double.pi
        let remainder = value.truncatingRemainder(
            dividingBy: fullTurn
        )
        return remainder >= 0
            ? remainder
            : remainder + fullTurn
    }
}
