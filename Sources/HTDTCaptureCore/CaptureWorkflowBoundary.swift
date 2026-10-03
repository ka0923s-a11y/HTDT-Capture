import Foundation

/// Capture workflow composition boundary (issue #410).
///
/// The app's single root historically held every capability as one
/// flat action bag plus every published state. This file declares the
/// boundary the root routes on: which workflow owns each public
/// action, what a mission launch routes to, and the handoff records
/// exchanged at workflow transitions.
///
/// `CaptureState` stays scoped to the spatial-capture lifecycle —
/// review, library, transfer, and administration are *not* capture
/// states and never join the enum.
///
/// Owned-state summary (ROOT-10 state table): each workflow's
/// published state is described by `CaptureWorkflow.stateScope`. The
/// action table below is the enforced inventory — AppShell validates
/// the runtime `CaptureRootActions` member list against it, and the
/// core tests assert the sets form an exact partition.
public enum CaptureWorkflow: String, Sendable, CaseIterable {
    /// Spatial Capture: scan session, guidance, coverage, target
    /// scans, connected regions, permissions, scan-time field notes,
    /// scan-time revisit flags, capture strategy/profile selection.
    /// Owns `CaptureState` plus every `isScanning`-era published
    /// signal (progress, coverage, guidance, regions, session
    /// diagnostics).
    case spatialCapture = "spatial_capture"
    /// Review / authoring: annotation + measurement + authority
    /// commits, room frame/datum, opening review, evidence curation,
    /// semantic correction, as-built verification, revision lineage,
    /// field notes in review, remediation, finalize/export-prep,
    /// persisted-workspace viewing. Owns the review workspace model
    /// and the annotation authority inputs (mesh anchors, RoomPlan
    /// surfaces/objects, field-authority drafts).
    case reviewAuthoring = "review_authoring"
    /// Field Return (non-spatial, issue #400): the field-return
    /// workspace lifecycle — open/resume, persist draft, finalize,
    /// list documents. Owns the open workspace + document list state.
    case fieldReturn = "field_return"
    /// Mission: task-plan import/clear, mission inbox lifecycle,
    /// dependency evaluation, checklist outcomes, repair tasks,
    /// as-built plan reference import. Owns mission inbox records,
    /// the active record id, progress evaluations, and the imported
    /// task plan bound to the capture.
    case mission
    /// Library: persisted captures/series, quarantine/orphans,
    /// recovered drafts, revisions, inbound/archive import-export,
    /// metadata, derived exports, failed captures. Owns the
    /// persisted inventory, library metadata, import/export staging,
    /// and the read-only persisted workspace.
    case library
    /// Transfer: HTDT send, destination pairing/lifecycle, delivery
    /// queue, preflight, export-archive cleanup. Owns paired
    /// destinations, endpoint capabilities, delivery jobs, and
    /// handoff receipts.
    case transfer
    /// Administration: app settings, equipment catalog cache, support
    /// diagnostics. Owns settings/catalog state and diagnostics
    /// staging.
    case administration = "administration"

    /// Short human-readable scope of the published state this
    /// workflow owns — the ROOT-10 state classification table.
    public var stateScope: String {
        switch self {
        case .spatialCapture:
            return "capture state machine, scan progress, coverage, "
                + "guidance, target scans, connected-space tracker, "
                + "camera permission, capture strategy/profile, "
                + "practice-prompt state"
        case .reviewAuthoring:
            return "review workspace model, annotation authority "
                + "inputs (mesh anchors, RoomPlan surfaces/objects), "
                + "field-authority draft, semantic-correction draft, "
                + "as-built items, opening review, room frame/datum, "
                + "revisit flags, revision comparison"
        case .fieldReturn:
            return "open field-return workspace, finalized "
                + "field-return document list"
        case .mission:
            return "mission inbox records, active mission id, "
                + "progress evaluations, imported task plan + "
                + "outcomes, repair task rows"
        case .library:
            return "persisted inventory, library metadata, "
                + "origin records, inbound import preview, "
                + "library export URL, persisted workspace, "
                + "cross-revision registrations, recovered drafts, "
                + "failed-capture state"
        case .transfer:
            return "paired destinations, endpoint capability cache, "
                + "delivery jobs, handoff receipts, preflight state"
        case .administration:
            return "app settings, equipment catalog snapshots/cache, "
                + "local-state upgrade notice"
        }
    }
}

/// The enforced ROOT-10 action-ownership table (issue #410): every
/// public `CaptureRootActions` member maps to exactly one owning
/// workflow. The runtime inventory check in AppShell reflects on the
/// action struct so a newly added unclassified action fails loudly
/// instead of drifting back into a global bag.
public enum CaptureWorkflowActionMap {
    public static let spatialCapture: Set<String> = [
        "beginCapture", "beginScanning", "cancelCaptureSetup",
        "beginReview", "captureEvidenceFrame",
        "captureHighResolutionEvidence", "beginTargetScan",
        "retakeTargetScan", "acceptTargetScan", "cancelTargetScan",
        "segmentationGesture", "useSegmentation", "cancelSegmentation",
        "segmentationAssetPrepare",
        "declareNearestUnresolvedRegion", "revokeOperatorRegion",
        "setGuidanceCuesEnabled", "setLoopClosureCheckActive",
        "recordLoopClosureOutcome",
        "setScanMovementCapability", "continueScanning",
        "captureIdentityPhoto", "scanEquipmentLabel",
        "captureFieldEvidencePhoto", "flagForReview",
        "updateRevisitFlagDetails", "selectTaskProfile",
        "resetCapture", "discardActiveCapture",
        "beginPracticeCapture", "dismissPracticePrompt",
        "retryCameraPermission", "openCameraSettings",
        "cancelCaptureStart", "setConnectedSpaceIntent",
        "beginConnectedSegment", "completeConnectedSegment",
        "recordConnectedPortal", "revisitConnectedRegion",
        "selectCaptureStrategy", "recordFieldNote",
        "requestScanCopilotSuggestion",
    ]
    public static let reviewAuthoring: Set<String> = [
        "beginAnnotation",
        "captureSpeakerOrientation", "capturePointOrientation",
        "probePlacementTarget", "probeCameraHeading",
        "captureTargetedPlacement", "commitFieldAuthority",
        "commitAnnotationAuthority", "cancelAnnotation",
        "flagEvidenceFrameForPrivacy", "removeEvidenceFrameForPrivacy",
        "captureRoomFrameOrigin", "confirmRoomReferenceFrame",
        "confirmFieldDatumFromRoomFrame", "removeRoomFieldDatum",
        "captureOpeningCenter", "clearOpeningCenter",
        "openingReviewCandidates", "commitOpeningReview",
        "refreshReviewWorkspace", "loadPersistedWorkspace",
        "suspendReview", "performRemediation", "resolveRevisitFlag",
        "reopenRevisitFlag", "finalizeCapture", "prepareExport",
        "asBuiltMarkUnavailable", "asBuiltEstablishAlignment",
        "asBuiltRecordActual", "preferRevisionHead",
        "proposeRevisionAlignment", "acceptRevisionAlignment",
        "recordReviewFieldNote", "resolveFieldNote",
        "supersedeFieldNote", "bindFieldNote",
        "beginSemanticCorrection", "commitSemanticCorrection",
        "cancelSemanticCorrection", "compareAdoptedRevisionWithParent",
    ]
    public static let fieldReturn: Set<String> = [
        "openFieldReturnWorkspace", "persistFieldReturnDraft",
        "finalizeFieldReturn", "listFieldReturns",
        "fieldReturnArtifactURL",
    ]
    public static let mission: Set<String> = [
        "importTaskPlan", "clearTaskPlan", "importMissionDocument",
        "importMissionPackage", "startMission", "deactivateMission",
        "archiveMission", "evaluateMissionDependencies",
        "waiveMissionItem", "markTaskPlanItem",
        "canRecordTaskPlanMarkReason", "resolveRepairTask",
        "importPlanReference", "checkHTDTForMissions",
    ]
    public static let library: Set<String> = [
        "openPersistedCapture", "deletePersistedCapture",
        "removeQuarantinedArtifact", "removeWorkingOrphan",
        "revisePersistedCapture", "reviseAdoptedCapture",
        "importCaptureArchive", "openRecoveredDraft",
        "discardRecoveredDraft", "updateLibraryEntry",
        "importInboundDocument", "confirmLibraryImport",
        "dismissLibraryImport", "exportLibraryPackage",
        "setSeriesArchived", "updateRevisionMark", "deleteSeries",
        "derivedExportInfo", "exportDerived", "exportSurveyReport",
        "inspectFailedCapture", "exportFailedCaptureDiagnostics",
    ]
    public static let transfer: Set<String> = [
        "sendCaptureToHTDT", "pairDestinationPayload",
        "confirmPairing", "forgetDestination", "revokeDestination",
        "refreshEndpointCapabilities", "deliveryRetryNow",
        "deliveryPause", "deliveryResume", "deliveryCancel",
        "deliveryPurgePayload", "preflightDestination",
        "preflightFieldReturn", "sendFieldReturnToHTDT",
        "deleteExportArchive",
    ]
    public static let administration: Set<String> = [
        "updateAppSettings", "clearEquipmentCatalogCache",
        "collectSupportDiagnostics", "importEquipmentCatalog",
        "selectEquipmentCatalog",
    ]

    /// The action set owned by each workflow, keyed by workflow.
    public static let table: [CaptureWorkflow: Set<String>] = [
        .spatialCapture: spatialCapture,
        .reviewAuthoring: reviewAuthoring,
        .fieldReturn: fieldReturn,
        .mission: mission,
        .library: library,
        .transfer: transfer,
        .administration: administration,
    ]

    /// The owning workflow for one action name, or nil when
    /// unclassified.
    public static func workflow(
        forActionName name: String
    ) -> CaptureWorkflow? {
        for (workflow, actions) in table where actions.contains(name) {
            return workflow
        }
        return nil
    }

    /// Names in `actionNames` not owned by any workflow — the drift
    /// signal the runtime check and the tests both assert empty.
    public static func unclassifiedActionNames(
        _ actionNames: [String]
    ) -> [String] {
        actionNames.filter { workflow(forActionName: $0) == nil }
            .sorted()
    }

    /// Stale inventory entries — table rows that no longer name a
    /// real action. The AppShell check reflects on the struct and
    /// compares both directions.
    public static func unknownActionNames(
        _ actionNames: [String]
    ) -> [String] {
        let known = Set(actionNames)
        return table.values.flatMap { $0 }
            .filter { !known.contains($0) }
            .sorted()
    }
}

// MARK: - Mission launch routing (issue #410)

/// Where launching a mission's work package goes. The router is a
/// pure decision — the App resolves a route into a concrete action
/// (`beginCapture` / `openFieldReturnWorkspace` / persisted viewer)
/// so the workflow boundary never reaches into UI.
public enum MissionLaunchRoute: Sendable, Equatable {
    /// The mission's plan contains spatial tasks — open Spatial
    /// Capture with the plan bound.
    case spatialCapture
    /// The plan is entirely non-spatial field work — open the
    /// field-return workspace (issue #400).
    case fieldReturn
    /// The mission's capture work is already done (finalized /
    /// delivered / completed / superseded) — open the artifact in
    /// Review instead of recapturing.
    case artifactReview
    /// The mission cannot start on this device — the decision
    /// surfaces the reason rather than silently refusing.
    case unsupported(reason: MissionLaunchUnsupportedReason)

    /// True when the route leads to an operator-usable workflow.
    public var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

/// Why a mission launch refused (issue #410): always explicit —
/// never a silent dead end.
public enum MissionLaunchUnsupportedReason:
    String, Sendable, Equatable
{
    /// The plan has spatial tasks but the device lacks spatial
    /// capture (non-LiDAR hardware — `roomPlanMeshEligible` false).
    case spatialCaptureUnavailable = "spatial_capture_unavailable"
    /// The record's plan payload could not be decoded — routing is
    /// impossible without it.
    case planUnavailable = "plan_unavailable"
    /// The plan carries no executable task items at all.
    case noExecutableTasks = "no_executable_tasks"
}

/// The routed decision plus the evidence behind it: which task items
/// need spatial capture (the refusal reason's subject) and which are
/// field-work. Operators and tests can see *why*, not just *where*.
public struct MissionLaunchDecision: Sendable, Equatable {
    public let route: MissionLaunchRoute
    /// `task_item:<id>` refs requiring spatial capture.
    public let spatialItemRefs: [String]
    /// `task_item:<id>` refs completable as field work.
    public let fieldItemRefs: [String]

    public init(
        route: MissionLaunchRoute,
        spatialItemRefs: [String] = [],
        fieldItemRefs: [String] = []
    ) {
        self.route = route
        self.spatialItemRefs = spatialItemRefs
        self.fieldItemRefs = fieldItemRefs
    }
}

/// Mission → workflow routing (issue #410). Composes the field-task
/// preflight (#400) — the same spatial/non-spatial classification
/// that drives the field-return ledger — so a mission can never be
/// routed somewhere its plan cannot execute.
public enum MissionLaunchRouter {
    /// Decide where starting `record` leads. `plan` is the mission's
    /// embedded task plan — the inbox record stores only its identity,
    /// so the caller re-decodes `payloadRelativePath` and passes it.
    /// `spatialAvailable` is the device's spatial-capture verdict
    /// (`roomPlanMeshEligible`).
    public static func route(
        for record: HTDTMissionRecord,
        plan: HTDTCaptureTaskPlan?,
        spatialAvailable: Bool
    ) -> MissionLaunchDecision {
        guard let plan else {
            return MissionLaunchDecision(
                route: .unsupported(reason: .planUnavailable)
            )
        }
        let preflight = HTDTFieldTaskPreflightEvaluator.evaluate(
            plan: plan,
            spatialAvailable: spatialAvailable
        )
        let spatialRefs = preflight
            .filter { $0.spatialRequirement == .spatial }
            .map(\.itemRef)
        let fieldRefs = preflight
            .filter { $0.spatialRequirement == .nonSpatial }
            .map(\.itemRef)

        // Capture work already finished: the artifact — not a fresh
        // capture — is the mission's remaining surface.
        if !record.lifecycle.canStart {
            return MissionLaunchDecision(
                route: .artifactReview,
                spatialItemRefs: spatialRefs,
                fieldItemRefs: fieldRefs
            )
        }
        if preflight.isEmpty {
            return MissionLaunchDecision(
                route: .unsupported(reason: .noExecutableTasks)
            )
        }
        if spatialRefs.isEmpty {
            return MissionLaunchDecision(
                route: .fieldReturn,
                fieldItemRefs: fieldRefs
            )
        }
        if !spatialAvailable {
            return MissionLaunchDecision(
                route: .unsupported(
                    reason: .spatialCaptureUnavailable
                ),
                spatialItemRefs: spatialRefs,
                fieldItemRefs: fieldRefs
            )
        }
        return MissionLaunchDecision(
            route: .spatialCapture,
            spatialItemRefs: spatialRefs,
            fieldItemRefs: fieldRefs
        )
    }
}

// MARK: - Workflow handoff records (issue #410)

/// The Spatial Capture → Review transition record: emitted when a
/// scan ends and Review/authoring begins. Reviewing a capture that
/// never passed through this handoff is the impossible state the
/// boundary exists to prevent.
public struct SpatialCaptureToReviewHandoff: Sendable, Equatable {
    public let captureRevisionID: CaptureRevisionID
    /// The capture coordinate space Review's authority records must
    /// bind — nil means no spatial authority was committed.
    public let coordinateSpaceID: CoordinateSpaceID?

    public init(
        captureRevisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID?
    ) {
        self.captureRevisionID = captureRevisionID
        self.coordinateSpaceID = coordinateSpaceID
    }
}

/// The Review → finalization handoff: the workspace revision that
/// sealed, so finalization/export operate on an explicit token
/// rather than ambient state.
public struct ReviewToFinalizationHandoff: Sendable, Equatable {
    public let captureRevisionID: CaptureRevisionID
    /// True when the sealed revision passed the opening review —
    /// the gate `#408` authoring surfaces check before mutations.
    public let spatialCaptureSealed: Bool

    public init(
        captureRevisionID: CaptureRevisionID,
        spatialCaptureSealed: Bool
    ) {
        self.captureRevisionID = captureRevisionID
        self.spatialCaptureSealed = spatialCaptureSealed
    }
}

/// The Library → Transfer handoff: a persisted artifact plus an
/// optional destination the operator pre-picked. `nil` destination
/// means "choose at send time" — the transfer workflow owns pairing.
public struct ArtifactToTransferHandoff: Sendable, Equatable {
    public let captureRevisionID: CaptureRevisionID
    public let destinationRecordID: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        destinationRecordID: String? = nil
    ) {
        self.captureRevisionID = captureRevisionID
        self.destinationRecordID = destinationRecordID
    }
}

/// The Mission → workflow launch handoff: the routed decision made
/// explicit so a mission's Start is a recorded transition, not an
/// implicit state read.
public struct MissionToWorkflowHandoff: Sendable, Equatable {
    /// Device-local inbox record id (UUID string).
    public let missionRecordID: String
    public let decision: MissionLaunchDecision

    public init(
        missionRecordID: String,
        decision: MissionLaunchDecision
    ) {
        self.missionRecordID = missionRecordID
        self.decision = decision
    }
}
