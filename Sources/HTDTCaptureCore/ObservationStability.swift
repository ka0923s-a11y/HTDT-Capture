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

/// Geometry evidence path the scan session is actually capturing.
///
/// The tracker infers this from the observed samples rather than from an
/// assumed configuration: `hasSceneDepth` proves the session produces
/// scene-depth evidence and `activeMeshAnchorCount > 0` proves it
/// produces mesh anchors. A session whose active depth strategy is the
/// bounded scene-depth fallback never reports mesh anchors, so requiring
/// mesh support would make stability unreachable; conversely a session
/// that has produced both kinds of evidence keeps the stronger combined
/// criterion.
public enum ObservationGeometryEvidenceMode:
    String,
    Sendable,
    Equatable
{
    /// No geometry evidence has been observed in the session yet.
    case none
    /// Only scene-depth evidence has been observed (depth fallback).
    case depthOnly = "depth_only"
    /// Only mesh-anchor evidence has been observed.
    case meshOnly = "mesh_only"
    /// Both depth and mesh evidence have been observed.
    case meshAndDepth = "mesh_and_depth"
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
    public let geometryEvidenceMode: ObservationGeometryEvidenceMode

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
        recheckReason: ObservationRecheckReason?,
        geometryEvidenceMode: ObservationGeometryEvidenceMode = .none
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
        self.geometryEvidenceMode = geometryEvidenceMode
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
            recheckReason: nil,
            geometryEvidenceMode: .none
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
    private var sessionDepthEvidenceObserved = false
    private var sessionMeshEvidenceObserved = false
    private var lastDepthEvidenceTimestampSeconds: Double?
    private var lastMeshEvidenceTimestampSeconds: Double?
    /// Trailing window for the evidence path a region can still be
    /// scored against (#L2): a sensor path that stopped producing
    /// evidence longer ago than this no longer counts as active
    /// support, so a region observed late is never demanded evidence
    /// the session has already stopped capturing.
    private static let evidenceRecencyWindowSeconds: Double = 15

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
        // The active geometry evidence path is session-level metadata:
        // a sample still proves depth/mesh availability even when its
        // pose or tracking is not usable for region accumulation.
        if sample.hasSceneDepth {
            sessionDepthEvidenceObserved = true
            if sample.sessionTimestampSeconds.isFinite {
                lastDepthEvidenceTimestampSeconds =
                    sample.sessionTimestampSeconds
            }
        }
        if sample.activeMeshAnchorCount > 0 {
            sessionMeshEvidenceObserved = true
            if sample.sessionTimestampSeconds.isFinite {
                lastMeshEvidenceTimestampSeconds =
                    sample.sessionTimestampSeconds
            }
        }

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

        if Self.isWellObserved(
            region,
            geometryEvidenceMode: scoringGeometryEvidenceMode
        ) {
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
                recheckReason: nil,
                geometryEvidenceMode: geometryEvidenceMode
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
        } else if Self.isWellObserved(
                      region,
                      geometryEvidenceMode: scoringGeometryEvidenceMode
                  ),
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
                  Self.activeGeometrySupportFraction(
                      geometryEvidenceMode: scoringGeometryEvidenceMode,
                      depthFraction: depthFraction,
                      meshFraction: meshFraction
                  ) < 0.35
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
            recheckReason: recheckReason,
            geometryEvidenceMode: geometryEvidenceMode
        )
    }

    /// Geometry evidence path inferred from the samples recorded so far.
    ///
    /// Session-level provenance reported on the emitted summary: a
    /// session that produced scene depth at any point reports it, even
    /// if the path later stopped — the bundle genuinely contains that
    /// evidence. Region scoring instead uses
    /// `scoringGeometryEvidenceMode`.
    private var geometryEvidenceMode: ObservationGeometryEvidenceMode {
        switch (
            sessionMeshEvidenceObserved,
            sessionDepthEvidenceObserved
        ) {
        case (true, true):
            return .meshAndDepth
        case (true, false):
            return .meshOnly
        case (false, true):
            return .depthOnly
        case (false, false):
            return .none
        }
    }

    /// Evidence paths still live for scoring purposes: the paths the
    /// session produced within the trailing recency window. A depth or
    /// mesh path that stopped producing evidence longer ago than the
    /// window no longer counts as available support, so a region
    /// observed late is never scored against evidence the session has
    /// already stopped capturing. Samples without timestamps fall back
    /// to session-level observation rather than claiming nothing is
    /// active.
    private var scoringGeometryEvidenceMode: ObservationGeometryEvidenceMode {
        let latestEvidenceTimestamp =
            [
                lastDepthEvidenceTimestampSeconds,
                lastMeshEvidenceTimestampSeconds
            ].compactMap { $0 }.max()

        func isRecent(
            _ lastTimestamp: Double?,
            observed: Bool
        ) -> Bool {
            guard observed else { return false }
            guard let lastTimestamp,
                  let latestEvidenceTimestamp
            else {
                return true
            }
            return latestEvidenceTimestamp - lastTimestamp
                <= Self.evidenceRecencyWindowSeconds
        }

        switch (
            isRecent(
                lastMeshEvidenceTimestampSeconds,
                observed: sessionMeshEvidenceObserved
            ),
            isRecent(
                lastDepthEvidenceTimestampSeconds,
                observed: sessionDepthEvidenceObserved
            )
        ) {
        case (true, true):
            return .meshAndDepth
        case (true, false):
            return .meshOnly
        case (false, true):
            return .depthOnly
        case (false, false):
            return .none
        }
    }

    private static func isWellObserved(
        _ region: RegionEvidence,
        geometryEvidenceMode: ObservationGeometryEvidenceMode
    ) -> Bool {
        guard region.normalObservationCount >= 8,
              region.viewAngleMask.nonzeroBitCount >= 3,
              region.consistentMovementCount >= 2
        else {
            return false
        }

        switch geometryEvidenceMode {
        case .meshAndDepth:
            return region.depthSupportCount >= 4
                && region.meshSupportCount >= 4
        case .depthOnly:
            return region.depthSupportCount >= 4
        case .meshOnly:
            return region.meshSupportCount >= 4
        case .none:
            return false
        }
    }

    /// Fraction of normal observations carrying the session's active
    /// geometry evidence. A mesh+depth session is scored by the weaker of
    /// its two evidence paths, while a single-path session is scored only
    /// on the path it is actually capturing. A session with no observed
    /// geometry evidence reports zero so weak support still rechecks.
    private static func activeGeometrySupportFraction(
        geometryEvidenceMode: ObservationGeometryEvidenceMode,
        depthFraction: Double,
        meshFraction: Double
    ) -> Double {
        switch geometryEvidenceMode {
        case .meshAndDepth:
            return min(depthFraction, meshFraction)
        case .depthOnly:
            return depthFraction
        case .meshOnly:
            return meshFraction
        case .none:
            return 0
        }
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
