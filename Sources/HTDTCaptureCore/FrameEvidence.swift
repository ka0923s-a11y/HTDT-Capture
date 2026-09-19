import Foundation

public struct EvidenceFrameID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum CameraIntrinsicsError: Error, Sendable, Equatable {
    case invalidElementCount(Int)
    case nonFinite
}

public struct CameraIntrinsics3x3: Codable, Sendable, Equatable {
    public static let representation = "column_major_3x3_f32"

    public let values: [Float]

    public init(values: [Float]) throws {
        guard values.count == 9 else {
            throw CameraIntrinsicsError.invalidElementCount(values.count)
        }
        guard values.allSatisfy(\.isFinite) else {
            throw CameraIntrinsicsError.nonFinite
        }
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case representation
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let representation = try container.decode(
            String.self,
            forKey: .representation
        )
        guard representation == Self.representation else {
            throw DecodingError.dataCorruptedError(
                forKey: .representation,
                in: container,
                debugDescription: "Unsupported intrinsics representation"
            )
        }
        try self.init(
            values: container.decode([Float].self, forKey: .values)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Self.representation,
            forKey: .representation
        )
        try container.encode(values, forKey: .values)
    }
}

public enum DepthEvidenceKind: String, Codable, Sendable, Equatable {
    case discreteSceneDepth = "scene_depth"
    case smoothedSceneDepth = "smoothed_scene_depth"
}

public enum FrameDepthStatus: String, Codable, Sendable, Equatable {
    case notRequested = "not_requested"
    case unavailable
    case capturedDiscrete = "captured_scene_depth"
    case capturedSmoothed = "captured_smoothed_scene_depth"
}

public enum DepthEvidenceReferenceError: Error, Sendable, Equatable {
    case emptyDepthPath
    case invalidDepthByteCount
    case incompleteConfidenceReference
    case invalidConfidenceReference
}

public struct DepthEvidenceReference: Codable, Sendable, Equatable {
    public let kind: DepthEvidenceKind
    public let depthRelativePath: String
    public let depthByteCount: Int
    public let depthSHA256: EvidenceSHA256
    public let confidenceRelativePath: String?
    public let confidenceByteCount: Int?
    public let confidenceSHA256: EvidenceSHA256?

    public init(
        kind: DepthEvidenceKind,
        depthRelativePath: String,
        depthByteCount: Int,
        depthSHA256: EvidenceSHA256,
        confidenceRelativePath: String? = nil,
        confidenceByteCount: Int? = nil,
        confidenceSHA256: EvidenceSHA256? = nil
    ) throws {
        guard !depthRelativePath.isEmpty else {
            throw DepthEvidenceReferenceError.emptyDepthPath
        }
        guard depthByteCount > 0 else {
            throw DepthEvidenceReferenceError.invalidDepthByteCount
        }

        let confidenceValues = (
            confidenceRelativePath,
            confidenceByteCount,
            confidenceSHA256
        )
        switch confidenceValues {
        case (nil, nil, nil):
            break
        case let (.some(path), .some(count), .some):
            guard !path.isEmpty, count > 0 else {
                throw DepthEvidenceReferenceError.invalidConfidenceReference
            }
        default:
            throw DepthEvidenceReferenceError.incompleteConfidenceReference
        }

        self.kind = kind
        self.depthRelativePath = depthRelativePath
        self.depthByteCount = depthByteCount
        self.depthSHA256 = depthSHA256
        self.confidenceRelativePath = confidenceRelativePath
        self.confidenceByteCount = confidenceByteCount
        self.confidenceSHA256 = confidenceSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case depthRelativePath = "depth_relative_path"
        case depthByteCount = "depth_byte_count"
        case depthSHA256 = "depth_sha256"
        case confidenceRelativePath = "confidence_relative_path"
        case confidenceByteCount = "confidence_byte_count"
        case confidenceSHA256 = "confidence_sha256"
    }
}

public enum FrameEvidenceDescriptorError: Error, Sendable, Equatable {
    case invalidTimestamp
    case invalidImageDimensions
    case invalidPixelByteCount
    case emptyPixelPath
    case depthStatusMismatch
}

public struct FrameEvidenceDescriptor: Codable, Sendable, Equatable {
    public let frameID: EvidenceFrameID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let sessionTimestampSeconds: Double
    public let worldFromCamera: Matrix4x4F
    public let intrinsics: CameraIntrinsics3x3
    public let imageWidth: Int
    public let imageHeight: Int
    public let pixelFormatFourCC: UInt32
    public let pixelRelativePath: String
    public let pixelByteCount: Int
    public let pixelSHA256: EvidenceSHA256
    public let exifAllowlisted: [String: String]
    public let depthStatus: FrameDepthStatus
    public let depth: DepthEvidenceReference?

    public init(
        frameID: EvidenceFrameID = EvidenceFrameID(),
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sessionTimestampSeconds: Double,
        worldFromCamera: Matrix4x4F,
        intrinsics: CameraIntrinsics3x3,
        imageWidth: Int,
        imageHeight: Int,
        pixelFormatFourCC: UInt32,
        pixelRelativePath: String,
        pixelByteCount: Int,
        pixelSHA256: EvidenceSHA256,
        exifAllowlisted: [String: String] = [:],
        depthStatus: FrameDepthStatus = .notRequested,
        depth: DepthEvidenceReference? = nil
    ) throws {
        guard sessionTimestampSeconds.isFinite,
              sessionTimestampSeconds >= 0
        else {
            throw FrameEvidenceDescriptorError.invalidTimestamp
        }
        guard imageWidth > 0, imageHeight > 0 else {
            throw FrameEvidenceDescriptorError.invalidImageDimensions
        }
        guard pixelByteCount > 0 else {
            throw FrameEvidenceDescriptorError.invalidPixelByteCount
        }
        guard !pixelRelativePath.isEmpty else {
            throw FrameEvidenceDescriptorError.emptyPixelPath
        }

        let depthMatchesStatus: Bool
        switch (depthStatus, depth?.kind) {
        case (.notRequested, nil), (.unavailable, nil):
            depthMatchesStatus = true
        case (.capturedDiscrete, .discreteSceneDepth):
            depthMatchesStatus = true
        case (.capturedSmoothed, .smoothedSceneDepth):
            depthMatchesStatus = true
        default:
            depthMatchesStatus = false
        }
        guard depthMatchesStatus else {
            throw FrameEvidenceDescriptorError.depthStatusMismatch
        }

        self.frameID = frameID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.worldFromCamera = worldFromCamera
        self.intrinsics = intrinsics
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pixelFormatFourCC = pixelFormatFourCC
        self.pixelRelativePath = pixelRelativePath
        self.pixelByteCount = pixelByteCount
        self.pixelSHA256 = pixelSHA256
        self.exifAllowlisted = exifAllowlisted
        self.depthStatus = depthStatus
        self.depth = depth
    }

    private enum CodingKeys: String, CodingKey {
        case frameID = "frame_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case sessionTimestampSeconds = "session_timestamp_s"
        case worldFromCamera = "T_world_from_camera"
        case intrinsics
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case pixelFormatFourCC = "pixel_format_fourcc"
        case pixelRelativePath = "pixel_relative_path"
        case pixelByteCount = "pixel_byte_count"
        case pixelSHA256 = "pixel_sha256"
        case exifAllowlisted = "exif_allowlisted"
        case depthStatus = "depth_status"
        case depth
    }
}
