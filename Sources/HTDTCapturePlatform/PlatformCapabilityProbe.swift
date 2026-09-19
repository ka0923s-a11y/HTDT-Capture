import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import RoomPlan

@available(iOS 17.0, *)
public enum PlatformCapabilityProbe {
    @MainActor
    public static func current() -> CaptureCapabilityMatrix {
        CaptureCapabilityMatrix(
            roomPlanSupported: RoomCaptureSession.isSupported,
            worldTrackingSupported: ARWorldTrackingConfiguration.isSupported,
            sceneReconstructionSupported:
                ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
                || ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            sceneDepthSupported:
                ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            smoothedSceneDepthSupported:
                ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth),
            highResolutionFrameSupported: false,
            combinedRoomPlanSceneDepthVerified: nil,
            sameSessionDepthAfterRoomPlanStopVerified: nil
        )
    }
}
#else
public enum PlatformCapabilityProbe {
    public static func current() -> CaptureCapabilityMatrix {
        CaptureCapabilityMatrix(
            roomPlanSupported: false,
            worldTrackingSupported: false,
            sceneReconstructionSupported: false,
            sceneDepthSupported: false,
            smoothedSceneDepthSupported: false,
            highResolutionFrameSupported: false,
            combinedRoomPlanSceneDepthVerified: nil,
            sameSessionDepthAfterRoomPlanStopVerified: nil
        )
    }
}
#endif
