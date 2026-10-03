import HTDTCaptureCore

#if os(iOS) && canImport(ARKit)
import ARKit

public enum ARConfigurationSnapshotError: Error {
    case configurationUnavailable
    case unsupportedConfigurationType(String)
}

public enum ARConfigurationSnapshotAdapter {
    public static func snapshot(
        session: ARSession,
        captureMode: CaptureMode,
        roomPlanOptions: [String: String] = [:]
    ) throws -> CaptureConfigurationProfile {
        guard let configuration = session.configuration else {
            throw ARConfigurationSnapshotError
                .configurationUnavailable
        }
        guard let world =
            configuration as? ARWorldTrackingConfiguration
        else {
            throw ARConfigurationSnapshotError
                .unsupportedConfigurationType(
                    String(describing: type(of: configuration))
                )
        }

        return CaptureConfigurationProfile(
            captureMode: captureMode,
            worldAlignment: worldAlignmentToken(
                configuration.worldAlignment
            ),
            planeDetection: planeDetectionTokens(
                world.planeDetection
            ),
            sceneReconstruction: sceneReconstructionToken(
                world.sceneReconstruction
            ),
            frameSemantics: frameSemanticTokens(
                configuration.frameSemantics
            ),
            videoFormat: VideoFormatDescriptor(
                width: Int(configuration.videoFormat.imageResolution.width),
                height: Int(configuration.videoFormat.imageResolution.height),
                framesPerSecond:
                    configuration.videoFormat.framesPerSecond,
                pixelFormat: nil
            ),
            autofocusEnabled: world.isAutoFocusEnabled,
            roomPlanOptions: roomPlanOptions
        )
    }

    private static func worldAlignmentToken(
        _ value: ARConfiguration.WorldAlignment
    ) -> String {
        switch value {
        case .gravity:
            return "gravity"
        case .gravityAndHeading:
            return "gravity_and_heading"
        case .camera:
            return "camera"
        @unknown default:
            return "unknown_raw_\(value.rawValue)"
        }
    }

    private static func planeDetectionTokens(
        _ value: ARWorldTrackingConfiguration.PlaneDetection
    ) -> [String] {
        var tokens: [String] = []
        var knownRaw: UInt = 0

        if value.contains(.horizontal) {
            tokens.append("horizontal")
            knownRaw |= ARWorldTrackingConfiguration
                .PlaneDetection.horizontal.rawValue
        }
        if value.contains(.vertical) {
            tokens.append("vertical")
            knownRaw |= ARWorldTrackingConfiguration
                .PlaneDetection.vertical.rawValue
        }

        let unknownRaw = value.rawValue & ~knownRaw
        if unknownRaw != 0 {
            tokens.append("unknown_raw_\(unknownRaw)")
        }
        return tokens.sorted()
    }

    private static func sceneReconstructionToken(
        _ value: ARConfiguration.SceneReconstruction
    ) -> String {
        if value == .meshWithClassification {
            return "mesh_with_classification"
        }
        if value == .mesh {
            return "mesh"
        }
        if value.rawValue == 0 {
            return "none"
        }
        return "unknown_raw_\(value.rawValue)"
    }

    private static func frameSemanticTokens(
        _ value: ARConfiguration.FrameSemantics
    ) -> [String] {
        var tokens: [String] = []
        var knownRaw: UInt = 0

        let known: [
            (ARConfiguration.FrameSemantics, String)
        ] = [
            (.sceneDepth, "scene_depth"),
            (.smoothedSceneDepth, "smoothed_scene_depth"),
            (.personSegmentation, "person_segmentation"),
            (
                .personSegmentationWithDepth,
                "person_segmentation_with_depth"
            ),
            (.bodyDetection, "body_detection"),
        ]

        for (option, name) in known where value.contains(option) {
            tokens.append(name)
            knownRaw |= option.rawValue
        }

        let unknownRaw = value.rawValue & ~knownRaw
        if unknownRaw != 0 {
            tokens.append("unknown_raw_\(unknownRaw)")
        }
        return tokens.sorted()
    }
}
#endif
