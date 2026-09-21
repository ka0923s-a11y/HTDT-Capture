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

public enum ScanMovementCapability: String, Sendable, Equatable {
    case unrestricted
    case stationaryOnly = "stationary_only"
}

/// Why guidance reported `isComplete` (issue #296). The boolean alone
/// conflated "every retained weak/unknown region was genuinely
/// observed" with termination by retry-budget exhaustion or an
/// operator-declared movement constraint — three semantically different
/// outcomes that must surface differently in copy, the persisted
/// end-of-scan coverage summary, and tutorial vocabulary.
public enum ScanGuidanceCompletionSource:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    /// Guidance is still running: `isComplete` is false.
    case incomplete
    /// Direction coverage was satisfied under normal tracking and no
    /// weak region still has an actionable or saturated retry budget —
    /// completion was genuinely observed, not negotiated.
    case observed
    /// Direction coverage was satisfied and no weak region remains
    /// actionable, but at least one weak region exhausted its bounded
    /// retry budget: completion came from saturation, not observation.
    case weakRegionRetriesExhausted = "weak_region_retries_exhausted"
    /// The overall spatial-guidance attempt budget ran out while weak
    /// regions were still actionable.
    case attemptBudgetExhausted = "attempt_budget_exhausted"
    /// The operator declared a movement-constrained scan; movement-
    /// dependent guidance is satisfied vacuously, never observed.
    case movementConstrained = "movement_constrained"
}

public struct ScanGuidanceProgress: Sendable, Equatable {
    public let movementCapability: ScanMovementCapability
    public let completedSpatialGuidanceAttemptCount: Int
    public let maximumSpatialGuidanceAttempts: Int
    public let actionableWeakRegionCount: Int
    public let saturatedWeakRegionCount: Int
    public let directionCoverageFraction: Double
    public let isComplete: Bool
    /// Typed reason behind `isComplete` (issue #296). `.incomplete`
    /// exactly when `isComplete` is false, so callers that render a
    /// completion claim can always demand the source instead of
    /// guessing from the boolean.
    public let completionSource: ScanGuidanceCompletionSource

    public init(
        movementCapability: ScanMovementCapability,
        completedSpatialGuidanceAttemptCount: Int,
        maximumSpatialGuidanceAttempts: Int,
        actionableWeakRegionCount: Int,
        saturatedWeakRegionCount: Int,
        directionCoverageFraction: Double,
        isComplete: Bool,
        completionSource: ScanGuidanceCompletionSource? = nil
    ) {
        self.movementCapability = movementCapability
        self.completedSpatialGuidanceAttemptCount =
            completedSpatialGuidanceAttemptCount
        self.maximumSpatialGuidanceAttempts =
            maximumSpatialGuidanceAttempts
        self.actionableWeakRegionCount = actionableWeakRegionCount
        self.saturatedWeakRegionCount = saturatedWeakRegionCount
        self.directionCoverageFraction = directionCoverageFraction
        self.isComplete = isComplete
        self.completionSource = completionSource
            ?? (isComplete ? .observed : .incomplete)
    }

    /// Weak regions still unresolved when completion fired — the count
    /// the UI keeps visible when the source was budget/constraint
    /// rather than observation (issue #296).
    public var unresolvedWeakRegionCount: Int {
        actionableWeakRegionCount + saturatedWeakRegionCount
    }

    public static let empty = ScanGuidanceProgress(
        movementCapability: .unrestricted,
        completedSpatialGuidanceAttemptCount: 0,
        maximumSpatialGuidanceAttempts: 0,
        actionableWeakRegionCount: 0,
        saturatedWeakRegionCount: 0,
        directionCoverageFraction: 0,
        isComplete: false,
        completionSource: .incomplete
    )
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
    public let maximumSpatialGuidanceAttempts: Int
    public let completionDirectionCoverageFraction: Double
    public let cameraHistoryLimit: Int

    public init(
        grossRotationThresholdRadians: Double = 18 * Double.pi / 180,
        pitchActivationThresholdRadians: Double = 12 * Double.pi / 180,
        minimumGuidanceDwellSeconds: Double = 1.5,
        minimumRepeatedWeakObservations: Int = 3,
        minimumTranslationBaselineMeters: Double = 0.30,
        translationCompletionMeters: Double = 0.25,
        spatialGuidanceActivationCoverageFraction: Double = 0.55,
        maximumActionDurationSeconds: Double = 6.0,
        maximumWeakRegionGuidanceAttempts: Int = 2,
        maximumSpatialGuidanceAttempts: Int = 5,
        completionDirectionCoverageFraction: Double = 0.95,
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
        precondition(maximumSpatialGuidanceAttempts > 0)
        precondition(
            completionDirectionCoverageFraction.isFinite
                && completionDirectionCoverageFraction >= 0
                && completionDirectionCoverageFraction <= 1
        )
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
        self.maximumSpatialGuidanceAttempts =
            maximumSpatialGuidanceAttempts
        self.completionDirectionCoverageFraction =
            completionDirectionCoverageFraction
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
    private var movementCapability: ScanMovementCapability =
        .unrestricted
    private var completedSpatialGuidanceAttemptCount = 0
    /// Coverage cells the operator declared intentionally unresolved
    /// (#257). Declared regions stay classified unresolved but stop
    /// producing movement guidance and no longer count as actionable.
    private var declaredRegionKeys: Set<SpatialCoverageCellKey> = []

    public init(
        configuration: ScanMotionGuidanceConfiguration = .standard
    ) {
        self.configuration = configuration
    }

    /// Replaces the operator-declared region set (#257). If the
    /// currently selected guidance targets a freshly declared cell,
    /// it is dropped so the next `record` picks a different target
    /// instead of continuing to coach a region the operator cannot
    /// reach.
    public mutating func setDeclaredRegionKeys(
        _ keys: Set<SpatialCoverageCellKey>
    ) {
        declaredRegionKeys = keys
        if let key = currentGuidance?.targetRegionKey,
           keys.contains(key)
        {
            currentGuidance = nil
            currentSelectedAtSeconds = nil
            currentStartCameraPosition = nil
            currentStartDiversityCount = nil
            currentStartDistanceBucket = nil
        }
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

    public mutating func setMovementCapability(
        _ capability: ScanMovementCapability
    ) {
        movementCapability = capability

        if capability == .stationaryOnly,
           let currentGuidance,
           requiresPhysicalTranslation(currentGuidance.action)
        {
            self.currentGuidance = nil
            currentSelectedAtSeconds = nil
            currentStartCameraPosition = nil
            currentStartDiversityCount = nil
            currentStartDistanceBucket = nil
        }
    }

    public func progress(
        coverage: ScanCoverageSummary,
        spatialCoverage: SpatialScanCoverageSummary
    ) -> ScanGuidanceProgress {
        let actionable = spatialCoverage.regions.filter {
            $0.classification == .weak
                && !declaredRegionKeys.contains($0.key)
                && (weakGuidanceAttempts[$0.key] ?? 0)
                    < configuration.maximumWeakRegionGuidanceAttempts
                && (spatialCoverage.displayBounds?
                    .contains($0.key) ?? true)
        }.count
        let saturated = spatialCoverage.regions.filter {
            $0.classification == .weak
                && !declaredRegionKeys.contains($0.key)
                && (weakGuidanceAttempts[$0.key] ?? 0)
                    >= configuration.maximumWeakRegionGuidanceAttempts
        }.count
        let directionReady =
            coverage.coverageFraction
                >= configuration.completionDirectionCoverageFraction
            && coverage.latestTrackingState == .normal
        let spatialBudgetExhausted =
            completedSpatialGuidanceAttemptCount
                >= configuration.maximumSpatialGuidanceAttempts
        let spatialComplete =
            movementCapability == .stationaryOnly
            || spatialBudgetExhausted
            || (
                spatialCoverage.knownRegionCount > 0
                && actionable == 0
            )
        let isComplete = directionReady && spatialComplete

        // Completion source precedence (issue #296): an operator-
        // declared movement constraint dominates — movement-dependent
        // guidance never ran. A spent global budget outranks per-region
        // retry saturation, and both outrank a genuinely-observed
        // completion, so a "complete" claim is never attributed to
        // observation when a bound terminated the loop.
        let completionSource: ScanGuidanceCompletionSource
        if !isComplete {
            completionSource = .incomplete
        } else if movementCapability == .stationaryOnly {
            completionSource = .movementConstrained
        } else if spatialBudgetExhausted {
            completionSource = .attemptBudgetExhausted
        } else if saturated > 0 {
            completionSource = .weakRegionRetriesExhausted
        } else {
            completionSource = .observed
        }

        return ScanGuidanceProgress(
            movementCapability: movementCapability,
            completedSpatialGuidanceAttemptCount:
                completedSpatialGuidanceAttemptCount,
            maximumSpatialGuidanceAttempts:
                configuration.maximumSpatialGuidanceAttempts,
            actionableWeakRegionCount: actionable,
            saturatedWeakRegionCount: saturated,
            directionCoverageFraction: coverage.coverageFraction,
            isComplete: isComplete,
            completionSource: completionSource
        )
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
                >= max(
                    configuration
                        .spatialGuidanceActivationCoverageFraction,
                    configuration
                        .completionDirectionCoverageFraction
                )
        let spatialGuidanceBudgetExhausted =
            completedSpatialGuidanceAttemptCount
                >= configuration.maximumSpatialGuidanceAttempts

        if spatialGuidanceActive,
           movementCapability == .unrestricted,
           !spatialGuidanceBudgetExhausted,
           let spatialGuidance = spatialMovementCandidate(
                spatialCoverage: spatialCoverage,
                observation: observation
           )
        {
            return spatialGuidance
        }

        if spatialGuidanceActive,
           coverage.coverageFraction
                >= configuration.completionDirectionCoverageFraction,
           (
                movementCapability == .stationaryOnly
                || spatialGuidanceBudgetExhausted
                || (
                    spatialCoverage.knownRegionCount > 0
                    && preferredWeakRegion(spatialCoverage) == nil
                )
           )
        {
            // Spatial movement is complete or unavailable, and broad
            // directional capture is also complete. Only now may the tracker
            // stop issuing guidance. Before this threshold, remaining yaw /
            // pitch direction gaps still need normal in-place guidance.
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

        if !spatialGuidanceActive,
           movementCapability == .unrestricted,
           let region = preferredWeakRegion(
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
                action:
                    movementCapability == .stationaryOnly
                    ? .holdObserve
                    : .reobserveAnotherAngle
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
            // Once broad direction coverage activates spatial guidance, a
            // global recheck flag must not recreate an unbounded targetless
            // re-observation loop after every weak region has exhausted its
            // retry budget. Targetless recheck guidance remains available in
            // the pre-spatial path below.
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
                    && !declaredRegionKeys.contains($0.key)
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

        guard let key = guidance.targetRegionKey else {
            return
        }

        // A temporarily absent target can fall out of the bounded spatial
        // summary without proving that the operator completed an action. Do
        // not consume the global movement budget for that map-window churn.
        guard let region = spatialCoverage.region(at: key) else {
            return
        }

        // The global budget counts completed actions when the target is still
        // observable in authority, including successful actions that promote
        // the region from weak to observed.
        completedSpatialGuidanceAttemptCount += 1

        guard region.classification == .weak else {
            return
        }

        // Per-region retry saturation represents *no-progress* attempts.
        // Successful progress advances guidance without consuming that
        // region's failure budget.
        if !guidanceMadeProgress(
            guidance,
            region: region,
            spatialCoverage: spatialCoverage
        ) {
            weakGuidanceAttempts[key, default: 0] += 1
        }
    }

    private func guidanceMadeProgress(
        _ guidance: ScanMotionGuidance,
        region: SpatialCoverageRegion,
        spatialCoverage: SpatialScanCoverageSummary
    ) -> Bool {
        switch guidance.action {
        case .translate:
            guard let start = currentStartCameraPosition,
                  let current = spatialCoverage.currentCameraPosition
            else {
                return false
            }
            return hypot(
                current.x - start.x,
                current.z - start.z
            ) >= configuration.translationCompletionMeters

        case .orbit, .reobserveAnotherAngle, .holdObserve:
            guard let initial = currentStartDiversityCount else {
                return false
            }
            return region.viewAngleDiversityCount > initial

        case .approach, .retreat:
            guard let initial = currentStartDistanceBucket else {
                return false
            }
            return region.latestDistanceBucket != initial

        case .trackingRecovery, .rotate, .tilt:
            return true
        }
    }

    private func requiresPhysicalTranslation(
        _ action: ScanMotionGuidanceAction
    ) -> Bool {
        switch action {
        case .translate, .approach, .retreat, .orbit,
             .reobserveAnotherAngle:
            return true
        case .trackingRecovery, .rotate, .tilt, .holdObserve:
            return false
        }
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
