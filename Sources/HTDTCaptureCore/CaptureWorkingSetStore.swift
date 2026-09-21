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
    case coordinateDiscontinuityRequiresBoundSpace
    case invalidCoordinateTransition
    case coordinateTransitionLimitExceeded
    case unsafeDiscardPath
    case workingSetSealed
    case workingSetNotSealed
    case workingSetConsumed
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
    public let capturedRoomMetadata: CapturedRoomMetadataDocument?
    public let coordinateSpacePolicy: CoordinateSpacePolicyDocument?
    public let meshAnchorCount: Int?
    /// Mesh anchors whose decoded geometry carries at least one vertex
    /// and at least one face. `nil` until a mesh index is committed
    /// (issue #169).
    public let usableMeshAnchorCount: Int?
    public let evidenceFrameCount: Int
    public let depthEvidenceCount: Int
    /// Total finite, positive, validity-masked depth samples across all
    /// committed frame depth maps (issue #169).
    public let usableDepthSampleCount: Int
    /// Committed frames whose depth map contains at least one usable
    /// sample — the fallback-satisfying depth evidence count.
    public let usableDepthEvidenceCount: Int
    public let evidenceFrameRefs: [String]

    public init(
        identity: CaptureWorkingSetIdentity,
        rootDirectory: URL,
        captureSessionIDs: [CaptureSessionID],
        coordinateSpaceIDs: [CoordinateSpaceID],
        payloadDeclarations: [BundlePayloadDeclaration],
        rawRoomPlanDescriptor: RoomPlanRawEvidenceDescriptor?,
        processedRoomPlanDescriptor: RoomPlanProcessedEvidenceDescriptor?,
        capturedRoomMetadata: CapturedRoomMetadataDocument?,
        coordinateSpacePolicy: CoordinateSpacePolicyDocument?,
        meshAnchorCount: Int?,
        usableMeshAnchorCount: Int?,
        evidenceFrameCount: Int,
        depthEvidenceCount: Int,
        usableDepthSampleCount: Int,
        usableDepthEvidenceCount: Int,
        evidenceFrameRefs: [String]
    ) {
        self.identity = identity
        self.rootDirectory = rootDirectory
        self.captureSessionIDs = captureSessionIDs
        self.coordinateSpaceIDs = coordinateSpaceIDs
        self.payloadDeclarations = payloadDeclarations
        self.rawRoomPlanDescriptor = rawRoomPlanDescriptor
        self.processedRoomPlanDescriptor = processedRoomPlanDescriptor
        self.capturedRoomMetadata = capturedRoomMetadata
        self.coordinateSpacePolicy = coordinateSpacePolicy
        self.meshAnchorCount = meshAnchorCount
        self.usableMeshAnchorCount = usableMeshAnchorCount
        self.evidenceFrameCount = evidenceFrameCount
        self.depthEvidenceCount = depthEvidenceCount
        self.usableDepthSampleCount = usableDepthSampleCount
        self.usableDepthEvidenceCount = usableDepthEvidenceCount
        self.evidenceFrameRefs = evidenceFrameRefs
    }
}

/// Immutable result of a successful `sealForFinalization` (issue #180).
/// The snapshot is the exact sealed state — every declaration it lists
/// was verified durable on disk after all in-flight mutations drained —
/// and `qualityReport` is the report evaluated from, and persisted
/// against, that same state. `sealToken` correlates this seal
/// acquisition for hosts that coordinate promotion; the store itself
/// enforces the barrier through `sealForFinalization`/`unseal`/
/// `consumeSealedWorkingSet`, not through the token.
public struct SealedWorkingSet: Sendable, Equatable {
    public let sealToken: UUID
    public let snapshot: CaptureWorkingSetSnapshot
    public let qualityReport: CaptureQualityReport
    public let sealedAtUTC: String

    public init(
        sealToken: UUID,
        snapshot: CaptureWorkingSetSnapshot,
        qualityReport: CaptureQualityReport,
        sealedAtUTC: String
    ) {
        self.sealToken = sealToken
        self.snapshot = snapshot
        self.qualityReport = qualityReport
        self.sealedAtUTC = sealedAtUTC
    }
}

/// v1 coordinate-authority policy for a capture revision (issue #157):
/// exactly one coordinate space is bound per revision. A spatial
/// discontinuity never rebinds the revision in place; the persisted
/// policy requires a new revision so coordinates are never silently
/// reinterpreted across a discontinuity.
public enum CoordinateSpacePolicy: String, Codable, Sendable, Equatable {
    case singleSpacePerRevision = "single_space_per_revision"
}

public enum CoordinateDiscontinuityRequirement:
    String,
    Codable,
    Sendable,
    Equatable
{
    case newRevisionRequired = "new_revision_required"
}

public enum WorldOriginContinuity: String, Codable, Sendable, Equatable {
    case preserved
    case broken
}

/// Canonical wire record for one declared spatial discontinuity. Kept
/// distinct from the domain `CoordinateSpaceTransition` so the persisted
/// schema controls its own snake_case key contract.
public struct CoordinateTransitionRecord:
    Codable,
    Sendable,
    Equatable
{
    public let previousCoordinateSpaceID: CoordinateSpaceID
    public let nextCoordinateSpaceID: CoordinateSpaceID
    public let reason: CoordinateDiscontinuityReason
    public let sessionTimestampSeconds: Double?

    public init(
        previousCoordinateSpaceID: CoordinateSpaceID,
        nextCoordinateSpaceID: CoordinateSpaceID,
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double?
    ) {
        self.previousCoordinateSpaceID = previousCoordinateSpaceID
        self.nextCoordinateSpaceID = nextCoordinateSpaceID
        self.reason = reason
        self.sessionTimestampSeconds = sessionTimestampSeconds
    }

    public init(_ transition: CoordinateSpaceTransition) {
        self.init(
            previousCoordinateSpaceID: transition.previous,
            nextCoordinateSpaceID: transition.next,
            reason: transition.reason,
            sessionTimestampSeconds:
                transition.sessionTimestampSeconds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case previousCoordinateSpaceID =
            "previous_coordinate_space_id"
        case nextCoordinateSpaceID = "next_coordinate_space_id"
        case reason
        case sessionTimestampSeconds = "session_timestamp_seconds"
    }
}

public enum CoordinateSpacePolicyError: Error, Sendable, Equatable {
    case transitionAuthorityMismatch
    case invalidTransitionTimestamp
    case encodedDocumentMismatch
}

/// Persisted at `session/coordinate-space-policy.json` by the End
/// RoomPlan commit. The document makes the single-space v1 contract
/// explicit and records every discontinuity the working set observed so
/// the finalized bundle states whether world-origin continuity was
/// preserved.
public struct CoordinateSpacePolicyDocument:
    Codable,
    Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let policy: CoordinateSpacePolicy
    public let discontinuityRequirement:
        CoordinateDiscontinuityRequirement
    public let worldOriginContinuity: WorldOriginContinuity
    public let coordinateTransitions: [CoordinateTransitionRecord]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        transitions: [CoordinateSpaceTransition]
    ) throws {
        var records: [CoordinateTransitionRecord] = []
        records.reserveCapacity(transitions.count)
        for transition in transitions {
            // The store never advances the bound space, so every
            // recorded discontinuity must originate from it and target a
            // different space.
            guard transition.previous == coordinateSpaceID,
                  transition.next != coordinateSpaceID
            else {
                throw CoordinateSpacePolicyError
                    .transitionAuthorityMismatch
            }
            if let seconds = transition.sessionTimestampSeconds {
                guard seconds.isFinite, seconds >= 0 else {
                    throw CoordinateSpacePolicyError
                        .invalidTransitionTimestamp
                }
            }
            records.append(CoordinateTransitionRecord(transition))
        }

        self.schema = "htdt.coordinate-space-policy"
        self.schemaVersion = "1.0.0"
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.policy = .singleSpacePerRevision
        self.discontinuityRequirement = .newRevisionRequired
        self.worldOriginContinuity =
            records.isEmpty ? .preserved : .broken
        self.coordinateTransitions = records
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case policy
        case discontinuityRequirement = "discontinuity_requirement"
        case worldOriginContinuity = "world_origin_continuity"
        case coordinateTransitions = "coordinate_transitions"
    }
}

public struct CoordinateSpacePolicyPackage: Sendable, Equatable {
    public static let path =
        "session/coordinate-space-policy.json"

    public let document: CoordinateSpacePolicyDocument
    public let data: Data

    public init(
        document: CoordinateSpacePolicyDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        )
    }
}

public enum CoordinateSpacePolicyPackageBuilder {
    public static func build(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        transitions: [CoordinateSpaceTransition]
    ) throws -> CoordinateSpacePolicyPackage {
        let document = try CoordinateSpacePolicyDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            transitions: transitions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)

        guard
            let decoded = try? JSONDecoder().decode(
                CoordinateSpacePolicyDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw CoordinateSpacePolicyError
                .encodedDocumentMismatch
        }

        return CoordinateSpacePolicyPackage(
            document: document,
            data: data
        )
    }
}

public actor CaptureWorkingSetStore {
    /// Deterministic bound on retained tracking-history intervals. Each
    /// interval contributes at most two quality events, so the canonical
    /// tracking history stays bounded on arbitrarily long scans.
    public static let maxTrackingIntervals = 128

    /// Deterministic bound on recorded spatial discontinuities. Under the
    /// v1 single-space policy a discontinuity already requires a new
    /// revision, so a large recorded count indicates abuse rather than a
    /// legitimate scan.
    public static let maxCoordinateTransitions = 64

    public let identity: CaptureWorkingSetIdentity
    public let rootDirectory: URL

    private let writer: AtomicCaptureFileWriter
    private var captureSessionID: CaptureSessionID?
    private var coordinateSpaceID: CoordinateSpaceID?
    private var coordinateTransitions: [CoordinateSpaceTransition] = []
    private var coordinateSpacePolicy: CoordinateSpacePolicyDocument?
    private var declarations: [String: BundlePayloadDeclaration] = [:]
    private var rawRoomPlanDescriptor: RoomPlanRawEvidenceDescriptor?
    private var processedRoomPlanDescriptor: RoomPlanProcessedEvidenceDescriptor?
    private var capturedRoomMetadata: CapturedRoomMetadataDocument?
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
    private var usableDepthSampleCount = 0
    private var usableDepthEvidenceCount = 0
    private var usableMeshAnchorCount: Int?
    private var trackingIntervals: [TrackingInterval] = []
    private var resourceEvents: [CaptureResourceEvent] = []
    private var sealState: SealState = .mutable
    /// Bounded pending-write admission ledger shared by every mutation
    /// entry point: evidence bytes are reserved before they become
    /// queued writer work and released deterministically on every exit
    /// path (issue #147).
    private let admissionController: CaptureStoreAdmissionController
    /// Set while a `persistence_backlog` pressure diagnostic is active
    /// so sustained pressure emits one bounded event rather than one
    /// per admission.
    private var backlogPressureActive = false
    /// Bumped on every seal-state transition. A `sealForFinalization`
    /// call captures it so an `unseal`/`consume` that slips into a
    /// writer suspension deterministically aborts the in-flight seal
    /// instead of letting it return a snapshot the store no longer
    /// holds (issue #180).
    private var sealGeneration = 0
    /// Mutation entry points currently inside the actor (between their
    /// entry guard and their return). The finalization seal drains this
    /// counter to zero — through writer fences — before verifying and
    /// snapshotting, so the sealed state deterministically contains
    /// every write that was already owned (issue #180).
    private var inFlightMutations = 0
    /// Canonical quality payload bytes plus declaration persisted by the
    /// active seal, retained so `unseal` can roll back exactly the bytes
    /// the seal committed.
    private var sealedQualityReport:
        (data: Data, declaration: BundlePayloadDeclaration)?
    /// Mutations rejected or dropped since the first seal: typed-error
    /// rejections from throwing entry points and drops from the
    /// non-throwing observation sinks. Exposed for diagnostics because
    /// the non-throwing sinks cannot surface the typed error.
    private var sealedMutationRejectionCount = 0

    /// Working-set seal lifecycle for the finalization barrier
    /// (issue #180): `.mutable` accepts mutations; `.sealed` rejects new
    /// mutations while `sealForFinalization` drains and snapshots;
    /// `.consumed` is the terminal state after successful promotion.
    private enum SealState: Sendable {
        case mutable
        case sealed
        case consumed
    }

    /// Default pending-write admission bounds (issue #147): generous
    /// enough for bursts of frame/depth packages plus an end-scan mesh
    /// transaction, while bounding how much materialized evidence can
    /// queue behind the file writer.
    public static let defaultAdmissionMaxPendingBytes =
        256 * 1024 * 1024
    public static let defaultAdmissionMaxPendingItems = 64
    /// Bounded diagnostic history for resource/persistence events.
    public static let maxResourceEvents = 256

    public init(
        identity: CaptureWorkingSetIdentity = CaptureWorkingSetIdentity(),
        rootDirectory: URL,
        admissionController: CaptureStoreAdmissionController? = nil
    ) throws {
        self.identity = identity
        self.rootDirectory = rootDirectory
        self.writer = try AtomicCaptureFileWriter(
            rootDirectory: rootDirectory
        )
        self.admissionController = admissionController
            ?? CaptureStoreAdmissionController(
                maxBytes: Self.defaultAdmissionMaxPendingBytes,
                maxItems: Self.defaultAdmissionMaxPendingItems
            )
    }

    public func persistSessionFoundation(
        _ package: CaptureSessionFoundationPackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        let admissionReservation = try reserveAdmission(
            bytes: package.sessionData.count
                + package.capabilitiesData.count
                + package.configurationData.count
                + package.deviceData.count
        )
        defer { releaseAdmission(admissionReservation) }

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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

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

        // Lineage metadata derives deterministically from the validated
        // descriptors, so it is part of the same logical transaction and
        // must replay byte-identically.
        let metadata = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: identity.captureRevisionID,
            raw: raw.descriptor,
            processed: processed.descriptor,
            summary: processed.metadataSummary
        )

        // The v1 coordinate-space policy is persisted with the End
        // RoomPlan commit (issue #157). It records the bound authority and
        // every declared discontinuity so the finalized bundle states
        // explicitly whether world-origin continuity was preserved.
        let policy = try CoordinateSpacePolicyPackageBuilder.build(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: raw.descriptor.captureSessionID,
            coordinateSpaceID: raw.descriptor.coordinateSpaceID,
            transitions: coordinateTransitions
        )

        if let timingDocument,
           let rawRoomPlanDescriptor,
           let processedRoomPlanDescriptor,
           let capturedRoomMetadata,
           let coordinateSpacePolicy
        {
            if timingDocument == timingPackage.document,
               rawRoomPlanDescriptor == raw.descriptor,
               processedRoomPlanDescriptor == processed.descriptor,
               capturedRoomMetadata == metadata.document,
               coordinateSpacePolicy == policy.document
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
              capturedRoomMetadata == nil,
              coordinateSpacePolicy == nil
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
        let metadataDeclaration = roomPlanMetadataDeclaration(
            raw: raw.descriptor,
            processed: processed.descriptor
        )
        let transactionDeclarations = [
            timingPackage.payloadDeclaration,
            rawDeclaration,
            processedDeclaration,
            metadataDeclaration,
            policy.payloadDeclaration,
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
            CaptureFileWriteRequest(
                data: metadata.data,
                path: CaptureStorePath(
                    RoomPlanEvidenceArtifactBuilder.metadataPath
                )
            ),
            CaptureFileWriteRequest(
                data: policy.data,
                path: CaptureStorePath(
                    CoordinateSpacePolicyPackage.path
                )
            ),
        ]

        // One reservation for the whole logical transaction: the five
        // canonical files are written by a single writer batch and must
        // not be double-counted as split-package pending writes.
        let admissionReservation = try reserveAdmission(
            bytes: writes.reduce(0) { $0 + $1.data.count }
        )
        defer { releaseAdmission(admissionReservation) }

        try await writer.writeBatchIfIdentical(writes)

        // The store actor may re-enter while awaiting the writer actor.
        // Another exact transaction can commit first; accept only that exact
        // replay. Any different logical authority remains fail-closed.
        if let existingTiming = timingDocument,
           let existingRaw = rawRoomPlanDescriptor,
           let existingProcessed = processedRoomPlanDescriptor,
           let existingMetadata = capturedRoomMetadata,
           let existingPolicy = coordinateSpacePolicy
        {
            if existingTiming == timingPackage.document,
               existingRaw == raw.descriptor,
               existingProcessed == processed.descriptor,
               existingMetadata == metadata.document,
               existingPolicy == policy.document
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
              capturedRoomMetadata == nil,
              coordinateSpacePolicy == nil,
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
        capturedRoomMetadata = metadata.document
        coordinateSpacePolicy = policy.document
    }

    public func rollbackAcceptedEndTransaction(
        removeOwnedMesh: Bool
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

        guard sessionFoundation != nil,
              let expectedTiming = timingDocument,
              let expectedRaw = rawRoomPlanDescriptor,
              let expectedProcessed = processedRoomPlanDescriptor,
              let expectedMetadata = capturedRoomMetadata,
              let expectedPolicy = coordinateSpacePolicy,
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

        let metadataData = try Data(
            contentsOf: payloadURL(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        )
        guard
            let decodedMetadata =
                try? JSONDecoder().decode(
                    CapturedRoomMetadataDocument.self,
                    from: metadataData
                ),
            decodedMetadata == expectedMetadata
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        let policyData = try Data(
            contentsOf: payloadURL(
                CoordinateSpacePolicyPackage.path
            )
        )
        guard
            let decodedPolicy =
                try? JSONDecoder().decode(
                    CoordinateSpacePolicyDocument.self,
                    from: policyData
                ),
            decodedPolicy == expectedPolicy
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

        let metadataDeclaration =
            roomPlanMetadataDeclaration(
                raw: expectedRaw,
                processed: expectedProcessed
            )
        let policyDeclaration =
            BundlePayloadDeclaration(
                path: CoordinateSpacePolicyPackage.path,
                mediaType: "application/json",
                producer: "capture_session",
                provenanceClass: .captureAppDerived,
                role: .canonical
            )

        var declarationsToRemove = [
            timingDeclaration,
            rawDeclaration,
            processedDeclaration,
            metadataDeclaration,
            policyDeclaration,
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
            CaptureFileWriteRequest(
                data: metadataData,
                path: CaptureStorePath(
                    RoomPlanEvidenceArtifactBuilder
                        .metadataPath
                )
            ),
            CaptureFileWriteRequest(
                data: policyData,
                path: CaptureStorePath(
                    CoordinateSpacePolicyPackage.path
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
              capturedRoomMetadata == expectedMetadata,
              coordinateSpacePolicy == expectedPolicy,
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
        capturedRoomMetadata = nil
        coordinateSpacePolicy = nil

        if removeOwnedMesh {
            meshIndex = nil
            meshAnchorCount = nil
            usableMeshAnchorCount = nil
        }
    }

    public func persistRawRoomPlan(
        _ payload: RoomPlanRawArtifactPayload
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

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

        // The lineage document commits alongside the raw artifact so the
        // RoomPlan session/coordinate/runtime authority survives
        // finalization even if no processed artifact ever lands (issue
        // #152). A later processed commit replaces these exact bytes with
        // the full raw+processed lineage document.
        let metadata = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: identity.captureRevisionID,
            raw: descriptor,
            processed: nil
        )

        // RoomCaptureView can deliver the same completion payload more than
        // once around stop()/review transition. Validate the replay bytes
        // first, then treat an exact descriptor replay as harmless.
        if let existing = rawRoomPlanDescriptor {
            if existing == descriptor,
               capturedRoomMetadata == metadata.document
            {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.rawPath
            )
        }

        let declaration = BundlePayloadDeclaration(
            path: descriptor.relativePath,
            mediaType: "application/json",
            producer: "roomplan_capture",
            provenanceClass: .appleRoomPlanRawScan,
            role: .canonical
        )
        let metadataDeclaration = roomPlanMetadataDeclaration(
            raw: descriptor,
            processed: nil
        )

        // One reservation covering the raw artifact plus its derived
        // lineage document before either becomes queued writer work
        // (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: payload.data.count + metadata.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        try await writer.writeBatchIfIdentical([
            CaptureFileWriteRequest(
                data: payload.data,
                path: try CaptureStorePath(descriptor.relativePath)
            ),
            CaptureFileWriteRequest(
                data: metadata.data,
                path: try CaptureStorePath(
                    RoomPlanEvidenceArtifactBuilder.metadataPath
                )
            ),
        ])

        // Re-check after the writer-actor suspension: an identical
        // reentrant commit is idempotent; any other authority fails.
        if let existing = rawRoomPlanDescriptor {
            if existing == descriptor,
               capturedRoomMetadata == metadata.document
            {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.rawPath
            )
        }

        try register(declaration)
        try register(metadataDeclaration)
        rawRoomPlanDescriptor = descriptor
        capturedRoomMetadata = metadata.document
    }

    public func persistProcessedRoomPlan(
        _ payload: RoomPlanProcessedArtifactPayload
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

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

        // The lineage document derives deterministically from the
        // validated descriptors, so a repeated call always produces
        // byte-identical metadata.
        let metadata = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: identity.captureRevisionID,
            raw: raw,
            processed: descriptor,
            summary: payload.metadataSummary
        )

        // Match raw RoomPlan replay semantics after validating bytes and
        // lineage. Exact duplicate completion is idempotent; a conflicting
        // canonical payload is rejected.
        if let existing = processedRoomPlanDescriptor {
            if existing == descriptor,
               capturedRoomMetadata == metadata.document
            {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.processedPath
            )
        }

        // The raw commit already wrote a raw-only lineage document. Rebuild
        // its exact bytes and remove only those bytes so the full
        // raw+processed document can take the canonical path. The in-memory
        // document is compared against a deterministic rebuild and the
        // declaration is re-verified, so nothing this attempt did not own
        // can be removed.
        guard let previousMetadata = capturedRoomMetadata else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        let previous = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: identity.captureRevisionID,
            raw: raw,
            processed: nil
        )
        guard previousMetadata == previous.document else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        let previousMetadataDeclaration =
            roomPlanMetadataDeclaration(
                raw: raw,
                processed: nil
            )
        guard declarations[previousMetadataDeclaration.path]
                == previousMetadataDeclaration
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        // Reserve the processed payload plus upgraded lineage document
        // before either becomes queued writer work (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: payload.data.count + metadata.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        let removedOrAbsent = try await writer.removeIfIdentical(
            previous.data,
            at: CaptureStorePath(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        )
        guard removedOrAbsent else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        // Re-check after the writer-actor suspension: no other commit may
        // have advanced RoomPlan authority while the old bytes were
        // removed.
        guard processedRoomPlanDescriptor == nil,
              capturedRoomMetadata == previousMetadata,
              declarations[previousMetadataDeclaration.path]
                == previousMetadataDeclaration
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

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
        let metadataDeclaration = roomPlanMetadataDeclaration(
            raw: raw,
            processed: descriptor
        )

        // Processed RoomPlan and its upgraded lineage metadata commit as
        // one writer-actor batch: a failure rolls back only files created
        // by this attempt and never deletes pre-existing conflicting
        // bytes. A retry after a failed batch is safe because state
        // mutation only happens after the last suspension point.
        do {
            try await writer.writeBatchIfIdentical([
                CaptureFileWriteRequest(
                    data: payload.data,
                    path: try CaptureStorePath(descriptor.relativePath)
                ),
                CaptureFileWriteRequest(
                    data: metadata.data,
                    path: try CaptureStorePath(
                        RoomPlanEvidenceArtifactBuilder.metadataPath
                    )
                ),
            ])
        } catch {
            // The raw-only lineage document was removed above to clear
            // the canonical path. Restore exactly those attempt-owned
            // bytes so a failed processed commit leaves the verified
            // raw+metadata state recoverable instead of a gap that
            // would fail integrity verification.
            try? await writer.writeIfIdentical(
                previous.data,
                to: CaptureStorePath(
                    RoomPlanEvidenceArtifactBuilder.metadataPath
                )
            )
            throw error
        }

        // Re-check after the writer-actor suspension: an identical
        // reentrant commit is idempotent; any other authority fails.
        if let existing = processedRoomPlanDescriptor {
            if existing == descriptor,
               capturedRoomMetadata == metadata.document
            {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                RoomPlanEvidenceArtifactBuilder.processedPath
            )
        }

        guard capturedRoomMetadata == previousMetadata else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }

        try register(declaration)
        declarations[metadataDeclaration.path] = metadataDeclaration
        processedRoomPlanDescriptor = descriptor
        capturedRoomMetadata = metadata.document
    }

    public func persistMeshPackage(
        _ package: MeshEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        // One reservation for the whole mesh package: the index plus
        // every geometry blob is one logical pending write, not one
        // admission item per canonical file (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: package.indexData.count
                + package.geometryFiles.reduce(0) {
                    $0 + $1.data.count
                }
        )
        defer { releaseAdmission(admissionReservation) }

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

        // Decode each committed geometry blob once at persistence time
        // (issue #169): the record's counts must match the actual blob,
        // and only anchors carrying real geometric primitives count as
        // usable. An anchor object with zero faces or zero vertices must
        // never satisfy a mesh requirement.
        var usableAnchors = 0
        for record in package.index.anchors {
            guard
                let file = filesByPath[record.geometryPath],
                let geometry = try? MeshBinaryCodec.decode(
                    file.data
                ),
                geometry.vertices.count == record.vertexCount,
                geometry.faceCount == record.faceCount
            else {
                throw CaptureWorkingSetError.invalidMeshPackage
            }
            if !geometry.vertices.isEmpty, geometry.faceCount > 0 {
                usableAnchors += 1
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
        usableMeshAnchorCount = usableAnchors
        meshIndex = package.index
    }

    public func rollbackCurrentMeshPackage() async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

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
        usableMeshAnchorCount = nil
    }

    public func persistFramePackage(
        _ package: FrameEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        // Reserve the whole frame package — descriptor, pixel, depth,
        // and derived preview payloads — before any of it becomes
        // queued writer work (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: package.descriptorData.count
                + package.pixelPayload.count
                + (package.depthPayload?.count ?? 0)
                + (package.previewPayload?.count ?? 0)
        )
        defer { releaseAdmission(admissionReservation) }

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

        // Usable-geometry accounting (issue #169): only finite, positive,
        // validity-masked depth samples count. The decode happens once at
        // commit time so quality evaluation never re-parses payloads.
        let usableSamples = Self.usableDepthSamples(
            in: package.depthPayload
        )
        usableDepthSampleCount += usableSamples
        if usableSamples > 0 {
            usableDepthEvidenceCount += 1
        }

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
                appendResourceEvent(
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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

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

    /// Shared validation for the paired annotation+measurement commit:
    /// decodes both packages, enforces the single-coordinate-space
    /// authority rule, binds that space, and derives the manifest
    /// declarations whose provenance must match record-level authority.
    private func validateAnnotationMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage
    ) throws -> (
        annotationDeclaration: BundlePayloadDeclaration,
        measurementDeclaration: BundlePayloadDeclaration
    ) {
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
        return (annotationDeclaration, measurementDeclaration)
    }

    public func persistAnnotationAndMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        // One reservation for the two-file transaction — the canonical
        // annotation and measurement files commit together and share
        // one admission item (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: annotationPackage.data.count
                + measurementPackage.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        let (annotationDeclaration, measurementDeclaration) =
            try validateAnnotationMeasurementPackages(
                annotationPackage: annotationPackage,
                measurementPackage: measurementPackage
            )

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

    /// Replaces the canonical annotation+measurement pair committed
    /// earlier in this revision (issue #163). Unlike
    /// `persistAnnotationAndMeasurementPackages`, which enforces
    /// write-once authority, this path is for the pre-finalization
    /// editor: the working revision is still mutable, so the operator
    /// may correct the committed pair. Both files swap atomically as
    /// one rollback-capable batch — a failed second write restores the
    /// first file's exact bytes — and in-memory authority updates only
    /// after both replacements are durable.
    public func replaceAnnotationAndMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        let admissionReservation = try reserveAdmission(
            bytes: annotationPackage.data.count
                + measurementPackage.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        let (annotationDeclaration, measurementDeclaration) =
            try validateAnnotationMeasurementPackages(
                annotationPackage: annotationPackage,
                measurementPackage: measurementPackage
            )

        // Snapshot pre-write state so a mutation that interleaved across
        // the write suspension is detected instead of silently mixing
        // authorities.
        let priorAnnotations = annotationCollection
        let priorMeasurements = measurementCollection

        try await writer.writeBatchReplacing([
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

        // Re-check after actor suspension: if another mutation committed
        // different authority while the replace was in flight, fail
        // closed rather than publish mixed provenance. Finalization then
        // refuses the working set on a declaration/payload mismatch.
        guard annotationCollection == priorAnnotations,
              measurementCollection == priorMeasurements
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

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

    /// Records one tracking-quality sample into bounded canonical history.
    ///
    /// Consecutive samples sharing one state/reason compact into a single
    /// interval that retains its first and last timestamps, so a scan
    /// sampled every ~250 ms cannot grow the history without bound. A
    /// temporary degraded interval therefore remains visible to quality
    /// evaluation even after tracking recovers before End.
    public func recordTrackingEvent(
        _ event: TrackingQualityEvent
    ) {
        // Non-throwing observation sink: while the working set is sealed
        // for finalization the event is dropped and counted rather than
        // mutating sealed quality inputs (issue #180).
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }

        let timestamp = event.sessionTimestampSeconds
        var index = trackingIntervals.firstIndex {
            $0.firstSeconds > timestamp
        } ?? trackingIntervals.count

        // Merge into the immediately preceding interval when the sample
        // continues the same tracking run (same state and reason).
        if index > 0 {
            let previous = index - 1
            if trackingIntervals[previous].state == event.state,
               trackingIntervals[previous].reason == event.reason
            {
                trackingIntervals[previous].lastSeconds = max(
                    trackingIntervals[previous].lastSeconds,
                    timestamp
                )
                trackingIntervals[previous].sampleCount += 1
                index = previous

                // An out-of-order sample can bridge two runs of the same
                // signature; collapse them into one interval.
                if index + 1 < trackingIntervals.count,
                   trackingIntervals[index + 1].state == event.state,
                   trackingIntervals[index + 1].reason == event.reason
                {
                    let next = trackingIntervals.remove(at: index + 1)
                    trackingIntervals[index].firstSeconds = min(
                        trackingIntervals[index].firstSeconds,
                        next.firstSeconds
                    )
                    trackingIntervals[index].lastSeconds = max(
                        trackingIntervals[index].lastSeconds,
                        next.lastSeconds
                    )
                    trackingIntervals[index].sampleCount +=
                        next.sampleCount
                }
                evictTrackingIntervalsIfNeeded()
                return
            }
        }

        trackingIntervals.insert(
            TrackingInterval(
                state: event.state,
                reason: event.reason,
                firstSeconds: timestamp,
                lastSeconds: timestamp,
                sampleCount: 1
            ),
            at: index
        )
        evictTrackingIntervalsIfNeeded()
    }

    /// Records a declared spatial discontinuity as retained provenance.
    /// v1 binds exactly one coordinate space per revision, so the event
    /// never advances the bound authority: every subsequent record that
    /// carries a different coordinate space still fails closed with
    /// `authorityMismatch`. The caller owns the next space identity
    /// through `CaptureSessionContext.registerDiscontinuity`.
    public func recordCoordinateDiscontinuity(
        to nextCoordinateSpaceID: CoordinateSpaceID,
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double? = nil
    ) throws {
        try requireMutable()

        guard let bound = coordinateSpaceID else {
            throw CaptureWorkingSetError
                .coordinateDiscontinuityRequiresBoundSpace
        }
        guard nextCoordinateSpaceID != bound else {
            throw CaptureWorkingSetError.invalidCoordinateTransition
        }
        if let sessionTimestampSeconds {
            guard sessionTimestampSeconds.isFinite,
                  sessionTimestampSeconds >= 0
            else {
                throw CaptureWorkingSetError
                    .invalidCoordinateTransition
            }
        }
        guard
            coordinateTransitions.count
                < Self.maxCoordinateTransitions
        else {
            throw CaptureWorkingSetError
                .coordinateTransitionLimitExceeded
        }
        coordinateTransitions.append(
            CoordinateSpaceTransition(
                previous: bound,
                next: nextCoordinateSpaceID,
                reason: reason,
                sessionTimestampSeconds: sessionTimestampSeconds
            )
        )
    }

    public func recordResourceEvent(
        _ event: CaptureResourceEvent
    ) {
        // Non-throwing observation sink: while the working set is sealed
        // for finalization the event is dropped and counted rather than
        // mutating sealed quality inputs (issue #180).
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }

        appendResourceEvent(event)
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

        // Quality-facing counts pair raw container counts with the
        // usable-geometry counts (issue #169): a committed mesh anchor
        // with zero faces and a depth map whose samples are all invalid
        // must not satisfy the mesh requirement or the depth fallback.
        // The evaluator prefers the usable counts when present.
        return CaptureQualityEvaluator.evaluate(
            CaptureQualityObservation(
                trackingEvents: trackingEvents,
                roomPlanStatus: roomPlanStatus,
                activeMeshAnchorCount: meshAnchorCount ?? 0,
                evidenceFrameCount: evidenceFrameCount,
                depthEvidenceCount: depthEvidenceCount,
                usableMeshAnchorCount: usableMeshAnchorCount,
                usableDepthSampleCount: usableDepthSampleCount,
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
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

        try await persistQualityReportPayload(report)
    }

    /// Shared canonical quality-payload write used by the public
    /// mutation entry point and by `sealForFinalization` (which is
    /// itself sealed and therefore cannot pass `requireMutable`). Both
    /// paths enforce the same readiness/integrity guards, write the
    /// canonical bytes durably, then register the declaration.
    /// Returns the exact bytes and declaration committed so the seal can
    /// roll back attempt-owned bytes on `unseal`.
    @discardableResult
    private func persistQualityReportPayload(
        _ report: CaptureQualityReport
    ) async throws -> (
        data: Data,
        declaration: BundlePayloadDeclaration
    ) {
        guard report.readyForHTDTIngestion else {
            throw CaptureWorkingSetError.qualityReportNotReady
        }
        guard report.integrityStatus == .pass else {
            throw CaptureWorkingSetError
                .qualityReportIntegrityMissing
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let path = "quality/capture-quality.json"
        let declaration = BundlePayloadDeclaration(
            path: path,
            mediaType: "application/json",
            producer: "capture_quality",
            provenanceClass: .captureAppDerived,
            role: .canonical
        )

        let admissionReservation = try reserveAdmission(
            bytes: data.count
        )
        defer { releaseAdmission(admissionReservation) }

        try await writer.writeIfIdentical(
            data,
            to: CaptureStorePath(path)
        )
        try register(declaration)
        return (data, declaration)
    }

    /// Seals the working set for finalization (issue #180).
    ///
    /// Once this call flips the seal, every mutation entry point fails
    /// with `workingSetSealed`. Mutations that were already inside the
    /// actor are then drained to completion through writer fences —
    /// their commits are part of the sealed state — before the durable
    /// bytes are re-verified, quality is evaluated from exactly that
    /// state, and the matching canonical quality payload is persisted.
    /// The returned snapshot is the sealed declaration/identity state
    /// the host must hand to `BundleRevisionFinalizer`.
    ///
    /// A failure leaves the store mutable again so the capture can
    /// continue (for example when quality is not yet ready). A
    /// successful seal stays in force until `unseal` (pre-promotion
    /// recoverable failure) or `consumeSealedWorkingSet` (promotion).
    public func sealForFinalization(
        requirements: CaptureQualityRequirements = .init()
    ) async throws -> SealedWorkingSet {
        switch sealState {
        case .sealed:
            throw CaptureWorkingSetError.workingSetSealed
        case .consumed:
            throw CaptureWorkingSetError.workingSetConsumed
        case .mutable:
            break
        }
        sealState = .sealed
        sealGeneration += 1
        let generation = sealGeneration
        do {
            // Wait for already-owned writes: suspended mutations resume
            // while this seal parks on the writer fence, finish their
            // commit, and decrement inFlightMutations. New mutations are
            // already rejected by requireMutable(), so the counter only
            // converges to zero.
            while inFlightMutations > 0 {
                await writer.barrier()
                try requireSealHeld(generation)
            }
            try verifyIntegrity()
            let report = evaluateQuality(requirements: requirements)
            guard report.readyForHTDTIngestion else {
                throw CaptureWorkingSetError.qualityReportNotReady
            }
            sealedQualityReport =
                try await persistQualityReportPayload(report)

            // The report write released the actor; drain any mutation
            // that completed during that suspension, then re-verify the
            // durable bytes — now including the canonical quality
            // payload — and snapshot the exact sealed state.
            while inFlightMutations > 0 {
                await writer.barrier()
                try requireSealHeld(generation)
            }
            try requireSealHeld(generation)
            try verifyIntegrity()
            return SealedWorkingSet(
                sealToken: UUID(),
                snapshot: snapshot(),
                qualityReport: report,
                sealedAtUTC: BundleTimestamp.utcString(from: Date())
            )
        } catch {
            // Roll back the seal attempt only while this attempt still
            // owns the lifecycle: remove exactly the canonical quality
            // bytes it persisted, then reopen mutations. If an
            // unseal/consume already transitioned the store while this
            // seal was suspended, leave the committed bytes untouched —
            // they are no longer owned by this attempt.
            if sealState == .sealed, sealGeneration == generation {
                if let sealedReport = sealedQualityReport {
                    if declarations[sealedReport.declaration.path]
                        == sealedReport.declaration
                    {
                        declarations.removeValue(
                            forKey: sealedReport.declaration.path
                        )
                    }
                    try? await writer.removeIfIdentical(
                        sealedReport.data,
                        at: CaptureStorePath(
                            sealedReport.declaration.path
                        )
                    )
                }
                sealedQualityReport = nil
                sealState = .mutable
                sealGeneration += 1
            }
            throw error
        }
    }

    /// Rolls a successful seal back after a pre-promotion recoverable
    /// failure so the host can retry a Review pass. Removes the
    /// canonical quality payload the seal persisted — it described the
    /// sealed state and would be stale once mutations resume — then
    /// reopens mutation entry points. Fails closed and stays sealed
    /// when the sealed report bytes no longer match disk.
    public func unseal() async throws {
        switch sealState {
        case .sealed:
            break
        case .consumed:
            throw CaptureWorkingSetError.workingSetConsumed
        case .mutable:
            throw CaptureWorkingSetError.workingSetNotSealed
        }

        if let sealedReport = sealedQualityReport {
            let removedOrAbsent =
                try await writer.removeIfIdentical(
                    sealedReport.data,
                    at: CaptureStorePath(
                        sealedReport.declaration.path
                    )
                )
            guard removedOrAbsent else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            if declarations[sealedReport.declaration.path]
                == sealedReport.declaration
            {
                declarations.removeValue(
                    forKey: sealedReport.declaration.path
                )
            }
            sealedQualityReport = nil
        }
        sealState = .mutable
        sealGeneration += 1
    }

    /// Marks the sealed working set as permanently consumed after the
    /// host promoted the staged bundle. Terminal: every mutation entry
    /// point rejects with `workingSetConsumed` afterwards and the seal
    /// can no longer be rolled back (issue #180).
    public func consumeSealedWorkingSet() throws {
        switch sealState {
        case .sealed:
            sealState = .consumed
            sealGeneration += 1
            sealedQualityReport = nil
        case .consumed:
            throw CaptureWorkingSetError.workingSetConsumed
        case .mutable:
            throw CaptureWorkingSetError.workingSetNotSealed
        }
    }

    /// Whether the working set is currently sealed for finalization.
    public var isSealedForFinalization: Bool {
        sealState == .sealed
    }

    /// Whether the sealed working set has been permanently consumed by
    /// a successful promotion.
    public var isConsumed: Bool {
        sealState == .consumed
    }

    /// Mutations rejected with a typed error or dropped by the
    /// non-throwing observation sinks since the first seal (issue
    /// #180).
    public var rejectedSealedMutationCount: Int {
        sealedMutationRejectionCount
    }

    public func discardUncommittedQualityReport(
        _ report: CaptureQualityReport
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { inFlightMutations -= 1 }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
        try requireMutable()

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
            capturedRoomMetadata: capturedRoomMetadata,
            coordinateSpacePolicy: coordinateSpacePolicy,
            meshAnchorCount: meshAnchorCount,
            usableMeshAnchorCount: usableMeshAnchorCount,
            evidenceFrameCount: evidenceFrameCount,
            depthEvidenceCount: depthEvidenceCount,
            usableDepthSampleCount: usableDepthSampleCount,
            usableDepthEvidenceCount: usableDepthEvidenceCount,
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
            guard capturedRoomMetadata != nil else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
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
                    == rawRoomPlanDescriptor.sha256,
                  capturedRoomMetadata?.processedSHA256
                    == processedRoomPlanDescriptor.sha256
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

        // The lineage document is committed iff raw RoomPlan evidence is
        // committed, and it records processed lineage iff the processed
        // descriptor is committed.
        if let capturedRoomMetadata {
            guard let rawRoomPlanDescriptor,
                  capturedRoomMetadata.captureSessionID
                    == rawRoomPlanDescriptor.captureSessionID,
                  capturedRoomMetadata.coordinateSpaceID
                    == rawRoomPlanDescriptor.coordinateSpaceID,
                  capturedRoomMetadata.rawPayloadPath
                    == rawRoomPlanDescriptor.relativePath,
                  capturedRoomMetadata.rawSHA256
                    == rawRoomPlanDescriptor.sha256,
                  (
                    capturedRoomMetadata.processedSHA256
                        == nil
                    ) == (processedRoomPlanDescriptor == nil)
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyTypedJSON(
                path: RoomPlanEvidenceArtifactBuilder.metadataPath,
                expected: capturedRoomMetadata,
                actualByPath: actualByPath
            )
        }

        // The coordinate-space policy is committed only by the End
        // RoomPlan transaction, so its presence implies the full end
        // commit and its authority fields must equal the bound authority.
        if let coordinateSpacePolicy {
            guard timingDocument != nil,
                  coordinateSpacePolicy.captureRevisionID
                    == identity.captureRevisionID,
                  coordinateSpacePolicy.captureSessionID
                    == captureSessionID,
                  coordinateSpacePolicy.coordinateSpaceID
                    == coordinateSpaceID
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyTypedJSON(
                path: CoordinateSpacePolicyPackage.path,
                expected: coordinateSpacePolicy,
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

    /// One compacted run of same-state tracking observations.
    private struct TrackingInterval: Sendable, Equatable {
        var state: TrackingQualityState
        var reason: String?
        var firstSeconds: Double
        var lastSeconds: Double
        var sampleCount: Int
    }

    /// Compacted canonical tracking history: each interval contributes its
    /// first observation and (when the run spanned more than one distinct
    /// timestamp) its last observation.
    private var trackingEvents: [TrackingQualityEvent] {
        var events: [TrackingQualityEvent] = []
        events.reserveCapacity(trackingIntervals.count * 2)
        for interval in trackingIntervals {
            events.append(
                TrackingQualityEvent(
                    sessionTimestampSeconds: interval.firstSeconds,
                    state: interval.state,
                    reason: interval.reason
                )
            )
            if interval.lastSeconds > interval.firstSeconds {
                events.append(
                    TrackingQualityEvent(
                        sessionTimestampSeconds: interval.lastSeconds,
                        state: interval.state,
                        reason: interval.reason
                    )
                )
            }
        }
        return events.sorted {
            $0.sessionTimestampSeconds < $1.sessionTimestampSeconds
        }
    }

    /// Keeps the interval history strictly bounded without ever losing the
    /// most recent observation of a tracking state: quality evaluation keys
    /// on state presence, so evicting must preserve at least one interval
    /// per observed state.
    private mutating func evictTrackingIntervalsIfNeeded() {
        while trackingIntervals.count > Self.maxTrackingIntervals {
            var evicted = false
            for index in trackingIntervals.indices.dropLast() {
                let state = trackingIntervals[index].state
                if trackingIntervals.lastIndex(where: {
                    $0.state == state
                }) != index {
                    trackingIntervals.remove(at: index)
                    evicted = true
                    break
                }
            }
            if !evicted {
                trackingIntervals.remove(at: 0)
            }
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

    /// Counts depth samples that carry real geometric information: a
    /// finite, positive depth whose validity-mask entry is set (or whose
    /// payload carries no mask). An undecodable payload contributes zero
    /// usable samples rather than failing persistence — the canonical
    /// bytes remain byte-exact evidence even when no sample is usable
    /// (issue #169).
    private static func usableDepthSamples(
        in payload: Data?
    ) -> Int {
        guard let payload,
              let map = try? DepthBinaryCodec.decode(payload)
        else {
            return 0
        }
        var count = 0
        for index in map.valuesMeters.indices {
            let value = map.valuesMeters[index]
            guard value.isFinite, value > 0 else {
                continue
            }
            if let mask = map.validityMask, mask[index] == 0 {
                continue
            }
            count += 1
        }
        return count
    }

    /// The lineage document declaration must be byte-identical between the
    /// persistence paths and rollback verification, so it is constructed in
    /// exactly one place. A raw-only lineage document references just the
    /// raw artifact; the processed commit swaps in the two-artifact
    /// declaration.
    private func roomPlanMetadataDeclaration(
        raw: RoomPlanRawEvidenceDescriptor,
        processed: RoomPlanProcessedEvidenceDescriptor?
    ) -> BundlePayloadDeclaration {
        var sourceRefs = ["path:\(raw.relativePath)"]
        if let processed {
            sourceRefs.append("path:\(processed.relativePath)")
        }
        return BundlePayloadDeclaration(
            path: RoomPlanEvidenceArtifactBuilder.metadataPath,
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .canonical,
            sourceRefs: sourceRefs
        )
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

    /// Every mutation entry point calls this before doing any work. The
    /// seal path flips `sealState` before it first suspends, so a
    /// mutation that arrives after seal acquisition fails
    /// deterministically with a typed error instead of mutating the
    /// sealed working set (issue #180).
    private func requireMutable() throws {
        switch sealState {
        case .mutable:
            return
        case .sealed:
            sealedMutationRejectionCount += 1
            throw CaptureWorkingSetError.workingSetSealed
        case .consumed:
            sealedMutationRejectionCount += 1
            throw CaptureWorkingSetError.workingSetConsumed
        }
    }

    /// Re-validates that a `sealForFinalization` call still owns the
    /// seal after each suspension: an `unseal`/`consumeSealedWorkingSet`
    /// that ran during a writer fence bumps `sealGeneration`, so the
    /// in-flight seal deterministically aborts instead of returning a
    /// snapshot the store no longer holds (issue #180).
    private func requireSealHeld(_ generation: Int) throws {
        guard sealState == .sealed,
              sealGeneration == generation
        else {
            throw CaptureWorkingSetError.workingSetNotSealed
        }
    }

    /// Current pending-write admission budget, exposed for
    /// diagnostics and tests (issue #147).
    public var admissionBudgetSnapshot: CaptureStoreBudgetSnapshot {
        admissionController.snapshot()
    }

    /// Reserves pending-write budget before a package's bytes become
    /// queued writer work. Exhaustion is a typed
    /// `CaptureStoreAdmissionError` rejection and emits a bounded
    /// `persistence_backlog` diagnostic; sustained pressure emits one
    /// warning diagnostic per transition into the pressured state.
    /// Returns nil for zero-byte calls so cheap paths do not consume
    /// reservation items.
    private func reserveAdmission(
        bytes: Int
    ) throws -> CaptureStoreReservation? {
        guard bytes > 0 else { return nil }
        do {
            let reservation = try admissionController.reserve(
                bytes: bytes
            )
            let budget = admissionController.snapshot()
            let pressured =
                budget.reservedBytes * 2 > budget.maxBytes
                || budget.reservedItems * 2 > budget.maxItems
            if pressured {
                if !backlogPressureActive {
                    backlogPressureActive = true
                    appendResourceEvent(
                        CaptureResourceEvent(
                            kind: .persistenceBacklog,
                            severity: .warning,
                            detail:
                                "reserved_bytes=\(budget.reservedBytes) reserved_items=\(budget.reservedItems)"
                        )
                    )
                }
            } else {
                backlogPressureActive = false
            }
            return reservation
        } catch let error as CaptureStoreAdmissionError {
            appendResourceEvent(
                CaptureResourceEvent(
                    kind: .persistenceBacklog,
                    severity: .error,
                    detail: Self.admissionRejectionDetail(
                        bytes: bytes,
                        error: error
                    )
                )
            )
            throw error
        }
    }

    /// Releases a held reservation. Called from `defer` at every
    /// mutation entry point so success, failure, and cancellation exits
    /// all release deterministically (issue #147).
    private func releaseAdmission(
        _ reservation: CaptureStoreReservation?
    ) {
        guard let reservation else { return }
        // `unknownReservation` can only mean ledger corruption: a held
        // reservation is released exactly once by its own defer.
        try? admissionController.release(reservation)
    }

    private static func admissionRejectionDetail(
        bytes: Int,
        error: CaptureStoreAdmissionError
    ) -> String {
        switch error {
        case .invalidByteCount(let invalid):
            return "admission_rejected invalid_bytes=\(invalid)"
        case .itemLimitExceeded(let maxItems):
            return "admission_rejected requested_bytes=\(bytes) max_items=\(maxItems)"
        case .byteLimitExceeded(
            let requested,
            let reserved,
            let maxBytes
        ):
            return "admission_rejected requested_bytes=\(requested) reserved_bytes=\(reserved) max_bytes=\(maxBytes)"
        case .unknownReservation:
            return "admission_rejected unknown_reservation"
        }
    }

    /// Bounded append for resource diagnostics so persistence and
    /// backlog events cannot grow the observation history without
    /// bound (issues #147/#180).
    private func appendResourceEvent(_ event: CaptureResourceEvent) {
        resourceEvents.append(event)
        if resourceEvents.count > Self.maxResourceEvents {
            resourceEvents.removeFirst(
                resourceEvents.count - Self.maxResourceEvents
            )
        }
    }
}
