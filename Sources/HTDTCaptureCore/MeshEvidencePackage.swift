import Foundation

public enum MeshEvidencePackageError: Error, Sendable, Equatable {
    case duplicateAnchorID(UUID)
    case invalidAnchorID(UUID)
    case missingSessionTimestamp(UUID)
    case invalidSessionTimestamp(UUID, Double)
}

public struct MeshAnchorEvidenceRecord: Codable, Sendable, Equatable {
    public let anchorID: String
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let worldFromAnchor: Matrix4x4F
    public let sessionTimestampSeconds: Double
    public let vertexCount: Int
    public let faceCount: Int
    public let geometryPath: String
    public let geometrySHA256: EvidenceSHA256

    public init(
        anchorID: UUID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        worldFromAnchor: Matrix4x4F,
        sessionTimestampSeconds: Double,
        vertexCount: Int,
        faceCount: Int,
        geometryPath: String,
        geometrySHA256: EvidenceSHA256
    ) {
        self.anchorID = anchorID.uuidString.lowercased()
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromAnchor = worldFromAnchor
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.geometryPath = geometryPath
        self.geometrySHA256 = geometrySHA256
    }

    private enum CodingKeys: String, CodingKey {
        case anchorID = "anchor_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case worldFromAnchor = "T_world_from_mesh_anchor"
        case sessionTimestampSeconds = "session_timestamp_s"
        case vertexCount = "vertex_count"
        case faceCount = "face_count"
        case geometryPath = "geometry_path"
        case geometrySHA256 = "geometry_sha256"
    }
}

public struct MeshAnchorEvidenceIndex: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let anchors: [MeshAnchorEvidenceRecord]

    public init(anchors: [MeshAnchorEvidenceRecord]) {
        self.schema = "htdt.capture.mesh-anchors"
        self.schemaVersion = "1.0.0"
        self.anchors = anchors
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case anchors
    }
}

public struct MeshEvidenceGeometryFile: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let sha256: EvidenceSHA256

    public init(
        path: String,
        data: Data,
        sha256: EvidenceSHA256
    ) {
        self.path = path
        self.data = data
        self.sha256 = sha256
    }
}

public struct MeshEvidencePackage: Sendable, Equatable {
    public static let indexPath = "mesh/anchors.json"

    public let index: MeshAnchorEvidenceIndex
    public let indexData: Data
    public let geometryFiles: [MeshEvidenceGeometryFile]

    public init(
        index: MeshAnchorEvidenceIndex,
        indexData: Data,
        geometryFiles: [MeshEvidenceGeometryFile]
    ) {
        self.index = index
        self.indexData = indexData
        self.geometryFiles = geometryFiles
    }

    public func persist(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        for file in geometryFiles {
            try await writer.write(
                file.data,
                to: CaptureStorePath(file.path)
            )
        }

        try await writer.write(
            indexData,
            to: CaptureStorePath(Self.indexPath)
        )
    }
}

public enum MeshEvidencePackageBuilder {
    public static func build(
        snapshots: [MeshAnchorSnapshot]
    ) throws -> MeshEvidencePackage {
        var seenAnchorIDs = Set<UUID>()

        let sorted = snapshots.sorted {
            $0.anchorID.uuidString.lowercased()
                < $1.anchorID.uuidString.lowercased()
        }

        var records: [MeshAnchorEvidenceRecord] = []
        var files: [MeshEvidenceGeometryFile] = []
        records.reserveCapacity(sorted.count)
        files.reserveCapacity(sorted.count)

        for snapshot in sorted {
            guard seenAnchorIDs.insert(snapshot.anchorID).inserted else {
                throw MeshEvidencePackageError.duplicateAnchorID(
                    snapshot.anchorID
                )
            }
            guard isUUIDv4(snapshot.anchorID) else {
                throw MeshEvidencePackageError.invalidAnchorID(
                    snapshot.anchorID
                )
            }
            guard let timestamp = snapshot.sessionTimestampSeconds else {
                throw MeshEvidencePackageError.missingSessionTimestamp(
                    snapshot.anchorID
                )
            }
            guard timestamp.isFinite, timestamp >= 0 else {
                throw MeshEvidencePackageError.invalidSessionTimestamp(
                    snapshot.anchorID,
                    timestamp
                )
            }

            let data = try MeshBinaryCodec.encode(snapshot.geometry)
            let digest = EvidenceIntegrity.sha256(of: data)
            let anchorText = snapshot.anchorID.uuidString.lowercased()
            let path = "mesh/geometry/\(anchorText).meshbin"

            files.append(
                MeshEvidenceGeometryFile(
                    path: path,
                    data: data,
                    sha256: digest
                )
            )
            records.append(
                MeshAnchorEvidenceRecord(
                    anchorID: snapshot.anchorID,
                    captureSessionID: snapshot.captureSessionID,
                    coordinateSpaceID: snapshot.coordinateSpaceID,
                    worldFromAnchor: snapshot.worldFromAnchor,
                    sessionTimestampSeconds: timestamp,
                    vertexCount: snapshot.geometry.vertices.count,
                    faceCount: snapshot.geometry.faceCount,
                    geometryPath: path,
                    geometrySHA256: digest
                )
            )
        }

        let index = MeshAnchorEvidenceIndex(anchors: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let indexData = try encoder.encode(index)

        return MeshEvidencePackage(
            index: index,
            indexData: indexData,
            geometryFiles: files
        )
    }

    private static func isUUIDv4(_ uuid: UUID) -> Bool {
        var value = uuid.uuid
        let bytes = withUnsafeBytes(of: &value) {
            Array($0)
        }
        return (bytes[6] & 0xf0) == 0x40
            && (bytes[8] & 0xc0) == 0x80
    }
}
