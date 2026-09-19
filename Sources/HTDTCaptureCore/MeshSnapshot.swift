import Foundation

public struct Float3: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

public enum Matrix4x4FError: Error, Sendable, Equatable {
    case invalidElementCount(Int)
    case nonFinite
}

public struct Matrix4x4F: Codable, Sendable, Equatable {
    public static let representation = "column_major_4x4_f32"

    public let values: [Float]

    public init(values: [Float]) throws {
        guard values.count == 16 else {
            throw Matrix4x4FError.invalidElementCount(values.count)
        }
        guard values.allSatisfy(\.isFinite) else {
            throw Matrix4x4FError.nonFinite
        }
        self.values = values
    }

    public static var identity: Matrix4x4F {
        try! Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    private enum CodingKeys: String, CodingKey {
        case representation
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let representation = try container.decode(
            String.self,
            forKey: .representation
        )
        guard representation == Self.representation else {
            throw DecodingError.dataCorruptedError(
                forKey: .representation,
                in: container,
                debugDescription: "Unsupported matrix representation"
            )
        }
        try self.init(
            values: container.decode([Float].self, forKey: .values)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Self.representation,
            forKey: .representation
        )
        try container.encode(values, forKey: .values)
    }
}

public enum MeshGeometryError: Error, Sendable, Equatable {
    case noVertices
    case invalidNormalCount(expected: Int, actual: Int)
    case indexCountNotTriangles(Int)
    case indexOutOfBounds(UInt32)
    case invalidClassificationCount(expected: Int, actual: Int)
    case nonFiniteVertex(Int)
    case nonFiniteNormal(Int)
}

public struct MeshGeometryPayload: Codable, Sendable, Equatable {
    public let vertices: [Float3]
    public let normals: [Float3]?
    public let triangleIndices: [UInt32]
    public let faceClassifications: [UInt8]?

    public init(
        vertices: [Float3],
        normals: [Float3]? = nil,
        triangleIndices: [UInt32],
        faceClassifications: [UInt8]? = nil
    ) throws {
        guard !vertices.isEmpty else {
            throw MeshGeometryError.noVertices
        }

        for (index, vertex) in vertices.enumerated() where !vertex.isFinite {
            throw MeshGeometryError.nonFiniteVertex(index)
        }

        if let normals {
            guard normals.count == vertices.count else {
                throw MeshGeometryError.invalidNormalCount(
                    expected: vertices.count,
                    actual: normals.count
                )
            }
            for (index, normal) in normals.enumerated() where !normal.isFinite {
                throw MeshGeometryError.nonFiniteNormal(index)
            }
        }

        guard triangleIndices.count.isMultiple(of: 3) else {
            throw MeshGeometryError.indexCountNotTriangles(triangleIndices.count)
        }

        guard let vertexCount = UInt32(exactly: vertices.count) else {
            throw MeshGeometryError.noVertices
        }
        for index in triangleIndices where index >= vertexCount {
            throw MeshGeometryError.indexOutOfBounds(index)
        }

        let faceCount = triangleIndices.count / 3
        if let faceClassifications, faceClassifications.count != faceCount {
            throw MeshGeometryError.invalidClassificationCount(
                expected: faceCount,
                actual: faceClassifications.count
            )
        }

        self.vertices = vertices
        self.normals = normals
        self.triangleIndices = triangleIndices
        self.faceClassifications = faceClassifications
    }

    public var faceCount: Int {
        triangleIndices.count / 3
    }
}

public struct MeshAnchorSnapshot: Codable, Sendable, Equatable {
    public let anchorID: UUID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let worldFromAnchor: Matrix4x4F
    public let sessionTimestampSeconds: Double?
    public let geometry: MeshGeometryPayload

    public init(
        anchorID: UUID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        worldFromAnchor: Matrix4x4F,
        sessionTimestampSeconds: Double?,
        geometry: MeshGeometryPayload
    ) {
        self.anchorID = anchorID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromAnchor = worldFromAnchor
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.geometry = geometry
    }
}
