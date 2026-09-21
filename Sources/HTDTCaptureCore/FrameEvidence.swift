import Foundation

public struct EvidenceFrameID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum CameraIntrinsicsError: Error, Sendable, Equatable {
    case invalidElementCount(Int)
    case nonFinite
    case nonPinholeStructure
    case nonPositiveFocalLength
    case invalidPrincipalPoint
}

/// Column-major 3x3 camera intrinsics authority. The capture contract
/// uses the documented AR camera matrix form
/// `| fx  0 cx |`
/// `|  0 fy cy |`
/// `|  0  0  1 |`
/// so the validating initializer rejects arbitrary projective matrices,
/// non-positive focal lengths and implausible principal points.
public struct CameraIntrinsics3x3: Codable, Sendable, Equatable {
    public static let representation = "column_major_3x3_f32"

    /// Absolute tolerance for the structurally fixed elements (the zero
    /// off-diagonal terms and the `1` at row 3, column 3). ARKit emits
    /// exact `0`/`1` values; the tolerance only absorbs Float32 noise.
    public static let structureTolerance: Float = 0.0001

    public let values: [Float]

    public init(values: [Float]) throws {
        guard values.count == 9 else {
            throw CameraIntrinsicsError.invalidElementCount(values.count)
        }
        guard values.allSatisfy(\.isFinite) else {
            throw CameraIntrinsicsError.nonFinite
        }

        // Column-major: elements 1, 2, 3, 5 must be zero and element 8
        // must be one for the AR pinhole form.
        guard abs(values[1]) <= Self.structureTolerance,
              abs(values[2]) <= Self.structureTolerance,
              abs(values[3]) <= Self.structureTolerance,
              abs(values[5]) <= Self.structureTolerance,
              abs(values[8] - 1) <= Self.structureTolerance
        else {
            throw CameraIntrinsicsError.nonPinholeStructure
        }
        guard values[0] > 0, values[4] > 0 else {
            throw CameraIntrinsicsError.nonPositiveFocalLength
        }
        guard values[6] >= 0, values[7] >= 0 else {
            throw CameraIntrinsicsError.invalidPrincipalPoint
        }
        self.values = values
    }

    /// Focal length `fx` in pixels.
    public var fx: Float { values[0] }
    /// Focal length `fy` in pixels.
    public var fy: Float { values[4] }
    /// Principal point x offset in pixels.
    public var cx: Float { values[6] }
    /// Principal point y offset in pixels.
    public var cy: Float { values[7] }

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
        let normalizedDepthPath = SchemaOwnedText.nfc(depthRelativePath)
        guard !normalizedDepthPath.isEmpty else {
            throw DepthEvidenceReferenceError.emptyDepthPath
        }
        guard depthByteCount > 0 else {
            throw DepthEvidenceReferenceError.invalidDepthByteCount
        }

        let normalizedConfidencePath =
            SchemaOwnedText.nfc(confidenceRelativePath)
        let confidenceValues = (
            normalizedConfidencePath,
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
        self.depthRelativePath = normalizedDepthPath
        self.depthByteCount = depthByteCount
        self.depthSHA256 = depthSHA256
        self.confidenceRelativePath = normalizedConfidencePath
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
    case principalPointOutsideImage
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
        // The principal point must lie within the declared image extent
        // (conservative bound; ARKit always reports it inside the frame).
        guard intrinsics.cx <= Float(imageWidth),
              intrinsics.cy <= Float(imageHeight)
        else {
            throw FrameEvidenceDescriptorError.principalPointOutsideImage
        }
        guard pixelByteCount > 0 else {
            throw FrameEvidenceDescriptorError.invalidPixelByteCount
        }
        let normalizedPixelPath = SchemaOwnedText.nfc(pixelRelativePath)
        guard !normalizedPixelPath.isEmpty else {
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
        self.pixelRelativePath = normalizedPixelPath
        self.pixelByteCount = pixelByteCount
        self.pixelSHA256 = pixelSHA256
        self.exifAllowlisted =
            SchemaOwnedText.nfc(exifAllowlisted)
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
