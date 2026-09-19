import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import RoomPlan

public enum PlatformCaptureError: Error {
    case roomPlanUnsupported
}

@available(iOS 17.0, *)
@MainActor
public final class SharedARSessionController {
    public let arSession: ARSession
    public private(set) var context: CaptureSessionContext
    public private(set) var roomCaptureSession: RoomCaptureSession?

    public init(
        arSession: ARSession = ARSession(),
        context: CaptureSessionContext = CaptureSessionContext()
    ) {
        self.arSession = arSession
        self.context = context
    }

    public func startRoomPlan(
        configuration: RoomCaptureSession.Configuration = .init()
    ) throws {
        guard RoomCaptureSession.isSupported else {
            throw PlatformCaptureError.roomPlanUnsupported
        }

        if roomCaptureSession == nil {
            roomCaptureSession = RoomCaptureSession(arSession: arSession)
        }
        roomCaptureSession?.run(configuration: configuration)
    }

    public func stopRoomPlanPreservingARSession() {
        roomCaptureSession?.stop(pauseARSession: false)
    }

    public func stopAndPauseARSession() {
        roomCaptureSession?.stop(pauseARSession: true)
        roomCaptureSession = nil
    }

    @discardableResult
    public func registerSpatialDiscontinuity(
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double? = nil
    ) -> CoordinateSpaceID {
        context.registerDiscontinuity(
            reason: reason,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }
}
#endif
