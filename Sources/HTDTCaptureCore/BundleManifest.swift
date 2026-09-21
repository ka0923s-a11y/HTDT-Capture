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
    case caseCollidingPayloadPath(String, String)
    case manifestSelfDeclaration
    case invalidTimestamp(String)
    case finalizedBeforeCreated(String, String)
    case selfParentRevision
    case malformedSourceRef(String, String)
    case duplicateSourceRef(String, String)
    case unresolvedSourceRefPath(String, String)
    case unresolvedSourceRefDigest(String, String)
    case unknownSourceRefSession(String, String)
    case selfReferencingSourceRef(String, String)
    case cyclicSourceRefPath(String, String)
    case derivedEntryMissingSourceRefs(String)
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
        if let parentRevisionID,
           parentRevisionID == captureRevisionID
        {
            throw BundleManifestError.selfParentRevision
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
        guard let createdInstant = Self.parseUTCText(
            createdAtUTC
        ) else {
            throw BundleManifestError.invalidTimestamp(createdAtUTC)
        }
        guard let finalizedInstant = Self.parseUTCText(
            finalizedAtUTC
        ) else {
            throw BundleManifestError.invalidTimestamp(finalizedAtUTC)
        }
        // The lifecycle timestamps are audit chronology: a revision
        // cannot be finalized before it was created. Compare parsed
        // instants so fractional-second representations cannot invert
        // the ordering.
        guard finalizedInstant >= createdInstant else {
            throw BundleManifestError.finalizedBeforeCreated(
                createdAtUTC,
                finalizedAtUTC
            )
        }

        var seen = Set<String>()
        var collisionMap: [String: String] = [:]
        var declaredByPath: [String: BundleFileEntry] = [:]
        for file in files {
            if file.path == "manifest.json" {
                throw BundleManifestError.manifestSelfDeclaration
            }
            try BundleLogicalPath.validate(file.path)
            if !seen.insert(file.path).inserted {
                throw BundleManifestError.duplicatePayloadPath(file.path)
            }

            let collisionKey =
                BundleLogicalPath.collisionKey(file.path)
            if let prior = collisionMap[collisionKey] {
                throw BundleManifestError
                    .caseCollidingPayloadPath(
                        prior,
                        file.path
                    )
            }
            collisionMap[collisionKey] = file.path
            declaredByPath[file.path] = file
        }

        var declaredDigests = Set<String>()
        for file in files {
            declaredDigests.insert(file.sha256.value)
        }
        let declaredSessionIDs = Set(captureSessionIDs)
        var pathEdges: [String: [String]] = [:]
        for file in files {
            try Self.validateSourceRefs(
                of: file,
                declaredByPath: declaredByPath,
                declaredDigests: declaredDigests,
                sessionIDs: declaredSessionIDs,
                pathEdges: &pathEdges
            )
        }
        try Self.validateSourceRefPathGraph(
            pathEdges: pathEdges,
            declaredPaths: seen.sorted(by: Self.utf8Less)
        )

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

    private static func parseUTCText(_ value: String) -> Date? {
        let pattern =
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"#
        guard value.range(
            of: pattern,
            options: .regularExpression
        ) != nil
        else {
            return nil
        }

        let base = ISO8601DateFormatter()
        base.formatOptions = [.withInternetDateTime]
        if let instant = base.date(from: value) {
            return instant
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return fractional.date(from: value)
    }

    private static func isUUIDv4(_ uuid: UUID) -> Bool {
        uuid.isCanonicalUUIDv4
    }

    private static func validateSourceRefs(
        of file: BundleFileEntry,
        declaredByPath: [String: BundleFileEntry],
        declaredDigests: Set<String>,
        sessionIDs: Set<CaptureSessionID>,
        pathEdges: inout [String: [String]]
    ) throws {
        let refs = file.sourceRefs ?? []
        if file.role == .derived, refs.isEmpty {
            throw BundleManifestError.derivedEntryMissingSourceRefs(
                file.path
            )
        }
        var seenRefs = Set<String>()
        for ref in refs {
            guard !ref.isEmpty else {
                throw BundleManifestError.malformedSourceRef(
                    file.path,
                    ref
                )
            }
            guard seenRefs.insert(ref).inserted else {
                throw BundleManifestError.duplicateSourceRef(
                    file.path,
                    ref
                )
            }
            if ref.hasPrefix("path:") {
                let target = String(ref.dropFirst(5))
                do {
                    try BundleLogicalPath.validate(target)
                } catch {
                    throw BundleManifestError.malformedSourceRef(
                        file.path,
                        ref
                    )
                }
                if target == file.path {
                    throw BundleManifestError.selfReferencingSourceRef(
                        file.path,
                        ref
                    )
                }
                guard declaredByPath[target] != nil else {
                    throw BundleManifestError.unresolvedSourceRefPath(
                        file.path,
                        ref
                    )
                }
                pathEdges[file.path, default: []].append(target)
            } else if ref.hasPrefix("sha256:") {
                let value = String(ref.dropFirst(7))
                guard (try? EvidenceSHA256(value)) != nil else {
                    throw BundleManifestError.malformedSourceRef(
                        file.path,
                        ref
                    )
                }
                if value == file.sha256.value {
                    throw BundleManifestError.selfReferencingSourceRef(
                        file.path,
                        ref
                    )
                }
                guard declaredDigests.contains(value) else {
                    throw BundleManifestError
                        .unresolvedSourceRefDigest(
                            file.path,
                            ref
                        )
                }
            } else if ref.hasPrefix("capture_session:") {
                let value = String(ref.dropFirst(16))
                guard let sessionID =
                        CaptureSessionID(canonicalString: value)
                else {
                    throw BundleManifestError.malformedSourceRef(
                        file.path,
                        ref
                    )
                }
                guard sessionIDs.contains(sessionID) else {
                    throw BundleManifestError.unknownSourceRefSession(
                        file.path,
                        ref
                    )
                }
            } else if ref != "roomplan_raw_serialization:unavailable" {
                throw BundleManifestError.malformedSourceRef(
                    file.path,
                    ref
                )
            }
        }
    }

    private static func validateSourceRefPathGraph(
        pathEdges: [String: [String]],
        declaredPaths: [String]
    ) throws {
        var visitState: [String: Int] = [:]
        for root in declaredPaths where visitState[root] == nil {
            visitState[root] = 1
            var stack: [(path: String, nextChild: Int)] = [
                (path: root, nextChild: 0)
            ]
            while let frame = stack.last {
                let children = pathEdges[frame.path] ?? []
                if frame.nextChild < children.count {
                    let child = children[frame.nextChild]
                    stack[stack.count - 1].nextChild += 1
                    if let childState = visitState[child] {
                        if childState == 1 {
                            throw BundleManifestError
                                .cyclicSourceRefPath(
                                    frame.path,
                                    "path:\(child)"
                                )
                        }
                    } else {
                        visitState[child] = 1
                        stack.append((path: child, nextChild: 0))
                    }
                } else {
                    visitState[frame.path] = 2
                    stack.removeLast()
                }
            }
        }
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
