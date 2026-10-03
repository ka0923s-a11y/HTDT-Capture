import Foundation

/// Bounded camera-source preflight models (issue bolph71656-ai/HTDT-Capture#277).
///
/// Source-quality assistance, not a measurement/completeness authority:
/// the outcome may surface a single advisory card before/early in a
/// scan, but it never blocks End/finalization, never invalidates
/// geometry, and never replaces ARKit tracking-state warnings.
public struct CameraSourcePreflightPolicy: Sendable, Equatable {
    /// Vision `DetectLensSmudgeRequest` confidence at or above which a
    /// smudge advisory surfaces. Provisional engineering default pending
    /// lane-A physical evaluation (clean/light/heavy smudge fixtures) —
    /// not an Apple-published threshold.
    public let smudgeWarnConfidence: Double

    /// Maximum camera-position drift between the two stability samples
    /// for a frame to count as stable. Tight enough that handheld jitter
    /// fails but a deliberate hold-still passes.
    public let stableFrameMaxPositionDeltaMeters: Double

    /// Maximum wait for a stable sample before the optional check is
    /// skipped rather than blocking capture.
    public let stableFrameMaxWaitSeconds: Double

    /// Revision tag recorded in diagnostics so the warn policy of an
    /// emitted note is explainable.
    public let policyRevision: String

    /// Stage-B low-light advisory. Disabled by default: ARKit's light
    /// estimate is not a calibrated capture-validity metric, so the
    /// warning ships only if lane-A physical evaluation shows it
    /// predicts an operator-correctable problem beyond the existing
    /// low-light guidance (legacy bolph71656-ai/HTDT-Capture#283).
    public let lowLightAdvisoryEnabled: Bool

    /// Ambient intensity (lumens) below which the optional Stage-B
    /// advisory would fire. Advisory only — never a scan-validity gate.
    public let lowLightThresholdLumens: Double

    public init(
        smudgeWarnConfidence: Double = 0.5,
        stableFrameMaxPositionDeltaMeters: Double = 0.02,
        stableFrameMaxWaitSeconds: Double = 3.0,
        policyRevision: String = "v1",
        lowLightAdvisoryEnabled: Bool = false,
        lowLightThresholdLumens: Double = 100
    ) {
        precondition(smudgeWarnConfidence > 0 && smudgeWarnConfidence <= 1)
        precondition(stableFrameMaxPositionDeltaMeters > 0)
        precondition(stableFrameMaxWaitSeconds > 0)
        precondition(lowLightThresholdLumens > 0)
        self.smudgeWarnConfidence = smudgeWarnConfidence
        self.stableFrameMaxPositionDeltaMeters =
            stableFrameMaxPositionDeltaMeters
        self.stableFrameMaxWaitSeconds = stableFrameMaxWaitSeconds
        self.policyRevision = policyRevision
        self.lowLightAdvisoryEnabled = lowLightAdvisoryEnabled
        self.lowLightThresholdLumens = lowLightThresholdLumens
    }
}

/// What the platform preflight actually measured for one attempt.
/// Every field is honest about acquisition: a missing stable frame or
/// an absent smudge result is recorded as such, never implied.
public struct CameraSourcePreflightOutcome: Sendable, Equatable {
    /// A stable ordinary camera frame was acquired within the wait
    /// budget. False means the check was skipped — no advisory may be
    /// derived from it.
    public let stableFrameAcquired: Bool
    /// `SmudgeObservation.confidence` (0...1) when the Vision request
    /// ran; nil on request failure or skipped acquisition.
    public let smudgeConfidence: Double?
    /// Ambient intensity (lumens) from the sampled frame's light
    /// estimate, when ARKit supplied one.
    public let ambientIntensityLumens: Double?
    /// Session-clock seconds of the sampled frame.
    public let sampledTimestampSeconds: Double?
    /// Vision request revision string recorded for provenance.
    public let visionRequestRevision: String?

    public init(
        stableFrameAcquired: Bool,
        smudgeConfidence: Double?,
        ambientIntensityLumens: Double?,
        sampledTimestampSeconds: Double?,
        visionRequestRevision: String?
    ) {
        self.stableFrameAcquired = stableFrameAcquired
        self.smudgeConfidence = smudgeConfidence
        self.ambientIntensityLumens = ambientIntensityLumens
        self.sampledTimestampSeconds = sampledTimestampSeconds
        self.visionRequestRevision = visionRequestRevision
    }
}

/// The single source-quality advisory the operator sees. At most one
/// card exists at a time: when both conditions are present they share
/// this one surface.
public struct CameraSourceAdvisory: Sendable, Equatable {
    public let smudgeSuspected: Bool
    public let smudgeConfidence: Double?
    /// Stage-B only — experimental and disabled by default policy.
    public let lowLightSuspected: Bool
    public let ambientIntensityLumens: Double?

    public init(
        smudgeSuspected: Bool,
        smudgeConfidence: Double?,
        lowLightSuspected: Bool,
        ambientIntensityLumens: Double?
    ) {
        self.smudgeSuspected = smudgeSuspected
        self.smudgeConfidence = smudgeConfidence
        self.lowLightSuspected = lowLightSuspected
        self.ambientIntensityLumens = ambientIntensityLumens
    }
}

public enum CameraSourcePreflightAssessment {
    /// Pure assessment: outcome + policy -> advisory or nil. Never
    /// surfaces anything when no stable frame was acquired, and never
    /// claims certainty — "may be smudged", never "is dirty".
    public static func assess(
        outcome: CameraSourcePreflightOutcome,
        policy: CameraSourcePreflightPolicy
    ) -> CameraSourceAdvisory? {
        guard outcome.stableFrameAcquired else {
            return nil
        }
        let smudgeSuspected =
            outcome.smudgeConfidence.map {
                $0 >= policy.smudgeWarnConfidence
            } ?? false
        let lowLightSuspected =
            policy.lowLightAdvisoryEnabled
            && (outcome.ambientIntensityLumens.map {
                $0 < policy.lowLightThresholdLumens
            } ?? false)
        guard smudgeSuspected || lowLightSuspected else {
            return nil
        }
        return CameraSourceAdvisory(
            smudgeSuspected: smudgeSuspected,
            smudgeConfidence: outcome.smudgeConfidence,
            lowLightSuspected: lowLightSuspected,
            ambientIntensityLumens: outcome.ambientIntensityLumens
        )
    }
}
