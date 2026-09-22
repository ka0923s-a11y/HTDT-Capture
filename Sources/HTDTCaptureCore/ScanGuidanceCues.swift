import Foundation

/// Non-visual scan-guidance cues (#252).
///
/// Each cue maps to a distinct haptic/VoiceOver signal on the host.
/// The policy is strictly edge-triggered and rate-limited: a 4 Hz
/// guidance loop produces cues only on meaningful state transitions,
/// never a stream. No geometric authority is encoded — the visual HUD
/// remains authoritative.
public enum ScanGuidanceCue: String, Sendable, Equatable, CaseIterable {
    case trackingLost = "tracking_lost"
    case trackingRecovered = "tracking_recovered"
    case moveLeft = "move_left"
    case moveRight = "move_right"
    case moveForward = "move_forward"
    case moveBack = "move_back"
    case holdSteady = "hold_steady"
    case orbitLeft = "orbit_left"
    case orbitRight = "orbit_right"
    case targetObserved = "target_observed"
    case guidanceComplete = "guidance_complete"
    case endAvailable = "end_available"
    case evidenceSaved = "evidence_saved"
    /// A revisit flag was recorded during scanning (#325) — one-shot
    /// confirmation haptic where non-visual cues are enabled.
    case revisitFlagSaved = "revisit_flag_saved"
}

/// Snapshot of the guidance-facing state the cue policy diffs between
/// sampling ticks.
public struct ScanGuidanceCueInputs: Sendable, Equatable {
    public let trackingState: TrackingQualityState?
    public let guidance: ScanMotionGuidance?
    public let guidanceComplete: Bool
    public let endScanAvailable: Bool

    public init(
        trackingState: TrackingQualityState?,
        guidance: ScanMotionGuidance?,
        guidanceComplete: Bool,
        endScanAvailable: Bool
    ) {
        self.trackingState = trackingState
        self.guidance = guidance
        self.guidanceComplete = guidanceComplete
        self.endScanAvailable = endScanAvailable
    }
}

public struct ScanGuidanceCuePolicy: Sendable, Equatable {
    /// Minimum spacing between any two cues.
    public let globalCooldownSeconds: Double
    /// Per-cue repetition cooldown for cues that can legitimately
    /// repeat (e.g. rotate further left after progress).
    public let repeatedCueCooldownSeconds: Double

    public init(
        globalCooldownSeconds: Double = 1.5,
        repeatedCueCooldownSeconds: Double = 4
    ) {
        precondition(globalCooldownSeconds > 0)
        precondition(repeatedCueCooldownSeconds >= globalCooldownSeconds)
        self.globalCooldownSeconds = globalCooldownSeconds
        self.repeatedCueCooldownSeconds = repeatedCueCooldownSeconds
    }

    private var previousInputs: ScanGuidanceCueInputs?
    private var previousWasComplete = false
    private var previousEndAvailable = false
    private var lastCueAt: Double = -.infinity
    private var lastCueKindAt: [ScanGuidanceCue: Double] = [:]

    /// Diff `inputs` against the previous sample and emit the cues to
    /// play, ordered by importance. `timestampSeconds` uses the session
    /// clock; pass a finite monotonically increasing value.
    public mutating func update(
        _ inputs: ScanGuidanceCueInputs,
        timestampSeconds: Double
    ) -> [ScanGuidanceCue] {
        var cues: [ScanGuidanceCue] = []
        let previous = previousInputs

        if let state = inputs.trackingState,
           state != .normal,
           previous?.trackingState == .normal
        {
            cues.append(.trackingLost)
        }
        if inputs.trackingState == .normal,
           let prev = previous?.trackingState,
           prev != .normal
        {
            cues.append(.trackingRecovered)
        }

        if let guidance = inputs.guidance,
           guidance != previous?.guidance
        {
            switch guidance.action {
            case .translate:
                if guidance.translationDirection == .forward {
                    cues.append(.moveForward)
                } else if guidance.translationDirection == .backward {
                    cues.append(.moveBack)
                } else if guidance.translationDirection == .left {
                    cues.append(.moveLeft)
                } else {
                    cues.append(.moveRight)
                }
            case .approach:
                cues.append(.moveForward)
            case .retreat:
                cues.append(.moveBack)
            case .orbit, .reobserveAnotherAngle:
                if guidance.horizontalDirection == .left {
                    cues.append(.orbitLeft)
                } else {
                    cues.append(.orbitRight)
                }
            case .rotate:
                if guidance.horizontalDirection == .left {
                    cues.append(.moveLeft)
                } else {
                    cues.append(.moveRight)
                }
            case .holdObserve:
                cues.append(.holdSteady)
            case .trackingRecovery, .tilt:
                break
            }
        }

        if inputs.guidanceComplete, !previousWasComplete {
            cues.append(.guidanceComplete)
        }
        if inputs.endScanAvailable, !previousEndAvailable {
            cues.append(.endAvailable)
        }

        previousInputs = inputs
        previousWasComplete = inputs.guidanceComplete
        previousEndAvailable = inputs.endScanAvailable

        return cues.filter { cue in
            admit(cue, timestampSeconds: timestampSeconds)
        }
    }

    /// A one-shot operator-facing event (manual or automatic evidence
    /// retention confirmed).
    public mutating func evidenceSaved(
        timestampSeconds: Double
    ) -> ScanGuidanceCue? {
        admit(.evidenceSaved, timestampSeconds: timestampSeconds)
            ? .evidenceSaved
            : nil
    }

    /// A target-specific event such as a targeted-rescan completion.
    public mutating func targetObserved(
        timestampSeconds: Double
    ) -> ScanGuidanceCue? {
        admit(.targetObserved, timestampSeconds: timestampSeconds)
            ? .targetObserved
            : nil
    }

    /// One-shot confirmation that a revisit flag was persisted (#325).
    public mutating func revisitFlagSaved(
        timestampSeconds: Double
    ) -> ScanGuidanceCue? {
        admit(.revisitFlagSaved, timestampSeconds: timestampSeconds)
            ? .revisitFlagSaved
            : nil
    }

    public mutating func reset() {
        previousInputs = nil
        previousWasComplete = false
        previousEndAvailable = false
        lastCueAt = -.infinity
        lastCueKindAt = [:]
    }

    private mutating func admit(
        _ cue: ScanGuidanceCue,
        timestampSeconds: Double
    ) -> Bool {
        guard timestampSeconds - lastCueAt >= globalCooldownSeconds
        else {
            return false
        }
        if let lastSame = lastCueKindAt[cue],
           timestampSeconds - lastSame < repeatedCueCooldownSeconds
        {
            return false
        }
        lastCueAt = timestampSeconds
        lastCueKindAt[cue] = timestampSeconds
        return true
    }
}
