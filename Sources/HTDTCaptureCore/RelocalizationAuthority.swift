import Foundation

/// Relocalization authority model (legacy bolph71656-ai/HTDT-Capture#323).
///
/// Resuming a scan after an interruption must never trust ARKit's
/// "relocalized" label alone: a relocalization claim is only an
/// authority when explicit reference observations (fiducials, loop
/// closures, control points, spatial anchors) confirm the resumed
/// world frame against the prior coordinate space, and only a
/// versioned acceptance policy may turn a verified attempt into a
/// resume decision. Anything else fails closed into a fresh
/// coordinate space so evidence from different world frames is never
/// silently merged.
///
/// The model is pure data + policy: it records what was observed and
/// what was decided, unit-testable without a device. Runtime device
/// validation is a separate gate (RDC 0).

/// A scan segment: one contiguous run of evidence capture under a
/// single coordinate-space identity (legacy bolph71656-ai/HTDT-Capture#323). Segment IDs let resumed
/// evidence stay attributable to the exact space it was captured in.
public struct ScanSegmentID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct RelocalizationAttemptID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// The interruption boundary a relocalization attempt crosses (legacy bolph71656-ai/HTDT-Capture#323).
public enum RelocalizationInterruptionBoundary:
    String,
    Codable,
    Sendable,
    Equatable
{
    /// The app process restarted; the prior world frame exists only
    /// as persisted state.
    case applicationRestart = "application_restart"
    /// The AR session was interrupted in place (phone call, Siri,
    /// app switcher) and tracking dropped.
    case arSessionInterruption = "ar_session_interruption"
    /// A persisted world map is being reloaded into a fresh session.
    case worldMapReload = "world_map_reload"
    /// The operator explicitly asked to continue a prior scan.
    case userInitiatedResume = "user_initiated_resume"
}

/// What ARKit reported for the attempt (legacy bolph71656-ai/HTDT-Capture#323). Mirrors the runtime
/// outcome without importing ARKit so the policy model stays
/// macOS-verifiable. A `.relocalized` value is a *claim*, never an
/// authority on its own.
public enum RelocalizationARKitOutcome: String, Codable, Sendable {
    case relocalized
    case failed
    case notAttempted = "not_attempted"
}

/// The kind of explicit reference observation used to verify a
/// relocalization claim (legacy bolph71656-ai/HTDT-Capture#323). `unqualified` exists so malformed
/// records decode — the acceptance policy never admits it.
public enum RelocalizationReferenceKind: String, Codable, Sendable {
    case fiducial
    case loopClosure = "loop_closure"
    case controlPoint = "control_point"
    case spatialAnchor = "spatial_anchor"
    case unqualified
}

/// One explicit reference observation made while verifying a
/// relocalization claim (legacy bolph71656-ai/HTDT-Capture#323): a measurable comparison between a
/// reference known in the prior coordinate space and its observed
/// pose after resume, expressed as residuals. A check with no
/// measured residual is not evidence.
public struct RelocalizationReferenceCheck:
    Codable,
    Sendable,
    Equatable
{
    /// Identity of the reference (fiducial ID, anchor ID, control-
    /// point key) — never a free-text label.
    public let referenceID: String
    public let kind: RelocalizationReferenceKind
    /// Translation residual between the expected prior-space position
    /// and the observed post-resume position, in meters.
    public let residualMeters: Double
    /// Optional angular residual in radians for orientation-bearing
    /// references.
    public let residualRadians: Double?

    public init(
        referenceID: String,
        kind: RelocalizationReferenceKind,
        residualMeters: Double,
        residualRadians: Double? = nil
    ) throws {
        let normalized = SchemaOwnedText.nfc(referenceID)
        guard !normalized.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard residualMeters.isFinite, residualMeters >= 0 else {
            throw AnnotationModelError.invalidPlacementReference
        }
        guard residualRadians == nil
                || (residualRadians!.isFinite && residualRadians! >= 0)
        else {
            throw AnnotationModelError.invalidPlacementReference
        }
        self.referenceID = normalized
        self.kind = kind
        self.residualMeters = residualMeters
        self.residualRadians = residualRadians
    }

    private enum CodingKeys: String, CodingKey {
        case referenceID = "reference_id"
        case kind
        case residualMeters = "residual_m"
        case residualRadians = "residual_rad"
    }
}

/// The decision recorded on a completed attempt (legacy bolph71656-ai/HTDT-Capture#323).
public enum RelocalizationDecision: String, Codable, Sendable {
    case accepted
    case rejected
}

/// A persisted record of one relocalization attempt (legacy bolph71656-ai/HTDT-Capture#323): prior
/// session/coordinate-space identity, map identity, interruption
/// boundary, attempt window, the ARKit-reported outcome, explicit
/// reference observations with residuals, the decision, and the
/// app/OS/device version context under which it was made.
public struct RelocalizationAttempt: Codable, Sendable, Equatable {
    public let attemptID: RelocalizationAttemptID
    /// The capture session the attempt belongs to.
    public let captureSessionID: CaptureSessionID
    /// The prior session whose world frame is being resumed, when
    /// the attempt crosses a session boundary.
    public let priorSessionID: CaptureSessionID?
    /// The coordinate-space identity all prior evidence claims.
    public let priorCoordinateSpaceID: CoordinateSpaceID
    /// Identity of the world map driving the attempt (e.g. a digest
    /// of the persisted map payload), nil when no map exists.
    public let mapIdentity: String?
    public let interruptionBoundary: RelocalizationInterruptionBoundary
    public let attemptStartedAtUTC: String
    /// nil while the attempt is in flight; an unevaluated attempt is
    /// never a resume authority.
    public let attemptEndedAtUTC: String?
    public let arkitOutcome: RelocalizationARKitOutcome
    /// Explicit reference observations made to verify the claim.
    /// Empty means nothing was checked — the "relocalized" label
    /// alone is never sufficient.
    public let referenceChecks: [RelocalizationReferenceCheck]
    /// The decision recorded for the attempt, and the policy that
    /// produced it. `nil` while unevaluated.
    public let decision: RelocalizationDecision?
    public let decisionPolicyID: String?
    public let decisionPolicyVersion: String?
    /// Version authority under which the attempt ran (legacy bolph71656-ai/HTDT-Capture#323).
    public let appVersion: String
    public let osVersion: String
    public let deviceModel: String

    public init(
        attemptID: RelocalizationAttemptID = RelocalizationAttemptID(),
        captureSessionID: CaptureSessionID,
        priorSessionID: CaptureSessionID? = nil,
        priorCoordinateSpaceID: CoordinateSpaceID,
        mapIdentity: String? = nil,
        interruptionBoundary: RelocalizationInterruptionBoundary,
        attemptStartedAtUTC: String,
        attemptEndedAtUTC: String? = nil,
        arkitOutcome: RelocalizationARKitOutcome,
        referenceChecks: [RelocalizationReferenceCheck] = [],
        decision: RelocalizationDecision? = nil,
        decisionPolicyID: String? = nil,
        decisionPolicyVersion: String? = nil,
        appVersion: String,
        osVersion: String,
        deviceModel: String
    ) throws {
        let started = SchemaOwnedText.nfc(attemptStartedAtUTC)
        guard !started.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        // A recorded decision must name the exact policy that made it
        // (legacy bolph71656-ai/HTDT-Capture#323): an unversioned acceptance is indistinguishable from
        // trusting the label.
        switch decision {
        case .none:
            guard decisionPolicyID == nil,
                  decisionPolicyVersion == nil
            else {
                throw AnnotationModelError
                    .invalidAuthorityComponent
            }
        case .accepted:
            guard arkitOutcome == .relocalized,
                  !referenceChecks.isEmpty,
                  decisionPolicyID != nil,
                  decisionPolicyVersion != nil
            else {
                throw AnnotationModelError
                    .invalidAuthorityComponent
            }
        case .rejected:
            guard decisionPolicyID != nil,
                  decisionPolicyVersion != nil
            else {
                throw AnnotationModelError
                    .invalidAuthorityComponent
            }
        }
        self.attemptID = attemptID
        self.captureSessionID = captureSessionID
        self.priorSessionID = priorSessionID
        self.priorCoordinateSpaceID = priorCoordinateSpaceID
        self.mapIdentity = mapIdentity
        self.interruptionBoundary = interruptionBoundary
        self.attemptStartedAtUTC = started
        self.attemptEndedAtUTC = attemptEndedAtUTC
        self.arkitOutcome = arkitOutcome
        self.referenceChecks = referenceChecks
        self.decision = decision
        self.decisionPolicyID = decisionPolicyID
        self.decisionPolicyVersion = decisionPolicyVersion
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    private enum CodingKeys: String, CodingKey {
        case attemptID = "attempt_id"
        case captureSessionID = "capture_session_id"
        case priorSessionID = "prior_session_id"
        case priorCoordinateSpaceID = "prior_coordinate_space_id"
        case mapIdentity = "map_identity"
        case interruptionBoundary = "interruption_boundary"
        case attemptStartedAtUTC = "attempt_started_at_utc"
        case attemptEndedAtUTC = "attempt_ended_at_utc"
        case arkitOutcome = "arkit_outcome"
        case referenceChecks = "reference_checks"
        case decision
        case decisionPolicyID = "decision_policy_id"
        case decisionPolicyVersion = "decision_policy_version"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case deviceModel = "device_model"
    }
}

/// Why an attempt failed acceptance (legacy bolph71656-ai/HTDT-Capture#323). Every reason is explicit
/// so a rejection is auditable, never a silent fallback.
public enum RelocalizationRejectionReason:
    String,
    Sendable,
    Equatable
{
    /// The attempt never completed — no end timestamp recorded.
    case incompleteAttempt = "incomplete_attempt"
    /// ARKit did not report a relocalization.
    case arkitDidNotRelocalize = "arkit_did_not_relocalize"
    /// Fewer explicit reference checks than the policy requires —
    /// the "relocalized" label alone is not evidence.
    case insufficientReferenceChecks = "insufficient_reference_checks"
    /// A reference check's residual exceeds the policy maximum.
    case residualExceedsMaximum = "residual_exceeds_maximum"
    /// A check kind the policy does not admit as authority.
    case unqualifiedCheckKind = "unqualified_check_kind"
}

/// Whether an accepted resume keeps the prior coordinate-space
/// identity or must open a fresh one (legacy bolph71656-ai/HTDT-Capture#323).
public enum RelocalizationSpaceDisposition:
    String,
    Sendable,
    Equatable
{
    /// Every residual is inside the preserve bound: the resumed
    /// world frame is the prior coordinate space, so
    /// `coordinate_space_id` is preserved and prior evidence stays
    /// geometrically comparable.
    case preserveCoordinateSpace = "preserve_coordinate_space"
    /// The claim verified but not tightly enough to trust the prior
    /// space: resume is allowed only into a fresh coordinate space,
    /// so old and new evidence stay segmented by space identity.
    case freshCoordinateSpace = "fresh_coordinate_space"
}

/// The outcome of evaluating an attempt under a policy (legacy bolph71656-ai/HTDT-Capture#323).
public enum RelocalizationEvaluation: Sendable, Equatable {
    /// Fail closed: the attempt is not a resume authority. Callers
    /// must open a fresh coordinate space and record a
    /// `.relocalizationFailure` discontinuity.
    case reject(reasons: [RelocalizationRejectionReason])
    /// Resume into a new `scan_segment_id`. The disposition states
    /// whether `coordinate_space_id` is preserved.
    case accept(spaceDisposition: RelocalizationSpaceDisposition)
}

/// A versioned relocalization acceptance policy (legacy bolph71656-ai/HTDT-Capture#323). Only a policy
/// instance may turn a completed attempt into a resume decision; the
/// evaluation result carries the policy identity so the decision is
/// attributable.
public struct RelocalizationAcceptancePolicy:
    Sendable,
    Equatable
{
    public let policyID: String
    public let policyVersion: String
    /// Minimum number of explicit reference checks required — never
    /// zero, since the "relocalized" label alone is not authority.
    public let minimumReferenceChecks: Int
    /// Largest translation residual (meters) any single check may
    /// report for the attempt to be accepted at all.
    public let maximumResidualMeters: Double
    /// Tighter residual bound (meters) required to *preserve* the
    /// prior coordinate space. Accepted attempts above this bound
    /// resume into a fresh space instead of silently reusing the old
    /// frame.
    public let preserveSpaceResidualMeters: Double
    /// Reference-check kinds admitted as authority.
    public let admittedCheckKinds: Set<RelocalizationReferenceKind>

    public init(
        policyID: String,
        policyVersion: String,
        minimumReferenceChecks: Int,
        maximumResidualMeters: Double,
        preserveSpaceResidualMeters: Double,
        admittedCheckKinds: Set<RelocalizationReferenceKind>
    ) {
        precondition(minimumReferenceChecks >= 1)
        precondition(maximumResidualMeters > 0)
        precondition(
            preserveSpaceResidualMeters > 0
                && preserveSpaceResidualMeters
                    <= maximumResidualMeters
        )
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.minimumReferenceChecks = minimumReferenceChecks
        self.maximumResidualMeters = maximumResidualMeters
        self.preserveSpaceResidualMeters = preserveSpaceResidualMeters
        self.admittedCheckKinds = admittedCheckKinds
    }

    /// The v1 policy: at least one qualified reference check, all
    /// residuals at or below 15 cm, and the prior space preserved only
    /// when every residual is at or below 5 cm.
    public static var standard: RelocalizationAcceptancePolicy {
        RelocalizationAcceptancePolicy(
            policyID: "htdt.relocalization-acceptance",
            policyVersion: "1.0.0",
            minimumReferenceChecks: 1,
            maximumResidualMeters: 0.15,
            preserveSpaceResidualMeters: 0.05,
            admittedCheckKinds: [
                .fiducial,
                .loopClosure,
                .controlPoint,
                .spatialAnchor,
            ]
        )
    }

    /// Evaluates a completed attempt. Any single failure rejects the
    /// whole attempt — fail closed (legacy bolph71656-ai/HTDT-Capture#323). The order of `reasons`
    /// follows evaluation order: boundary, outcome, then checks.
    public func evaluate(
        _ attempt: RelocalizationAttempt
    ) -> RelocalizationEvaluation {
        var reasons: [RelocalizationRejectionReason] = []
        if attempt.attemptEndedAtUTC == nil {
            reasons.append(.incompleteAttempt)
        }
        if attempt.arkitOutcome != .relocalized {
            reasons.append(.arkitDidNotRelocalize)
        }
        let qualified = attempt.referenceChecks.filter {
            admittedCheckKinds.contains($0.kind)
        }
        if attempt.referenceChecks.contains(where: {
            !admittedCheckKinds.contains($0.kind)
        }) {
            reasons.append(.unqualifiedCheckKind)
        }
        if qualified.count < minimumReferenceChecks {
            reasons.append(.insufficientReferenceChecks)
        }
        if qualified.contains(where: {
            $0.residualMeters > maximumResidualMeters
        }) {
            reasons.append(.residualExceedsMaximum)
        }
        guard reasons.isEmpty else {
            return .reject(reasons: reasons)
        }
        let preservesSpace = qualified.allSatisfy {
            $0.residualMeters <= preserveSpaceResidualMeters
        }
        return .accept(
            spaceDisposition: preservesSpace
                ? .preserveCoordinateSpace
                : .freshCoordinateSpace
        )
    }

    /// Applies `evaluate` and records the decision on the attempt
    /// (legacy bolph71656-ai/HTDT-Capture#323): the returned copy stamps `decision` plus this policy's
    /// identity so the record is self-describing.
    public func recordDecision(
        on attempt: RelocalizationAttempt
    ) throws -> RelocalizationAttempt {
        let evaluated = evaluate(attempt)
        let decision: RelocalizationDecision
        switch evaluated {
        case .accept:
            decision = .accepted
        case .reject:
            decision = .rejected
        }
        return try RelocalizationAttempt(
            attemptID: attempt.attemptID,
            captureSessionID: attempt.captureSessionID,
            priorSessionID: attempt.priorSessionID,
            priorCoordinateSpaceID: attempt.priorCoordinateSpaceID,
            mapIdentity: attempt.mapIdentity,
            interruptionBoundary: attempt.interruptionBoundary,
            attemptStartedAtUTC: attempt.attemptStartedAtUTC,
            attemptEndedAtUTC: attempt.attemptEndedAtUTC,
            arkitOutcome: attempt.arkitOutcome,
            referenceChecks: attempt.referenceChecks,
            decision: decision,
            decisionPolicyID: policyID,
            decisionPolicyVersion: policyVersion,
            appVersion: attempt.appVersion,
            osVersion: attempt.osVersion,
            deviceModel: attempt.deviceModel
        )
    }
}

/// A scan segment record (legacy bolph71656-ai/HTDT-Capture#323): the resumption boundary's output.
/// Evidence captured after the boundary is attributed to this segment
/// and its `coordinateSpaceID`, so frames from different world
/// identities are never silently merged.
public struct ScanSegment: Codable, Sendable, Equatable {
    public let scanSegmentID: ScanSegmentID
    public let captureSessionID: CaptureSessionID
    /// The coordinate space this segment's evidence is expressed in —
    /// preserved on a verified relocalization, fresh otherwise.
    public let coordinateSpaceID: CoordinateSpaceID
    /// The relocalization attempt that opened the segment, nil for
    /// the first segment of a session.
    public let openedByAttemptID: RelocalizationAttemptID?
    /// Session-relative seconds when the segment opened.
    public let startedAtSessionTimestampSeconds: Double

    public init(
        scanSegmentID: ScanSegmentID = ScanSegmentID(),
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        openedByAttemptID: RelocalizationAttemptID? = nil,
        startedAtSessionTimestampSeconds: Double
    ) {
        self.scanSegmentID = scanSegmentID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.openedByAttemptID = openedByAttemptID
        self.startedAtSessionTimestampSeconds =
            startedAtSessionTimestampSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case scanSegmentID = "scan_segment_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case openedByAttemptID = "opened_by_attempt_id"
        case startedAtSessionTimestampSeconds =
            "started_at_session_timestamp_s"
    }
}

extension RelocalizationAttempt {
    /// The resume decision this attempt authorizes (legacy bolph71656-ai/HTDT-Capture#323): only an
    /// `accepted` evaluation under a named policy opens a new segment.
    /// `preserveCoordinateSpace` reuses `priorCoordinateSpaceID`;
    /// anything else returns a fresh space. `sessionTimestampSeconds`
    /// anchors the new segment on the session clock.
    public func resumeDecision(
        evaluatedUnder policy: RelocalizationAcceptancePolicy,
        sessionTimestampSeconds: Double,
        freshSpace: CoordinateSpaceID = CoordinateSpaceID()
    ) -> ScanSegment? {
        guard case let .accept(disposition) = policy.evaluate(self)
        else {
            return nil
        }
        let space: CoordinateSpaceID
        switch disposition {
        case .preserveCoordinateSpace:
            space = priorCoordinateSpaceID
        case .freshCoordinateSpace:
            space = freshSpace
        }
        return ScanSegment(
            captureSessionID: captureSessionID,
            coordinateSpaceID: space,
            openedByAttemptID: attemptID,
            startedAtSessionTimestampSeconds: sessionTimestampSeconds
        )
    }
}
