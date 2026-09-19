import Foundation

public enum PixelBufferBinaryCodecError: Error, Sendable, Equatable {
    case invalidMagic
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case invalidHeaderLength(UInt32)
    case invalidReserved
    case noPlanes
    case countOverflow
    case invalidPlaneLayout(Int)
    case nonContiguousPayload(Int)
    case truncated
    case trailingBytes(Int)
    case invalidPayload
}

public enum PixelBufferBinaryCodec {
    private static let magic = Array("HTDTPXL1".utf8)
    private static let major: UInt16 = 1
    private static let minor: UInt16 = 0
    private static let fixedHeaderLength = 32
    private static let planeDescriptorLength = 24

    public static func encode(_ pixelBuffer: PackedPixelBuffer) throws -> Data {
        guard let width = UInt32(exactly: pixelBuffer.width),
              let height = UInt32(exactly: pixelBuffer.height),
              let planeCount = UInt16(exactly: pixelBuffer.planes.count),
              planeCount > 0
        else {
            throw PixelBufferBinaryCodecError.countOverflow
        }

        let descriptorBytes = try checkedMultiply(
            Int(planeCount),
            planeDescriptorLength
        )
        let headerLengthInt = try checkedAdd(
            fixedHeaderLength,
            descriptorBytes
        )
        guard let headerLength = UInt32(exactly: headerLengthInt) else {
            throw PixelBufferBinaryCodecError.countOverflow
        }

        var payloadOffsets: [UInt32] = []
        var currentOffset = headerLengthInt
        for plane in pixelBuffer.planes {
            guard let offset = UInt32(exactly: currentOffset) else {
                throw PixelBufferBinaryCodecError.countOverflow
            }
            payloadOffsets.append(offset)
            currentOffset = try checkedAdd(currentOffset, plane.bytes.count)
        }

        var data = Data()
        data.append(contentsOf: magic)
        appendUInt16(major, to: &data)
        appendUInt16(minor, to: &data)
        appendUInt32(headerLength, to: &data)
        appendUInt32(width, to: &data)
        appendUInt32(height, to: &data)
        appendUInt32(pixelBuffer.pixelFormatFourCC, to: &data)
        appendUInt16(planeCount, to: &data)
        appendUInt16(0, to: &data)

        for (index, plane) in pixelBuffer.planes.enumerated() {
            guard let planeWidth = UInt32(exactly: plane.width),
                  let planeHeight = UInt32(exactly: plane.height),
                  let sourceBytesPerRow = UInt32(exactly: plane.sourceBytesPerRow),
                  let packedBytesPerRow = UInt32(exactly: plane.packedBytesPerRow),
                  let payloadBytes = UInt32(exactly: plane.bytes.count)
            else {
                throw PixelBufferBinaryCodecError.countOverflow
            }

            appendUInt32(planeWidth, to: &data)
            appendUInt32(planeHeight, to: &data)
            appendUInt32(sourceBytesPerRow, to: &data)
            appendUInt32(packedBytesPerRow, to: &data)
            appendUInt32(payloadOffsets[index], to: &data)
            appendUInt32(payloadBytes, to: &data)
        }

        for plane in pixelBuffer.planes {
            data.append(plane.bytes)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> PackedPixelBuffer {
        var reader = Reader(data: data)
        let magicBytes = try reader.readBytes(count: magic.count)
        guard Array(magicBytes) == magic else {
            throw PixelBufferBinaryCodecError.invalidMagic
        }

        let readMajor = try reader.readUInt16()
        let readMinor = try reader.readUInt16()
        guard readMajor == major, readMinor == minor else {
            throw PixelBufferBinaryCodecError.unsupportedVersion(
                major: readMajor,
                minor: readMinor
            )
        }

        let headerLength = try reader.readUInt32()
        let imageWidth = Int(try reader.readUInt32())
        let imageHeight = Int(try reader.readUInt32())
        let pixelFormat = try reader.readUInt32()
        let planeCount = Int(try reader.readUInt16())
        let reserved = try reader.readUInt16()
        guard reserved == 0 else {
            throw PixelBufferBinaryCodecError.invalidReserved
        }
        guard planeCount > 0 else {
            throw PixelBufferBinaryCodecError.noPlanes
        }

        let expectedHeader = try checkedAdd(
            fixedHeaderLength,
            try checkedMultiply(planeCount, planeDescriptorLength)
        )
        guard headerLength == UInt32(expectedHeader) else {
            throw PixelBufferBinaryCodecError.invalidHeaderLength(headerLength)
        }
        guard data.count >= expectedHeader else {
            throw PixelBufferBinaryCodecError.truncated
        }

        struct Descriptor {
            let width: Int
            let height: Int
            let sourceBytesPerRow: Int
            let packedBytesPerRow: Int
            let payloadOffset: Int
            let payloadBytes: Int
        }

        var descriptors: [Descriptor] = []
        descriptors.reserveCapacity(planeCount)
        var expectedPayloadOffset = expectedHeader

        for index in 0..<planeCount {
            let width = Int(try reader.readUInt32())
            let height = Int(try reader.readUInt32())
            let sourceBytesPerRow = Int(try reader.readUInt32())
            let packedBytesPerRow = Int(try reader.readUInt32())
            let payloadOffset = Int(try reader.readUInt32())
            let payloadBytes = Int(try reader.readUInt32())

            guard width > 0,
                  height > 0,
                  packedBytesPerRow > 0,
                  sourceBytesPerRow >= packedBytesPerRow
            else {
                throw PixelBufferBinaryCodecError.invalidPlaneLayout(index)
            }

            let expectedBytes = try checkedMultiply(height, packedBytesPerRow)
            guard payloadBytes == expectedBytes else {
                throw PixelBufferBinaryCodecError.invalidPlaneLayout(index)
            }
            guard payloadOffset == expectedPayloadOffset else {
                throw PixelBufferBinaryCodecError.nonContiguousPayload(index)
            }
            expectedPayloadOffset = try checkedAdd(
                expectedPayloadOffset,
                payloadBytes
            )

            descriptors.append(
                Descriptor(
                    width: width,
                    height: height,
                    sourceBytesPerRow: sourceBytesPerRow,
                    packedBytesPerRow: packedBytesPerRow,
                    payloadOffset: payloadOffset,
                    payloadBytes: payloadBytes
                )
            )
        }

        guard data.count >= expectedPayloadOffset else {
            throw PixelBufferBinaryCodecError.truncated
        }
        guard data.count == expectedPayloadOffset else {
            throw PixelBufferBinaryCodecError.trailingBytes(
                data.count - expectedPayloadOffset
            )
        }

        var planes: [PackedPixelPlane] = []
        planes.reserveCapacity(planeCount)
        do {
            for descriptor in descriptors {
                let payloadStart = descriptor.payloadOffset
                let payloadEnd =
                    descriptor.payloadOffset + descriptor.payloadBytes
                let bytes = data.subdata(
                    in: payloadStart..<payloadEnd
                )
                planes.append(
                    try PackedPixelPlane(
                        width: descriptor.width,
                        height: descriptor.height,
                        sourceBytesPerRow: descriptor.sourceBytesPerRow,
                        packedBytesPerRow: descriptor.packedBytesPerRow,
                        bytes: bytes
                    )
                )
            }
            return try PackedPixelBuffer(
                width: imageWidth,
                height: imageHeight,
                pixelFormatFourCC: pixelFormat,
                planes: planes
            )
        } catch {
            throw PixelBufferBinaryCodecError.invalidPayload
        }
    }

    private static func checkedMultiply(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw PixelBufferBinaryCodecError.countOverflow
        }
        return result.partialValue
    }

    private static func checkedAdd(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw PixelBufferBinaryCodecError.countOverflow
        }
        return result.partialValue
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private struct Reader {
        let data: Data
        var offset = 0

        var remaining: Int { data.count - offset }

        mutating func readBytes(count: Int) throws -> Data {
            guard count >= 0, remaining >= count else {
                throw PixelBufferBinaryCodecError.truncated
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readUInt8() throws -> UInt8 {
            guard remaining >= 1 else {
                throw PixelBufferBinaryCodecError.truncated
            }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            UInt16(try readUInt8())
                | (UInt16(try readUInt8()) << 8)
        }

        mutating func readUInt32() throws -> UInt32 {
            UInt32(try readUInt8())
                | (UInt32(try readUInt8()) << 8)
                | (UInt32(try readUInt8()) << 16)
                | (UInt32(try readUInt8()) << 24)
        }
    }
}
