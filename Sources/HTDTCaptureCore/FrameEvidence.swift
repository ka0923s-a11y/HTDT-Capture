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
    ) {
        self.kind = kind
        self.depthRelativePath = depthRelativePath
        self.depthByteCount = depthByteCount
        self.depthSHA256 = depthSHA256
        self.confidenceRelativePath = confidenceRelativePath
        self.confidenceByteCount = confidenceByteCount
        self.confidenceSHA256 = confidenceSHA256
    }
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
    ) {
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
}
