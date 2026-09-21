import Foundation

public struct CaptureConfigurationDocument: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.configuration"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureMode: CaptureMode
    public let worldAlignment: String
    public let planeDetection: [String]
    public let sceneReconstruction: String
    public let frameSemantics: [String]
    public let videoFormat: VideoFormatDescriptor?
    public let autofocusEnabled: Bool?
    public let roomPlanOptions: [String: String]

    public init(profile: CaptureConfigurationProfile) {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.captureMode = profile.captureMode
        self.worldAlignment =
            SchemaOwnedText.nfc(profile.worldAlignment)
        self.planeDetection =
            SchemaOwnedText.nfc(profile.planeDetection).sorted()
        self.sceneReconstruction =
            SchemaOwnedText.nfc(profile.sceneReconstruction)
        self.frameSemantics =
            SchemaOwnedText.nfc(profile.frameSemantics).sorted()
        self.videoFormat = profile.videoFormat
        self.autofocusEnabled = profile.autofocusEnabled
        self.roomPlanOptions =
            SchemaOwnedText.nfc(profile.roomPlanOptions)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureMode = "capture_mode"
        case worldAlignment = "world_alignment"
        case planeDetection = "plane_detection"
        case sceneReconstruction = "scene_reconstruction"
        case frameSemantics = "frame_semantics"
        case videoFormat = "video_format"
        case autofocusEnabled = "autofocus_enabled"
        case roomPlanOptions = "roomplan"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription:
                    "Unsupported capture configuration schema"
            )
        }
        // Route through the profile initializer so canonical ordering
        // and normalization match the producer path exactly.
        let profile = CaptureConfigurationProfile(
            captureMode: try container.decode(
                CaptureMode.self,
                forKey: .captureMode
            ),
            worldAlignment: try container.decode(
                String.self,
                forKey: .worldAlignment
            ),
            planeDetection: try container.decode(
                [String].self,
                forKey: .planeDetection
            ),
            sceneReconstruction: try container.decode(
                String.self,
                forKey: .sceneReconstruction
            ),
            frameSemantics: try container.decode(
                [String].self,
                forKey: .frameSemantics
            ),
            videoFormat: try container.decodeIfPresent(
                VideoFormatDescriptor.self,
                forKey: .videoFormat
            ),
            autofocusEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .autofocusEnabled
            ),
            roomPlanOptions: try container.decode(
                [String: String].self,
                forKey: .roomPlanOptions
            )
        )
        self.init(profile: profile)
    }
}

public struct CaptureCapabilitiesDocument: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.capabilities"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let roomPlanSupported: Bool
    public let worldTrackingSupported: Bool
    public let sceneReconstructionSupported: Bool
    public let sceneDepthSupported: Bool
    public let smoothedSceneDepthSupported: Bool
    public let highResolutionFrameSupported: Bool
    public let combinedModeProbe: CombinedModeProbe?

    public struct CombinedModeProbe: Codable, Sendable, Equatable {
        public let roomPlanMeshOK: Bool?
        public let roomPlanSceneDepthOK: Bool?
        public let sameSessionDepthAfterRoomPlanStopOK: Bool?

        private enum CodingKeys: String, CodingKey {
            case roomPlanMeshOK = "roomplan_mesh_ok"
            case roomPlanSceneDepthOK = "roomplan_scene_depth_ok"
            case sameSessionDepthAfterRoomPlanStopOK =
                "same_session_depth_after_roomplan_stop_ok"
        }
    }

    public init(matrix: CaptureCapabilityMatrix) {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.roomPlanSupported = matrix.roomPlanSupported
        self.worldTrackingSupported = matrix.worldTrackingSupported
        self.sceneReconstructionSupported =
            matrix.sceneReconstructionSupported
        self.sceneDepthSupported = matrix.sceneDepthSupported
        self.smoothedSceneDepthSupported =
            matrix.smoothedSceneDepthSupported
        self.highResolutionFrameSupported =
            matrix.highResolutionFrameSupported

        if matrix.combinedRoomPlanSceneDepthVerified != nil
            || matrix.sameSessionDepthAfterRoomPlanStopVerified != nil
        {
            self.combinedModeProbe = CombinedModeProbe(
                roomPlanMeshOK: matrix.roomPlanMeshEligible,
                roomPlanSceneDepthOK:
                    matrix.combinedRoomPlanSceneDepthVerified,
                sameSessionDepthAfterRoomPlanStopOK:
                    matrix.sameSessionDepthAfterRoomPlanStopVerified
            )
        } else {
            self.combinedModeProbe = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case roomPlanSupported = "roomplan_supported"
        case worldTrackingSupported = "world_tracking_supported"
        case sceneReconstructionSupported =
            "scene_reconstruction_supported"
        case sceneDepthSupported = "scene_depth_supported"
        case smoothedSceneDepthSupported =
            "smoothed_scene_depth_supported"
        case highResolutionFrameSupported =
            "high_resolution_frame_supported"
        case combinedModeProbe = "combined_mode_probe"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription:
                    "Unsupported capture capabilities schema"
            )
        }
        let probe = try container.decodeIfPresent(
            CombinedModeProbe.self,
            forKey: .combinedModeProbe
        )
        // Rebuild through the matrix initializer so the derived probe
        // shape is reconstructed exactly as the producer computes it.
        let matrix = CaptureCapabilityMatrix(
            roomPlanSupported: try container.decode(
                Bool.self,
                forKey: .roomPlanSupported
            ),
            worldTrackingSupported: try container.decode(
                Bool.self,
                forKey: .worldTrackingSupported
            ),
            sceneReconstructionSupported: try container.decode(
                Bool.self,
                forKey: .sceneReconstructionSupported
            ),
            sceneDepthSupported: try container.decode(
                Bool.self,
                forKey: .sceneDepthSupported
            ),
            smoothedSceneDepthSupported: try container.decode(
                Bool.self,
                forKey: .smoothedSceneDepthSupported
            ),
            highResolutionFrameSupported: try container.decode(
                Bool.self,
                forKey: .highResolutionFrameSupported
            ),
            combinedRoomPlanSceneDepthVerified:
                probe?.roomPlanSceneDepthOK,
            sameSessionDepthAfterRoomPlanStopVerified:
                probe?.sameSessionDepthAfterRoomPlanStopOK
        )
        // `roomPlanMeshOK` is derived from the support flags; reject a
        // document whose probe contradicts them.
        if let meshOK = probe?.roomPlanMeshOK,
           meshOK != matrix.roomPlanMeshEligible
        {
            throw DecodingError.dataCorruptedError(
                forKey: .combinedModeProbe,
                in: container,
                debugDescription:
                    "Combined-mode probe contradicts capability flags"
            )
        }
        self.init(matrix: matrix)
    }
}

public struct CaptureSessionDocument: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.session"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let captureMode: CaptureMode
    public let startedAtUTC: String
    public let configurationRef: String
    public let timingRef: String

    public init(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        captureMode: CaptureMode,
        startedAtUTC: String,
        configurationRef: String,
        timingRef: String
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(startedAtUTC) else {
            throw CaptureSessionMetadataError.invalidUTCTimestamp
        }
        let normalizedConfigurationRef =
            SchemaOwnedText.nfc(configurationRef)
        let normalizedTimingRef = SchemaOwnedText.nfc(timingRef)
        guard !normalizedConfigurationRef.isEmpty,
              !normalizedTimingRef.isEmpty
        else {
            throw CaptureSessionMetadataError.emptySessionReference
        }

        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.captureMode = captureMode
        self.startedAtUTC = startedAtUTC
        self.configurationRef = normalizedConfigurationRef
        self.timingRef = normalizedTimingRef
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case captureMode = "capture_mode"
        case startedAtUTC = "started_at"
        case configurationRef = "configuration_ref"
        case timingRef = "timing_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported capture session schema"
            )
        }
        try self.init(
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            captureMode: container.decode(
                CaptureMode.self,
                forKey: .captureMode
            ),
            startedAtUTC: container.decode(
                String.self,
                forKey: .startedAtUTC
            ),
            configurationRef: container.decode(
                String.self,
                forKey: .configurationRef
            ),
            timingRef: container.decode(
                String.self,
                forKey: .timingRef
            )
        )
    }
}

public struct CaptureSessionFoundationPackage: Sendable, Equatable {
    public static let sessionPath = "session/capture-session.json"
    public static let capabilitiesPath = "session/capabilities.json"
    public static let configurationPath =
        "session/capture-configuration.json"
    public static let devicePath = "session/device.json"

    public let session: CaptureSessionDocument
    public let capabilities: CaptureCapabilitiesDocument
    public let configuration: CaptureConfigurationDocument
    public let device: CaptureDeviceDocument
    public let sessionData: Data
    public let capabilitiesData: Data
    public let configurationData: Data
    public let deviceData: Data

    public var payloadDeclarations: [BundlePayloadDeclaration] {
        [
            BundlePayloadDeclaration(
                path: Self.capabilitiesPath,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            BundlePayloadDeclaration(
                path: Self.configurationPath,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            BundlePayloadDeclaration(
                path: Self.devicePath,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical
            ),
            BundlePayloadDeclaration(
                path: Self.sessionPath,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical,
                sourceRefs: [
                    "path:\(Self.capabilitiesPath)",
                    "path:\(Self.configurationPath)",
                    "path:\(Self.devicePath)",
                    "path:\(CaptureTimingPackage.path)",
                ]
            ),
        ].sorted {
            BundleLogicalPath.utf8Less($0.path, $1.path)
        }
    }

    public func persist(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        try await writer.writeBatchIfIdentical([
            try CaptureFileWriteRequest(
                data: capabilitiesData,
                path: CaptureStorePath(Self.capabilitiesPath)
            ),
            try CaptureFileWriteRequest(
                data: configurationData,
                path: CaptureStorePath(Self.configurationPath)
            ),
            try CaptureFileWriteRequest(
                data: deviceData,
                path: CaptureStorePath(Self.devicePath)
            ),
            try CaptureFileWriteRequest(
                data: sessionData,
                path: CaptureStorePath(Self.sessionPath)
            ),
        ])
    }
}

public enum CaptureSessionFoundationPackageBuilder {
    public static func build(
        context: CaptureSessionContext,
        capabilities: CaptureCapabilityMatrix,
        configurationProfile: CaptureConfigurationProfile,
        startedAtUTC: String,
        device: CaptureDeviceDocument
    ) throws -> CaptureSessionFoundationPackage {
        let configuration = CaptureConfigurationDocument(
            profile: configurationProfile
        )
        let capabilitiesDocument = CaptureCapabilitiesDocument(
            matrix: capabilities
        )
        let session = try CaptureSessionDocument(
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            captureMode: configurationProfile.captureMode,
            startedAtUTC: startedAtUTC,
            configurationRef:
                CaptureSessionFoundationPackage.configurationPath,
            timingRef: CaptureTimingPackage.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let sessionData = try encoder.encode(session)
        let capabilitiesData = try encoder.encode(
            capabilitiesDocument
        )
        let configurationData = try encoder.encode(configuration)
        let deviceData = try encoder.encode(device)

        guard
            try JSONDecoder().decode(
                CaptureSessionDocument.self,
                from: sessionData
            ) == session,
            try JSONDecoder().decode(
                CaptureCapabilitiesDocument.self,
                from: capabilitiesData
            ) == capabilitiesDocument,
            try JSONDecoder().decode(
                CaptureConfigurationDocument.self,
                from: configurationData
            ) == configuration,
            try JSONDecoder().decode(
                CaptureDeviceDocument.self,
                from: deviceData
            ) == device
        else {
            throw CocoaError(.coderInvalidValue)
        }

        return CaptureSessionFoundationPackage(
            session: session,
            capabilities: capabilitiesDocument,
            configuration: configuration,
            device: device,
            sessionData: sessionData,
            capabilitiesData: capabilitiesData,
            configurationData: configurationData,
            deviceData: deviceData
        )
    }
}
