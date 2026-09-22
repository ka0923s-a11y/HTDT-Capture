import Foundation

public enum CaptureWorkingSetError: Error, Sendable, Equatable {
    case invalidRawRoomPlanDescriptor
    case invalidProcessedRoomPlanDescriptor
    case processedRoomPlanRequiresRaw
    case processedRoomPlanLineageMismatch
    case invalidMeshPackage
    case invalidAnnotationPackage
    case invalidMeasurementPackage
    case invalidAuthorityPackage
    /// A theater-authority record references an entity that is absent
    /// from the committed/candidate annotation collection, or whose
    /// entity type does not match the reference's contract.
    case unresolvedAuthorityReference(String)
    /// A denormalized authority field disagrees with the canonical
    /// semantic-relation assertion of the same fact (#333/#403): when
    /// both forms are present they must agree.
    case conflictingAuthorityValue(String)
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
    case invalidSupplementalDocument
    case workingSetSealed
    case workingSetNotSealed
    case workingSetConsumed
    /// A spatial evidence link (`path:evidence/frames/<id>.json`,
    /// `frame:<uuid>`, `mesh_anchor:<uuid>`, or a placement's
    /// `source_mesh_anchor_id`) cannot be resolved to committed
    /// frame/mesh authority, so its coordinate-space congruence can
    /// never be proven (issue #199).
    case unresolvableSpatialEvidenceLink(String)
    /// A spatial evidence link resolves to committed frame/mesh
    /// authority expressed in a different coordinate space than the
    /// record referencing it (issue #199).
    case spatialEvidenceSpaceMismatch(String)
    /// A benchmark reference failed the immutable/versioned
    /// `slug@semver` grammar and was rejected (#285).
    case invalidBenchmarkReference(String)
    /// A task profile failed validation (empty identity, empty
    /// requirement identifier, or invalid counts) (#259).
    case invalidTaskProfile
    /// A capture-strategy payload failed validation — an unknown
    /// `strategy_id`, a policy echo that does not match the published
    /// profile, or an invalid `selected_at` timestamp (#307).
    case invalidCaptureStrategy
    /// `session/revision-state.json` decoded but with a schema or
    /// version this build does not own (issue #297).
    case unsupportedRevisionStateSchema
    /// A relaunch tried to restore a working revision whose phase
    /// marker is absent, undecodable, or still `live_scan_incomplete` —
    /// none of those prove an accepted End boundary (issue #297).
    case workingRevisionNotRecoverable
    /// A mutation that needs live AR authority (frame/depth/mesh
    /// capture, an End transaction, its rollback) reached a working set
    /// restored from disk. Recovered drafts are spatially sealed: their
    /// coordinate authority ended with the process (issue #297).
    case spatialAuthorityNotLive
    /// Finalization was requested on a practice working set. Practice
    /// captures never produce a real bundle (issue #320).
    case practiceWorkingSetNotFinalizable
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
    /// Committed room reference frame document (issue #232), if any.
    public let roomReferenceFrame: RoomReferenceFrameDocument?
    /// Committed room field datum document (issue #232), if any.
    public let roomFieldDatum: RoomFieldDatumDocument?
    /// Committed opening-review document (issue #231), if any.
    public let openingReview: OpeningReviewDocument?
    /// Frame ids committed by the accepted End boundary (issue #241);
    /// these are the non-removable closing observations of the scan.
    public let endBoundaryFrameIDs: [EvidenceFrameID]
    /// Committed capture-strategy document (issue #307), if any.
    public let captureStrategy: CaptureStrategyDocument?
    /// Committed plan-reference underlay document (issue #322), if any.
    public let planUnderlay: PlanUnderlayDocument?
    /// Durable lifecycle phase mirrored to
    /// `session/revision-state.json` (issue #297).
    public let revisionPhase: WorkingRevisionPhase?
    /// False only on a store rebuilt from disk: its AR coordinate
    /// authority ended with the prior process so live spatial mutation
    /// is permanently unavailable (issue #297).
    public let spatialAuthorityLive: Bool
    /// True for a practice-mode working set (issue #320): never
    /// finalizable, never a real capture.
    public let practiceCapture: Bool
    /// Operator field notes committed on this revision (issue #375) —
    /// exposed on the snapshot so sealed Review/finalization paths
    /// read the same collection the checkpoint persists.
    public let fieldNotes: [CaptureFieldNote]
    /// `evidence/frames/<id>.json` of the most recently committed
    /// evidence frame (commit order, not id order) — the default
    /// evidence attachment for a note authored mid-scan (#375).
    public let latestEvidenceDescriptorPath: String?

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
        evidenceFrameRefs: [String],
        roomReferenceFrame: RoomReferenceFrameDocument? = nil,
        roomFieldDatum: RoomFieldDatumDocument? = nil,
        openingReview: OpeningReviewDocument? = nil,
        revisionPhase: WorkingRevisionPhase? = nil,
        spatialAuthorityLive: Bool = true,
        practiceCapture: Bool = false,
        endBoundaryFrameIDs: [EvidenceFrameID] = [],
        fieldNotes: [CaptureFieldNote] = [],
        latestEvidenceDescriptorPath: String? = nil,
        captureStrategy: CaptureStrategyDocument? = nil,
        planUnderlay: PlanUnderlayDocument? = nil
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
        self.roomReferenceFrame = roomReferenceFrame
        self.roomFieldDatum = roomFieldDatum
        self.openingReview = openingReview
        self.revisionPhase = revisionPhase
        self.spatialAuthorityLive = spatialAuthorityLive
        self.practiceCapture = practiceCapture
        self.endBoundaryFrameIDs = endBoundaryFrameIDs
        self.fieldNotes = fieldNotes
        self.latestEvidenceDescriptorPath =
            latestEvidenceDescriptorPath
        self.captureStrategy = captureStrategy
        self.planUnderlay = planUnderlay
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

/// One unresolved or space-mismatched spatial evidence link on a
/// committed record (issue #236). Reported — never silently repaired —
/// so the host can name the dangling reference for repair.
public struct SpatialEvidenceIssue:
    Sendable,
    Equatable
{
    public let owner: String
    public let ref: String
    public let reason: String

    public init(owner: String, ref: String, reason: String) {
        self.owner = owner
        self.ref = ref
        self.reason = reason
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
    public nonisolated let rootDirectory: URL

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
    /// Committed supplemental-document bytes keyed by bundle path —
    /// the write-once ledger for feature payloads committed through
    /// `persistSupplementalDocument` (issues #222/#226/#227/#240/
    /// #249/#293).
    private var supplementalDocuments: [String: Data] = [:]
    private var authorityCollection: TheaterAuthorityCollection?
    private var annotationKeysPresent: Set<String> = []
    private var measurementQuantityTypesPresent: Set<String> = []
    /// User-confirmed room reference frame (issue #232), iff committed.
    private var roomReferenceFrame: RoomReferenceFrameDocument?
    /// Operator-declared field/install datum (issue #232), iff
    /// committed.
    private var roomFieldDatum: RoomFieldDatumDocument?
    /// Operator opening-review document (issue #231), iff committed.
    private var openingReviewDocument: OpeningReviewDocument?
    /// Frames committed by an accepted End boundary (issue #241). The
    /// marker is in-memory host bookkeeping — cleared when the End
    /// transaction is rolled back by Continue scanning — and never a
    /// persisted field, so it carries no cross-launch semantics.
    private var endBoundaryFrameIDs: Set<EvidenceFrameID> = []
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

    // Advisory/provenance state (#223, #259, #260, #268, #277, #284,
    // #285). None of it feeds canonical geometry; it is persisted as a
    // derived payload at seal and rendered in Review.
    private var depthSufficiencyAccumulator =
        DepthSufficiencyAccumulator()
    private var meshGeometryProfile = MeshGeometryProfile()
    private var roomPlanGuidanceTracker = RoomPlanGuidanceTracker()
    private var meshLifecycleTracker = MeshAnchorLifecycleTracker()
    private var advisoryEndContext: CaptureEndCoverageSummary?
    private var roomPlanGuidanceAvailable = false
    private var taskProfile: CaptureTaskProfile?
    private var skippedTaskRequirementIDs: Set<String> = []
    /// The persisted `session/capture-strategy.json` document, iff the
    /// host committed a strategy selection for this revision (#307).
    private var captureStrategyDocument: CaptureStrategyDocument?
    private var planUnderlayDocument: PlanUnderlayDocument?
    private var benchmarkRefs: [String] = []
    /// Advisory provenance notes recorded by the operator or capture
    /// policies; persisted at `advisory/operator-advisories.json` and
    /// surfaced to quality evaluation as advisory findings.
    private var advisoryNotes: [CaptureAdvisoryNote] = []
    /// Operator field notes bound to this revision (issue #375);
    /// persisted at `session/field-notes.json` as a canonical
    /// user-annotation payload and carried into the finalized bundle.
    private var fieldNotes: [CaptureFieldNote] = []
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
    /// counter to zero — suspending on `mutationDrainers` until the last
    /// mutation's defer decrements it — before verifying and
    /// snapshotting, so the sealed state deterministically contains
    /// every write that was already owned (issue #180).
    private var inFlightMutations = 0
    /// Canonical quality payload bytes plus declaration persisted by the
    /// active seal, retained so `unseal` can roll back exactly the bytes
    /// the seal committed.
    private var sealedQualityReport:
        (data: Data, declaration: BundlePayloadDeclaration)?
    /// The advisory payload written inside the seal (#223). Rolled
    /// back with the quality report if the seal is lifted.
    private var sealedAdvisoryReport:
        (data: Data, declaration: BundlePayloadDeclaration)?
    /// Mutations rejected or dropped since the first seal: typed-error
    /// rejections from throwing entry points and drops from the
    /// non-throwing observation sinks. Exposed for diagnostics because
    /// the non-throwing sinks cannot surface the typed error.
    private var sealedMutationRejectionCount = 0

    /// Durable lifecycle phase mirrored to
    /// `session/revision-state.json` (issue #297). Written
    /// `liveScanIncomplete` at foundation commit, `endAccepted` inside
    /// the End RoomPlan transaction, `semanticAuthoring` on the first
    /// post-End semantic commit, `readyToFinalize` inside the seal.
    private var revisionPhase: WorkingRevisionPhase =
        .liveScanIncomplete
    /// Phase the store held when the current seal was taken, so
    /// `unseal` restores the truthful marker rather than a guess.
    private var phaseBeforeSeal: WorkingRevisionPhase?
    /// False only on a store rebuilt from disk by
    /// `restoreWorkingRevision` (issue #297): its AR coordinate
    /// authority ended with the prior process, so every mutation that
    /// presumes live spatial authority fails closed.
    private var liveSpatialAuthority = true
    /// Advisory RoomPlan coaching history recovered from the phase
    /// checkpoint; used instead of the empty tracker's history so a
    /// restored draft does not report scan-time guidance as absent.
    private var recoveredRoomPlanGuidance: RoomPlanGuidanceSummary?
    /// Recovered mesh-anchor lifecycle summary, same rationale.
    private var recoveredMeshLifecycle: MeshAnchorLifecycleSummary?
    /// Practice-mode marker (issue #320): practice working sets write
    /// the flag into `session/revision-state.json` and refuse
    /// `sealForFinalization`, so a rehearsal can never produce a real
    /// bundle or pass the inventory as a real draft.
    private let isPracticeWorkingSet: Bool
    /// Suspended seal drains waiting for `inFlightMutations` to reach
    /// zero. Resumed by the last mutation exit — a direct wakeup instead
    /// of a writer-actor fence poll, which could starve queued writes
    /// under the actor executor's non-FIFO job scheduling (issue #180).
    private var mutationDrainers: [CheckedContinuation<Void, Never>] = []

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
    /// Deterministic bound on operator/policy advisory provenance
    /// notes (#216/#257/#273/#274). Each note is a bounded record; a
    /// count far beyond this indicates abuse rather than legitimate
    /// scan annotations.
    public static let maxAdvisoryNotes = 128
    /// Deterministic bound on operator field notes (#375).
    public static let maxFieldNotes = 256

    public init(
        identity: CaptureWorkingSetIdentity = CaptureWorkingSetIdentity(),
        rootDirectory: URL,
        admissionController: CaptureStoreAdmissionController? = nil,
        practice: Bool = false
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
        self.isPracticeWorkingSet = practice
    }

    public func persistSessionFoundation(
        _ package: CaptureSessionFoundationPackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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

        // The session/coordinate binding is part of the logical commit
        // (issue #202): validate the proposed authority now, but publish
        // it only after the foundation files are durable. A failed write
        // leaves the working set's identity exactly as it was.
        try validateAuthority(
            captureSessionID: package.session.captureSessionID,
            coordinateSpaceID: package.session.coordinateSpaceID
        )

        // The foundation is write-once authority and its four canonical
        // files are one recoverable transaction (issue #203): an
        // identical replay is idempotent, and any other package on a
        // committed foundation is a conflicting canonical payload.
        // Detecting a committed foundation before writing means a
        // reentrant attempt never treats a partial-write artifact as a
        // new commit.
        if let existing = sessionFoundation {
            if existing == package {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                CaptureSessionFoundationPackage.sessionPath
            )
        }
        if let conflicting = package.payloadDeclarations.first(where: {
            declarations[$0.path] != nil
                && declarations[$0.path] != $0
        }) {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(conflicting.path)
        }

        // All four files commit as one writer-actor batch: files this
        // attempt creates roll back on a mid-write failure,
        // byte-identical leftovers from an interrupted attempt are
        // adopted, and conflicting pre-existing bytes fail closed.
        // The revision phase marker (issue #297) joins the same batch so
        // every working revision is born with a durable, atomic
        // `live_scan_incomplete` record — a relaunch never has to guess
        // whether a directory died before or after its first commit.
        let phaseDocument = revisionStateDocument(
            phase: .liveScanIncomplete
        )
        let phaseWrite = try CaptureFileWriteRequest(
            data: phaseDocument.encoded(),
            path: CaptureStorePath(WorkingRevisionStateDocument.path)
        )
        try await package.persist(
            using: writer,
            additionalFileWrites: [phaseWrite]
        )

        // The store actor may have re-entered while the writer ran: an
        // identical reentrant commit is harmless, anything else fails
        // closed rather than mixing foundation authority.
        if let existing = sessionFoundation {
            if existing == package {
                return
            }
            throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                CaptureSessionFoundationPackage.sessionPath
            )
        }
        guard package.payloadDeclarations.allSatisfy({
            declarations[$0.path] == nil
                || declarations[$0.path] == $0
        }) else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    CaptureSessionFoundationPackage.sessionPath
                )
        }

        // No suspension points below: identity binding, all four
        // declarations, and the foundation record publish as one
        // logical commit — never a subset of the foundation files
        // (issues #202/#203).
        try publishAuthority(
            captureSessionID: package.session.captureSessionID,
            coordinateSpaceID: package.session.coordinateSpaceID
        )
        for declaration in package.payloadDeclarations {
            declarations[declaration.path] = declaration
        }
        try register(phaseDocument.payloadDeclaration)
        revisionPhase = .liveScanIncomplete
        sessionFoundation = package
    }

    public func persistTimingPackage(
        _ package: CaptureTimingPackage
    ) async throws {
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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
        try requireLiveSpatialAuthority()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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

        // Validate the proposed authority without mutating it: the
        // binding publishes only inside the post-write commit block so a
        // failed transaction cannot leave ghost identity (issue #202).
        try validateAuthority(
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
        // authority atomically after every required file is durable. The
        // session/coordinate binding publishes first: if a reentrant
        // commit bound a different authority while this transaction was
        // suspended, publication fails closed instead of rebinding the
        // revision (issue #202).
        try publishAuthority(
            captureSessionID: raw.descriptor.captureSessionID,
            coordinateSpaceID: raw.descriptor.coordinateSpaceID
        )
        for declaration in transactionDeclarations {
            declarations[declaration.path] = declaration
        }
        timingDocument = timingPackage.document
        rawRoomPlanDescriptor = raw.descriptor
        processedRoomPlanDescriptor = processed.descriptor
        capturedRoomMetadata = metadata.document
        coordinateSpacePolicy = policy.document

        // Durable phase transition (issue #297): the marker flips to
        // `end_accepted` only after every End file is durable and bound,
        // and the rewrite re-verifies post-suspension that a racing
        // rollback did not lift the commit mid-write.
        try await persistRevisionState(
            .endAccepted,
            commitCheck: { [self] in
                guard timingDocument == timingPackage.document,
                      rawRoomPlanDescriptor == raw.descriptor,
                      processedRoomPlanDescriptor
                        == processed.descriptor,
                      coordinateSpacePolicy == policy.document
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
            }
        )
    }

    public func rollbackAcceptedEndTransaction(
        removeOwnedMesh: Bool
    ) async throws {
        try requireMutable()
        // Rollback is the live "Continue scanning" path: it must never
        // run on a store restored from disk (issue #297).
        try requireLiveSpatialAuthority()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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
        // The End boundary that marked closing frames no longer exists;
        // its markers must not outlive the accepted transaction
        // (issue #241).
        endBoundaryFrameIDs = []
        // The accepted End context is likewise part of that boundary:
        // keeping it would let a resumed scan advertise coverage for a
        // transaction that was rolled back (issue #297).
        advisoryEndContext = nil

        if removeOwnedMesh {
            meshIndex = nil
            meshAnchorCount = nil
            usableMeshAnchorCount = nil
        }

        // Roll the durable marker back to `live_scan_incomplete` — the
        // revision once again belongs to a live scan, and a relaunch
        // must not reopen it as a draft. The rewrite verifies
        // post-suspension that no End transaction committed meanwhile.
        try await persistRevisionState(.liveScanIncomplete) { [self] in
            guard timingDocument == nil,
                  rawRoomPlanDescriptor == nil,
                  processedRoomPlanDescriptor == nil,
                  coordinateSpacePolicy == nil
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
        }
    }

    public func persistRawRoomPlan(
        _ payload: RoomPlanRawArtifactPayload
    ) async throws {
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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

        // Validate without mutating: the binding publishes only after
        // the raw artifact and lineage document are durable (issue
        // #202).
        try validateAuthority(
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
        guard declarations[declaration.path] == nil
                || declarations[declaration.path] == declaration,
              declarations[metadataDeclaration.path] == nil
                || declarations[metadataDeclaration.path]
                    == metadataDeclaration
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    descriptor.relativePath
                )
        }

        // No suspension points below: identity binding, declarations,
        // and logical state publish as one commit (issue #202).
        try publishAuthority(
            captureSessionID: descriptor.captureSessionID,
            coordinateSpaceID: descriptor.coordinateSpaceID
        )
        declarations[declaration.path] = declaration
        declarations[metadataDeclaration.path] = metadataDeclaration
        rawRoomPlanDescriptor = descriptor
        capturedRoomMetadata = metadata.document
    }

    public func persistProcessedRoomPlan(
        _ payload: RoomPlanProcessedArtifactPayload
    ) async throws {
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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
            // Bounded world-space geometry profile for the advisory
            // RoomPlan/mesh consistency check (#277).
            meshGeometryProfile.record(
                worldFromAnchor: record.worldFromAnchor,
                geometry: geometry
            )
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
            // Validate without mutating: the authority binding publishes
            // only inside the post-write commit block (issue #202).
            try validateAuthority(
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

        // No suspension points below: the authority binding, geometry
        // declarations, and mesh index publish as one commit (issue
        // #202). An empty-anchor package binds nothing new.
        if let first = package.index.anchors.first {
            try publishAuthority(
                captureSessionID: first.captureSessionID,
                coordinateSpaceID: first.coordinateSpaceID
            )
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
        defer { mutationDidFinish() }

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
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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

        // Validate without mutating: the session/coordinate binding
        // publishes only after the canonical frame files are durable, so
        // a failed write cannot leave uncommitted authority (issue
        // #202).
        try validateAuthority(
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
        if let duplicate = package.canonicalPayloadDeclarations
            .first(where: {
                declarations[$0.path] != nil
                    && declarations[$0.path] != $0
            })
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(duplicate.path)
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
        guard package.canonicalPayloadDeclarations.allSatisfy({
            declarations[$0.path] == nil
                || declarations[$0.path] == $0
        }) else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(package.descriptorPath)
        }

        // No suspension points below: the authority binding, canonical
        // declarations, and frame state publish as one commit (issue
        // #202).
        try publishAuthority(
            captureSessionID: package.descriptor.captureSessionID,
            coordinateSpaceID: package.descriptor.coordinateSpaceID
        )
        for declaration in package.canonicalPayloadDeclarations {
            declarations[declaration.path] = declaration
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

        // Bounded depth-sufficiency accumulation (#284): the decoded
        // payload statistics (valid/spatial/confidence distribution)
        // feed the versioned fallback gate and the advisory payload.
        if let depthData = package.depthPayload,
           let depth = try? DepthBinaryCodec.decode(depthData)
        {
            let confidence = package.confidencePayload
                .flatMap { try? ConfidenceBinaryCodec.decode($0) }
            depthSufficiencyAccumulator.record(
                depth: depth,
                confidence: confidence
            )
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
        try requireLiveSpatialAuthority()
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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
    /// authority rule, validates the proposed space binding without
    /// mutating it (issue #202 — callers publish it inside their
    /// post-write commit block), and derives the manifest declarations
    /// whose provenance must match record-level authority.
    private func validateAnnotationMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage
    ) throws -> (
        annotationDeclaration: BundlePayloadDeclaration,
        measurementDeclaration: BundlePayloadDeclaration,
        coordinateSpaceID: CoordinateSpaceID?
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
        let packageSpace =
            annotationSpaces.union(measurementSpaces).first
        if let packageSpace {
            try validateCoordinateAuthority(packageSpace)
        }

        // Issue #199: every spatial evidence link must resolve to
        // committed frame/mesh authority expressed in the record's own
        // coordinate space — manifest membership of both space IDs is
        // not sufficient.
        for entity in annotationPackage.collection.entities {
            try requireSpatialEvidenceCongruence(entity: entity)
        }
        for measurement in measurementPackage.collection.measurements {
            try requireSpatialEvidenceCongruence(
                measurement: measurement
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
        return (
            annotationDeclaration,
            measurementDeclaration,
            packageSpace
        )
    }

    /// Decodes the theater-authorities payload back, binds every entity
    /// reference it carries to the committed/candidate entity set, and
    /// checks each record's own coordinate space against committed
    /// frame/mesh authority. The single-space policy matches
    /// `validateAnnotationMeasurementPackages`.
    private func validateTheaterAuthorityPackage(
        _ authorityPackage: TheaterAuthorityPackage,
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation]
    ) throws -> (
        authorityDeclaration: BundlePayloadDeclaration,
        coordinateSpaceID: CoordinateSpaceID?
    ) {
        guard
            let decoded = try? JSONDecoder().decode(
                TheaterAuthorityCollection.self,
                from: authorityPackage.data
            ),
            decoded == authorityPackage.collection
        else {
            throw CaptureWorkingSetError.invalidAuthorityPackage
        }
        let collection = authorityPackage.collection

        try validateAuthorityEntityReferences(
            collection,
            entities: entities,
            relations: relations
        )
        for snapshot in collection.roomStateSnapshots {
            guard snapshot.captureRevisionID
                    == identity.captureRevisionID
            else {
                throw CaptureWorkingSetError.authorityMismatch
            }
        }

        var spaces = Set<CoordinateSpaceID>()
        func requireBindingCongruence(
            _ binding: SurfaceRegionBinding
        ) throws {
            spaces.insert(binding.coordinateSpaceID)
            for ref in binding.evidenceRefs {
                try requireSpatialEvidenceLinkCongruence(
                    ref,
                    coordinateSpaceID: binding.coordinateSpaceID
                )
            }
            if let anchorID = binding.meshAnchorID {
                try requireMeshAnchorLinkCongruence(
                    anchorID,
                    ref: "mesh_anchor:\(anchorID.uuidString.lowercased())",
                    coordinateSpaceID: binding.coordinateSpaceID
                )
            }
        }
        for record in collection.surfaceSemantics {
            try requireBindingCongruence(record.binding)
        }
        for record in collection.surfaceConstructions {
            try requireBindingCongruence(record.binding)
        }
        for record in collection.problemSurfaces {
            try requireBindingCongruence(record.binding)
        }
        for record in collection.constructionFeatures {
            try requireBindingCongruence(record.binding)
        }
        for record in collection.furnitureSemantics {
            if let binding = record.binding {
                try requireBindingCongruence(binding)
            }
        }
        for record in collection.speakerInstallations {
            if let binding = record.hostSurface {
                try requireBindingCongruence(binding)
            }
        }
        for item in collection.inventoryItems {
            if let space = item.coordinateSpaceID {
                spaces.insert(space)
                for ref in item.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: space
                    )
                }
            }
        }
        for placement in collection.rackPlacements {
            if let space = placement.coordinateSpaceID {
                spaces.insert(space)
                for ref in placement.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: space
                    )
                }
            }
        }
        for observation in collection.roomStateObservations {
            if let space = observation.coordinateSpaceID {
                spaces.insert(space)
                for ref in observation.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: space
                    )
                }
            }
        }
        for record in collection.routingVerifications {
            if let space = record.coordinateSpaceID {
                spaces.insert(space)
                for ref in record.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: space
                    )
                }
            }
        }
        for record in collection.projectorCommissionings {
            if let space = record.coordinateSpaceID {
                spaces.insert(space)
                for ref in record.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: space
                    )
                }
            }
        }
        for record in collection.installationAlignments {
            spaces.insert(record.coordinateSpaceID)
            for ref in record.evidenceRefs {
                try requireSpatialEvidenceLinkCongruence(
                    ref,
                    coordinateSpaceID: record.coordinateSpaceID
                )
            }
            if let alignment = record.alignment {
                for ref in alignment.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID: record.coordinateSpaceID
                    )
                }
            }
        }
        guard spaces.count <= 1 else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        let authoritySpace = spaces.first
        if let authoritySpace {
            try validateCoordinateAuthority(authoritySpace)
        }
        let declaration = BundlePayloadDeclaration(
            path: TheaterAuthorityPackage.path,
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical
        )
        return (declaration, authoritySpace)
    }

    /// Entity-reference checks that bind authority records to committed
    /// annotation entities: the target must exist and, where the record
    /// contract names an entity kind, carry the matching entity type.
    /// Relation endpoints resolve here too (#403): the `inventory_item`
    /// namespace points at this collection's `inventoryItems`, and a
    /// denormalized `host_rack_entity_id` must agree with the canonical
    /// `member_of_rack` relation when both are present (#333).
    private func validateAuthorityEntityReferences(
        _ collection: TheaterAuthorityCollection,
        entities: [CaptureAnnotationEntity],
        relations: [CaptureSemanticRelation]
    ) throws {
        let entityTypes = Dictionary(
            entities.map { ($0.entityID, $0.type) },
            uniquingKeysWith: { first, _ in first }
        )
        func requireEntity(
            _ id: AnnotationEntityID?,
            types: Set<AnnotationEntityType>,
            field: String
        ) throws {
            guard let id else { return }
            guard let type = entityTypes[id],
                  types.isEmpty || types.contains(type)
            else {
                throw CaptureWorkingSetError
                    .unresolvedAuthorityReference(field)
            }
        }
        for observation in collection.roomStateObservations {
            try requireEntity(
                observation.targetEntityID,
                types: [],
                field: "target_entity_id"
            )
        }
        for item in collection.inventoryItems {
            try requireEntity(
                item.hostRackEntityID,
                types: [.equipmentRack],
                field: "host_rack_entity_id"
            )
        }
        for placement in collection.rackPlacements {
            try requireEntity(
                placement.hostRackEntityID,
                types: [.equipmentRack],
                field: "host_rack_entity_id"
            )
        }
        for item in collection.furnitureSemantics {
            try requireEntity(
                item.targetEntityID,
                types: [],
                field: "target_entity_id"
            )
        }
        for record in collection.speakerInstallations {
            try requireEntity(
                record.speakerEntityID,
                types: [.speaker, .subwoofer],
                field: "speaker_entity_id"
            )
        }
        for record in collection.screenSemantics {
            try requireEntity(
                record.screenEntityID,
                types: [.projectionScreen],
                field: "screen_entity_id"
            )
            for id in record.behindScreenSpeakerEntityIDs {
                try requireEntity(
                    id,
                    types: [.speaker, .subwoofer],
                    field: "behind_screen_speaker_entity_ids"
                )
            }
        }
        for record in collection.seatLayouts {
            try requireEntity(
                record.seatEntityID,
                types: [.seat],
                field: "seat_entity_id"
            )
            try requireEntity(
                record.earListeningEntityID,
                types: [.listeningPosition],
                field: "ear_listening_entity_id"
            )
            try requireEntity(
                record.eyeReferenceEntityID,
                types: [.referencePoint],
                field: "eye_reference_entity_id"
            )
        }
        for record in collection.routingVerifications {
            for id in record.speakerEntityIDs {
                try requireEntity(
                    id,
                    types: [.speaker, .subwoofer],
                    field: "speaker_entity_ids"
                )
            }
        }
        for record in collection.projectorCommissionings {
            try requireEntity(
                record.projectorEntityID,
                types: [.projector],
                field: "projector_entity_id"
            )
            try requireEntity(
                record.lensCenterEntityID,
                types: [.projector, .referencePoint, .custom],
                field: "lens_center_entity_id"
            )
        }
        for record in collection.installationAlignments {
            try requireEntity(
                record.finalEntityID,
                types: [],
                field: "final_entity_id"
            )
            try requireEntity(
                record.aimAtEntityID,
                types: [.listeningPosition, .referencePoint, .seat,
                        .measurementPoint],
                field: "aim_at_entity_id"
            )
        }
        try validateRelationAuthorityReferences(
            collection,
            relations: relations
        )
    }

    /// Referential integrity between the annotation relation graph and
    /// the authority collection (#403): every `inventory_item:`
    /// endpoint must resolve to an item committed in this collection,
    /// and a denormalized `host_rack_entity_id` must agree with the
    /// canonical `member_of_rack` relation when both are present
    /// (#333). A nil collection means no inventory exists, so any
    /// `inventory_item:` endpoint dangles.
    private func validateRelationAuthorityReferences(
        _ collection: TheaterAuthorityCollection?,
        relations: [CaptureSemanticRelation]
    ) throws {
        let inventoryIDs = Set(
            (collection?.inventoryItems ?? []).map(\.itemID)
        )
        for relation in relations {
            for endpoint in [relation.subjectRef] + relation.objectRefs
            where endpoint.isInventoryItemRef {
                guard let itemID = endpoint.inventoryItemID,
                      inventoryIDs.contains(itemID)
                else {
                    throw CaptureWorkingSetError
                        .unresolvedAuthorityReference(
                            "relation \(endpoint.rawValue)"
                        )
                }
            }
        }
        for item in collection?.inventoryItems ?? [] {
            guard let host = item.hostRackEntityID else { continue }
            let membershipObjects = relations
                .filter {
                    $0.relationType == .memberOfRack
                        && $0.subjectRef.inventoryItemID == item.itemID
                }
                .flatMap(\.objectRefs)
            if !membershipObjects.isEmpty,
               !membershipObjects.contains(where: {
                   $0.entityID == host
               })
            {
                throw CaptureWorkingSetError
                    .conflictingAuthorityValue(
                        "host_rack_entity_id"
                    )
            }
        }
    }

    public func persistAnnotationAndMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage,
        authorityPackage: TheaterAuthorityPackage? = nil
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        // One reservation for the transaction — the canonical
        // annotation, measurement, and optional authority files commit
        // together and share one admission item (issue #147).
        let admissionReservation = try reserveAdmission(
            bytes: annotationPackage.data.count
                + measurementPackage.data.count
                + (authorityPackage?.data.count ?? 0)
        )
        defer { releaseAdmission(admissionReservation) }

        let (
            annotationDeclaration,
            measurementDeclaration,
            packageSpace
        ) = try validateAnnotationMeasurementPackages(
            annotationPackage: annotationPackage,
            measurementPackage: measurementPackage
        )
        var authorityDeclaration: BundlePayloadDeclaration?
        var authoritySpace: CoordinateSpaceID?
        if let authorityPackage {
            let validated = try validateTheaterAuthorityPackage(
                authorityPackage,
                entities: annotationPackage.collection.entities,
                relations: annotationPackage.collection.relations
            )
            authorityDeclaration = validated.authorityDeclaration
            authoritySpace = validated.coordinateSpaceID
        } else if let authorityCollection {
            // No staged authority package: relation endpoints still
            // resolve against the committed inventory (#403).
            try validateAuthorityEntityReferences(
                authorityCollection,
                entities: annotationPackage.collection.entities,
                relations: annotationPackage.collection.relations
            )
        } else {
            try validateRelationAuthorityReferences(
                nil,
                relations: annotationPackage.collection.relations
            )
        }
        if let packageSpace, let authoritySpace,
           packageSpace != authoritySpace
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        let effectiveSpace = packageSpace ?? authoritySpace

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
        if let authorityPackage,
           let existing = authorityCollection,
           existing != authorityPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    TheaterAuthorityPackage.path
                )
        }
        var expectedDeclarations = [
            annotationDeclaration,
            measurementDeclaration,
        ]
        if let authorityDeclaration {
            expectedDeclarations.append(authorityDeclaration)
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

        var requests = [
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
        ]
        if let authorityPackage {
            requests.append(
                try CaptureFileWriteRequest(
                    data: authorityPackage.data,
                    path: CaptureStorePath(
                        TheaterAuthorityPackage.path
                    )
                )
            )
        }
        try await writer.writeBatchIfIdentical(requests)

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
        if let authorityPackage,
           let existing = authorityCollection,
           existing != authorityPackage.collection
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    TheaterAuthorityPackage.path
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

        // No suspension points below: the coordinate-space binding,
        // declarations, and collection state publish as one commit
        // (issue #202).
        if let effectiveSpace {
            try publishCoordinateAuthority(effectiveSpace)
        }
        for declaration in expectedDeclarations {
            declarations[declaration.path] = declaration
        }
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
        if let authorityPackage {
            authorityCollection = authorityPackage.collection
        }

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Replaces the canonical annotation+measurement pair committed
    /// earlier in this revision (issue #163). Unlike
    /// `persistAnnotationAndMeasurementPackages`, which enforces
    /// write-once authority, this path is for the pre-finalization
    /// editor: the working revision is still mutable, so the operator
    /// may correct the committed pair. Passing `authorityPackage`
    /// swaps `annotations/authorities.json` in the same batch (or
    /// creates it when first authored after the pair); leaving it nil
    /// keeps any committed authorities, re-validating their entity
    /// references against the replacement entities so a deleted entity
    /// cannot leave a dangling authority reference. Committed
    /// authorities are never removed — replace with an empty collection
    /// to clear them. All files swap atomically as one rollback-capable
    /// batch, and in-memory authority updates only after every
    /// replacement is durable.
    public func replaceAnnotationAndMeasurementPackages(
        annotationPackage: AnnotationEvidencePackage,
        measurementPackage: MeasurementEvidencePackage,
        authorityPackage: TheaterAuthorityPackage? = nil
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: annotationPackage.data.count
                + measurementPackage.data.count
                + (authorityPackage?.data.count ?? 0)
        )
        defer { releaseAdmission(admissionReservation) }

        let (
            annotationDeclaration,
            measurementDeclaration,
            packageSpace
        ) = try validateAnnotationMeasurementPackages(
            annotationPackage: annotationPackage,
            measurementPackage: measurementPackage
        )
        var authorityDeclaration: BundlePayloadDeclaration?
        var authoritySpace: CoordinateSpaceID?
        if let authorityPackage {
            let validated = try validateTheaterAuthorityPackage(
                authorityPackage,
                entities: annotationPackage.collection.entities,
                relations: annotationPackage.collection.relations
            )
            authorityDeclaration = validated.authorityDeclaration
            authoritySpace = validated.coordinateSpaceID
        } else if let authorityCollection {
            // An entity removed by this replace must not orphan a
            // committed authority reference; relation endpoints
            // re-resolve against the committed inventory (#403).
            try validateAuthorityEntityReferences(
                authorityCollection,
                entities: annotationPackage.collection.entities,
                relations: annotationPackage.collection.relations
            )
        } else {
            try validateRelationAuthorityReferences(
                nil,
                relations: annotationPackage.collection.relations
            )
        }
        if let packageSpace, let authoritySpace,
           packageSpace != authoritySpace
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        let effectiveSpace = packageSpace ?? authoritySpace

        // Snapshot pre-write state so a mutation that interleaved across
        // the write suspension is detected instead of silently mixing
        // authorities.
        let priorAnnotations = annotationCollection
        let priorMeasurements = measurementCollection
        let priorAuthorities = authorityCollection

        var requests = [
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
        ]
        if let authorityPackage {
            requests.append(
                try CaptureFileWriteRequest(
                    data: authorityPackage.data,
                    path: CaptureStorePath(
                        TheaterAuthorityPackage.path
                    )
                )
            )
        }
        try await writer.writeBatchReplacing(requests)

        // Re-check after actor suspension: if another mutation committed
        // different authority while the replace was in flight, fail
        // closed rather than publish mixed provenance. Finalization then
        // refuses the working set on a declaration/payload mismatch.
        guard annotationCollection == priorAnnotations,
              measurementCollection == priorMeasurements,
              authorityCollection == priorAuthorities
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
        }

        // The replacement stays in the validated space; publishing is a
        // fail-closed re-check in case a different authority committed
        // while the replace was suspended (issue #202).
        if let effectiveSpace {
            try publishCoordinateAuthority(effectiveSpace)
        }
        declarations[annotationDeclaration.path] =
            annotationDeclaration
        declarations[measurementDeclaration.path] =
            measurementDeclaration
        if let authorityDeclaration {
            declarations[authorityDeclaration.path] = authorityDeclaration
        }
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
        if let authorityPackage {
            authorityCollection = authorityPackage.collection
        }

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Persists the derived equipment-identity document (issue #239).
    /// `derived/equipment-identity.json` is a derived-role payload: the
    /// operator may re-record identity evidence before finalization, so
    /// a fresh record set atomically replaces the document and its
    /// declaration. Every record must still bind to the currently
    /// committed annotation collection — a stale attestation can never
    /// outlive the entity it refers to.
    public func persistOrReplaceEquipmentIdentityEvidence(
        _ package: EquipmentIdentityEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        guard
            let decoded = try? JSONDecoder().decode(
                EquipmentIdentityDocument.self,
                from: package.data
            ),
            decoded == package.document
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }
        guard let committedEntities = annotationCollection?.entities
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }
        // Rebuild-validate against the committed entities: binding and
        // duplicate rules are enforced by the document initializer.
        _ = try EquipmentIdentityDocument(
            captureRevisionID: package.document.captureRevisionID,
            coordinateSpaceID: package.document.coordinateSpaceID,
            records: package.document.records,
            entities: committedEntities,
            recordedAtUTC: package.document.recordedAtUTC
        )

        let declaration = BundlePayloadDeclaration(
            path: EquipmentIdentityEvidencePackage.path,
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: package.sourceRefs
        )

        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: package.data,
                path: CaptureStorePath(
                    EquipmentIdentityEvidencePackage.path
                )
            ),
        ])

        // Re-check the binding after the writer suspension: a replaced
        // annotation pair committed mid-write must fail closed rather
        // than leave the document bound to removed entities.
        guard let currentEntities = annotationCollection?.entities,
              (try? EquipmentIdentityDocument(
                  captureRevisionID: package.document.captureRevisionID,
                  coordinateSpaceID: package.document.coordinateSpaceID,
                  records: package.document.records,
                  entities: currentEntities,
                  recordedAtUTC: package.document.recordedAtUTC
              )) != nil
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }

        declarations[declaration.path] = declaration

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Removes the derived equipment-identity document when the
    /// committed annotations no longer carry identity records. `data`
    /// must be the exact bytes this revision wrote — the removal is
    /// identity-checked so a different payload is never deleted.
    /// No-op when the document was never persisted.
    public func discardEquipmentIdentityEvidence(
        data: Data
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        guard let declaration =
                declarations[EquipmentIdentityEvidencePackage.path]
        else {
            return
        }
        _ = try await writer.removeIfIdentical(
            data,
            at: CaptureStorePath(EquipmentIdentityEvidencePackage.path)
        )
        declarations[declaration.path] = nil

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Persists the derived external-authority dependency manifest
    /// (#337). `derived/authority-dependencies.json` is a derived-role
    /// payload rewritten wholesale each commit — the declaration
    /// always reflects the entity collection it was built from, and a
    /// fresh commit atomically replaces it rather than accumulating
    /// stale authority pins.
    public func persistOrReplaceAuthorityDependencies(
        _ package: ExternalAuthorityDependencyPackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        guard
            let decoded = try? JSONDecoder().decode(
                ExternalAuthorityDependencyManifest.self,
                from: package.data
            ),
            decoded == package.manifest
        else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }

        let declaration = BundlePayloadDeclaration(
            path: ExternalAuthorityDependencyPackage.path,
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: package.sourceRefs
        )

        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: package.data,
                path: CaptureStorePath(
                    ExternalAuthorityDependencyPackage.path
                )
            ),
        ])

        declarations[declaration.path] = declaration
    }

    /// Removes the dependency manifest when a revision carries no
    /// external authority dependencies at all — the declaration list
    /// must never name a document the revision no longer emits.
    /// `data` must be the exact bytes this revision wrote.
    public func discardAuthorityDependencies(
        data: Data
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        guard let declaration = declarations[
            ExternalAuthorityDependencyPackage.path
        ]
        else {
            return
        }
        _ = try await writer.removeIfIdentical(
            data,
            at: CaptureStorePath(
                ExternalAuthorityDependencyPackage.path
            )
        )
        declarations[declaration.path] = nil
    }

    /// Commits the field-authority bundle (issues #300/#301/#310/
    /// #314/#324/#331): operator profiles, typed field-evidence
    /// records, instrument profiles, installed-settings observations,
    /// and as-built wiring routes — plus any binary assets the field
    /// evidence owns — in one atomic write. Documents not staged in
    /// the bundle keep their committed bytes; every binding ref is
    /// validated against the *effective* committed state (staged or
    /// previously persisted), and the whole publish happens only
    /// after the write suspension's re-checks pass.
    public func persistFieldAuthorityBundle(
        _ bundle: FieldAuthorityBundle
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let stagedBytes = [
            bundle.operators?.data,
            bundle.fieldEvidence?.data,
            bundle.instruments?.data,
            bundle.settings?.data,
            bundle.wiring?.data,
        ].compactMap(\.self).reduce(0) { $0 + $1.count }
            + bundle.assetWrites.reduce(0) { $0 + $1.data.count }
        let admissionReservation = try reserveAdmission(
            bytes: stagedBytes
        )
        defer { releaseAdmission(admissionReservation) }

        func decodeVerify<D: Codable & Equatable>(
            _ type: D.Type,
            _ data: Data,
            _ error: CaptureWorkingSetError
        ) throws -> D {
            guard let decoded = try? JSONDecoder().decode(
                type,
                from: data
            ) else {
                throw error
            }
            return decoded
        }

        // Decode-verify every staged document: the committed bytes
        // must round-trip to exactly the document that was built.
        let stagedOperators = try bundle.operators.map {
            try decodeVerify(
                OperatorProfileDocument.self,
                $0.data,
                .invalidAnnotationPackage
            )
        }
        let stagedFieldEvidence = try bundle.fieldEvidence.map {
            try decodeVerify(
                FieldEvidenceDocument.self,
                $0.data,
                .invalidAnnotationPackage
            )
        }
        let stagedInstruments = try bundle.instruments.map {
            try decodeVerify(
                InstrumentProfileDocument.self,
                $0.data,
                .invalidAnnotationPackage
            )
        }
        let stagedSettings = try bundle.settings.map {
            try decodeVerify(
                InstalledSettingsDocument.self,
                $0.data,
                .invalidAnnotationPackage
            )
        }
        let stagedWiring = try bundle.wiring.map {
            try decodeVerify(
                AsBuiltWiringDocument.self,
                $0.data,
                .invalidAnnotationPackage
            )
        }
        let documentsMatch =
            (stagedOperators == nil
                || stagedOperators == bundle.operators?.document)
            && (stagedFieldEvidence == nil
                || stagedFieldEvidence
                    == bundle.fieldEvidence?.document)
            && (stagedInstruments == nil
                || stagedInstruments
                    == bundle.instruments?.document)
            && (stagedSettings == nil
                || stagedSettings == bundle.settings?.document)
            && (stagedWiring == nil
                || stagedWiring == bundle.wiring?.document)
        guard documentsMatch else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }

        guard let captureSessionID else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        let boundCoordinate = coordinateSpaceID
        let entitiesBefore = annotationCollection?.entities ?? []
        let measurementsBefore = measurementCollection?.measurements
            ?? []
        let inventoryBefore = authorityCollection?.inventoryItems ?? []

        // Every staged document must be bound to this revision.
        for revision in [
            stagedOperators?.captureRevisionID,
            stagedFieldEvidence?.captureRevisionID,
            stagedInstruments?.captureRevisionID,
            stagedSettings?.captureRevisionID,
            stagedWiring?.captureRevisionID,
        ].compactMap(\.self) {
            guard revision == identity.captureRevisionID else {
                throw CaptureWorkingSetError.authorityMismatch
            }
        }

        func committed<D: Codable>(
            _ type: D.Type,
            _ path: String
        ) throws -> D? {
            guard let data = supplementalDocuments[path] else {
                return nil
            }
            return try? JSONDecoder().decode(type, from: data)
        }

        func effectiveDocs() throws
            -> EffectiveFieldAuthorityDocuments
        {
            try EffectiveFieldAuthorityDocuments(
                operators: bundle.operators?.document
                    ?? committed(
                        OperatorProfileDocument.self,
                        OperatorProfilePackage.path
                    ),
                fieldEvidence: bundle.fieldEvidence?.document
                    ?? committed(
                        FieldEvidenceDocument.self,
                        FieldEvidencePackage.path
                    ),
                instruments: bundle.instruments?.document
                    ?? committed(
                        InstrumentProfileDocument.self,
                        InstrumentProfilePackage.path
                    ),
                settings: bundle.settings?.document
                    ?? committed(
                        InstalledSettingsDocument.self,
                        InstalledSettingsPackage.path
                    ),
                wiring: bundle.wiring?.document
                    ?? committed(
                        AsBuiltWiringDocument.self,
                        AsBuiltWiringPackage.path
                    )
            )
        }

        // Committed measurements keep their instrument-authority binds
        // even when the caller is only adding a new field-evidence
        // record — validate both directions.
        for measurement in measurementsBefore {
            if let reference = measurement.instrumentAuthority {
                let effective = try effectiveDocs()
                guard let profile = effective.instruments?.profile(
                    matching: reference
                ) else {
                    throw FieldAuthorityModelError
                        .unknownInstrumentVersion
                }
                guard profile.profileSHA256
                    == reference.profileSHA256
                else {
                    throw FieldAuthorityModelError
                        .unknownInstrumentVersion
                }
            }
        }
        // Committed entities' author bindings must resolve against
        // the effective operator document.
        let operatorIDs = Set(
            (try effectiveDocs().operators)?.operators
                .map(\.operatorID) ?? []
        )
        for entity in entitiesBefore {
            if let authorID = entity.authorOperatorID {
                guard operatorIDs.contains(authorID) else {
                    throw FieldAuthorityModelError
                        .unboundReference(authorID.description)
                }
            }
        }

        try FieldAuthorityBindingValidator.validate(
            bundle: bundle,
            effective: try effectiveDocs(),
            entityIDs: Set(entitiesBefore.map(\.entityID)),
            measurementIDs: Set(measurementsBefore.map(\.measurementID)),
            inventoryItemIDs: Set(inventoryBefore.map(\.itemID)),
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: captureSessionID,
            declaredPaths: Set(declarations.keys),
            coordinateSpaceIDs: boundCoordinate.map { [$0] } ?? []
        )

        // Write-once binary assets first, then the document batch;
        // an identity mismatch anywhere fails before any doc lands.
        try await writer.writeBatchIfIdentical(
            bundle.assetWrites.map {
                try CaptureFileWriteRequest(
                    data: $0.data,
                    path: CaptureStorePath($0.path)
                )
            }
        )

        var docRequests: [CaptureFileWriteRequest] = []
        for package in [
            bundle.operators.map { (
                OperatorProfilePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.fieldEvidence.map { (
                FieldEvidencePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.instruments.map { (
                InstrumentProfilePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.settings.map { (
                InstalledSettingsPackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.wiring.map { (
                AsBuiltWiringPackage.path, $0.data, $0.sourceRefs
            ) },
        ].compactMap(\.self) {
            docRequests.append(
                try CaptureFileWriteRequest(
                    data: package.1,
                    path: CaptureStorePath(package.0)
                )
            )
        }
        try await writer.writeBatchReplacing(docRequests)

        var removedPaths = Set<String>()
        for removal in bundle.assetRemovals {
            if try await writer.removeIfIdentical(
                removal.data,
                at: CaptureStorePath(removal.path)
            ) {
                removedPaths.insert(removal.path)
            }
        }

        // Post-suspension re-check: an interleaved commit must fail
        // closed rather than leave the documents bound to authority
        // state that no longer matches.
        guard self.captureSessionID == captureSessionID,
              self.coordinateSpaceID == boundCoordinate,
              annotationCollection?.entities ?? [] == entitiesBefore,
              measurementCollection?.measurements ?? []
                == measurementsBefore,
              authorityCollection?.inventoryItems ?? []
                == inventoryBefore
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }

        for payload in bundle.assetWrites {
            declarations[payload.path] = payload.declaration
        }
        for path in removedPaths {
            declarations[path] = nil
        }
        for package in [
            bundle.operators.map { (
                OperatorProfilePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.fieldEvidence.map { (
                FieldEvidencePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.instruments.map { (
                InstrumentProfilePackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.settings.map { (
                InstalledSettingsPackage.path, $0.data, $0.sourceRefs
            ) },
            bundle.wiring.map { (
                AsBuiltWiringPackage.path, $0.data, $0.sourceRefs
            ) },
        ].compactMap(\.self) {
            let declaration = BundlePayloadDeclaration(
                path: package.0,
                mediaType: "application/json",
                producer: "capture_app",
                provenanceClass: .captureAppDerived,
                role: .derived,
                sourceRefs: package.2
            )
            declarations[declaration.path] = declaration
            supplementalDocuments[package.0] = package.1
        }
    }

    /// Commits or replaces the operator-confirmed room reference frame
    /// (issue #232). The frame is one canonical JSON payload bound to
    /// the revision's session and coordinate space; replacement before
    /// finalization is a single atomic rewrite so a re-capture never
    /// leaves a half-updated frame behind.
    public func commitRoomReferenceFrame(
        _ package: RoomReferenceFramePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        guard let decoded = try? JSONDecoder().decode(
            RoomReferenceFrameDocument.self,
            from: package.data
        ), decoded == package.document else {
            throw CaptureWorkingSetError
                .invalidSessionFoundationPackage
        }
        let document = package.document
        guard document.captureRevisionID
                == identity.captureRevisionID,
              let captureSessionID,
              document.captureSessionID == captureSessionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try validateCoordinateAuthority(
            document.coordinateSpaceID
        )
        for ref in document.evidenceRefs {
            try requireSpatialEvidenceLinkCongruence(
                ref,
                coordinateSpaceID: document.coordinateSpaceID
            )
        }

        let declaration = package.payloadDeclaration
        if let existing = declarations[declaration.path] {
            guard existing.path == declaration.path,
                  existing.mediaType == declaration.mediaType,
                  existing.producer == declaration.producer,
                  existing.provenanceClass
                    == declaration.provenanceClass,
                  existing.role == declaration.role
            else {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: package.data,
                path: CaptureStorePath(
                    RoomReferenceFramePackage.path
                )
            ),
        ])

        // Re-check after the write suspension (#202).
        guard let captureSessionIDAfter = self.captureSessionID,
              document.captureSessionID == captureSessionIDAfter
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try publishCoordinateAuthority(
            document.coordinateSpaceID
        )
        declarations[declaration.path] = declaration
        roomReferenceFrame = document

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Commits or replaces the operator-declared field/install datum
    /// (issue #232). Same binding and atomic-rewrite rules as the room
    /// reference frame; every reference token the datum carries
    /// (origin, axis, vertical, and evidence links) passes spatial
    /// evidence-link congruence against committed authority.
    public func commitRoomFieldDatum(
        _ package: RoomFieldDatumPackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        guard let decoded = try? JSONDecoder().decode(
            RoomFieldDatumDocument.self,
            from: package.data
        ), decoded == package.document else {
            throw CaptureWorkingSetError
                .invalidSessionFoundationPackage
        }
        let document = package.document
        guard document.captureRevisionID
                == identity.captureRevisionID,
              let captureSessionID,
              document.captureSessionID == captureSessionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try validateCoordinateAuthority(
            document.coordinateSpaceID
        )
        for ref in document.referenceTokens {
            try requireSpatialEvidenceLinkCongruence(
                ref,
                coordinateSpaceID: document.coordinateSpaceID
            )
        }

        let declaration = package.payloadDeclaration
        if let existing = declarations[declaration.path] {
            guard existing.path == declaration.path,
                  existing.mediaType == declaration.mediaType,
                  existing.producer == declaration.producer,
                  existing.provenanceClass
                    == declaration.provenanceClass,
                  existing.role == declaration.role
            else {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: package.data,
                path: CaptureStorePath(
                    RoomFieldDatumPackage.path
                )
            ),
        ])

        // Re-check after the write suspension (#202).
        guard let captureSessionIDAfter = self.captureSessionID,
              document.captureSessionID == captureSessionIDAfter
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try publishCoordinateAuthority(
            document.coordinateSpaceID
        )
        declarations[declaration.path] = declaration
        roomFieldDatum = document
    }

    /// Removes the field datum payload entirely (issue #232). The
    /// datum is optional promotion reference and entities never
    /// reference it implicitly, so removal is safe whenever the set is
    /// mutable.
    public func removeRoomFieldDatum() async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        guard roomFieldDatum != nil else {
            return
        }
        try await writer.removeIfPresent(
            CaptureStorePath(RoomFieldDatumPackage.path)
        )
        declarations.removeValue(
            forKey: RoomFieldDatumPackage.path
        )
        roomFieldDatum = nil
    }

    /// Removes the room reference frame payload entirely (issue #232).
    /// The frame is optional authority and entities never reference it
    /// implicitly, so removal is safe whenever the set is mutable.
    public func removeRoomReferenceFrame() async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        guard roomReferenceFrame != nil else {
            return
        }
        try await writer.removeIfPresent(
            CaptureStorePath(RoomReferenceFramePackage.path)
        )
        declarations.removeValue(
            forKey: RoomReferenceFramePackage.path
        )
        roomReferenceFrame = nil

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Commits or replaces the operator's opening-review document
    /// (issue #231). Upsert semantics: each review pass rewrites the
    /// whole candidate set atomically, so disposition edits never
    /// produce a torn document.
    public func commitOpeningReview(
        _ package: OpeningReviewPackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: package.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        guard let decoded = try? JSONDecoder().decode(
            OpeningReviewDocument.self,
            from: package.data
        ), decoded == package.document else {
            throw CaptureWorkingSetError.invalidAnnotationPackage
        }
        let document = package.document
        guard document.captureRevisionID
                == identity.captureRevisionID,
              let captureSessionID,
              document.captureSessionID == captureSessionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try validateCoordinateAuthority(
            document.coordinateSpaceID
        )
        for opening in document.openings {
            for ref in opening.evidenceRefs {
                try requireSpatialEvidenceLinkCongruence(
                    ref,
                    coordinateSpaceID:
                        document.coordinateSpaceID
                )
            }
        }

        let declaration = package.payloadDeclaration
        if let existing = declarations[declaration.path] {
            guard existing.path == declaration.path,
                  existing.mediaType == declaration.mediaType,
                  existing.producer == declaration.producer,
                  existing.provenanceClass
                    == declaration.provenanceClass,
                  existing.role == declaration.role
            else {
                throw CaptureWorkingSetError
                    .duplicatePayloadDeclaration(
                        declaration.path
                    )
            }
        }

        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: package.data,
                path: CaptureStorePath(OpeningReviewPackage.path)
            ),
        ])

        guard let captureSessionIDAfter = self.captureSessionID,
              document.captureSessionID == captureSessionIDAfter
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try publishCoordinateAuthority(
            document.coordinateSpaceID
        )
        declarations[declaration.path] = declaration
        openingReviewDocument = document

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Removes the opening-review document (issue #231). The document
    /// is operator metadata over RoomPlan inference; removing it leaves
    /// the underlying candidates' source payload intact.
    public func removeOpeningReview() async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        guard openingReviewDocument != nil else {
            return
        }
        try await writer.removeIfPresent(
            CaptureStorePath(OpeningReviewPackage.path)
        )
        declarations.removeValue(
            forKey: OpeningReviewPackage.path
        )
        openingReviewDocument = nil

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Marks frames committed by the current accepted End boundary
    /// (issue #241): they are the closing spatial observation of the
    /// scan and are never removable in the visual evidence review —
    /// replacing them requires Continue scanning → End again. Runs as
    /// a mutation entry point so the marker commits inside the same
    /// fence ordering as the frame persistence it describes.
    public func markEndBoundaryFrames(
        _ frameIDs: [EvidenceFrameID]
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        endBoundaryFrameIDs.formUnion(frameIDs)

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Removes one unreferenced optional evidence frame and all of its
    /// payloads (issue #241). Refuses when the frame is the
    /// End-boundary observation, when any committed authority
    /// (annotation, measurement, opening candidate, or the room
    /// reference frame) still references it, or when any of its
    /// canonical members fail their recorded hash — a byte-level
    /// mismatch means the working set is already inconsistent and the
    /// failure must surface rather than silently delete evidence.
    public func removeEvidenceFrame(
        _ frameID: EvidenceFrameID
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        guard let descriptor = frameDescriptors.first(where: {
            $0.frameID == frameID
        }) else {
            throw CaptureWorkingSetError.integrityVerificationFailed
        }
        guard !endBoundaryFrameIDs.contains(frameID) else {
            throw CaptureWorkingSetError
                .unresolvableSpatialEvidenceLink(
                    "end_boundary:\(frameID.description)"
                )
        }

        // Referenced frames are never removable: deleting one would
        // leave committed authority pointing at missing evidence.
        let frameTokens: Set<String> = [
            "path:evidence/frames/\(frameID.description).json",
            "path:\(descriptor.pixelRelativePath)",
            "frame:\(frameID.description)",
        ]
        func refsFrame(_ refs: [String]) -> Bool {
            refs.contains { frameTokens.contains($0) }
        }
        for entity in annotationCollection?.entities ?? [] {
            if refsFrame(
                entity.evidenceRefs
                    + entity.placement.sourceEvidenceRefs
            ) {
                throw CaptureWorkingSetError
                    .unresolvableSpatialEvidenceLink(
                        "referenced:\(entity.entityID.description)"
                    )
            }
        }
        for measurement in measurementCollection?.measurements ?? [] {
            if refsFrame(
                measurement.evidenceRefs + measurement.endpointRefs
            ) {
                throw CaptureWorkingSetError
                    .unresolvableSpatialEvidenceLink(
                        "referenced:\(measurement.measurementID.description)"
                    )
            }
        }
        for opening in openingReviewDocument?.openings ?? [] {
            if refsFrame(opening.evidenceRefs) {
                throw CaptureWorkingSetError
                    .unresolvableSpatialEvidenceLink(
                        "referenced:\(opening.sourceRef)"
                    )
            }
        }
        if let frame = roomReferenceFrame,
           refsFrame(frame.evidenceRefs)
        {
            throw CaptureWorkingSetError
                .unresolvableSpatialEvidenceLink(
                    "referenced:room_reference_frame"
                )
        }
        if let datum = roomFieldDatum,
           refsFrame(datum.referenceTokens)
        {
            throw CaptureWorkingSetError
                .unresolvableSpatialEvidenceLink(
                    "referenced:room_field_datum"
                )
        }

        // Collect the frame's canonical + derived paths and verify the
        // committed descriptor bytes still match before deleting.
        let descriptorPath =
            "evidence/frames/\(frameID.description).json"
        var removals: [String] = [
            descriptorPath,
            descriptor.pixelRelativePath,
        ]
        if let depth = descriptor.depth {
            removals.append(depth.depthRelativePath)
            if let confidencePath = depth.confidenceRelativePath {
                removals.append(confidencePath)
            }
        }
        let preview = framePreviews.first(where: {
            $0.path
                == "evidence/frames/\(frameID.description).preview.heic"
        })
        if let preview {
            removals.append(preview.path)
        }

        for path in removals {
            let url = path.split(separator: "/").reduce(
                rootDirectory
            ) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            guard FileManager.default.fileExists(
                atPath: url.path
            ), let bytes = try? Data(contentsOf: url)
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            switch path {
            case descriptorPath:
                guard (try? JSONDecoder().decode(
                    FrameEvidenceDescriptor.self,
                    from: bytes
                )) == descriptor else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
            case descriptor.pixelRelativePath:
                guard EvidenceIntegrity.sha256(of: bytes)
                    == descriptor.pixelSHA256
                else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
            default:
                break
            }
            try await writer.removeIfPresent(
                CaptureStorePath(path)
            )
            declarations.removeValue(forKey: path)
        }

        frameDescriptors.removeAll { $0.frameID == frameID }
        if let preview {
            framePreviews.removeAll { $0 == preview }
        }
        endBoundaryFrameIDs.remove(frameID)
        evidenceFrameCount -= 1
        if descriptor.depth != nil {
            depthEvidenceCount -= 1
            // Recompute usable-depth counters: samples are tracked per
            // package payload, which is no longer retained in memory,
            // so recount from the remaining descriptors' payloads.
            var usableSamples = 0
            var usableFrames = 0
            for remaining in frameDescriptors {
                guard let depthPath =
                        remaining.depth?.depthRelativePath
                else {
                    continue
                }
                let depthURL = depthPath
                    .split(separator: "/")
                    .reduce(rootDirectory) {
                        $0.appendingPathComponent(
                            String($1),
                            isDirectory: false
                        )
                    }
                let payload = try? Data(contentsOf: depthURL)
                let samples = Self.usableDepthSamples(
                    in: payload
                )
                usableSamples += samples
                if samples > 0 {
                    usableFrames += 1
                }
            }
            usableDepthSampleCount = usableSamples
            usableDepthEvidenceCount = usableFrames
        }

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Post-commit spatial evidence issues (#236): after a re-End the
    /// accepted RoomPlan/mesh authority may have been replaced while
    /// committed annotations still reference the prior mesh anchors or
    /// frames. Reports every record whose spatial evidence link no
    /// longer resolves so the host can surface repair targets instead
    /// of silently dropping them.
    public func committedSpatialEvidenceIssues()
        -> [SpatialEvidenceIssue]
    {
        var issues: [SpatialEvidenceIssue] = []
        func check(
            _ ref: String,
            space: CoordinateSpaceID,
            owner: String
        ) {
            do {
                try requireSpatialEvidenceLinkCongruence(
                    ref,
                    coordinateSpaceID: space
                )
            } catch {
                issues.append(
                    SpatialEvidenceIssue(
                        owner: owner,
                        ref: ref,
                        reason: String(describing: error)
                    )
                )
            }
        }
        for entity in annotationCollection?.entities ?? [] {
            for ref in entity.evidenceRefs
                + entity.placement.sourceEvidenceRefs
            {
                check(
                    ref,
                    space: entity.coordinateSpaceID,
                    owner: "entity:\(entity.entityID.description)"
                )
            }
            if let anchorID = entity.placement.sourceMeshAnchorID {
                check(
                    "mesh_anchor:\(anchorID.uuidString.lowercased())",
                    space: entity.coordinateSpaceID,
                    owner: "entity:\(entity.entityID.description)"
                )
            }
            if let ref = entity.acousticCenter?.authorityRef {
                check(
                    ref,
                    space: entity.coordinateSpaceID,
                    owner: "entity:\(entity.entityID.description)"
                )
            }
        }
        for measurement in measurementCollection?.measurements ?? [] {
            guard let space = measurement.coordinateSpaceID else {
                continue
            }
            for ref in measurement.evidenceRefs
                + measurement.endpointRefs
            {
                check(
                    ref,
                    space: space,
                    owner: "measurement:\(measurement.measurementID.description)"
                )
            }
        }
        return issues
    }
    public func persistAnnotationPackage(
        _ package: AnnotationEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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
        // Validate without mutating: the space binding publishes only
        // after the canonical file is durable (issue #202).
        if let space = spaces.first {
            try validateCoordinateAuthority(space)
        }

        // Issue #199: spatial evidence links must resolve to committed
        // frame/mesh authority in the entity's own coordinate space.
        for entity in package.collection.entities {
            try requireSpatialEvidenceCongruence(entity: entity)
        }

        // Write-once replay semantics before any durable work: an
        // identical committed collection is idempotent, a different one
        // fails closed.
        if let existing = annotationCollection {
            if existing == package.collection {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
        }

        let provenance = try annotationCollectionProvenance(
            package.collection
        )
        let declaration = BundlePayloadDeclaration(
            path: AnnotationEvidencePackage.path,
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: provenance,
            role: .canonical
        )
        if let existing = declarations[declaration.path],
           existing != declaration
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }

        try await writer.writeIfIdentical(
            package.data,
            to: CaptureStorePath(AnnotationEvidencePackage.path)
        )

        // Re-check after the writer suspension: an identical reentrant
        // commit is idempotent; any other authority fails closed.
        if let existing = annotationCollection {
            if existing == package.collection {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
        }
        guard declarations[declaration.path] == nil
                || declarations[declaration.path] == declaration
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }

        // No suspension points below: binding, declaration, and
        // collection state publish as one commit (issue #202).
        if let space = spaces.first {
            try publishCoordinateAuthority(space)
        }
        declarations[declaration.path] = declaration
        annotationCollection = package.collection
        annotationKeysPresent = Set(
            package.collection.entities.map(annotationQualityKey)
        )

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    public func persistMeasurementPackage(
        _ package: MeasurementEvidencePackage
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
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
        // Validate without mutating: the space binding publishes only
        // after the canonical file is durable (issue #202).
        if let space = spaces.first {
            try validateCoordinateAuthority(space)
        }

        // Issue #199: spatial evidence links must resolve to committed
        // frame/mesh authority in the measurement's own coordinate
        // space.
        for measurement in package.collection.measurements {
            try requireSpatialEvidenceCongruence(
                measurement: measurement
            )
        }

        // Write-once replay semantics before any durable work: an
        // identical committed collection is idempotent, a different one
        // fails closed.
        if let existing = measurementCollection {
            if existing == package.collection {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeasurementEvidencePackage.path
                )
        }

        let provenance = try measurementCollectionProvenance(
            package.collection
        )
        let declaration = BundlePayloadDeclaration(
            path: MeasurementEvidencePackage.path,
            mediaType: "application/json",
            producer: "measurement",
            provenanceClass: provenance,
            role: .canonical
        )
        if let existing = declarations[declaration.path],
           existing != declaration
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }

        try await writer.writeIfIdentical(
            package.data,
            to: CaptureStorePath(MeasurementEvidencePackage.path)
        )

        // Re-check after the writer suspension: an identical reentrant
        // commit is idempotent; any other authority fails closed.
        if let existing = measurementCollection {
            if existing == package.collection {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(
                    MeasurementEvidencePackage.path
                )
        }
        guard declarations[declaration.path] == nil
                || declarations[declaration.path] == declaration
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(declaration.path)
        }

        // No suspension points below: binding, declaration, and
        // collection state publish as one commit (issue #202).
        if let space = spaces.first {
            try publishCoordinateAuthority(space)
        }
        declarations[declaration.path] = declaration
        measurementCollection = package.collection
        measurementQuantityTypesPresent = Set(
            package.collection.measurements.map(\.quantityType)
        )

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Commits a supplemental feature payload (issues #222/#226/#227/
    /// #240/#249/#293). Same rules as the typed families: admission is
    /// reserved, every claimed coordinate space must match the bound
    /// authority, the committed bytes are write-once, and the
    /// declaration registers into the manifest set so integrity and
    /// finalization see the file. Identical replays are idempotent.
    public func persistSupplementalDocument(
        _ document: WorkingSetSupplementalDocument
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: document.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        for space in document.coordinateSpaceIDs {
            try validateCoordinateAuthority(space)
        }
        if let boundSession = captureSessionID {
            guard document.captureSessionIDs.allSatisfy({
                $0 == boundSession
            }) else {
                throw CaptureWorkingSetError.authorityMismatch
            }
        }

        if let existing = supplementalDocuments[document.path] {
            if existing == document.data {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }
        if let existing = declarations[document.path],
           existing != document.declaration
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }

        try await writer.writeIfIdentical(
            document.data,
            to: CaptureStorePath(document.path)
        )

        // Re-check after the writer suspension: an identical reentrant
        // commit is idempotent; any other authority fails closed.
        if let existing = supplementalDocuments[document.path] {
            if existing == document.data {
                return
            }
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }
        guard declarations[document.path] == nil
                || declarations[document.path] == document.declaration
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }

        // No suspension points below: binding, declaration, and ledger
        // publish as one commit (issue #202).
        for space in document.coordinateSpaceIDs {
            try publishCoordinateAuthority(space)
        }
        declarations[document.path] = document.declaration
        supplementalDocuments[document.path] = document.data

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Replaces a committed supplemental document (e.g. evolving
    /// task-plan status, reference-target observations, or a rebuilt
    /// derived-candidate payload after Continue scanning). The
    /// manifest declaration for the path must be identical — only the
    /// payload bytes evolve.
    public func replaceSupplementalDocument(
        _ document: WorkingSetSupplementalDocument
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }
        let admissionReservation = try reserveAdmission(
            bytes: document.data.count
        )
        defer { releaseAdmission(admissionReservation) }

        for space in document.coordinateSpaceIDs {
            try validateCoordinateAuthority(space)
        }
        if let boundSession = captureSessionID {
            guard document.captureSessionIDs.allSatisfy({
                $0 == boundSession
            }) else {
                throw CaptureWorkingSetError.authorityMismatch
            }
        }

        if let existing = supplementalDocuments[document.path],
           existing == document.data
        {
            return
        }
        if let existing = declarations[document.path],
           existing != document.declaration
        {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }

        let prior = supplementalDocuments[document.path]
        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: document.data,
                path: CaptureStorePath(document.path)
            ),
        ])

        // Re-check after actor suspension: a mutation that interleaved
        // across the write is detected instead of silently mixing
        // committed bytes.
        guard supplementalDocuments[document.path] == prior else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }
        guard declarations[document.path] == nil
                || declarations[document.path] == document.declaration
        else {
            throw CaptureWorkingSetError
                .duplicatePayloadDeclaration(document.path)
        }

        for space in document.coordinateSpaceIDs {
            try publishCoordinateAuthority(space)
        }
        declarations[document.path] = document.declaration
        supplementalDocuments[document.path] = document.data

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
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
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
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
        try requireLiveSpatialAuthority()

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
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }

        appendResourceEvent(event)
    }

    /// Records one RoomPlan coaching/instruction sample (#260). The
    /// tracker deduplicates consecutive identical instructions and
    /// caps the transition history, so per-frame calls stay bounded.
    /// `instruction` must be the stable framework case identity (e.g.
    /// `moveCloseToWall`), never a localized string.
    public func recordRoomPlanGuidanceInstruction(
        _ observation: RoomPlanGuidanceObservation
    ) {
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }
        roomPlanGuidanceAvailable = true
        roomPlanGuidanceTracker.record(observation)
    }

    /// Marks that the RoomPlan instruction delegate path is not
    /// available on this run, so the advisory history can state the
    /// degraded source explicitly instead of looking like a clean
    /// session (#260).
    public func recordRoomPlanGuidanceUnavailable() {
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }
        roomPlanGuidanceAvailable = false
    }

    /// Records a mesh anchor lifecycle event during scanning (#268).
    /// Bounded: the tracker retains at most
    /// `MeshAnchorLifecycleTracker.uniqueAnchorLimit` distinct anchors
    /// and `eventLimit` events.
    public func recordMeshAnchorLifecycle(
        _ kind: MeshAnchorLifecycleKind,
        anchorID: UUID,
        sessionTimestampSeconds: Double
    ) {
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }
        meshLifecycleTracker.record(
            kind,
            anchorID: anchorID,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }

    /// Replaces the advisory End-boundary coverage snapshot (#223). The
    /// host records it once per accepted End attempt; the latest call
    /// wins so repeated End presses stay deterministic.
    public func recordAdvisoryEndContext(
        _ summary: CaptureEndCoverageSummary
    ) {
        guard liveSpatialAuthority else {
            sealedMutationRejectionCount += 1
            return
        }
        guard sealState == .mutable else {
            sealedMutationRejectionCount += 1
            return
        }
        advisoryEndContext = summary
    }

    /// Selects (or clears) the operator capture-task profile (#217).
    /// Task completeness is advisory only — it never feeds
    /// `ready_for_htdt_ingestion`.
    public func recordTaskProfile(
        _ profile: CaptureTaskProfile?,
        skippedRequirementIDs: Set<String> = []
    ) async throws {
        try requireMutable()
        if let profile {
            guard !profile.identifier.isEmpty,
                  profile.requirements.allSatisfy({
                      !$0.identifier.isEmpty
                  })
            else {
                throw CaptureWorkingSetError.invalidTaskProfile
            }
        }
        taskProfile = profile
        skippedTaskRequirementIDs = skippedRequirementIDs

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Persists the operator/plan capture-strategy selection as the
    /// `session/capture-strategy.json` payload (#307). The strategy is
    /// advisory provenance: it records which published guidance and
    /// evidence budgets steered this revision and never feeds
    /// `ready_for_htdt_ingestion`. Idempotent on an identical
    /// re-commit; a conflicting second selection fails closed like
    /// every other canonical payload.
    public func persistCaptureStrategy(
        _ package: CaptureStrategyPackage
    ) async throws {
        try requireMutable()
        guard let catalogID = CaptureStrategyCatalog.identifier(
            forPersistedValue: package.document.strategyID
        ) else {
            throw CaptureWorkingSetError.invalidCaptureStrategy
        }
        let publishedProfile = CaptureStrategyCatalog.profile(
            for: catalogID
        )
        guard package.document.policyVersion
                == publishedProfile.policyVersion,
              package.document.resolvedPolicy
                == CaptureStrategyPolicyEcho(
                    profile: publishedProfile
                ),
              package.document.reviewExpectation
                == publishedProfile.reviewExpectation,
              package.document.promptsComplexObjectReview
                == publishedProfile.promptsComplexObjectReview,
              package.document.promptsLoopClosureCheck
                == publishedProfile.promptsLoopClosureCheck
        else {
            throw CaptureWorkingSetError.invalidCaptureStrategy
        }
        guard package.document.captureRevisionID
                == identity.captureRevisionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try await persistSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: CaptureStrategyPackage.path,
                data: package.data,
                declaration: package.payloadDeclaration,
                coordinateSpaceIDs: [
                    package.document.coordinateSpaceID
                ],
                captureSessionIDs: [
                    package.document.captureSessionID
                ]
            )
        )
        captureStrategyDocument = package.document
    }

    /// Persists the floor-plan reference underlay as the
    /// `reference/plan-underlay.json` payload (#322). The underlay is
    /// `.importedReference` provenance — a declared reference for
    /// guidance/coverage comparison only; it is never merged into
    /// observed geometry, never feeds `ready_for_htdt_ingestion`, and
    /// its residual stays visible on the document. The alignment
    /// method must be one of the explicit published authorities —
    /// scale inference from image metadata is rejected by
    /// construction (the document carries no DPI/pixel fields at all).
    public func persistPlanUnderlay(
        _ package: PlanUnderlayPackage
    ) async throws {
        try requireMutable()
        guard package.document.captureRevisionID
                == identity.captureRevisionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try await persistSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: PlanUnderlayPackage.path,
                data: package.data,
                declaration: package.payloadDeclaration,
                coordinateSpaceIDs: [
                    package.document.coordinateSpaceID
                ],
                captureSessionIDs: []
            )
        )
        planUnderlayDocument = package.document
    }

    /// Binds benchmark references into the quality report (#285). Only
    /// immutable/versioned `slug@semver` refs pass validation; anything
    /// else fails closed.
    public func recordBenchmarkReferences(_ refs: [String]) async throws {
        try requireMutable()
        for ref in refs
        where !BenchmarkReferenceValidator.isValid(ref) {
            throw CaptureWorkingSetError
                .invalidBenchmarkReference(ref)
        }
        benchmarkRefs = CaptureQualityEvaluator
            .canonicalBenchmarkRefs(refs)

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// Evaluates the advisory diagnostics layer from current state
    /// (#223). Read-only: identical state produces identical output.
    /// Used by Review before seal and persisted at seal.
    public func evaluateAdvisoryDiagnostics() -> CaptureAdvisoryReport? {
        guard let captureSessionID else { return nil }
        let endTimestamp = advisoryEndContext?
            .endSessionTimestampSeconds
        return CaptureAdvisoryReport(
            captureSessionID: captureSessionID,
            generatedAtUTC: BundleTimestamp.utcString(from: Date()),
            endCoverage: advisoryEndContext,
            taskCompleteness:
                CaptureTaskCompletenessEvaluator.evaluate(
                    profile: taskProfile,
                    annotations: annotationCollection?.entities ?? [],
                    measurements: measurementCollection?.measurements
                        ?? [],
                    skippedRequirementIDs: skippedTaskRequirementIDs
                ),
            roomPlanGuidance: roomPlanGuidanceAvailable
                ? (recoveredRoomPlanGuidance?.history
                    ?? roomPlanGuidanceTracker.history())
                : RoomPlanGuidanceHistory(
                    source: .unavailable,
                    transitions: [],
                    truncated: false
                ),
            meshLifecycle: recoveredMeshLifecycle
                ?? meshLifecycleTracker
                .summary(endSessionTimestampSeconds: endTimestamp),
            depthSufficiency: depthSufficiencyAccumulator.summary,
            conflicts: CaptureConflictAnalyzer.analyze(
                measurements: measurementCollection?.measurements,
                annotations: annotationCollection?.entities,
                roomMetadata: capturedRoomMetadata
            ),
            geometryConsistency:
                RoomPlanMeshConsistencyAnalyzer.analyze(
                    meshProfile: meshGeometryProfile,
                    roomMetadata: capturedRoomMetadata,
                    meshCoordinateSpaceID: meshIndex?.anchors.first?
                        .coordinateSpaceID,
                    roomPlanCoordinateSpaceID: coordinateSpaceID
                )
        )
    }

    /// Persists the advisory diagnostics payload as a derived bundle
    /// entry (#223). Role `.derived` with explicit source refs keeps it
    /// advisory: it is never canonical geometry truth.
    @discardableResult
    private func persistAdvisoryDiagnosticsPayload(
        _ report: CaptureAdvisoryReport
    ) async throws -> (
        data: Data,
        declaration: BundlePayloadDeclaration
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let path = CaptureAdvisoryReport.payloadPath
        let declaration = BundlePayloadDeclaration(
            path: path,
            mediaType: "application/json",
            producer: "capture_quality",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: [
                "capture_session:\(report.captureSessionID)",
                "path:quality/capture-quality.json",
            ]
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
    /// Records one advisory provenance note and rewrites the bounded
    /// `advisory/operator-advisories.json` derived payload. Exact
    /// duplicates (same kind/detail/timestamp) are idempotent so a
    /// retried record does not grow history.
    public func recordAdvisoryNote(
        _ note: CaptureAdvisoryNote
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        if !advisoryNotes.contains(note) {
            guard advisoryNotes.count < Self.maxAdvisoryNotes else {
                return
            }
            advisoryNotes.append(note)
        }

        let document = CaptureAdvisoryNoteDocument(
            captureRevisionID: identity.captureRevisionID,
            notes: advisoryNotes
        )
        let data = try document.encoded()
        let reservation = try reserveAdmission(bytes: data.count)
        defer { releaseAdmission(reservation) }
        try await writer.writeIfIdentical(
            data,
            to: CaptureStorePath(CaptureAdvisoryNoteDocument.path)
        )
        try register(
            BundlePayloadDeclaration(
                path: CaptureAdvisoryNoteDocument.path,
                mediaType: "application/json",
                producer: "capture_advisory",
                provenanceClass: .captureAppDerived,
                role: .derived
            )
        )

        // Post-End semantic commit (issue #297): advance
        // the durable marker to semantic_authoring so a relaunch
        // reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    /// The advisory findings currently recorded, exposed as the
    /// quality-evaluation input.
    public var advisoryFindings: [QualityDiagnostic] {
        advisoryNotes.map(\.qualityDiagnostic)
    }

    /// The operator field notes recorded on this revision (issue
    /// #375), chronological as committed.
    public var recordedFieldNotes: [CaptureFieldNote] {
        fieldNotes
    }

    /// Records one operator field note and rewrites the canonical
    /// `session/field-notes.json` payload (issue #375). The note binds
    /// this revision and, once the session foundation is committed,
    /// the live capture session. Exact note-id duplicates are a no-op
    /// so a retried record does not grow history; a conflicting id is
    /// a typed rejection. Notes are never rewritten in place —
    /// corrections land via `supersedeFieldNote`.
    public func recordFieldNote(_ note: CaptureFieldNote) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        guard note.captureRevisionID == identity.captureRevisionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        // A note may legitimately arrive before the session
        // foundation commits (or on a restored draft): bind the live
        // session authority when it exists; a conflicting declared
        // session is a typed rejection, never a silent rewrite.
        var bound = note
        if bound.captureSessionID == nil, let captureSessionID {
            bound = try bound.withSessionBinding(captureSessionID)
        }
        if let declared = bound.captureSessionID,
           declared != captureSessionID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        if let existingIndex = fieldNotes.firstIndex(where: {
            $0.noteID == bound.noteID
        }) {
            guard fieldNotes[existingIndex] == bound else {
                throw CaptureWorkingSetError.duplicatePayloadDeclaration(
                    CaptureFieldNoteDocument.path
                )
            }
            return
        }
        if let supersedes = bound.supersedesNoteID,
           let target = fieldNotes.first(where: {
               $0.noteID == supersedes
           })
        {
            // Recording a replacement note performs the supersession
            // atomically: the earlier note goes terminal in the same
            // document commit so the pair can never disagree on disk.
            try await applySupersession(
                target: target,
                replacement: bound
            )
            return
        }
        guard fieldNotes.count < Self.maxFieldNotes else {
            throw CaptureFieldNoteError.collectionBoundExceeded
        }
        fieldNotes.append(bound)
        try await persistFieldNotes()
    }

    /// Supersedes an active field note with a replacement note
    /// (issue #375). The replacement's `supersedes_note_id` must name
    /// the target; both land in one document commit.
    public func supersedeFieldNote(
        _ noteID: CaptureFieldNoteID,
        replacement: CaptureFieldNote
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        guard replacement.captureRevisionID
                == identity.captureRevisionID
        else {
            throw CaptureWorkingSetError.authorityMismatch
        }
        guard let targetIndex = fieldNotes.firstIndex(where: {
            $0.noteID == noteID
        }) else {
            throw CaptureFieldNoteError.unknownNoteID
        }
        var bound = replacement
        if bound.captureSessionID == nil, let captureSessionID {
            bound = try bound.withSessionBinding(captureSessionID)
        }
        if let declared = bound.captureSessionID,
           declared != captureSessionID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
        try await applySupersession(
            target: fieldNotes[targetIndex],
            replacement: bound
        )
    }

    /// Marks an active field note resolved — a terminal lifecycle
    /// transition that keeps the recorded bytes (issue #375).
    public func resolveFieldNote(
        _ noteID: CaptureFieldNoteID
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        guard let index = fieldNotes.firstIndex(where: {
            $0.noteID == noteID
        }) else {
            throw CaptureFieldNoteError.unknownNoteID
        }
        fieldNotes[index] = try fieldNotes[index].resolving()
        try await persistFieldNotes()
    }

    /// Shared supersession body: validates the replacement declares
    /// the target, flips the target terminal, appends the replacement,
    /// and commits the whole collection in one write.
    private func applySupersession(
        target: CaptureFieldNote,
        replacement: CaptureFieldNote
    ) async throws {
        guard replacement.supersedesNoteID == target.noteID else {
            throw CaptureFieldNoteError.supersessionNotDeclared
        }
        guard let index = fieldNotes.firstIndex(where: {
            $0.noteID == target.noteID
        }) else {
            throw CaptureFieldNoteError.unknownNoteID
        }
        guard fieldNotes.count < Self.maxFieldNotes else {
            throw CaptureFieldNoteError.collectionBoundExceeded
        }
        fieldNotes[index] = try target.superseding(
            by: replacement.noteID
        )
        fieldNotes.append(replacement)
        try await persistFieldNotes()
    }

    /// Rewrites `session/field-notes.json` from the committed note
    /// collection and re-registers its stable declaration (issue
    /// #375).
    private func persistFieldNotes() async throws {
        let document = CaptureFieldNoteDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: captureSessionID,
            notes: fieldNotes
        )
        let data = try document.encoded()
        let reservation = try reserveAdmission(bytes: data.count)
        defer { releaseAdmission(reservation) }
        // The notes document is lifecycle-mutable (resolve/supersede
        // rewrite it), so it commits through the replacing writer like
        // the revision-state marker.
        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: data,
                path: CaptureStorePath(
                    CaptureFieldNoteDocument.path
                )
            ),
        ])
        try register(Self.fieldNotesDeclaration)

        // Post-End semantic commit (issue #297): the durable marker
        // advances so a relaunch reports truthful progress.
        try await refreshRevisionStateAfterSemanticCommit()
    }

    private static var fieldNotesDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: CaptureFieldNoteDocument.path,
            mediaType: "application/json",
            producer: "capture_field_notes",
            provenanceClass: .userAnnotation,
            role: .canonical
        )
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
                coordinateDiscontinuityCount:
                    coordinateTransitions.count,
                depthSufficiency: depthSufficiencyAccumulator.summary,
                annotationKeysPresent: annotationKeysPresent,
                measurementQuantityTypesPresent:
                    measurementQuantityTypesPresent,
                resourceEvents: resourceEvents,
                integrityStatus: integrityStatus,
                benchmarkRefs: benchmarkRefs,
                advisoryFindings: advisoryNotes.map(
                    \.qualityDiagnostic
                )
            ),
            requirements: requirements
        )
    }

    public func persistQualityReport(
        _ report: CaptureQualityReport
    ) async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

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
        // Practice working sets never produce a real bundle
        // (issue #320): the rehearsal ends at Review.
        guard !isPracticeWorkingSet else {
            throw CaptureWorkingSetError
                .practiceWorkingSetNotFinalizable
        }
        sealState = .sealed
        sealGeneration += 1
        let generation = sealGeneration
        do {
            // Wait for already-owned writes: suspended mutations resume
            // while this seal parks on a drain continuation, finish their
            // commit, and decrement inFlightMutations. New mutations are
            // already rejected by requireMutable(), so the counter only
            // converges to zero. The continuation resumes exactly when the
            // last in-flight mutation leaves — unlike a writer-fence poll
            // loop it injects no competing jobs onto the writer actor.
            while inFlightMutations > 0 {
                await waitForMutationDrain()
                try requireSealHeld(generation)
            }
            try verifyIntegrity()
            let report = evaluateQuality(requirements: requirements)
            guard report.readyForHTDTIngestion else {
                throw CaptureWorkingSetError.qualityReportNotReady
            }
            sealedQualityReport =
                try await persistQualityReportPayload(report)

            // Advisory provenance payload (#223): derived, bounded, and
            // rolled back with the quality report if the seal lifts.
            // Recorded AFTER the canonical quality write so its
            // path:quality/capture-quality.json source ref resolves.
            if let advisory = evaluateAdvisoryDiagnostics() {
                sealedAdvisoryReport =
                    try await persistAdvisoryDiagnosticsPayload(
                        advisory
                    )
            }

            // Durable phase transition (issue #297): quality and
            // advisory verdicts are committed, so the marker records a
            // revision with nothing left but the finalization write.
            // `unseal` restores the pre-seal phase.
            phaseBeforeSeal = revisionPhase
            if revisionPhase.isRecoverableDraft {
                try await persistRevisionState(.readyToFinalize) {
                    [self] in
                    guard sealState == .sealed,
                          sealGeneration == generation
                    else {
                        throw CaptureWorkingSetError
                            .integrityVerificationFailed
                    }
                }
            }

            // The report write released the actor; drain any mutation
            // that completed during that suspension, then re-verify the
            // durable bytes — now including the canonical quality
            // payload — and snapshot the exact sealed state.
            while inFlightMutations > 0 {
                await waitForMutationDrain()
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
                if let sealedAdvisory = sealedAdvisoryReport {
                    if declarations[sealedAdvisory.declaration.path]
                        == sealedAdvisory.declaration
                    {
                        declarations.removeValue(
                            forKey: sealedAdvisory.declaration.path
                        )
                    }
                    try? await writer.removeIfIdentical(
                        sealedAdvisory.data,
                        at: CaptureStorePath(
                            sealedAdvisory.declaration.path
                        )
                    )
                }
                sealedAdvisoryReport = nil
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
                if let priorPhase = phaseBeforeSeal {
                    phaseBeforeSeal = nil
                    try? await persistRevisionState(priorPhase)
                }
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

        if let sealedAdvisory = sealedAdvisoryReport {
            let removedOrAbsent =
                try await writer.removeIfIdentical(
                    sealedAdvisory.data,
                    at: CaptureStorePath(
                        sealedAdvisory.declaration.path
                    )
                )
            guard removedOrAbsent else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            if declarations[sealedAdvisory.declaration.path]
                == sealedAdvisory.declaration
            {
                declarations.removeValue(
                    forKey: sealedAdvisory.declaration.path
                )
            }
            sealedAdvisoryReport = nil
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

        // The seal had advanced the durable marker to
        // `ready_to_finalize`; lifting it returns the revision to
        // whatever phase it held before sealing (issue #297).
        if let priorPhase = phaseBeforeSeal {
            phaseBeforeSeal = nil
            try? await persistRevisionState(priorPhase)
        }
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
            sealedAdvisoryReport = nil
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
        defer { mutationDidFinish() }

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

    /// Terminal discard of the whole working revision (issue #254).
    /// Fencing order: the store first flips to `.consumed` so every
    /// queued and future mutation entry point fails closed, then the
    /// writer actor drains already-queued writes, and only then is the
    /// directory removed — a write that was still queued can never
    /// resurrect an orphan payload inside a deleted working set.
    public func discardIncompleteRevision() async throws {
        try requireMutable()
        inFlightMutations += 1
        defer { mutationDidFinish() }

        sealState = .consumed
        sealGeneration += 1

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

        // Drain queued file writes before deleting the root.
        await writer.barrier()

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
                .sorted(),
            roomReferenceFrame: roomReferenceFrame,
            roomFieldDatum: roomFieldDatum,
            openingReview: openingReviewDocument,
            revisionPhase: revisionPhase,
            spatialAuthorityLive: liveSpatialAuthority,
            practiceCapture: isPracticeWorkingSet,
            endBoundaryFrameIDs: endBoundaryFrameIDs.sorted {
                $0.description < $1.description
            },
            fieldNotes: fieldNotes,
            latestEvidenceDescriptorPath:
                frameDescriptors.last.map {
                    "evidence/frames/"
                        + $0.frameID.description
                        + ".json"
                },
            captureStrategy: captureStrategyDocument,
            planUnderlay: planUnderlayDocument
        )
    }

    /// Byte accounting of the live working revision for the active-
    /// capture storage UX (issue #308). Scans the same directory the
    /// manifest would be built from, so the operator-visible totals
    /// equal the retained bytes of the bundle that would finalize.
    /// Advisory only — never persisted, never a quality input.
    public func storageProfile() throws
        -> CaptureWorkingSetStorageProfile
    {
        let scanned = try BundleDirectoryScanner.scan(
            root: rootDirectory
        )
        var accumulator = CaptureWorkingSetStorageProfile
            .Accumulator()
        for file in scanned {
            CaptureWorkingSetStorageProfile.accumulate(
                path: file.path,
                bytes: file.bytes,
                into: &accumulator
            )
        }
        return CaptureWorkingSetStorageProfile(
            framePixelBytes: accumulator.framePixelBytes,
            depthConfidenceBytes: accumulator.depthConfidenceBytes,
            meshBytes: accumulator.meshBytes,
            roomPlanBytes: accumulator.roomPlanBytes,
            previewAndDerivedBytes: accumulator
                .previewAndDerivedBytes,
            documentBytes: accumulator.documentBytes
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

        // The room reference frame and opening review are operator
        // authority payloads (issues #231/#232): when committed, their
        // stored bytes must decode byte-exact to the tracked document.
        if let roomReferenceFrame {
            guard roomReferenceFrame.captureRevisionID
                    == identity.captureRevisionID,
                  roomReferenceFrame.captureSessionID
                    == captureSessionID,
                  roomReferenceFrame.coordinateSpaceID
                    == coordinateSpaceID
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyTypedJSON(
                path: RoomReferenceFramePackage.path,
                expected: roomReferenceFrame,
                actualByPath: actualByPath
            )
        }

        if let openingReviewDocument {
            guard openingReviewDocument.captureRevisionID
                    == identity.captureRevisionID,
                  openingReviewDocument.captureSessionID
                    == captureSessionID,
                  openingReviewDocument.coordinateSpaceID
                    == coordinateSpaceID
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyTypedJSON(
                path: OpeningReviewPackage.path,
                expected: openingReviewDocument,
                actualByPath: actualByPath
            )
        }

        if let roomFieldDatum {
            guard roomFieldDatum.captureRevisionID
                    == identity.captureRevisionID,
                  roomFieldDatum.captureSessionID
                    == captureSessionID,
                  roomFieldDatum.coordinateSpaceID
                    == coordinateSpaceID
            else {
                throw CaptureWorkingSetError.integrityVerificationFailed
            }
            try verifyTypedJSON(
                path: RoomFieldDatumPackage.path,
                expected: roomFieldDatum,
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

        if let authorityCollection {
            guard let file =
                    actualByPath[TheaterAuthorityPackage.path],
                  let data = try? Data(contentsOf: file.url),
                  let decoded = try? JSONDecoder().decode(
                    TheaterAuthorityCollection.self,
                    from: data
                  ),
                  decoded == authorityCollection
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

        // Supplemental documents commit by byte ledger: the sealed set
        // must hold exactly the bytes that were committed.
        for (path, data) in supplementalDocuments {
            try verifyFile(
                path: path,
                byteCount: data.count,
                sha256: EvidenceIntegrity.sha256(of: data),
                actualByPath: actualByPath
            )
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
                // Issue #286: user-attested and derived measurements
                // coexist in one collection for conflict review. A
                // heterogeneous collection declares capture_app_derived
                // container authority — the same conservative class an
                // empty collection uses — so the manifest never
                // overclaims and each record's provenance_class remains
                // the authoritative statement.
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
    private func evictTrackingIntervalsIfNeeded() {
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
        if entity.type == .speaker
            || entity.type == .subwoofer,
           let role = entity.channelRole
        {
            return entity.type.rawValue + ":" + role.rawValue
        }
        // Listening-position completeness keys on the typed role,
        // not the free-text label (#243).
        if entity.type == .listeningPosition,
           let role = entity.listeningRole
        {
            return entity.type.rawValue + ":" + role.rawValue
        }
        return entity.type.rawValue + ":" + entity.label
    }

    /// Validates a proposed coordinate-space binding without mutating
    /// state (issue #202). The authority binding is part of the logical
    /// persistence commit: it may only be published after the matching
    /// durable writes succeed, so validation and publication are split
    /// across the write suspension.
    private func validateCoordinateAuthority(
        _ coordinateSpaceID: CoordinateSpaceID
    ) throws {
        if let existing = self.coordinateSpaceID,
           existing != coordinateSpaceID
        {
            throw CaptureWorkingSetError.authorityMismatch
        }
    }

    /// Validates a proposed session/coordinate binding without mutating
    /// state (issue #202).
    private func validateAuthority(
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
    }

    /// Publishes a coordinate-space binding. Must only run inside the
    /// post-write commit block, with no suspension point between the
    /// last re-check and this call. The re-check is retained so a
    /// reentrant commit of a different authority fails closed instead
    /// of silently rebinding the revision (issue #202).
    private func publishCoordinateAuthority(
        _ coordinateSpaceID: CoordinateSpaceID
    ) throws {
        try validateCoordinateAuthority(coordinateSpaceID)
        self.coordinateSpaceID = coordinateSpaceID
    }

    /// Publishes a session/coordinate binding under the same rules as
    /// `publishCoordinateAuthority`.
    private func publishAuthority(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID
    ) throws {
        try validateAuthority(
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID
        )
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
    }

    /// Issue #199: an evidence reference of the form
    /// `path:evidence/frames/<frame-id>.json`, `frame:<uuid>`, or
    /// `mesh_anchor:<uuid>` is a *spatial* evidence link — it claims
    /// support from frame/mesh authority expressed in a coordinate
    /// space. Resolve every such link against committed authority and
    /// require the referenced coordinate space to equal the record's
    /// own: manifest membership alone never satisfies congruence, a
    /// link that does not resolve to committed spatial authority can
    /// never prove it, and v1 defines no cross-space alignment
    /// authority — so every mismatch or unresolvable link fails closed.
    /// References with other prefixes (`entity:`, `measurement:`,
    /// `user:`, `sha256:`, non-frame `path:` values, and
    /// annotation-authored tokens) carry no spatial authority and are
    /// out of scope.
    private func requireSpatialEvidenceLinkCongruence(
        _ ref: String,
        coordinateSpaceID: CoordinateSpaceID
    ) throws {
        guard let separator = ref.firstIndex(of: ":") else {
            return
        }
        let prefix = ref[..<separator]
        let value = String(ref[ref.index(after: separator)...])

        switch prefix {
        case "path":
            // Frame-descriptor paths resolve to the committed
            // descriptor; mesh-geometry paths resolve to the committed
            // anchor record that owns the geometry. Other `path:` links
            // carry no spatial authority and are validated by the
            // manifest/dangling-reference checks, not congruence.
            let components = value.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            if components.count == 3,
               components[0] == "evidence",
               components[1] == "frames",
               components[2].hasSuffix(".json"),
               components[2].count > ".json".count
            {
                let stem = String(
                    components[2].dropLast(".json".count)
                )
                guard let frameID = EvidenceFrameID(
                    canonicalString: stem
                ) else {
                    throw CaptureWorkingSetError
                        .unresolvableSpatialEvidenceLink(ref)
                }
                try requireFrameLinkCongruence(
                    frameID,
                    ref: ref,
                    coordinateSpaceID: coordinateSpaceID
                )
                return
            }
            if value.hasPrefix("mesh/geometry/"),
               value.hasSuffix(".meshbin")
            {
                guard let record = meshIndex?.anchors.first(where: {
                    $0.geometryPath == value
                }) else {
                    throw CaptureWorkingSetError
                        .unresolvableSpatialEvidenceLink(ref)
                }
                guard record.coordinateSpaceID == coordinateSpaceID
                else {
                    throw CaptureWorkingSetError
                        .spatialEvidenceSpaceMismatch(ref)
                }
            }
            return

        case "frame":
            guard let frameID = EvidenceFrameID(
                canonicalString: value
            ) else {
                throw CaptureWorkingSetError
                    .unresolvableSpatialEvidenceLink(ref)
            }
            try requireFrameLinkCongruence(
                frameID,
                ref: ref,
                coordinateSpaceID: coordinateSpaceID
            )

        case "mesh_anchor":
            guard let anchorID = UUID(
                canonicalUUIDv4Text: value
            ) else {
                throw CaptureWorkingSetError
                    .unresolvableSpatialEvidenceLink(ref)
            }
            try requireMeshAnchorLinkCongruence(
                anchorID,
                ref: ref,
                coordinateSpaceID: coordinateSpaceID
            )

        default:
            return
        }
    }

    /// Resolves a frame link to the committed descriptor and requires
    /// its coordinate space to equal the referencing record's space.
    private func requireFrameLinkCongruence(
        _ frameID: EvidenceFrameID,
        ref: String,
        coordinateSpaceID: CoordinateSpaceID
    ) throws {
        guard let descriptor = frameDescriptors.first(where: {
            $0.frameID == frameID
        }) else {
            throw CaptureWorkingSetError
                .unresolvableSpatialEvidenceLink(ref)
        }
        guard descriptor.coordinateSpaceID == coordinateSpaceID else {
            throw CaptureWorkingSetError
                .spatialEvidenceSpaceMismatch(ref)
        }
    }

    /// Resolves a mesh-anchor link to the committed index record and
    /// requires its coordinate space to equal the referencing record's
    /// space.
    private func requireMeshAnchorLinkCongruence(
        _ anchorID: UUID,
        ref: String,
        coordinateSpaceID: CoordinateSpaceID
    ) throws {
        let anchorText = anchorID.uuidString.lowercased()
        guard let record = meshIndex?.anchors.first(where: {
            $0.anchorID == anchorText
        }) else {
            throw CaptureWorkingSetError
                .unresolvableSpatialEvidenceLink(ref)
        }
        guard record.coordinateSpaceID == coordinateSpaceID else {
            throw CaptureWorkingSetError
                .spatialEvidenceSpaceMismatch(ref)
        }
    }

    /// Every spatial authority claim carried by an annotation entity:
    /// record-level evidence refs, placement source refs, the
    /// placement's mesh anchor, and a prefixed acoustic-center
    /// authority ref.
    private func requireSpatialEvidenceCongruence(
        entity: CaptureAnnotationEntity
    ) throws {
        for ref in entity.evidenceRefs
            + entity.placement.sourceEvidenceRefs
            + entity.contractEvidenceRefs
        {
            try requireSpatialEvidenceLinkCongruence(
                ref,
                coordinateSpaceID: entity.coordinateSpaceID
            )
        }
        if let anchorID = entity.placement.sourceMeshAnchorID {
            try requireMeshAnchorLinkCongruence(
                anchorID,
                ref: "mesh_anchor:\(anchorID.uuidString.lowercased())",
                coordinateSpaceID: entity.coordinateSpaceID
            )
        }
        if let authorityRef = entity.acousticCenter?.authorityRef {
            try requireSpatialEvidenceLinkCongruence(
                authorityRef,
                coordinateSpaceID: entity.coordinateSpaceID
            )
        }
    }

    /// Every spatial authority claim carried by a spatial measurement:
    /// record-level evidence refs and endpoint refs. Non-spatial
    /// measurements (no coordinate space) carry no congruence claim.
    private func requireSpatialEvidenceCongruence(
        measurement: CaptureMeasurement
    ) throws {
        guard let space = measurement.coordinateSpaceID else {
            return
        }
        for ref in measurement.evidenceRefs + measurement.endpointRefs {
            try requireSpatialEvidenceLinkCongruence(
                ref,
                coordinateSpaceID: space
            )
        }
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

    // MARK: - Working-revision phase marker (issue #297)

    /// Builds the persisted lifecycle record for `path
    /// session/revision-state.json`. The checkpoint captures every
    /// volatile input `evaluateQuality`/`evaluateAdvisoryDiagnostics`
    /// cannot re-derive from committed payload bytes, so a relaunched
    /// draft re-evaluates from real history rather than reporting the
    /// scan-time trackers as absent.
    private func revisionStateDocument(
        phase: WorkingRevisionPhase
    ) -> WorkingRevisionStateDocument {
        WorkingRevisionStateDocument(
            identity: identity,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            phase: phase,
            updatedAtUTC: BundleTimestamp.utcString(from: Date()),
            practice: isPracticeWorkingSet,
            checkpoint: phase.isRecoverableDraft
                ? revisionCheckpoint()
                : nil
        )
    }

    private func revisionCheckpoint() -> WorkingRevisionCheckpoint {
        WorkingRevisionCheckpoint(
            trackingIntervals: trackingIntervals.map {
                WorkingRevisionTrackingInterval(
                    state: $0.state,
                    reason: $0.reason,
                    firstSeconds: $0.firstSeconds,
                    lastSeconds: $0.lastSeconds,
                    sampleCount: $0.sampleCount
                )
            },
            resourceEvents: resourceEvents,
            benchmarkRefs: benchmarkRefs,
            taskProfile: taskProfile,
            skippedTaskRequirementIDs: skippedTaskRequirementIDs
                .sorted(),
            endBoundaryFrameIDs: endBoundaryFrameIDs.sorted {
                $0.description < $1.description
            },
            endCoverage: advisoryEndContext,
            roomPlanGuidanceAvailable: roomPlanGuidanceAvailable,
            roomPlanGuidance: roomPlanGuidanceAvailable
                ? RoomPlanGuidanceSummary(
                    roomPlanGuidanceTracker.history()
                )
                : nil,
            meshLifecycle: meshLifecycleTracker.summary(
                endSessionTimestampSeconds:
                    advisoryEndContext?.endSessionTimestampSeconds
            ),
            advisoryNotes: advisoryNotes,
            fieldNotes: fieldNotes
        )
    }

    /// Atomically rewrites the phase marker, keeping its declaration
    /// stable. Phase content changes never change the declaration, so
    /// `register`/`verifyIntegrity` stay consistent. `commitCheck`
    /// re-runs after the writer suspension: the write interleaves with
    /// other actor work, so a caller whose transaction must still be
    /// committed supplies the check (a racing rollback unwinds the
    /// marker before the phase is published, never after).
    private func persistRevisionState(
        _ phase: WorkingRevisionPhase,
        commitCheck: () throws -> Void = {}
    ) async throws {
        let document = revisionStateDocument(phase: phase)
        try await writer.writeBatchReplacing([
            try CaptureFileWriteRequest(
                data: document.encoded(),
                path: CaptureStorePath(
                    WorkingRevisionStateDocument.path
                )
            ),
        ])
        try commitCheck()
        try register(document.payloadDeclaration)
        revisionPhase = phase
    }

    /// Advances the durable phase from `end_accepted` to
    /// `semantic_authoring` — or refreshes the checkpoint while the
    /// phase is already post-End — after a semantic mutation commit.
    /// No-op for live (pre-End) revisions and for sealed/consumed
    /// stores, where the phase is managed by the seal lifecycle.
    private func refreshRevisionStateAfterSemanticCommit() async throws {
        guard sealState == .mutable,
              revisionPhase.isRecoverableDraft
        else {
            return
        }
        try await persistRevisionState(.semanticAuthoring)
    }

    /// Rejects mutations that presume a live AR coordinate authority on
    /// a store restored from disk (issue #297). Recovered drafts are
    /// spatially sealed: semantic authoring is allowed, live capture is
    /// not.
    private func requireLiveSpatialAuthority() throws {
        guard liveSpatialAuthority else {
            throw CaptureWorkingSetError.spatialAuthorityNotLive
        }
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

    /// Suspends the caller until the in-flight mutation counter drains
    /// to zero. Must only be called while it is non-zero; the last
    /// mutation's exit hook resumes every waiter on the actor.
    private func waitForMutationDrain() async {
        await withCheckedContinuation { continuation in
            mutationDrainers.append(continuation)
        }
    }

    /// Every mutation entry point decrements through this hook from its
    /// `defer` so a parked seal drain wakes exactly when the last owned
    /// mutation leaves the actor (issue #180).
    private func mutationDidFinish() {
        inFlightMutations -= 1
        if inFlightMutations == 0, !mutationDrainers.isEmpty {
            let drainers = mutationDrainers
            mutationDrainers.removeAll()
            for drainer in drainers {
                drainer.resume(returning: ())
            }
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


    // MARK: - Working-revision restore (issue #297)

    /// Reopens an end-accepted working revision left behind by a prior
    /// process. The relaunch reads `session/revision-state.json`,
    /// decodes every committed payload back into working-set state, and
    /// returns a store whose spatial authority is permanently sealed:
    /// semantic authoring and finalization work, live capture does not.
    ///
    /// Restore is all-or-nothing on *canonical* payloads: a missing or
    /// corrupt End-transaction file fails the whole restore rather than
    /// surfacing a half-true draft. Unrecognized extra files are kept,
    /// declared generically, and reported — never silently dropped.
    public static func restoreWorkingRevision(
        _ draft: RecoverableWorkingRevision
    ) async throws -> (
        store: CaptureWorkingSetStore,
        report: WorkingRevisionRestoreReport
    ) {
        let stateData: Data
        do {
            stateData = try Data(
                contentsOf: draft.url
                    .appendingPathComponent(
                        "session",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        "revision-state.json",
                        isDirectory: false
                    )
            )
        } catch {
            throw CaptureWorkingSetError
                .workingRevisionNotRecoverable
        }
        let state: WorkingRevisionStateDocument
        do {
            state = try WorkingRevisionStateDocument.decode(stateData)
        } catch {
            throw CaptureWorkingSetError
                .workingRevisionNotRecoverable
        }
        guard state.phase.isRecoverableDraft,
              !state.practice,
              state.captureRevisionID == draft.revisionID
        else {
            throw CaptureWorkingSetError
                .workingRevisionNotRecoverable
        }
        let store = try CaptureWorkingSetStore(
            identity: CaptureWorkingSetIdentity(
                captureSeriesID: state.captureSeriesID,
                captureRevisionID: state.captureRevisionID,
                parentRevisionID: state.parentRevisionID,
                createdAtUTC: state.createdAtUTC
            ),
            rootDirectory: draft.url
        )
        let report =
            try await store.restoreWorkingRevisionFromDisk(
                stateDocument: state
            )
        return (store, report)
    }

    private func restoreWorkingRevisionFromDisk(
        stateDocument state: WorkingRevisionStateDocument
    ) async throws -> WorkingRevisionRestoreReport {
        guard sealState == .mutable,
              sessionFoundation == nil,
              declarations.isEmpty
        else {
            throw CaptureWorkingSetError.workingSetSealed
        }
        guard let checkpoint = state.checkpoint else {
            throw CaptureWorkingSetError
                .workingRevisionNotRecoverable
        }

        let scanned = try BundleDirectoryScanner.scan(
            root: rootDirectory
        )
        var scannedByPath = Dictionary(
            uniqueKeysWithValues: scanned.map { ($0.path, $0) }
        )
        func readConsumed(
            _ path: String,
            required: Bool = true
        ) throws -> Data? {
            guard let file = scannedByPath.removeValue(
                forKey: path
            )
            else {
                if required {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
                return nil
            }
            return try Data(contentsOf: file.url)
        }
        func consumeIfPresent(_ path: String) {
            scannedByPath.removeValue(forKey: path)
        }

        var supersededPaths: [String] = []
        var missingCheckpoint: [String] = []

        // 1. Session foundation (required: written before any spatial
        //    commit and bound by the End transaction).
        guard
            let capabilitiesData = try readConsumed(
                CaptureSessionFoundationPackage.capabilitiesPath
            ),
            let configurationData = try readConsumed(
                CaptureSessionFoundationPackage.configurationPath
            ),
            let deviceData = try readConsumed(
                CaptureSessionFoundationPackage.devicePath
            ),
            let sessionData = try readConsumed(
                CaptureSessionFoundationPackage.sessionPath
            )
        else {
            throw CaptureWorkingSetError
                .invalidSessionFoundationPackage
        }
        let decoder = JSONDecoder()
        guard
            let capabilities = try? decoder.decode(
                CaptureCapabilitiesDocument.self,
                from: capabilitiesData
            ),
            let configuration = try? decoder.decode(
                CaptureConfigurationDocument.self,
                from: configurationData
            ),
            let device = try? decoder.decode(
                CaptureDeviceDocument.self,
                from: deviceData
            ),
            let session = try? decoder.decode(
                CaptureSessionDocument.self,
                from: sessionData
            )
        else {
            throw CaptureWorkingSetError
                .invalidSessionFoundationPackage
        }
        let foundation = CaptureSessionFoundationPackage(
            session: session,
            capabilities: capabilities,
            configuration: configuration,
            device: device,
            sessionData: sessionData,
            capabilitiesData: capabilitiesData,
            configurationData: configurationData,
            deviceData: deviceData
        )
        try publishAuthority(
            captureSessionID: session.captureSessionID,
            coordinateSpaceID: session.coordinateSpaceID
        )
        for declaration in foundation.payloadDeclarations {
            try register(declaration)
        }
        sessionFoundation = foundation
        // The marker itself is declared but not re-read from the scan
        // set — remove it so the leftover sweep cannot re-register it.
        consumeIfPresent(WorkingRevisionStateDocument.path)
        try register(state.payloadDeclaration)

        // 2. The End RoomPlan transaction — required in full because
        //    the phase marker only advances when it committed.
        guard
            let timingData = try readConsumed(
                CaptureTimingPackage.path
            ),
            let metadataData = try readConsumed(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            ),
            let policyData = try readConsumed(
                CoordinateSpacePolicyPackage.path
            )
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        guard
            let timingDoc = try? decoder.decode(
                CaptureTimingDocument.self,
                from: timingData
            ),
            let metadataDoc = try? decoder.decode(
                CapturedRoomMetadataDocument.self,
                from: metadataData
            ),
            let policyDoc = try? decoder.decode(
                CoordinateSpacePolicyDocument.self,
                from: policyData
            )
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        // The lineage document carries every descriptor field, so the
        // raw/processed descriptors rebuild deterministically and the
        // recorded hashes re-verify the payloads on disk.
        let rawDescriptor = RoomPlanRawEvidenceDescriptor(
            captureSessionID: metadataDoc.captureSessionID,
            coordinateSpaceID: metadataDoc.coordinateSpaceID,
            relativePath: metadataDoc.rawPayloadPath,
            byteCount: metadataDoc.rawByteCount,
            sha256: metadataDoc.rawSHA256,
            serializationFormat: metadataDoc.rawSerializationFormat,
            runtime: metadataDoc.runtime
        )
        guard
            let rawData = try readConsumed(
                rawDescriptor.relativePath
            ),
            rawData.count == rawDescriptor.byteCount,
            EvidenceIntegrity.sha256(of: rawData)
                == rawDescriptor.sha256
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        guard
            let processedPath = metadataDoc.processedPayloadPath,
            let processedSHA = metadataDoc.processedSHA256,
            let processedBytes = metadataDoc.processedByteCount,
            let processedFormat =
                metadataDoc.processedSerializationFormat
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        let processedDescriptor = RoomPlanProcessedEvidenceDescriptor(
            captureSessionID: metadataDoc.captureSessionID,
            coordinateSpaceID: metadataDoc.coordinateSpaceID,
            relativePath: processedPath,
            byteCount: processedBytes,
            sha256: processedSHA,
            sourceRawSHA256: rawDescriptor.sha256,
            serializationFormat: processedFormat,
            capturedRoomVersion: metadataDoc.capturedRoomVersion,
            runtime: metadataDoc.runtime
        )
        guard
            let processedData = try readConsumed(
                processedDescriptor.relativePath
            ),
            processedData.count == processedDescriptor.byteCount,
            EvidenceIntegrity.sha256(of: processedData)
                == processedDescriptor.sha256,
            metadataDoc.captureRevisionID
                == identity.captureRevisionID,
            metadataDoc.captureSessionID == captureSessionID,
            metadataDoc.coordinateSpaceID == coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        guard policyDoc.captureRevisionID
                == identity.captureRevisionID,
              policyDoc.captureSessionID == captureSessionID,
              policyDoc.coordinateSpaceID == coordinateSpaceID
        else {
            throw CaptureWorkingSetError
                .integrityVerificationFailed
        }
        timingDocument = timingDoc
        try register(
            CaptureTimingPackage(
                document: timingDoc,
                data: timingData
            ).payloadDeclaration
        )
        try register(
            BundlePayloadDeclaration(
                path: rawDescriptor.relativePath,
                mediaType: "application/json",
                producer: "roomplan_capture",
                provenanceClass: .appleRoomPlanRawScan,
                role: .canonical
            )
        )
        try register(
            BundlePayloadDeclaration(
                path: processedDescriptor.relativePath,
                mediaType: "application/json",
                producer: "roomplan_builder",
                provenanceClass: .appleRoomPlanInference,
                role: .canonical,
                sourceRefs: [
                    "sha256:\(rawDescriptor.sha256.description)"
                ]
            )
        )
        try register(
            roomPlanMetadataDeclaration(
                raw: rawDescriptor,
                processed: processedDescriptor
            )
        )
        try register(
            CoordinateSpacePolicyPackage(
                document: policyDoc,
                data: policyData
            ).payloadDeclaration
        )
        rawRoomPlanDescriptor = rawDescriptor
        processedRoomPlanDescriptor = processedDescriptor
        capturedRoomMetadata = metadataDoc
        coordinateSpacePolicy = policyDoc

        // 3. Mesh index + geometry (optional).
        if let indexData = try readConsumed(
            MeshEvidencePackage.indexPath,
            required: false
        ) {
            guard
                let index = try? decoder.decode(
                    MeshAnchorEvidenceIndex.self,
                    from: indexData
                )
            else {
                throw CaptureWorkingSetError.invalidMeshPackage
            }
            var geometryRefs: [String] = []
            var usableAnchors = 0
            for record in index.anchors {
                guard
                    let geometryData = try readConsumed(
                        record.geometryPath
                    ),
                    geometryData.count > 0,
                    EvidenceIntegrity.sha256(of: geometryData)
                        == record.geometrySHA256,
                    let geometry = try? MeshBinaryCodec.decode(
                        geometryData
                    ),
                    geometry.vertices.count == record.vertexCount,
                    geometry.faceCount == record.faceCount
                else {
                    throw CaptureWorkingSetError.invalidMeshPackage
                }
                if !geometry.vertices.isEmpty,
                   geometry.faceCount > 0
                {
                    usableAnchors += 1
                }
                meshGeometryProfile.record(
                    worldFromAnchor: record.worldFromAnchor,
                    geometry: geometry
                )
                geometryRefs.append("path:" + record.geometryPath)
                try register(
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
            }
            try register(
                BundlePayloadDeclaration(
                    path: MeshEvidencePackage.indexPath,
                    mediaType: "application/json",
                    producer: "mesh_capture",
                    provenanceClass: .arkitMeshReconstruction,
                    role: .canonical,
                    sourceRefs: geometryRefs.isEmpty
                        ? nil
                        : geometryRefs.sorted()
                )
            )
            meshIndex = index
            meshAnchorCount = index.anchors.count
            usableMeshAnchorCount = usableAnchors
        }

        // 4. Evidence frames (optional set): each committed frame is a
        //    descriptor JSON plus its declared sibling payloads. The
        //    builder revalidates every recorded hash.
        let frameDescriptorPaths = scannedByPath.keys.filter {
            $0.hasPrefix("evidence/frames/") && $0.hasSuffix(".json")
        }
        .sorted(by: BundleLogicalPath.utf8Less)
        for descriptorPath in frameDescriptorPaths {
            guard
                let descriptorData = try readConsumed(descriptorPath),
                let descriptor = try? decoder.decode(
                    FrameEvidenceDescriptor.self,
                    from: descriptorData
                ),
                descriptorPath
                    == "evidence/frames/"
                        + descriptor.frameID.description + ".json"
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            let pixelPath = descriptor.pixelRelativePath
            guard
                let pixelData = try readConsumed(pixelPath)
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            var depthData: Data?
            var confidenceData: Data?
            if let depth = descriptor.depth {
                depthData = try readConsumed(depth.depthRelativePath)
                guard depthData != nil else {
                    throw CaptureWorkingSetError
                        .integrityVerificationFailed
                }
                if let confidencePath = depth.confidenceRelativePath {
                    confidenceData = try readConsumed(confidencePath)
                    guard confidenceData != nil else {
                        throw CaptureWorkingSetError
                            .integrityVerificationFailed
                    }
                }
            }
            let previewPath =
                "evidence/frames/"
                    + descriptor.frameID.description
                    + ".preview.heic"
            let previewData = try readConsumed(
                previewPath,
                required: false
            )
            // The builder enforces canonical paths plus byte-count and
            // SHA-256 agreement across the whole package.
            let package = try FrameEvidencePackageBuilder.build(
                descriptor: descriptor,
                pixelPayload: pixelData,
                depthPayload: depthData,
                confidencePayload: confidenceData,
                previewPayload: previewData
            )
            try validateAuthority(
                captureSessionID: descriptor.captureSessionID,
                coordinateSpaceID: descriptor.coordinateSpaceID
            )
            for declaration in package.payloadDeclarations {
                try register(declaration)
            }
            frameDescriptors.append(package.descriptor)
            evidenceFrameCount += 1
            depthEvidenceCount += package.capturedDepthCount
            let usableSamples = Self.usableDepthSamples(
                in: package.depthPayload
            )
            usableDepthSampleCount += usableSamples
            if usableSamples > 0 {
                usableDepthEvidenceCount += 1
            }
            if let depthPayload = package.depthPayload,
               let depth = try? DepthBinaryCodec.decode(depthPayload)
            {
                let confidence = package.confidencePayload
                    .flatMap { try? ConfidenceBinaryCodec.decode($0) }
                depthSufficiencyAccumulator.record(
                    depth: depth,
                    confidence: confidence
                )
            }
            if let preview = package.preview,
               !framePreviews.contains(preview)
            {
                framePreviews.append(preview)
            }
        }

        // 5. Semantic authoring payloads (optional). They reuse the
        //    exact commit-time validators, so a restored draft cannot
        //    carry authority that would fail the live path.
        if let annotationData = try readConsumed(
            AnnotationEvidencePackage.path,
            required: false
        ) {
            guard
                let collection = try? decoder.decode(
                    CaptureAnnotationCollection.self,
                    from: annotationData
                )
            else {
                throw CaptureWorkingSetError
                    .invalidAnnotationPackage
            }
            let spaces = Set(
                collection.entities.map(\.coordinateSpaceID)
            )
            guard spaces.count <= 1 else {
                throw CaptureWorkingSetError.authorityMismatch
            }
            for entity in collection.entities {
                try requireSpatialEvidenceCongruence(entity: entity)
            }
            try register(
                BundlePayloadDeclaration(
                    path: AnnotationEvidencePackage.path,
                    mediaType: "application/json",
                    producer: "annotation",
                    provenanceClass:
                        try annotationCollectionProvenance(
                            collection
                        ),
                    role: .canonical
                )
            )
            annotationCollection = collection
            annotationKeysPresent = Set(
                collection.entities.map(annotationQualityKey)
            )
        }
        if let measurementData = try readConsumed(
            MeasurementEvidencePackage.path,
            required: false
        ) {
            guard
                let collection = try? decoder.decode(
                    CaptureMeasurementCollection.self,
                    from: measurementData
                )
            else {
                throw CaptureWorkingSetError
                    .invalidMeasurementPackage
            }
            let spaces = Set(
                collection.measurements.compactMap(
                    \.coordinateSpaceID
                )
            )
            guard spaces.count <= 1 else {
                throw CaptureWorkingSetError.authorityMismatch
            }
            for measurement in collection.measurements {
                try requireSpatialEvidenceCongruence(
                    measurement: measurement
                )
            }
            try register(
                BundlePayloadDeclaration(
                    path: MeasurementEvidencePackage.path,
                    mediaType: "application/json",
                    producer: "measurement",
                    provenanceClass:
                        try measurementCollectionProvenance(
                            collection
                        ),
                    role: .canonical
                )
            )
            measurementCollection = collection
            measurementQuantityTypesPresent = Set(
                collection.measurements.map(\.quantityType)
            )
        }
        if let authorityData = try readConsumed(
            TheaterAuthorityPackage.path,
            required: false
        ) {
            guard
                let collection = try? decoder.decode(
                    TheaterAuthorityCollection.self,
                    from: authorityData
                )
            else {
                throw CaptureWorkingSetError
                    .invalidAuthorityPackage
            }
            let validated = try validateTheaterAuthorityPackage(
                TheaterAuthorityPackage(
                    collection: collection,
                    data: authorityData
                ),
                entities: annotationCollection?.entities ?? [],
                relations: annotationCollection?.relations ?? []
            )
            try register(validated.authorityDeclaration)
            authorityCollection = collection
        }
        if let identityData = try readConsumed(
            EquipmentIdentityEvidencePackage.path,
            required: false
        ) {
            guard
                let document = try? decoder.decode(
                    EquipmentIdentityDocument.self,
                    from: identityData
                ),
                let committedEntities =
                    annotationCollection?.entities
            else {
                throw CaptureWorkingSetError
                    .invalidAnnotationPackage
            }
            _ = try EquipmentIdentityDocument(
                captureRevisionID: document.captureRevisionID,
                coordinateSpaceID: document.coordinateSpaceID,
                records: document.records,
                entities: committedEntities,
                recordedAtUTC: document.recordedAtUTC
            )
            let package = try EquipmentIdentityEvidencePackage(
                document: document
            )
            try register(
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
        if let frameData = try readConsumed(
            RoomReferenceFramePackage.path,
            required: false
        ) {
            guard
                let document = try? decoder.decode(
                    RoomReferenceFrameDocument.self,
                    from: frameData
                ),
                document.captureRevisionID
                    == identity.captureRevisionID,
                document.captureSessionID == captureSessionID,
                document.coordinateSpaceID == coordinateSpaceID
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            try register(
                RoomReferenceFramePackage(
                    document: document,
                    data: frameData
                ).payloadDeclaration
            )
            roomReferenceFrame = document
        }
        if let reviewData = try readConsumed(
            OpeningReviewPackage.path,
            required: false
        ) {
            guard
                let document = try? decoder.decode(
                    OpeningReviewDocument.self,
                    from: reviewData
                ),
                document.captureRevisionID
                    == identity.captureRevisionID,
                document.captureSessionID == captureSessionID,
                document.coordinateSpaceID == coordinateSpaceID
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            for opening in document.openings {
                for ref in opening.evidenceRefs {
                    try requireSpatialEvidenceLinkCongruence(
                        ref,
                        coordinateSpaceID:
                            document.coordinateSpaceID
                    )
                }
            }
            try register(
                OpeningReviewPackage(
                    document: document,
                    data: reviewData
                ).payloadDeclaration
            )
            openingReviewDocument = document
        }
        if let advisoryData = try readConsumed(
            CaptureAdvisoryNoteDocument.path,
            required: false
        ) {
            guard
                let document = try? decoder.decode(
                    CaptureAdvisoryNoteDocument.self,
                    from: advisoryData
                ),
                document.captureRevisionID
                    == identity.captureRevisionID
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            advisoryNotes = document.notes
            try register(
                BundlePayloadDeclaration(
                    path: CaptureAdvisoryNoteDocument.path,
                    mediaType: "application/json",
                    producer: "capture_advisory",
                    provenanceClass: .captureAppDerived,
                    role: .derived
                )
            )
        } else {
            advisoryNotes = checkpoint.advisoryNotes
            if !advisoryNotes.isEmpty {
                missingCheckpoint.append("operator_advisories_file")
            }
        }
        if let fieldNotesData = try readConsumed(
            CaptureFieldNoteDocument.path,
            required: false
        ) {
            guard
                let document = try? decoder.decode(
                    CaptureFieldNoteDocument.self,
                    from: fieldNotesData
                ),
                document.captureRevisionID
                    == identity.captureRevisionID
            else {
                throw CaptureWorkingSetError
                    .integrityVerificationFailed
            }
            fieldNotes = document.notes
            try register(Self.fieldNotesDeclaration)
        } else {
            fieldNotes = checkpoint.fieldNotes
            if !fieldNotes.isEmpty {
                missingCheckpoint.append("field_notes_file")
            }
        }

        // 6. Operator supplemental payloads at reserved paths — these
        //    carry the workflow state (task plan/status, connected
        //    spaces, reference targets, derived candidates, as-built)
        //    the recovered Review must show again.
        for (path, binding) in BundleReservedPaths.exact {
            switch path {
            case
                "session/capture-task-plan.json",
                "session/task-plan-status.json",
                "session/connected-spaces.json",
                "session/field-notes.json",
                "evidence/reference-targets.json",
                "derived/geometry-candidates.json",
                "verification/as-built.json":
                break
            default:
                continue
            }
            guard let data = try readConsumed(
                path,
                required: false
            ) else {
                continue
            }
            try register(
                BundlePayloadDeclaration(
                    path: path,
                    mediaType: binding.mediaType,
                    producer: binding.producer,
                    provenanceClass: binding.provenanceClass,
                    role: binding.role
                )
            )
            supplementalDocuments[path] = data
        }

        // 7. Stale seal-time outputs are superseded by definition: a
        //    relaunched draft re-evaluates quality from restored state,
        //    so remove them (and report it) rather than let a prior
        //    process's verdict shadow the recovered one.
        for superseded in [
            "quality/capture-quality.json",
            "quality/capture-advisory.json",
        ] where scannedByPath[superseded] != nil {
            consumeIfPresent(superseded)
            try await writer.removeIfPresent(
                CaptureStorePath(superseded)
            )
            supersededPaths.append(superseded)
        }

        // 8. Anything the inventory could not classify stays on disk,
        //    declared generically, and is reported as unsupported —
        //    never silently dropped and never blocking recovery.
        var unsupportedPaths: [String] = []
        for path in scannedByPath.keys.sorted(
            by: BundleLogicalPath.utf8Less
        ) {
            unsupportedPaths.append(path)
            try register(
                BundlePayloadDeclaration(
                    path: path,
                    mediaType: "application/octet-stream",
                    producer: "capture_app",
                    provenanceClass: .captureAppDerived,
                    role: .derived
                )
            )
        }

        // 9. Checkpoint → volatile evaluation inputs.
        trackingIntervals = checkpoint.trackingIntervals.map {
            TrackingInterval(
                state: $0.state,
                reason: $0.reason,
                firstSeconds: $0.firstSeconds,
                lastSeconds: $0.lastSeconds,
                sampleCount: $0.sampleCount
            )
        }
        resourceEvents = checkpoint.resourceEvents
        benchmarkRefs = checkpoint.benchmarkRefs
        taskProfile = checkpoint.taskProfile
        skippedTaskRequirementIDs = Set(
            checkpoint.skippedTaskRequirementIDs
        )
        endBoundaryFrameIDs = Set(checkpoint.endBoundaryFrameIDs)
        advisoryEndContext = checkpoint.endCoverage
        if checkpoint.endCoverage == nil {
            missingCheckpoint.append("end_coverage")
        }
        roomPlanGuidanceAvailable =
            checkpoint.roomPlanGuidanceAvailable
        recoveredRoomPlanGuidance = checkpoint.roomPlanGuidance
        if checkpoint.roomPlanGuidanceAvailable,
           checkpoint.roomPlanGuidance == nil
        {
            missingCheckpoint.append("roomplan_guidance")
        }
        recoveredMeshLifecycle = checkpoint.meshLifecycle
        if checkpoint.meshLifecycle == nil {
            missingCheckpoint.append("mesh_lifecycle")
        }
        if checkpoint.taskProfile == nil,
           !checkpoint.skippedTaskRequirementIDs.isEmpty
        {
            missingCheckpoint.append("task_profile")
        }

        liveSpatialAuthority = false
        revisionPhase = state.phase

        // Everything now mirrors what the live commit path produced;
        // run the same byte-vs-declaration proof a seal runs.
        try verifyIntegrity()

        return WorkingRevisionRestoreReport(
            unsupportedPaths: unsupportedPaths,
            supersededPaths: supersededPaths,
            missingCheckpointFields: missingCheckpoint.sorted()
        )
    }

    /// Reads the durable phase marker of a `working/<uuid>` directory
    /// without mutating anything. Used by the inventory to separate
    /// recoverable post-End drafts from mid-scan leftovers (issue #297).
    public static func peekRevisionPhase(
        workingRevisionURL url: URL
    ) -> WorkingRevisionStateDocument? {
        guard
            let data = try? Data(
                contentsOf: url
                    .appendingPathComponent(
                        "session",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        "revision-state.json",
                        isDirectory: false
                    )
            ),
            let document = try? WorkingRevisionStateDocument
                .decode(data)
        else {
            return nil
        }
        return document
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
