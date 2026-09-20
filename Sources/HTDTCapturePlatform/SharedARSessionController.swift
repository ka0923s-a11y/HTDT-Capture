import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import Foundation
import RoomPlan

public enum PlatformCaptureError: Error {
    case roomPlanUnsupported
    case currentFrameUnavailable
}

@available(iOS 17.0, *)
@MainActor
private final class RoomPlanSessionDelegateBridge:
    NSObject,
    RoomCaptureSessionDelegate
{
    var completionHandler: (
        (CapturedRoomData, (any Error)?) -> Void
    )?

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        completionHandler?(data, error)
    }
}

@available(iOS 17.0, *)
@MainActor
public final class SharedARSessionController {
    public let arSession: ARSession
    public private(set) var context: CaptureSessionContext
    public private(set) var roomCaptureSession: RoomCaptureSession?

    private let roomPlanDelegateBridge =
        RoomPlanSessionDelegateBridge()

    public init(
        arSession: ARSession = ARSession(),
        context: CaptureSessionContext = CaptureSessionContext()
    ) {
        self.arSession = arSession
        self.context = context
    }

    public func setRoomPlanCompletionHandler(
        _ handler: @escaping (
            CapturedRoomData,
            (any Error)?
        ) -> Void
    ) {
        roomPlanDelegateBridge.completionHandler = handler
        roomCaptureSession?.delegate = roomPlanDelegateBridge
    }

    public func startRoomPlan(
        configuration: RoomCaptureSession.Configuration = .init()
    ) throws {
        guard RoomCaptureSession.isSupported else {
            throw PlatformCaptureError.roomPlanUnsupported
        }

        if roomCaptureSession == nil {
            let session = RoomCaptureSession(arSession: arSession)
            session.delegate = roomPlanDelegateBridge
            roomCaptureSession = session
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

    public func snapshotActiveMeshAnchors() throws -> [MeshAnchorSnapshot] {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted {
                $0.identifier.uuidString.lowercased()
                    < $1.identifier.uuidString.lowercased()
            }

        return try anchors.map { anchor in
            try ARMeshSnapshotAdapter.snapshot(
                anchor: anchor,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                sessionTimestampSeconds: frame.timestamp
            )
        }
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
