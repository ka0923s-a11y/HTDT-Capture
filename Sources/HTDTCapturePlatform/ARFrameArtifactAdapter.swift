import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit)
import ARKit
import CoreImage
import simd

public enum FrameDepthSelection: Sendable {
    case none
    case discrete
    case smoothed
}

public struct CapturedFrameArtifacts: Sendable {
    public let descriptor: FrameEvidenceDescriptor
    public let pixelPayload: Data
    public let depthPayload: Data?
    public let confidencePayload: Data?
    public let previewPayload: Data?

    public init(
        descriptor: FrameEvidenceDescriptor,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?,
        previewPayload: Data? = nil
    ) {
        self.descriptor = descriptor
        self.pixelPayload = pixelPayload
        self.depthPayload = depthPayload
        self.confidencePayload = confidencePayload
        self.previewPayload = previewPayload
    }
}

/// Retained inputs for deferred frame-evidence materialization.
///
/// Produced by the synchronous SNAPSHOT step on the AR/MainActor
/// boundary: it retains the frame's pixel and depth buffers and copies
/// pose/intrinsics/EXIF metadata only. All expensive work — pixel row
/// copies, canonical binary packing, SHA-256 hashing and HEIC preview
/// generation — happens later in `ARFrameArtifactAdapter.materialize`,
/// which is safe to run off the main actor.
///
/// `capturedImage` and the retained `ARDepthData` keep their
/// CVPixelBuffers alive for the materialization window. The type is
/// `@unchecked Sendable` because those CoreFoundation/ARKit inputs are
/// treated as immutable and are only ever read under read-only locks.
/// Callers must bound the number of outstanding snapshots so retained
/// frame buffers cannot become unbounded queued memory.
public struct CapturedFrameSnapshot: @unchecked Sendable {
    public let frameID: EvidenceFrameID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let sessionTimestampSeconds: Double
    public let worldFromCamera: Matrix4x4F
    public let intrinsics: CameraIntrinsics3x3
    public let exifAllowlisted: [String: String]
    public let capturedImage: CVPixelBuffer
    public let discreteDepthData: ARDepthData?
    public let smoothedDepthData: ARDepthData?
    public let depthSelection: FrameDepthSelection

    public init(
        frameID: EvidenceFrameID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sessionTimestampSeconds: Double,
        worldFromCamera: Matrix4x4F,
        intrinsics: CameraIntrinsics3x3,
        exifAllowlisted: [String: String],
        capturedImage: CVPixelBuffer,
        discreteDepthData: ARDepthData?,
        smoothedDepthData: ARDepthData?,
        depthSelection: FrameDepthSelection
    ) {
        self.frameID = frameID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.worldFromCamera = worldFromCamera
        self.intrinsics = intrinsics
        self.exifAllowlisted = exifAllowlisted
        self.capturedImage = capturedImage
        self.discreteDepthData = discreteDepthData
        self.smoothedDepthData = smoothedDepthData
        self.depthSelection = depthSelection
    }
}

@available(iOS 17.0, *)
public enum ARFrameArtifactAdapter {
    /// Lightweight synchronous SNAPSHOT step, safe on the MainActor/AR
    /// boundary: retains pixel/depth buffers and copies pose metadata
    /// only. No packing, hashing or image encoding is performed here.
    public static func snapshot(
        frame: ARFrame,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameSnapshot {
        try CapturedFrameSnapshot(
            frameID: EvidenceFrameID(),
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            sessionTimestampSeconds: frame.timestamp,
            worldFromCamera: matrix4x4(frame.camera.transform),
            intrinsics: matrix3x3(frame.camera.intrinsics),
            exifAllowlisted: EXIFEvidenceAllowlist.filter(
                frame.exifData
            ),
            capturedImage: frame.capturedImage,
            discreteDepthData: frame.sceneDepth,
            smoothedDepthData: frame.smoothedSceneDepth,
            depthSelection: depthSelection
        )
    }

    /// Asynchronous MATERIALIZE boundary: performs pixel/depth row
    /// copies, canonical binary packing, SHA-256 hashing and HEIC preview
    /// generation off the calling actor. Safe to invoke from a detached
    /// or bounded persistence task. Canonical bytes and hashes are
    /// identical to the synchronous `capture` output for the same source
    /// buffers; preview generation failure remains non-blocking.
    public static func materialize(
        _ snapshot: CapturedFrameSnapshot
    ) async throws -> CapturedFrameArtifacts {
        try materializeArtifacts(snapshot)
    }

    public static func capture(
        frame: ARFrame,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameArtifacts {
        try materializeArtifacts(
            snapshot(
                frame: frame,
                captureSessionID: captureSessionID,
                coordinateSpaceID: coordinateSpaceID,
                depthSelection: depthSelection
            )
        )
    }

    private static func materializeArtifacts(
        _ snapshot: CapturedFrameSnapshot
    ) throws -> CapturedFrameArtifacts {
        let frameID = snapshot.frameID

        let pixelBuffer = try PixelBufferSnapshotAdapter.snapshot(
            snapshot.capturedImage
        )
        let pixelPayload = try PixelBufferBinaryCodec.encode(pixelBuffer)
        let pixelSHA256 = EvidenceIntegrity.sha256(of: pixelPayload)

        let pixelPath = "evidence/frames/\(frameID).pixelbin"

        let depthResult = try materializeDepth(snapshot)

        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: snapshot.captureSessionID,
            coordinateSpaceID: snapshot.coordinateSpaceID,
            sessionTimestampSeconds: snapshot.sessionTimestampSeconds,
            worldFromCamera: snapshot.worldFromCamera,
            intrinsics: snapshot.intrinsics,
            imageWidth: pixelBuffer.width,
            imageHeight: pixelBuffer.height,
            pixelFormatFourCC: pixelBuffer.pixelFormatFourCC,
            pixelRelativePath: pixelPath,
            pixelByteCount: pixelPayload.count,
            pixelSHA256: pixelSHA256,
            exifAllowlisted: snapshot.exifAllowlisted,
            depthStatus: depthResult.status,
            depth: depthResult.reference
        )

        return CapturedFrameArtifacts(
            descriptor: descriptor,
            pixelPayload: pixelPayload,
            depthPayload: depthResult.depthPayload,
            confidencePayload: depthResult.confidencePayload,
            previewPayload: captureHEICPreview(
                snapshot.capturedImage
            )
        )
    }

    private static func captureHEICPreview(
        _ pixelBuffer: CVPixelBuffer
    ) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let colorSpace = CGColorSpace(
            name: CGColorSpace.sRGB
        ) else {
            return nil
        }
        return context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [:]
        )
    }

    private static func materializeDepth(
        _ snapshot: CapturedFrameSnapshot
    ) throws -> (
        status: FrameDepthStatus,
        reference: DepthEvidenceReference?,
        depthPayload: Data?,
        confidencePayload: Data?
    ) {
        let frameID = snapshot.frameID
        let selected: (ARDepthData?, DepthEvidenceKind, FrameDepthStatus)?
        switch snapshot.depthSelection {
        case .none:
            return (.notRequested, nil, nil, nil)
        case .discrete:
            selected = (
                snapshot.discreteDepthData,
                .discreteSceneDepth,
                .capturedDiscrete
            )
        case .smoothed:
            selected = (
                snapshot.smoothedDepthData,
                .smoothedSceneDepth,
                .capturedSmoothed
            )
        }

        guard let selected,
              let depthData = selected.0
        else {
            return (.unavailable, nil, nil, nil)
        }

        let depthSnapshot = try DepthDataSnapshotAdapter.snapshot(
            depthData
        )
        let depthPayload = try DepthBinaryCodec.encode(
            depthSnapshot.depth
        )
        let depthHash = EvidenceIntegrity.sha256(of: depthPayload)
        let depthPath = "evidence/depth/\(frameID).depthbin"

        var confidencePayload: Data?
        var confidencePath: String?
        var confidenceHash: EvidenceSHA256?
        if let confidence = depthSnapshot.confidence {
            let encoded = try ConfidenceBinaryCodec.encode(confidence)
            confidencePayload = encoded
            confidencePath = "evidence/depth/\(frameID).confidencebin"
            confidenceHash = EvidenceIntegrity.sha256(of: encoded)
        }

        let reference = try DepthEvidenceReference(
            kind: selected.1,
            depthRelativePath: depthPath,
            depthByteCount: depthPayload.count,
            depthSHA256: depthHash,
            confidenceRelativePath: confidencePath,
            confidenceByteCount: confidencePayload?.count,
            confidenceSHA256: confidenceHash
        )
        return (
            selected.2,
            reference,
            depthPayload,
            confidencePayload
        )
    }

    private static func matrix4x4(
        _ value: simd_float4x4
    ) throws -> Matrix4x4F {
        try Matrix4x4F(values: [
            value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w,
            value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w,
            value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w,
            value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w,
        ])
    }

    private static func matrix3x3(
        _ value: simd_float3x3
    ) throws -> CameraIntrinsics3x3 {
        try CameraIntrinsics3x3(values: [
            value.columns.0.x, value.columns.0.y, value.columns.0.z,
            value.columns.1.x, value.columns.1.y, value.columns.1.z,
            value.columns.2.x, value.columns.2.y, value.columns.2.z,
        ])
    }
}

@available(iOS 17.0, *)
public enum EXIFEvidenceAllowlist {
    private static let allowedLeafKeys: Set<String> = [
        "ExposureTime",
        "FNumber",
        "ISOSpeedRatings",
        "FocalLength",
        "FocalLenIn35mmFilm",
        "ExposureBiasValue",
        "MeteringMode",
        "WhiteBalance",
    ]

    public static func filter(
        _ raw: [String: Any]
    ) -> [String: String] {
        var result: [String: String] = [:]
        visit(raw, prefix: "", result: &result)
        return result
    }

    private static func visit(
        _ dictionary: [String: Any],
        prefix: String,
        result: inout [String: String]
    ) {
        for key in dictionary.keys.sorted() {
            let value = dictionary[key]!
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"

            if allowedLeafKeys.contains(key),
               let rendered = render(value)
            {
                result[path] = rendered
                continue
            }

            if let nested = value as? [String: Any] {
                visit(nested, prefix: path, result: &result)
            } else if let nested = value as? NSDictionary {
                var converted: [String: Any] = [:]
                for (key, value) in nested {
                    if let key = key as? String {
                        converted[key] = value
                    }
                }
                visit(converted, prefix: path, result: &result)
            }
        }
    }

    private static func render(_ value: Any) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        if let values = value as? [NSNumber] {
            return values.map(\.stringValue).joined(separator: ",")
        }
        return nil
    }
}
#endif
