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

public struct ScanGuidanceConfiguration:
    Sendable,
    Equatable
{
    public let pitchBandThresholdRadians: Double
    public let lowTargetPitchRadians: Double
    public let highTargetPitchRadians: Double
    public let alignedYawToleranceRadians: Double
    public let alignedPitchToleranceRadians: Double
    public let minimumTargetHoldSeconds: Double

    public init(
        pitchBandThresholdRadians: Double =
            20 * Double.pi / 180,
        lowTargetPitchRadians: Double =
            -35 * Double.pi / 180,
        highTargetPitchRadians: Double =
            35 * Double.pi / 180,
        alignedYawToleranceRadians: Double =
            12 * Double.pi / 180,
        alignedPitchToleranceRadians: Double =
            10 * Double.pi / 180,
        minimumTargetHoldSeconds: Double = 1.5
    ) {
        precondition(
            pitchBandThresholdRadians.isFinite
                && pitchBandThresholdRadians > 0
        )
        precondition(
            lowTargetPitchRadians.isFinite
                && lowTargetPitchRadians
                    < -pitchBandThresholdRadians
        )
        precondition(
            highTargetPitchRadians.isFinite
                && highTargetPitchRadians
                    > pitchBandThresholdRadians
        )
        precondition(
            alignedYawToleranceRadians.isFinite
                && alignedYawToleranceRadians >= 0
        )
        precondition(
            alignedPitchToleranceRadians.isFinite
                && alignedPitchToleranceRadians >= 0
        )
        precondition(
            minimumTargetHoldSeconds.isFinite
                && minimumTargetHoldSeconds >= 0
        )

        self.pitchBandThresholdRadians =
            pitchBandThresholdRadians
        self.lowTargetPitchRadians =
            lowTargetPitchRadians
        self.highTargetPitchRadians =
            highTargetPitchRadians
        self.alignedYawToleranceRadians =
            alignedYawToleranceRadians
        self.alignedPitchToleranceRadians =
            alignedPitchToleranceRadians
        self.minimumTargetHoldSeconds =
            minimumTargetHoldSeconds
    }

    public static let standard =
        ScanGuidanceConfiguration()
}

public enum ScanGuidanceArrow:
    String,
    Sendable,
    Equatable
{
    case left
    case right
    case up
    case down
    case upLeft
    case upRight
    case downLeft
    case downRight
    case aligned
}

public struct ScanCoverageGuidance:
    Sendable,
    Equatable
{
    public let target: ScanCoverageGap
    public let targetYawRadians: Double
    public let targetPitchRadians: Double
    public let signedYawErrorRadians: Double
    public let pitchErrorRadians: Double
    public let angularDistanceRadians: Double
    public let arrow: ScanGuidanceArrow

    public static func make(
        target: ScanCoverageGap,
        sectorCount: Int,
        currentRelativeYawRadians: Double,
        currentPitchRadians: Double,
        configuration: ScanGuidanceConfiguration = .standard
    ) -> ScanCoverageGuidance? {
        guard sectorCount > 0,
              currentRelativeYawRadians.isFinite,
              currentPitchRadians.isFinite
        else {
            return nil
        }

        let targetYaw = targetYawRadians(
            sectorIndex: target.sectorIndex,
            sectorCount: sectorCount
        )
        let targetPitch = targetPitchRadians(
            pitchBand: target.pitchBand,
            configuration: configuration
        )
        let yawError = signedYawError(
            targetYawRadians: targetYaw,
            currentYawRadians:
                currentRelativeYawRadians
        )
        let pitchError =
            targetPitch - currentPitchRadians

        let cosineDistance =
            sin(currentPitchRadians) * sin(targetPitch)
            + cos(currentPitchRadians) * cos(targetPitch)
                * cos(yawError)
        let angularDistance = acos(
            min(1, max(-1, cosineDistance))
        )

        let horizontalDirection: Int
        if abs(yawError)
            <= configuration.alignedYawToleranceRadians
        {
            horizontalDirection = 0
        } else {
            horizontalDirection = yawError > 0 ? 1 : -1
        }

        let verticalDirection: Int
        if abs(pitchError)
            <= configuration.alignedPitchToleranceRadians
        {
            verticalDirection = 0
        } else {
            verticalDirection = pitchError > 0 ? 1 : -1
        }

        let arrow: ScanGuidanceArrow
        switch (horizontalDirection, verticalDirection) {
        case (0, 0):
            arrow = .aligned
        case (-1, 0):
            arrow = .left
        case (1, 0):
            arrow = .right
        case (0, 1):
            arrow = .up
        case (0, -1):
            arrow = .down
        case (-1, 1):
            arrow = .upLeft
        case (1, 1):
            arrow = .upRight
        case (-1, -1):
            arrow = .downLeft
        case (1, -1):
            arrow = .downRight
        default:
            arrow = .aligned
        }

        return ScanCoverageGuidance(
            target: target,
            targetYawRadians: targetYaw,
            targetPitchRadians: targetPitch,
            signedYawErrorRadians: yawError,
            pitchErrorRadians: pitchError,
            angularDistanceRadians: angularDistance,
            arrow: arrow
        )
    }

    public static func signedYawError(
        targetYawRadians: Double,
        currentYawRadians: Double
    ) -> Double {
        normalizeSignedRadians(
            targetYawRadians - currentYawRadians
        )
    }

    public static func targetYawRadians(
        sectorIndex: Int,
        sectorCount: Int
    ) -> Double {
        precondition(sectorCount > 0)
        let normalizedSector =
            ((sectorIndex % sectorCount) + sectorCount)
            % sectorCount
        let width =
            2 * Double.pi / Double(sectorCount)
        return normalizeSignedRadians(
            Double(normalizedSector) * width
        )
    }

    public static func targetPitchRadians(
        pitchBand: ScanCoveragePitchBand,
        configuration: ScanGuidanceConfiguration = .standard
    ) -> Double {
        switch pitchBand {
        case .low:
            return configuration.lowTargetPitchRadians
        case .level:
            return 0
        case .high:
            return configuration.highTargetPitchRadians
        }
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
    /// Ambient scene illumination in lumens from the frame's light
    /// estimate, when the platform provides one (legacy bolph71656-ai/HTDT-Capture#283). nil means no
    /// reading — lighting assessment must then stay `unknown`, never a
    /// fabricated pass/fail.
    public let ambientLightIntensityLumens: Double?

    public init(
        sessionTimestampSeconds: Double,
        yawRadians: Double,
        pitchRadians: Double,
        cameraPosition: ScanCameraPosition? = nil,
        trackingState: TrackingQualityState,
        trackingReason: String? = nil,
        activeMeshAnchorCount: Int,
        hasSceneDepth: Bool,
        ambientLightIntensityLumens: Double? = nil
    ) {
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
        self.cameraPosition = cameraPosition
        self.trackingState = trackingState
        self.trackingReason = trackingReason
        self.activeMeshAnchorCount = activeMeshAnchorCount
        self.hasSceneDepth = hasSceneDepth
        self.ambientLightIntensityLumens =
            ambientLightIntensityLumens
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
    public let currentPitchRadians: Double?
    public let latestTrackingState: TrackingQualityState?
    public let latestTrackingReason: String?
    public let latestMeshAnchorCount: Int
    public let latestHasSceneDepth: Bool
    public let recommendedGap: ScanCoverageGap?
    public let guidanceConfiguration: ScanGuidanceConfiguration

    public init(
        sectorCount: Int,
        minimumSamplesPerCell: Int,
        cellSampleCounts: [Int],
        referenceYawRadians: Double?,
        currentRelativeYawRadians: Double?,
        currentPitchRadians: Double?,
        latestTrackingState: TrackingQualityState?,
        latestTrackingReason: String?,
        latestMeshAnchorCount: Int,
        latestHasSceneDepth: Bool,
        recommendedGap: ScanCoverageGap?,
        guidanceConfiguration: ScanGuidanceConfiguration = .standard
    ) {
        self.sectorCount = sectorCount
        self.minimumSamplesPerCell = minimumSamplesPerCell
        self.cellSampleCounts = cellSampleCounts
        self.referenceYawRadians = referenceYawRadians
        self.currentRelativeYawRadians =
            currentRelativeYawRadians
        self.currentPitchRadians = currentPitchRadians
        self.latestTrackingState = latestTrackingState
        self.latestTrackingReason = latestTrackingReason
        self.latestMeshAnchorCount = latestMeshAnchorCount
        self.latestHasSceneDepth = latestHasSceneDepth
        self.recommendedGap = recommendedGap
        self.guidanceConfiguration = guidanceConfiguration
    }

    public static var empty: ScanCoverageSummary {
        ScanCoverageSummary(
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 0, count: 36),
            referenceYawRadians: nil,
            currentRelativeYawRadians: nil,
            currentPitchRadians: nil,
            latestTrackingState: nil,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 0,
            latestHasSceneDepth: false,
            recommendedGap: nil
        )
    }

    public var recommendedGuidance: ScanCoverageGuidance? {
        guard let recommendedGap,
              let currentRelativeYawRadians,
              let currentPitchRadians
        else {
            return nil
        }

        return ScanCoverageGuidance.make(
            target: recommendedGap,
            sectorCount: sectorCount,
            currentRelativeYawRadians:
                currentRelativeYawRadians,
            currentPitchRadians: currentPitchRadians,
            configuration: guidanceConfiguration
        )
    }

    public var totalCellCount: Int {
        sectorCount * ScanCoveragePitchBand.allCases.count
    }

    public var observedCellCount: Int {
        cellSampleCounts.reduce(into: 0) {
            count,
            samples in
            if samples >= minimumSamplesPerCell {
                count += 1
            }
        }
    }

    public var coverageFraction: Double {
        guard totalCellCount > 0 else {
            return 0
        }
        return Double(observedCellCount)
            / Double(totalCellCount)
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
            sectorIndex
                * ScanCoveragePitchBand.allCases.count
            + pitchBand.rawValue
        guard cellSampleCounts.indices.contains(offset)
        else {
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
        ScanCoveragePitchBand.allCases.reduce(
            into: 0
        ) {
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

        let observed = (0..<sectorCount).reduce(
            into: 0
        ) {
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
    public let guidanceConfiguration:
        ScanGuidanceConfiguration

    private var referenceYawRadians: Double?
    private var currentRelativeYawRadians: Double?
    private var currentPitchRadians: Double?
    private var cellSampleCounts: [Int]
    private var latestTrackingState: TrackingQualityState?
    private var latestTrackingReason: String?
    private var latestMeshAnchorCount = 0
    private var latestHasSceneDepth = false
    private var recommendedGap: ScanCoverageGap?
    private var recommendedGapSelectedAtSeconds: Double?

    public init(
        sectorCount: Int = 12,
        minimumSamplesPerCell: Int = 2,
        guidanceConfiguration:
            ScanGuidanceConfiguration = .standard
    ) {
        precondition(sectorCount > 0)
        precondition(minimumSamplesPerCell > 0)

        self.sectorCount = sectorCount
        self.minimumSamplesPerCell =
            minimumSamplesPerCell
        self.guidanceConfiguration =
            guidanceConfiguration
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
        latestMeshAnchorCount = max(
            0,
            sample.activeMeshAnchorCount
        )
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
        currentPitchRadians = sample.pitchRadians

        if sample.trackingState == .normal {
            let sectorIndex = sectorIndex(
                relativeYawRadians: relativeYaw
            )
            let pitchBand = pitchBand(
                pitchRadians: sample.pitchRadians
            )
            let index =
                sectorIndex
                    * ScanCoveragePitchBand.allCases.count
                + pitchBand.rawValue
            cellSampleCounts[index] += 1
        }

        updateRecommendedGap(
            timestampSeconds:
                sample.sessionTimestampSeconds
        )

        return summary()
    }

    public func summary() -> ScanCoverageSummary {
        ScanCoverageSummary(
            sectorCount: sectorCount,
            minimumSamplesPerCell:
                minimumSamplesPerCell,
            cellSampleCounts: cellSampleCounts,
            referenceYawRadians: referenceYawRadians,
            currentRelativeYawRadians:
                currentRelativeYawRadians,
            currentPitchRadians: currentPitchRadians,
            latestTrackingState: latestTrackingState,
            latestTrackingReason: latestTrackingReason,
            latestMeshAnchorCount:
                latestMeshAnchorCount,
            latestHasSceneDepth:
                latestHasSceneDepth,
            recommendedGap: recommendedGap,
            guidanceConfiguration:
                guidanceConfiguration
        )
    }

    private mutating func updateRecommendedGap(
        timestampSeconds: Double
    ) {
        guard currentRelativeYawRadians != nil,
              currentPitchRadians != nil
        else {
            recommendedGap = nil
            recommendedGapSelectedAtSeconds = nil
            return
        }

        guard observedCellCount < totalCellCount else {
            recommendedGap = nil
            recommendedGapSelectedAtSeconds = nil
            return
        }

        let timestamp =
            timestampSeconds.isFinite
            ? timestampSeconds
            : (recommendedGapSelectedAtSeconds ?? 0)

        if let currentTarget = recommendedGap,
           !isObserved(currentTarget)
        {
            let selectedAt =
                recommendedGapSelectedAtSeconds
                ?? timestamp
            let elapsed = max(0, timestamp - selectedAt)

            guard elapsed
                    >= guidanceConfiguration
                        .minimumTargetHoldSeconds
            else {
                return
            }

            guard let candidate = bestGap(),
                  candidate != currentTarget
            else {
                return
            }

            let currentObservedBands =
                observedPitchBandCount(
                    sectorIndex:
                        currentTarget.sectorIndex
                )
            let candidateObservedBands =
                observedPitchBandCount(
                    sectorIndex:
                        candidate.sectorIndex
                )

            if candidateObservedBands
                < currentObservedBands
            {
                recommendedGap = candidate
                recommendedGapSelectedAtSeconds =
                    timestamp
            }
            return
        }

        recommendedGap = bestGap()
        recommendedGapSelectedAtSeconds =
            recommendedGap == nil ? nil : timestamp
    }

    private func bestGap() -> ScanCoverageGap? {
        guard observedCellCount < totalCellCount
        else {
            return nil
        }

        let currentSector: Int
        if let yaw = currentRelativeYawRadians {
            currentSector = sectorIndex(
                relativeYawRadians: yaw
            )
        } else {
            currentSector = 0
        }

        let candidateSector = (0..<sectorCount)
            .filter {
                observedPitchBandCount(
                    sectorIndex: $0
                ) < ScanCoveragePitchBand.allCases.count
            }
            .min {
                let lhsCoverage =
                    observedPitchBandCount(
                        sectorIndex: $0
                    )
                let rhsCoverage =
                    observedPitchBandCount(
                        sectorIndex: $1
                    )
                if lhsCoverage != rhsCoverage {
                    return lhsCoverage < rhsCoverage
                }

                let lhsDistance =
                    circularSectorDistance(
                        from: currentSector,
                        to: $0
                    )
                let rhsDistance =
                    circularSectorDistance(
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

        let pitchPreference:
            [ScanCoveragePitchBand] = [
                .level,
                .low,
                .high,
            ]
        guard let missingBand =
                pitchPreference.first(where: {
                    !isObserved(
                        ScanCoverageGap(
                            sectorIndex: candidateSector,
                            pitchBand: $0
                        )
                    )
                })
        else {
            return nil
        }

        return ScanCoverageGap(
            sectorIndex: candidateSector,
            pitchBand: missingBand
        )
    }

    private var totalCellCount: Int {
        sectorCount * ScanCoveragePitchBand.allCases.count
    }

    private var observedCellCount: Int {
        cellSampleCounts.reduce(into: 0) {
            count,
            samples in
            if samples >= minimumSamplesPerCell {
                count += 1
            }
        }
    }

    private func observedPitchBandCount(
        sectorIndex: Int
    ) -> Int {
        ScanCoveragePitchBand.allCases.reduce(
            into: 0
        ) {
            count,
            band in
            if isObserved(
                ScanCoverageGap(
                    sectorIndex: sectorIndex,
                    pitchBand: band
                )
            ) {
                count += 1
            }
        }
    }

    private func isObserved(
        _ gap: ScanCoverageGap
    ) -> Bool {
        guard gap.sectorIndex >= 0,
              gap.sectorIndex < sectorCount
        else {
            return false
        }

        let index =
            gap.sectorIndex
                * ScanCoveragePitchBand.allCases.count
            + gap.pitchBand.rawValue
        guard cellSampleCounts.indices.contains(index)
        else {
            return false
        }
        return cellSampleCounts[index]
            >= minimumSamplesPerCell
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
        return Int(floor(shifted / width))
            % sectorCount
    }

    private func circularSectorDistance(
        from lhs: Int,
        to rhs: Int
    ) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, sectorCount - direct)
    }

    private func pitchBand(
        pitchRadians: Double
    ) -> ScanCoveragePitchBand {
        let threshold =
            guidanceConfiguration
                .pitchBandThresholdRadians
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
        return remainder >= 0
            ? remainder
            : remainder + fullTurn
    }
}
