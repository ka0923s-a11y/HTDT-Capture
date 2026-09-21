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
    case confidenceDimensionsMismatch
    case invalidDepthDimensions(width: Int, height: Int)
    case invalidConfidenceDimensions(width: Int, height: Int)
    case unsupportedConfidenceValue(index: Int, value: UInt8)
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
        if let confidence,
           (confidence.width != depth.width || confidence.height != depth.height)
        {
            throw DepthDataSnapshotAdapterError.confidenceDimensionsMismatch
        }
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
        // Malformed dimensions must fail before any allocation or
        // evidence construction; the count multiplication below would
        // otherwise overflow/trap on hostile inputs.
        guard width > 0,
              height > 0,
              !width.multipliedReportingOverflow(by: height).overflow
        else {
            throw DepthDataSnapshotAdapterError.invalidDepthDimensions(
                width: width,
                height: height
            )
        }
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
                // v1 canonical semantics: `valuesMeters` is the estimated
                // positive distance from the device to the environment.
                // Finite-but-non-positive and non-finite samples are not
                // valid scene-depth observations; they are normalized to
                // zero and marked invalid in the validity mask, which is
                // emitted whenever at least one invalid sample exists.
                if value.isFinite, value > 0 {
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
        guard width > 0,
              height > 0,
              !width.multipliedReportingOverflow(by: height).overflow
        else {
            throw DepthDataSnapshotAdapterError
                .invalidConfidenceDimensions(
                    width: width,
                    height: height
                )
        }
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
                let raw = rowBase[column]
                // Each confidence byte must carry a supported
                // ARConfidenceLevel raw value. The policy is fail-closed:
                // bytes outside the current ARKit domain (including any
                // future SDK values) reject the map rather than silently
                // qualifying as canonical confidence.
                guard ARConfidenceLevel(rawValue: Int(raw)) != nil
                else {
                    throw DepthDataSnapshotAdapterError
                        .unsupportedConfidenceValue(
                            index: row * width + column,
                            value: raw
                        )
                }
                values.append(raw)
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
