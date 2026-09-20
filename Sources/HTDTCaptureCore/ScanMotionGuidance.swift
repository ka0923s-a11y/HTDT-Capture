import Foundation

public enum ScanMotionGuidanceAction: String, Sendable, Equatable, CaseIterable {
    case trackingRecovery = "tracking_recovery"
    case rotate
    case tilt
    case translate
    case approach
    case retreat
    case orbit
    case holdObserve = "hold_observe"
    case reobserveAnotherAngle = "reobserve_another_angle"
}

public enum ScanMotionHorizontalDirection: String, Sendable, Equatable {
    case left
    case right
}

public enum ScanMotionVerticalDirection: String, Sendable, Equatable {
    case up
    case down
}

public enum ScanTranslationDirection: String, Sendable, Equatable, CaseIterable {
    case left
    case right
    case forward
    case backward
}

public struct ScanMotionGuidanceConfiguration: Sendable, Equatable {
    public let grossRotationThresholdRadians: Double
    public let pitchActivationThresholdRadians: Double
    public let minimumGuidanceDwellSeconds: Double
    public let minimumRepeatedWeakObservations: Int
    public let minimumTranslationBaselineMeters: Double
    public let translationCompletionMeters: Double
    public let spatialGuidanceActivationCoverageFraction: Double
    public let maximumActionDurationSeconds: Double
    public let maximumWeakRegionGuidanceAttempts: Int
    public let cameraHistoryLimit: Int

    public init(
        grossRotationThresholdRadians: Double = 18 * Double.pi / 180,
        pitchActivationThresholdRadians: Double = 12 * Double.pi / 180,
        minimumGuidanceDwellSeconds: Double = 1.5,
        minimumRepeatedWeakObservations: Int = 3,
        minimumTranslationBaselineMeters: Double = 0.30,
        translationCompletionMeters: Double = 0.25,
        spatialGuidanceActivationCoverageFraction: Double = 0.55,
        maximumActionDurationSeconds: Double = 8.0,
        maximumWeakRegionGuidanceAttempts: Int = 3,
        cameraHistoryLimit: Int = 12
    ) {
        precondition(
            grossRotationThresholdRadians.isFinite
                && grossRotationThresholdRadians >= 0
        )
        precondition(
            pitchActivationThresholdRadians.isFinite
                && pitchActivationThresholdRadians >= 0
        )
        precondition(
            minimumGuidanceDwellSeconds.isFinite
                && minimumGuidanceDwellSeconds >= 0
        )
        precondition(minimumRepeatedWeakObservations > 0)
        precondition(
            minimumTranslationBaselineMeters.isFinite
                && minimumTranslationBaselineMeters >= 0
        )
        precondition(
            translationCompletionMeters.isFinite
                && translationCompletionMeters >= 0
        )
        precondition(
            spatialGuidanceActivationCoverageFraction.isFinite
                && spatialGuidanceActivationCoverageFraction >= 0
                && spatialGuidanceActivationCoverageFraction <= 1
        )
        precondition(
            maximumActionDurationSeconds.isFinite
                && maximumActionDurationSeconds > 0
        )
        precondition(maximumWeakRegionGuidanceAttempts > 0)
        precondition(cameraHistoryLimit > 1)

        self.grossRotationThresholdRadians =
            grossRotationThresholdRadians
        self.pitchActivationThresholdRadians =
            pitchActivationThresholdRadians
        self.minimumGuidanceDwellSeconds =
            minimumGuidanceDwellSeconds
        self.minimumRepeatedWeakObservations =
            minimumRepeatedWeakObservations
        self.minimumTranslationBaselineMeters =
            minimumTranslationBaselineMeters
        self.translationCompletionMeters =
            translationCompletionMeters
        self.spatialGuidanceActivationCoverageFraction =
            spatialGuidanceActivationCoverageFraction
        self.maximumActionDurationSeconds =
            maximumActionDurationSeconds
        self.maximumWeakRegionGuidanceAttempts =
            maximumWeakRegionGuidanceAttempts
        self.cameraHistoryLimit = cameraHistoryLimit
    }

    public static let standard =
        ScanMotionGuidanceConfiguration()
}

/// Typed operator advisory. This is intentionally ephemeral: it is not
/// canonical geometry, measurement authority, or a finalization gate.
public struct ScanMotionGuidance: Sendable, Equatable {
    public let action: ScanMotionGuidanceAction
    public let horizontalDirection: ScanMotionHorizontalDirection?
    public let verticalDirection: ScanMotionVerticalDirection?
    public let translationDirection: ScanTranslationDirection?
    public let targetGap: ScanCoverageGap?
    public let targetRegionKey: SpatialCoverageCellKey?

    public init(
        action: ScanMotionGuidanceAction,
        horizontalDirection: ScanMotionHorizontalDirection? = nil,
        verticalDirection: ScanMotionVerticalDirection? = nil,
        translationDirection: ScanTranslationDirection? = nil,
        targetGap: ScanCoverageGap? = nil,
        targetRegionKey: SpatialCoverageCellKey? = nil
    ) {
        self.action = action
        self.horizontalDirection = horizontalDirection
        self.verticalDirection = verticalDirection
        self.translationDirection = translationDirection
        self.targetGap = targetGap
        self.targetRegionKey = targetRegionKey
    }
}

public enum ScanMotionGuidanceLanguage: Sendable, Equatable {
    case english
    case japanese
}

public enum ScanMotionGuidanceCopy {
    public static var preferredLanguage: ScanMotionGuidanceLanguage {
        Locale.preferredLanguages.first?
            .lowercased()
            .hasPrefix("ja") == true
            ? .japanese
            : .english
    }

    public static func prompt(
        for guidance: ScanMotionGuidance,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        switch (language, guidance.action) {
        case (.japanese, .trackingRecovery):
            return "端末を安定させ、見覚えのある場所を映してください"
        case (.english, .trackingRecovery):
            return "Hold the phone steady and show previously seen room features."

        case (.japanese, .rotate):
            return guidance.horizontalDirection == .left
                ? "その場で左を向いてください"
                : "その場で右を向いてください"
        case (.english, .rotate):
            return guidance.horizontalDirection == .left
                ? "Turn left in place."
                : "Turn right in place."

        case (.japanese, .tilt):
            return guidance.verticalDirection == .down
                ? "下側を映してください"
                : "上側を映してください"
        case (.english, .tilt):
            return guidance.verticalDirection == .down
                ? "Capture the lower area."
                : "Capture the upper area."

        case (.japanese, .translate):
            switch guidance.translationDirection ?? .right {
            case .left:
                return "少し左へ移動してください"
            case .right:
                return "少し右へ移動してください"
            case .forward:
                return "少し前へ進んでください"
            case .backward:
                return "少し下がってください"
            }
        case (.english, .translate):
            switch guidance.translationDirection ?? .right {
            case .left:
                return "Move slightly to the left."
            case .right:
                return "Move slightly to the right."
            case .forward:
                return "Move slightly forward."
            case .backward:
                return "Move slightly back."
            }

        case (.japanese, .approach):
            return "少し近づいてください"
        case (.english, .approach):
            return "Move slightly closer."

        case (.japanese, .retreat):
            return "少し離れてください"
        case (.english, .retreat):
            return "Move slightly farther away."

        case (.japanese, .orbit):
            return "この領域の反対側へ回り込んでください"
        case (.english, .orbit):
            return "Move around to the other side of this region."

        case (.japanese, .reobserveAnotherAngle):
            return "別角度から映してください"
        case (.english, .reobserveAnotherAngle):
            return "Show this region from another angle."

        case (.japanese, .holdObserve):
            return "この方向をゆっくり映してください"
        case (.english, .holdObserve):
            return "Slowly scan this direction."
        }
    }

    public static func category(
        for action: ScanMotionGuidanceAction,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        switch (language, action) {
        case (.japanese, .trackingRecovery):
            return "トラッキング回復"
        case (.english, .trackingRecovery):
            return "Tracking recovery"
        case (.japanese, .rotate):
            return "回頭"
        case (.english, .rotate):
            return "Turn in place"
        case (.japanese, .tilt):
            return "上下"
        case (.english, .tilt):
            return "Tilt"
        case (.japanese, .translate),
             (.japanese, .approach),
             (.japanese, .retreat):
            return "移動"
        case (.english, .translate),
             (.english, .approach),
             (.english, .retreat):
            return "Move"
        case (.japanese, .orbit),
             (.japanese, .reobserveAnotherAngle):
            return "再観測"
        case (.english, .orbit),
             (.english, .reobserveAnotherAngle):
            return "Reobserve"
        case (.japanese, .holdObserve):
            return "観測"
        case (.english, .holdObserve):
            return "Observe"
        }
    }
}

public struct ScanMotionGuidanceTracker: Sendable {
    public let configuration: ScanMotionGuidanceConfiguration

    private var currentGuidance: ScanMotionGuidance?
    private var currentSelectedAtSeconds: Double?
    private var currentStartCameraPosition: SpatialCoveragePoint2D?
    private var currentStartDiversityCount: Int?
    private var currentStartDistanceBucket: SpatialCoverageDistanceBucket?

    private var cameraHistory: [SpatialCoveragePoint2D] = []
    private var cameraHistoryTargetKey: SpatialCoverageCellKey?
    private var weakObservationCounts:
        [SpatialCoverageCellKey: Int] = [:]
    private var weakGuidanceAttempts:
        [SpatialCoverageCellKey: Int] = [:]

    public init(
        configuration: ScanMotionGuidanceConfiguration = .standard
    ) {
        self.configuration = configuration
    }

    @discardableResult
    public mutating func record(
        timestampSeconds: Double,
        coverage: ScanCoverageSummary,
        spatialCoverage: SpatialScanCoverageSummary,
        observation: ObservationStabilitySummary
    ) -> ScanMotionGuidance? {
        updateWeakObservationCounts(spatialCoverage.regions)
        resetCameraHistoryIfTargetChanged(spatialCoverage)
        appendCameraPosition(spatialCoverage.currentCameraPosition)

        let candidate = candidateGuidance(
            coverage: coverage,
            spatialCoverage: spatialCoverage,
            observation: observation
        )

        let timestamp = timestampSeconds.isFinite
            ? timestampSeconds
            : (currentSelectedAtSeconds ?? 0)

        guard let currentGuidance else {
            select(
                candidate,
                timestampSeconds: timestamp,
                spatialCoverage: spatialCoverage
            )
            return candidate
        }

        if isComplete(
            currentGuidance,
            coverage: coverage,
            spatialCoverage: spatialCoverage,
            timestampSeconds: timestamp
        ) {
            recordCompletedGuidanceAttempt(
                currentGuidance,
                spatialCoverage: spatialCoverage
            )
            let refreshedCandidate = candidateGuidance(
                coverage: coverage,
                spatialCoverage: spatialCoverage,
                observation: observation
            )
            select(
                refreshedCandidate,
                timestampSeconds: timestamp,
                spatialCoverage: spatialCoverage
            )
            return refreshedCandidate
        }

        guard let candidate else {
            let elapsed = max(
                0,
                timestamp - (currentSelectedAtSeconds ?? timestamp)
            )
            if elapsed >= configuration.minimumGuidanceDwellSeconds {
                select(
                    nil,
                    timestampSeconds: timestamp,
                    spatialCoverage: spatialCoverage
                )
                return nil
            }
            return currentGuidance
        }

        if candidate == currentGuidance {
            return currentGuidance
        }

        if priority(of: candidate.action)
            < priority(of: currentGuidance.action)
        {
            select(
                candidate,
                timestampSeconds: timestamp,
                spatialCoverage: spatialCoverage
            )
            return candidate
        }

        let elapsed = max(
            0,
            timestamp - (currentSelectedAtSeconds ?? timestamp)
        )
        guard elapsed
                >= configuration.minimumGuidanceDwellSeconds
        else {
            return currentGuidance
        }

        select(
            candidate,
            timestampSeconds: timestamp,
            spatialCoverage: spatialCoverage
        )
        return candidate
    }

    public func guidance() -> ScanMotionGuidance? {
        currentGuidance
    }

    private mutating func select(
        _ guidance: ScanMotionGuidance?,
        timestampSeconds: Double,
        spatialCoverage: SpatialScanCoverageSummary
    ) {
        currentGuidance = guidance
        currentSelectedAtSeconds = guidance == nil
            ? nil
            : timestampSeconds
        currentStartCameraPosition =
            spatialCoverage.currentCameraPosition

        if let key = guidance?.targetRegionKey,
           let region = spatialCoverage.region(at: key)
        {
            currentStartDiversityCount =
                region.viewAngleDiversityCount
            currentStartDistanceBucket =
                region.latestDistanceBucket
        } else {
            currentStartDiversityCount = nil
            currentStartDistanceBucket = nil
        }
    }

    private mutating func resetCameraHistoryIfTargetChanged(
        _ spatialCoverage: SpatialScanCoverageSummary
    ) {
        let preferredKey =
            preferredWeakRegion(spatialCoverage)?.key
        guard preferredKey != cameraHistoryTargetKey else {
            return
        }

        cameraHistoryTargetKey = preferredKey
        cameraHistory = spatialCoverage.currentCameraPosition
            .map { [$0] } ?? []
    }

    private mutating func appendCameraPosition(
        _ position: SpatialCoveragePoint2D?
    ) {
        guard let position else {
            return
        }

        if let last = cameraHistory.last,
           hypot(last.x - position.x, last.z - position.z) < 0.005
        {
            return
        }

        cameraHistory.append(position)
        if cameraHistory.count > configuration.cameraHistoryLimit {
            cameraHistory.removeFirst(
                cameraHistory.count - configuration.cameraHistoryLimit
            )
        }
    }

    private mutating func updateWeakObservationCounts(
        _ regions: [SpatialCoverageRegion]
    ) {
        let currentKeys = Set(regions.map(\.key))
        weakObservationCounts =
            weakObservationCounts.filter {
                currentKeys.contains($0.key)
            }

        for region in regions {
            if region.classification == .weak {
                weakObservationCounts[region.key] =
                    max(
                        weakObservationCounts[region.key] ?? 0,
                        region.normalTrackingObservationCount
                    )
            } else {
                weakObservationCounts.removeValue(
                    forKey: region.key
                )
                weakGuidanceAttempts.removeValue(
                    forKey: region.key
                )
            }
        }

        weakGuidanceAttempts =
            weakGuidanceAttempts.filter {
                currentKeys.contains($0.key)
            }
    }

    private func candidateGuidance(
        coverage: ScanCoverageSummary,
        spatialCoverage: SpatialScanCoverageSummary,
        observation: ObservationStabilitySummary
    ) -> ScanMotionGuidance? {
        switch coverage.latestTrackingState {
        case .unavailable, .limited:
            return ScanMotionGuidance(
                action: .trackingRecovery
            )
        case .normal, nil:
            break
        }

        let spatialGuidanceActive =
            coverage.coverageFraction
                >= configuration
                    .spatialGuidanceActivationCoverageFraction
        if spatialGuidanceActive,
           let spatialGuidance = spatialMovementCandidate(
                spatialCoverage: spatialCoverage,
                observation: observation
           )
        {
            return spatialGuidance
        }

        if spatialGuidanceActive,
           spatialCoverage.knownRegionCount > 0,
           preferredWeakRegion(spatialCoverage) == nil
        {
            // Direction coverage is already broad and every remaining weak
            // region has either become observed or exhausted its bounded
            // retry budget. Stop issuing movement guidance rather than
            // creating an endless re-observation loop.
            return nil
        }

        if let direction = coverage.recommendedGuidance {
            let yawError = direction.signedYawErrorRadians
            let pitchError = direction.pitchErrorRadians
            let yawTolerance =
                coverage.guidanceConfiguration
                    .alignedYawToleranceRadians
            let pitchTolerance =
                max(
                    coverage.guidanceConfiguration
                        .alignedPitchToleranceRadians,
                    configuration.pitchActivationThresholdRadians
                )

            if abs(yawError)
                >= configuration.grossRotationThresholdRadians
            {
                return ScanMotionGuidance(
                    action: .rotate,
                    horizontalDirection:
                        yawError >= 0 ? .right : .left,
                    targetGap: direction.target
                )
            }

            if abs(pitchError) > pitchTolerance {
                return ScanMotionGuidance(
                    action: .tilt,
                    verticalDirection:
                        pitchError >= 0 ? .up : .down,
                    targetGap: direction.target
                )
            }

            if abs(yawError) > yawTolerance {
                return ScanMotionGuidance(
                    action: .rotate,
                    horizontalDirection:
                        yawError >= 0 ? .right : .left,
                    targetGap: direction.target
                )
            }
        }

        if let region = preferredWeakRegion(
            spatialCoverage
        ) {
            let repeatedCount =
                weakObservationCounts[region.key] ?? 0

            if repeatedCount
                >= configuration.minimumRepeatedWeakObservations
            {
                if region.viewAngleDiversityCount < 2 {
                    let baseline = cameraPositionBaseline()
                    if baseline
                        < configuration
                            .minimumTranslationBaselineMeters
                    {
                        return ScanMotionGuidance(
                            action: .translate,
                            translationDirection:
                                lateralTranslationDirection(
                                    region: region,
                                    spatialCoverage:
                                        spatialCoverage
                                ),
                            targetRegionKey: region.key
                        )
                    }

                    return ScanMotionGuidance(
                        action: .orbit,
                        horizontalDirection:
                            orbitDirection(
                                region: region,
                                spatialCoverage:
                                    spatialCoverage
                            ),
                        targetRegionKey: region.key
                    )
                }

                if region.latestDistanceBucket == .far {
                    return ScanMotionGuidance(
                        action: .approach,
                        translationDirection: .forward,
                        targetRegionKey: region.key
                    )
                }

                if region.latestDistanceBucket == .near {
                    return ScanMotionGuidance(
                        action: .retreat,
                        translationDirection: .backward,
                        targetRegionKey: region.key
                    )
                }
            }

            if observation.recheckSuggested {
                return ScanMotionGuidance(
                    action: .reobserveAnotherAngle,
                    targetRegionKey: region.key
                )
            }

            return ScanMotionGuidance(
                action: .holdObserve,
                targetRegionKey: region.key
            )
        }

        if observation.recheckSuggested {
            return ScanMotionGuidance(
                action: .reobserveAnotherAngle
            )
        }

        if let direction = coverage.recommendedGuidance {
            return ScanMotionGuidance(
                action: .holdObserve,
                targetGap: direction.target
            )
        }

        return nil
    }

    private func spatialMovementCandidate(
        spatialCoverage: SpatialScanCoverageSummary,
        observation: ObservationStabilitySummary
    ) -> ScanMotionGuidance? {
        guard let region = preferredWeakRegion(spatialCoverage) else {
            if observation.recheckSuggested,
               spatialCoverage.knownRegionCount > 0
            {
                return ScanMotionGuidance(
                    action: .reobserveAnotherAngle
                )
            }
            return nil
        }

        let repeatedCount =
            weakObservationCounts[region.key] ?? 0

        if repeatedCount
            >= configuration.minimumRepeatedWeakObservations
        {
            if region.viewAngleDiversityCount < 2 {
                let baseline = cameraPositionBaseline()
                if baseline
                    < configuration
                        .minimumTranslationBaselineMeters
                {
                    return ScanMotionGuidance(
                        action: .translate,
                        translationDirection:
                            lateralTranslationDirection(
                                region: region,
                                spatialCoverage: spatialCoverage
                            ),
                        targetRegionKey: region.key
                    )
                }

                return ScanMotionGuidance(
                    action: .orbit,
                    horizontalDirection:
                        orbitDirection(
                            region: region,
                            spatialCoverage: spatialCoverage
                        ),
                    targetRegionKey: region.key
                )
            }

            if region.latestDistanceBucket == .far {
                return ScanMotionGuidance(
                    action: .approach,
                    translationDirection: .forward,
                    targetRegionKey: region.key
                )
            }

            if region.latestDistanceBucket == .near {
                return ScanMotionGuidance(
                    action: .retreat,
                    translationDirection: .backward,
                    targetRegionKey: region.key
                )
            }
        }

        if observation.recheckSuggested {
            return ScanMotionGuidance(
                action: .reobserveAnotherAngle,
                targetRegionKey: region.key
            )
        }

        return ScanMotionGuidance(
            action: .holdObserve,
            targetRegionKey: region.key
        )
    }

    private func preferredWeakRegion(
        _ spatialCoverage: SpatialScanCoverageSummary
    ) -> SpatialCoverageRegion? {
        let camera = spatialCoverage.currentCameraPosition

        return spatialCoverage.regions
            .filter {
                $0.classification == .weak
                    && (weakGuidanceAttempts[$0.key] ?? 0)
                        < configuration
                            .maximumWeakRegionGuidanceAttempts
                    && (spatialCoverage.displayBounds?
                        .contains($0.key) ?? true)
            }
            .min { lhs, rhs in
                let lhsDistance = squaredDistance(
                    from: camera,
                    to: lhs.key,
                    cellSize: spatialCoverage.cellSizeMeters
                )
                let rhsDistance = squaredDistance(
                    from: camera,
                    to: rhs.key,
                    cellSize: spatialCoverage.cellSizeMeters
                )

                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs.key < rhs.key
            }
    }

    private func squaredDistance(
        from camera: SpatialCoveragePoint2D?,
        to key: SpatialCoverageCellKey,
        cellSize: Double
    ) -> Double {
        guard let camera else {
            return Double.greatestFiniteMagnitude
        }

        let centerX = (Double(key.x) + 0.5) * cellSize
        let centerZ = (Double(key.z) + 0.5) * cellSize
        let dx = centerX - camera.x
        let dz = centerZ - camera.z
        return dx * dx + dz * dz
    }

    private func cameraPositionBaseline() -> Double {
        guard let first = cameraHistory.first else {
            return 0
        }

        return cameraHistory.reduce(0) { maximum, position in
            max(
                maximum,
                hypot(
                    position.x - first.x,
                    position.z - first.z
                )
            )
        }
    }

    private func lateralTranslationDirection(
        region: SpatialCoverageRegion,
        spatialCoverage: SpatialScanCoverageSummary
    ) -> ScanTranslationDirection {
        guard let camera =
                spatialCoverage.currentCameraPosition,
              let heading =
                spatialCoverage.currentRelativeHeadingRadians
        else {
            return .right
        }

        let centerX =
            (Double(region.key.x) + 0.5)
            * spatialCoverage.cellSizeMeters
        let centerZ =
            (Double(region.key.z) + 0.5)
            * spatialCoverage.cellSizeMeters
        let dx = centerX - camera.x
        let dz = centerZ - camera.z
        let rightComponent =
            dx * cos(heading) - dz * sin(heading)

        return rightComponent >= 0 ? .left : .right
    }

    private func orbitDirection(
        region: SpatialCoverageRegion,
        spatialCoverage: SpatialScanCoverageSummary
    ) -> ScanMotionHorizontalDirection {
        switch lateralTranslationDirection(
            region: region,
            spatialCoverage: spatialCoverage
        ) {
        case .left:
            return .left
        case .right:
            return .right
        case .forward, .backward:
            return .right
        }
    }

    private func isComplete(
        _ guidance: ScanMotionGuidance,
        coverage: ScanCoverageSummary,
        spatialCoverage: SpatialScanCoverageSummary,
        timestampSeconds: Double
    ) -> Bool {
        let elapsed = max(
            0,
            timestampSeconds
                - (currentSelectedAtSeconds ?? timestampSeconds)
        )
        let timedOut =
            elapsed >= configuration.maximumActionDurationSeconds
        switch guidance.action {
        case .trackingRecovery:
            return coverage.latestTrackingState == .normal

        case .rotate:
            guard let target = guidance.targetGap else {
                return true
            }
            if coverage.isObserved(
                sectorIndex: target.sectorIndex,
                pitchBand: target.pitchBand
            ) {
                return true
            }
            guard coverage.recommendedGap == target,
                  let direction =
                    coverage.recommendedGuidance
            else {
                return true
            }
            return abs(direction.signedYawErrorRadians)
                <= coverage.guidanceConfiguration
                    .alignedYawToleranceRadians

        case .tilt:
            guard let target = guidance.targetGap else {
                return true
            }
            if coverage.isObserved(
                sectorIndex: target.sectorIndex,
                pitchBand: target.pitchBand
            ) {
                return true
            }
            guard coverage.recommendedGap == target,
                  let direction =
                    coverage.recommendedGuidance
            else {
                return true
            }
            return abs(direction.pitchErrorRadians)
                <= coverage.guidanceConfiguration
                    .alignedPitchToleranceRadians

        case .translate:
            if timedOut {
                return true
            }
            if targetRegionCompleted(
                guidance.targetRegionKey,
                spatialCoverage: spatialCoverage
            ) {
                return true
            }
            guard let start = currentStartCameraPosition,
                  let current =
                    spatialCoverage.currentCameraPosition
            else {
                return false
            }
            return hypot(
                current.x - start.x,
                current.z - start.z
            ) >= configuration.translationCompletionMeters

        case .orbit, .reobserveAnotherAngle:
            if timedOut {
                return true
            }
            if targetRegionCompleted(
                guidance.targetRegionKey,
                spatialCoverage: spatialCoverage
            ) {
                return true
            }
            guard let key = guidance.targetRegionKey,
                  let region = spatialCoverage.region(at: key),
                  let initial = currentStartDiversityCount
            else {
                return false
            }
            return region.viewAngleDiversityCount > initial

        case .approach, .retreat:
            if timedOut {
                return true
            }
            if targetRegionCompleted(
                guidance.targetRegionKey,
                spatialCoverage: spatialCoverage
            ) {
                return true
            }
            guard let key = guidance.targetRegionKey,
                  let region = spatialCoverage.region(at: key),
                  let initial = currentStartDistanceBucket
            else {
                return false
            }
            return region.latestDistanceBucket != initial

        case .holdObserve:
            if timedOut {
                return true
            }
            if let gap = guidance.targetGap {
                return coverage.isObserved(
                    sectorIndex: gap.sectorIndex,
                    pitchBand: gap.pitchBand
                )
            }
            return targetRegionCompleted(
                guidance.targetRegionKey,
                spatialCoverage: spatialCoverage
            )
        }
    }

    private mutating func recordCompletedGuidanceAttempt(
        _ guidance: ScanMotionGuidance,
        spatialCoverage: SpatialScanCoverageSummary
    ) {
        switch guidance.action {
        case .translate,
             .orbit,
             .reobserveAnotherAngle,
             .approach,
             .retreat,
             .holdObserve:
            break
        case .trackingRecovery, .rotate, .tilt:
            return
        }

        guard let key = guidance.targetRegionKey,
              let region = spatialCoverage.region(at: key),
              region.classification == .weak
        else {
            return
        }

        weakGuidanceAttempts[key, default: 0] += 1
    }

    private func targetRegionCompleted(
        _ key: SpatialCoverageCellKey?,
        spatialCoverage: SpatialScanCoverageSummary
    ) -> Bool {
        guard let key else {
            return false
        }
        guard let region = spatialCoverage.region(at: key) else {
            return true
        }
        return region.classification == .observed
    }

    private func priority(
        of action: ScanMotionGuidanceAction
    ) -> Int {
        switch action {
        case .trackingRecovery:
            return 0
        case .rotate:
            return 1
        case .tilt:
            return 2
        case .translate:
            return 3
        case .orbit, .reobserveAnotherAngle:
            return 4
        case .approach, .retreat:
            return 5
        case .holdObserve:
            return 6
        }
    }
}
