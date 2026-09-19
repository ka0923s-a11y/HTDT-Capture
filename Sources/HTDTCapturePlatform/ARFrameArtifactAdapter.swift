import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit)
import ARKit
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

    public init(
        descriptor: FrameEvidenceDescriptor,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?
    ) {
        self.descriptor = descriptor
        self.pixelPayload = pixelPayload
        self.depthPayload = depthPayload
        self.confidencePayload = confidencePayload
    }
}

@available(iOS 17.0, *)
public enum ARFrameArtifactAdapter {
    public static func capture(
        frame: ARFrame,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameArtifacts {
        let frameID = EvidenceFrameID()

        let pixelBuffer = try PixelBufferSnapshotAdapter.snapshot(
            frame.capturedImage
        )
        let pixelPayload = try PixelBufferBinaryCodec.encode(pixelBuffer)
        let pixelSHA256 = EvidenceIntegrity.sha256(of: pixelPayload)

        let pixelPath = "evidence/frames/\(frameID).pixelbin"

        let depthResult = try captureDepth(
            frame: frame,
            frameID: frameID,
            selection: depthSelection
        )

        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            sessionTimestampSeconds: frame.timestamp,
            worldFromCamera: try matrix4x4(frame.camera.transform),
            intrinsics: try matrix3x3(frame.camera.intrinsics),
            imageWidth: pixelBuffer.width,
            imageHeight: pixelBuffer.height,
            pixelFormatFourCC: pixelBuffer.pixelFormatFourCC,
            pixelRelativePath: pixelPath,
            pixelByteCount: pixelPayload.count,
            pixelSHA256: pixelSHA256,
            exifAllowlisted: EXIFEvidenceAllowlist.filter(
                frame.exifData
            ),
            depthStatus: depthResult.status,
            depth: depthResult.reference
        )

        return CapturedFrameArtifacts(
            descriptor: descriptor,
            pixelPayload: pixelPayload,
            depthPayload: depthResult.depthPayload,
            confidencePayload: depthResult.confidencePayload
        )
    }

    private static func captureDepth(
        frame: ARFrame,
        frameID: EvidenceFrameID,
        selection: FrameDepthSelection
    ) throws -> (
        status: FrameDepthStatus,
        reference: DepthEvidenceReference?,
        depthPayload: Data?,
        confidencePayload: Data?
    ) {
        let selected: (ARDepthData?, DepthEvidenceKind, FrameDepthStatus)?
        switch selection {
        case .none:
            return (.notRequested, nil, nil, nil)
        case .discrete:
            selected = (
                frame.sceneDepth,
                .discreteSceneDepth,
                .capturedDiscrete
            )
        case .smoothed:
            selected = (
                frame.smoothedSceneDepth,
                .smoothedSceneDepth,
                .capturedSmoothed
            )
        }

        guard let selected,
              let depthData = selected.0
        else {
            return (.unavailable, nil, nil, nil)
        }

        let snapshot = try DepthDataSnapshotAdapter.snapshot(
            depthData
        )
        let depthPayload = try DepthBinaryCodec.encode(snapshot.depth)
        let depthHash = EvidenceIntegrity.sha256(of: depthPayload)
        let depthPath = "evidence/depth/\(frameID).depthbin"

        var confidencePayload: Data?
        var confidencePath: String?
        var confidenceHash: EvidenceSHA256?
        if let confidence = snapshot.confidence {
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
