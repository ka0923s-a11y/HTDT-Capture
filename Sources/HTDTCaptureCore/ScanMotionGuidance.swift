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

public extension ScanMotionGuidanceAction {
    /// Whether the action asks the operator to physically move (walk).
    /// In-place actions — rotate, tilt, hold, tracking recovery — never
    /// carry movement-safety wording (legacy bolph71656-ai/HTDT-Capture#313).
    var requiresPhysicalTranslation: Bool {
        switch self {
        case .translate, .approach, .retreat, .orbit,
             .reobserveAnotherAngle:
            return true
        case .trackingRecovery, .rotate, .tilt, .holdObserve:
            return false
        }
    }
}

/// How much physical translation the operator can currently make
/// (legacy bolph71656-ai/HTDT-Capture#257 stationary-only, legacy bolph71656-ai/HTDT-Capture#313 safety-constrained). Anything but
/// `unrestricted` suppresses movement guidance: the app never claims to
/// know the operator's path is safe, so a constrained mode removes
/// translation prompts entirely rather than coaching risky movement.
public enum ScanMovementCapability: String, Codable, Sendable, Equatable {
    case unrestricted
    case stationaryOnly = "stationary_only"
    /// The operator can move, but the current surroundings make guided
    /// translation unsafe or unwanted right now (e.g. narrow corridor,
    /// obstacles, other people). Same guidance semantics as
    /// `stationaryOnly`; persisted separately so Review can distinguish
    /// "operator chose to stay" from "movement was unsafe".
    case safetyConstrained = "safety_constrained"

    /// Whether guidance may ask for physical translation. Only the
    /// unrestricted capability allows move/orbit prompts.
    public var canGuideTranslation: Bool {
        self == .unrestricted
    }
}

/// Why guidance reported `isComplete` (issue bolph71656-ai/HTDT-Capture#296). The boolean alone
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
    /// Retained weak regions still eligible for guidance, counted
    /// across the whole retained map — not just the live display
    /// window (legacy bolph71656-ai/HTDT-Capture#347). A weak region the operator walked away from
    /// stays unresolved here until it is re-observed or its guidance
    /// attempt budget is exhausted.
    public let actionableWeakRegionCount: Int
    public let saturatedWeakRegionCount: Int
    /// Weak, undeclared retained regions outside the current display
    /// viewport (legacy bolph71656-ai/HTDT-Capture#347). Nonzero means unresolved coverage exists
    /// beyond what the operator is looking at right now.
    public let remoteWeakRegionCount: Int
    public let directionCoverageFraction: Double
    public let isComplete: Bool
    /// Typed reason behind `isComplete` (issue bolph71656-ai/HTDT-Capture#296). `.incomplete`
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
        remoteWeakRegionCount: Int = 0,
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
        self.remoteWeakRegionCount = remoteWeakRegionCount
        self.directionCoverageFraction = directionCoverageFraction
        self.isComplete = isComplete
        self.completionSource = completionSource
            ?? (isComplete ? .observed : .incomplete)
    }

    /// Weak regions still unresolved when completion fired — the count
    /// the UI keeps visible when the source was budget/constraint
    /// rather than observation (issue bolph71656-ai/HTDT-Capture#296).
    public var unresolvedWeakRegionCount: Int {
        actionableWeakRegionCount + saturatedWeakRegionCount
    }

    public static let empty = ScanGuidanceProgress(
        movementCapability: .unrestricted,
        completedSpatialGuidanceAttemptCount: 0,
        maximumSpatialGuidanceAttempts: 0,
        actionableWeakRegionCount: 0,
        saturatedWeakRegionCount: 0,
        remoteWeakRegionCount: 0,
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

/// Copy authority for scan-guidance prompts (legacy bolph71656-ai/HTDT-Capture#399): every string
/// resolves through `Localizable.strings` (English source strings are
/// the keys), so the scan UI, VoiceOver readouts, and the rest of the
/// app share one Apple-native localization mechanism. No language
/// signal is consulted here — `String(localized:)` follows the
/// resolved app localization.
public enum ScanMotionGuidanceCopy {
    public static func prompt(
        for guidance: ScanMotionGuidance
    ) -> String {
        switch guidance.action {
        case .trackingRecovery:
            return String(localized: "Hold the phone steady and show previously seen room features.")
        case .rotate:
            return guidance.horizontalDirection == .left
                ? String(localized: "Turn left in place.")
                : String(localized: "Turn right in place.")
        case .tilt:
            return guidance.verticalDirection == .down
                ? String(localized: "Capture the lower area.")
                : String(localized: "Capture the upper area.")

        // legacy bolph71656-ai/HTDT-Capture#313: every movement prompt is qualified with an explicit
        // path-check precondition. Guidance is advisory — the app does
        // not know the operator's path is safe — so wording must never
        // present walking backward or orbiting as a required or
        // sensor-verified-safe action.
        case .translate:
            switch guidance.translationDirection ?? .right {
            case .left:
                return String(localized: "If the path is clear, step slightly left.")
            case .right:
                return String(localized: "If the path is clear, step slightly right.")
            case .forward:
                return String(localized: "If the path is clear, step slightly forward.")
            case .backward:
                return String(localized: "If the path behind you is clear, step slightly back.")
            }
        case .approach:
            return String(localized: "If safe, move slightly closer.")
        case .retreat:
            return String(localized: "If the path behind you is clear, step slightly back.")
        case .orbit:
            return String(localized: "If safe, view this region from another angle.")
        case .reobserveAnotherAngle:
            return String(localized: "If safe, show this region from another angle.")
        case .holdObserve:
            return String(localized: "Slowly scan this direction.")
        }
    }

    public static func category(
        for action: ScanMotionGuidanceAction
    ) -> String {
        switch action {
        case .trackingRecovery:
            return String(localized: "Tracking recovery")
        case .rotate:
            return String(localized: "Turn in place")
        case .tilt:
            return String(localized: "Tilt")
        case .translate, .approach, .retreat:
            return String(localized: "Move")
        case .orbit, .reobserveAnotherAngle:
            return String(localized: "Reobserve")
        case .holdObserve:
            return String(localized: "Observe")
        }
    }

    /// Short reminder shown while a prompt asks for physical
    /// translation (legacy bolph71656-ai/HTDT-Capture#313). Returns nil for in-place actions, which
    /// need no movement-safety qualifier.
    public static func safetyNote(
        for guidance: ScanMotionGuidance
    ) -> String? {
        guard guidance.action.requiresPhysicalTranslation else {
            return nil
        }
        return String(localized: "Your path is your call — stop walking before reading this.")
    }

    /// First-use safety statement shown before scanning starts and kept
    /// in the guidance help (legacy bolph71656-ai/HTDT-Capture#313). Deliberately plain: awareness, stop
    /// before interacting, never walk backward following the screen.
    /// The app does not detect obstacles — this text never claims it
    /// does.
    public static func safetyDisclaimer() -> String {
        String(localized: "Stay aware of your surroundings. Stop walking before reading or interacting with the screen, and never walk backward following on-screen guidance. Guidance is advisory only — it does not detect obstacles.")
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
    /// (legacy bolph71656-ai/HTDT-Capture#257). Declared regions stay classified unresolved but stop
    /// producing movement guidance and no longer count as actionable.
    private var declaredRegionKeys: Set<SpatialCoverageCellKey> = []

    public init(
        configuration: ScanMotionGuidanceConfiguration = .standard
    ) {
        self.configuration = configuration
    }

    /// Replaces the operator-declared region set (legacy bolph71656-ai/HTDT-Capture#257). If the
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

        if !capability.canGuideTranslation,
           let currentGuidance,
           currentGuidance.action.requiresPhysicalTranslation
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
        // Weak-region accounting is global (legacy bolph71656-ai/HTDT-Capture#347): the live display
        // window is a presentation bound, not a completeness bound,
        // so walking away from a weak region must never drop it from
        // the unresolved count or complete the spatial dimension.
        let actionable = spatialCoverage.regions.filter {
            $0.classification == .weak
                && !declaredRegionKeys.contains($0.key)
                && (weakGuidanceAttempts[$0.key] ?? 0)
                    < configuration.maximumWeakRegionGuidanceAttempts
        }.count
        let saturated = spatialCoverage.regions.filter {
            $0.classification == .weak
                && !declaredRegionKeys.contains($0.key)
                && (weakGuidanceAttempts[$0.key] ?? 0)
                    >= configuration.maximumWeakRegionGuidanceAttempts
        }.count
        let remote = spatialCoverage.regions.filter {
            $0.classification == .weak
                && !declaredRegionKeys.contains($0.key)
                && !(spatialCoverage.displayBounds?
                    .contains($0.key) ?? false)
        }.count
        let directionReady =
            coverage.coverageFraction
                >= configuration.completionDirectionCoverageFraction
            && coverage.latestTrackingState == .normal
        let spatialBudgetExhausted =
            completedSpatialGuidanceAttemptCount
                >= configuration.maximumSpatialGuidanceAttempts
        let spatialComplete =
            !movementCapability.canGuideTranslation
            || spatialBudgetExhausted
            || (
                spatialCoverage.knownRegionCount > 0
                && actionable == 0
            )
        let isComplete = directionReady && spatialComplete

        // Completion source precedence (issue bolph71656-ai/HTDT-Capture#296): an operator-
        // declared movement constraint dominates — movement-dependent
        // guidance never ran. A spent global budget outranks per-region
        // retry saturation, and both outrank a genuinely-observed
        // completion, so a "complete" claim is never attributed to
        // observation when a bound terminated the loop.
        let completionSource: ScanGuidanceCompletionSource
        if !isComplete {
            completionSource = .incomplete
        } else if !movementCapability.canGuideTranslation {
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
            remoteWeakRegionCount: remote,
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

        // Spatial coaching begins at the activation fraction; the
        // completion fraction only gates when guidance may go silent
        // (below). Taking the max here made activation dead config —
        // every published strategy sets activation < completion.
        let spatialGuidanceActive =
            coverage.coverageFraction
                >= configuration
                    .spatialGuidanceActivationCoverageFraction
        let spatialGuidanceBudgetExhausted =
            completedSpatialGuidanceAttemptCount
                >= configuration.maximumSpatialGuidanceAttempts

        // Remaining direction gaps stay ahead of spatial translation:
        // rotation/tilt guidance is answered before any movement
        // candidate, so a partially-covered scan never trades its
        // last direction sectors for a relocation prompt.
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
                !movementCapability.canGuideTranslation
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
                    movementCapability.canGuideTranslation
                    ? .reobserveAnotherAngle
                    : .holdObserve
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

    /// Local-first weak-region targeting (legacy bolph71656-ai/HTDT-Capture#347): regions inside the
    /// live display window are preferred so the operator finishes
    /// nearby unresolved cells first; when none remain actionable
    /// locally, the nearest remote unresolved region becomes the
    /// target so retained weak regions beyond the viewport are never
    /// silently ignored.
    private func preferredWeakRegion(
        _ spatialCoverage: SpatialScanCoverageSummary
    ) -> SpatialCoverageRegion? {
        let camera = spatialCoverage.currentCameraPosition

        let actionable = spatialCoverage.regions
            .filter {
                $0.classification == .weak
                    && !declaredRegionKeys.contains($0.key)
                    && (weakGuidanceAttempts[$0.key] ?? 0)
                        < configuration
                            .maximumWeakRegionGuidanceAttempts
            }
        let local: [SpatialCoverageRegion]
        if let displayBounds = spatialCoverage.displayBounds {
            local = actionable.filter {
                displayBounds.contains($0.key)
            }
        } else {
            local = actionable
        }
        let candidates = local.isEmpty ? actionable : local

        return candidates
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
