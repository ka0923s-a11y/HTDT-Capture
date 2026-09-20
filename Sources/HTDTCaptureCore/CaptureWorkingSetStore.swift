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

        try await writer.write(
            package.data,
            to: CaptureStorePath(CaptureTimingPackage.path)
        )
        try register(package.payloadDeclaration)
        timingDocument = package.document
    }

    public func persistEndRoomPlanTransaction(
        timingPackage: CaptureTimingPackage,
        roomPlanLineage: RoomPlanArtifactLineage
    ) async throws {
        guard let processed = roomPlanLineage.processed else {
            throw CaptureWorkingSetError
                .invalidProcessedRoomPlanDescriptor
        }
        try await persistEndRoomPlanTransaction(
            timingPackage: timingPackage,
            rawRoomPlan: roomPlanLineage.raw,
            processedRoomPlan: processed
        )
    }

    public func persistEndRoomPlanTransaction(
        timingPackage: CaptureTimingPackage,
        rawRoomPlan: RoomPlanRawArtifactPayload?,
        processedRoomPlan: RoomPlanProcessedArtifactPayload
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

        let processed = processedRoomPlan
        guard
            processed.descriptor.relativePath
                == RoomPlanEvidenceArtifactBuilder.processedPath,
            processed.descriptor.byteCount == processed.data.count,
            processed.descriptor.sha256
                == EvidenceIntegrity.sha256(of: processed.data)
        else {
            throw CaptureWorkingSetError
                .invalidProcessedRoomPlanDescriptor
        }

        let sourceRefs: [String]
        switch processed.descriptor.sourceRawSerializationStatus {
        case .persisted:
            guard let raw = rawRoomPlan else {
                throw CaptureWorkingSetError
                    .processedRoomPlanRequiresRaw
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
                processed.descriptor.sourceRawSHA256
                    == raw.descriptor.sha256,
                processed.descriptor.captureSessionID
                    == raw.descriptor.captureSessionID,
                processed.descriptor.coordinateSpaceID
                    == raw.descriptor.coordinateSpaceID
            else {
                throw CaptureWorkingSetError
                    .processedRoomPlanLineageMismatch
            }
            try bindAuthority(
                captureSessionID: raw.descriptor.captureSessionID,
                coordinateSpaceID: raw.descriptor.coordinateSpaceID
            )
            sourceRefs = [
                "sha256:\(raw.descriptor.sha256.description)"
            ]

        case .unavailable:
            guard
                rawRoomPlan == nil,
                processed.descriptor.sourceRawSHA256 == nil
            else {
                throw CaptureWorkingSetError
                    .processedRoomPlanLineageMismatch
            }
            try bindAuthority(
                captureSessionID:
                    processed.descriptor.captureSessionID,
                coordinateSpaceID:
                    processed.descriptor.coordinateSpaceID
            )
            sourceRefs = [
                "capture_session:"
                    + processed.descriptor.captureSessionID.description,
                "roomplan_raw_serialization:unavailable",
            ]
        }

        if let existingTiming = timingDocument,
           let existingProcessed = processedRoomPlanDescriptor
        {
            let rawMatches: Bool
            switch processed.descriptor.sourceRawSerializationStatus {
            case .persisted:
                rawMatches =
                    rawRoomPlanDescriptor
                        == rawRoomPlan?.descriptor
            case .unavailable:
                rawMatches = rawRoomPlanDescriptor == nil
            }

            if existingTiming == timingPackage.document,
               existingProcessed == processed.descriptor,
               rawMatches
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

        var transactionDeclarations: [BundlePayloadDeclaration] = [
            timingPackage.payloadDeclaration,
        ]
        if let raw = rawRoomPlan {
            transactionDeclarations.append(
                BundlePayloadDeclaration(
                    path: raw.descriptor.relativePath,
                    mediaType: "application/json",
                    producer: "roomplan_capture",
                    provenanceClass: .appleRoomPlanRawScan,
                    role: .canonical
                )
            )
        }
        transactionDeclarations.append(
            BundlePayloadDeclaration(
                path: processed.descriptor.relativePath,
                mediaType: "application/json",
                producer: "roomplan_builder",
                provenanceClass: .appleRoomPlanInference,
                role: .canonical,
                sourceRefs: sourceRefs
            )
        )

        for declaration in transactionDeclarations {
            guard declarations[declaration.path] == nil else {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        var writes: [(Data, CaptureStorePath)] = try [
            (
                timingPackage.data,
                CaptureStorePath(CaptureTimingPackage.path)
            ),
        ]
        if let raw = rawRoomPlan {
            writes.append(
                (
                    raw.data,
                    try CaptureStorePath(
                        raw.descriptor.relativePath
                    )
                )
            )
        }
        writes.append(
            (
                processed.data,
                try CaptureStorePath(
                    processed.descriptor.relativePath
                )
            )
        )

        do {
            for (data, path) in writes {
                try await writer.writeIfIdentical(
                    data,
                    to: path
                )
            }
        } catch {
            for (data, path) in writes.reversed() {
                _ = try? await writer.removeIfIdentical(
                    data,
                    at: path
                )
            }
            throw error
        }

        for declaration in transactionDeclarations {
            declarations[declaration.path] = declaration
        }
        timingDocument = timingPackage.document
        rawRoomPlanDescriptor = rawRoomPlan?.descriptor
        processedRoomPlanDescriptor = processed.descriptor
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

        let sourceRefs: [String]
        switch descriptor.sourceRawSerializationStatus {
        case .persisted:
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
            sourceRefs = [
                "sha256:\(raw.sha256.description)"
            ]

        case .unavailable:
            guard
                descriptor.sourceRawSHA256 == nil,
                rawRoomPlanDescriptor == nil
            else {
                throw CaptureWorkingSetError
                    .processedRoomPlanLineageMismatch
            }
            try bindAuthority(
                captureSessionID: descriptor.captureSessionID,
                coordinateSpaceID: descriptor.coordinateSpaceID
            )
            sourceRefs = [
                "capture_session:"
                    + descriptor.captureSessionID.description,
                "roomplan_raw_serialization:unavailable",
            ]
        }

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
            sourceRefs: sourceRefs
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

        let meshPaths =
            package.geometryFiles.map(\.path)
            + [MeshEvidencePackage.indexPath]
        if let duplicate = meshPaths.first(where: {
            declarations[$0] != nil
        }) {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(duplicate)
        }

        do {
            try await package.persist(using: writer)
        } catch {
            // Mesh is optional at review time. Keep a failed write from
            // leaving undeclared complete files that would poison bundle
            // integrity and prevent the already-persisted frame/depth
            // fallback from being used.
            for path in meshPaths {
                if let storePath = try? CaptureStorePath(path) {
                    try? await writer.removeIfPresent(storePath)
                }
            }
            throw error
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

        try await writer.write(
            package.data,
            to: CaptureStorePath(AnnotationEvidencePackage.path)
        )
        try register(
            BundlePayloadDeclaration(
                path: AnnotationEvidencePackage.path,
                mediaType: "application/json",
                producer: "annotation",
                provenanceClass: .userAnnotation,
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

        try await writer.write(
            package.data,
            to: CaptureStorePath(MeasurementEvidencePackage.path)
        )
        try register(
            BundlePayloadDeclaration(
                path: MeasurementEvidencePackage.path,
                mediaType: "application/json",
                producer: "measurement",
                provenanceClass: .userAttestedMeasurement,
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

        try await writer.write(
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
            switch processedRoomPlanDescriptor
                .sourceRawSerializationStatus
            {
            case .persisted:
                guard let rawRoomPlanDescriptor,
                      processedRoomPlanDescriptor.sourceRawSHA256
                        == rawRoomPlanDescriptor.sha256
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }

            case .unavailable:
                guard
                    rawRoomPlanDescriptor == nil,
                    processedRoomPlanDescriptor.sourceRawSHA256 == nil
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
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
