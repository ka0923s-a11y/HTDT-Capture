import Foundation

public enum DepthBinaryCodecError: Error, Sendable, Equatable {
    case invalidMagic
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case invalidHeaderLength(UInt32)
    case unsupportedComponentType(UInt8)
    case invalidFlags(UInt8)
    case nonZeroReserved
    case countOverflow
    case truncated
    case trailingBytes(Int)
    case invalidPayload
}

public enum DepthBinaryCodec {
    private static let magic = Array("HTDTDPT1".utf8)
    private static let major: UInt16 = 1
    private static let minor: UInt16 = 0
    private static let headerLength: UInt32 = 32
    private static let float32Meters: UInt8 = 1
    private static let flagValidityMask: UInt8 = 1 << 0

    public static func encode(_ payload: DepthMapPayload) throws -> Data {
        guard let width = UInt32(exactly: payload.width),
              let height = UInt32(exactly: payload.height)
        else {
            throw DepthBinaryCodecError.countOverflow
        }

        var flags: UInt8 = 0
        if payload.validityMask != nil {
            flags |= flagValidityMask
        }

        var data = Data()
        data.append(contentsOf: magic)
        appendUInt16(major, to: &data)
        appendUInt16(minor, to: &data)
        appendUInt32(headerLength, to: &data)
        appendUInt32(width, to: &data)
        appendUInt32(height, to: &data)
        data.append(float32Meters)
        data.append(flags)
        appendUInt16(0, to: &data)
        appendUInt32(0, to: &data)

        for value in payload.valuesMeters {
            appendUInt32(value.bitPattern, to: &data)
        }
        if let validityMask = payload.validityMask {
            data.append(contentsOf: validityMask)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> DepthMapPayload {
        var reader = Reader(data: data)
        guard Array(try reader.readBytes(count: magic.count)) == magic else {
            throw DepthBinaryCodecError.invalidMagic
        }
        let readMajor = try reader.readUInt16()
        let readMinor = try reader.readUInt16()
        guard readMajor == major, readMinor == minor else {
            throw DepthBinaryCodecError.unsupportedVersion(
                major: readMajor,
                minor: readMinor
            )
        }
        let readHeaderLength = try reader.readUInt32()
        guard readHeaderLength == headerLength else {
            throw DepthBinaryCodecError.invalidHeaderLength(readHeaderLength)
        }

        let width = Int(try reader.readUInt32())
        let height = Int(try reader.readUInt32())
        let componentType = try reader.readUInt8()
        guard componentType == float32Meters else {
            throw DepthBinaryCodecError.unsupportedComponentType(componentType)
        }
        let flags = try reader.readUInt8()
        guard flags & ~flagValidityMask == 0 else {
            throw DepthBinaryCodecError.invalidFlags(flags)
        }
        let reserved16 = try reader.readUInt16()
        let reserved32 = try reader.readUInt32()
        guard reserved16 == 0, reserved32 == 0 else {
            throw DepthBinaryCodecError.nonZeroReserved
        }

        let count = try checkedMultiply(width, height)
        let depthBytes = try checkedMultiply(count, 4)
        let validityBytes = flags & flagValidityMask != 0 ? count : 0
        let expectedBytes = try checkedAdd(depthBytes, validityBytes)
        guard reader.remaining >= expectedBytes else {
            throw DepthBinaryCodecError.truncated
        }
        guard reader.remaining == expectedBytes else {
            throw DepthBinaryCodecError.trailingBytes(
                reader.remaining - expectedBytes
            )
        }

        var values: [Float] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(Float(bitPattern: try reader.readUInt32()))
        }

        var validityMask: [UInt8]?
        if flags & flagValidityMask != 0 {
            validityMask = Array(try reader.readBytes(count: count))
        }

        do {
            return try DepthMapPayload(
                width: width,
                height: height,
                valuesMeters: values,
                validityMask: validityMask
            )
        } catch {
            throw DepthBinaryCodecError.invalidPayload
        }
    }

    private static func checkedMultiply(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw DepthBinaryCodecError.countOverflow
        }
        return result.partialValue
    }

    private static func checkedAdd(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw DepthBinaryCodecError.countOverflow
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
                throw DepthBinaryCodecError.truncated
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readUInt8() throws -> UInt8 {
            guard remaining >= 1 else {
                throw DepthBinaryCodecError.truncated
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

public enum ConfidenceBinaryCodecError: Error, Sendable, Equatable {
    case invalidMagic
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case invalidHeaderLength(UInt32)
    case unsupportedComponentType(UInt8)
    case nonZeroReserved
    case countOverflow
    case truncated
    case trailingBytes(Int)
    case invalidPayload
}

public enum ConfidenceBinaryCodec {
    private static let magic = Array("HTDTCNF1".utf8)
    private static let major: UInt16 = 1
    private static let minor: UInt16 = 0
    private static let headerLength: UInt32 = 32
    private static let uint8Confidence: UInt8 = 1

    public static func encode(_ payload: ConfidenceMapPayload) throws -> Data {
        guard let width = UInt32(exactly: payload.width),
              let height = UInt32(exactly: payload.height)
        else {
            throw ConfidenceBinaryCodecError.countOverflow
        }

        var data = Data()
        data.append(contentsOf: magic)
        appendUInt16(major, to: &data)
        appendUInt16(minor, to: &data)
        appendUInt32(headerLength, to: &data)
        appendUInt32(width, to: &data)
        appendUInt32(height, to: &data)
        data.append(uint8Confidence)
        data.append(0)
        appendUInt16(0, to: &data)
        appendUInt32(0, to: &data)
        data.append(contentsOf: payload.values)
        return data
    }

    public static func decode(_ data: Data) throws -> ConfidenceMapPayload {
        var reader = Reader(data: data)
        guard Array(try reader.readBytes(count: magic.count)) == magic else {
            throw ConfidenceBinaryCodecError.invalidMagic
        }
        let readMajor = try reader.readUInt16()
        let readMinor = try reader.readUInt16()
        guard readMajor == major, readMinor == minor else {
            throw ConfidenceBinaryCodecError.unsupportedVersion(
                major: readMajor,
                minor: readMinor
            )
        }
        let readHeaderLength = try reader.readUInt32()
        guard readHeaderLength == headerLength else {
            throw ConfidenceBinaryCodecError.invalidHeaderLength(
                readHeaderLength
            )
        }
        let width = Int(try reader.readUInt32())
        let height = Int(try reader.readUInt32())
        let componentType = try reader.readUInt8()
        guard componentType == uint8Confidence else {
            throw ConfidenceBinaryCodecError.unsupportedComponentType(
                componentType
            )
        }
        let reserved8 = try reader.readUInt8()
        let reserved16 = try reader.readUInt16()
        let reserved32 = try reader.readUInt32()
        guard reserved8 == 0, reserved16 == 0, reserved32 == 0 else {
            throw ConfidenceBinaryCodecError.nonZeroReserved
        }

        let count = try checkedMultiply(width, height)
        guard reader.remaining >= count else {
            throw ConfidenceBinaryCodecError.truncated
        }
        guard reader.remaining == count else {
            throw ConfidenceBinaryCodecError.trailingBytes(
                reader.remaining - count
            )
        }

        let values = Array(try reader.readBytes(count: count))
        do {
            return try ConfidenceMapPayload(
                width: width,
                height: height,
                values: values
            )
        } catch {
            throw ConfidenceBinaryCodecError.invalidPayload
        }
    }

    private static func checkedMultiply(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw ConfidenceBinaryCodecError.countOverflow
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
                throw ConfidenceBinaryCodecError.truncated
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readUInt8() throws -> UInt8 {
            guard remaining >= 1 else {
                throw ConfidenceBinaryCodecError.truncated
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
