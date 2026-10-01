import Foundation

/// Durable lifecycle phase of a `working/<uuid>` revision (issue #297).
///
/// The record lives at `session/revision-state.json` inside the working
/// directory — a declared payload, so `verifyIntegrity` keeps its
/// files-vs-declarations contract and the marker is persisted with the
/// same atomic writer batches as the evidence it describes.
///
/// Semantics a relaunch can rely on:
/// - The document is written at session-foundation commit with
///   `liveScanIncomplete`, rewritten inside the End RoomPlan
///   transaction with `endAccepted`, advanced to `semanticAuthoring`
///   on the first post-End semantic commit, and to `readyToFinalize`
///   inside `sealForFinalization`. A directory without a decodable
///   document, or with `liveScanIncomplete`, is a mid-scan leftover:
///   its AR coordinate authority died with the process and it is never
///   resumable (the #224 abandoned-revision path) — unless the
///   complete durable End payload set is present, which proves the
///   End batch committed and only the marker-flip write was lost;
///   restore then heals the marker to `endAccepted`.
/// - `endAccepted`/`semanticAuthoring`/`readyToFinalize` mean the End
///   transaction committed durably: the revision reopens into a
///   spatially sealed Review — semantic authoring and finalization are
///   allowed, live capture is not.
public enum WorkingRevisionPhase: String, Codable, Sendable, Equatable {
    case liveScanIncomplete = "live_scan_incomplete"
    case endAccepted = "end_accepted"
    case semanticAuthoring = "semantic_authoring"
    case readyToFinalize = "ready_to_finalize"

    /// True when the phase proves an accepted End boundary, so the
    /// revision may reopen as a recovered draft after relaunch.
    public var isRecoverableDraft: Bool {
        self != .liveScanIncomplete
    }
}

/// Volatile evaluation inputs checkpointed at the End commit so a
/// relaunched draft re-derives the same quality and advisory verdicts
/// instead of reporting scan-time trackers as absent (issue #297).
public struct WorkingRevisionCheckpoint: Codable, Sendable, Equatable {
    /// Compacted tracking-run intervals (the source of `trackingEvents`
    /// in `evaluateQuality`). Persisted verbatim because the AR frame
    /// stream that produced them cannot be replayed.
    public let trackingIntervals: [WorkingRevisionTrackingInterval]
    public let resourceEvents: [CaptureResourceEvent]
    public let benchmarkRefs: [String]
    /// Operator capture-task profile (#217/#259), persisted so task
    /// completeness re-evaluates against the recovered annotations.
    public let taskProfile: CaptureTaskProfile?
    public let skippedTaskRequirementIDs: [String]
    /// The accepted End boundary's closing frame markers (#241).
    public let endBoundaryFrameIDs: [EvidenceFrameID]
    /// The advisory End-boundary coverage snapshot (#223).
    public let endCoverage: CaptureEndCoverageSummary?
    /// RoomPlan coaching history as recorded during the scan (#260) —
    /// persisted because the delegate feed died with the session.
    public let roomPlanGuidanceAvailable: Bool
    public let roomPlanGuidance: RoomPlanGuidanceSummary?
    /// Mesh anchor lifecycle summary (#268), likewise unrecoverable
    /// from the committed index alone.
    public let meshLifecycle: MeshAnchorLifecycleSummary?
    /// Operator/provenance advisory notes (#277) — also committed as
    /// `advisory/operator-advisories.json`; carried here so a recovery
    /// that finds the advisory file missing still has the notes.
    public let advisoryNotes: [CaptureAdvisoryNote]
    /// Operator field notes (#375) — also committed as
    /// `session/field-notes.json`; carried here so recovery still has
    /// them when the file itself is missing.
    public let fieldNotes: [CaptureFieldNote]

    public init(
        trackingIntervals: [WorkingRevisionTrackingInterval],
        resourceEvents: [CaptureResourceEvent],
        benchmarkRefs: [String],
        taskProfile: CaptureTaskProfile?,
        skippedTaskRequirementIDs: [String],
        endBoundaryFrameIDs: [EvidenceFrameID],
        endCoverage: CaptureEndCoverageSummary?,
        roomPlanGuidanceAvailable: Bool,
        roomPlanGuidance: RoomPlanGuidanceSummary?,
        meshLifecycle: MeshAnchorLifecycleSummary?,
        advisoryNotes: [CaptureAdvisoryNote],
        fieldNotes: [CaptureFieldNote] = []
    ) {
        self.trackingIntervals = trackingIntervals
        self.resourceEvents = resourceEvents
        self.benchmarkRefs = benchmarkRefs
        self.taskProfile = taskProfile
        self.skippedTaskRequirementIDs = skippedTaskRequirementIDs
        self.endBoundaryFrameIDs = endBoundaryFrameIDs
        self.endCoverage = endCoverage
        self.roomPlanGuidanceAvailable = roomPlanGuidanceAvailable
        self.roomPlanGuidance = roomPlanGuidance
        self.meshLifecycle = meshLifecycle
        self.advisoryNotes = advisoryNotes
        self.fieldNotes = fieldNotes
    }

    private enum CodingKeys: String, CodingKey {
        case trackingIntervals = "tracking_intervals"
        case resourceEvents = "resource_events"
        case benchmarkRefs = "benchmark_refs"
        case taskProfile = "task_profile"
        case skippedTaskRequirementIDs =
            "skipped_task_requirement_ids"
        case endBoundaryFrameIDs = "end_boundary_frame_ids"
        case endCoverage = "end_coverage"
        case roomPlanGuidanceAvailable =
            "roomplan_guidance_available"
        case roomPlanGuidance = "roomplan_guidance"
        case meshLifecycle = "mesh_lifecycle"
        case advisoryNotes = "advisory_notes"
        case fieldNotes = "field_notes"
    }

    /// Back-compatible decode: `field_notes` did not exist on
    /// checkpoints written before issue #375, so it tolerates a
    /// missing key while every older field keeps its strict
    /// requirement.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        trackingIntervals = try container.decode(
            [WorkingRevisionTrackingInterval].self,
            forKey: .trackingIntervals
        )
        resourceEvents = try container.decode(
            [CaptureResourceEvent].self,
            forKey: .resourceEvents
        )
        benchmarkRefs = try container.decode(
            [String].self,
            forKey: .benchmarkRefs
        )
        taskProfile = try container.decodeIfPresent(
            CaptureTaskProfile.self,
            forKey: .taskProfile
        )
        skippedTaskRequirementIDs = try container.decode(
            [String].self,
            forKey: .skippedTaskRequirementIDs
        )
        endBoundaryFrameIDs = try container.decode(
            [EvidenceFrameID].self,
            forKey: .endBoundaryFrameIDs
        )
        endCoverage = try container.decodeIfPresent(
            CaptureEndCoverageSummary.self,
            forKey: .endCoverage
        )
        roomPlanGuidanceAvailable = try container.decode(
            Bool.self,
            forKey: .roomPlanGuidanceAvailable
        )
        roomPlanGuidance = try container.decodeIfPresent(
            RoomPlanGuidanceSummary.self,
            forKey: .roomPlanGuidance
        )
        meshLifecycle = try container.decodeIfPresent(
            MeshAnchorLifecycleSummary.self,
            forKey: .meshLifecycle
        )
        advisoryNotes = try container.decode(
            [CaptureAdvisoryNote].self,
            forKey: .advisoryNotes
        )
        fieldNotes = try container.decodeIfPresent(
            [CaptureFieldNote].self,
            forKey: .fieldNotes
        ) ?? []
    }
}

/// Codable mirror of the working set's compacted tracking interval.
/// Decoding treats the fields as untrusted: non-finite or out-of-order
/// bounds fail recovery validation rather than silently clamping the
/// quality input.
public struct WorkingRevisionTrackingInterval:
    Codable,
    Sendable,
    Equatable
{
    public var state: TrackingQualityState
    public var reason: String?
    public var firstSeconds: Double
    public var lastSeconds: Double
    public var sampleCount: Int

    public init(
        state: TrackingQualityState,
        reason: String?,
        firstSeconds: Double,
        lastSeconds: Double,
        sampleCount: Int
    ) {
        self.state = state
        self.reason = reason
        self.firstSeconds = firstSeconds
        self.lastSeconds = lastSeconds
        self.sampleCount = sampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reason
        case firstSeconds = "first_seconds"
        case lastSeconds = "last_seconds"
        case sampleCount = "sample_count"
    }
}

/// Codable mirror of `RoomPlanGuidanceHistory` suitable for a
/// checkpoint document — kept as its own record so the persisted
/// schema, not the live tracker shape, controls the wire contract.
public struct RoomPlanGuidanceSummary: Codable, Sendable, Equatable {
    public let source: String
    public let transitions: [RoomPlanGuidanceTransition]
    public let truncated: Bool

    public init(
        source: String,
        transitions: [RoomPlanGuidanceTransition],
        truncated: Bool
    ) {
        self.source = source
        self.transitions = transitions
        self.truncated = truncated
    }

    public init(_ history: RoomPlanGuidanceHistory) {
        self.source = history.source.rawValue
        self.transitions = history.transitions
        self.truncated = history.truncated
    }

    public var history: RoomPlanGuidanceHistory? {
        guard let source = RoomPlanGuidanceSource(rawValue: source)
        else {
            return nil
        }
        return RoomPlanGuidanceHistory(
            source: source,
            transitions: transitions,
            truncated: truncated
        )
    }
}

/// Persisted lifecycle record at `session/revision-state.json`. Small
/// enough to rewrite on every phase transition; the `checkpoint` is
/// present exactly when the revision has committed an End boundary.
public struct WorkingRevisionStateDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let path = "session/revision-state.json"
    public static let expectedSchema = "htdt.working-revision-state"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    public let parentRevisionID: CaptureRevisionID?
    public let createdAtUTC: String
    public let captureSessionID: CaptureSessionID?
    public let coordinateSpaceID: CoordinateSpaceID?
    public let phase: WorkingRevisionPhase
    public let updatedAtUTC: String
    /// True when the revision was created under practice mode
    /// (issue #320): it can never be finalized and is never surfaced as
    /// a recoverable real capture.
    public let practice: Bool
    public let checkpoint: WorkingRevisionCheckpoint?

    public init(
        identity: CaptureWorkingSetIdentity,
        captureSessionID: CaptureSessionID?,
        coordinateSpaceID: CoordinateSpaceID?,
        phase: WorkingRevisionPhase,
        updatedAtUTC: String,
        practice: Bool = false,
        checkpoint: WorkingRevisionCheckpoint? = nil
    ) {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.captureSeriesID = identity.captureSeriesID
        self.captureRevisionID = identity.captureRevisionID
        self.parentRevisionID = identity.parentRevisionID
        self.createdAtUTC = identity.createdAtUTC
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.phase = phase
        self.updatedAtUTC = updatedAtUTC
        self.practice = practice
        self.checkpoint = checkpoint
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureSeriesID = "capture_series_id"
        case captureRevisionID = "capture_revision_id"
        case parentRevisionID = "parent_revision_id"
        case createdAtUTC = "created_at_utc"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case phase
        case updatedAtUTC = "updated_at_utc"
        case practice
        case checkpoint
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

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Strict decode for the relaunch path: schema/version must match
    /// exactly so a document written by a newer app is surfaced as
    /// unsupported rather than half-interpreted.
    public static func decode(_ data: Data) throws
        -> WorkingRevisionStateDocument
    {
        let document = try JSONDecoder().decode(
            WorkingRevisionStateDocument.self,
            from: data
        )
        guard document.schema == expectedSchema,
              document.schemaVersion == expectedSchemaVersion
        else {
            throw CaptureWorkingSetError.unsupportedRevisionStateSchema
        }
        return document
    }
}

/// A `working/<uuid>` revision whose End boundary committed durably and
/// whose phase marker survived relaunch (issue #297). It reopens into
/// Review with spatial authority sealed; it is never resumable as a
/// live scan.
public struct RecoverableWorkingRevision:
    Sendable, Equatable, Identifiable
{
    public let url: URL
    public let revisionID: CaptureRevisionID
    public let phase: WorkingRevisionPhase
    public let captureSessionID: CaptureSessionID?
    public let coordinateSpaceID: CoordinateSpaceID?
    public let retainedBytes: Int64
    /// Payload files the recovery loader could not classify — kept on
    /// disk, declared generically, and reported rather than silently
    /// dropped. Populated at inventory time so the operator sees the
    /// caveat before reopening.
    public let unsupportedPaths: [String]
    /// True when a `liveScanIncomplete` marker sits next to the
    /// complete durable End payload set — the marker-flip write was
    /// lost after the atomic End batch committed, so the draft
    /// actually reached End and restore heals the marker.
    public let endEvidenceCommitted: Bool

    /// Phase to present: a lost marker-flip draft reads as its true
    /// post-End phase, not as an interrupted scan.
    public var displayPhase: WorkingRevisionPhase {
        phase == .liveScanIncomplete && endEvidenceCommitted
            ? .endAccepted
            : phase
    }

    public init(
        url: URL,
        revisionID: CaptureRevisionID,
        phase: WorkingRevisionPhase,
        captureSessionID: CaptureSessionID?,
        coordinateSpaceID: CoordinateSpaceID?,
        retainedBytes: Int64,
        unsupportedPaths: [String] = [],
        endEvidenceCommitted: Bool = false
    ) {
        self.url = url
        self.revisionID = revisionID
        self.phase = phase
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.retainedBytes = retainedBytes
        self.unsupportedPaths = unsupportedPaths
        self.endEvidenceCommitted = endEvidenceCommitted
    }

    public var id: URL { url }
}

/// What the restore pass found while rebuilding an end-accepted working
/// revision (issue #297): provenance for the recovery itself, surfaced
/// in the reopened Review instead of guessed.
public struct WorkingRevisionRestoreReport: Sendable, Equatable {
    /// Files present on disk with no recoverable declaration — kept,
    /// declared generically, and listed here as unsupported.
    public let unsupportedPaths: [String]
    /// Declared-but-superseded artifacts removed at restore because the
    /// store will recompute them (seal-time quality/advisory payloads).
    public let supersededPaths: [String]
    /// Real payload files removed at restore because no legal manifest
    /// declaration exists for them — consented evidence loss, listed
    /// separately from recomputed artifacts so the operator sees what
    /// is actually gone.
    public let unmanifestablePaths: [String]
    /// Checkpoint fields the recovered phase document did not carry —
    /// informational, since a missing field degrades a report section
    /// rather than inventing it.
    public let missingCheckpointFields: [String]

    public init(
        unsupportedPaths: [String],
        supersededPaths: [String],
        unmanifestablePaths: [String],
        missingCheckpointFields: [String]
    ) {
        self.unsupportedPaths = unsupportedPaths
        self.supersededPaths = supersededPaths
        self.unmanifestablePaths = unmanifestablePaths
        self.missingCheckpointFields = missingCheckpointFields
    }
}
