import Foundation

public enum MeshBinaryCodecError: Error, Sendable, Equatable {
    case invalidMagic
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case invalidHeaderLength(UInt32)
    case unsupportedIndexWidth(UInt8)
    case invalidFlags(UInt8)
    case truncated
    case trailingBytes(Int)
    case invalidGeometry
    case countOverflow
}

public enum MeshBinaryCodec {
    private static let magic = Array("HTDTMSH1".utf8)
    private static let major: UInt16 = 1
    private static let minor: UInt16 = 0
    private static let headerLength: UInt32 = 32
    private static let flagNormals: UInt8 = 1 << 0
    private static let flagClassifications: UInt8 = 1 << 1

    public static func encode(_ geometry: MeshGeometryPayload) throws -> Data {
        guard let vertexCount = UInt32(exactly: geometry.vertices.count),
              let faceCount = UInt32(exactly: geometry.faceCount)
        else {
            throw MeshBinaryCodecError.countOverflow
        }

        var flags: UInt8 = 0
        if geometry.normals != nil {
            flags |= flagNormals
        }
        if geometry.faceClassifications != nil {
            flags |= flagClassifications
        }

        var data = Data()
        data.append(contentsOf: magic)
        appendUInt16(major, to: &data)
        appendUInt16(minor, to: &data)
        appendUInt32(headerLength, to: &data)
        appendUInt32(vertexCount, to: &data)
        appendUInt32(faceCount, to: &data)
        data.append(4)
        data.append(flags)
        appendUInt16(0, to: &data)
        appendUInt32(0, to: &data)

        for vertex in geometry.vertices {
            appendFloat(vertex.x, to: &data)
            appendFloat(vertex.y, to: &data)
            appendFloat(vertex.z, to: &data)
        }

        if let normals = geometry.normals {
            for normal in normals {
                appendFloat(normal.x, to: &data)
                appendFloat(normal.y, to: &data)
                appendFloat(normal.z, to: &data)
            }
        }

        for index in geometry.triangleIndices {
            appendUInt32(index, to: &data)
        }

        if let classifications = geometry.faceClassifications {
            data.append(contentsOf: classifications)
        }

        return data
    }

    public static func decode(_ data: Data) throws -> MeshGeometryPayload {
        var reader = Reader(data: data)

        let magicBytes = try reader.readBytes(count: magic.count)
        guard Array(magicBytes) == magic else {
            throw MeshBinaryCodecError.invalidMagic
        }

        let readMajor = try reader.readUInt16()
        let readMinor = try reader.readUInt16()
        guard readMajor == major, readMinor == minor else {
            throw MeshBinaryCodecError.unsupportedVersion(
                major: readMajor,
                minor: readMinor
            )
        }

        let readHeaderLength = try reader.readUInt32()
        guard readHeaderLength == headerLength else {
            throw MeshBinaryCodecError.invalidHeaderLength(readHeaderLength)
        }

        let vertexCount = Int(try reader.readUInt32())
        let faceCount = Int(try reader.readUInt32())
        let indexWidth = try reader.readUInt8()
        guard indexWidth == 4 else {
            throw MeshBinaryCodecError.unsupportedIndexWidth(indexWidth)
        }

        let flags = try reader.readUInt8()
        let allowedFlags = flagNormals | flagClassifications
        guard flags & ~allowedFlags == 0 else {
            throw MeshBinaryCodecError.invalidFlags(flags)
        }

        _ = try reader.readUInt16()
        _ = try reader.readUInt32()

        var vertices: [Float3] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            vertices.append(
                Float3(
                    try reader.readFloat(),
                    try reader.readFloat(),
                    try reader.readFloat()
                )
            )
        }

        var normals: [Float3]?
        if flags & flagNormals != 0 {
            var decoded: [Float3] = []
            decoded.reserveCapacity(vertexCount)
            for _ in 0..<vertexCount {
                decoded.append(
                    Float3(
                        try reader.readFloat(),
                        try reader.readFloat(),
                        try reader.readFloat()
                    )
                )
            }
            normals = decoded
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(faceCount * 3)
        for _ in 0..<(faceCount * 3) {
            indices.append(try reader.readUInt32())
        }

        var classifications: [UInt8]?
        if flags & flagClassifications != 0 {
            classifications = Array(try reader.readBytes(count: faceCount))
        }

        let trailing = reader.remaining
        guard trailing == 0 else {
            throw MeshBinaryCodecError.trailingBytes(trailing)
        }

        do {
            return try MeshGeometryPayload(
                vertices: vertices,
                normals: normals,
                triangleIndices: indices,
                faceClassifications: classifications
            )
        } catch {
            throw MeshBinaryCodecError.invalidGeometry
        }
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

    private static func appendFloat(_ value: Float, to data: inout Data) {
        appendUInt32(value.bitPattern, to: &data)
    }

    private struct Reader {
        let data: Data
        var offset: Int = 0

        var remaining: Int {
            data.count - offset
        }

        mutating func readBytes(count: Int) throws -> Data {
            guard count >= 0, remaining >= count else {
                throw MeshBinaryCodecError.truncated
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readUInt8() throws -> UInt8 {
            guard remaining >= 1 else {
                throw MeshBinaryCodecError.truncated
            }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            let b0 = UInt16(try readUInt8())
            let b1 = UInt16(try readUInt8())
            return b0 | (b1 << 8)
        }

        mutating func readUInt32() throws -> UInt32 {
            let b0 = UInt32(try readUInt8())
            let b1 = UInt32(try readUInt8())
            let b2 = UInt32(try readUInt8())
            let b3 = UInt32(try readUInt8())
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }

        mutating func readFloat() throws -> Float {
            Float(bitPattern: try readUInt32())
        }
    }
}
