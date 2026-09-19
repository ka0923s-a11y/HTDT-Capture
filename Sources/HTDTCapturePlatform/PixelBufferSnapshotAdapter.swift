import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(CoreVideo)
import CoreVideo

public enum PixelBufferSnapshotAdapterError: Error {
    case lockFailed(CVReturn)
    case unsupportedPixelFormat(OSType)
    case invalidPlaneCount(Int)
    case unavailableBaseAddress(Int)
    case invalidSourceStride(plane: Int, source: Int, packed: Int)
}

@available(iOS 17.0, *)
public enum PixelBufferSnapshotAdapter {
    public static func snapshot(
        _ pixelBuffer: CVPixelBuffer
    ) throws -> PackedPixelBuffer {
        let lockResult = CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        )
        guard lockResult == kCVReturnSuccess else {
            throw PixelBufferSnapshotAdapterError.lockFailed(lockResult)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
                throw PixelBufferSnapshotAdapterError.invalidPlaneCount(
                    CVPixelBufferGetPlaneCount(pixelBuffer)
                )
            }
            let luma = try copyPlane(
                pixelBuffer,
                plane: 0,
                bytesPerPixel: 1
            )
            let chroma = try copyPlane(
                pixelBuffer,
                plane: 1,
                bytesPerPixel: 2
            )
            return try PackedPixelBuffer(
                width: imageWidth,
                height: imageHeight,
                pixelFormatFourCC: pixelFormat,
                planes: [luma, chroma]
            )

        case kCVPixelFormatType_32BGRA:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) == 0 else {
                throw PixelBufferSnapshotAdapterError.invalidPlaneCount(
                    CVPixelBufferGetPlaneCount(pixelBuffer)
                )
            }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw PixelBufferSnapshotAdapterError.unavailableBaseAddress(0)
            }
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let packedBytesPerRow = imageWidth * 4
            guard sourceBytesPerRow >= packedBytesPerRow else {
                throw PixelBufferSnapshotAdapterError.invalidSourceStride(
                    plane: 0,
                    source: sourceBytesPerRow,
                    packed: packedBytesPerRow
                )
            }
            let bytes = copyRows(
                base: base,
                height: imageHeight,
                sourceBytesPerRow: sourceBytesPerRow,
                packedBytesPerRow: packedBytesPerRow
            )
            let plane = try PackedPixelPlane(
                width: imageWidth,
                height: imageHeight,
                sourceBytesPerRow: sourceBytesPerRow,
                packedBytesPerRow: packedBytesPerRow,
                bytes: bytes
            )
            return try PackedPixelBuffer(
                width: imageWidth,
                height: imageHeight,
                pixelFormatFourCC: pixelFormat,
                planes: [plane]
            )

        default:
            throw PixelBufferSnapshotAdapterError.unsupportedPixelFormat(
                pixelFormat
            )
        }
    }

    private static func copyPlane(
        _ pixelBuffer: CVPixelBuffer,
        plane: Int,
        bytesPerPixel: Int
    ) throws -> PackedPixelPlane {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(
            pixelBuffer,
            plane
        ) else {
            throw PixelBufferSnapshotAdapterError.unavailableBaseAddress(
                plane
            )
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(
            pixelBuffer,
            plane
        )
        let packedBytesPerRow = width * bytesPerPixel
        guard sourceBytesPerRow >= packedBytesPerRow else {
            throw PixelBufferSnapshotAdapterError.invalidSourceStride(
                plane: plane,
                source: sourceBytesPerRow,
                packed: packedBytesPerRow
            )
        }

        return try PackedPixelPlane(
            width: width,
            height: height,
            sourceBytesPerRow: sourceBytesPerRow,
            packedBytesPerRow: packedBytesPerRow,
            bytes: copyRows(
                base: base,
                height: height,
                sourceBytesPerRow: sourceBytesPerRow,
                packedBytesPerRow: packedBytesPerRow
            )
        )
    }

    private static func copyRows(
        base: UnsafeMutableRawPointer,
        height: Int,
        sourceBytesPerRow: Int,
        packedBytesPerRow: Int
    ) -> Data {
        var result = Data()
        result.reserveCapacity(height * packedBytesPerRow)

        for row in 0..<height {
            let rowBase = base.advanced(
                by: row * sourceBytesPerRow
            )
            result.append(
                Data(
                    bytes: rowBase,
                    count: packedBytesPerRow
                )
            )
        }
        return result
    }
}
#endif
