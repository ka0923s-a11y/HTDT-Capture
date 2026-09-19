import Foundation

public enum PixelBufferEvidenceError: Error, Sendable, Equatable {
    case invalidImageDimensions
    case noPlanes
    case invalidPlaneDimensions(Int)
    case invalidRowBytes(Int)
    case sourceStrideTooSmall(Int)
    case payloadSizeOverflow
    case payloadSizeMismatch(plane: Int, expected: Int, actual: Int)
}

public struct PackedPixelPlane: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let sourceBytesPerRow: Int
    public let packedBytesPerRow: Int
    public let bytes: Data

    public init(
        width: Int,
        height: Int,
        sourceBytesPerRow: Int,
        packedBytesPerRow: Int,
        bytes: Data
    ) throws {
        guard width > 0, height > 0 else {
            throw PixelBufferEvidenceError.invalidPlaneDimensions(0)
        }
        guard packedBytesPerRow > 0, sourceBytesPerRow > 0 else {
            throw PixelBufferEvidenceError.invalidRowBytes(0)
        }
        guard sourceBytesPerRow >= packedBytesPerRow else {
            throw PixelBufferEvidenceError.sourceStrideTooSmall(0)
        }
        let size = height.multipliedReportingOverflow(by: packedBytesPerRow)
        guard !size.overflow else {
            throw PixelBufferEvidenceError.payloadSizeOverflow
        }
        guard bytes.count == size.partialValue else {
            throw PixelBufferEvidenceError.payloadSizeMismatch(
                plane: 0,
                expected: size.partialValue,
                actual: bytes.count
            )
        }

        self.width = width
        self.height = height
        self.sourceBytesPerRow = sourceBytesPerRow
        self.packedBytesPerRow = packedBytesPerRow
        self.bytes = bytes
    }
}

public struct PackedPixelBuffer: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixelFormatFourCC: UInt32
    public let planes: [PackedPixelPlane]

    public init(
        width: Int,
        height: Int,
        pixelFormatFourCC: UInt32,
        planes: [PackedPixelPlane]
    ) throws {
        guard width > 0, height > 0 else {
            throw PixelBufferEvidenceError.invalidImageDimensions
        }
        guard !planes.isEmpty else {
            throw PixelBufferEvidenceError.noPlanes
        }

        self.width = width
        self.height = height
        self.pixelFormatFourCC = pixelFormatFourCC
        self.planes = planes
    }
}
