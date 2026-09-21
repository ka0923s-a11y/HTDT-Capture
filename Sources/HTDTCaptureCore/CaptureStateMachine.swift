import Foundation

public enum CaptureState: String, Codable, Sendable, CaseIterable {
    case idle
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
        case (.idle, .beginCapabilityCheck):
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
        case (.failed, .reset), (.finalized, .reset),
             (.exported, .reset):
            state = .idle
            lastFailure = nil
        default:
            throw CaptureStateMachineError(state: state, event: event)
        }
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
