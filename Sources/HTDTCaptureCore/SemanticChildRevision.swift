import Foundation

/// Semantic-only child revisions (issue #319): a new capture revision
/// that corrects annotations, measurements, opening dispositions, and
/// equipment metadata of a *finalized* parent bundle without rescanning
/// the room. The child preserves the parent's sensor evidence byte-for-
/// byte (sha256-identical payloads), keeps the parent's capture-session
/// and coordinate-space identities (no fabricated session), and
/// regenerates only the semantic records plus the quality report and
/// the `revision/intent.json` lineage document.
///
/// Revision-bound JSON documents the operator does not edit (connected
/// spaces, task-plan status, capture strategy, room reference frame,
/// as-built verification, reference targets, advisories, geometry
/// candidates, RoomPlan metadata) are carried forward unchanged except
/// that `capture_revision_id` members equal to the parent identity are
/// rebound to the child — their content, timestamps, and record ids all
/// stay exactly the parent's.
public enum SemanticChildRevisionError: Error, Sendable, Equatable {
    case parentNotValidated
    case parentMissingManifest
    case parentMissingQualityReport
    case sessionDocumentUnavailable
    case payloadReadFailed(String)
    case payloadDigestMismatch(String)
    case payloadDecodeFailed(String)
    case equipmentIdentityWithoutParent
    /// The edited collection mixes provenance classes in one payload
    /// — the working-set store rejects the same shape rather than
    /// under-claiming container authority.
    case mixedProvenanceCollection(String)
}

/// A validated parent bundle plus the semantic records the correction
/// flow may edit. Nothing here is mutable — edits arrive separately in
/// `SemanticChildRevisionEdits` so unchanged records round-trip
/// byte-identical by construction.
public struct SemanticChildRevisionContext: Sendable {
    public let parentDirectory: URL
    public let manifest: BundleManifest
    /// SHA-256 of the parent bundle's canonical `manifest.json` bytes —
    /// the exact authority the child derives from, persisted in
    /// `revision/intent.json`.
    public let bundleDigestSHA256: EvidenceSHA256
    public let sessionDocument: CaptureSessionDocument
    public let parentQualityReport: CaptureQualityReport
    public let entities: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]
    public let openingReview: OpeningReviewDocument?
    public let equipmentIdentity: EquipmentIdentityDocument?
    /// The parent's own revision intent when the parent is itself a
    /// child revision; the child's intent supersedes it (lineage chains
    /// stay addressable through `parent_bundle_sha256`).
    public let parentIntent: CaptureRevisionIntentDocument?

    public init(
        parentDirectory: URL,
        manifest: BundleManifest,
        bundleDigestSHA256: EvidenceSHA256,
        sessionDocument: CaptureSessionDocument,
        parentQualityReport: CaptureQualityReport,
        entities: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        openingReview: OpeningReviewDocument?,
        equipmentIdentity: EquipmentIdentityDocument?,
        parentIntent: CaptureRevisionIntentDocument?
    ) {
        self.parentDirectory = parentDirectory
        self.manifest = manifest
        self.bundleDigestSHA256 = bundleDigestSHA256
        self.sessionDocument = sessionDocument
        self.parentQualityReport = parentQualityReport
        self.entities = entities
        self.measurements = measurements
        self.openingReview = openingReview
        self.equipmentIdentity = equipmentIdentity
        self.parentIntent = parentIntent
    }
}

/// Operator edits for one semantic correction (issue #319). A nil field
/// means "keep the parent's record"; every field is content-only — the
/// builder re-binds revision identity and lifecycle metadata itself.
public struct SemanticChildRevisionEdits: Sendable, Equatable {
    public var entities: [CaptureAnnotationEntity]?
    public var measurements: [CaptureMeasurement]?
    /// Opening candidates for the child's review document. The doc's
    /// session/space identities are re-bound to the parent's, so edits
    /// supply only the record list.
    public var openings: [RoomOpeningCandidate]?
    /// Equipment-identity records (must bind to the child entity set).
    public var equipmentRecords: [EquipmentIdentityRecord]?
    /// Operator note explaining the correction, persisted in
    /// `revision/intent.json`.
    public var correctionNote: String?

    public init(
        entities: [CaptureAnnotationEntity]? = nil,
        measurements: [CaptureMeasurement]? = nil,
        openings: [RoomOpeningCandidate]? = nil,
        equipmentRecords: [EquipmentIdentityRecord]? = nil,
        correctionNote: String? = nil
    ) {
        self.entities = entities
        self.measurements = measurements
        self.openings = openings
        self.equipmentRecords = equipmentRecords
        self.correctionNote = correctionNote
    }
}

/// Outcome of one semantic-child build: the finalized child bundle
/// directory, its manifest, and the intent document that records the
/// exact semantic diff against the parent.
public struct SemanticChildRevisionResult: Sendable, Equatable {
    public let bundleDirectory: URL
    public let bundleDigestSHA256: EvidenceSHA256
    public let payloadCount: Int
    public let intent: CaptureRevisionIntentDocument

    public init(
        bundleDirectory: URL,
        bundleDigestSHA256: EvidenceSHA256,
        payloadCount: Int,
        intent: CaptureRevisionIntentDocument
    ) {
        self.bundleDirectory = bundleDirectory
        self.bundleDigestSHA256 = bundleDigestSHA256
        self.payloadCount = payloadCount
        self.intent = intent
    }
}

public enum SemanticChildRevisionBuilder {
    private static let qualityPath =
        "quality/capture-quality.json"
    /// Payloads regenerated from typed records rather than carried
    /// forward. Everything else in the parent's payload set is copied
    /// (binaries verbatim, JSON with revision identity rebound).
    private static let regeneratedPaths: Set<String> = [
        AnnotationEvidencePackage.path,
        MeasurementEvidencePackage.path,
        OpeningReviewPackage.path,
        EquipmentIdentityEvidencePackage.path,
        qualityPath,
        CaptureRevisionIntentPackage.path,
    ]

    /// Validates the parent directory and decodes its semantic records.
    /// Only a `pass` bundle may parent a correction — evidence tampering
    /// must never propagate into a child (issue #319).
    public static func loadContext(
        parentDirectory: URL
    ) throws -> SemanticChildRevisionContext {
        let report = try BundleDirectoryValidator.validate(
            root: parentDirectory
        )
        guard report.valid else {
            throw SemanticChildRevisionError.parentNotValidated
        }
        let manifest = report.manifest
        let digest = report.bundleDigest

        func decode<T: Decodable>(
            _ type: T.Type,
            path: String
        ) throws -> T? {
            guard manifest.files.contains(where: {
                $0.path == path
            }) else {
                return nil
            }
            let url = parentDirectory.appendingPathComponent(
                path,
                isDirectory: false
            )
            guard let data = try? Data(contentsOf: url) else {
                throw SemanticChildRevisionError
                    .payloadReadFailed(path)
            }
            guard let value = try? JSONDecoder().decode(
                T.self,
                from: data
            ) else {
                throw SemanticChildRevisionError
                    .payloadDecodeFailed(path)
            }
            return value
        }

        guard let session = try decode(
            CaptureSessionDocument.self,
            path: CaptureSessionFoundationPackage.sessionPath
        ) else {
            throw SemanticChildRevisionError
                .sessionDocumentUnavailable
        }
        guard let quality = try decode(
            CaptureQualityReport.self,
            path: qualityPath
        ) else {
            throw SemanticChildRevisionError
                .parentMissingQualityReport
        }
        let entities = try decode(
            CaptureAnnotationCollection.self,
            path: AnnotationEvidencePackage.path
        )?.entities ?? []
        let measurements = try decode(
            CaptureMeasurementCollection.self,
            path: MeasurementEvidencePackage.path
        )?.measurements ?? []
        return SemanticChildRevisionContext(
            parentDirectory: parentDirectory,
            manifest: manifest,
            bundleDigestSHA256: digest,
            sessionDocument: session,
            parentQualityReport: quality,
            entities: entities,
            measurements: measurements,
            openingReview: try decode(
                OpeningReviewDocument.self,
                path: OpeningReviewPackage.path
            ),
            equipmentIdentity: try decode(
                EquipmentIdentityDocument.self,
                path: EquipmentIdentityEvidencePackage.path
            ),
            parentIntent: try decode(
                CaptureRevisionIntentDocument.self,
                path: CaptureRevisionIntentPackage.path
            )
        )
    }

    /// Builds and finalizes the semantic child bundle (issue #319).
    /// `stagingDirectory` must be a fresh, empty directory on the same
    /// volume as `destinationDirectory`; it becomes the child's staging
    /// area and is moved into place atomically by the shared finalizer.
    public static func build(
        context: SemanticChildRevisionContext,
        childRevisionID: CaptureRevisionID,
        edits: SemanticChildRevisionEdits =
            SemanticChildRevisionEdits(),
        stagingDirectory: URL,
        destinationDirectory: URL,
        app: BundleAppIdentity,
        now: Date = Date()
    ) async throws -> SemanticChildRevisionResult {
        let parentRevisionID = context.manifest.captureRevisionID
        let childEntities = edits.entities ?? context.entities
        let childMeasurements =
            edits.measurements ?? context.measurements

        var fileManager: FileManager { .default }
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        var declarations: [BundlePayloadDeclaration] = []
        var stagedPaths = Set<String>()

        // Regenerated semantic payloads --------------------------------
        let parentHasAnnotations = context.manifest.files
            .contains { $0.path == AnnotationEvidencePackage.path }
        if parentHasAnnotations || edits.entities != nil {
            let package = try AnnotationEvidencePackageBuilder.build(
                entities: childEntities,
                priorEntities: context.entities,
                revisedAt: now
            )
            try write(package.data, path: AnnotationEvidencePackage.path,
                      to: stagingDirectory)
            stagedPaths.insert(AnnotationEvidencePackage.path)
            declarations.append(
                BundlePayloadDeclaration(
                    path: AnnotationEvidencePackage.path,
                    mediaType: "application/json",
                    producer: "annotation",
                    provenanceClass: try annotationProvenance(
                        package.collection
                    ),
                    role: .canonical
                )
            )
        }
        let parentHasMeasurements = context.manifest.files
            .contains { $0.path == MeasurementEvidencePackage.path }
        if parentHasMeasurements || edits.measurements != nil {
            let package = try MeasurementEvidencePackageBuilder.build(
                measurements: childMeasurements
            )
            try write(
                package.data,
                path: MeasurementEvidencePackage.path,
                to: stagingDirectory
            )
            stagedPaths.insert(MeasurementEvidencePackage.path)
            declarations.append(
                BundlePayloadDeclaration(
                    path: MeasurementEvidencePackage.path,
                    mediaType: "application/json",
                    producer: "measurement",
                    provenanceClass: try measurementProvenance(
                        package.collection
                    ),
                    role: .canonical
                )
            )
        }
        let parentReview = context.openingReview
        if parentReview != nil || edits.openings != nil {
            let sessionID = parentReview?.captureSessionID
                ?? context.sessionDocument.captureSessionID
            let spaceID = parentReview?.coordinateSpaceID
                ?? context.sessionDocument.coordinateSpaceID
            let document = try OpeningReviewDocument(
                captureRevisionID: childRevisionID,
                captureSessionID: sessionID,
                coordinateSpaceID: spaceID,
                openings: edits.openings
                    ?? parentReview?.openings ?? []
            )
            let package = try OpeningReviewPackageBuilder.build(
                document: document
            )
            try write(
                package.data,
                path: OpeningReviewPackage.path,
                to: stagingDirectory
            )
            stagedPaths.insert(OpeningReviewPackage.path)
            declarations.append(package.payloadDeclaration)
        }
        if edits.equipmentRecords != nil || context.equipmentIdentity
            != nil
        {
            let records = edits.equipmentRecords
                ?? context.equipmentIdentity?.records
            guard let records else {
                throw SemanticChildRevisionError
                    .equipmentIdentityWithoutParent
            }
            let document = try EquipmentIdentityDocument(
                captureRevisionID: childRevisionID,
                coordinateSpaceID: context.equipmentIdentity?
                    .coordinateSpaceID
                    ?? context.sessionDocument.coordinateSpaceID,
                records: records,
                entities: childEntities
            )
            let package = try EquipmentIdentityEvidencePackage(
                document: document
            )
            try write(
                package.data,
                path: EquipmentIdentityEvidencePackage.path,
                to: stagingDirectory
            )
            stagedPaths.insert(EquipmentIdentityEvidencePackage.path)
            declarations.append(
                BundlePayloadDeclaration(
                    path: EquipmentIdentityEvidencePackage.path,
                    mediaType: "application/json",
                    producer: "capture_app",
                    provenanceClass: .captureAppDerived,
                    role: .derived,
                    sourceRefs: package.sourceRefs
                )
            )
        }

        // Carried-forward payloads: binaries verbatim, JSON with the
        // revision identity rebound to the child -----------------------
        var reusedEvidenceRefs: [String] = []
        for entry in context.manifest.files
            where !regeneratedPaths.contains(entry.path)
        {
            let source = context.parentDirectory
                .appendingPathComponent(entry.path, isDirectory: false)
            guard let bytes = try? Data(contentsOf: source) else {
                throw SemanticChildRevisionError
                    .payloadReadFailed(entry.path)
            }
            guard EvidenceIntegrity.sha256(of: bytes).description
                    == entry.sha256.description
            else {
                throw SemanticChildRevisionError
                    .payloadDigestMismatch(entry.path)
            }
            var staged = bytes
            var semanticRecordChanged = false
            if entry.path.hasSuffix(".json") {
                do {
                    var value = try StrictJSON.parse(bytes)
                    semanticRecordChanged = rebindRevisionID(
                        &value,
                        from: parentRevisionID,
                        to: childRevisionID
                    )
                    staged = try CanonicalJSONProfile
                        .canonicalBytes(of: value)
                } catch let error as SemanticChildRevisionError {
                    throw error
                } catch {
                    throw SemanticChildRevisionError
                        .payloadDecodeFailed(entry.path)
                }
            }
            try write(
                staged,
                path: entry.path,
                to: stagingDirectory
            )
            stagedPaths.insert(entry.path)
            // The parent's own declaration survives: provenance class,
            // producer, role, and lineage refs describe content that is
            // byte-identical or rebound only in revision identity, so
            // the parent manifest is the authoritative statement.
            declarations.append(
                BundlePayloadDeclaration(
                    path: entry.path,
                    mediaType: entry.mediaType,
                    producer: entry.producer,
                    provenanceClass: entry.provenanceClass,
                    role: entry.role,
                    sourceRefs: entry.sourceRefs
                )
            )
            if !semanticRecordChanged {
                reusedEvidenceRefs.append(entry.path)
            }
        }

        // Quality report: parent counters carried forward, completeness
        // recomputed against the child collections (issue #319). The
        // correction can only ever clear `annotation_missing` /
        // `measurement_missing` diagnostics or introduce them —
        // every other finding is evidence-bound and stays verbatim.
        let parentReport = context.parentQualityReport
        let annotationStatus = CompletenessStatus(
            required: Set(parentReport.annotationCompleteness.required),
            present: Set(childEntities.map(annotationQualityKey))
        )
        let measurementStatus = CompletenessStatus(
            required: Set(
                parentReport.measurementCompleteness.required
            ),
            present: Set(childMeasurements.map(\.quantityType))
        )
        var diagnostics = parentReport.diagnostics.filter {
            $0.code != "annotation_missing"
                && $0.code != "measurement_missing"
        }
        for missing in annotationStatus.missing {
            diagnostics.append(
                QualityDiagnostic(
                    code: "annotation_missing",
                    severity: .error,
                    message:
                        "Required annotation is missing: \(missing)"
                )
            )
        }
        for missing in measurementStatus.missing {
            diagnostics.append(
                QualityDiagnostic(
                    code: "measurement_missing",
                    severity: .error,
                    message:
                        "Required measurement is missing: \(missing)"
                )
            )
        }
        diagnostics.append(
            QualityDiagnostic(
                code: "semantic_correction_revision",
                severity: .info,
                message:
                    "Semantic-only child of \(parentRevisionID): "
                    + "parent sensor evidence reused byte-for-byte"
            )
        )
        let childReport = CaptureQualityReport(
            schema: parentReport.schema,
            schemaVersion: parentReport.schemaVersion,
            rulesetVersion: parentReport.rulesetVersion,
            readyForHTDTIngestion: !diagnostics.contains {
                $0.severity == .error
            },
            trackingEvents: parentReport.trackingEvents,
            roomPlanStatus: parentReport.roomPlanStatus,
            activeMeshAnchorCount: parentReport.activeMeshAnchorCount,
            evidenceFrameCount: parentReport.evidenceFrameCount,
            depthEvidenceCount: parentReport.depthEvidenceCount,
            usableMeshAnchorCount: parentReport.usableMeshAnchorCount,
            usableDepthSampleCount: parentReport
                .usableDepthSampleCount,
            annotationCompleteness: annotationStatus,
            measurementCompleteness: measurementStatus,
            resourceEvents: parentReport.resourceEvents,
            integrityStatus: .pass,
            benchmarkRefs: parentReport.benchmarkRefs,
            diagnostics: diagnostics
        )
        let qualityData = try encode(packageStyle: childReport)
        try write(
            qualityData,
            path: qualityPath,
            to: stagingDirectory
        )
        stagedPaths.insert(qualityPath)
        declarations.append(
            BundlePayloadDeclaration(
                path: qualityPath,
                mediaType: "application/json",
                producer: "capture_quality",
                provenanceClass: .captureAppDerived,
                role: .canonical
            )
        )

        // Revision intent: the semantic diff the child performs -------
        let parentEntityByID = Dictionary(
            context.entities.map { ($0.entityID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let childEntityByID = Dictionary(
            childEntities.map { ($0.entityID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let parentMeasurementByID = Dictionary(
            context.measurements.map { ($0.measurementID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let childMeasurementByID = Dictionary(
            childMeasurements.map { ($0.measurementID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var added: [CaptureRevisionRecordRef] = []
        var changed: [CaptureRevisionRecordRef] = []
        var superseded: [CaptureRevisionRecordRef] = []
        func appendRef(
            _ ref: CaptureRevisionRecordRef?,
            to bucket: inout [CaptureRevisionRecordRef]
        ) {
            if let ref, bucket.count
                < CaptureRevisionIntentDocument.maximumRecordRefs
            {
                bucket.append(ref)
            }
        }
        for entity in childEntities {
            let ref = try? CaptureRevisionRecordRef(
                payloadPath: AnnotationEvidencePackage.path,
                recordID: entity.entityID.description
            )
            if parentEntityByID[entity.entityID] == nil {
                appendRef(ref, to: &added)
            } else if parentEntityByID[entity.entityID] != entity {
                appendRef(ref, to: &changed)
            }
        }
        for entity in context.entities
        where childEntityByID[entity.entityID] == nil {
            appendRef(
                try? CaptureRevisionRecordRef(
                    payloadPath: AnnotationEvidencePackage.path,
                    recordID: entity.entityID.description
                ),
                to: &superseded
            )
        }
        for measurement in childMeasurements {
            let ref = try? CaptureRevisionRecordRef(
                payloadPath: MeasurementEvidencePackage.path,
                recordID: measurement.measurementID.description
            )
            if parentMeasurementByID[measurement.measurementID] == nil
            {
                appendRef(ref, to: &added)
            } else if parentMeasurementByID[
                measurement.measurementID
            ] != measurement {
                appendRef(ref, to: &changed)
            }
        }
        for measurement in context.measurements
        where childMeasurementByID[measurement.measurementID] == nil {
            appendRef(
                try? CaptureRevisionRecordRef(
                    payloadPath: MeasurementEvidencePackage.path,
                    recordID: measurement.measurementID.description
                ),
                to: &superseded
            )
        }
        let intentDocument = try CaptureRevisionIntentDocument(
            captureRevisionID: childRevisionID,
            parentRevisionID: parentRevisionID,
            parentBundleSHA256: context.bundleDigestSHA256.description,
            revisionKind: .semanticCorrection,
            reusedCaptureSessionIDs: context.manifest.captureSessionIDs,
            reusedCoordinateSpaceIDs: context.manifest
                .coordinateSpaceIDs,
            addedRecordRefs: added,
            changedRecordRefs: changed,
            supersededRecordRefs: superseded,
            reusedEvidenceRefs: reusedEvidenceRefs,
            correctionNote: edits.correctionNote,
            createdAtUTC: BundleTimestamp.utcString(from: now)
        )
        let intentPackage = try CaptureRevisionIntentPackageBuilder
            .build(document: intentDocument)
        try write(
            intentPackage.data,
            path: CaptureRevisionIntentPackage.path,
            to: stagingDirectory
        )
        stagedPaths.insert(CaptureRevisionIntentPackage.path)
        declarations.append(intentPackage.payloadDeclaration)

        let request = BundleFinalizationRequest(
            captureSeriesID: context.manifest.captureSeriesID,
            captureRevisionID: childRevisionID,
            parentRevisionID: parentRevisionID,
            captureSessionIDs: context.manifest.captureSessionIDs,
            coordinateSpaceIDs: context.manifest
                .coordinateSpaceIDs,
            createdAtUTC: intentDocument.createdAtUTC,
            finalizedAtUTC: BundleTimestamp.utcString(from: now),
            app: app,
            payloads: declarations.sorted {
                BundleLogicalPath.utf8Less($0.path, $1.path)
            },
            qualityReport: childReport
        )
        let result = try await BundleRevisionFinalizer().finalize(
            stagingDirectory: stagingDirectory,
            destinationDirectory: destinationDirectory,
            request: request
        )
        return SemanticChildRevisionResult(
            bundleDirectory: result.directory,
            bundleDigestSHA256: result.bundleDigest,
            payloadCount: result.payloadCount,
            intent: intentDocument
        )
    }

    /// Rebinds `capture_revision_id` members equal to the parent
    /// identity to the child — at any object depth, since records like
    /// `RoomStateSnapshot` nest the field inside collections. Returns
    /// true when any member changed.
    private static func rebindRevisionID(
        _ value: inout StrictJSONValue,
        from parent: CaptureRevisionID,
        to child: CaptureRevisionID
    ) -> Bool {
        var changed = false
        switch value {
        case let .object(pairs):
            var rebound: [(key: String, value: StrictJSONValue)] = []
            rebound.reserveCapacity(pairs.count)
            for pair in pairs {
                var member = pair.value
                if pair.key == "capture_revision_id",
                   case let .string(text) = member,
                   text == parent.description
                {
                    member = .string(child.description)
                    changed = true
                } else {
                    changed = rebindRevisionID(
                        &member,
                        from: parent,
                        to: child
                    ) || changed
                }
                rebound.append((key: pair.key, value: member))
            }
            if changed {
                value = .object(rebound)
            }
        case let .array(elements):
            var reboundElements: [StrictJSONValue] = []
            reboundElements.reserveCapacity(elements.count)
            for var element in elements {
                changed = rebindRevisionID(
                    &element,
                    from: parent,
                    to: child
                ) || changed
                reboundElements.append(element)
            }
            if changed {
                value = .array(reboundElements)
            }
        default:
            break
        }
        return changed
    }

    private static func write(
        _ data: Data,
        path: String,
        to root: URL
    ) throws {
        let url = root.appendingPathComponent(
            path,
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private static func encode<T: Encodable>(
        packageStyle value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return try encoder.encode(value)
    }

    private static func annotationQualityKey(
        _ entity: CaptureAnnotationEntity
    ) -> String {
        if entity.type == .speaker || entity.type == .subwoofer,
           let role = entity.channelRole
        {
            return entity.type.rawValue + ":" + role.rawValue
        }
        if entity.type == .listeningPosition,
           let role = entity.listeningRole
        {
            return entity.type.rawValue + ":" + role.rawValue
        }
        return entity.type.rawValue + ":" + entity.label
    }

    private static func annotationProvenance(
        _ collection: CaptureAnnotationCollection
    ) throws -> BundleProvenanceClass {
        var provenance: AnnotationProvenanceClass?
        for entity in collection.entities {
            if let provenance,
               provenance != entity.provenanceClass
            {
                // Same closed rule the working-set store applies: a
                // mixed-provenance entity collection cannot declare
                // honest container authority.
                throw SemanticChildRevisionError
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
        case .captureAppDerived, nil:
            return .captureAppDerived
        }
    }

    private static func measurementProvenance(
        _ collection: CaptureMeasurementCollection
    ) throws -> BundleProvenanceClass {
        var provenance: MeasurementProvenanceClass?
        for measurement in collection.measurements {
            if let provenance,
               provenance != measurement.provenanceClass
            {
                return .captureAppDerived
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
        case .captureAppDerived, nil:
            return .captureAppDerived
        }
    }
}
