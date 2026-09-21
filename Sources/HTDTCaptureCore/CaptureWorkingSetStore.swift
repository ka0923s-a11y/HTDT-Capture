import Foundation

public enum CaptureWorkingSetError: Error, Sendable, Equatable {
    case invalidRawRoomPlanDescriptor
    case invalidProcessedRoomPlanDescriptor
    case processedRoomPlanRequiresRaw
    case processedRoomPlanLineageMismatch
    case invalidMeshPackage
    case invalidAnnotationPackage
    case invalidMeasurementPackage
    case invalidSessionFoundationPackage
    case invalidTimingPackage
    case timingFoundationMissing
    case authorityMismatch
    case qualityReportNotReady
    case qualityReportIntegrityMissing
    case integrityVerificationFailed
    case duplicatePayloadDeclaration(String)
    case mixedProvenanceCollection(String)
    case unsafeDiscardPath
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
    public let evidenceFrameRefs: [String]

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
        depthEvidenceCount: Int,
        evidenceFrameRefs: [String]
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
        self.evidenceFrameRefs = evidenceFrameRefs
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
    private var meshIndex: MeshAnchorEvidenceIndex?
    private var frameDescriptors: [FrameEvidenceDescriptor] = []
    private var framePreviews: [DerivedFramePreviewReference] = []
    private var annotationCollection: CaptureAnnotationCollection?
    private var measurementCollection: CaptureMeasurementCollection?
    private var annotationKeysPresent: Set<String> = []
    private var measurementQuantityTypesPresent: Set<String> = []
    private var sessionFoundation:
        CaptureSessionFoundationPackage?
    private var timingDocument: CaptureTimingDocument?
    private var evidenceFrameCount = 0
    private var depthEvidenceCount = 0
    private var trackingEvents: [TrackingQualityEvent] = []
    private var resourceEvents: [CaptureResourceEvent] = []

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

    public func persistSessionFoundation(
        _ package: CaptureSessionFoundationPackage
    ) async throws {
        guard
            package.session.configurationRef
                == CaptureSessionFoundationPackage.configurationPath,
            package.session.timingRef
                == CaptureTimingPackage.path,
            package.session.captureMode
                == package.configuration.captureMode
        else {
            throw CaptureWorkingSetError
                .invalidSessionFoundationPackage
        }

        try bindAuthority(
            captureSessionID: package.session.captureSessionID,
            coordinateSpaceID: package.session.coordinateSpaceID
        )

        try await package.persist(using: writer)
        for declaration in package.payloadDeclarations {
            try register(declaration)
        }
        sessionFoundation = package
    }

    public func persistTimingPackage(
        _ package: CaptureTimingPackage
    ) async throws {
        guard sessionFoundation != nil else {
            throw CaptureWorkingSetError.timingFoundationMissing
        }
        guard
            package.document.clockDomain
                == CaptureTimingPackage.clockDomain,
            package.document.correlations.count == 2,
            let decoded = try? JSONDecoder().decode(
                CaptureTimingDocument.self,
                from: package.data
            ),
            decoded == package.document
        else {
            throw CaptureWorkingSetError.invalidTimingPackage
        }

        if let existing = timingDocument {
            if existing == package.document {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    CaptureTimingPackage.path
                )
        }

        try await writer.writeIfIdentical(
            package.data,
            to: CaptureStorePath(CaptureTimingPackage.path)
        )

        if let existing = timingDocument {
            if existing == package.document {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    CaptureTimingPackage.path
                )
        }

        try register(package.payloadDeclaration)
        timingDocument = package.document
    }

    public func persistEndRoomPlanTransaction(
        timingPackage: CaptureTimingPackage,
        roomPlanLineage: RoomPlanArtifactLineage
    ) async throws {
        guard sessionFoundation != nil else {
            throw CaptureWorkingSetError.timingFoundationMissing
        }
        guard
            timingPackage.document.clockDomain
                == CaptureTimingPackage.clockDomain,
            timingPackage.document.correlations.count == 2,
            let decodedTiming = try? JSONDecoder().decode(
                CaptureTimingDocument.self,
                from: timingPackage.data
            ),
            decodedTiming == timingPackage.document
        else {
            throw CaptureWorkingSetError.invalidTimingPackage
        }

        let raw = roomPlanLineage.raw
        guard let processed = roomPlanLineage.processed else {
            throw CaptureWorkingSetError
                .invalidProcessedRoomPlanDescriptor
        }

        guard
            raw.descriptor.relativePath
                == RoomPlanEvidenceArtifactBuilder.rawPath,
            raw.descriptor.byteCount == raw.data.count,
            raw.descriptor.sha256
                == EvidenceIntegrity.sha256(of: raw.data)
        else {
            throw CaptureWorkingSetError
                .invalidRawRoomPlanDescriptor
        }

        guard
            processed.descriptor.relativePath
                == RoomPlanEvidenceArtifactBuilder.processedPath,
            processed.descriptor.byteCount == processed.data.count,
            processed.descriptor.sha256
                == EvidenceIntegrity.sha256(of: processed.data),
            processed.descriptor.sourceRawSHA256
                == raw.descriptor.sha256,
            processed.descriptor.captureSessionID
                == raw.descriptor.captureSessionID,
            processed.descriptor.coordinateSpaceID
                == raw.descriptor.coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .invalidProcessedRoomPlanDescriptor
        }

        try bindAuthority(
            captureSessionID: raw.descriptor.captureSessionID,
            coordinateSpaceID: raw.descriptor.coordinateSpaceID
        )

        if let timingDocument,
           let rawRoomPlanDescriptor,
           let processedRoomPlanDescriptor
        {
            if timingDocument == timingPackage.document,
               rawRoomPlanDescriptor == raw.descriptor,
               processedRoomPlanDescriptor == processed.descriptor
            {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    CaptureTimingPackage.path
                )
        }

        guard timingDocument == nil,
              rawRoomPlanDescriptor == nil,
              processedRoomPlanDescriptor == nil
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        let rawDeclaration = BundlePayloadDeclaration(
            path: raw.descriptor.relativePath,
            mediaType: "application/json",
            producer: "roomplan_capture",
            provenanceClass: .appleRoomPlanRawScan,
            role: .canonical
        )
        let processedDeclaration = BundlePayloadDeclaration(
            path: processed.descriptor.relativePath,
            mediaType: "application/json",
            producer: "roomplan_builder",
            provenanceClass: .appleRoomPlanInference,
            role: .canonical,
            sourceRefs: [
                "sha256:\(raw.descriptor.sha256.description)"
            ]
        )
        let transactionDeclarations = [
            timingPackage.payloadDeclaration,
            rawDeclaration,
            processedDeclaration,
        ]

        for declaration in transactionDeclarations {
            guard declarations[declaration.path] == nil else {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        let writes: [CaptureFileWriteRequest] = try [
            CaptureFileWriteRequest(
                data: timingPackage.data,
                path: CaptureStorePath(
                    CaptureTimingPackage.path
                )
            ),
            CaptureFileWriteRequest(
                data: raw.data,
                path: CaptureStorePath(
                    raw.descriptor.relativePath
                )
            ),
            CaptureFileWriteRequest(
                data: processed.data,
                path: CaptureStorePath(
                    processed.descriptor.relativePath
                )
            ),
        ]

        try await writer.writeBatchIfIdentical(writes)

        // The store actor may re-enter while awaiting the writer actor.
        // Another exact transaction can commit first; accept only that exact
        // replay. Any different logical authority remains fail-closed.
        if let existingTiming = timingDocument,
           let existingRaw = rawRoomPlanDescriptor,
           let existingProcessed = processedRoomPlanDescriptor
        {
            if existingTiming == timingPackage.document,
               existingRaw == raw.descriptor,
               existingProcessed == processed.descriptor
            {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    CaptureTimingPackage.path
                )
        }

        guard timingDocument == nil,
              rawRoomPlanDescriptor == nil,
              processedRoomPlanDescriptor == nil,
              transactionDeclarations.allSatisfy({
                  declarations[$0.path] == nil
              })
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        // There are no suspension points after this line. Commit the logical
        // authority atomically after every required file is durable.
        for declaration in transactionDeclarations {
            declarations[declaration.path] = declaration
        }
        timingDocument = timingPackage.document
        rawRoomPlanDescriptor = raw.descriptor
        processedRoomPlanDescriptor = processed.descriptor
    }

    public func rollbackAcceptedEndTransaction(
        removeOwnedMesh: Bool
    ) async throws {
        guard sessionFoundation != nil,
              let expectedTiming = timingDocument,
              let expectedRaw = rawRoomPlanDescriptor,
              let expectedProcessed = processedRoomPlanDescriptor,
              expectedProcessed.sourceRawSHA256
                == expectedRaw.sha256,
              expectedProcessed.captureSessionID
                == expectedRaw.captureSessionID,
              expectedProcessed.coordinateSpaceID
                == expectedRaw.coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        func payloadURL(_ path: String) throws -> URL {
            try BundleLogicalPath.validate(path)
            return path
                .split(separator: "/")
                .reduce(rootDirectory) {
                    url,
                    component in
                    url.appendingPathComponent(
                        String(component),
                        isDirectory: false
                    )
                }
        }

        let timingData = try Data(
            contentsOf: payloadURL(
                CaptureTimingPackage.path
            )
        )
        guard
            let decodedTiming = try? JSONDecoder().decode(
                CaptureTimingDocument.self,
                from: timingData
            ),
            decodedTiming == expectedTiming
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        let rawData = try Data(
            contentsOf: payloadURL(expectedRaw.relativePath)
        )
        guard
            rawData.count == expectedRaw.byteCount,
            EvidenceIntegrity.sha256(of: rawData)
                == expectedRaw.sha256
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        let processedData = try Data(
            contentsOf: payloadURL(
                expectedProcessed.relativePath
            )
        )
        guard
            processedData.count
                == expectedProcessed.byteCount,
            EvidenceIntegrity.sha256(of: processedData)
                == expectedProcessed.sha256
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        let timingDeclaration =
            BundlePayloadDeclaration(
                path: CaptureTimingPackage.path,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical
            )
        let rawDeclaration =
            BundlePayloadDeclaration(
                path: expectedRaw.relativePath,
                mediaType: "application/json",
                producer: "roomplan_capture",
                provenanceClass: .appleRoomPlanRawScan,
                role: .canonical
            )
        let processedDeclaration =
            BundlePayloadDeclaration(
                path: expectedProcessed.relativePath,
                mediaType: "application/json",
                producer: "roomplan_builder",
                provenanceClass: .appleRoomPlanInference,
                role: .canonical,
                sourceRefs: [
                    "sha256:"
                        + expectedRaw.sha256.description
                ]
            )

        var declarationsToRemove = [
            timingDeclaration,
            rawDeclaration,
            processedDeclaration,
        ]
        var removals: [CaptureFileWriteRequest] = try [
            CaptureFileWriteRequest(
                data: timingData,
                path: CaptureStorePath(
                    CaptureTimingPackage.path
                )
            ),
            CaptureFileWriteRequest(
                data: rawData,
                path: CaptureStorePath(
                    expectedRaw.relativePath
                )
            ),
            CaptureFileWriteRequest(
                data: processedData,
                path: CaptureStorePath(
                    expectedProcessed.relativePath
                )
            ),
        ]

        let expectedMesh = removeOwnedMesh
            ? meshIndex
            : nil
        if removeOwnedMesh,
           let expectedMesh
        {
            let indexData = try Data(
                contentsOf: payloadURL(
                    MeshEvidencePackage.indexPath
                )
            )
            guard
                let decodedIndex =
                    try? JSONDecoder().decode(
                        MeshAnchorEvidenceIndex.self,
                        from: indexData
                    ),
                decodedIndex == expectedMesh
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }

            var geometryRefs: [String] = []
            for record in expectedMesh.anchors {
                let data = try Data(
                    contentsOf: payloadURL(
                        record.geometryPath
                    )
                )
                guard
                    EvidenceIntegrity.sha256(of: data)
                        == record.geometrySHA256
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
                removals.append(
                    try CaptureFileWriteRequest(
                        data: data,
                        path: CaptureStorePath(
                            record.geometryPath
                        )
                    )
                )
                declarationsToRemove.append(
                    BundlePayloadDeclaration(
                        path: record.geometryPath,
                        mediaType:
                            "application/vnd.htdt.meshbin",
                        producer: "mesh_capture",
                        provenanceClass:
                            .arkitMeshReconstruction,
                        role: .canonical
                    )
                )
                geometryRefs.append(
                    "path:" + record.geometryPath
                )
            }

            removals.append(
                try CaptureFileWriteRequest(
                    data: indexData,
                    path: CaptureStorePath(
                        MeshEvidencePackage.indexPath
                    )
                )
            )
            declarationsToRemove.append(
                BundlePayloadDeclaration(
                    path: MeshEvidencePackage.indexPath,
                    mediaType: "application/json",
                    producer: "mesh_capture",
                    provenanceClass:
                        .arkitMeshReconstruction,
                    role: .canonical,
                    sourceRefs:
                        geometryRefs.isEmpty
                        ? nil
                        : geometryRefs.sorted()
                )
            )
        } else if removeOwnedMesh {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        for declaration in declarationsToRemove {
            guard declarations[declaration.path]
                    == declaration
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
        }

        try await writer.removeBatchIfIdentical(removals)

        // Re-check logical authority after the writer-actor suspension. The
        // owned files are now absent from the bundle root, so any in-memory
        // mutation across this await is unsafe and must fail closed.
        guard timingDocument == expectedTiming,
              rawRoomPlanDescriptor == expectedRaw,
              processedRoomPlanDescriptor
                == expectedProcessed,
              (
                !removeOwnedMesh
                || meshIndex == expectedMesh
              ),
              declarationsToRemove.allSatisfy({
                  declarations[$0.path] == $0
              })
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        for declaration in declarationsToRemove {
            declarations.removeValue(
                forKey: declaration.path
            )
        }
        timingDocument = nil
        rawRoomPlanDescriptor = nil
        processedRoomPlanDescriptor = nil

        if removeOwnedMesh {
            meshIndex = nil
            meshAnchorCount = nil
        }
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

        // RoomCaptureView can deliver the same completion payload more than
        // once around stop()/review transition. Validate the replay bytes
        // first, then treat an exact descriptor replay as harmless.
        if let existing = rawRoomPlanDescriptor {
            if existing == descriptor {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.rawPath
            )
        }

        try bindAuthority(
            captureSessionID: descriptor.captureSessionID,
            coordinateSpaceID: descriptor.coordinateSpaceID
        )

        let path = try CaptureStorePath(descriptor.relativePath)
        try await writer.writeIfIdentical(
            payload.data,
            to: path
        )

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

        guard let raw = rawRoomPlanDescriptor else {
            throw CaptureWorkingSetError.processedRoomPlanRequiresRaw
        }

        guard
            descriptor.sourceRawSHA256 == raw.sha256,
            descriptor.captureSessionID == raw.captureSessionID,
            descriptor.coordinateSpaceID == raw.coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .processedRoomPlanLineageMismatch
        }

        // Match raw RoomPlan replay semantics after validating bytes and
        // lineage. Exact duplicate completion is idempotent; a conflicting
        // canonical payload is rejected.
        if let existing = processedRoomPlanDescriptor {
            if existing == descriptor {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.processedPath
            )
        }

        let path = try CaptureStorePath(descriptor.relativePath)
        try await writer.writeIfIdentical(
            payload.data,
            to: path
        )

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

        if let existing = meshIndex {
            if existing == package.index {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeshEvidencePackage.indexPath
                )
        }

        let meshPaths =
            package.geometryFiles.map(\.path)
            + [MeshEvidencePackage.indexPath]
        if let duplicate = meshPaths.first(where: {
            declarations[$0] != nil
        }) {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(duplicate)
        }

        // MeshEvidencePackage uses one writer-actor batch. A failed batch
        // rolls back only files created by that batch and never deletes a
        // pre-existing conflicting path.
        try await package.persist(using: writer)

        // Re-check after actor suspension. An exact concurrent replay is
        // harmless; any different committed authority is rejected.
        if let existing = meshIndex {
            if existing == package.index {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeshEvidencePackage.indexPath
                )
        }
        if let duplicate = meshPaths.first(where: {
            declarations[$0] != nil
        }) {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(duplicate)
        }

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
        meshIndex = package.index
    }

    public func rollbackCurrentMeshPackage() async throws {
        guard let expectedMesh = meshIndex else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        func payloadURL(_ path: String) throws -> URL {
            try BundleLogicalPath.validate(path)
            return path
                .split(separator: "/")
                .reduce(rootDirectory) {
                    url,
                    component in
                    url.appendingPathComponent(
                        String(component),
                        isDirectory: false
                    )
                }
        }

        let indexData = try Data(
            contentsOf: payloadURL(
                MeshEvidencePackage.indexPath
            )
        )
        guard
            let decodedIndex = try? JSONDecoder().decode(
                MeshAnchorEvidenceIndex.self,
                from: indexData
            ),
            decodedIndex == expectedMesh
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        var removals: [CaptureFileWriteRequest] = []
        var expectedDeclarations:
            [BundlePayloadDeclaration] = []
        var geometryRefs: [String] = []

        for record in expectedMesh.anchors {
            let data = try Data(
                contentsOf: payloadURL(
                    record.geometryPath
                )
            )
            guard
                EvidenceIntegrity.sha256(of: data)
                    == record.geometrySHA256
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }

            removals.append(
                try CaptureFileWriteRequest(
                    data: data,
                    path: CaptureStorePath(
                        record.geometryPath
                    )
                )
            )
            expectedDeclarations.append(
                BundlePayloadDeclaration(
                    path: record.geometryPath,
                    mediaType:
                        "application/vnd.htdt.meshbin",
                    producer: "mesh_capture",
                    provenanceClass:
                        .arkitMeshReconstruction,
                    role: .canonical
                )
            )
            geometryRefs.append(
                "path:" + record.geometryPath
            )
        }

        removals.append(
            try CaptureFileWriteRequest(
                data: indexData,
                path: CaptureStorePath(
                    MeshEvidencePackage.indexPath
                )
            )
        )
        expectedDeclarations.append(
            BundlePayloadDeclaration(
                path: MeshEvidencePackage.indexPath,
                mediaType: "application/json",
                producer: "mesh_capture",
                provenanceClass:
                    .arkitMeshReconstruction,
                role: .canonical,
                sourceRefs:
                    geometryRefs.isEmpty
                    ? nil
                    : geometryRefs.sorted()
            )
        )

        for declaration in expectedDeclarations {
            guard declarations[declaration.path]
                    == declaration
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
        }

        try await writer.removeBatchIfIdentical(removals)

        guard meshIndex == expectedMesh,
              expectedDeclarations.allSatisfy({
                  declarations[$0.path] == $0
              })
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        for declaration in expectedDeclarations {
            declarations.removeValue(
                forKey: declaration.path
            )
        }
        meshIndex = nil
        meshAnchorCount = nil
    }

    public func persistFramePackage(
        _ package: FrameEvidencePackage
    ) async throws {
        try bindAuthority(
            captureSessionID: package.descriptor.captureSessionID,
            coordinateSpaceID: package.descriptor.coordinateSpaceID
        )

        if let existing = frameDescriptors.first(where: {
            $0.frameID == package.descriptor.frameID
        }) {
            if existing == package.descriptor {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(package.descriptorPath)
        }

        try await package.persistCanonical(using: writer)

        // The actor can re-enter while the file-writer actor is awaited.
        // If another identical call committed this frame first, do not double
        // count it. Conflicting bytes were already rejected by the writer.
        if let existing = frameDescriptors.first(where: {
            $0.frameID == package.descriptor.frameID
        }) {
            if existing == package.descriptor {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(package.descriptorPath)
        }

        for declaration in package.canonicalPayloadDeclarations {
            try register(declaration)
        }

        frameDescriptors.append(package.descriptor)
        evidenceFrameCount += 1
        depthEvidenceCount += package.capturedDepthCount

        if let preview = package.preview {
            do {
                try await package.persistPreview(using: writer)
                if let declaration =
                    package.previewPayloadDeclaration
                {
                    try register(declaration)
                }
                if !framePreviews.contains(preview) {
                    framePreviews.append(preview)
                }
            } catch {
                // Preview HEIC is derived convenience evidence. Never destroy
                // an otherwise complete canonical pixel/depth frame because a
                // preview-only write failed. Remove a conflicting/stale
                // preview path so bundle integrity does not see an undeclared
                // derived file.
                // This path is exclusively a derived convenience
                // artifact for this exact frame ID. It is never canonical
                // authority and is not registered unless the preview write
                // succeeds. Removing a stale/conflicting derived preview is
                // therefore safe and restores working-set integrity without
                // mutating the committed canonical frame/depth evidence.
                if let previewPath = try? CaptureStorePath(preview.path) {
                    try? await writer.removeIfPresent(previewPath)
                }
                resourceEvents.append(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Derived frame preview could not be persisted; canonical frame/depth evidence remains valid."
                    )
                )
            }
        }
    }

    public func discardUncommittedFramePackage(
        _ package: FrameEvidencePackage
    ) async throws {
        if let existing = frameDescriptors.first(where: {
            $0.frameID == package.descriptor.frameID
        }) {
            if existing == package.descriptor {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(package.descriptorPath)
        }

        let canonicalPaths = Set(
            package.canonicalPayloadDeclarations.map(\.path)
        )
        guard !declarations.keys.contains(where: {
            canonicalPaths.contains($0)
        }) else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        var payloads: [(Data, String)] = [
            (package.descriptorData, package.descriptorPath),
            (
                package.pixelPayload,
                package.descriptor.pixelRelativePath
            ),
        ]

        if let depth = package.descriptor.depth,
           let depthPayload = package.depthPayload
        {
            payloads.append(
                (depthPayload, depth.depthRelativePath)
            )
        }

        if let confidencePath =
            package.descriptor.depth?.confidenceRelativePath,
           let confidencePayload = package.confidencePayload
        {
            payloads.append(
                (confidencePayload, confidencePath)
            )
        }

        for (data, path) in payloads {
            let removedOrAbsent =
                try await writer.removeIfIdentical(
                    data,
                    at: CaptureStorePath(path)
                )
            guard removedOrAbsent else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
        }
    }

    public func persistAnnotationAndMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage
    ) async throws {
        guard
            let decodedAnnotations = try? JSONDecoder().decode(
                CaptureAnnotationCollection.self,
                from: annotationPackage.data
            ),
            decodedAnnotations == annotationPackage.collection
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }
        guard
            let decodedMeasurements = try? JSONDecoder().decode(
                CaptureMeasurementCollection.self,
                from: measurementPackage.data
            ),
            decodedMeasurements == measurementPackage.collection
        else {
            throw CaptureWorkingSetError.invalidMeasurementPackage
        }

        let annotationSpaces = Set(
            annotationPackage.collection.entities.map(
                \.coordinateSpaceID
            )
        )
        let measurementSpaces = Set(
            measurementPackage.collection.measurements.compactMap(
                \.coordinateSpaceID
            )
        )
        guard annotationSpaces.count <= 1,
              measurementSpaces.count <= 1,
              annotationSpaces.union(measurementSpaces).count <= 1
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        if let space =
            annotationSpaces.union(measurementSpaces).first
        {
            try bindCoordinateAuthority(space)
        }

        if let existing = annotationCollection,
           existing != annotationPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
        }
        if let existing = measurementCollection,
           existing != measurementPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeasurementEvidencePackage.path
                )
        }

        // Container provenance is derived from the records it carries:
        // every record must share one provenance class so the manifest
        // declaration cannot contradict record-level authority.
        let annotationDeclaration =
            BundlePayloadDeclaration(
                path: AnnotationEvidencePackage.path,
                mediaType: "application/json",
                producer: "annotation",
                provenanceClass:
                    try annotationCollectionProvenance(
                        annotationPackage.collection
                    ),
                role: .canonical
            )
        let measurementDeclaration =
            BundlePayloadDeclaration(
                path: MeasurementEvidencePackage.path,
                mediaType: "application/json",
                producer: "measurement",
                provenanceClass:
                    try measurementCollectionProvenance(
                        measurementPackage.collection
                    ),
                role: .canonical
            )
        let expectedDeclarations = [
            annotationDeclaration,
            measurementDeclaration,
        ]
        for declaration in expectedDeclarations {
            if let existing = declarations[declaration.path],
               existing != declaration
            {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        try await writer.writeBatchIfIdentical([
            try CaptureFileWriteRequest(
                data: annotationPackage.data,
                path: CaptureStorePath(
                    AnnotationEvidencePackage.path
                )
            ),
            try CaptureFileWriteRequest(
                data: measurementPackage.data,
                path: CaptureStorePath(
                    MeasurementEvidencePackage.path
                )
            ),
        ])

        // Re-check after actor suspension. This also repairs a compatible
        // legacy partial commit without accepting conflicting authority.
        if let existing = annotationCollection,
           existing != annotationPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
        }
        if let existing = measurementCollection,
           existing != measurementPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeasurementEvidencePackage.path
                )
        }
        for declaration in expectedDeclarations {
            if let existing = declarations[declaration.path],
               existing != declaration
            {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        declarations[annotationDeclaration.path] =
            annotationDeclaration
        declarations[measurementDeclaration.path] =
            measurementDeclaration
        annotationCollection = annotationPackage.collection
        annotationKeysPresent = Set(
            annotationPackage.collection.entities.map(
                annotationQualityKey
            )
        )
        measurementCollection =
            measurementPackage.collection
        measurementQuantityTypesPresent = Set(
            measurementPackage.collection.measurements.map(
                \.quantityType
            )
        )
    }

    public func persistAnnotationPackage(
        _ package: AnnotationEvidencePackage
    ) async throws {
        guard
            let decoded = try? JSONDecoder().decode(
                CaptureAnnotationCollection.self,
                from: package.data
            ),
            decoded == package.collection
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }

        let spaces = Set(
            package.collection.entities.map(\.coordinateSpaceID)
        )
        guard spaces.count <= 1 else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }
        if let space = spaces.first {
            try bindCoordinateAuthority(space)
        }

        let provenance = try annotationCollectionProvenance(
            package.collection
        )
        try await writer.writeIfIdentical(
            package.data,
            to: CaptureStorePath(AnnotationEvidencePackage.path)
        )
        try register(
            BundlePayloadDeclaration(
                path: AnnotationEvidencePackage.path,
                mediaType: "application/json",
                producer: "annotation",
                provenanceClass: provenance,
                role: .canonical
            )
        )

        annotationCollection = package.collection
        annotationKeysPresent = Set(
            package.collection.entities.map(annotationQualityKey)
        )
    }

    public func persistMeasurementPackage(
        _ package: MeasurementEvidencePackage
    ) async throws {
        guard
            let decoded = try? JSONDecoder().decode(
                CaptureMeasurementCollection.self,
                from: package.data
            ),
            decoded == package.collection
        else {
            throw CaptureWorkingSetError.invalidMeasurementPackage
        }

        let spaces = Set(
            package.collection.measurements.compactMap(
                \.coordinateSpaceID
            )
        )
        guard spaces.count <= 1 else {
            throw CaptureWorkingSetError.invalidMeasurementPackage
        }
        if let space = spaces.first {
            try bindCoordinateAuthority(space)
        }

        let provenance = try measurementCollectionProvenance(
            package.collection
        )
        try await writer.writeIfIdentical(
            package.data,
            to: CaptureStorePath(MeasurementEvidencePackage.path)
        )
        try register(
            BundlePayloadDeclaration(
                path: MeasurementEvidencePackage.path,
                mediaType: "application/json",
                producer: "measurement",
                provenanceClass: provenance,
                role: .canonical
            )
        )

        measurementCollection = package.collection
        measurementQuantityTypesPresent = Set(
            package.collection.measurements.map(\.quantityType)
        )
    }

    public func recordTrackingEvent(
        _ event: TrackingQualityEvent
    ) {
        trackingEvents.append(event)
        trackingEvents.sort {
            $0.sessionTimestampSeconds < $1.sessionTimestampSeconds
        }
    }

    public func recordResourceEvent(
        _ event: CaptureResourceEvent
    ) {
        resourceEvents.append(event)
    }

    public func evaluateQuality(
        requirements: CaptureQualityRequirements = .init()
    ) -> CaptureQualityReport {
        let integrityStatus: BundleIntegrityStatus
        do {
            try verifyIntegrity()
            integrityStatus = .pass
        } catch {
            integrityStatus = .fail
        }

        let roomPlanStatus: RoomPlanQualityStatus
        if processedRoomPlanDescriptor != nil {
            roomPlanStatus = .completed
        } else if rawRoomPlanDescriptor != nil
                    || meshAnchorCount != nil
                    || evidenceFrameCount > 0
        {
            roomPlanStatus = .running
        } else {
            roomPlanStatus = .notStarted
        }

        return CaptureQualityEvaluator.evaluate(
            CaptureQualityObservation(
                trackingEvents: trackingEvents,
                roomPlanStatus: roomPlanStatus,
                activeMeshAnchorCount: meshAnchorCount ?? 0,
                evidenceFrameCount: evidenceFrameCount,
                depthEvidenceCount: depthEvidenceCount,
                annotationKeysPresent: annotationKeysPresent,
                measurementQuantityTypesPresent:
                    measurementQuantityTypesPresent,
                resourceEvents: resourceEvents,
                integrityStatus: integrityStatus
            ),
            requirements: requirements
        )
    }

    public func persistQualityReport(
        _ report: CaptureQualityReport
    ) async throws {
        guard report.readyForHTDTIngestion else {
            throw CaptureWorkingSetError.qualityReportNotReady
        }
        guard report.integrityStatus == .pass else {
            throw CaptureWorkingSetError
                .qualityReportIntegrityMissing
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let path = "quality/capture-quality.json"

        try await writer.writeIfIdentical(
            data,
            to: CaptureStorePath(path)
        )
        try register(
            BundlePayloadDeclaration(
                path: path,
                mediaType: "application/json",
                producer: "capture_quality",
                provenanceClass: .captureAppDerived,
                role: .canonical
            )
        )
    }

    public func discardUncommittedQualityReport(
        _ report: CaptureQualityReport
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let path = "quality/capture-quality.json"
        let declaration = BundlePayloadDeclaration(
            path: path,
            mediaType: "application/json",
            producer: "capture_quality",
            provenanceClass: .captureAppDerived,
            role: .canonical
        )

        if let existing = declarations[path],
           existing != declaration
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(path)
        }

        let removedOrAbsent =
            try await writer.removeIfIdentical(
                data,
                at: CaptureStorePath(path)
            )
        guard removedOrAbsent else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        if declarations[path] == declaration {
            declarations.removeValue(forKey: path)
        }
    }

    public func discardIncompleteRevision() throws {
        let resolvedRoot = rootDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let workingDirectory =
            resolvedRoot.deletingLastPathComponent()
        let captureDirectory =
            workingDirectory.deletingLastPathComponent()

        guard
            resolvedRoot.lastPathComponent
                == identity.captureRevisionID.description,
            workingDirectory.lastPathComponent == "working",
            captureDirectory.lastPathComponent == "HTDTCapture"
        else {
            throw CaptureWorkingSetError.unsafeDiscardPath
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolvedRoot.path) else {
            return
        }
        try fileManager.removeItem(at: resolvedRoot)
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
            depthEvidenceCount: depthEvidenceCount,
            evidenceFrameRefs: frameDescriptors
                .map {
                    "path:evidence/frames/"
                        + $0.frameID.description
                        + ".json"
                }
                .sorted()
        )
    }

    private func verifyIntegrity() throws {
        let manifestURL = rootDirectory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard !FileManager.default.fileExists(
            atPath: manifestURL.path
        ) else {
            throw CaptureWorkingSetError.integrityVerificationFailed
        }

        let scanned = try BundleDirectoryScanner.scan(
            root: rootDirectory
        )
        let actualByPath = Dictionary(
            uniqueKeysWithValues: scanned.map {
                ($0.path, $0)
            }
        )
        guard Set(actualByPath.keys) == Set(declarations.keys) else {
            throw CaptureWorkingSetError.integrityVerificationFailed
        }

        for file in scanned {
            _ = try BundleFileHasher.sha256(url: file.url)
        }

        if let sessionFoundation {
            guard let timingDocument else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }

            try verifyTypedJSON(
                path: CaptureSessionFoundationPackage.sessionPath,
                expected: sessionFoundation.session,
                actualByPath: actualByPath
            )
            try verifyTypedJSON(
                path:
                    CaptureSessionFoundationPackage.capabilitiesPath,
                expected: sessionFoundation.capabilities,
                actualByPath: actualByPath
            )
            try verifyTypedJSON(
                path:
                    CaptureSessionFoundationPackage.configurationPath,
                expected: sessionFoundation.configuration,
                actualByPath: actualByPath
            )
            try verifyTypedJSON(
                path:
                    CaptureSessionFoundationPackage.devicePath,
                expected: sessionFoundation.device,
                actualByPath: actualByPath
            )
            try verifyTypedJSON(
                path: CaptureTimingPackage.path,
                expected: timingDocument,
                actualByPath: actualByPath
            )
        }

        if let rawRoomPlanDescriptor {
            try verifyFile(
                path: rawRoomPlanDescriptor.relativePath,
                byteCount: rawRoomPlanDescriptor.byteCount,
                sha256: rawRoomPlanDescriptor.sha256,
                actualByPath: actualByPath
            )
        }

        if let processedRoomPlanDescriptor {
            guard let rawRoomPlanDescriptor,
                  processedRoomPlanDescriptor.sourceRawSHA256
                    == rawRoomPlanDescriptor.sha256
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyFile(
                path: processedRoomPlanDescriptor.relativePath,
                byteCount: processedRoomPlanDescriptor.byteCount,
                sha256: processedRoomPlanDescriptor.sha256,
                actualByPath: actualByPath
            )
        }

        if let meshIndex {
            guard let indexFile =
                actualByPath[MeshEvidencePackage.indexPath],
                  let indexData = try? Data(
                    contentsOf: indexFile.url
                  ),
                  let decoded = try? JSONDecoder().decode(
                    MeshAnchorEvidenceIndex.self,
                    from: indexData
                  ),
                  decoded == meshIndex
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }

            for record in meshIndex.anchors {
                guard let file = actualByPath[record.geometryPath],
                      try BundleFileHasher.sha256(url: file.url)
                        == record.geometrySHA256
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
            }
        }

        if let annotationCollection {
            guard let file =
                    actualByPath[AnnotationEvidencePackage.path],
                  let data = try? Data(contentsOf: file.url),
                  let decoded = try? JSONDecoder().decode(
                    CaptureAnnotationCollection.self,
                    from: data
                  ),
                  decoded == annotationCollection
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
        }

        if let measurementCollection {
            guard let file =
                    actualByPath[MeasurementEvidencePackage.path],
                  let data = try? Data(contentsOf: file.url),
                  let decoded = try? JSONDecoder().decode(
                    CaptureMeasurementCollection.self,
                    from: data
                  ),
                  decoded == measurementCollection
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
        }

        for preview in framePreviews {
            try verifyFile(
                path: preview.path,
                byteCount: preview.byteCount,
                sha256: preview.sha256,
                actualByPath: actualByPath
            )
        }

        for descriptor in frameDescriptors {
            let descriptorPath =
                "evidence/frames/\(descriptor.frameID).json"
            guard let descriptorFile = actualByPath[descriptorPath],
                  let descriptorData = try? Data(
                    contentsOf: descriptorFile.url
                  ),
                  let decoded = try? JSONDecoder().decode(
                    FrameEvidenceDescriptor.self,
                    from: descriptorData
                  ),
                  decoded == descriptor
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }

            try verifyFile(
                path: descriptor.pixelRelativePath,
                byteCount: descriptor.pixelByteCount,
                sha256: descriptor.pixelSHA256,
                actualByPath: actualByPath
            )

            if let depth = descriptor.depth {
                try verifyFile(
                    path: depth.depthRelativePath,
                    byteCount: depth.depthByteCount,
                    sha256: depth.depthSHA256,
                    actualByPath: actualByPath
                )

                if let confidencePath = depth.confidenceRelativePath,
                   let confidenceByteCount =
                        depth.confidenceByteCount,
                   let confidenceSHA256 = depth.confidenceSHA256
                {
                    try verifyFile(
                        path: confidencePath,
                        byteCount: confidenceByteCount,
                        sha256: confidenceSHA256,
                        actualByPath: actualByPath
                    )
                }
            }
        }
    }

    private func verifyTypedJSON<T>(
        path: String,
        expected: T,
        actualByPath: [String: ScannedBundleFile]
    ) throws where T: Codable & Equatable {
        guard let file = actualByPath[path],
              let data = try? Data(contentsOf: file.url),
              let decoded = try? JSONDecoder().decode(
                T.self,
                from: data
              ),
              decoded == expected
        else {
            throw CaptureWorkingSetError.integrityVerificationFailed
        }
    }

    private func verifyFile(
        path: String,
        byteCount: Int,
        sha256: EvidenceSHA256,
        actualByPath: [String: ScannedBundleFile]
    ) throws {
        guard let file = actualByPath[path],
              Int64(byteCount) == file.bytes,
              try BundleFileHasher.sha256(url: file.url) == sha256
        else {
            throw CaptureWorkingSetError.integrityVerificationFailed
        }
    }

    // Manifest declarations describe the whole collection file, so a
    // collection is accepted only when every record shares one provenance
    // class (issue #186, homogeneous-collection policy). A mixed-provenance
    // payload is rejected rather than mislabeled; an empty collection claims
    // only app-derived container authority.
    private func annotationCollectionProvenance(
        _ collection: CaptureAnnotationCollection
    ) throws -> BundleProvenanceClass {
        var provenance: AnnotationProvenanceClass?
        for entity in collection.entities {
            if let provenance,
               provenance != entity.provenanceClass
            {
                throw CaptureWorkingSetError
                    .mixedProvenanceCollection(
                        AnnotationEvidencePackage.path
                    )
            }
            provenance = entity.provenanceClass
        }
        switch provenance {
        case .userAnnotation:
            return .userAnnotation
        case .importedReference:
            return .importedReference
        case .captureAppDerived:
            return .captureAppDerived
        case nil:
            return .captureAppDerived
        }
    }

    private func measurementCollectionProvenance(
        _ collection: CaptureMeasurementCollection
    ) throws -> BundleProvenanceClass {
        var provenance: MeasurementProvenanceClass?
        for measurement in collection.measurements {
            if let provenance,
               provenance != measurement.provenanceClass
            {
                throw CaptureWorkingSetError
                    .mixedProvenanceCollection(
                        MeasurementEvidencePackage.path
                    )
            }
            provenance = measurement.provenanceClass
        }
        switch provenance {
        case .userAttestedMeasurement:
            return .userAttestedMeasurement
        case .appleRoomPlanInference:
            return .appleRoomPlanInference
        case .arkitMeshReconstruction:
            return .arkitMeshReconstruction
        case .importedReference:
            return .importedReference
        case nil:
            return .captureAppDerived
        }
    }

    private func annotationQualityKey(
        _ entity: CaptureAnnotationEntity
    ) -> String {
        if entity.type == .speaker,
           let role = entity.channelRole
        {
            return "speaker:\(role.rawValue)"
        }
        return entity.type.rawValue + ":" + entity.label
    }

    private func bindCoordinateAuthority(
        _ coordinateSpaceID: CoordinateSpaceID
    ) throws {
        if let existing = self.coordinateSpaceID,
           existing != coordinateSpaceID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        self.coordinateSpaceID = coordinateSpaceID
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
        if let existing = declarations[declaration.path] {
            if existing == declaration {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }
        declarations[declaration.path] = declaration
    }
}
