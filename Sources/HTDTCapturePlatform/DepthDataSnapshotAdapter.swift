import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(CoreVideo)
import ARKit
import CoreVideo

public enum DepthDataSnapshotAdapterError: Error {
    case lockFailed(CVReturn)
    case unsupportedDepthPixelFormat(OSType)
    case unsupportedConfidencePixelFormat(OSType)
    case unexpectedPlaneCount(Int)
    case unavailableBaseAddress
    case sourceStrideTooSmall
}

public struct DepthArtifactSnapshot: Sendable {
    public let depth: DepthMapPayload
    public let confidence: ConfidenceMapPayload?

    public init(
        depth: DepthMapPayload,
        confidence: ConfidenceMapPayload?
    ) {
        self.depth = depth
        self.confidence = confidence
    }
}

@available(iOS 17.0, *)
public enum DepthDataSnapshotAdapter {
    public static func snapshot(
        _ depthData: ARDepthData
    ) throws -> DepthArtifactSnapshot {
        let depth = try copyDepth(depthData.depthMap)
        let confidence = try depthData.confidenceMap.map(copyConfidence)
        return DepthArtifactSnapshot(
            depth: depth,
            confidence: confidence
        )
    }

    private static func copyDepth(
        _ pixelBuffer: CVPixelBuffer
    ) throws -> DepthMapPayload {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_DepthFloat32 else {
            throw DepthDataSnapshotAdapterError
                .unsupportedDepthPixelFormat(format)
        }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 0 else {
            throw DepthDataSnapshotAdapterError.unexpectedPlaneCount(
                CVPixelBufferGetPlaneCount(pixelBuffer)
            )
        }

        let lockResult = CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        )
        guard lockResult == kCVReturnSuccess else {
            throw DepthDataSnapshotAdapterError.lockFailed(lockResult)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DepthDataSnapshotAdapterError.unavailableBaseAddress
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let activeBytesPerRow = width * MemoryLayout<Float>.stride
        guard sourceBytesPerRow >= activeBytesPerRow else {
            throw DepthDataSnapshotAdapterError.sourceStrideTooSmall
        }

        var values: [Float] = []
        var validity: [UInt8] = []
        values.reserveCapacity(width * height)
        validity.reserveCapacity(width * height)
        var sawInvalid = false

        for row in 0..<height {
            let rowBase = base
                .advanced(by: row * sourceBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                let value = rowBase[column]
                if value.isFinite {
                    values.append(value)
                    validity.append(1)
                } else {
                    values.append(0)
                    validity.append(0)
                    sawInvalid = true
                }
            }
        }

        return try DepthMapPayload(
            width: width,
            height: height,
            valuesMeters: values,
            validityMask: sawInvalid ? validity : nil
        )
    }

    private static func copyConfidence(
        _ pixelBuffer: CVPixelBuffer
    ) throws -> ConfidenceMapPayload {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_OneComponent8 else {
            throw DepthDataSnapshotAdapterError
                .unsupportedConfidencePixelFormat(format)
        }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 0 else {
            throw DepthDataSnapshotAdapterError.unexpectedPlaneCount(
                CVPixelBufferGetPlaneCount(pixelBuffer)
            )
        }

        let lockResult = CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        )
        guard lockResult == kCVReturnSuccess else {
            throw DepthDataSnapshotAdapterError.lockFailed(lockResult)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DepthDataSnapshotAdapterError.unavailableBaseAddress
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard sourceBytesPerRow >= width else {
            throw DepthDataSnapshotAdapterError.sourceStrideTooSmall
        }

        var values: [UInt8] = []
        values.reserveCapacity(width * height)
        for row in 0..<height {
            let rowBase = base
                .advanced(by: row * sourceBytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                values.append(rowBase[column])
            }
        }

        return try ConfidenceMapPayload(
            width: width,
            height: height,
            values: values
        )
    }
}
#endif
