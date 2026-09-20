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
    case beginAnnotation
    case beginValidation
    case validationFailed
    case finalize
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
        case (.finalized, .export):
            state = .exported
        case (.failed, .reset), (.exported, .reset):
            state = .idle
            lastFailure = nil
        default:
            throw CaptureStateMachineError(state: state, event: event)
        }
    }
}
