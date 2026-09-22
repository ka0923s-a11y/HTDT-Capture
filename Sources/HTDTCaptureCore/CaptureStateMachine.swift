import Foundation

public enum CaptureState: String, Codable, Sendable, CaseIterable {
    case idle
    case setup
    case capabilityCheck = "capability_check"
    case permissions
    case preparing
    case scanning
    case paused
    case reviewing
    case annotating
    case validating
    case finalized
    case exported
    case failed
}

public enum CaptureFailureCode: String, Codable, Sendable, Equatable {
    case permissionDenied = "permission_denied"
    case unsupportedDevice = "unsupported_device"
    case trackingUnavailable = "tracking_unavailable"
    case roomPlanFailure = "roomplan_failure"
    case storagePressure = "storage_pressure"
    case persistenceFailure = "persistence_failure"
    case thermalPressure = "thermal_pressure"
    case interrupted
    case unknown
}

public enum CaptureEvent: Sendable, Equatable {
    /// Enter the pre-capture setup step (#212): the operator reviews
    /// device readiness and room-preparation guidance before the
    /// capability/permission pipeline runs. No capture session or
    /// RoomPlan authority exists in this state.
    case prepareCapture
    case beginCapabilityCheck
    case capabilitiesAccepted
    case permissionsGranted
    case prepared
    case pause
    case resume
    case beginReview
    case resumeScanning
    case beginAnnotation
    case beginValidation
    case validationFailed
    case finalize
    /// Adopt an already-persisted finalized revision whose bytes are
    /// durable truth: after relaunch (from `.idle`), after the
    /// irreversible commit point when post-promotion validation cannot
    /// prove the revision (from `.validating`), or when a racing failure
    /// resolved while a committed promotion was already durable (from
    /// `.failed`). This never fabricates Review or scanning state: the
    /// working set and its AR coordinate authority are gone.
    case adoptFinalized
    case export
    case fail(CaptureFailureCode)
    /// Operator-owned abort of a live (uncommitted) capture revision
    /// (issue #254): stops spatial capture, fences further writes, and
    /// returns to idle so the working set can be discarded. Distinct
    /// from `fail`, which preserves retained evidence for recovery, and
    /// from `reset`, which only resolves terminal/post-capture states.
    case abortCapture
    /// Reopen a persisted end-accepted working revision as a recovered
    /// draft (issue #297): `.idle` → `.reviewing` with spatial
    /// authority sealed. `.resumeScanning` is therefore unreachable on
    /// the recovered draft — the store fails live mutations closed
    /// before a UI affordance can offer them.
    case reopenDraft
    /// Leave Review back to `.idle` without discarding the working
    /// revision (issue #297): the durable end-accepted draft stays on
    /// disk and the session can reopen it later.
    case suspendReview
    case reset
}

public struct CaptureStateMachineError: Error, Sendable, Equatable {
    public let state: CaptureState
    public let event: CaptureEvent

    public init(state: CaptureState, event: CaptureEvent) {
        self.state = state
        self.event = event
    }
}

public struct CaptureStateMachine: Sendable, Equatable {
    public private(set) var state: CaptureState
    public private(set) var lastFailure: CaptureFailureCode?

    public init(state: CaptureState = .idle, lastFailure: CaptureFailureCode? = nil) {
        self.state = state
        self.lastFailure = lastFailure
    }

    public mutating func apply(_ event: CaptureEvent) throws {
        if case let .fail(code) = event,
           state != .finalized,
           state != .exported
        {
            state = .failed
            lastFailure = code
            return
        }

        switch (state, event) {
        case (.idle, .prepareCapture):
            state = .setup
        case (.setup, .beginCapabilityCheck),
             (.idle, .beginCapabilityCheck):
            state = .capabilityCheck
        case (.capabilityCheck, .capabilitiesAccepted):
            state = .permissions
        case (.permissions, .permissionsGranted):
            state = .preparing
        case (.preparing, .prepared):
            state = .scanning
        case (.scanning, .pause):
            state = .paused
        case (.paused, .resume):
            state = .scanning
        case (.scanning, .beginReview):
            state = .reviewing
        case (.reviewing, .resumeScanning):
            state = .scanning
        // #297: relaunch draft recovery — Review without live capture.
        case (.idle, .reopenDraft):
            state = .reviewing
            lastFailure = nil
        case (.reviewing, .suspendReview):
            state = .idle
            lastFailure = nil
        case (.reviewing, .beginAnnotation):
            state = .annotating
        case (.annotating, .beginReview):
            state = .reviewing
        case (.reviewing, .beginValidation), (.annotating, .beginValidation):
            state = .validating
        case (.validating, .validationFailed):
            state = .reviewing
        case (.validating, .finalize):
            state = .finalized
        case (.idle, .adoptFinalized), (.validating, .adoptFinalized),
             (.failed, .adoptFinalized):
            state = .finalized
        case (.finalized, .export):
            state = .exported
        // #254: aborting is legal at every pre-commit capture boundary.
        // `.validating` is deliberately excluded — the finalization
        // commit transaction owns the fence there, and an abort mid-
        // commit would race promotion; the abort must wait for the
        // validating attempt to resolve back to Review or Failed.
        case (.scanning, .abortCapture), (.paused, .abortCapture),
             (.reviewing, .abortCapture), (.annotating, .abortCapture):
            state = .idle
            lastFailure = nil
        // #295: the pre-capture prerequisite states are cancellable —
        // camera denial is a recovery workflow, not a failed capture,
        // so the operator may leave `.permissions` back to idle without
        // fabricating a working revision or a failed capture record.
        case (.setup, .reset), (.capabilityCheck, .reset),
             (.permissions, .reset), (.failed, .reset),
             (.finalized, .reset), (.exported, .reset):
            state = .idle
            lastFailure = nil
        default:
            throw CaptureStateMachineError(state: state, event: event)
        }
    }
}

extension CaptureFailureCode {
    /// Terminal resource/lifecycle conditions that the finalization
    /// commit policy can fence while a promotion is in flight (#185).
    /// Non-lifecycle failures (persistence, tracking, RoomPlan, ...)
    /// keep their ordinary immediate handling and still invalidate the
    /// capture generation.
    public var isLifecycleFailure: Bool {
        switch self {
        case .interrupted, .thermalPressure, .storagePressure:
            return true
        case .permissionDenied, .unsupportedDevice,
             .trackingUnavailable, .roomPlanFailure,
             .persistenceFailure, .unknown:
            return false
        }
    }
}

/// The phase of a host finalization commit transaction (#160/#185).
public enum FinalizationCommitPhase: String, Sendable, Equatable {
    /// No commit transaction is claimed.
    case inactive
    /// The transaction is claimed and the working-set seal is held,
    /// but the irreversible promotion has not committed. A fenced
    /// lifecycle failure may still cancel the transaction.
    case commitClaimed
    /// The atomic promotion already moved the working directory into
    /// `finalized/`. The revision is durable truth and must be adopted;
    /// rollback semantics no longer apply and commit wins over any
    /// fenced lifecycle failure.
    case promoted
}

/// Commit-point policy for host finalization (#160/#185).
///
/// The coordinator claims the commit transaction when finalization
/// begins (`claimCommit`), marks the irreversible filesystem promotion
/// (`markPromoted`), and resolves the transaction (`reset`) once the
/// outcome is applied. While the transaction is claimed, terminal
/// lifecycle/resource failures (`interrupted`, `thermalPressure`,
/// `storagePressure`) are fenced instead of invalidating the capture
/// generation underneath an in-flight promotion:
///
/// - before promotion, `preCommitFailure` lets the host cancel the
///   transaction with no finalized destination produced, then apply
///   the deferred failure through the ordinary Review/failed policy;
/// - after promotion, `postCommitFailure` is surfaced as post-capture
///   status while the promoted revision is adopted (commit wins).
///
/// Non-lifecycle failures are never fenced, and ordinary stale-callback
/// generation fencing is unchanged outside the transaction.
public struct FinalizationCommitPolicy: Sendable, Equatable {
    public private(set) var phase: FinalizationCommitPhase
    /// The first lifecycle failure fenced while the commit transaction
    /// was claimed, if any. Only the first is retained so the host
    /// applies a single deterministic lifecycle resolution.
    public private(set) var fencedFailure: CaptureFailureCode?

    public init(
        phase: FinalizationCommitPhase = .inactive,
        fencedFailure: CaptureFailureCode? = nil
    ) {
        self.phase = phase
        self.fencedFailure = fencedFailure
    }

    /// Whether the commit transaction is claimed and unresolved.
    public var isClaimed: Bool {
        phase != .inactive
    }

    /// Whether the irreversible promotion already committed.
    public var isPromoted: Bool {
        phase == .promoted
    }

    /// Claim the commit transaction. Claiming is idempotent so a
    /// retried finalization attempt cannot double-claim.
    public mutating func claimCommit() {
        if phase == .inactive {
            phase = .commitClaimed
        }
    }

    /// Record the irreversible promotion. Once marked, pre-commit
    /// cancellation is no longer available.
    public mutating func markPromoted() {
        if phase == .commitClaimed {
            phase = .promoted
        }
    }

    /// Fence a failure observed while the transaction is claimed.
    /// Returns true when `failure` is a lifecycle/resource failure
    /// absorbed by the policy; false when ordinary failure handling
    /// applies.
    public mutating func fenceLifecycleFailure(
        _ failure: CaptureFailureCode
    ) -> Bool {
        guard phase != .inactive,
              failure.isLifecycleFailure
        else {
            return false
        }
        if fencedFailure == nil {
            fencedFailure = failure
        }
        return true
    }

    /// The fenced failure that must cancel the transaction before
    /// promotion begins, if any. Once promoted this returns nil —
    /// pre-commit cancellation is no longer possible.
    public func preCommitFailure() -> CaptureFailureCode? {
        phase == .commitClaimed ? fencedFailure : nil
    }

    /// The fenced failure to surface as post-capture status after a
    /// committed promotion, if any.
    public func postCommitFailure() -> CaptureFailureCode? {
        phase == .promoted ? fencedFailure : nil
    }

    /// Resolve the transaction. A resolved commit no longer fences new
    /// failures.
    public mutating func reset() {
        phase = .inactive
        fencedFailure = nil
    }
}

/// Bounded-wait policy for an unresolved RoomPlan completion at End
/// (issue #96).
///
/// The RoomPlan completion callback carries no HTDT End-attempt token,
/// so after `RoomCaptureSession.stop` the host must not blindly restart
/// the session while a stale callback may still arrive. Instead the
/// host waits a bounded window: it publishes a "still processing"
/// warning after `warningDelay`, and terminates the unresolved End
/// attempt with a precise terminal failure once `terminationDelay` has
/// elapsed without a correlated completion. The bound is what keeps
/// the capture UI from remaining locked in `isEndingScan` forever when
/// the completion callback is genuinely lost.
public struct RoomPlanEndTimeoutPolicy: Sendable, Equatable {
    /// Delay from RoomPlan stop until the operator warning is
    /// published.
    public let warningDelay: Duration
    /// Total delay from RoomPlan stop until the unresolved attempt is
    /// terminated. Must exceed `warningDelay` so the warning is
    /// observable before termination.
    public let terminationDelay: Duration

    public init(
        warningDelay: Duration = .seconds(8),
        terminationDelay: Duration = .seconds(30)
    ) {
        precondition(warningDelay > .zero)
        precondition(
            terminationDelay > warningDelay,
            "the End timeout must terminate after the warning delay"
        )
        self.warningDelay = warningDelay
        self.terminationDelay = terminationDelay
    }

    /// Additional wait between the operator warning and termination of
    /// the unresolved attempt.
    public var unresolvedGracePeriod: Duration {
        terminationDelay - warningDelay
    }
}

/// Transition-compaction gate for canonical tracking history (#148).
///
/// The live scan loop samples AR tracking roughly four times per
/// second, but the working-set quality authority must record a bounded
/// history, not every sample. The gate emits the first observed
/// (state, reason) pair as the baseline and then emits only genuine
/// state/reason transitions; identical consecutive samples are
/// compacted away. The working-set store additionally bounds retained
/// history.
///
/// The gate is deliberately payload-agnostic about severity: a
/// transition into `.unavailable` is recorded faithfully and the
/// quality evaluator applies the configured policy to it.
public struct ScanTrackingTransitionGate: Sendable, Equatable {
    private var lastState: TrackingQualityState?
    private var lastReason: String?

    public init() {
        lastState = nil
        lastReason = nil
    }

    /// Whether `event` opens a new state/reason interval that should be
    /// persisted into the canonical tracking history.
    public mutating func shouldRecord(
        _ event: TrackingQualityEvent
    ) -> Bool {
        if lastState == event.state,
           lastReason == event.reason
        {
            return false
        }
        lastState = event.state
        lastReason = event.reason
        return true
    }

    /// Forget the current interval baseline. A fresh capture must start
    /// with an empty gate so its first sample is recorded.
    public mutating func reset() {
        lastState = nil
        lastReason = nil
    }
}
