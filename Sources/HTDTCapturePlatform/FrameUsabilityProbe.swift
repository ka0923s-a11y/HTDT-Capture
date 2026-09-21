import Foundation
import HTDTCaptureCore

#if canImport(CoreVideo)
import CoreVideo

/// Cheap bounded image-usability probe for evidence frames (#274).
///
/// Samples the luma content on a fixed coarse grid — never the full
/// frame — to produce `FrameUsabilityMetrics` (mean luminance, clipped
/// and dark pixel fractions, mean gradient energy). It answers "is
/// this frame visibly usable evidence", not "is this a good image".
/// Compiled for every platform that has CoreVideo so the statistics
/// are unit-testable off-device; ARKit frames are only produced on
/// iOS.
public enum FrameUsabilityProbe {
    /// Sampling grid bounds: fixed and small so probing stays O(1)
    /// regardless of sensor resolution.
    public static let gridColumns = 24
    public static let gridRows = 16
    /// Luma bounds in the normalized 0...1 space the evaluator uses.
    static let clipBound = 248.0 / 255.0
    static let darkBound = 16.0 / 255.0

    /// Measure luma statistics for `pixelBuffer`. Returns nil when the
    /// buffer is empty, an unsupported format, or cannot be locked —
    /// callers must treat nil as "usability unknown", never as a pass.
    public static func metrics(
        from pixelBuffer: CVPixelBuffer
    ) -> FrameUsabilityMetrics? {
        guard CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        ) == kCVReturnSuccess else {
            return nil
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width >= gridColumns, height >= gridRows else {
            return nil
        }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let planeIndex = 0
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1 else {
                return nil
            }
        case kCVPixelFormatType_32BGRA:
            break
        default:
            return nil
        }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(
            pixelBuffer,
            planeIndex
        ) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(
            pixelBuffer,
            planeIndex
        )
        let planeHeight = CVPixelBufferGetHeightOfPlane(
            pixelBuffer,
            planeIndex
        )
        let planeWidth = CVPixelBufferGetWidthOfPlane(
            pixelBuffer,
            planeIndex
        )
        guard bytesPerRow > 0, planeWidth > 0, planeHeight > 0 else {
            return nil
        }

        let cols = min(gridColumns, planeWidth)
        let rows = min(gridRows, planeHeight)
        let stepX = max(1, planeWidth / cols)
        let stepY = max(1, planeHeight / rows)
        let isBGRA =
            format == kCVPixelFormatType_32BGRA

        var grid = [Double](
            repeating: 0,
            count: rows * cols
        )
        var sum = 0.0
        var clipped = 0
        var dark = 0

        base.withMemoryRebound(
            to: UInt8.self,
            capacity: bytesPerRow * planeHeight
        ) { bytes in
            for row in 0..<rows {
                let y = min(planeHeight - 1, row * stepY)
                for col in 0..<cols {
                    let x = min(planeWidth - 1, col * stepX)
                    let value: Double
                    if isBGRA {
                        let offset = y * bytesPerRow + x * 4
                        let b = Double(bytes[offset])
                        let g = Double(bytes[offset + 1])
                        let r = Double(bytes[offset + 2])
                        value = (0.114 * b + 0.587 * g + 0.299 * r)
                            / 255.0
                    } else {
                        value =
                            Double(bytes[y * bytesPerRow + x]) / 255.0
                    }
                    grid[row * cols + col] = value
                    sum += value
                    if value >= clipBound {
                        clipped += 1
                    }
                    if value <= darkBound {
                        dark += 1
                    }
                }
            }
        }

        let count = Double(rows * cols)
        var gradientSum = 0.0
        var gradientCount = 0
        for row in 0..<rows {
            for col in 0..<(cols - 1) {
                gradientSum += abs(
                    grid[row * cols + col + 1]
                        - grid[row * cols + col]
                )
                gradientCount += 1
            }
        }
        for row in 0..<(rows - 1) {
            for col in 0..<cols {
                gradientSum += abs(
                    grid[(row + 1) * cols + col]
                        - grid[row * cols + col]
                )
                gradientCount += 1
            }
        }

        return FrameUsabilityMetrics(
            meanLuminance: sum / count,
            clippedFraction: Double(clipped) / count,
            darkFraction: Double(dark) / count,
            gradientEnergy:
                gradientCount > 0
                ? gradientSum / Double(gradientCount)
                : 0
        )
    }
}
#endif
