import Foundation

public enum CoordinateDiscontinuityReason: String, Codable, Sendable, Equatable {
    case arSessionRestart = "ar_session_restart"
    case worldOriginReset = "world_origin_reset"
    case relocalizationFailure = "relocalization_failure"
    case incompatibleReconfiguration = "incompatible_reconfiguration"
    case explicitNewSession = "explicit_new_session"
}

public struct CoordinateSpaceTransition: Codable, Sendable, Equatable {
    public let previous: CoordinateSpaceID
    public let next: CoordinateSpaceID
    public let reason: CoordinateDiscontinuityReason
    public let sessionTimestampSeconds: Double?

    public init(
        previous: CoordinateSpaceID,
        next: CoordinateSpaceID,
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double?
    ) {
        self.previous = previous
        self.next = next
        self.reason = reason
        self.sessionTimestampSeconds = sessionTimestampSeconds
    }
}

public struct CaptureSessionContext: Codable, Sendable, Equatable {
    public let captureSessionID: CaptureSessionID
    public private(set) var coordinateSpaceID: CoordinateSpaceID
    public private(set) var coordinateTransitions: [CoordinateSpaceTransition]

    public init(
        captureSessionID: CaptureSessionID = CaptureSessionID(),
        coordinateSpaceID: CoordinateSpaceID = CoordinateSpaceID(),
        coordinateTransitions: [CoordinateSpaceTransition] = []
    ) {
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.coordinateTransitions = coordinateTransitions
    }

    @discardableResult
    public mutating func registerDiscontinuity(
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double? = nil
    ) -> CoordinateSpaceID {
        let next = CoordinateSpaceID()
        coordinateTransitions.append(
            CoordinateSpaceTransition(
                previous: coordinateSpaceID,
                next: next,
                reason: reason,
                sessionTimestampSeconds: sessionTimestampSeconds
            )
        )
        coordinateSpaceID = next
        return next
    }
}
