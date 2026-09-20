import Foundation

public enum CaptureWorkingSetError: Error, Sendable, Equatable {
    case invalidRawRoomPlanDescriptor
    case invalidProcessedRoomPlanDescriptor
    case processedRoomPlanRequiresRaw
    case processedRoomPlanLineageMismatch
    case invalidMeshPackage
    case authorityMismatch
    case duplicatePayloadDeclaration(String)
}

public struct CaptureWorkingSetIdentity: Sendable, Equatable {
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    public let parentRevisionID: CaptureRevisionID?
    public let createdAtUTC: String

    public init(
        captureSeriesID: CaptureSeriesID = CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID = CaptureRevisionID(),
        parentRevisionID: CaptureRevisionID? = nil,
        createdAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) {
        self.captureSeriesID = captureSeriesID
        self.captureRevisionID = captureRevisionID
        self.parentRevisionID = parentRevisionID
        self.createdAtUTC = createdAtUTC
    }
}

public struct CaptureWorkingSetSnapshot: Sendable, Equatable {
    public let identity: CaptureWorkingSetIdentity
    public let rootDirectory: URL
    public let captureSessionIDs: [CaptureSessionID]
    public let coordinateSpaceIDs: [CoordinateSpaceID]
    public let payloadDeclarations: [BundlePayloadDeclaration]
    public let rawRoomPlanDescriptor: RoomPlanRawEvidenceDescriptor?
    public let processedRoomPlanDescriptor: RoomPlanProcessedEvidenceDescriptor?
    public let meshAnchorCount: Int?
    public let evidenceFrameCount: Int
    public let depthEvidenceCount: Int

    public init(
        identity: CaptureWorkingSetIdentity,
        rootDirectory: URL,
        captureSessionIDs: [CaptureSessionID],
        coordinateSpaceIDs: [CoordinateSpaceID],
        payloadDeclarations: [BundlePayloadDeclaration],
        rawRoomPlanDescriptor: RoomPlanRawEvidenceDescriptor?,
        processedRoomPlanDescriptor: RoomPlanProcessedEvidenceDescriptor?,
        meshAnchorCount: Int?,
        evidenceFrameCount: Int,
        depthEvidenceCount: Int
    ) {
        self.identity = identity
        self.rootDirectory = rootDirectory
        self.captureSessionIDs = captureSessionIDs
        self.coordinateSpaceIDs = coordinateSpaceIDs
        self.payloadDeclarations = payloadDeclarations
        self.rawRoomPlanDescriptor = rawRoomPlanDescriptor
        self.processedRoomPlanDescriptor = processedRoomPlanDescriptor
        self.meshAnchorCount = meshAnchorCount
        self.evidenceFrameCount = evidenceFrameCount
        self.depthEvidenceCount = depthEvidenceCount
    }
}

public actor CaptureWorkingSetStore {
    public let identity: CaptureWorkingSetIdentity
    public let rootDirectory: URL

    private let writer: AtomicCaptureFileWriter
    private var captureSessionID: CaptureSessionID?
    private var coordinateSpaceID: CoordinateSpaceID?
    private var declarations: [String: BundlePayloadDeclaration] = [:]
    private var rawRoomPlanDescriptor: RoomPlanRawEvidenceDescriptor?
    private var processedRoomPlanDescriptor: RoomPlanProcessedEvidenceDescriptor?
    private var meshAnchorCount: Int?
    private var evidenceFrameCount = 0
    private var depthEvidenceCount = 0

    public init(
        identity: CaptureWorkingSetIdentity = CaptureWorkingSetIdentity(),
        rootDirectory: URL
    ) throws {
        self.identity = identity
        self.rootDirectory = rootDirectory
        self.writer = try AtomicCaptureFileWriter(
            rootDirectory: rootDirectory
        )
    }

    public func persistRawRoomPlan(
        _ payload: RoomPlanRawArtifactPayload
    ) async throws {
        let descriptor = payload.descriptor
        guard
            descriptor.relativePath
                == RoomPlanEvidenceArtifactBuilder.rawPath,
            descriptor.byteCount == payload.data.count,
            descriptor.sha256
                == EvidenceIntegrity.sha256(of: payload.data)
        else {
            throw CaptureWorkingSetError.invalidRawRoomPlanDescriptor
        }

        try bindAuthority(
            captureSessionID: descriptor.captureSessionID,
            coordinateSpaceID: descriptor.coordinateSpaceID
        )

        let path = try CaptureStorePath(descriptor.relativePath)
        try await writer.write(payload.data, to: path)

        let declaration = BundlePayloadDeclaration(
            path: descriptor.relativePath,
            mediaType: "application/json",
            producer: "roomplan_capture",
            provenanceClass: .appleRoomPlanRawScan,
            role: .canonical
        )
        try register(declaration)
        rawRoomPlanDescriptor = descriptor
    }

    public func persistProcessedRoomPlan(
        _ payload: RoomPlanProcessedArtifactPayload
    ) async throws {
        guard let raw = rawRoomPlanDescriptor else {
            throw CaptureWorkingSetError.processedRoomPlanRequiresRaw
        }

        let descriptor = payload.descriptor
        guard
            descriptor.relativePath
                == RoomPlanEvidenceArtifactBuilder.processedPath,
            descriptor.byteCount == payload.data.count,
            descriptor.sha256
                == EvidenceIntegrity.sha256(of: payload.data)
        else {
            throw CaptureWorkingSetError
                .invalidProcessedRoomPlanDescriptor
        }

        guard
            descriptor.sourceRawSHA256 == raw.sha256,
            descriptor.captureSessionID == raw.captureSessionID,
            descriptor.coordinateSpaceID == raw.coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .processedRoomPlanLineageMismatch
        }

        let path = try CaptureStorePath(descriptor.relativePath)
        try await writer.write(payload.data, to: path)

        let declaration = BundlePayloadDeclaration(
            path: descriptor.relativePath,
            mediaType: "application/json",
            producer: "roomplan_builder",
            provenanceClass: .appleRoomPlanInference,
            role: .canonical,
            sourceRefs: [
                "sha256:\(raw.sha256.description)"
            ]
        )
        try register(declaration)
        processedRoomPlanDescriptor = descriptor
    }

    public func persistMeshPackage(
        _ package: MeshEvidencePackage
    ) async throws {
        guard
            let decoded = try? JSONDecoder().decode(
                MeshAnchorEvidenceIndex.self,
                from: package.indexData
            ),
            decoded == package.index
        else {
            throw CaptureWorkingSetError.invalidMeshPackage
        }

        var filesByPath: [String: MeshEvidenceGeometryFile] = [:]
        for file in package.geometryFiles {
            guard
                filesByPath[file.path] == nil,
                file.sha256 == EvidenceIntegrity.sha256(of: file.data)
            else {
                throw CaptureWorkingSetError.invalidMeshPackage
            }
            filesByPath[file.path] = file
        }

        let recordPaths = Set(
            package.index.anchors.map(\.geometryPath)
        )
        guard recordPaths == Set(filesByPath.keys) else {
            throw CaptureWorkingSetError.invalidMeshPackage
        }

        for record in package.index.anchors {
            guard
                let file = filesByPath[record.geometryPath],
                record.geometrySHA256 == file.sha256
            else {
                throw CaptureWorkingSetError.invalidMeshPackage
            }
        }

        if let first = package.index.anchors.first {
            for record in package.index.anchors {
                guard
                    record.captureSessionID == first.captureSessionID,
                    record.coordinateSpaceID == first.coordinateSpaceID
                else {
                    throw CaptureWorkingSetError.invalidMeshPackage
                }
            }
            try bindAuthority(
                captureSessionID: first.captureSessionID,
                coordinateSpaceID: first.coordinateSpaceID
            )
        }

        try await package.persist(using: writer)

        for file in package.geometryFiles {
            try register(
                BundlePayloadDeclaration(
                    path: file.path,
                    mediaType: "application/vnd.htdt.meshbin",
                    producer: "mesh_capture",
                    provenanceClass: .arkitMeshReconstruction,
                    role: .canonical
                )
            )
        }

        let sourceRefs = package.geometryFiles
            .map { "path:\($0.path)" }
            .sorted()
        try register(
            BundlePayloadDeclaration(
                path: MeshEvidencePackage.indexPath,
                mediaType: "application/json",
                producer: "mesh_capture",
                provenanceClass: .arkitMeshReconstruction,
                role: .canonical,
                sourceRefs: sourceRefs.isEmpty ? nil : sourceRefs
            )
        )
        meshAnchorCount = package.index.anchors.count
    }

    public func persistFramePackage(
        _ package: FrameEvidencePackage
    ) async throws {
        try bindAuthority(
            captureSessionID: package.descriptor.captureSessionID,
            coordinateSpaceID: package.descriptor.coordinateSpaceID
        )

        try await package.persist(using: writer)
        for declaration in package.payloadDeclarations {
            try register(declaration)
        }

        evidenceFrameCount += 1
        depthEvidenceCount += package.capturedDepthCount
    }

    public func snapshot() -> CaptureWorkingSetSnapshot {
        CaptureWorkingSetSnapshot(
            identity: identity,
            rootDirectory: rootDirectory,
            captureSessionIDs: captureSessionID.map { [$0] } ?? [],
            coordinateSpaceIDs: coordinateSpaceID.map { [$0] } ?? [],
            payloadDeclarations: declarations.values.sorted {
                BundleLogicalPath.utf8Less($0.path, $1.path)
            },
            rawRoomPlanDescriptor: rawRoomPlanDescriptor,
            processedRoomPlanDescriptor: processedRoomPlanDescriptor,
            meshAnchorCount: meshAnchorCount,
            evidenceFrameCount: evidenceFrameCount,
            depthEvidenceCount: depthEvidenceCount
        )
    }

    private func bindAuthority(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID
    ) throws {
        if let existingSession = self.captureSessionID,
           existingSession != captureSessionID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        if let existingCoordinate = self.coordinateSpaceID,
           existingCoordinate != coordinateSpaceID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
    }

    private func register(
        _ declaration: BundlePayloadDeclaration
    ) throws {
        if declarations[declaration.path] != nil {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }
        declarations[declaration.path] = declaration
    }
}
