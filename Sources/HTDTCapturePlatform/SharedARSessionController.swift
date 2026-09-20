import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import CoreVideo
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
    public let meshSnapshotSucceeded: Bool
    public let frameArtifacts: CapturedFrameArtifacts
    public let trackingQualityEvent: TrackingQualityEvent

    public init(
        meshAnchors: [MeshAnchorSnapshot],
        meshSnapshotSucceeded: Bool = true,
        frameArtifacts: CapturedFrameArtifacts,
        trackingQualityEvent: TrackingQualityEvent
    ) {
        self.meshAnchors = meshAnchors
        self.meshSnapshotSucceeded = meshSnapshotSucceeded
        self.frameArtifacts = frameArtifacts
        self.trackingQualityEvent = trackingQualityEvent
    }
}

public struct DerivedShapeLiveObservationSet: Sendable {
    public let objectObservation: DerivedShapeObservation?
    public let objectVolumeObservation: DerivedShapeObservation?
    public let wallObservation: DerivedShapeObservation?
    public let floorReferenceY: Double?

    public init(
        objectObservation: DerivedShapeObservation?,
        objectVolumeObservation: DerivedShapeObservation? = nil,
        wallObservation: DerivedShapeObservation?,
        floorReferenceY: Double? = nil
    ) {
        self.objectObservation = objectObservation
        self.objectVolumeObservation = objectVolumeObservation
        self.wallObservation = wallObservation
        self.floorReferenceY = floorReferenceY
    }

    public static let empty = DerivedShapeLiveObservationSet(
        objectObservation: nil,
        objectVolumeObservation: nil,
        wallObservation: nil,
        floorReferenceY: nil
    )
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

        var evidenceSource: SpatialCoverageEvidenceSource =
            points.isEmpty ? .none : .mesh

        if points.isEmpty, budget > 0 {
            let depthPoints = liveSceneDepthWorldPoints(
                frame: frame,
                maxPoints: budget,
                cropFraction: 0.95,
                minimumDepthMeters: 0.15,
                maximumDepthMeters: 5.5
            )
            points = depthPoints.map {
                SpatialCoveragePoint3D(
                    x: Double($0.x),
                    y: Double($0.y),
                    z: Double($0.z)
                )
            }
            if !points.isEmpty {
                evidenceSource = .sceneDepth
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
            surfaceEvidenceSource: evidenceSource,
            surfacePointsWorld: points
        )
    }

    public func currentDerivedShapeObservations(
        maxObjectPoints: Int = 384,
        maxWallPoints: Int = 512
    ) throws -> DerivedShapeLiveObservationSet {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let cameraPosition = frame.camera.transform.columns.3
        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted { lhs, rhs in
                let lhsPosition = lhs.transform.columns.3
                let rhsPosition = rhs.transform.columns.3
                let lhsDistance =
                    pow(lhsPosition.x - cameraPosition.x, 2)
                    + pow(lhsPosition.y - cameraPosition.y, 2)
                    + pow(lhsPosition.z - cameraPosition.z, 2)
                let rhsDistance =
                    pow(rhsPosition.x - cameraPosition.x, 2)
                    + pow(rhsPosition.y - cameraPosition.y, 2)
                    + pow(rhsPosition.z - cameraPosition.z, 2)
                if abs(lhsDistance - rhsDistance) > 0.000_001 {
                    return lhsDistance < rhsDistance
                }
                return lhs.identifier.uuidString.lowercased()
                    < rhs.identifier.uuidString.lowercased()
            }

        let meshObjectObservation =
            liveDerivedShapeObservation(
                anchors: anchors,
                classifications: [.table, .seat, .none],
                sessionTimestampSeconds: frame.timestamp,
                voxelSizeMeters: 0.035,
                maxPoints: maxObjectPoints,
                maxInspectedFaces: 10_000
            )
        let wallObservation =
            liveDerivedShapeObservation(
                anchors: anchors,
                classifications: [.wall],
                sessionTimestampSeconds: frame.timestamp,
                voxelSizeMeters: 0.06,
                maxPoints: maxWallPoints,
                maxInspectedFaces: 12_000
            )
        let meshFloorReferenceY = liveFloorReferenceY(
            anchors: anchors,
            maxInspectedFaces: 2_500,
            maxSamples: 192
        )

        let depthWorldPoints = liveSceneDepthWorldPoints(
            frame: frame,
            maxPoints: min(
                max(maxObjectPoints * 3, 512),
                1_152
            ),
            cropFraction: 0.92,
            minimumDepthMeters: 0.18,
            maximumDepthMeters: 4.5
        )
        let depthFloorReferenceY =
            meshFloorReferenceY
            ?? estimatedFloorY(from: depthWorldPoints)

        let depthVolumeObservation =
            liveDepthDerivedShapeObservation(
                points: depthWorldPoints,
                sessionTimestampSeconds: frame.timestamp,
                floorReferenceY: depthFloorReferenceY,
                voxelSizeMeters: 0.05,
                maxPoints: max(maxObjectPoints, 512)
            )

        let objectObservation: DerivedShapeObservation?
        if let meshObjectObservation,
           meshObjectObservation.points.count >= 8
        {
            objectObservation = meshObjectObservation
        } else {
            objectObservation = depthVolumeObservation
        }

        return DerivedShapeLiveObservationSet(
            objectObservation: objectObservation,
            objectVolumeObservation:
                depthVolumeObservation
                ?? objectObservation,
            wallObservation: wallObservation,
            floorReferenceY: depthFloorReferenceY
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

    public func snapshotTrackingQualityEvent()
        throws -> TrackingQualityEvent
    {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        return trackingQualityEvent(from: frame)
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

        let meshAnchors: [MeshAnchorSnapshot]
        let meshSnapshotSucceeded: Bool
        do {
            meshAnchors = try snapshotMeshAnchors(from: frame)
            meshSnapshotSucceeded = true
        } catch {
            meshAnchors = []
            meshSnapshotSucceeded = false
        }

        return CaptureReviewEvidenceSnapshot(
            meshAnchors: meshAnchors,
            meshSnapshotSucceeded: meshSnapshotSucceeded,
            frameArtifacts: try ARFrameArtifactAdapter.capture(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            ),
            trackingQualityEvent: trackingQualityEvent(from: frame)
        )
    }

    private func liveSceneDepthWorldPoints(
        frame: ARFrame,
        maxPoints: Int,
        cropFraction: Float,
        minimumDepthMeters: Float,
        maximumDepthMeters: Float
    ) -> [SIMD3<Float>] {
        guard maxPoints > 0,
              cropFraction.isFinite,
              cropFraction > 0,
              minimumDepthMeters.isFinite,
              maximumDepthMeters.isFinite,
              minimumDepthMeters > 0,
              maximumDepthMeters > minimumDepthMeters,
              let depthData =
                frame.smoothedSceneDepth ?? frame.sceneDepth
        else {
            return []
        }

        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 1, height > 1 else {
            return []
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let depthBaseAddress =
                CVPixelBufferGetBaseAddress(depthMap)
        else {
            return []
        }

        let confidenceMap = depthData.confidenceMap
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(
                confidenceMap,
                .readOnly
            )
        }
        defer {
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(
                    confidenceMap,
                    .readOnly
                )
            }
        }

        let boundedCrop = min(max(cropFraction, 0.25), 1.0)
        let horizontalInset =
            Int(Float(width) * (1 - boundedCrop) / 2)
        let verticalInset =
            Int(Float(height) * (1 - boundedCrop) / 2)
        let minX = min(max(horizontalInset, 0), width - 1)
        let maxX = max(minX + 1, width - horizontalInset)
        let minY = min(max(verticalInset, 0), height - 1)
        let maxY = max(minY + 1, height - verticalInset)

        let sampleArea =
            max(1, (maxX - minX) * (maxY - minY))
        let step = max(
            1,
            Int(
                ceil(
                    sqrt(
                        Double(sampleArea)
                        / Double(maxPoints)
                    )
                )
            )
        )

        let imageResolution = frame.camera.imageResolution
        guard imageResolution.width > 0,
              imageResolution.height > 0
        else {
            return []
        }

        let scaleX =
            Float(width) / Float(imageResolution.width)
        let scaleY =
            Float(height) / Float(imageResolution.height)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY
        guard fx.isFinite, fy.isFinite,
              fx > 0, fy > 0
        else {
            return []
        }

        let depthBytesPerRow =
            CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceBytesPerRow =
            confidenceMap.map {
                CVPixelBufferGetBytesPerRow($0)
            } ?? 0
        let confidenceBaseAddress =
            confidenceMap.flatMap {
                CVPixelBufferGetBaseAddress($0)
            }

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(maxPoints)

        var y = minY + step / 2
        while y < maxY, points.count < maxPoints {
            let depthRow = depthBaseAddress
                .advanced(by: y * depthBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            let confidenceRow =
                confidenceBaseAddress?
                    .advanced(by: y * confidenceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)

            var x = minX + step / 2
            while x < maxX, points.count < maxPoints {
                let depth = depthRow[x]
                guard depth.isFinite,
                      depth >= minimumDepthMeters,
                      depth <= maximumDepthMeters
                else {
                    x += step
                    continue
                }

                if let confidenceRow,
                   confidenceRow[x] == 0
                {
                    x += step
                    continue
                }

                let localX =
                    (Float(x) - cx) * depth / fx
                let localY =
                    -(Float(y) - cy) * depth / fy
                let cameraPoint = SIMD4<Float>(
                    localX,
                    localY,
                    -depth,
                    1
                )
                let world = frame.camera.transform * cameraPoint
                if world.x.isFinite,
                   world.y.isFinite,
                   world.z.isFinite
                {
                    points.append(
                        SIMD3<Float>(
                            world.x,
                            world.y,
                            world.z
                        )
                    )
                }

                x += step
            }
            y += step
        }

        return points
    }

    private func estimatedFloorY(
        from points: [SIMD3<Float>]
    ) -> Double? {
        let values = points
            .map { Double($0.y) }
            .filter(\.isFinite)
            .sorted()
        guard values.count >= 24,
              let first = values.first,
              let last = values.last,
              last - first >= 0.35
        else {
            return nil
        }

        let index = min(
            values.count - 1,
            Int(Double(values.count - 1) * 0.10)
        )
        return values[index]
    }

    private func liveDepthDerivedShapeObservation(
        points: [SIMD3<Float>],
        sessionTimestampSeconds: Double,
        floorReferenceY: Double?,
        voxelSizeMeters: Double,
        maxPoints: Int
    ) -> DerivedShapeObservation? {
        guard maxPoints > 0,
              voxelSizeMeters.isFinite,
              voxelSizeMeters > 0
        else {
            return nil
        }

        let filtered = points.filter { point in
            guard point.x.isFinite,
                  point.y.isFinite,
                  point.z.isFinite
            else {
                return false
            }
            guard let floorReferenceY else {
                return true
            }
            return Double(point.y) >= floorReferenceY + 0.05
        }

        let observations = filtered.enumerated().map {
            index,
            point in
            DerivedObservationPoint(
                position: DerivedPoint2D(
                    x: Double(point.x),
                    y: Double(point.z)
                ),
                evidenceRef:
                    "live-scene-depth:"
                    + String(
                        format: "%.3f",
                        sessionTimestampSeconds
                    )
                    + ":"
                    + String(index),
                evidenceKind: .sceneDepth,
                verticalPositionMeters: Double(point.y)
            )
        }

        let reduced = reduceLiveDerivedPoints(
            observations,
            voxelSizeMeters: voxelSizeMeters,
            maxPoints: maxPoints
        )
        guard reduced.count >= 8 else {
            return nil
        }

        return DerivedShapeObservation(
            coordinateSpaceID: context.coordinateSpaceID,
            points: reduced,
            observationStartSeconds: sessionTimestampSeconds,
            observationEndSeconds: sessionTimestampSeconds
        )
    }

    private func liveDerivedShapeObservation(
        anchors: [ARMeshAnchor],
        classifications requestedClassifications: [ARMeshClassification],
        sessionTimestampSeconds: Double,
        voxelSizeMeters: Double,
        maxPoints: Int,
        maxInspectedFaces: Int
    ) -> DerivedShapeObservation? {
        guard maxPoints > 0,
              maxInspectedFaces > 0,
              voxelSizeMeters.isFinite,
              voxelSizeMeters > 0
        else {
            return nil
        }

        var edges: [LiveDerivedMeshEdgeKey: LiveDerivedMeshEdgeRecord] = [:]
        var fallbackPoints: [DerivedObservationPoint] = []
        var inspectedFaces = 0

        outer: for anchor in anchors {
            let geometry = anchor.geometry
            guard let geometryClassifications = geometry.classification,
                  geometry.faces.indexCountPerPrimitive == 3,
                  geometry.faces.bytesPerIndex == 2
                    || geometry.faces.bytesPerIndex == 4
            else {
                continue
            }

            for faceIndex in 0..<geometry.faces.count {
                if inspectedFaces >= maxInspectedFaces {
                    break outer
                }
                inspectedFaces += 1

                let classificationPointer =
                    geometryClassifications.buffer.contents().advanced(
                        by:
                            geometryClassifications.offset
                            + faceIndex * geometryClassifications.stride
                    )
                let rawClassification =
                    classificationPointer
                        .assumingMemoryBound(to: UInt8.self)
                        .pointee
                guard requestedClassifications.contains(where: {
                    rawClassification
                        == UInt8(truncatingIfNeeded: $0.rawValue)
                }) else {
                    continue
                }

                guard let indices = liveMeshFaceIndices(
                    geometry: geometry,
                    faceIndex: faceIndex
                ) else {
                    continue
                }

                let vertices = indices.compactMap {
                    liveMeshWorldVertex(
                        geometry: geometry,
                        vertexIndex: Int($0),
                        transform: anchor.transform
                    )
                }
                guard vertices.count == 3 else {
                    continue
                }

                let evidenceRef =
                    "live-mesh:"
                    + anchor.identifier.uuidString.lowercased()
                    + ":face:"
                    + String(faceIndex)

                for point in vertices {
                    fallbackPoints.append(
                        DerivedObservationPoint(
                            position: DerivedPoint2D(
                                x: Double(point.x),
                                y: Double(point.z)
                            ),
                            evidenceRef: evidenceRef,
                            evidenceKind: .mesh,
                            verticalPositionMeters: Double(point.y)
                        )
                    )
                }

                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[0],
                    firstPoint: vertices[0],
                    secondIndex: indices[1],
                    secondPoint: vertices[1],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[1],
                    firstPoint: vertices[1],
                    secondIndex: indices[2],
                    secondPoint: vertices[2],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[2],
                    firstPoint: vertices[2],
                    secondIndex: indices[0],
                    secondPoint: vertices[0],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
            }
        }

        let boundaryPoints = edges.values
            .filter { $0.count == 1 }
            .flatMap { edge in
                [
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: Double(edge.firstPoint.x),
                            y: Double(edge.firstPoint.z)
                        ),
                        evidenceRef: edge.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: Double(edge.firstPoint.y)
                    ),
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: Double(edge.secondPoint.x),
                            y: Double(edge.secondPoint.z)
                        ),
                        evidenceRef: edge.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: Double(edge.secondPoint.y)
                    ),
                ]
            }

        let sourcePoints =
            boundaryPoints.count >= 8
            ? boundaryPoints
            : fallbackPoints

        let reduced = reduceLiveDerivedPoints(
            sourcePoints,
            voxelSizeMeters: voxelSizeMeters,
            maxPoints: maxPoints
        )
        guard !reduced.isEmpty else {
            return nil
        }

        return DerivedShapeObservation(
            coordinateSpaceID: context.coordinateSpaceID,
            points: reduced,
            observationStartSeconds: sessionTimestampSeconds,
            observationEndSeconds: sessionTimestampSeconds
        )
    }

    private func liveFloorReferenceY(
        anchors: [ARMeshAnchor],
        maxInspectedFaces: Int,
        maxSamples: Int
    ) -> Double? {
        guard maxInspectedFaces > 0, maxSamples > 0 else {
            return nil
        }

        var inspectedFaces = 0
        var samples: [Double] = []
        samples.reserveCapacity(maxSamples)

        outer: for anchor in anchors {
            let geometry = anchor.geometry
            guard let classifications = geometry.classification,
                  geometry.faces.indexCountPerPrimitive == 3
            else {
                continue
            }

            for faceIndex in 0..<geometry.faces.count {
                if inspectedFaces >= maxInspectedFaces
                    || samples.count >= maxSamples
                {
                    break outer
                }
                inspectedFaces += 1

                let pointer = classifications.buffer.contents().advanced(
                    by:
                        classifications.offset
                        + faceIndex * classifications.stride
                )
                let rawClassification = pointer
                    .assumingMemoryBound(to: UInt8.self)
                    .pointee
                guard rawClassification
                        == UInt8(
                            truncatingIfNeeded:
                                ARMeshClassification.floor.rawValue
                        ),
                      let indices = liveMeshFaceIndices(
                        geometry: geometry,
                        faceIndex: faceIndex
                      )
                else {
                    continue
                }

                let vertices = indices.compactMap {
                    liveMeshWorldVertex(
                        geometry: geometry,
                        vertexIndex: Int($0),
                        transform: anchor.transform
                    )
                }
                guard vertices.count == 3 else {
                    continue
                }

                samples.append(
                    Double(
                        (vertices[0].y + vertices[1].y + vertices[2].y)
                        / 3
                    )
                )
            }
        }

        let finite = samples.filter(\.isFinite).sorted()
        guard !finite.isEmpty else {
            return nil
        }
        let middle = finite.count / 2
        if finite.count.isMultiple(of: 2) {
            return (finite[middle - 1] + finite[middle]) / 2
        }
        return finite[middle]
    }

    private func liveMeshFaceIndices(
        geometry: ARMeshGeometry,
        faceIndex: Int
    ) -> [UInt32]? {
        let faces = geometry.faces
        guard faceIndex >= 0,
              faceIndex < faces.count,
              faces.indexCountPerPrimitive == 3,
              faces.bytesPerIndex == 2
                || faces.bytesPerIndex == 4
        else {
            return nil
        }

        var result: [UInt32] = []
        result.reserveCapacity(3)
        for localIndex in 0..<3 {
            let flatIndex = faceIndex * 3 + localIndex
            let pointer = faces.buffer.contents().advanced(
                by: flatIndex * faces.bytesPerIndex
            )
            let bytes = pointer.assumingMemoryBound(to: UInt8.self)
            if faces.bytesPerIndex == 2 {
                result.append(
                    UInt32(bytes[0])
                    | (UInt32(bytes[1]) << 8)
                )
            } else {
                result.append(
                    UInt32(bytes[0])
                    | (UInt32(bytes[1]) << 8)
                    | (UInt32(bytes[2]) << 16)
                    | (UInt32(bytes[3]) << 24)
                )
            }
        }
        return result
    }

    private func liveMeshWorldVertex(
        geometry: ARMeshGeometry,
        vertexIndex: Int,
        transform: simd_float4x4
    ) -> SIMD3<Float>? {
        let source = geometry.vertices
        guard vertexIndex >= 0,
              vertexIndex < source.count
        else {
            return nil
        }

        let pointer = source.buffer.contents().advanced(
            by: source.offset + vertexIndex * source.stride
        )
        let values = pointer.assumingMemoryBound(to: Float.self)
        let local = SIMD4<Float>(
            values[0],
            values[1],
            values[2],
            1
        )
        let world = transform * local
        guard world.x.isFinite,
              world.y.isFinite,
              world.z.isFinite
        else {
            return nil
        }
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private func recordLiveDerivedEdge(
        anchorID: UUID,
        firstIndex: UInt32,
        firstPoint: SIMD3<Float>,
        secondIndex: UInt32,
        secondPoint: SIMD3<Float>,
        evidenceRef: String,
        into edges: inout [
            LiveDerivedMeshEdgeKey:
                LiveDerivedMeshEdgeRecord
        ]
    ) {
        let lowIndex = min(firstIndex, secondIndex)
        let highIndex = max(firstIndex, secondIndex)
        let key = LiveDerivedMeshEdgeKey(
            anchorID: anchorID,
            lowVertexIndex: lowIndex,
            highVertexIndex: highIndex
        )

        if var existing = edges[key] {
            existing.count += 1
            edges[key] = existing
            return
        }

        let firstIsLow = firstIndex == lowIndex
        edges[key] = LiveDerivedMeshEdgeRecord(
            count: 1,
            firstPoint: firstIsLow ? firstPoint : secondPoint,
            secondPoint: firstIsLow ? secondPoint : firstPoint,
            evidenceRef: evidenceRef
        )
    }

    private func reduceLiveDerivedPoints(
        _ points: [DerivedObservationPoint],
        voxelSizeMeters: Double,
        maxPoints: Int
    ) -> [DerivedObservationPoint] {
        var cells: [
            LiveDerivedVoxelKey:
                DerivedObservationPoint
        ] = [:]

        for point in points.sorted(by: {
            if $0.position.x != $1.position.x {
                return $0.position.x < $1.position.x
            }
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }
            if $0.verticalPositionMeters != $1.verticalPositionMeters {
                return ($0.verticalPositionMeters ?? -.infinity)
                    < ($1.verticalPositionMeters ?? -.infinity)
            }
            return $0.evidenceRef < $1.evidenceRef
        }) {
            let key = LiveDerivedVoxelKey(
                x: Int(floor(point.position.x / voxelSizeMeters)),
                z: Int(floor(point.position.y / voxelSizeMeters)),
                y: point.verticalPositionMeters.map {
                    Int(floor($0 / voxelSizeMeters))
                } ?? Int.min
            )
            if cells[key] == nil {
                cells[key] = point
            }
        }

        let reduced = cells.values.sorted {
            if $0.position.x != $1.position.x {
                return $0.position.x < $1.position.x
            }
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }
            if $0.verticalPositionMeters != $1.verticalPositionMeters {
                return ($0.verticalPositionMeters ?? -.infinity)
                    < ($1.verticalPositionMeters ?? -.infinity)
            }
            return $0.evidenceRef < $1.evidenceRef
        }

        guard reduced.count > maxPoints else {
            return reduced
        }

        let stride = Double(reduced.count) / Double(maxPoints)
        return (0..<maxPoints).map {
            reduced[Int(Double($0) * stride)]
        }
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
private struct LiveDerivedMeshEdgeKey: Hashable {
    let anchorID: UUID
    let lowVertexIndex: UInt32
    let highVertexIndex: UInt32
}

private struct LiveDerivedMeshEdgeRecord {
    var count: Int
    let firstPoint: SIMD3<Float>
    let secondPoint: SIMD3<Float>
    let evidenceRef: String
}

private struct LiveDerivedVoxelKey: Hashable {
    let x: Int
    let z: Int
    let y: Int
}

}
#endif
