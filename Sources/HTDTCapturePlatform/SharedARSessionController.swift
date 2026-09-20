import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import Foundation
import RoomPlan

public enum PlatformCaptureError: Error {
    case roomPlanUnsupported
    case currentFrameUnavailable
    case raycastMiss
}

public struct CapturedRaycastPlacement: Sendable {
    public let positionWorld: Float3
    public let frameArtifacts: CapturedFrameArtifacts

    public init(
        positionWorld: Float3,
        frameArtifacts: CapturedFrameArtifacts
    ) {
        self.positionWorld = positionWorld
        self.frameArtifacts = frameArtifacts
    }
}

public struct CaptureReviewEvidenceSnapshot: Sendable {
    public let meshAnchors: [MeshAnchorSnapshot]
    public let frameArtifacts: CapturedFrameArtifacts
    public let trackingQualityEvent: TrackingQualityEvent

    public init(
        meshAnchors: [MeshAnchorSnapshot],
        frameArtifacts: CapturedFrameArtifacts,
        trackingQualityEvent: TrackingQualityEvent
    ) {
        self.meshAnchors = meshAnchors
        self.frameArtifacts = frameArtifacts
        self.trackingQualityEvent = trackingQualityEvent
    }
}

@available(iOS 17.0, *)
@MainActor
private final class RoomPlanSessionDelegateBridge:
    NSObject,
    @preconcurrency RoomCaptureSessionDelegate
{
    var completionHandler: (
        @MainActor (CapturedRoomData, (any Error)?) -> Void
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
        _ handler: @escaping @MainActor (
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
        return try snapshotMeshAnchors(from: frame)
    }

    public func snapshotCenterRaycastPlacement(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedRaycastPlacement {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let origin = SIMD3<Float>(
            camera.columns.3.x,
            camera.columns.3.y,
            camera.columns.3.z
        )
        let direction = SIMD3<Float>(
            -camera.columns.2.x,
            -camera.columns.2.y,
            -camera.columns.2.z
        )

        let targets: [ARRaycastQuery.Target] = [
            .existingPlaneGeometry,
            .estimatedPlane,
        ]
        var hit: ARRaycastResult?
        for target in targets {
            let query = ARRaycastQuery(
                origin: origin,
                direction: direction,
                allowing: target,
                alignment: .any
            )
            if let result = arSession.raycast(query).first {
                hit = result
                break
            }
        }

        guard let hit else {
            throw PlatformCaptureError.raycastMiss
        }

        let position = hit.worldTransform.columns.3
        return CapturedRaycastPlacement(
            positionWorld: Float3(
                position.x,
                position.y,
                position.z
            ),
            frameArtifacts: try ARFrameArtifactAdapter.capture(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            )
        )
    }

    public func snapshotTimingCorrelation()
        throws -> CaptureTimingCorrelation
    {
        let before = Date()
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        let after = Date()

        let midpoint = Date(
            timeIntervalSince1970:
                (
                    before.timeIntervalSince1970
                    + after.timeIntervalSince1970
                ) / 2
        )
        let uncertainty =
            max(0, after.timeIntervalSince(before) / 2)

        return try CaptureTimingCorrelation(
            monotonicSeconds: frame.timestamp,
            utc: BundleTimestamp.utcString(from: midpoint),
            method: "bracketed_arframe_current_frame",
            estimatedUncertaintySeconds: uncertainty
        )
    }

    public func snapshotFrameEvidence(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameArtifacts {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        return try ARFrameArtifactAdapter.capture(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: depthSelection
        )
    }

    public func snapshotReviewEvidence(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CaptureReviewEvidenceSnapshot {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        return CaptureReviewEvidenceSnapshot(
            meshAnchors: try snapshotMeshAnchors(from: frame),
            frameArtifacts: try ARFrameArtifactAdapter.capture(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            ),
            trackingQualityEvent: trackingQualityEvent(from: frame)
        )
    }

    private func trackingQualityEvent(
        from frame: ARFrame
    ) -> TrackingQualityEvent {
        switch frame.camera.trackingState {
        case .normal:
            return TrackingQualityEvent(
                sessionTimestampSeconds: frame.timestamp,
                state: .normal
            )
        case .notAvailable:
            return TrackingQualityEvent(
                sessionTimestampSeconds: frame.timestamp,
                state: .unavailable,
                reason: "arkit_not_available"
            )
        case let .limited(reason):
            return TrackingQualityEvent(
                sessionTimestampSeconds: frame.timestamp,
                state: .limited,
                reason: trackingReasonToken(reason)
            )
        }
    }

    private func trackingReasonToken(
        _ reason: ARCamera.TrackingState.Reason
    ) -> String {
        switch reason {
        case .initializing:
            return "initializing"
        case .excessiveMotion:
            return "excessive_motion"
        case .insufficientFeatures:
            return "insufficient_features"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }

    private func snapshotMeshAnchors(
        from frame: ARFrame
    ) throws -> [MeshAnchorSnapshot] {
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
