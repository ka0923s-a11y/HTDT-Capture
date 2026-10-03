import Foundation
import HTDTCaptureCore

/// Workflow composition boundary (issue #410): the seven typed
/// action ports the root routes between, decomposed from the flat
/// `CaptureRootActions` bag. A view receives only the port(s) its
/// workflow owns — a Library view can no longer reach scan-session
/// actions, and a Mission view cannot reach transfer internals.
///
/// Ownership is the enforced `CaptureWorkflowActionMap` table: the
/// init asserts (debug) that every `CaptureRootActions` member is
/// classified and no classified name is missing, so a new action
/// added to the bag fails loudly until it is routed — never silently
/// global again.

/// Spatial Capture workflow (issue #410): scan session, guidance, coverage, target scans, connected regions, permissions, practice, scan-time field notes and revisit flags, strategy/profile selection. Views outside the scan session never see these.
public struct SpatialCaptureActions {
    public let beginCapture: () -> Void
    public let beginScanning: () -> Void
    public let cancelCaptureSetup: () -> Void
    public let beginReview: () -> Void
    public let captureEvidenceFrame: () -> Void
    public let beginTargetScan: () -> Void
    public let retakeTargetScan: () -> Void
    public let acceptTargetScan: () -> Void
    public let cancelTargetScan: () -> Void
    /// #269: operator seed/refine gesture over the preview
    /// (view-normalized points; the coordinator maps them through the
    /// recorded display-transform authority).
    public let segmentationGesture: (SegmentationGesture) -> Void
    /// #269: fuse + persist the accepted mask ("Use").
    public let useSegmentation: () -> Void
    /// #269: drop the live segmentation run ("Cancel"/"New selection").
    public let cancelSegmentation: () -> Void
    /// #269: explicit operator asset-prep request — the only mid-scan
    /// path allowed to reach `downloadAssets()`.
    public let segmentationAssetPrepare: () -> Void
    public let declareNearestUnresolvedRegion: (DeclaredRegionReason) -> Void
    public let revokeOperatorRegion: (SpatialCoverageCellKey) -> Void
    public let setGuidanceCuesEnabled: (Bool) -> Void
    public let setLoopClosureCheckActive: (Bool) -> Void
    /// Records the operator's response to the armed return-to-start
    /// check (#273): "accepted", "reobserve", or "continued" — kept as
    /// advisory provenance next to the verdict + residuals.
    public let recordLoopClosureOutcome: (String) -> Void
    public let setScanMovementCapability: (ScanMovementCapability) -> Void
    public let continueScanning: () -> Void
    public let captureIdentityPhoto: () async throws -> String
    public let scanEquipmentLabel: () async throws -> EquipmentLabelScanResult
    public let captureFieldEvidencePhoto: () async throws -> CapturedFieldPhoto
    public let flagForReview: () -> String?
    public let updateRevisitFlagDetails: (String, ScanRevisitFlagCategory?, String?) -> Void
    public let selectTaskProfile: (CaptureTaskProfile?, Set<String>) -> Void
    public let resetCapture: () -> Void
    public let discardActiveCapture: () -> Void
    public let beginPracticeCapture: () -> Void
    public let dismissPracticePrompt: (Bool) -> Void
    public let retryCameraPermission: () -> Void
    public let openCameraSettings: () -> Void
    public let cancelCaptureStart: () -> Void
    public let setConnectedSpaceIntent: (Bool) -> Void
    public let beginConnectedSegment: (String, CaptureRegionKind) -> Void
    public let completeConnectedSegment: () -> Void
    public let recordConnectedPortal: (CaptureRegionID, CapturePortalKind) -> Void
    public let revisitConnectedRegion: (CaptureRegionID) -> Void
    public let selectCaptureStrategy: (CaptureStrategyIdentifier) -> Void
    public let recordFieldNote: (String, CaptureFieldNoteCategory, Bool, Bool, Bool, CaptureFieldNoteAnchorRequest) -> Void
    /// #272: on-demand advisory copilot request (advisory only).
    public let requestScanCopilotSuggestion: () -> Void

    public init(from actions: CaptureRootActions) {
        self.beginCapture = actions.beginCapture
        self.beginScanning = actions.beginScanning
        self.cancelCaptureSetup = actions.cancelCaptureSetup
        self.beginReview = actions.beginReview
        self.captureEvidenceFrame = actions.captureEvidenceFrame
        self.beginTargetScan = actions.beginTargetScan
        self.retakeTargetScan = actions.retakeTargetScan
        self.acceptTargetScan = actions.acceptTargetScan
        self.cancelTargetScan = actions.cancelTargetScan
        self.segmentationGesture = actions.segmentationGesture
        self.useSegmentation = actions.useSegmentation
        self.cancelSegmentation = actions.cancelSegmentation
        self.segmentationAssetPrepare =
            actions.segmentationAssetPrepare
        self.declareNearestUnresolvedRegion = actions.declareNearestUnresolvedRegion
        self.revokeOperatorRegion = actions.revokeOperatorRegion
        self.setGuidanceCuesEnabled = actions.setGuidanceCuesEnabled
        self.setLoopClosureCheckActive = actions.setLoopClosureCheckActive
        self.recordLoopClosureOutcome = actions.recordLoopClosureOutcome
        self.setScanMovementCapability = actions.setScanMovementCapability
        self.continueScanning = actions.continueScanning
        self.captureIdentityPhoto = actions.captureIdentityPhoto
        self.scanEquipmentLabel = actions.scanEquipmentLabel
        self.captureFieldEvidencePhoto = actions.captureFieldEvidencePhoto
        self.flagForReview = actions.flagForReview
        self.updateRevisitFlagDetails = actions.updateRevisitFlagDetails
        self.selectTaskProfile = actions.selectTaskProfile
        self.resetCapture = actions.resetCapture
        self.discardActiveCapture = actions.discardActiveCapture
        self.beginPracticeCapture = actions.beginPracticeCapture
        self.dismissPracticePrompt = actions.dismissPracticePrompt
        self.retryCameraPermission = actions.retryCameraPermission
        self.openCameraSettings = actions.openCameraSettings
        self.cancelCaptureStart = actions.cancelCaptureStart
        self.setConnectedSpaceIntent = actions.setConnectedSpaceIntent
        self.beginConnectedSegment = actions.beginConnectedSegment
        self.completeConnectedSegment = actions.completeConnectedSegment
        self.recordConnectedPortal = actions.recordConnectedPortal
        self.revisitConnectedRegion = actions.revisitConnectedRegion
        self.selectCaptureStrategy = actions.selectCaptureStrategy
        self.recordFieldNote = actions.recordFieldNote
        self.requestScanCopilotSuggestion =
            actions.requestScanCopilotSuggestion
    }
}

/// Review/authoring workflow (issue #410): annotation + measurement + authority commits, room frame/datum, opening review, evidence curation, semantic correction, as-built verification, revision lineage, field notes, remediation, finalize/export-prep, persisted workspace.
public struct ReviewAuthoringActions {
    public let beginAnnotation: () -> Void
    public let captureSpeakerOrientation: () async throws -> AnnotationOrientationAuthority
    public let capturePointOrientation: () async throws -> AnnotationOrientationAuthority
    public let probePlacementTarget: () async -> AnnotationPlacementProbe
    public let probeCameraHeading: () async -> Float?
    public let captureTargetedPlacement: ( PlacementTargetPreference ) async throws -> AnnotationPlacementAuthority?
    public let commitFieldAuthority: (FieldAuthorityWorkspace) -> Void
    public let commitAnnotationAuthority: ( [CaptureAnnotationEntity], [CaptureMeasurement], [EquipmentIdentityRecord], TheaterAuthorityCollection ) -> Void
    public let cancelAnnotation: () -> Void
    public let flagEvidenceFrameForPrivacy: (EvidenceFrameID) -> Void
    public let unflagEvidenceFrameForPrivacy: (EvidenceFrameID) -> Void
    public let removeEvidenceFrameForPrivacy: (EvidenceFrameID) async -> Void
    public let captureRoomFrameOrigin: () -> Void
    public let confirmRoomReferenceFrame: () -> Void
    public let confirmFieldDatumFromRoomFrame: () async -> Bool
    public let removeRoomFieldDatum: () async -> Void
    public let captureOpeningCenter: () -> Void
    public let clearOpeningCenter: () -> Void
    public let openingReviewCandidates: () async -> [RoomOpeningCandidate]?
    public let commitOpeningReview: ([RoomOpeningCandidate]) async -> Bool
    public let refreshReviewWorkspace: () -> Void
    /// Loads a persisted capture into the read-only viewer —
    /// `true` only when the load actually started (the guard can
    /// refuse during other persisted operations).
    public let loadPersistedWorkspace: (PersistedCaptureRecord) -> Bool
    public let suspendReview: () -> Void
    public let performRemediation: (CaptureRemediationAction) -> Void
    public let resolveRevisitFlag: ( String, ScanRevisitFlagResolution.Outcome, String? ) -> Void
    public let reopenRevisitFlag: (String) -> Void
    public let finalizeCapture: () -> Void
    public let prepareExport: () -> Void
    public let asBuiltMarkUnavailable: (String) -> Void
    public let asBuiltEstablishAlignment: () -> Void
    public let asBuiltRecordActual: (String, AnnotationEntityID) -> Void
    public let preferRevisionHead: (CaptureSeriesID, CaptureRevisionID?) -> Void
    public let proposeRevisionAlignment: (CaptureRevisionID, CaptureRevisionID) async -> CrossRevisionRegistrationSolve?
    public let acceptRevisionAlignment: (CaptureRevisionID, CaptureRevisionID) async -> CrossRevisionRegistration?
    public let recordReviewFieldNote: (String, CaptureFieldNoteCategory, Bool, [String]) -> Void
    public let resolveFieldNote: (CaptureFieldNoteID) -> Void
    public let supersedeFieldNote: (CaptureFieldNoteID, String, CaptureFieldNoteCategory) -> Void
    public let bindFieldNote: (CaptureFieldNoteID, String) -> Void
    public let beginSemanticCorrection: (PersistedCaptureRecord) -> Void
    public let commitSemanticCorrection: (SemanticChildRevisionEdits) async -> Bool
    public let cancelSemanticCorrection: () -> Void
    public let compareAdoptedRevisionWithParent: () async -> CaptureRevisionComparison?

    public init(from actions: CaptureRootActions) {
        self.beginAnnotation = actions.beginAnnotation
        self.captureSpeakerOrientation = actions.captureSpeakerOrientation
        self.capturePointOrientation = actions.capturePointOrientation
        self.probePlacementTarget = actions.probePlacementTarget
        self.probeCameraHeading = actions.probeCameraHeading
        self.captureTargetedPlacement = actions.captureTargetedPlacement
        self.commitFieldAuthority = actions.commitFieldAuthority
        self.commitAnnotationAuthority = actions.commitAnnotationAuthority
        self.cancelAnnotation = actions.cancelAnnotation
        self.flagEvidenceFrameForPrivacy = actions.flagEvidenceFrameForPrivacy
        self.unflagEvidenceFrameForPrivacy = actions.unflagEvidenceFrameForPrivacy
        self.removeEvidenceFrameForPrivacy = actions.removeEvidenceFrameForPrivacy
        self.captureRoomFrameOrigin = actions.captureRoomFrameOrigin
        self.confirmRoomReferenceFrame = actions.confirmRoomReferenceFrame
        self.confirmFieldDatumFromRoomFrame = actions.confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = actions.removeRoomFieldDatum
        self.captureOpeningCenter = actions.captureOpeningCenter
        self.clearOpeningCenter = actions.clearOpeningCenter
        self.openingReviewCandidates = actions.openingReviewCandidates
        self.commitOpeningReview = actions.commitOpeningReview
        self.refreshReviewWorkspace = actions.refreshReviewWorkspace
        self.loadPersistedWorkspace = actions.loadPersistedWorkspace
        self.suspendReview = actions.suspendReview
        self.performRemediation = actions.performRemediation
        self.resolveRevisitFlag = actions.resolveRevisitFlag
        self.reopenRevisitFlag = actions.reopenRevisitFlag
        self.finalizeCapture = actions.finalizeCapture
        self.prepareExport = actions.prepareExport
        self.asBuiltMarkUnavailable = actions.asBuiltMarkUnavailable
        self.asBuiltEstablishAlignment = actions.asBuiltEstablishAlignment
        self.asBuiltRecordActual = actions.asBuiltRecordActual
        self.preferRevisionHead = actions.preferRevisionHead
        self.proposeRevisionAlignment = actions.proposeRevisionAlignment
        self.acceptRevisionAlignment = actions.acceptRevisionAlignment
        self.recordReviewFieldNote = actions.recordReviewFieldNote
        self.resolveFieldNote = actions.resolveFieldNote
        self.supersedeFieldNote = actions.supersedeFieldNote
        self.bindFieldNote = actions.bindFieldNote
        self.beginSemanticCorrection = actions.beginSemanticCorrection
        self.commitSemanticCorrection = actions.commitSemanticCorrection
        self.cancelSemanticCorrection = actions.cancelSemanticCorrection
        self.compareAdoptedRevisionWithParent = actions.compareAdoptedRevisionWithParent
    }
}

/// Field Return workflow (issue #410): non-spatial mission field-return lifecycle — open/resume workspace, persist drafts, finalize, list documents.
public struct FieldReturnActions {
    public let openFieldReturnWorkspace: (String) async -> HTDTFieldReturnWorkspace?
    public let persistFieldReturnDraft: (HTDTFieldReturnWorkspace) async -> Void
    public let finalizeFieldReturn: (HTDTFieldReturnWorkspace) async -> URL?
    public let listFieldReturns: () async -> [HTDTFieldReturnDocument]
    /// #423: resolves the finalized container's URL for share flows.
    public let fieldReturnArtifactURL: (HTDTFieldReturnID) -> URL?

    public init(from actions: CaptureRootActions) {
        self.openFieldReturnWorkspace = actions.openFieldReturnWorkspace
        self.persistFieldReturnDraft = actions.persistFieldReturnDraft
        self.finalizeFieldReturn = actions.finalizeFieldReturn
        self.listFieldReturns = actions.listFieldReturns
        self.fieldReturnArtifactURL = actions.fieldReturnArtifactURL
    }
}

/// Mission workflow (issue #410): task-plan import/clear, mission inbox lifecycle, dependency evaluation, checklist outcomes, repair tasks, plan-reference import.
public struct MissionActions {
    public let importTaskPlan: (URL) -> Void
    public let clearTaskPlan: () -> Void
    public let importMissionDocument: (URL) -> Void
    public let importMissionPackage: (URL) async -> Void
    public let startMission: (String) async -> Void
    public let deactivateMission: () async -> Void
    public let archiveMission: (String) async -> Void
    public let completeMission: (String) async -> Void
    public let updateMissionUserNote:
        (String, String?) async -> Void
    public let evaluateMissionDependencies: (String) async throws -> HTDTMissionDependencyReport
    public let waiveMissionItem: (String, String, String?) async -> Void
    public let markTaskPlanItem:
        (String, TaskPlanItemOutcome, String?) -> Void
    public let canRecordTaskPlanMarkReason:
        (HTDTCaptureTaskPlan) -> Bool
    public let resolveRepairTask: (HTDTRepairTaskRow) -> Void
    public let importPlanReference: (URL) -> Void
    /// #422: bounded pairing-scoped Mission pull refresh.
    public let checkHTDTForMissions:
        () async -> [HTDTMissionReceiveReport]

    public init(from actions: CaptureRootActions) {
        self.importTaskPlan = actions.importTaskPlan
        self.clearTaskPlan = actions.clearTaskPlan
        self.importMissionDocument = actions.importMissionDocument
        self.importMissionPackage = actions.importMissionPackage
        self.startMission = actions.startMission
        self.deactivateMission = actions.deactivateMission
        self.archiveMission = actions.archiveMission
        self.completeMission = actions.completeMission
        self.updateMissionUserNote = actions.updateMissionUserNote
        self.evaluateMissionDependencies = actions.evaluateMissionDependencies
        self.waiveMissionItem = actions.waiveMissionItem
        self.markTaskPlanItem = actions.markTaskPlanItem
        self.canRecordTaskPlanMarkReason =
            actions.canRecordTaskPlanMarkReason
        self.resolveRepairTask = actions.resolveRepairTask
        self.importPlanReference = actions.importPlanReference
        self.checkHTDTForMissions = actions.checkHTDTForMissions
    }
}

/// Library workflow (issue #410): persisted captures/series, quarantine/orphans, recovered drafts, revisions, inbound/archive import-export, metadata, derived exports, failed captures.
public struct LibraryActions {
    public let openPersistedCapture: (CaptureRevisionID) -> Void
    public let deletePersistedCapture: (CaptureRevisionID) -> Void
    public let removeQuarantinedArtifact: (PersistedCaptureQuarantinedArtifact) -> Void
    public let removeWorkingOrphan: (PersistedCaptureWorkingOrphan) -> Void
    public let revisePersistedCapture: (PersistedCaptureRecord) -> Void
    public let reviseAdoptedCapture: () -> Void
    public let importCaptureArchive: (URL) -> Void
    public let openRecoveredDraft: (RecoverableWorkingRevision) -> Void
    public let discardRecoveredDraft: (RecoverableWorkingRevision) -> Void
    public let updateLibraryEntry: (CaptureRevisionID?, CaptureSeriesID?, CaptureLibraryEntryMetadata) -> Void
    public let importInboundDocument: (URL) -> Void
    public let confirmLibraryImport: () -> Void
    public let dismissLibraryImport: () -> Void
    public let exportLibraryPackage: () -> Void
    public let setSeriesArchived: (CaptureSeriesID, Bool) -> Void
    public let updateRevisionMark: (CaptureRevisionID, CaptureRevisionMark) -> Void
    public let deleteSeries: (CaptureSeriesID, Bool) -> Void
    public let derivedExportInfo: (CaptureRevisionID) async -> DerivedExportInfo?
    public let exportDerived3D: (CaptureRevisionID, Derived3DExportSelection) async -> DerivedExportOutcome
    public let exportSurveyReport: (CaptureRevisionID, SurveyReportSelection) async -> DerivedExportOutcome
    public let inspectFailedCapture: () -> Void
    public let exportFailedCaptureDiagnostics: () async -> URL?

    public init(from actions: CaptureRootActions) {
        self.openPersistedCapture = actions.openPersistedCapture
        self.deletePersistedCapture = actions.deletePersistedCapture
        self.removeQuarantinedArtifact = actions.removeQuarantinedArtifact
        self.removeWorkingOrphan = actions.removeWorkingOrphan
        self.revisePersistedCapture = actions.revisePersistedCapture
        self.reviseAdoptedCapture = actions.reviseAdoptedCapture
        self.importCaptureArchive = actions.importCaptureArchive
        self.openRecoveredDraft = actions.openRecoveredDraft
        self.discardRecoveredDraft = actions.discardRecoveredDraft
        self.updateLibraryEntry = actions.updateLibraryEntry
        self.importInboundDocument = actions.importInboundDocument
        self.confirmLibraryImport = actions.confirmLibraryImport
        self.dismissLibraryImport = actions.dismissLibraryImport
        self.exportLibraryPackage = actions.exportLibraryPackage
        self.setSeriesArchived = actions.setSeriesArchived
        self.updateRevisionMark = actions.updateRevisionMark
        self.deleteSeries = actions.deleteSeries
        self.derivedExportInfo = actions.derivedExportInfo
        self.exportDerived3D = actions.exportDerived3D
        self.exportSurveyReport = actions.exportSurveyReport
        self.inspectFailedCapture = actions.inspectFailedCapture
        self.exportFailedCaptureDiagnostics = actions.exportFailedCaptureDiagnostics
    }
}

/// Transfer workflow (issue #410): HTDT send, destination pairing/lifecycle, delivery queue, preflight, export-archive cleanup.
public struct TransferActions {
    public let sendCaptureToHTDT:
        (HTDTHandoffDestination, HTDTShareSheetOutcome?) async -> Void
    public let pairDestinationPayload: (Data) throws -> HTDTReceiverPairingPayload
    public let confirmPairing: (HTDTReceiverPairingPayload) async -> Void
    public let forgetDestination: (String) async -> Void
    public let revokeDestination: (String) async -> Void
    public let refreshEndpointCapabilities: (String) async -> Void
    public let deliveryRetryNow: (String) async -> Void
    public let deliveryPause: (String) async -> Void
    public let deliveryResume: (String) async -> Void
    public let deliveryCancel: (String) async -> Void
    public let deliveryPurgePayload: (String) async -> Void
    public let preflightDestination: (HTDTHandoffDestination) async -> HTDTCompatibilityVerdict
    /// #423: field-return deliverable preflight + durable-queue send.
    public let preflightFieldReturn: (HTDTFieldReturnID, HTDTHandoffDestination) async -> HTDTCompatibilityVerdict
    public let sendFieldReturnToHTDT: (HTDTFieldReturnID, HTDTHandoffDestination) async -> FieldReturnSendOutcome
    public let deleteExportArchive: (PersistedCaptureRecord) -> Void

    public init(from actions: CaptureRootActions) {
        self.sendCaptureToHTDT = actions.sendCaptureToHTDT
        self.pairDestinationPayload = actions.pairDestinationPayload
        self.confirmPairing = actions.confirmPairing
        self.forgetDestination = actions.forgetDestination
        self.revokeDestination = actions.revokeDestination
        self.refreshEndpointCapabilities = actions.refreshEndpointCapabilities
        self.deliveryRetryNow = actions.deliveryRetryNow
        self.deliveryPause = actions.deliveryPause
        self.deliveryResume = actions.deliveryResume
        self.deliveryCancel = actions.deliveryCancel
        self.deliveryPurgePayload = actions.deliveryPurgePayload
        self.preflightDestination = actions.preflightDestination
        self.preflightFieldReturn = actions.preflightFieldReturn
        self.sendFieldReturnToHTDT = actions.sendFieldReturnToHTDT
        self.deleteExportArchive = actions.deleteExportArchive
    }
}

/// Administration workflow (issue #410): app settings, equipment catalog cache, support diagnostics.
public struct AdministrationActions {
    public let updateAppSettings: (CaptureAppSettings) -> Void
    public let clearEquipmentCatalogCache: () -> Void
    public let collectSupportDiagnostics: () async throws -> SupportDiagnosticsPackage
    public let importEquipmentCatalog: (Data) throws -> HTDTEquipmentCatalogSnapshot
    public let selectEquipmentCatalog: (String) -> Void

    public init(from actions: CaptureRootActions) {
        self.updateAppSettings = actions.updateAppSettings
        self.clearEquipmentCatalogCache = actions.clearEquipmentCatalogCache
        self.collectSupportDiagnostics = actions.collectSupportDiagnostics
        self.importEquipmentCatalog = actions.importEquipmentCatalog
        self.selectEquipmentCatalog = actions.selectEquipmentCatalog
    }
}

/// The routed capability surface of the capture root
/// (issue #410): one value per workflow, built once from the flat
/// bag. Constructing it runs the inventory check that keeps the
/// ownership table honest.
public struct CaptureWorkflowPorts {
    public let spatialCapture: SpatialCaptureActions
    public let reviewAuthoring: ReviewAuthoringActions
    public let fieldReturn: FieldReturnActions
    public let mission: MissionActions
    public let library: LibraryActions
    public let transfer: TransferActions
    public let administration: AdministrationActions

    public init(from actions: CaptureRootActions) {
        CaptureWorkflowPorts.assertInventoryComplete(actions)
        self.spatialCapture = SpatialCaptureActions(from: actions)
        self.reviewAuthoring = ReviewAuthoringActions(from: actions)
        self.fieldReturn = FieldReturnActions(from: actions)
        self.mission = MissionActions(from: actions)
        self.library = LibraryActions(from: actions)
        self.transfer = TransferActions(from: actions)
        self.administration = AdministrationActions(from: actions)
    }

    /// The action names `CaptureRootActions` actually publishes —
    /// reflected so the inventory tracks the bag, not a stale copy.
    public static func actionNames(
        of actions: CaptureRootActions
    ) -> [String] {
        Mirror(reflecting: actions).children
            .compactMap(\.label)
            .filter { !$0.hasPrefix("_") }
            .sorted()
    }

    /// Debug assertion that the ownership table partitions the real
    /// bag exactly: every published action owned, every table entry
    /// still published. A new unclassified action trips here at
    /// first `ports` construction — in release the check is a no-op
    /// and routing still works off the flat bag.
    public static func assertInventoryComplete(
        _ actions: CaptureRootActions
    ) {
        let names = actionNames(of: actions)
        let unclassified =
            CaptureWorkflowActionMap.unclassifiedActionNames(names)
        let unknown =
            CaptureWorkflowActionMap.unknownActionNames(names)
        assert(
            unclassified.isEmpty && unknown.isEmpty,
            "capture action inventory drift — "
                + "unclassified: \(unclassified), "
                + "unknown: \(unknown)"
        )
    }
}

extension CaptureRootActions {
    /// The decomposed capability surface (issue #410). The flat bag
    /// stays intact for migration; new surfaces take the port they
    /// need instead of the whole bag.
    public var ports: CaptureWorkflowPorts {
        CaptureWorkflowPorts(from: self)
    }
}
