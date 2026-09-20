import Foundation

public enum ScanCoveragePitchBand:
    Int,
    CaseIterable,
    Sendable,
    Equatable
{
    case low = 0
    case level = 1
    case high = 2
}

public struct ScanCameraPosition: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct ScanCoverageSample: Sendable {
    public let sessionTimestampSeconds: Double
    public let yawRadians: Double
    public let pitchRadians: Double
    public let cameraPosition: ScanCameraPosition?
    public let trackingState: TrackingQualityState
    public let trackingReason: String?
    public let activeMeshAnchorCount: Int
    public let hasSceneDepth: Bool

    public init(
        sessionTimestampSeconds: Double,
        yawRadians: Double,
        pitchRadians: Double,
        cameraPosition: ScanCameraPosition? = nil,
        trackingState: TrackingQualityState,
        trackingReason: String? = nil,
        activeMeshAnchorCount: Int,
        hasSceneDepth: Bool
    ) {
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
        self.cameraPosition = cameraPosition
        self.trackingState = trackingState
        self.trackingReason = trackingReason
        self.activeMeshAnchorCount = activeMeshAnchorCount
        self.hasSceneDepth = hasSceneDepth
    }
}

public struct ScanCoverageGap: Sendable, Equatable {
    public let sectorIndex: Int
    public let pitchBand: ScanCoveragePitchBand

    public init(
        sectorIndex: Int,
        pitchBand: ScanCoveragePitchBand
    ) {
        self.sectorIndex = sectorIndex
        self.pitchBand = pitchBand
    }
}

public struct ScanCoverageSummary: Sendable {
    public let sectorCount: Int
    public let minimumSamplesPerCell: Int
    public let cellSampleCounts: [Int]
    public let referenceYawRadians: Double?
    public let currentRelativeYawRadians: Double?
    public let latestTrackingState: TrackingQualityState?
    public let latestTrackingReason: String?
    public let latestMeshAnchorCount: Int
    public let latestHasSceneDepth: Bool
    public let recommendedGap: ScanCoverageGap?

    public init(
        sectorCount: Int,
        minimumSamplesPerCell: Int,
        cellSampleCounts: [Int],
        referenceYawRadians: Double?,
        currentRelativeYawRadians: Double?,
        latestTrackingState: TrackingQualityState?,
        latestTrackingReason: String?,
        latestMeshAnchorCount: Int,
        latestHasSceneDepth: Bool,
        recommendedGap: ScanCoverageGap?
    ) {
        self.sectorCount = sectorCount
        self.minimumSamplesPerCell = minimumSamplesPerCell
        self.cellSampleCounts = cellSampleCounts
        self.referenceYawRadians = referenceYawRadians
        self.currentRelativeYawRadians = currentRelativeYawRadians
        self.latestTrackingState = latestTrackingState
        self.latestTrackingReason = latestTrackingReason
        self.latestMeshAnchorCount = latestMeshAnchorCount
        self.latestHasSceneDepth = latestHasSceneDepth
        self.recommendedGap = recommendedGap
    }

    public static var empty: ScanCoverageSummary {
        ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 0, count: 36),
            referenceYawRadians: nil,
            currentRelativeYawRadians: nil,
            latestTrackingState: nil,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 0,
            latestHasSceneDepth: false,
            recommendedGap: ScanCoverageGap(
                sectorIndex: 0,
                pitchBand: .level
            )
        )
    }

    public var totalCellCount: Int {
        sectorCount * ScanCoveragePitchBand.allCases.count
    }

    public var observedCellCount: Int {
        cellSampleCounts.reduce(into: 0) { count, samples in
            if samples >= minimumSamplesPerCell {
                count += 1
            }
        }
    }

    public var coverageFraction: Double {
        guard totalCellCount > 0 else {
            return 0
        }
        return Double(observedCellCount) / Double(totalCellCount)
    }

    public func sampleCount(
        sectorIndex: Int,
        pitchBand: ScanCoveragePitchBand
    ) -> Int {
        guard sectorIndex >= 0,
              sectorIndex < sectorCount
        else {
            return 0
        }

        let offset =
            sectorIndex * ScanCoveragePitchBand.allCases.count
            + pitchBand.rawValue
        guard cellSampleCounts.indices.contains(offset) else {
            return 0
        }
        return cellSampleCounts[offset]
    }

    public func isObserved(
        sectorIndex: Int,
        pitchBand: ScanCoveragePitchBand
    ) -> Bool {
        sampleCount(
            sectorIndex: sectorIndex,
            pitchBand: pitchBand
        ) >= minimumSamplesPerCell
    }

    public func observedPitchBandCount(
        sectorIndex: Int
    ) -> Int {
        ScanCoveragePitchBand.allCases.reduce(into: 0) {
            count,
            band in
            if isObserved(
                sectorIndex: sectorIndex,
                pitchBand: band
            ) {
                count += 1
            }
        }
    }

    public func pitchBandCoverageFraction(
        _ pitchBand: ScanCoveragePitchBand
    ) -> Double {
        guard sectorCount > 0 else {
            return 0
        }

        let observed = (0..<sectorCount).reduce(into: 0) {
            count,
            sectorIndex in
            if isObserved(
                sectorIndex: sectorIndex,
                pitchBand: pitchBand
            ) {
                count += 1
            }
        }
        return Double(observed) / Double(sectorCount)
    }
}

public struct AdvisoryScanCoverageTracker: Sendable {
    public let sectorCount: Int
    public let minimumSamplesPerCell: Int

    private var referenceYawRadians: Double?
    private var currentRelativeYawRadians: Double?
    private var cellSampleCounts: [Int]
    private var latestTrackingState: TrackingQualityState?
    private var latestTrackingReason: String?
    private var latestMeshAnchorCount = 0
    private var latestHasSceneDepth = false

    public init(
        sectorCount: Int = 12,
        minimumSamplesPerCell: Int = 2
    ) {
        precondition(sectorCount > 0)
        precondition(minimumSamplesPerCell > 0)

        self.sectorCount = sectorCount
        self.minimumSamplesPerCell = minimumSamplesPerCell
        self.cellSampleCounts = Array(
            repeating: 0,
            count:
                sectorCount
                * ScanCoveragePitchBand.allCases.count
        )
    }

    @discardableResult
    public mutating func record(
        _ sample: ScanCoverageSample
    ) -> ScanCoverageSummary {
        latestTrackingState = sample.trackingState
        latestTrackingReason = sample.trackingReason
        latestMeshAnchorCount = max(0, sample.activeMeshAnchorCount)
        latestHasSceneDepth = sample.hasSceneDepth

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
        currentRelativeYawRadians = relativeYaw

        guard sample.trackingState == .normal else {
            return summary()
        }

        let sectorIndex = sectorIndex(
            relativeYawRadians: relativeYaw
        )
        let pitchBand = Self.pitchBand(
            pitchRadians: sample.pitchRadians
        )
        let index =
            sectorIndex * ScanCoveragePitchBand.allCases.count
            + pitchBand.rawValue
        cellSampleCounts[index] += 1

        return summary()
    }

    public func summary() -> ScanCoverageSummary {
        let provisional = ScanCoverageSummary(
            sectorCount: sectorCount,
            minimumSamplesPerCell: minimumSamplesPerCell,
            cellSampleCounts: cellSampleCounts,
            referenceYawRadians: referenceYawRadians,
            currentRelativeYawRadians: currentRelativeYawRadians,
            latestTrackingState: latestTrackingState,
            latestTrackingReason: latestTrackingReason,
            latestMeshAnchorCount: latestMeshAnchorCount,
            latestHasSceneDepth: latestHasSceneDepth,
            recommendedGap: nil
        )

        return ScanCoverageSummary(
            sectorCount: provisional.sectorCount,
            minimumSamplesPerCell:
                provisional.minimumSamplesPerCell,
            cellSampleCounts: provisional.cellSampleCounts,
            referenceYawRadians: provisional.referenceYawRadians,
            currentRelativeYawRadians:
                provisional.currentRelativeYawRadians,
            latestTrackingState: provisional.latestTrackingState,
            latestTrackingReason: provisional.latestTrackingReason,
            latestMeshAnchorCount:
                provisional.latestMeshAnchorCount,
            latestHasSceneDepth:
                provisional.latestHasSceneDepth,
            recommendedGap: recommendedGap(
                from: provisional
            )
        )
    }

    private func recommendedGap(
        from summary: ScanCoverageSummary
    ) -> ScanCoverageGap? {
        guard summary.observedCellCount
                < summary.totalCellCount
        else {
            return nil
        }

        let currentSector: Int
        if let yaw = summary.currentRelativeYawRadians {
            currentSector = sectorIndex(
                relativeYawRadians: yaw
            )
        } else {
            currentSector = 0
        }

        let candidateSector = (0..<sectorCount)
            .filter {
                summary.observedPitchBandCount(
                    sectorIndex: $0
                ) < ScanCoveragePitchBand.allCases.count
            }
            .min {
                let lhsCoverage =
                    summary.observedPitchBandCount(
                        sectorIndex: $0
                    )
                let rhsCoverage =
                    summary.observedPitchBandCount(
                        sectorIndex: $1
                    )
                if lhsCoverage != rhsCoverage {
                    return lhsCoverage < rhsCoverage
                }

                let lhsDistance = circularSectorDistance(
                    from: currentSector,
                    to: $0
                )
                let rhsDistance = circularSectorDistance(
                    from: currentSector,
                    to: $1
                )
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return $0 < $1
            }

        guard let candidateSector else {
            return nil
        }

        let pitchPreference: [ScanCoveragePitchBand] = [
            .level,
            .low,
            .high,
        ]
        guard let missingBand = pitchPreference.first(where: {
            !summary.isObserved(
                sectorIndex: candidateSector,
                pitchBand: $0
            )
        }) else {
            return nil
        }

        return ScanCoverageGap(
            sectorIndex: candidateSector,
            pitchBand: missingBand
        )
    }

    private func sectorIndex(
        relativeYawRadians: Double
    ) -> Int {
        let fullTurn = 2 * Double.pi
        let width = fullTurn / Double(sectorCount)
        let shifted =
            Self.normalizePositiveRadians(
                relativeYawRadians + width / 2
            )
        return Int(floor(shifted / width)) % sectorCount
    }

    private func circularSectorDistance(
        from lhs: Int,
        to rhs: Int
    ) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, sectorCount - direct)
    }

    private static func pitchBand(
        pitchRadians: Double
    ) -> ScanCoveragePitchBand {
        let threshold = 20 * Double.pi / 180
        if pitchRadians < -threshold {
            return .low
        }
        if pitchRadians > threshold {
            return .high
        }
        return .level
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
        return remainder >= 0 ? remainder : remainder + fullTurn
    }
}
