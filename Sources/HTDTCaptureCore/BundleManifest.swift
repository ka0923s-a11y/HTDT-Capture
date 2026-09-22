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
    case reservedPathMetadataMismatch(String)
    case unboundProvenanceClass(String)
    case malformedSourceRef(String, String)
    case duplicateSourceRef(String, String)
    case unresolvedSourceRefPath(String, String)
    case unresolvedSourceRefDigest(String, String)
    case ambiguousSourceRefDigest(String, String)
    case sourceRefLimitExceeded(String)
    case unknownSourceRefSession(String, String)
    case selfReferencingSourceRef(String, String)
    case cyclicSourceRefPath(String, String)
    case derivedEntryMissingSourceRefs(String)
    case reservedPathSourceRefMismatch(String)
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
            try Self.validateReservedPathBinding(file)
        }

        // sha256 source_refs must resolve to exactly one payload
        // authority (#193): identical bytes under different logical
        // paths are distinct authorities (different producer /
        // provenance / lineage), so a shared digest cannot disambiguate
        // them and must be expressed as a path: reference instead.
        var digestCounts: [String: Int] = [:]
        for file in files {
            digestCounts[file.sha256.value, default: 0] += 1
        }
        let declaredSessionIDs = Set(captureSessionIDs)
        var pathEdges: [String: [String]] = [:]
        var totalSourceRefs = 0
        for file in files {
            try Self.validateSourceRefs(
                of: file,
                declaredByPath: declaredByPath,
                digestCounts: digestCounts,
                sessionIDs: declaredSessionIDs,
                pathEdges: &pathEdges,
                totalSourceRefs: &totalSourceRefs
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

    private static func validateReservedPathBinding(
        _ file: BundleFileEntry
    ) throws {
        if let binding = BundleReservedPaths.binding(for: file.path) {
            guard file.mediaType == binding.mediaType,
                  file.producer == binding.producer,
                  file.provenanceClass == binding.provenanceClass,
                  file.role == binding.role
            else {
                throw BundleManifestError
                    .reservedPathMetadataMismatch(file.path)
            }
        } else {
            guard BundleReservedPaths.unrestrictedProvenanceClasses
                .contains(file.provenanceClass)
            else {
                throw BundleManifestError.unboundProvenanceClass(
                    file.path
                )
            }
        }
    }

    /// v1 source_ref budgets (#195): lineage resolution work must stay
    /// bounded independently of the manifest byte cap. Identical limits
    /// are enforced by the Python validator and reference ingestor.
    static let maxSourceRefsPerEntry = 32
    static let maxSourceRefBytes = 512
    static let maxSourceRefsTotal = 65_536

    private static func validateSourceRefs(
        of file: BundleFileEntry,
        declaredByPath: [String: BundleFileEntry],
        digestCounts: [String: Int],
        sessionIDs: Set<CaptureSessionID>,
        pathEdges: inout [String: [String]],
        totalSourceRefs: inout Int
    ) throws {
        let refs = file.sourceRefs ?? []
        if refs.count > maxSourceRefsPerEntry {
            throw BundleManifestError.sourceRefLimitExceeded(file.path)
        }
        totalSourceRefs += refs.count
        if totalSourceRefs > maxSourceRefsTotal {
            throw BundleManifestError.sourceRefLimitExceeded(file.path)
        }
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
            guard ref.utf8.count <= maxSourceRefBytes else {
                throw BundleManifestError.sourceRefLimitExceeded(
                    file.path
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
                let digestCount = digestCounts[value] ?? 0
                guard digestCount > 0 else {
                    throw BundleManifestError
                        .unresolvedSourceRefDigest(
                            file.path,
                            ref
                        )
                }
                guard digestCount == 1 else {
                    throw BundleManifestError
                        .ambiguousSourceRefDigest(
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
        if file.path == "roomplan/captured-room.json" {
            guard let rawDigest =
                    declaredByPath["roomplan/captured-room-data.json"]?
                    .sha256.value,
                  refs.contains("sha256:\(rawDigest)")
            else {
                throw BundleManifestError
                    .reservedPathSourceRefMismatch(file.path)
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

enum BundleReservedPaths {
    struct Binding: Sendable, Equatable {
        let mediaType: String
        let producer: String
        let provenanceClass: BundleProvenanceClass
        let role: BundleFileRole
    }

    static let exact: [String: Binding] = [
        "annotations/entities.json": Binding(
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical
        ),
        "annotations/authorities.json": Binding(
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical
        ),
        "annotations/measurements.json": Binding(
            mediaType: "application/json",
            producer: "measurement",
            provenanceClass: .userAttestedMeasurement,
            role: .canonical
        ),
        "annotations/opening-review.json": Binding(
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical
        ),
        "mesh/anchors.json": Binding(
            mediaType: "application/json",
            producer: "mesh_capture",
            provenanceClass: .arkitMeshReconstruction,
            role: .canonical
        ),
        "quality/capture-quality.json": Binding(
            mediaType: "application/json",
            producer: "capture_quality",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "roomplan/captured-room-data.json": Binding(
            mediaType: "application/json",
            producer: "roomplan_capture",
            provenanceClass: .appleRoomPlanRawScan,
            role: .canonical
        ),
        "roomplan/captured-room-metadata.json": Binding(
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "roomplan/captured-room.json": Binding(
            mediaType: "application/json",
            producer: "roomplan_builder",
            provenanceClass: .appleRoomPlanInference,
            role: .canonical
        ),
        "session/capabilities.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/capture-configuration.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/capture-session.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/coordinate-space-policy.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/device.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/room-reference-frame.json": Binding(
            mediaType: "application/json",
            producer: "room_frame",
            provenanceClass: .userAnnotation,
            role: .canonical
        ),
        "session/timing.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        // Advanced workflow payloads (issues #222/#227/#240/#249/#293):
        // reserved-path-bound but not schema-owned, matching the
        // coordinate-space-policy precedent.
        "derived/authority-dependencies.json": Binding(
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .derived
        ),
        "derived/geometry-candidates.json": Binding(
            mediaType: "application/json",
            producer: "derived_geometry",
            provenanceClass: .captureAppDerived,
            role: .derived
        ),
        "evidence/reference-targets.json": Binding(
            mediaType: "application/json",
            producer: "reference_target_capture",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/capture-task-plan.json": Binding(
            mediaType: "application/json",
            producer: "htdt_plan",
            provenanceClass: .importedReference,
            role: .canonical
        ),
        "session/connected-spaces.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "session/task-plan-status.json": Binding(
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
        "verification/as-built.json": Binding(
            mediaType: "application/json",
            producer: "asbuilt_verification",
            provenanceClass: .captureAppDerived,
            role: .canonical
        ),
    ]

    static let patterned:
        [(directory: String, suffix: String, binding: Binding)] = [
            (
                "evidence/depth",
                ".confidencebin",
                Binding(
                    mediaType: "application/vnd.htdt.confidencebin",
                    producer: "depth_capture",
                    provenanceClass: .arkitSceneDepthObservation,
                    role: .canonical
                )
            ),
            (
                "evidence/depth",
                ".depthbin",
                Binding(
                    mediaType: "application/vnd.htdt.depthbin",
                    producer: "depth_capture",
                    provenanceClass: .arkitSceneDepthObservation,
                    role: .canonical
                )
            ),
            (
                "evidence/frames",
                ".json",
                Binding(
                    mediaType: "application/json",
                    producer: "frame_capture",
                    provenanceClass: .arkitFrameObservation,
                    role: .canonical
                )
            ),
            (
                "evidence/frames",
                ".pixelbin",
                Binding(
                    mediaType: "application/vnd.htdt.pixelbin",
                    producer: "frame_capture",
                    provenanceClass: .arkitFrameObservation,
                    role: .canonical
                )
            ),
            (
                "evidence/frames",
                ".preview.heic",
                Binding(
                    mediaType: "image/heic",
                    producer: "frame_preview",
                    provenanceClass: .captureAppDerived,
                    role: .derived
                )
            ),
            (
                "mesh/geometry",
                ".meshbin",
                Binding(
                    mediaType: "application/vnd.htdt.meshbin",
                    producer: "mesh_capture",
                    provenanceClass: .arkitMeshReconstruction,
                    role: .canonical
                )
            ),
            // Typed field evidence (issues #300/#314): dedicated
            // close-up photos captured for a record live under
            // `evidence/field/captured/`, imported documents/photos
            // under `evidence/field/imported/`. The directory split
            // pins provenance by path alone — a captured asset can
            // never masquerade as an imported external document.
            (
                "evidence/field/captured",
                ".heic",
                Binding(
                    mediaType: "image/heic",
                    producer: "field_evidence_capture",
                    provenanceClass: .captureAppDerived,
                    role: .canonical
                )
            ),
            (
                "evidence/field/captured",
                ".jpg",
                Binding(
                    mediaType: "image/jpeg",
                    producer: "field_evidence_capture",
                    provenanceClass: .captureAppDerived,
                    role: .canonical
                )
            ),
            (
                "evidence/field/captured",
                ".png",
                Binding(
                    mediaType: "image/png",
                    producer: "field_evidence_capture",
                    provenanceClass: .captureAppDerived,
                    role: .canonical
                )
            ),
            (
                "evidence/field/imported",
                ".heic",
                Binding(
                    mediaType: "image/heic",
                    producer: "field_evidence_import",
                    provenanceClass: .importedReference,
                    role: .canonical
                )
            ),
            (
                "evidence/field/imported",
                ".jpg",
                Binding(
                    mediaType: "image/jpeg",
                    producer: "field_evidence_import",
                    provenanceClass: .importedReference,
                    role: .canonical
                )
            ),
            (
                "evidence/field/imported",
                ".png",
                Binding(
                    mediaType: "image/png",
                    producer: "field_evidence_import",
                    provenanceClass: .importedReference,
                    role: .canonical
                )
            ),
            (
                "evidence/field/imported",
                ".pdf",
                Binding(
                    mediaType: "application/pdf",
                    producer: "field_evidence_import",
                    provenanceClass: .importedReference,
                    role: .canonical
                )
            ),
            (
                "evidence/field/imported",
                ".bin",
                Binding(
                    mediaType: "application/octet-stream",
                    producer: "field_evidence_import",
                    provenanceClass: .importedReference,
                    role: .canonical
                )
            ),
        ]

    static let unrestrictedProvenanceClasses:
        Set<BundleProvenanceClass> = [
            .captureAppDerived,
            .importedReference,
            .backendDerived,
        ]

    static func binding(for path: String) -> Binding? {
        if let binding = exact[path] {
            return binding
        }
        for pattern in patterned {
            guard path.hasPrefix(pattern.directory + "/") else {
                continue
            }
            let name = String(
                path.dropFirst(pattern.directory.count + 1)
            )
            guard name.hasSuffix(pattern.suffix),
                  name.count > pattern.suffix.count,
                  !name.contains("/")
            else {
                continue
            }
            let stem = name.dropLast(pattern.suffix.count)
            guard UUID(canonicalUUIDv4Text: String(stem)) != nil
            else {
                continue
            }
            return pattern.binding
        }
        return nil
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
