import Foundation

public enum BundleProvenanceClass: String, Codable, Sendable {
    case arkitFrameObservation = "arkit_frame_observation"
    case arkitSceneDepthObservation = "arkit_scene_depth_observation"
    case arkitMeshReconstruction = "arkit_mesh_reconstruction"
    case appleRoomPlanRawScan = "apple_roomplan_raw_scan"
    case appleRoomPlanInference = "apple_roomplan_inference"
    case userAttestedMeasurement = "user_attested_measurement"
    case userAnnotation = "user_annotation"
    case importedReference = "imported_reference"
    case captureAppDerived = "capture_app_derived"
    case backendDerived = "backend_derived"
}

public enum BundleFileRole: String, Codable, Sendable {
    case canonical
    case derived
}

public struct BundleAppIdentity: Codable, Sendable, Equatable {
    public let name: String
    public let version: String
    public let build: String

    public init(
        name: String = "HTDT-Capture",
        version: String,
        build: String
    ) {
        self.name = name
        self.version = version
        self.build = build
    }
}

public struct BundlePayloadDeclaration: Sendable, Equatable {
    public let path: String
    public let mediaType: String
    public let producer: String
    public let provenanceClass: BundleProvenanceClass
    public let role: BundleFileRole
    public let sourceRefs: [String]?

    public init(
        path: String,
        mediaType: String,
        producer: String,
        provenanceClass: BundleProvenanceClass,
        role: BundleFileRole,
        sourceRefs: [String]? = nil
    ) {
        self.path = path
        self.mediaType = mediaType
        self.producer = producer
        self.provenanceClass = provenanceClass
        self.role = role
        self.sourceRefs = sourceRefs
    }
}

public struct BundleFileEntry: Codable, Sendable, Equatable {
    public let path: String
    public let bytes: Int
    public let mediaType: String
    public let sha256: EvidenceSHA256
    public let producer: String
    public let provenanceClass: BundleProvenanceClass
    public let role: BundleFileRole
    public let sourceRefs: [String]?

    public init(
        path: String,
        bytes: Int,
        mediaType: String,
        sha256: EvidenceSHA256,
        producer: String,
        provenanceClass: BundleProvenanceClass,
        role: BundleFileRole,
        sourceRefs: [String]? = nil
    ) {
        self.path = path
        self.bytes = bytes
        self.mediaType = mediaType
        self.sha256 = sha256
        self.producer = producer
        self.provenanceClass = provenanceClass
        self.role = role
        self.sourceRefs = sourceRefs
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case bytes
        case mediaType = "media_type"
        case sha256
        case producer
        case provenanceClass = "provenance_class"
        case role
        case sourceRefs = "source_refs"
    }

    func canonicalJSONValue() -> CanonicalJSONValue {
        var object: [String: CanonicalJSONValue] = [
            "path": .string(path),
            "bytes": .integer(bytes),
            "media_type": .string(mediaType),
            "sha256": .string(sha256.description),
            "producer": .string(producer),
            "provenance_class": .string(provenanceClass.rawValue),
            "role": .string(role.rawValue),
        ]
        if let sourceRefs {
            object["source_refs"] = .array(
                sourceRefs.map(CanonicalJSONValue.string)
            )
        }
        return .object(object)
    }
}

public enum BundleManifestError: Error, Sendable, Equatable {
    case invalidSchema
    case invalidAppIdentity
    case invalidUUIDv4(String)
    case emptySessionIDs
    case emptyCoordinateSpaceIDs
    case duplicateSessionID
    case duplicateCoordinateSpaceID
    case duplicatePayloadPath(String)
    case manifestSelfDeclaration
    case invalidTimestamp(String)
}

public struct BundleManifest: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    public let parentRevisionID: CaptureRevisionID?
    public let captureSessionIDs: [CaptureSessionID]
    public let coordinateSpaceIDs: [CoordinateSpaceID]
    public let createdAtUTC: String
    public let finalizedAtUTC: String
    public let app: BundleAppIdentity
    public let files: [BundleFileEntry]

    public init(
        captureSeriesID: CaptureSeriesID,
        captureRevisionID: CaptureRevisionID,
        parentRevisionID: CaptureRevisionID?,
        captureSessionIDs: [CaptureSessionID],
        coordinateSpaceIDs: [CoordinateSpaceID],
        createdAtUTC: String,
        finalizedAtUTC: String,
        app: BundleAppIdentity,
        files: [BundleFileEntry]
    ) throws {
        guard Self.isUUIDv4(captureSeriesID.rawValue) else {
            throw BundleManifestError.invalidUUIDv4(
                captureSeriesID.description
            )
        }
        guard Self.isUUIDv4(captureRevisionID.rawValue) else {
            throw BundleManifestError.invalidUUIDv4(
                captureRevisionID.description
            )
        }
        if let parentRevisionID,
           !Self.isUUIDv4(parentRevisionID.rawValue)
        {
            throw BundleManifestError.invalidUUIDv4(
                parentRevisionID.description
            )
        }
        guard !captureSessionIDs.isEmpty else {
            throw BundleManifestError.emptySessionIDs
        }
        guard !coordinateSpaceIDs.isEmpty else {
            throw BundleManifestError.emptyCoordinateSpaceIDs
        }
        for id in captureSessionIDs where !Self.isUUIDv4(id.rawValue) {
            throw BundleManifestError.invalidUUIDv4(id.description)
        }
        for id in coordinateSpaceIDs where !Self.isUUIDv4(id.rawValue) {
            throw BundleManifestError.invalidUUIDv4(id.description)
        }
        guard Set(captureSessionIDs).count == captureSessionIDs.count else {
            throw BundleManifestError.duplicateSessionID
        }
        guard Set(coordinateSpaceIDs).count == coordinateSpaceIDs.count else {
            throw BundleManifestError.duplicateCoordinateSpaceID
        }
        guard app.name == "HTDT-Capture",
              !app.version.isEmpty,
              !app.build.isEmpty
        else {
            throw BundleManifestError.invalidAppIdentity
        }
        guard Self.isUTCText(createdAtUTC) else {
            throw BundleManifestError.invalidTimestamp(createdAtUTC)
        }
        guard Self.isUTCText(finalizedAtUTC) else {
            throw BundleManifestError.invalidTimestamp(finalizedAtUTC)
        }

        var seen = Set<String>()
        for file in files {
            if file.path == "manifest.json" {
                throw BundleManifestError.manifestSelfDeclaration
            }
            if !seen.insert(file.path).inserted {
                throw BundleManifestError.duplicatePayloadPath(file.path)
            }
        }

        self.schema = "htdt.capture.bundle"
        self.schemaVersion = "1.0.0"
        self.captureSeriesID = captureSeriesID
        self.captureRevisionID = captureRevisionID
        self.parentRevisionID = parentRevisionID
        self.captureSessionIDs = captureSessionIDs
        self.coordinateSpaceIDs = coordinateSpaceIDs
        self.createdAtUTC = createdAtUTC
        self.finalizedAtUTC = finalizedAtUTC
        self.app = app
        self.files = files.sorted { Self.utf8Less($0.path, $1.path) }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureSeriesID = "capture_series_id"
        case captureRevisionID = "capture_revision_id"
        case parentRevisionID = "parent_revision_id"
        case captureSessionIDs = "capture_session_ids"
        case coordinateSpaceIDs = "coordinate_space_ids"
        case createdAtUTC = "created_at"
        case finalizedAtUTC = "finalized_at"
        case app
        case files
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == "htdt.capture.bundle",
              schemaVersion == "1.0.0"
        else {
            throw BundleManifestError.invalidSchema
        }

        try self.init(
            captureSeriesID: container.decode(
                CaptureSeriesID.self,
                forKey: .captureSeriesID
            ),
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            parentRevisionID: container.decodeIfPresent(
                CaptureRevisionID.self,
                forKey: .parentRevisionID
            ),
            captureSessionIDs: container.decode(
                [CaptureSessionID].self,
                forKey: .captureSessionIDs
            ),
            coordinateSpaceIDs: container.decode(
                [CoordinateSpaceID].self,
                forKey: .coordinateSpaceIDs
            ),
            createdAtUTC: container.decode(
                String.self,
                forKey: .createdAtUTC
            ),
            finalizedAtUTC: container.decode(
                String.self,
                forKey: .finalizedAtUTC
            ),
            app: container.decode(
                BundleAppIdentity.self,
                forKey: .app
            ),
            files: container.decode(
                [BundleFileEntry].self,
                forKey: .files
            )
        )
    }

    public func canonicalBytes() throws -> Data {
        try CanonicalJSON.encode(canonicalJSONValue())
    }

    public func canonicalJSONValue() -> CanonicalJSONValue {
        .object([
            "schema": .string(schema),
            "schema_version": .string(schemaVersion),
            "capture_series_id": .string(captureSeriesID.description),
            "capture_revision_id": .string(captureRevisionID.description),
            "parent_revision_id": parentRevisionID.map {
                .string($0.description)
            } ?? .null,
            "capture_session_ids": .array(
                captureSessionIDs.map {
                    .string($0.description)
                }
            ),
            "coordinate_space_ids": .array(
                coordinateSpaceIDs.map {
                    .string($0.description)
                }
            ),
            "created_at": .string(createdAtUTC),
            "finalized_at": .string(finalizedAtUTC),
            "app": .object([
                "name": .string(app.name),
                "version": .string(app.version),
                "build": .string(app.build),
            ]),
            "files": .array(files.map { $0.canonicalJSONValue() }),
        ])
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
    }

    private static func isUTCText(_ value: String) -> Bool {
        value.contains("T") && value.hasSuffix("Z")
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

public enum BundleTimestamp {
    public static func utcString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
