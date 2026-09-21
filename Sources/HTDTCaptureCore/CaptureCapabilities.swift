import Foundation

/// Resolved capture mode (#248). Production startup intentionally
/// requires `roomPlanMesh` (Option B): a scan only begins on a device
/// whose configuration can run RoomPlan with scene reconstruction.
/// `evidenceDepth`/`degradedNoDepth` are *runtime resolution* outcomes
/// persisted from the active configuration — e.g. mesh reconstruction
/// missing on the running configuration after a mesh-eligible start —
/// and the bounded quality fallback, never modes the operator can
/// select at scan start.
public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case roomPlanMesh = "roomplan_mesh"
    case evidenceDepth = "evidence_depth"
    case degradedNoDepth = "degraded_no_depth"
}

public struct CaptureCapabilityMatrix: Codable, Sendable, Equatable {
    public var roomPlanSupported: Bool
    public var worldTrackingSupported: Bool
    public var sceneReconstructionSupported: Bool
    public var sceneDepthSupported: Bool
    public var smoothedSceneDepthSupported: Bool
    public var highResolutionFrameSupported: Bool
    public var combinedRoomPlanSceneDepthVerified: Bool?
    public var sameSessionDepthAfterRoomPlanStopVerified: Bool?

    public init(
        roomPlanSupported: Bool,
        worldTrackingSupported: Bool,
        sceneReconstructionSupported: Bool,
        sceneDepthSupported: Bool,
        smoothedSceneDepthSupported: Bool = false,
        highResolutionFrameSupported: Bool = false,
        combinedRoomPlanSceneDepthVerified: Bool? = nil,
        sameSessionDepthAfterRoomPlanStopVerified: Bool? = nil
    ) {
        self.roomPlanSupported = roomPlanSupported
        self.worldTrackingSupported = worldTrackingSupported
        self.sceneReconstructionSupported = sceneReconstructionSupported
        self.sceneDepthSupported = sceneDepthSupported
        self.smoothedSceneDepthSupported = smoothedSceneDepthSupported
        self.highResolutionFrameSupported = highResolutionFrameSupported
        self.combinedRoomPlanSceneDepthVerified = combinedRoomPlanSceneDepthVerified
        self.sameSessionDepthAfterRoomPlanStopVerified = sameSessionDepthAfterRoomPlanStopVerified
    }

    public var roomPlanMeshEligible: Bool {
        roomPlanSupported && worldTrackingSupported && sceneReconstructionSupported
    }

    public var requiresCombinedFeatureProbe: Bool {
        roomPlanMeshEligible
            && sceneDepthSupported
            && combinedRoomPlanSceneDepthVerified == nil
    }

    /// Modes a scan may start in (#248, Option B). Production capture
    /// requires RoomPlan + scene reconstruction, so the only startup
    /// mode is `roomPlanMesh`.
    public var startupModes: [CaptureMode] {
        roomPlanMeshEligible ? [.roomPlanMesh] : []
    }

    /// Modes the running configuration may resolve to during or after
    /// a mesh-eligible start. Degraded entries describe observed
    /// runtime fallbacks for evidence/quality semantics, not operator
    /// startup choices.
    public var allowedModes: [CaptureMode] {
        guard roomPlanMeshEligible else { return [] }
        var modes: [CaptureMode] = [.roomPlanMesh, .degradedNoDepth]
        if sceneDepthSupported {
            modes.append(.evidenceDepth)
        }
        return modes
    }
}

public struct VideoFormatDescriptor: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int
    public var pixelFormat: String?

    public init(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        pixelFormat: String? = nil
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.pixelFormat = pixelFormat
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case framesPerSecond = "frames_per_second"
        case pixelFormat = "pixel_format"
    }
}

public struct CaptureConfigurationProfile: Codable, Sendable, Equatable {
    public var captureMode: CaptureMode
    public var worldAlignment: String
    public var planeDetection: [String]
    public var sceneReconstruction: String
    public var frameSemantics: [String]
    public var videoFormat: VideoFormatDescriptor?
    public var autofocusEnabled: Bool?
    public var roomPlanOptions: [String: String]

    public init(
        captureMode: CaptureMode,
        worldAlignment: String,
        planeDetection: [String] = [],
        sceneReconstruction: String,
        frameSemantics: [String] = [],
        videoFormat: VideoFormatDescriptor? = nil,
        autofocusEnabled: Bool? = nil,
        roomPlanOptions: [String: String] = [:]
    ) {
        self.captureMode = captureMode
        self.worldAlignment = worldAlignment
        self.planeDetection = planeDetection
        self.sceneReconstruction = sceneReconstruction
        self.frameSemantics = frameSemantics
        self.videoFormat = videoFormat
        self.autofocusEnabled = autofocusEnabled
        self.roomPlanOptions = roomPlanOptions
    }
}
