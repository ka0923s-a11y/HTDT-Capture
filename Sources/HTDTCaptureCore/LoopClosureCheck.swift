import Foundation

/// Optional end-of-scan return-to-start consistency check (#273).
///
/// The operator walks back to the capture start region; the check
/// compares the reported camera pose with the recorded start
/// reference. A map that drifted reports the camera far from the start
/// even though the operator physically returned — the residual makes
/// that inconsistency visible before finalization. The check is purely
/// advisory: it never reprojects or corrects the AR world, and an
/// absent/unreliable reference yields `.unavailable`, not a pass.
public enum LoopClosureVerdict: String, Sendable, Equatable {
    /// Reference (capture-start pose) was measured and the camera is
    /// back inside the closure tolerance.
    case closed
    /// Camera is back near the start region but the measured residual
    /// exceeds the closure tolerance — likely drift.
    case inconsistent
    /// Camera has not yet returned near the start region.
    case notAtStart
    /// No start reference was captured or tracking is unreliable — the
    /// check cannot produce a meaningful verdict.
    case unavailable
}

public struct LoopClosureAssessment: Sendable, Equatable {
    public let verdict: LoopClosureVerdict
    /// Horizontal distance from the camera to the recorded start
    /// position, when both were measurable.
    public let residualMeters: Double?
    /// Signed heading difference from the recorded start yaw, when
    /// measurable.
    public let headingResidualRadians: Double?

    public init(
        verdict: LoopClosureVerdict,
        residualMeters: Double? = nil,
        headingResidualRadians: Double? = nil
    ) {
        self.verdict = verdict
        self.residualMeters = residualMeters
        self.headingResidualRadians = headingResidualRadians
    }
}

public struct LoopClosureCheckPolicy: Sendable, Equatable {
    /// Distance from the recorded start position inside which the
    /// operator counts as "returned to start".
    public let approachRadiusMeters: Double
    /// Residual distance below which the return counts as closed.
    /// This bounds only the self-consistency claim — it does not
    /// certify absolute accuracy.
    public let closureToleranceMeters: Double
    /// Heading residual below which the return counts as closed.
    public let closureHeadingRadians: Double

    public init(
        approachRadiusMeters: Double = 1.25,
        closureToleranceMeters: Double = 0.5,
        closureHeadingRadians: Double = .pi / 6
    ) {
        precondition(approachRadiusMeters > closureToleranceMeters)
        precondition(closureToleranceMeters > 0)
        precondition(closureHeadingRadians > 0)
        self.approachRadiusMeters = approachRadiusMeters
        self.closureToleranceMeters = closureToleranceMeters
        self.closureHeadingRadians = closureHeadingRadians
    }

    /// `distanceToStartMeters` is the operator's current horizontal
    /// distance from the recorded start position in the capture's
    /// relative frame (nil when the camera position is unavailable).
    /// `headingResidualRadians` is the current heading minus the
    /// recorded start yaw (nil when heading is unavailable).
    /// `referenceAvailable` reports whether a start reference was
    /// recorded at all; `trackingState` must be normal for a verdict.
    public func assess(
        distanceToStartMeters: Double?,
        headingResidualRadians: Double?,
        referenceAvailable: Bool,
        trackingState: TrackingQualityState?
    ) -> LoopClosureAssessment {
        guard referenceAvailable,
              let distance = distanceToStartMeters,
              distance.isFinite,
              trackingState == .normal
        else {
            return LoopClosureAssessment(verdict: .unavailable)
        }

        let headingResidual: Double? = {
            guard let h = headingResidualRadians, h.isFinite else {
                return nil
            }
            return abs(h)
        }()
        guard distance <= approachRadiusMeters else {
            return LoopClosureAssessment(
                verdict: .notAtStart,
                residualMeters: distance,
                headingResidualRadians: headingResidual
            )
        }

        let headingOK =
            (headingResidual ?? .greatestFiniteMagnitude)
                <= closureHeadingRadians
        let verdict: LoopClosureVerdict =
            distance <= closureToleranceMeters && headingOK
            ? .closed
            : .inconsistent
        return LoopClosureAssessment(
            verdict: verdict,
            residualMeters: distance,
            headingResidualRadians: headingResidual
        )
    }
}
