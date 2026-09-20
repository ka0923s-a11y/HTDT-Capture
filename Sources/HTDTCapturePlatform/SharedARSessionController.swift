import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import Foundation
import RoomPlan
import simd

public enum PlatformCaptureError: Error {
    case roomPlanUnsupported
    case currentFrameUnavailable
    case raycastMiss
    case orientationUnavailable
}

public struct CapturedSpeakerOrientation: Sendable {
    public let frontAxisWorld: SpatialVector3F
    public let frameArtifacts: CapturedFrameArtifacts

    public init(
        frontAxisWorld: SpatialVector3F,
        frameArtifacts: CapturedFrameArtifacts
    ) {
        self.frontAxisWorld = frontAxisWorld
        self.frameArtifacts = frameArtifacts
    }
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
@objc(HTDTRoomPlanViewDelegateBridge)
private final class RoomPlanViewDelegateBridge:
    NSObject,
    @preconcurrency RoomCaptureViewDelegate
{
    var completionHandler: (
        @MainActor (CapturedRoomData, (any Error)?) -> Void
    )?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
    }

    func encode(with coder: NSCoder) {
        // RoomCaptureViewDelegate inherits NSCoding. This bridge has no
        // persistent state; capture authority remains in the host/store.
    }

    func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: (any Error)?
    ) -> Bool {
        completionHandler?(roomDataForProcessing, error)
        return false
    }
}

@available(iOS 17.0, *)
@MainActor
public final class SharedARSessionController {
    public let arSession: ARSession
    public let roomCaptureView: RoomCaptureView
    public private(set) var context: CaptureSessionContext

    public var roomCaptureSession: RoomCaptureSession? {
        roomCaptureView.captureSession
    }

    private let roomPlanDelegateBridge =
        RoomPlanViewDelegateBridge()
    private var liveRoomCaptureViewMountObserved = false

    public init(
        arSession: ARSession = ARSession(),
        context: CaptureSessionContext = CaptureSessionContext()
    ) {
        self.arSession = arSession
        self.context = context
        self.roomCaptureView = RoomCaptureView(
            frame: .zero,
            arSession: arSession
        )
        self.roomCaptureView.isModelEnabled = true
        self.roomCaptureView.delegate = roomPlanDelegateBridge
    }

    func markLiveRoomCaptureViewMounted(
        _ view: RoomCaptureView
    ) {
        guard view === roomCaptureView else {
            return
        }
        liveRoomCaptureViewMountObserved = true
        roomCaptureView.setNeedsLayout()
        roomCaptureView.layoutIfNeeded()
    }

    func markLiveRoomCaptureViewUnmounted(
        _ view: RoomCaptureView
    ) {
        guard view === roomCaptureView else {
            return
        }
        liveRoomCaptureViewMountObserved = false
    }

    public func waitForLiveRoomCaptureViewPresentation()
        async -> Bool
    {
        for _ in 0..<60 {
            if liveRoomCaptureViewMountObserved,
               roomCaptureView.window != nil,
               roomCaptureView.bounds.width > 1,
               roomCaptureView.bounds.height > 1
            {
                return true
            }

            if Task.isCancelled {
                return false
            }

            try? await Task.sleep(
                for: .milliseconds(50)
            )
        }

        return false
    }

    public func setRoomPlanCompletionHandler(
        _ handler: @escaping @MainActor (
            CapturedRoomData,
            (any Error)?
        ) -> Void
    ) {
        roomPlanDelegateBridge.completionHandler = handler
        roomCaptureView.delegate = roomPlanDelegateBridge
    }

    public func startRoomPlan(
        configuration: RoomCaptureSession.Configuration = .init()
    ) throws {
        guard RoomCaptureSession.isSupported else {
            throw PlatformCaptureError.roomPlanUnsupported
        }

        guard let roomCaptureSession else {
            throw PlatformCaptureError.roomPlanUnsupported
        }
        roomCaptureSession.run(configuration: configuration)
    }

    public func stopRoomPlanPreservingARSession() {
        roomCaptureSession?.stop(pauseARSession: false)
    }

    public func stopAndPauseARSession() {
        roomCaptureSession?.stop(pauseARSession: true)
    }

    public func currentScanCoverageSample()
        throws -> ScanCoverageSample
    {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let forward = SIMD3<Double>(
            Double(-camera.columns.2.x),
            Double(-camera.columns.2.y),
            Double(-camera.columns.2.z)
        )
        let horizontalMagnitude = hypot(forward.x, forward.z)
        let yaw = atan2(forward.x, -forward.z)
        let pitch = atan2(
            forward.y,
            max(horizontalMagnitude, 0.000_001)
        )
        let tracking = trackingQualityEvent(from: frame)
        let cameraPosition = ScanCameraPosition(
            x: Double(camera.columns.3.x),
            y: Double(camera.columns.3.y),
            z: Double(camera.columns.3.z)
        )
        let meshAnchorCount = frame.anchors.reduce(into: 0) {
            count,
            anchor in
            if anchor is ARMeshAnchor {
                count += 1
            }
        }

        return ScanCoverageSample(
            sessionTimestampSeconds: frame.timestamp,
            yawRadians: yaw,
            pitchRadians: pitch,
            cameraPosition: cameraPosition,
            trackingState: tracking.state,
            trackingReason: tracking.reason,
            activeMeshAnchorCount: meshAnchorCount,
            hasSceneDepth:
                frame.sceneDepth != nil
                || frame.smoothedSceneDepth != nil
        )
    }

    public func currentSpatialCoverageSample(
        maxSurfacePoints: Int = 96
    ) throws -> SpatialCoverageSample {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let cameraFromWorld = simd_inverse(camera)
        let cameraPosition = SpatialCoveragePoint3D(
            x: Double(camera.columns.3.x),
            y: Double(camera.columns.3.y),
            z: Double(camera.columns.3.z)
        )
        let forward = SIMD3<Double>(
            Double(-camera.columns.2.x),
            Double(-camera.columns.2.y),
            Double(-camera.columns.2.z)
        )
        let yaw = atan2(forward.x, -forward.z)
        let tracking = trackingQualityEvent(from: frame)

        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted {
                $0.identifier.uuidString.lowercased()
                    < $1.identifier.uuidString.lowercased()
            }

        let sceneReconstructionSupported =
            ARWorldTrackingConfiguration
                .supportsSceneReconstruction(.mesh)
        let activeConfigurationName =
            arSession.configuration.map {
                String(describing: type(of: $0))
            }

        let sceneReconstructionEnabled: Bool
        if let worldConfiguration =
            arSession.configuration as? ARWorldTrackingConfiguration
        {
            sceneReconstructionEnabled =
                !worldConfiguration.sceneReconstruction.isEmpty
        } else {
            sceneReconstructionEnabled = false
        }

        let meshAvailability = MeshAvailabilityDiagnostic(
            sceneReconstructionSupported:
                sceneReconstructionSupported,
            sceneReconstructionEnabled:
                sceneReconstructionEnabled,
            activeMeshAnchorCount: anchors.count,
            activeConfigurationName:
                activeConfigurationName,
            configurationMismatchSuspected:
                sceneReconstructionSupported
                && !sceneReconstructionEnabled
        )

        let budget = min(max(maxSurfacePoints, 0), 128)
        var points: [SpatialCoveragePoint3D] = []
        points.reserveCapacity(budget)

        if budget > 0, !anchors.isEmpty {
            let perAnchorBudget =
                max(1, budget / anchors.count)

            for anchor in anchors.prefix(budget) {
                guard points.count < budget else {
                    break
                }

                let vertices = anchor.geometry.vertices
                guard vertices.count > 0 else {
                    continue
                }

                let anchorBudget = min(
                    perAnchorBudget,
                    budget - points.count
                )
                let vertexStride = max(
                    1,
                    vertices.count / max(anchorBudget, 1)
                )

                var index = 0
                var sampled = 0
                while index < vertices.count,
                      points.count < budget,
                      sampled < anchorBudget
                {
                    let address =
                        vertices.buffer.contents()
                            .advanced(
                                by:
                                    vertices.offset
                                    + index * vertices.stride
                            )
                    let local = address
                        .assumingMemoryBound(
                            to: SIMD3<Float>.self
                        )
                        .pointee
                    let world =
                        anchor.transform
                        * SIMD4<Float>(
                            local.x,
                            local.y,
                            local.z,
                            1
                        )
                    let cameraLocal =
                        cameraFromWorld * world
                    let forwardDepth =
                        -cameraLocal.z
                    let isCurrentViewCandidate =
                        forwardDepth >= 0.15
                        && forwardDepth <= 6.0
                        && abs(cameraLocal.x)
                            <= forwardDepth * 0.95
                        && abs(cameraLocal.y)
                            <= forwardDepth * 0.85

                    if isCurrentViewCandidate {
                        points.append(
                            SpatialCoveragePoint3D(
                                x: Double(world.x),
                                y: Double(world.y),
                                z: Double(world.z)
                            )
                        )
                    }

                    index += vertexStride
                    sampled += 1
                }
            }
        }

        return SpatialCoverageSample(
            sessionTimestampSeconds: frame.timestamp,
            cameraPositionWorld: cameraPosition,
            cameraYawRadians: yaw,
            trackingState: tracking.state,
            hasSceneDepth:
                frame.sceneDepth != nil
                || frame.smoothedSceneDepth != nil,
            meshAvailability: meshAvailability,
            surfacePointsWorld: points
        )
    }

    public func snapshotActiveMeshAnchors() throws -> [MeshAnchorSnapshot] {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        return try snapshotMeshAnchors(from: frame)
    }

    public func snapshotHorizontalCameraHeading(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedSpeakerOrientation {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let x = -camera.columns.2.x
        let z = -camera.columns.2.z
        let magnitude = sqrt(x * x + z * z)
        guard magnitude.isFinite, magnitude > 0.001 else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let front = try SpatialVector3F.unit(
            x / magnitude,
            0,
            z / magnitude
        )
        return CapturedSpeakerOrientation(
            frontAxisWorld: front,
            frameArtifacts: try ARFrameArtifactAdapter.capture(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            )
        )
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
