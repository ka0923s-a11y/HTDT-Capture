import HTDTCaptureCore

/// Observation of the live capture pipeline used to resolve the
/// combined-feature verification fields of `CaptureCapabilityMatrix`.
/// Verification fields follow an explicit lifecycle: `nil` means "not
/// yet established in this session", `false` is an established negative.
public struct CombinedFeatureObservation: Sendable, Equatable {
    /// Whether the RoomPlan capture session is running in this capture
    /// session, or was stopped while preserving the ARSession.
    public enum RoomPlanPhase: String, Sendable, Equatable {
        case notStarted
        case running
        case stoppedPreservingARSession
    }

    public var roomPlanPhase: RoomPlanPhase
    /// Scene reconstruction (mesh) is enabled on the running
    /// AR configuration.
    public var sceneReconstructionActive: Bool
    /// Scene depth frame semantics are enabled on the running
    /// AR configuration and depth data is actually produced.
    public var sceneDepthActive: Bool

    public init(
        roomPlanPhase: RoomPlanPhase,
        sceneReconstructionActive: Bool,
        sceneDepthActive: Bool
    ) {
        self.roomPlanPhase = roomPlanPhase
        self.sceneReconstructionActive = sceneReconstructionActive
        self.sceneDepthActive = sceneDepthActive
    }
}

/// Resolved combined-feature verification fields for
/// `CaptureCapabilityMatrix`.
public struct CombinedFeatureVerification: Sendable, Equatable {
    public let combinedRoomPlanSceneDepthVerified: Bool?
    public let sameSessionDepthAfterRoomPlanStopVerified: Bool?

    public init(
        combinedRoomPlanSceneDepthVerified: Bool?,
        sameSessionDepthAfterRoomPlanStopVerified: Bool?
    ) {
        self.combinedRoomPlanSceneDepthVerified =
            combinedRoomPlanSceneDepthVerified
        self.sameSessionDepthAfterRoomPlanStopVerified =
            sameSessionDepthAfterRoomPlanStopVerified
    }
}

/// Resolved description of the AR configuration actually running on a
/// session. `resolvedCaptureMode` is derived from the configuration
/// itself, so a configuration without scene reconstruction can never
/// claim `.roomPlanMesh` merely because the device supports it.
public struct ActiveARConfigurationResolution: Sendable, Equatable {
    /// Concrete ARKit class name of the running configuration.
    public let configurationTypeName: String
    /// True when the running configuration is an
    /// `ARWorldTrackingConfiguration`.
    public let isWorldTracking: Bool
    /// Scene reconstruction is enabled on the running configuration.
    public let sceneReconstructionEnabled: Bool
    /// The `.sceneDepth` frame semantic is enabled.
    public let sceneDepthEnabled: Bool
    /// The `.smoothedSceneDepth` frame semantic is enabled.
    public let smoothedSceneDepthEnabled: Bool
    /// The capture mode the running configuration honestly satisfies.
    public let resolvedCaptureMode: CaptureMode
    /// Non-nil when a requested mode is not satisfied by the running
    /// configuration; the host must fail closed or explicitly downgrade
    /// rather than persisting the requested mode.
    public let unsatisfiedRequestedMode: CaptureMode?

    public init(
        configurationTypeName: String,
        isWorldTracking: Bool,
        sceneReconstructionEnabled: Bool,
        sceneDepthEnabled: Bool,
        smoothedSceneDepthEnabled: Bool,
        resolvedCaptureMode: CaptureMode,
        unsatisfiedRequestedMode: CaptureMode?
    ) {
        self.configurationTypeName = configurationTypeName
        self.isWorldTracking = isWorldTracking
        self.sceneReconstructionEnabled = sceneReconstructionEnabled
        self.sceneDepthEnabled = sceneDepthEnabled
        self.smoothedSceneDepthEnabled = smoothedSceneDepthEnabled
        self.resolvedCaptureMode = resolvedCaptureMode
        self.unsatisfiedRequestedMode = unsatisfiedRequestedMode
    }
}

public enum PlatformCapabilityProbe {
    /// Map an actually-running AR configuration to the declared capture
    /// mode it satisfies. Resolution is driven by the configuration,
    /// gated by device support: without scene reconstruction the mode is
    /// never `.roomPlanMesh`; without scene depth it is never
    /// `.evidenceDepth`; otherwise the capture runs degraded.
    public static func resolvedCaptureMode(
        sceneReconstructionEnabled: Bool,
        sceneDepthEnabled: Bool,
        capabilities: CaptureCapabilityMatrix
    ) -> CaptureMode {
        if sceneReconstructionEnabled,
           capabilities.roomPlanMeshEligible
        {
            return .roomPlanMesh
        }
        if sceneDepthEnabled,
           capabilities.sceneDepthSupported
        {
            return .evidenceDepth
        }
        return .degradedNoDepth
    }

    /// Derive the combined-feature verification fields from an observed
    /// live configuration. Verification is only claimed from direct
    /// observation of the running pipeline, never inferred from device
    /// support or device-name heuristics.
    public static func combinedFeatureVerification(
        for observation: CombinedFeatureObservation
    ) -> CombinedFeatureVerification {
        let combined: Bool?
        switch observation.roomPlanPhase {
        case .running:
            // Combined RoomPlan + scene depth is verified only while
            // RoomPlan is actually running and both features are active.
            combined = observation.sceneReconstructionActive
                && observation.sceneDepthActive
        case .notStarted, .stoppedPreservingARSession:
            combined = nil
        }

        let sameSession: Bool?
        switch observation.roomPlanPhase {
        case .stoppedPreservingARSession:
            // After RoomPlan stops with the ARSession preserved, depth
            // availability is directly observable.
            sameSession = observation.sceneDepthActive
        case .notStarted, .running:
            sameSession = nil
        }

        return CombinedFeatureVerification(
            combinedRoomPlanSceneDepthVerified: combined,
            sameSessionDepthAfterRoomPlanStopVerified: sameSession
        )
    }

    /// Return `matrix` with verification fields resolved from
    /// `observation`. Fields not yet established keep their prior value
    /// so a later observation can complete the lifecycle.
    public static func applyingCombinedFeatureVerification(
        _ observation: CombinedFeatureObservation,
        to matrix: CaptureCapabilityMatrix
    ) -> CaptureCapabilityMatrix {
        var resolved = matrix
        let verification = combinedFeatureVerification(
            for: observation
        )
        if let combined =
            verification.combinedRoomPlanSceneDepthVerified
        {
            resolved.combinedRoomPlanSceneDepthVerified = combined
        }
        if let sameSession =
            verification.sameSessionDepthAfterRoomPlanStopVerified
        {
            resolved.sameSessionDepthAfterRoomPlanStopVerified =
                sameSession
        }
        return resolved
    }
}

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import RoomPlan

@available(iOS 17.0, *)
extension PlatformCapabilityProbe {
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
            highResolutionFrameSupported:
                ARWorldTrackingConfiguration
                .recommendedVideoFormatForHighResolutionFrameCapturing
                != nil,
            combinedRoomPlanSceneDepthVerified: nil,
            sameSessionDepthAfterRoomPlanStopVerified: nil
        )
    }

    /// Resolve the capture mode honestly satisfied by the configuration
    /// currently running on `session`, against `requestedMode` and
    /// `capabilities`. Returns nil while the session reports no active
    /// configuration yet (e.g. before the first run completes); callers
    /// may retry, matching `waitForActiveConfiguration()` semantics.
    @MainActor
    public static func resolveActiveConfiguration(
        session: ARSession,
        requestedMode: CaptureMode? = nil,
        capabilities: CaptureCapabilityMatrix
    ) -> ActiveARConfigurationResolution? {
        guard let configuration = session.configuration else {
            return nil
        }

        let world =
            configuration as? ARWorldTrackingConfiguration
        let reconstructionEnabled =
            world.map { !$0.sceneReconstruction.isEmpty } ?? false
        let sceneDepthEnabled =
            configuration.frameSemantics.contains(.sceneDepth)
        let smoothedSceneDepthEnabled =
            configuration.frameSemantics
                .contains(.smoothedSceneDepth)

        let resolved = resolvedCaptureMode(
            sceneReconstructionEnabled: reconstructionEnabled,
            sceneDepthEnabled: sceneDepthEnabled,
            capabilities: capabilities
        )

        let unsatisfied: CaptureMode?
        if let requestedMode, requestedMode != resolved {
            unsatisfied = requestedMode
        } else {
            unsatisfied = nil
        }

        return ActiveARConfigurationResolution(
            configurationTypeName:
                String(describing: type(of: configuration)),
            isWorldTracking: world != nil,
            sceneReconstructionEnabled: reconstructionEnabled,
            sceneDepthEnabled: sceneDepthEnabled,
            smoothedSceneDepthEnabled: smoothedSceneDepthEnabled,
            resolvedCaptureMode: resolved,
            unsatisfiedRequestedMode: unsatisfied
        )
    }
}
#else
extension PlatformCapabilityProbe {
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
