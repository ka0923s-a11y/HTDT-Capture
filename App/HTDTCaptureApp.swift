import Combine
import Foundation
import RoomPlan
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import HTDTCaptureAppShell
import HTDTCaptureCore
import HTDTCapturePlatform

@main
struct HTDTCaptureApplication: App {
    var body: some Scene {
        WindowGroup {
            HTDTCaptureHostView()
        }
    }
}

@MainActor
private struct HTDTCaptureHostView: View {
    @StateObject private var coordinator = HTDTCaptureHostCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        CaptureRootView(
            state: coordinator.state,
            capabilities: coordinator.capabilities,
            cameraPermission: coordinator.cameraPermission,
            lastFailure: coordinator.lastFailure,
            workingSetStatus: coordinator.workingSetStatus,
            qualityReport: coordinator.qualityReport,
            advisoryReport: coordinator.advisoryReport,
            taskProfile: coordinator.taskProfile,
            validationReport: coordinator.validationReport,
            exportURL: coordinator.exportURL,
            annotationCoordinateSpaceID:
                coordinator.annotationCoordinateSpaceID,
            annotationWorkspaceCoordinateSpaceID:
                coordinator.annotationWorkspaceCoordinateSpaceID,
            annotationEvidenceRefs:
                coordinator.annotationEvidenceRefs,
            annotationRoomPlanSurfaces:
                coordinator.annotationRoomPlanSurfaces,
            annotationMeshAnchors:
                coordinator.annotationMeshAnchors,
            annotationAuthorityCommitted:
                coordinator.annotationAuthorityCommitted,
            annotationRevisionSeed:
                coordinator.annotationRevisionSeed,
            equipmentCatalog:
                coordinator.equipmentCatalog,
            operatorRoster:
                coordinator.operatorRoster,
            equipmentCatalogLibrary:
                coordinator.equipmentCatalogLibrary,
            taskPlan: coordinator.taskPlan,
            taskPlanMission: coordinator.taskPlanMission,
            workingSetIdentity:
                coordinator.workingSetIdentity,
            annotationEvidenceFrames:
                coordinator.annotationEvidenceFrames,
            annotationRoomPlanObjects:
                coordinator.annotationRoomPlanObjects,
            spatialPlausibilityFindings:
                coordinator.spatialPlausibilityFindings,
            annotationPlausibilityContext:
                coordinator.spatialPlausibilityContext,
            speakerLayoutPlans:
                coordinator.speakerLayoutPlans,
            equipmentRecents: coordinator.equipmentRecents,
            annotationDraftStore:
                coordinator.annotationDraftStore,
            annotationDraftRevisionID:
                coordinator.annotationDraftRevisionID,
            scanningPreview: AnyView(
                RoomPlanLiveCaptureView(
                    controller: coordinator.scanSessionController
                )
            ),
            scanCoverage: coordinator.scanCoverage,
            observationStability:
                coordinator.observationStability,
            spatialCoverage:
                coordinator.spatialCoverage,
            motionGuidance:
                coordinator.motionGuidance,
            scanGuidanceProgress:
                coordinator.scanGuidanceProgress,
            derivedShapePreview:
                coordinator.derivedShapePreview,
            scanEvidenceFrameCount:
                coordinator.scanEvidenceFrameCount,
            endScanGuidance:
                coordinator.endScanGuidance,
            captureSetup: coordinator.captureSetup,
            isEndingScan: coordinator.isEndingScan,
            isCapturingEvidence:
                coordinator.isCapturingEvidenceFrame,
            automaticEvidenceCount:
                coordinator.automaticEvidenceFrameCount,
            lowLightGuidanceActive:
                coordinator.lowLightGuidanceActive,
            targetScanStatus: coordinator.targetScanStatus,
            declaredRegions: coordinator.declaredRegionList,
            loopClosureCheckActive:
                coordinator.loopClosureCheckActive,
            loopClosureAssessment:
                coordinator.loopClosureAssessment,
            guidanceCuesEnabled:
                coordinator.guidanceCuesEnabled,
            revisitFlags: coordinator.revisitFlags,
            revisitFlagsFull: coordinator.revisitFlagsFull,
            persistedInventory:
                coordinator.persistedInventory,
            reviewWorkspace: coordinator.reviewWorkspace,
            persistedWorkspace: coordinator.persistedWorkspace,
            persistedWorkspaceRoomPlanObjects:
                coordinator
                    .persistedWorkspaceRoomPlanObjects,
            roomFrameOriginPending:
                coordinator.roomFrameOriginPending,
            openingCenterPending:
                coordinator.openingCenterPending,
            danglingSpatialIssues:
                coordinator.danglingSpatialIssues,
            handoffDestinations:
                coordinator.handoffDestinations,
            handoffReceipts: coordinator.handoffReceipts,
            missionRecords: coordinator.missionRecords,
            activeMissionRecordID:
                coordinator.activeMissionRecordID,
            pairedDestinations:
                coordinator.pairedDestinations,
            deliveryJobs: coordinator.deliveryJobs,
            libraryMetadata: coordinator.libraryMetadata,
            localStateUpgradeNotice:
                coordinator.localStateUpgradeNotice,
            libraryImportPreview:
                coordinator.libraryImportPreview,
            libraryExportURL: coordinator.libraryExportURL,
            failedInspection: coordinator.failedInspection,
            failedDraftRecoverable:
                coordinator.failedDraftRecoverable,
            finalizeRejection: coordinator.finalizeRejection,
            exportRejection: coordinator.exportRejection,
            // Sealed for the workspace whenever live spatial capture
            // is unavailable — a finalization seal (#276) or a
            // recovered draft whose spatial evidence is sealed —
            // regardless of committed annotations, so spatial
            // affordances hide instead of dead-ending on a torn-down
            // session.
            spatialCaptureSealed:
                coordinator.spatialAuthoritySealedForFinalization
                    || !coordinator.workingSetSpatialAuthorityLive,
            appSettings: coordinator.appSettings,
            missionEntries: coordinator.missionEntries,
            missionTaskPlan: coordinator.captureTaskPlan,
            missionTaskPlanOutcomes:
                coordinator.missionTaskPlanOutcomes,
            connectedSpaceIntent:
                coordinator.connectedSpaceIntent,
            connectedTracker: coordinator.connectedSpaceTracker,
            asBuiltPlanLoaded: coordinator.asBuiltPlan != nil,
            asBuiltItems: coordinator.asBuiltItems,
            asBuiltGhostOverlayEnabled:
                coordinator.asBuiltGhostOverlayEnabled,
            asBuiltAlignmentInstalled:
                coordinator.asBuiltAlignmentInstalled,
            asBuiltAlignment: coordinator.asBuiltAlignment,
            asBuiltOverlayModel: coordinator.asBuiltOverlayModel,
            asBuiltTolerancePolicyRef:
                coordinator.asBuiltTolerancePolicyRef,
            asBuiltActualCandidates:
                coordinator.asBuiltActualCandidates,
            roomFrameAvailable: coordinator.roomFrameAvailable,
            repairTaskRows: coordinator.repairTaskRows,
            evidenceStorageAdvisory:
                coordinator.evidenceStorageAdvisory,
            selectedStrategyID: coordinator.selectedStrategyID,
            strategyPinnedByTaskPlan:
                coordinator.strategyPinnedByTaskPlan,
            captureOrigins: coordinator.captureOrigins,
            planUnderlayDocument:
                coordinator.planUnderlayDocument,
            semanticCorrectionContext:
                coordinator.semanticCorrectionContext,
            liveSpatialAuthority:
                coordinator.workingSetSpatialAuthorityLive,
            recoveredDraftReport:
                coordinator.recoveredDraftReport,
            practiceCaptureActive:
                coordinator.practiceCaptureActive,
            practicePromptShown:
                coordinator.practicePromptShown,
            crossRevisionRegistrations:
                coordinator.crossRevisionRegistrations,
            missionProgressEvaluations:
                coordinator.missionProgressEvaluations,
            activeOperations: coordinator.activeOperations,
            operationTargetRevisionID:
                coordinator.operationTargetRevisionID,
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginScanning: coordinator.beginScanning,
                cancelCaptureSetup:
                    coordinator.cancelCaptureSetup,
                beginReview: coordinator.beginReview,
                captureEvidenceFrame: coordinator.captureEvidenceFrame,
                beginTargetScan: coordinator.beginTargetScan,
                retakeTargetScan: coordinator.retakeTargetScan,
                acceptTargetScan: coordinator.acceptTargetScan,
                cancelTargetScan: coordinator.cancelTargetScan,
                declareNearestUnresolvedRegion:
                    coordinator.declareNearestUnresolvedRegion,
                revokeOperatorRegion:
                    coordinator.revokeOperatorRegion,
                setGuidanceCuesEnabled:
                    coordinator.setGuidanceCuesEnabled,
                setLoopClosureCheckActive:
                    coordinator.setLoopClosureCheckActive,
                recordLoopClosureOutcome:
                    coordinator.recordLoopClosureOutcome,
                setScanMovementCapability:
                    coordinator.setScanMovementCapability,
                continueScanning:
                    coordinator.continueScanningFromReview,
                beginAnnotation: coordinator.beginAnnotation,
                captureRaycastPlacement:
                    coordinator.captureRaycastPlacement,
                captureSpeakerOrientation:
                    coordinator.captureSpeakerOrientation,
                capturePointOrientation:
                    coordinator.capturePointOrientation,
                probePlacementTarget:
                    coordinator.probePlacementTarget,
                probeCameraHeading:
                    coordinator.probeCameraHeading,
                captureTargetedPlacement:
                    coordinator.captureTargetedPlacement,
                captureIdentityPhoto:
                    coordinator.captureIdentityPhoto,
                scanEquipmentLabel:
                    coordinator.scanEquipmentLabel,
                captureFieldEvidencePhoto:
                    coordinator.captureFieldEvidencePhoto,
                commitFieldAuthority:
                    coordinator.commitFieldAuthority,
                commitAnnotationAuthority:
                    coordinator.commitAnnotationAuthority,
                cancelAnnotation: coordinator.cancelAnnotation,
                selectTaskProfile: coordinator.selectTaskProfile,
                importTaskPlan: coordinator.importTaskPlan,
                clearTaskPlan: coordinator.clearTaskPlan,
                flagForReview: coordinator.flagForReview,
                updateRevisitFlagDetails:
                    coordinator.updateRevisitFlagDetails,
                resolveRevisitFlag: coordinator.resolveRevisitFlag,
                reopenRevisitFlag: coordinator.reopenRevisitFlag,
                markTaskPlanItem:
                    coordinator.markTaskPlanItem(_:outcome:reason:),
                canRecordTaskPlanMarkReason:
                    coordinator.canRecordTaskPlanMarkReason,
                importEquipmentCatalog:
                    coordinator.importEquipmentCatalog,
                selectEquipmentCatalog:
                    coordinator.selectEquipmentCatalog,
                finalizeCapture: coordinator.finalizeCapture,
                prepareExport: coordinator.prepareExport,
                revalidateAdoptedRevision:
                    coordinator.revalidateAdoptedRevision,
                resetCapture: coordinator.resetCapture,
                openPersistedCapture:
                    coordinator.openPersistedCapture,
                deletePersistedCapture:
                    coordinator.deletePersistedCapture,
                removeQuarantinedArtifact:
                    coordinator.removeQuarantinedArtifact,
                removeWorkingOrphan:
                    coordinator.removeWorkingOrphan,
                revisePersistedCapture:
                    coordinator.revisePersistedCapture,
                reviseAdoptedCapture:
                    coordinator.reviseAdoptedCapture,
                importCaptureArchive:
                    coordinator.importCaptureArchive,
                discardActiveCapture:
                    coordinator.discardActiveCapture,
                resumeFailedAsDraft:
                    coordinator.resumeFailedCaptureAsDraft,
                keepFailedAsDraft:
                    coordinator.preserveFailedCaptureAsDraft,
                discardFailedAndStartNew:
                    coordinator.discardFailedAndStartNewCapture,
                refreshReviewWorkspace:
                    coordinator.refreshReviewWorkspace,
                captureRoomFrameOrigin:
                    coordinator.captureRoomFrameOriginPoint,
                confirmRoomReferenceFrame:
                    coordinator.confirmRoomReferenceFrame,
                confirmFieldDatumFromRoomFrame:
                    coordinator
                        .confirmFieldDatumFromRoomFrame,
                removeRoomFieldDatum:
                    coordinator.removeRoomFieldDatum,
                commitFieldDatum:
                    coordinator.commitFieldDatum,
                captureOpeningCenter:
                    coordinator.captureOpeningCenterPoint,
                clearOpeningCenter:
                    coordinator.clearOpeningCenterPoint,
                openingReviewCandidates:
                    coordinator.openingReviewCandidates,
                commitOpeningReview:
                    coordinator.commitOpeningReview,
                removeEvidenceFrameForPrivacy:
                    coordinator.removeEvidenceFrameForPrivacy,
                loadPersistedWorkspace:
                    coordinator.loadPersistedWorkspace,
                compareAdoptedRevisionWithParent:
                    coordinator.compareAdoptedRevisionWithParent,
                inspectFailedCapture:
                    coordinator.inspectFailedCapture,
                exportFailedCaptureDiagnostics:
                    coordinator.exportFailedCaptureDiagnostics,
                importMissionDocument:
                    coordinator.importMissionDocument,
                setConnectedSpaceIntent:
                    coordinator.setConnectedSpaceIntent,
                beginConnectedSegment:
                    coordinator.beginConnectedSegment,
                completeConnectedSegment:
                    coordinator.completeConnectedSegment,
                recordConnectedPortal:
                    coordinator.recordConnectedPortal,
                revisitConnectedRegion:
                    coordinator.revisitConnectedRegion,
                asBuiltMarkUnavailable:
                    coordinator.asBuiltMarkUnavailable,
                asBuiltEstablishAlignment:
                    coordinator.asBuiltEstablishAlignment,
                asBuiltRecordActual:
                    coordinator.asBuiltRecordActual,
                resolveRepairTask:
                    coordinator.resolveRepairTask,
                sendCaptureToHTDT:
                    coordinator.sendCaptureToHTDT,
                importMissionPackage:
                    coordinator.importMissionPackage,
                startMission: coordinator.startMission,
                deactivateMission:
                    coordinator.deactivateMission,
                archiveMission: coordinator.archiveMission,
                completeMission: coordinator.completeMission,
                updateMissionUserNote:
                    coordinator.updateMissionUserNote,
                evaluateMissionDependencies:
                    coordinator.evaluateMissionDependencies,
                pairDestinationPayload:
                    coordinator.pairDestinationPayload,
                confirmPairing: coordinator.confirmPairing,
                forgetDestination:
                    coordinator.forgetDestination,
                revokeDestination:
                    coordinator.revokeDestination,
                refreshEndpointCapabilities:
                    coordinator.refreshEndpointCapabilities,
                deliveryRetryNow:
                    coordinator.deliveryRetryNow,
                deliveryPause: coordinator.deliveryPause,
                deliveryResume: coordinator.deliveryResume,
                deliveryCancel: coordinator.deliveryCancel,
                deliveryPurgePayload:
                    coordinator.deliveryPurgePayload,
                preflightDestination:
                    coordinator.preflightDestination,
                deleteExportArchive:
                    coordinator.deleteExportArchive,
                updateLibraryEntry:
                    coordinator.updateLibraryEntry,
                importInboundDocument:
                    coordinator.importInboundDocument,
                confirmLibraryImport:
                    coordinator.confirmLibraryImport,
                dismissLibraryImport:
                    coordinator.dismissLibraryImport,
                exportLibraryPackage:
                    coordinator.exportLibraryPackage,
                setSeriesArchived:
                    coordinator.setSeriesArchived,
                updateRevisionMark:
                    coordinator.updateRevisionMark,
                deleteSeries: coordinator.deleteSeries,
                derivedExportInfo:
                    coordinator.derivedExportInfo,
                exportDerived3D:
                    coordinator.exportDerived3D,
                exportSurveyReport:
                    coordinator.exportSurveyReport,
                updateAppSettings:
                    coordinator.updateAppSettings,
                clearEquipmentCatalogCache:
                    coordinator.clearEquipmentCatalogCache,
                selectCaptureStrategy:
                    coordinator.selectCaptureStrategy,
                importPlanReference:
                    coordinator.importPlanReference,
                beginSemanticCorrection:
                    coordinator.beginSemanticCorrection,
                commitSemanticCorrection:
                    coordinator.commitSemanticCorrection,
                cancelSemanticCorrection:
                    coordinator.cancelSemanticCorrection,
                openRecoveredDraft:
                    coordinator.openRecoveredDraft,
                discardRecoveredDraft:
                    coordinator.discardRecoveredDraft,
                suspendReview:
                    coordinator.suspendReviewAndFinishLater,
                performRemediation:
                    coordinator.performRemediation,
                beginPracticeCapture:
                    coordinator.beginPracticeCapture,
                dismissPracticePrompt:
                    coordinator.dismissPracticePrompt,
                retryCameraPermission:
                    coordinator.retryCameraPermission,
                openCameraSettings:
                    coordinator.openCameraSettings,
                cancelCaptureStart:
                    coordinator.cancelCaptureStart,
                preferRevisionHead:
                    coordinator.preferRevisionHead,
                proposeRevisionAlignment:
                    coordinator.proposeRevisionAlignment,
                acceptRevisionAlignment:
                    coordinator.acceptRevisionAlignment,
                waiveMissionItem:
                    coordinator.waiveMissionItem,
                recordFieldNote: {
                    text, category, attention, attach, dictated,
                    anchor in
                    coordinator.recordFieldNote(
                        text: text,
                        category: category,
                        needsAttention: attention,
                        attachLatestEvidence: attach,
                        dictated: dictated,
                        anchorRequest: anchor
                    )
                },
                recordReviewFieldNote:
                    coordinator.recordReviewFieldNote,
                resolveFieldNote:
                    coordinator.resolveFieldNote,
                supersedeFieldNote:
                    coordinator.supersedeFieldNote,
                bindFieldNote:
                    coordinator.bindFieldNote,
                flagEvidenceFrameForPrivacy:
                    coordinator.flagEvidenceFrameForPrivacy,
                unflagEvidenceFrameForPrivacy:
                    coordinator.unflagEvidenceFrameForPrivacy,
                collectSupportDiagnostics:
                    coordinator.collectSupportDiagnostics,
                openFieldReturnWorkspace:
                    coordinator.openFieldReturnWorkspace,
                persistFieldReturnDraft:
                    coordinator.persistFieldReturnDraft,
                finalizeFieldReturn:
                    coordinator.finalizeFieldReturn,
                listFieldReturns:
                    coordinator.listFieldReturns,
                checkHTDTForMissions:
                    coordinator.checkHTDTForMissions,
                preflightFieldReturn:
                    coordinator.preflightFieldReturn,
                sendFieldReturnToHTDT:
                    coordinator.sendFieldReturnToHTDT,
                fieldReturnArtifactURL:
                    coordinator.fieldReturnArtifactURL,
                updateOperatorRoster:
                    coordinator.updateOperatorRoster,
                removeFromOperatorRoster:
                    coordinator.removeFromOperatorRoster
            )
        )
        .onOpenURL { url in
            // #393: every external document enters through the
            // inbound router — the kind is identified, gated by
            // capture state, then handed to its owning importer.
            coordinator.importInboundDocument(from: url)
        }
        // Foregrounding is when an iOS-Settings permission change
        // takes effect (#295).
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                coordinator.sceneDidBecomeActive()
            }
        }
    }
}


@MainActor
private final class HTDTCaptureHostCoordinator: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var capabilities: CaptureCapabilityMatrix
    @Published private(set) var cameraPermission: CameraPermissionStatus
    @Published private(set) var lastFailure: CaptureFailureCode?
    @Published private(set) var workingSetStatus =
        String(localized: "Not prepared")
    @Published private(set) var qualityReport: CaptureQualityReport?
    @Published private(set) var advisoryReport: CaptureAdvisoryReport?
    /// Operator-selected capture-task profile (#217/#259). Nil means the
    /// geometry-only default: task completeness evaluates to an
    /// explicit "no profile" state, never a misleading "Complete".
    @Published private(set) var taskProfile: CaptureTaskProfile?
    @Published private(set) var skippedTaskRequirementIDs: Set<String> = []
    /// Revisit flags dropped during the live scan (#325). Persisted
    /// into the working set at `session/revisit-flags.json` after
    /// every mutation; Review lists every unresolved one.
    @Published private(set)
    var revisitFlags: [ScanRevisitFlag] = []
    private var revisitFlagStore = CaptureRevisitFlagStore()
    /// #352: the HTDT task plan imported on the setup screen, held as
    /// verbatim bytes+plan until `continueBeginCapture` binds it to
    /// the new working revision.
    @Published private(set)
    var pendingTaskPlanImport: CaptureTaskPlanImport?
    /// Operator-visible failure of the last attempted plan import.
    @Published private(set)
    var pendingTaskPlanImportError: String?
    /// Live item-mark tracker for the bound task plan (#240/#352).
    private var boundTaskPlanStatus: CaptureTaskPlanStatus?
    /// True when the bounded revisit-flag store is full (#325).
    var revisitFlagsFull: Bool {
        revisitFlagStore.isFull
    }
    @Published private(set) var validationReport: BundleValidationReport?
    @Published private(set) var exportURL: URL?
    /// #437: typed reason the last finalize attempt was rejected —
    /// cleared when a retry starts or the capture leaves Review.
    @Published private(set)
    var finalizeRejection: CaptureFinalizeRejection?
    /// #437: typed reason the last export attempt was rejected —
    /// cleared on retry or when the finalized surface is left.
    @Published private(set)
    var exportRejection: CaptureExportRejection?
    /// #437: true when `.failed` was entered with a durable End
    /// boundary already committed — the failed working set can be
    /// preserved as a recoverable draft.
    @Published private(set)
    var failedDraftRecoverable = false
    @Published private(set)
    var annotationAuthorityCommitted = false
    @Published private(set)
    var annotationEvidenceRefs: [String] = []
    var annotationRoomPlanSurfaces: [CapturedSurfaceOption] = []
    var annotationMeshAnchors: [CapturedSurfaceOption] = []
    @Published private(set)
    var scanCoverage: ScanCoverageSummary = .empty
    @Published private(set)
    var observationStability: ObservationStabilitySummary = .empty
    @Published private(set)
    var spatialCoverage: SpatialScanCoverageSummary = .empty
    @Published private(set)
    var motionGuidance: ScanMotionGuidance?
    @Published private(set)
    var scanGuidanceProgress: ScanGuidanceProgress = .empty
    @Published private(set)
    var derivedShapePreview: DerivedShapePreviewSnapshot = .empty
    @Published private(set)
    var scanEvidenceFrameCount = 0
    @Published private(set)
    var scanDepthEvidenceCount = 0
    @Published private(set)
    var endScanGuidance: String?
    /// Pre-capture setup presentation while the state machine is in
    /// `.setup` (#212): capabilities, storage preflight, device
    /// readiness and the resolved production mode, shown before the
    /// capability/permission/RoomPlan pipeline runs.
    @Published private(set)
    var captureSetup: CaptureSetupPresentation?
    /// Live lighting assessment for dark-room guidance (#283).
    @Published private(set)
    var scanLightingStatus: ScanLightingStatus = .unknown
    /// True when live signals justify surfacing the low-light recovery
    /// copy instead of generic tracking text (#283).
    @Published private(set)
    var lowLightGuidanceActive = false
    /// Live status of the operator-targeted object orbit pass, if one
    /// is active (#250).
    @Published private(set)
    var targetScanStatus: TargetScanStatus?
    /// Operator-declared intentionally-unresolved regions (#257), in
    /// declaration order.
    @Published private(set)
    var declaredRegionList: [DeclaredCoverageRegion] = []
    /// Whether the optional return-to-start consistency check UI is
    /// active (#273).
    @Published private(set)
    var loopClosureCheckActive = false
    @Published private(set)
    var loopClosureAssessment: LoopClosureAssessment?
    /// The operator's response to the armed check ("accepted" /
    /// "reobserve" / "continued") — advisory provenance recorded
    /// beside the verdict at end-scan (#273).
    private(set) var loopClosureOutcome: String?
    /// Most recent assessment, retained after the check disarms so
    /// the end-scan note keeps the residual + verdict the operator
    /// answered (#273).
    private(set) var loopClosureLastAssessment:
        LoopClosureAssessment?
    /// Evidence class that supplied the in-progress object pass'
    /// aim anchor (#250), e.g. "existing_plane_geometry".
    private var targetScanAnchorSource: String?
    /// Evidence frames retained by the automatic keyframe policy this
    /// scan (#216), shown next to the manual/total count.
    @Published private(set)
    var automaticEvidenceFrameCount = 0
    /// Battery/charging/Low-Power snapshot for the setup screen (#272).
    @Published private(set)
    var deviceReadiness: CaptureDeviceReadiness?
    /// Whether haptic/announcement guidance cues play (#252). Mirrors
    /// the persisted presentation preference (#338); default on.
    @Published var guidanceCuesEnabled = true
    /// Versioned app-local settings (#338): presentation preferences,
    /// device-local workflow defaults, and the storage/privacy policy
    /// — never capture authority.
    @Published private(set)
    var appSettings = CaptureAppSettings()
    /// Durable store for `appSettings` under the app-private capture
    /// root — outside `finalized/`, `exports/` and `working/` so it is
    /// never part of a bundle or the persisted inventory.
    private lazy var appSettingsStore: CaptureAppSettingsStore? =
        Self.captureRootDirectory().map {
            CaptureAppSettingsStore(captureRoot: $0)
        }
    /// Operator-selected capture strategy for the next scan (#307).
    /// Drives advisory guidance/evidence budgets only — the canonical
    /// quality rule set never reads it.
    @Published private(set)
    var selectedStrategyID: CaptureStrategyIdentifier = .standard
    /// True when an imported task plan pins the strategy (#307/#240):
    /// the picker stays visible read-only and `selectCaptureStrategy`
    /// becomes a no-op until a new scan resets the pin.
    @Published private(set)
    var strategyPinnedByTaskPlan = false
    /// Live storage accounting for the active capture (#308):
    /// working-revision bytes by category, evidence counts, device free
    /// space and the automatic-keyframe budget. Advisory only.
    @Published private(set)
    var evidenceStorageAdvisory: CaptureEvidenceStorageAdvisory?
    /// Acquisition provenance for the library (#317), joined to
    /// persisted captures by capture_revision_id.
    @Published private(set)
    var captureOrigins:
        [CaptureRevisionID: CaptureAcquisitionOriginRecord] = [:]
    /// Imported plan-reference underlay for the next/active capture
    /// (#322). Shown in setup; rebound to the live revision's identity
    /// at session-foundation and persisted as `reference/plan-
    /// underlay.json`. Reference-only — never observed truth.
    @Published private(set)
    var planUnderlayDocument: PlanUnderlayDocument?
    /// Decoded parent context for an in-flight semantic correction
    /// (#319); non-nil while the correction sheet is open.
    @Published private(set)
    var semanticCorrectionContext:
        SemanticChildRevisionContext?
    @Published private(set)
    var persistedInventory = PersistedCaptureInventoryResult()
    /// Identity of the live working revision; carries the
    /// series/parent lineage so Review can show when a capture revises
    /// a stored finalized revision.
    @Published private(set)
    var workingSetIdentity: CaptureWorkingSetIdentity?
    /// Assembled Review workspace (plan preview, evidence gallery,
    /// openings, room frame) for the post-End states (#213/#241).
    @Published private(set)
    var reviewWorkspace: CaptureReviewWorkspaceModel?
    /// Required-task progress for the journey header (#372):
    /// evaluated from the active task plan plus the committed
    /// records — distinct from technical readiness.
    @Published private(set)
    var taskPlanMission: CaptureJourneyMissionSummary?
    /// Read-only workspace model for a persisted capture opened from
    /// the library (#294). Independent of the live-capture workspace.
    @Published private(set)
    var persistedWorkspace: CaptureReviewWorkspaceModel?
    /// RoomPlan bindables decoded beside `persistedWorkspace`
    /// (#408/#409) — drive the read-only 3D scene + survey targets
    /// in the persisted viewer.
    @Published private(set)
    var persistedWorkspaceRoomPlanObjects:
        [RoomPlanBindableObject] = []
    /// First captured point of the pending two-point room reference
    /// frame capture (issue #232).
    @Published private(set)
    var roomFrameOriginPending: WorldPoint3D?
    /// Camera-captured center pending a user-declared opening
    /// candidate (issue #231).
    @Published private(set)
    var openingCenterPending: WorldPoint3D?
    /// Spatial evidence links on committed annotations/measurements
    /// that no longer resolve after a re-End (issue #236). Surfaced for
    /// repair; never silently dropped.
    @Published private(set)
    var danglingSpatialIssues: [SpatialEvidenceIssue] = []
    /// Handoff destinations offered for the current finalized capture
    /// (#225): always the system share/file destination plus any
    /// operator-configured ingestion endpoints.
    @Published private(set)
    var handoffDestinations: [HTDTHandoffDestination] = []
    /// Receipts recorded for the adopted finalized revision (#225).
    @Published private(set)
    var handoffReceipts: [HTDTHandoffReceipt] = []
    /// Mission inbox records (#386) and the record currently driving
    /// the capture, if any.
    @Published private(set)
    var missionRecords: [HTDTMissionRecord] = []
    @Published private(set)
    var activeMissionRecordID: String?
    /// QR-paired, identity-pinned receivers (#379).
    @Published private(set)
    var pairedDestinations: [PairedHTDTDestination] = []
    /// Durable delivery-queue ledger (#387).
    @Published private(set)
    var deliveryJobs: [HTDTDeliveryJob] = []
    /// Accepted cross-revision spatial registrations (#395) — the
    /// app-local transform authority the library surfaces.
    @Published private(set)
    var crossRevisionRegistrations:
        [CrossRevisionRegistration] = []
    /// Replayed mission progress keyed by inbox record id (#397) —
    /// completeness recomputed from the append-only ledger, never a
    /// stored percentage.
    @Published private(set)
    var missionProgressEvaluations:
        [String: MissionProgressEvaluation] = [:]
    /// SHA of the plan bytes bound to `taskPlan` (#386): the mission's
    /// embedded plan import carries its own content digest.
    private var taskPlanSHA256: EvidenceSHA256?
    /// Operator-facing library metadata (names, notes, series
    /// lifecycle state, revision marks) layered over the persisted
    /// inventory (issues #219/#394).
    @Published private(set)
    var libraryMetadata = CaptureLibraryMetadataDocument()
    /// #390: one-line operator notice when an app-local durable
    /// document was written by a different app version and could not
    /// be upgraded — its bytes are preserved and journaled instead
    /// of silently emptied. nil when everything migrated or nothing
    /// was preserved.
    @Published private(set)
    var localStateUpgradeNotice: String?
    /// #378: staged library-package import preview awaiting the
    /// operator's confirm — the owning importer has already
    /// validated the manifest, every archive, and the merge.
    @Published private(set)
    var libraryImportPreview: CaptureLibraryImportPreview?
    /// Staging directory backing `libraryImportPreview`; discarded
    /// on confirm or dismiss.
    private var libraryImportStagingDirectory: URL?
    /// #378: the most recently written `.htdtcapturelibrary`
    /// package, offered to the ShareLink row on the home surface.
    @Published private(set)
    var libraryExportURL: URL?
    /// Inspection of the retained working set of the current failed
    /// capture (issue #224); populated on demand.
    @Published private(set)
    var failedInspection: FailedCaptureInspection?
    /// Seed collections for a pre-finalization annotation edit: the
    /// canonical authority previously committed inside the same working
    /// revision, reloaded for correction (#163).
    @Published private(set)
    var annotationRevisionSeed: AnnotationWorkspaceSeed?
    /// Operator reference context for exact equipment selection (#211).
    /// The imported HTDT catalog snapshot is host-owned and mirrored to
    /// an app-support cache so it survives annotation cancel → Review →
    /// re-enter and app relaunch. It is never persisted into the capture
    /// bundle: annotations store only the exact selected equipment
    /// tuple as immutable authority.
    @Published private(set)
    var equipmentCatalog: HTDTEquipmentCatalogSnapshot?
    /// Every catalog snapshot stored in the multi-catalog library
    /// (#302); the annotation workspace lists them for explicit
    /// operator selection.
    @Published private(set)
    var equipmentCatalogLibrary:
        [HTDTEquipmentCatalogLibrary.StoredCatalog] = []
    /// Imported capture task plan (#240), if the host has supplied one;
    /// its catalog pin and layout profile drive workspace behavior
    /// (#302/#315). No in-app import path exists yet.
    @Published private(set)
    var taskPlan: HTDTCaptureTaskPlan?
    private let equipmentCatalogStore =
        HTDTCaptureHostCoordinator.makeEquipmentCatalogLibrary()
    /// App-local operator roster (#458): Author identities saved once
    /// on this device, persisted beside the equipment catalog at the
    /// capture root — never inside a bundle.
    private let operatorRosterStore =
        HTDTCaptureHostCoordinator.makeOperatorRosterStore()
    /// Profiles remembered on this device (#458), mirrored to the
    /// Operators sheet.
    @Published private(set)
    var operatorRoster: [OperatorProfile] = []

    /// Visual presentation for each retained evidence frame (#255),
    /// refreshed whenever the workspace's linkable ref set changes.
    @Published private(set)
    var annotationEvidenceFrames: [EvidenceFramePresentation] = []
    /// Persisted RoomPlan objects offered for direct placement binding
    /// (#246), decoded once per annotation session from the accepted
    /// `roomplan/captured-room.json`.
    @Published private(set)
    var annotationRoomPlanObjects: [RoomPlanBindableObject] = []
    /// Accepted-geometry context for advisory plausibility checks
    /// (#247); empty means geometry is unavailable ("analysis
    /// unavailable", never a silent pass).
    @Published private(set)
    var spatialPlausibilityContext = SpatialPlausibilityContext()
    /// Findings for the committed annotation set; nil = unavailable.
    @Published private(set)
    var spatialPlausibilityFindings: [SpatialPlausibilityFinding]?
    /// Session-level equipment-picker recents (#265).
    let equipmentRecents = EquipmentRecents()
    /// Explicit operator-selected layout plans for guided batch
    /// capture (#278): presets act as the task profile until #217/#240
    /// plans land.
    let speakerLayoutPlans = SpeakerLayoutPresets.all
    /// Draft autosave store (#266), rooted under the app-private
    /// capture root — outside the persisted-inventory scan directories
    /// so drafts never register as capture authority.
    private lazy var annotationDraftStoreValue:
        AnnotationWorkspaceDraftStore? =
        Self.captureRootDirectory().map {
            AnnotationWorkspaceDraftStore(
                directoryURL: $0.appendingPathComponent(
                    "annotation-drafts",
                    isDirectory: true
                )
            )
        }
    var annotationDraftStore: AnnotationWorkspaceDraftStore? {
        annotationDraftStoreValue
    }
    var annotationDraftRevisionID: CaptureRevisionID? {
        workingSetIdentity?.captureRevisionID
    }
    /// Why each retained evidence frame exists (#255 picker labels).
    private var annotationRetentionKinds:
        [String: EvidenceFrameRetentionKind] = [:]
    /// Committed `derived/equipment-identity.json` bytes, so an empty
    /// record set on the next revision commit discards byte-identical
    /// rather than leaving a stale attestation (#239).
    private var committedIdentityDocData: Data?
    /// Field-authority workspace staged by the annotation editor,
    /// consumed inside `commitAnnotationAuthority` (#300/#301/#310/
    /// #314/#324/#331).
    private var pendingFieldAuthority = FieldAuthorityWorkspace()
    private var annotationRoomPlanObjectsLoaded = false

    // MARK: Mission workflow state (#353/#240/#222/#293/#321)

    /// Imported capture task plan + per-item outcomes (#240); the
    /// plan payload persists verbatim in the working revision.
    @Published private(set)
    var captureTaskPlan: HTDTCaptureTaskPlan?
    private var captureTaskPlanImport: CaptureTaskPlanImport?
    private var captureTaskPlanStatus: CaptureTaskPlanStatus?
    @Published private(set)
    var missionTaskPlanOutcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome] = []
    /// Operator's multi-region intent declared at setup or in the
    /// mission sheet (#353); keeps connected-space controls hidden
    /// from simple captures.
    @Published private(set)
    var connectedSpaceIntent = false
    @Published private(set)
    var connectedSpaceTracker: ConnectedSpaceTracker?
    /// Imported as-built plan (#293) + verification session bound to
    /// the live coordinate space.
    @Published private(set)
    var asBuiltPlan: HTDTAsBuiltPlan?
    private var asBuiltPlanImport: HTDTAsBuiltPlanImport?
    private var asBuiltSession: AsBuiltVerificationSession?
    @Published private(set)
    var asBuiltItems: [AsBuiltVerificationItem] = []
    @Published private(set)
    var asBuiltAlignmentInstalled = false
    /// Committed annotation entities offered as actual observations
    /// for as-built items.
    @Published private(set)
    var asBuiltActualCandidates: [CaptureAnnotationEntity] = []
    /// A committed room reference frame exists in the working set —
    /// the as-built plan alignment authority anchor (#293).
    @Published private(set)
    var roomFrameAvailable = false
    /// HTDT repair tasks returned by ingestion (#321), across all
    /// received plans; unresolved rows are surfaced as actionable.
    @Published private(set)
    var repairTaskRows: [HTDTRepairTaskRow] = []
    /// The revision a repair link was persisted into — resolution
    /// is only credited when THAT revision promotes (#321).
    private var persistedRepairLinkRevisionID: CaptureRevisionID?
    /// Row currently routed by "Fix in Capture"; resolved by the
    /// promoted repair revision (fresh rescan) or by the next
    /// annotation authority commit (in-place repairs).
    private var activeRepairRow: HTDTRepairTaskRow?
    /// App-local repair-plan ledger under the capture root (#321).
    private lazy var repairPlanStore: HTDTRepairPlanStore? =
        Self.captureRootDirectory().map {
            HTDTRepairPlanStore(captureRoot: $0)
        }

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var finalizedRevision: FinalizedCaptureRevision?
    private var resourceMonitor: CaptureResourceMonitor?
    private var resourceEventTask: Task<Void, Never>?
    private var captureGeneration = UUID()
    /// Published so the scanning UI can show the End transaction as a
    /// visible busy state instead of leaving controls tappable while
    /// the host guards make them no-op (#279).
    @Published private(set) var isEndingScan = false
    @Published private(set) var isCapturingEvidenceFrame = false
    /// Handle on the in-flight manual evidence-save persistence task.
    /// End drains it before sampling the working set so a committed
    /// save lands wholly before the End boundary (#179).
    private var evidenceFrameSaveTask: Task<Void, Never>?
    private var endScanPreflightBlocked = false
    private var captureStartTimingCorrelation:
        CaptureTimingCorrelation?
    private var acceptedRoomPlanRawSHA256: EvidenceSHA256?
    private var acceptedEndMeshWasPersisted = false
    /// Number of RoomPlan `run()` segments started on the current
    /// revision. Each re-run rebuilds the room model from that
    /// segment's observations alone, so segment 2+ carries an
    /// advisory-provenance note into the bundle.
    private var roomPlanScanSegmentOrdinal = 0
    private var pendingEndAttempt: PendingEndScanAttempt?
    private var roomPlanCompletionInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var annotationCommitInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var reviewOperationInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var exportOperationInFlight = false {
        didSet { syncActiveOperations() }
    }
    private(set) var spatialAuthoritySealedForFinalization = false
    /// #297: false when the working set was rebuilt from disk by
    /// `restoreWorkingRevision` — its AR coordinate authority ended
    /// with the prior process, so live spatial mutation is
    /// permanently unavailable.
    @Published private(set) var workingSetSpatialAuthorityLive = true
    /// Recovery provenance for the currently open recovered draft
    /// (#297): unsupported/superseded files the restore pass found.
    @Published private(set)
    var recoveredDraftReport: WorkingRevisionRestoreReport?
    /// #320: the active working set is a practice rehearsal — it is
    /// never finalizable and never sendable to HTDT.
    @Published private(set) var practiceCaptureActive = false
    /// First-launch practice prompt (#320): shown until the operator
    /// dismisses it; "Don't show again" suppresses it permanently.
    @Published private(set) var practicePromptShown = false
    private var activeCaptureIsPractice = false
    private static let practicePromptDismissedDefaultsKey =
        "practice_prompt_dismissed"
    /// Explicit commit-point policy for the finalization transaction
    /// (#185). While claimed, terminal lifecycle/resource failures are
    /// fenced instead of invalidating the capture generation; a fenced
    /// failure either cancels the transaction pre-promotion (no
    /// finalized destination produced) or is surfaced as post-capture
    /// status after the promoted revision is adopted (commit wins).
    private var finalizationCommit = FinalizationCommitPolicy()
    private var persistedStore: PersistedCaptureInventory?
    private var persistedInventoryRequest = 0
    private var persistedAdoptionInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var persistedDeletionInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var importOperationInFlight = false {
        didSet { syncActiveOperations() }
    }
    /// Read-only persisted workspace load (#309: the View row was the
    /// one library action with no in-flight guard at all).
    private var persistedWorkspaceLoadInFlight = false {
        didSet { syncActiveOperations() }
    }
    private var exportDiagnosticsInFlight = false {
        didSet { syncActiveOperations() }
    }
    /// In-flight host operations published for busy-state UI (#309):
    /// controls disable visibly instead of silently no-op'ing against
    /// the guards in each action.
    @Published private(set)
    var activeOperations: Set<CaptureHostOperation> = []
    /// Revision a persisted-library operation is currently acting on,
    /// so that row can show its own progress affordance (#309).
    @Published private(set)
    var operationTargetRevisionID: CaptureRevisionID?

    private func syncActiveOperations() {
        var operations = Set<CaptureHostOperation>()
        if importOperationInFlight {
            operations.insert(.importArchive)
        }
        if persistedAdoptionInFlight
            || persistedWorkspaceLoadInFlight
        {
            operations.insert(.openPersisted)
        }
        if persistedDeletionInFlight {
            operations.insert(.deletePersisted)
        }
        if exportOperationInFlight {
            operations.insert(.prepareExport)
        }
        if reviewOperationInFlight {
            operations.insert(.reviewOperation)
        }
        if annotationCommitInFlight {
            operations.insert(.annotationCommit)
        }
        if exportDiagnosticsInFlight {
            operations.insert(.exportDiagnostics)
        }
        activeOperations = operations
        if operations.isEmpty {
            operationTargetRevisionID = nil
        }
    }
    /// Lineage for the working revision being prepared: nil for a fresh
    /// series root, or the validated parent identity for a
    /// revise-existing capture.
    private var activeRevisionLineage: RevisionLineage?
    private var annotationEditIsRevision = false
    private var scanCoverageTracker =
        AdvisoryScanCoverageTracker()
    private var observationStabilityTracker =
        ObservationStabilityTracker()
    private var spatialCoverageAggregator =
        SpatialScanCoverageAggregator()
    private var motionGuidanceTracker =
        ScanMotionGuidanceTracker()
    private var derivedObjectFusionTracker =
        DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 6,
                maximumAgeSeconds: 24,
                voxelSizeMeters: 0.055,
                maximumPointCount: 384
            )
        )
    private var derivedVolumeFusionTracker =
        DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 6,
                maximumAgeSeconds: 24,
                voxelSizeMeters: 0.055,
                maximumPointCount: 384
            )
        )
    private var derivedWallFusionTracker =
        DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 4,
                maximumAgeSeconds: 20,
                voxelSizeMeters: 0.08,
                maximumPointCount: 256
            )
        )
    private var scanCoverageTask: Task<Void, Never>?
    private var scanTrackingTransitionGate =
        ScanTrackingTransitionGate()
    private var scanGuidanceCuePolicy = ScanGuidanceCuePolicy()
    private var automaticKeyframeTracker =
        AutomaticKeyframeTracker()
    private var operatorRegionDeclarations =
        OperatorRegionDeclarations()
    private var targetScanTracker: TargetedObjectScanTracker?
    private var loopClosurePolicy = LoopClosureCheckPolicy()
    private var scanLightingPolicy = ScanLightingPolicy()
    /// Byte total persisted by automatic keyframes; combined with the
    /// estimator's own bound so a stored overrun still stops the
    /// selector (#216).
    private var automaticKeyframePersistedBytes = 0
    /// Task-plan strategy override resolved at scan start (#307/#240):
    /// a pinned recommendation wins over the operator selection until
    /// the next `beginCapture` resets it.
    private var taskPlanStrategyOverride:
        (identifier: CaptureStrategyIdentifier, pinned: Bool)?
    /// The strategy actually used for the active scan — resolved at
    /// `beginCapture` so mid-scan setup edits cannot change budgets.
    private var activeCaptureStrategy: CaptureStrategyProfile =
        .standard
    /// The source under which `activeCaptureStrategy` was resolved —
    /// echoed into `session/capture-strategy.json` (#307).
    private var pendingStrategySource: CaptureStrategySource =
        .operatorSelected
    /// App-local acquisition-provenance store (#317): lives outside the
    /// immutable bundle under the capture root, keyed by
    /// capture_revision_id.
    private var captureOriginStore: CaptureAcquisitionOriginStore?
    /// Periodic storage sampler for the #308 advisory surface; runs at
    /// the resource-monitor cadence while `.scanning`.
    private var storageSampleTask: Task<Void, Never>?
    /// Parent record the semantic-correction sheet is editing (#319).
    private var semanticCorrectionParent: PersistedCaptureRecord?
    private var semanticCorrectionInFlight = false
    /// Whether the display idle-timer override is currently held for
    /// this capture (#272). Restored on every transition out of
    /// `.scanning`, so failure/End/reset paths cannot leak it.
    private var displayIdleTimerSuspended = false
    private var deviceReadinessObserving = false
    private var deviceReadinessObservers: [NSObjectProtocol] = []
    /// Latest scan sample's session-clock seconds — the timestamp base
    /// for advisory notes written from operator actions (#257/#250).
    private var latestScanTimestampSeconds: Double?
    /// Bounded in-flight automatic keyframe persistence; End drains it
    /// with the manual save so the End boundary stays atomic (#179).
    private var automaticFrameSaveTask: Task<Void, Never>?
    private var memoryWarningCancellable: AnyCancellable?
    private var derivedPreviewSuspendedForMemoryPressure = false
    private var roomPlanModelRenderingEnabled = true
    // 1.2.0 adds the versioned tracking-recovery and depth-fallback
    // sufficiency policies (#242, #284). Published 1.1.0 semantics stay
    // pinned in the registry for reopened/older captures.
    private let qualityRequirements = CaptureQualityRequirements(
        rulesetVersion: "1.2.0"
    )
    /// Bounded wait for a RoomPlan completion callback that never
    /// arrives (#96): warn the operator after `warningDelay`, then
    /// terminate the unresolved End attempt at `terminationDelay`
    /// instead of leaving the capture locked in `isEndingScan`.
    private static let roomPlanEndTimeoutPolicy =
        RoomPlanEndTimeoutPolicy()

    init() {
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()
        persistedStore = Self.makePersistedStore()
        captureOriginStore = Self.captureRootDirectory().map {
            CaptureAcquisitionOriginStore(captureRoot: $0)
        }

        // #390: every registered app-local durable document upgrades
        // before any store reads it — only through a verified
        // version step, preserving bytes + a journal entry whenever
        // the stored version is newer, unreadable, or has no
        // migration path.
        if let captureRoot = Self.captureRootDirectory() {
            let runtime = PlatformRuntimeProvenance.current()
            let report = LocalStateMigrator.migrate(
                captureRoot: captureRoot,
                appVersion: runtime.appVersion,
                appBuild: runtime.appBuild
            )
            let preserved = report.events.filter {
                $0.outcome != .migrated
            }
            if !preserved.isEmpty {
                localStateUpgradeNotice = String(localized: "Some saved app data was written by a different app version and was kept unchanged so nothing was lost")
            }
        }

        // #338: load the versioned app-local settings before any
        // policy application so the at-rest backup policy below
        // matches the operator's stored choice. A corrupt settings
        // file fails closed like the library metadata store — the
        // app runs on defaults and the status line says why rather
        // than silently discarding the operator's intent.
        if let appSettingsStore {
            do {
                appSettings = try appSettingsStore.load()
            } catch {
                workingSetStatus = String(localized: "Device settings could not be read; defaults are in use")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
        guidanceCuesEnabled =
            appSettings.presentation.guidanceCuesEnabled

        // #320: the first-launch practice prompt is suppressed only by
        // an explicit permanent dismissal; "Not now" hides it for this
        // run while practice stays reachable from the home surface.
        practicePromptShown = !UserDefaults.standard.bool(
            forKey: Self.practicePromptDismissedDefaultsKey
        )

        // At-rest policy is applied before the first inventory scan so
        // the app-owned roots carry their backup/protection attributes
        // even when no capture has ever run (#136, #166). Failures are
        // surfaced in the status line rather than silently ignored.
        if let captureRoot = Self.captureRootDirectory() {
            let policyFailures =
                CaptureStoragePolicy.applyCaptureRootPolicy(
                    captureRoot: captureRoot,
                    finalizedBackupPolicy: appSettings
                        .storagePrivacy.finalizedBackupPolicy
                )
            if !policyFailures.isEmpty {
                workingSetStatus =
                    String(localized: "Storage protection policy was not fully applied to the capture roots")
                    + " ["
                    + policyFailures.joined(separator: "; ")
                    + "]"
            }
        }

        loadPersistedCaptures()
        refreshRepairTaskRows()

        // #386/#379/#387: surface the mission inbox, paired
        // receivers and delivery ledger immediately, then reconcile
        // the durable queue — a job `sending` when the app last
        // exited is rescheduled for an idempotent retry, and every
        // due job resumes under the queue's backoff.
        refreshMissionDeliveryStores()
        if let queue = deliveryQueueStore {
            try? queue.reconcileOnLaunch()
            refreshMissionDeliveryStores()
            Task { @MainActor [weak self] in
                _ = await queue.processDueJobs(
                    receiptStore: self?.handoffReceiptStore()
                )
                self?.refreshMissionDeliveryStores()
            }
        }

        // #211/#302: restore the catalog library — the legacy
        // single-slot cache migrates in-place, then the active (or
        // sole) stored snapshot becomes the operator's reference
        // context. A missing or invalid entry is surfaced to the
        // workspace rather than silently substituted.
        if let equipmentCatalogStore {
            // list()/active() fold the pre-#302 single-slot cache into
            // the library on first read.
            equipmentCatalogLibrary = equipmentCatalogStore.list()
            equipmentCatalog = equipmentCatalogStore.active()?.snapshot
        }

        // #458: restore the app-local operator roster — saved Author
        // profiles survive relaunch and are offered for reuse in the
        // Operators sheet of every later capture.
        operatorRoster =
            (try? operatorRosterStore?.load().operators) ?? []

        #if canImport(UIKit)
        memoryWarningCancellable =
            NotificationCenter.default
                .publisher(
                    for: UIApplication
                        .didReceiveMemoryWarningNotification
                )
                .sink { [weak self] _ in
                    Task { @MainActor in
                        guard let self else {
                            return
                        }
                        self.derivedPreviewSuspendedForMemoryPressure =
                            true
                        self.derivedShapePreview = .empty
                        self.setRoomPlanModelRenderingEnabled(false)
                    }
                }
        #endif
    }

    /// Validated parent identity for a revise-existing capture: the
    /// child's `capture_series_id` equals the parent's and its
    /// `parent_revision_id` names the exact prior revision.
    private struct RevisionLineage: Sendable, Equatable {
        let captureSeriesID: CaptureSeriesID
        let parentRevisionID: CaptureRevisionID
    }

    var scanSessionController: SharedARSessionController {
        sessionController
    }

    private func setRoomPlanModelRenderingEnabled(
        _ enabled: Bool
    ) {
        guard roomPlanModelRenderingEnabled != enabled else {
            return
        }
        roomPlanModelRenderingEnabled = enabled
        sessionController.setRoomPlanModelRenderingEnabled(enabled)
    }


    var annotationCoordinateSpaceID: CoordinateSpaceID? {
        guard !spatialAuthoritySealedForFinalization,
              state == .reviewing || state == .annotating
        else {
            return nil
        }
        return sessionController.context.coordinateSpaceID
    }

    /// Bound space for the annotation workspace. While live capture
    /// runs this is the active session space; once spatial authority
    /// is sealed for finalization (#276), the same working-set space
    /// stays the correct binding for non-spatial corrections —
    /// sealing pauses AR, it does not rebind the committed authority.
    /// It is returned whether or not annotations were already
    /// committed so a sealed-but-uncommitted Review still renders the
    /// workspace (spatial affordances hide on the seal itself).
    var annotationWorkspaceCoordinateSpaceID: CoordinateSpaceID? {
        if !spatialAuthoritySealedForFinalization {
            return annotationCoordinateSpaceID
        }
        guard state == .reviewing || state == .annotating else {
            return nil
        }
        return sessionController.context.coordinateSpaceID
    }

    func beginCapture() { 
        beginCapture(revisionLineage: nil)
    }

    /// #320 practice mode: a full rehearsal of the real capture flow —
    /// scan guidance, End, Review, quality diagnostics — on a working
    /// set that can never finalize or send to HTDT.
    func beginPracticeCapture() {
        guard state == .idle,
              capabilities.roomPlanMeshEligible
        else {
            return
        }
        practicePromptShown = false
        beginCapture(revisionLineage: nil, practice: true)
    }

    /// #320: "Not now" hides the prompt for this run; "Don't show
    /// again" writes the durable opt-out.
    func dismissPracticePrompt(permanently: Bool) {
        practicePromptShown = false
        if permanently {
            UserDefaults.standard.set(
                true,
                forKey: Self.practicePromptDismissedDefaultsKey
            )
        }
    }

    /// Starts a correction capture for a stored finalized revision: the
    /// record is revalidated on disk before its manifest identity is
    /// used as lineage authority, then an ordinary new scan begins.
    /// The new revision shares the parent's `capture_series_id` and
    /// records the parent as `parent_revision_id`; the finalized parent
    /// is never opened for mutation and no spatial evidence is carried
    /// into the new coordinate space (#155).
    func revisePersistedCapture(_ record: PersistedCaptureRecord) {
        guard state == .idle,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight,
              !importOperationInFlight,
              let store = persistedStore
        else {
            return
        }
        // An unfinalized or unvalidated artifact can never seed a child
        // revision; lineage authority only comes from a validated
        // manifest.
        guard record.canOpen || record.exportArchive != nil else {
            return
        }

        persistedAdoptionInFlight = true
        operationTargetRevisionID = record.captureRevisionID
        workingSetStatus = String(localized: "Revalidating the parent revision")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let archiveURL = record.exportArchive
            let lineage = await Task.detached(
                priority: .userInitiated
            ) { () -> RevisionLineage? in
                // Prefer the canonical finalized directory; fall back to
                // the validated export archive when only it survives.
                if let fresh = store.validatedRecord(
                    captureRevisionID: record.captureRevisionID
                ), let validation = fresh.finalizedValidation {
                    return RevisionLineage(
                        captureSeriesID:
                            validation.manifest.captureSeriesID,
                        parentRevisionID:
                            validation.manifest.captureRevisionID
                    )
                }
                if let archiveURL,
                   let report =
                    try? StoredCaptureBundleArchiveValidator
                        .validate(archive: archiveURL),
                   report.manifest.captureRevisionID
                    == record.captureRevisionID
                {
                    return RevisionLineage(
                        captureSeriesID:
                            report.manifest.captureSeriesID,
                        parentRevisionID:
                            report.manifest.captureRevisionID
                    )
                }
                return nil
            }.value

            self.persistedAdoptionInFlight = false
            guard self.state == .idle else {
                return
            }
            guard let lineage else {
                self.loadPersistedCaptures()
                self.workingSetStatus = String(localized: "The parent capture could not be revalidated; the on-disk inventory was refreshed")
                return
            }
            self.beginCapture(revisionLineage: lineage)
        }
    }

    /// Starts a correction capture for the currently adopted finalized
    /// revision. The manifest was already validated at adoption, so its
    /// identity is the lineage authority; the host returns to idle and
    /// begins a fresh scan in a new revision of the same series (#155).
    func reviseAdoptedCapture() {
        guard state == .finalized || state == .exported,
              let manifest = validationReport?.manifest
        else {
            return
        }
        let lineage = RevisionLineage(
            captureSeriesID: manifest.captureSeriesID,
            parentRevisionID: manifest.captureRevisionID
        )
        resetCapture()
        guard state == .idle else {
            return
        }
        beginCapture(revisionLineage: lineage)
    }

    private func beginCapture(
        revisionLineage: RevisionLineage?,
        practice: Bool = false
    ) {
        // A persisted-library operation in flight holds authority over
        // the inventory/import pipeline; starting a capture mid-flight
        // would collide with its completion (#309).
        guard state == .idle,
              !importOperationInFlight,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight
        else {
            return
        }

        activeRevisionLineage = revisionLineage
        activeCaptureIsPractice = practice
        practiceCaptureActive = practice
        workingSetSpatialAuthorityLive = true
        recoveredDraftReport = nil
        workingSetIdentity = nil
        annotationRevisionSeed = nil
        pendingFieldAuthority = FieldAuthorityWorkspace()
        annotationEditIsRevision = false
        qualityReport = nil
        validationReport = nil
        exportURL = nil
        finalizedRevision = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        annotationRoomPlanSurfaces = []
        annotationMeshAnchors = []
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false
        roomPlanScanSegmentOrdinal = 0
        pendingEndAttempt = nil
        roomPlanCompletionInFlight = false
        annotationCommitInFlight = false
        reviewOperationInFlight = false
        exportOperationInFlight = false
        spatialAuthoritySealedForFinalization = false
        finalizationCommit.reset()
        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        scanCoverageTracker = AdvisoryScanCoverageTracker()
        scanCoverage = scanCoverageTracker.summary()
        handoffDestinations = []
        handoffReceipts = []
        reviewWorkspace = nil
        taskPlanMission = nil
        persistedWorkspace = nil
        persistedWorkspaceRoomPlanObjects = []
        roomFrameOriginPending = nil
        openingCenterPending = nil
        danglingSpatialIssues = []
        failedInspection = nil
        // Per-capture mission runtime resets; imported mission
        // inputs (plans, staged payloads, the active repair row)
        // carry into this new revision on purpose (#353/#321).
        connectedSpaceIntent = false
        connectedSpaceTracker = nil
        asBuiltSession = nil
        asBuiltItems = []
        asBuiltAlignmentInstalled = false
        asBuiltActualCandidates = []
        roomFrameAvailable = false
        missionTaskPlanOutcomes = []
        persistedRepairLinkRevisionID = nil
        observationStabilityTracker =
            ObservationStabilityTracker()
        observationStability =
            observationStabilityTracker.summary()
        spatialCoverageAggregator =
            SpatialScanCoverageAggregator()
        spatialCoverage = .empty
        // Resolve the capture strategy for this scan (#307): a pinned
        // task-plan recommendation wins, then a plan recommendation,
        // then the operator pick. The resolved profile configures the
        // advisory trackers only — canonical quality rules never read
        // it — and is persisted into session/capture-strategy.json at
        // session-foundation time.
        let (strategyProfile, strategySource) =
            resolvedCaptureStrategy()
        activeCaptureStrategy = strategyProfile
        pendingStrategySource = strategySource
        motionGuidanceTracker = ScanMotionGuidanceTracker(
            configuration: strategyProfile.motionGuidance
        )
        motionGuidance = nil
        scanGuidanceProgress = .empty
        derivedObjectFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384,
                    maximumObservationCenterShiftMeters: 0.65
                )
            )
        derivedVolumeFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384,
                    maximumObservationCenterShiftMeters: 0.65
                )
            )
        derivedWallFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 4,
                    maximumAgeSeconds: 20,
                    voxelSizeMeters: 0.08,
                    maximumPointCount: 256
                )
            )
        derivedShapePreview = .empty
        derivedPreviewSuspendedForMemoryPressure = false
        setRoomPlanModelRenderingEnabled(true)
        scanEvidenceFrameCount = 0
        scanDepthEvidenceCount = 0
        endScanGuidance = nil
        endScanPreflightBlocked = false
        scanTrackingTransitionGate.reset()
        scanGuidanceCuePolicy.reset()
        automaticKeyframeTracker = AutomaticKeyframeTracker(
            configuration: strategyProfile.automaticKeyframes
        )
        automaticKeyframePersistedBytes = 0
        automaticEvidenceFrameCount = 0
        automaticFrameSaveTask?.cancel()
        automaticFrameSaveTask = nil
        storageSampleTask?.cancel()
        storageSampleTask = nil
        evidenceStorageAdvisory = nil
        semanticCorrectionContext = nil
        semanticCorrectionParent = nil
        scanLightingStatus = .unknown
        lowLightGuidanceActive = false
        endTargetScan()
        operatorRegionDeclarations = OperatorRegionDeclarations()
        declaredRegionList = []
        // Device-local workflow defaults seed each capture (#338):
        // the stored default task profile initializes unset task
        // state, but the project/task plan — the workspace's
        // explicit selection — stays the override authority.
        taskProfile = appSettings.captureDefaults.defaultTaskProfile
        skippedTaskRequirementIDs = []
        loopClosureCheckActive =
            appSettings.captureDefaults.returnToStartCheckEnabled
        revisitFlagStore = CaptureRevisitFlagStore()
        revisitFlags = []
        pendingTaskPlanImport = nil
        pendingTaskPlanImportError = nil
        boundTaskPlanStatus = nil
        loopClosureCheckActive = false
        loopClosureAssessment = nil
        loopClosureLastAssessment = nil
        loopClosureOutcome = nil
        latestScanTimestampSeconds = nil
        resourceMonitor?.stop()
        resourceMonitor = nil
        resourceEventTask = nil

        do {
            try transition(.prepareCapture)
        } catch {
            fail(.unknown)
            return
        }

        // The capability/permission/RoomPlan pipeline and the canonical
        // session clock start only when the operator confirms on the
        // setup screen; `.setup` itself creates no capture authority
        // (#212).
        refreshCaptureSetupPresentation()
        startDeviceReadinessObserving()
    }

    /// Operator confirmed setup: leave `.setup` and run the ordinary
    /// capability → permission → prepare → RoomPlan pipeline (#212).
    func beginScanning() {
        guard state == .setup else {
            return
        }
        do {
            try transition(.beginCapabilityCheck)
        } catch {
            fail(.unknown)
            return
        }
        captureSetup = nil

        Task {
            await continueBeginCapture()
        }
    }

    /// Operator cancelled the pre-capture setup: back to Idle with no
    /// capture session ever created (#212).
    func cancelCaptureSetup() {
        guard state == .setup else {
            return
        }
        do {
            try transition(.reset)
        } catch {
            fail(.unknown)
            return
        }
        captureSetup = nil
        stopDeviceReadinessObserving()
        workingSetStatus = String(localized: "Ready")
    }

    /// Rebuild the setup-screen model with a fresh storage preflight
    /// and device readiness sample (#212, #272).
    private func refreshCaptureSetupPresentation() {
        capabilities = PlatformCapabilityProbe.current()
        deviceReadiness = Self.currentDeviceReadiness()
        captureSetup = CaptureSetupPresentation(
            capabilities: capabilities,
            storagePreflight: Self.currentStoragePreflight(),
            deviceReadiness: deviceReadiness,
            resolvedMode: capabilities.roomPlanMeshEligible
                ? .roomPlanMesh
                : nil,
            finalizedBackupPolicy: appSettings.storagePrivacy
                .finalizedBackupPolicy,
            taskProfile: taskProfile,
            importedTaskPlan: pendingTaskPlanImport?.plan,
            taskPlanImportError: pendingTaskPlanImportError,
            cameraPermission:
                CameraPermissionController.currentStatus(),
            interruptedDrafts:
                persistedInventory.recoverableDrafts
        )
    }

    /// #352: import an HTDT task plan on the setup screen, before any
    /// acquisition. The file is decoded+validated now so the operator
    /// sees failures immediately; the verbatim bytes bind to the
    /// working set only when scanning actually starts.
    func importTaskPlan(from url: URL) {
        guard state == .setup else {
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            pendingTaskPlanImport = try CaptureTaskPlanImport(
                data: data
            )
            pendingTaskPlanImportError = nil
        } catch {
            pendingTaskPlanImport = nil
            pendingTaskPlanImportError = String(localized: "The selected file is not a valid HTDT task plan")
        }
        refreshCaptureSetupPresentation()
    }

    /// Removes the imported plan so the setup returns to the generic
    /// task-profile intent (#352).
    func clearTaskPlan() {
        guard state == .setup else {
            return
        }
        pendingTaskPlanImport = nil
        pendingTaskPlanImportError = nil
        refreshCaptureSetupPresentation()
    }

    /// One-shot storage preflight for the setup screen using the same
    /// volume and thresholds as the runtime resource monitor (#212).
    /// An undetermined query stays `unknown`, never a fabricated pass.
    private static func currentStoragePreflight()
        -> CaptureStoragePreflight
    {
        guard let root = captureRootDirectory() else {
            return CaptureStoragePreflight(availableBytes: nil)
        }
        let policy = CaptureResourceMonitorPolicy()
        let available = try? root.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]
        ).volumeAvailableCapacityForImportantUsage
        return CaptureStoragePreflight(
            availableBytes: available.map { UInt64(max(0, $0)) },
            warningBytes: UInt64(policy.storageWarningBytes),
            criticalBytes: UInt64(policy.storageCriticalBytes)
        )
    }

    /// Device battery / power-mode snapshot (#272). On platforms
    /// without a battery the snapshot reports `unknown` so the UI can
    /// omit the section instead of fabricating readiness.
    private static func currentDeviceReadiness()
        -> CaptureDeviceReadiness
    {
        #if canImport(UIKit)
        let device = UIDevice.current
        // Monitoring is idempotent; the observer lifetime in
        // start/stopDeviceReadinessObserving owns the flag.
        device.isBatteryMonitoringEnabled = true
        let rawLevel = device.batteryLevel
        let rawState = device.batteryState
        let level: Double? =
            rawLevel >= 0 ? Double(rawLevel) : nil
        let state: CaptureDeviceReadiness.BatteryState
        switch rawState {
        case .unplugged:
            state = .unplugged
        case .charging:
            state = .charging
        case .full:
            state = .full
        case .unknown:
            state = .unknown
        @unknown default:
            state = .unknown
        }
        return CaptureDeviceReadiness(
            batteryLevel: level,
            batteryState: state,
            lowPowerModeEnabled:
                ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #else
        return CaptureDeviceReadiness(
            batteryLevel: nil,
            batteryState: .unknown,
            lowPowerModeEnabled:
                ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #endif
    }

    /// Battery/Low-Power observation while setup or scanning is live
    /// (#272). Runtime changes refresh the published snapshot and,
    /// during a scan, surface a non-blocking advisory before the
    /// battery reaches a critical state.
    private func startDeviceReadinessObserving() {
        guard !deviceReadinessObserving else {
            return
        }
        deviceReadinessObserving = true
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
        ]
        for name in names {
            deviceReadinessObservers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.deviceReadinessDidChange()
                    }
                }
            )
        }
        #endif
    }

    private func stopDeviceReadinessObserving() {
        guard deviceReadinessObserving else {
            return
        }
        deviceReadinessObserving = false
        for observer in deviceReadinessObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        deviceReadinessObservers = []
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    private func deviceReadinessDidChange() {
        let readiness = Self.currentDeviceReadiness()
        deviceReadiness = readiness
        if state == .setup {
            refreshCaptureSetupPresentation()
        }
        guard state == .scanning else {
            return
        }
        // Advisory-only runtime surface (#272): warn before the battery
        // is critical; never a canonical quality rule and never a
        // failure path.
        if readiness.hasLowBattery {
            workingSetStatus = String(localized: "Battery is low; consider ending soon or connecting power")
        }
    }

    /// Scoped display keep-awake for active capture (#272). The
    /// override is engaged only while `.scanning`; `transition()` calls
    /// this on every state change, so any End/failure/reset path
    /// releases it automatically.
    private func updateDisplayIdleTimer() {
        #if canImport(UIKit)
        let shouldSuspend = state == .scanning
        guard shouldSuspend != displayIdleTimerSuspended else {
            return
        }
        displayIdleTimerSuspended = shouldSuspend
        UIApplication.shared.isIdleTimerDisabled = shouldSuspend
        #endif
    }

    func setScanMovementCapability(
        _ capability: ScanMovementCapability
    ) {
        guard state == .scanning else {
            return
        }

        motionGuidanceTracker.setMovementCapability(capability)
        motionGuidance = motionGuidanceTracker.guidance()
        scanGuidanceProgress = motionGuidanceTracker.progress(
            coverage: scanCoverage,
            spatialCoverage: spatialCoverage
        )
    }

    func captureEvidenceFrame() {
        guard state == .scanning,
              !isEndingScan,
              !isCapturingEvidenceFrame,
              let store = workingSetStore
        else {
            return
        }

        isCapturingEvidenceFrame = true
        let generation = captureGeneration
        // Synchronous MainActor boundary (#177): the platform split API
        // retains only the frame buffers plus pose/intrinsics metadata
        // here; binary packing, SHA-256 and HEIC preview generation are
        // deferred to the async materialize boundary inside the
        // persistence task so they run off MainActor. CONTRACT:
        // CapturedFrameSnapshot is the sibling platform agent's
        // retained-snapshot type name; if it lands under a different
        // name this annotation is the single host-side rename site.
        let frameSnapshot: CapturedFrameSnapshot

        do {
            frameSnapshot =
                try sessionController.snapshotFrameEvidenceCapture(
                    depthSelection: .discrete
                )
        } catch PlatformCaptureError.currentFrameUnavailable {
            isCapturingEvidenceFrame = false
            workingSetStatus = String(localized: "Evidence frame was not captured because the current AR frame is temporarily unavailable; this scan is still active")
            endScanGuidance = String(localized: "Hold the phone steady on previously scanned features until tracking is normal, then retry Evidence Save or continue scanning.")
            return
        } catch {
            isCapturingEvidenceFrame = false
            workingSetStatus =
                String(localized: "Evidence frame could not be prepared; this scan is still active")
                + " ["
                + Self.persistenceDiagnostic(error)
                + "]"
            return
        }

        // Advisory usability check on the same AR frame (#274): manual
        // Save always retains, but a suspect/unusable result is
        // recorded and surfaced so the operator can retake.
        let frameUsability =
            sessionController.currentFrameUsabilityAssessment()

        // Keep a handle on the persistence task so End can claim its
        // boundary atomically and drain this save before it samples the
        // working set (#179). While End holds isEndingScan the save's
        // commit still lands (its bytes are canonically before the End
        // snapshot) but its UI continuation is suppressed so a stale
        // continuation cannot overwrite End/Review status.
        evidenceFrameSaveTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isCapturingEvidenceFrame = false
                self.evidenceFrameSaveTask = nil
            }
            guard self.captureGeneration == generation,
                  self.state == .scanning
            else {
                return
            }

            // Async boundary (#177): binary packing, SHA-256 and the
            // derived HEIC preview run off MainActor inside the
            // platform adapter's materialize step. The retained
            // snapshot keeps the same-frame pixel/depth/pose
            // association; a preview failure is non-blocking by
            // contract. CONTRACT: sibling platform agent exposes
            // ARFrameArtifactAdapter.materialize(_:) -> CapturedFrameArtifacts.
            let artifacts: CapturedFrameArtifacts
            do {
                artifacts = try await ARFrameArtifactAdapter
                    .materialize(frameSnapshot)
            } catch {
                guard !self.isEndingScan else {
                    return
                }
                self.workingSetStatus =
                    String(localized: "Evidence frame could not be prepared; this scan is still active")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                return
            }

            guard self.captureGeneration == generation,
                  self.state == .scanning
            else {
                return
            }

            let package: FrameEvidencePackage
            do {
                package = try FrameEvidencePackageBuilder.build(
                    descriptor: artifacts.descriptor,
                    pixelPayload: artifacts.pixelPayload,
                    depthPayload: artifacts.depthPayload,
                    confidencePayload: artifacts.confidencePayload,
                    previewPayload: artifacts.previewPayload
                )
            } catch {
                guard !self.isEndingScan else {
                    return
                }
                self.workingSetStatus =
                    String(localized: "Evidence frame package could not be built; this scan is still active")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                return
            }

            do {
                try await store.persistFramePackage(package)
            } catch {
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }

                let diagnostic =
                    Self.persistenceDiagnostic(error)

                if error is CaptureWorkingSetError {
                    // A capture-authority conflict is terminal even when
                    // End is draining this save: End cannot proceed on a
                    // corrupted working set either.
                    self.workingSetStatus =
                        String(localized: "Evidence-frame persistence hit a capture-authority conflict and cannot continue safely")
                        + " ["
                        + diagnostic
                        + "]"
                    self.fail(.persistenceFailure)
                    return
                }

                // The partial write must be fully resolved before End
                // may continue; never leave undeclared bytes behind.
                do {
                    try await store.discardUncommittedFramePackage(
                        package
                    )
                } catch {
                    self.workingSetStatus =
                        String(localized: "Evidence-frame persistence failed and partial canonical files could not be rolled back safely")
                        + " ["
                        + diagnostic
                        + "]"
                    self.fail(.persistenceFailure)
                    return
                }

                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }

                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Recoverable manual evidence-frame persistence failure: "
                            + diagnostic
                    )
                )
                guard self.captureGeneration == generation,
                      self.state == .scanning,
                      !self.isEndingScan
                else {
                    return
                }
                self.workingSetStatus =
                    String(localized: "Evidence frame was not committed; this scan is still active")
                    + " ["
                    + diagnostic
                    + "]"
                self.endScanGuidance = String(localized: "Continue scanning or retry Evidence Save. End remains available after the required end evidence can be persisted.")
                return
            }

            if let usability = frameUsability,
               usability.status != .usable
            {
                self.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .frameUsability,
                        sessionTimestampSeconds:
                            frameSnapshot.sessionTimestampSeconds,
                        detail:
                            "status=\(usability.status.rawValue)"
                            + " frame=\(frameSnapshot.frameID) issues="
                            + usability.issues
                                .map(\.rawValue)
                                .joined(separator: ",")
                    )
                )
            }

            self.markEvidenceRetention(
                "path:" + package.descriptorPath,
                .manualScan
            )

            let snapshot = await store.snapshot()
            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  !self.isEndingScan
            else {
                return
            }
            self.scanEvidenceFrameCount =
                snapshot.evidenceFrameCount
            self.scanDepthEvidenceCount =
                snapshot.depthEvidenceCount
            self.updateLiveEndScanGuidance()
            if self.guidanceCuesEnabled {
                self.playCueIfAdmitted(
                    .evidenceSaved,
                    timestampSeconds:
                        frameSnapshot.sessionTimestampSeconds
                )
            }
            var savedStatus = captureCountPhrase(
                snapshot.evidenceFrameCount,
                singular: String(
                    localized: "Scanning; %lld evidence frame persisted"
                ),
                plural: String(
                    localized: "Scanning; %lld evidence frames persisted"
                )
            )
            if let usability = frameUsability,
               usability.status != .usable
            {
                savedStatus += String(localized: " — the saved frame may be unusable (dark, blurred or overexposed); consider a retake")
            }
            self.workingSetStatus = savedStatus
        }
    }

    // MARK: - Operator-targeted object pass (#250)

    /// Begin a "Scan this object" orbit pass. Target authority comes
    /// from a center-of-view raycast against live mesh/depth evidence —
    /// a bounded anchor the operator aimed at, never a fabricated
    /// segmentation.
    func beginTargetScan() {
        guard state == .scanning,
              !isEndingScan,
              targetScanTracker == nil
        else {
            return
        }
        do {
            let placement = try sessionController
                .snapshotCenterRaycastPlacement()
            targetScanTracker = TargetedObjectScanTracker(
                target: ScanTargetAnchor(
                    x: Double(placement.positionWorld.x),
                    y: Double(placement.positionWorld.y),
                    z: Double(placement.positionWorld.z),
                    radiusMeters: 0.75
                )
            )
            // #250: which evidence class supplied the aim anchor —
            // retained in the accept note's provenance.
            targetScanAnchorSource =
                placement.raycastProvenance?.target.rawValue
            let initialDistance = spatialCoverage
                .currentCameraPosition.map { camera in
                    hypot(
                        Double(camera.x)
                            - Double(placement.positionWorld.x),
                        Double(camera.z)
                            - Double(placement.positionWorld.z)
                    )
                }
            targetScanStatus = TargetScanStatus(
                angularCoverageFraction: 0,
                observedBucketCount: 0,
                totalBucketCount: targetScanTracker?.bucketCount ?? 8,
                isComplete: false,
                expired: false,
                outOfRange: false,
                guidance: .hold,
                distanceToTargetMeters: initialDistance
            )
            workingSetStatus = String(localized: "Object pass started; keep the aimed object centered and move around it")
        } catch {
            workingSetStatus = String(localized: "No surface was detected at the aim point; aim at the object and try again")
        }
    }

    /// Discard the current pass' observations and start the bounded
    /// orbit again on the same anchor (Retake).
    func retakeTargetScan() {
        guard let anchor = targetScanTracker?.target else {
            return
        }
        targetScanTracker = TargetedObjectScanTracker(target: anchor)
        targetScanStatus = nil
    }

    /// Complete the pass: record advisory provenance and leave target
    /// mode. Partial progress is kept honest in the note detail.
    func acceptTargetScan() {
        guard let tracker = targetScanTracker else {
            return
        }
        let status = targetScanStatus
        let anchorSource = targetScanAnchorSource
        endTargetScan()
        if let status {
            let detail =
                "buckets=\(status.observedBucketCount)/"
                + "\(status.totalBucketCount)"
                + " expired=\(status.expired)"
                + " anchor_x=\(tracker.target.x)"
                + " anchor_y=\(tracker.target.y)"
                + " anchor_z=\(tracker.target.z)"
                + " radius_m=\(tracker.target.radiusMeters)"
                + " anchor_source=\(anchorSource ?? "none")"
            recordAdvisoryNote(
                CaptureAdvisoryNote(
                    kind: .targetScanPass,
                    sessionTimestampSeconds:
                        latestScanTimestampSeconds ?? 0,
                    detail: detail
                )
            )
        }
        workingSetStatus = String(localized: "Object pass recorded")
        if guidanceCuesEnabled,
           let timestamp = latestScanTimestampSeconds
        {
            playCueIfAdmitted(
                .targetObserved,
                timestampSeconds: timestamp
            )
        }
    }

    /// Leave target mode without recording a completed pass.
    func cancelTargetScan() {
        endTargetScan()
    }

    private func endTargetScan() {
        targetScanTracker = nil
        targetScanStatus = nil
        targetScanAnchorSource = nil
    }

    // MARK: - Operator-declared regions (#257)

    /// Mark a weak/unknown coverage cell intentionally unresolved. The
    /// cell keeps its classification (never becomes "observed");
    /// guidance stops steering toward it and the declaration persists
    /// as advisory provenance through Review/finalization.
    func declareOperatorRegion(
        _ key: SpatialCoverageCellKey,
        reason: DeclaredRegionReason
    ) {
        guard state == .scanning else {
            return
        }
        let timestamp = latestScanTimestampSeconds ?? 0
        operatorRegionDeclarations.declare(
            DeclaredCoverageRegion(
                key: key,
                reason: reason,
                declaredAtSessionSeconds: timestamp
            )
        )
        declaredRegionList = operatorRegionDeclarations.regions
        motionGuidanceTracker.setDeclaredRegionKeys(
            operatorRegionDeclarations.declaredKeys
        )
        motionGuidance = motionGuidanceTracker.guidance()
        scanGuidanceProgress = motionGuidanceTracker.progress(
            coverage: scanCoverage,
            spatialCoverage: spatialCoverage
        )
        recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .declaredRegion,
                sessionTimestampSeconds: timestamp,
                detail:
                    "cell_x=\(key.x) cell_z=\(key.z) reason=\(reason.rawValue)"
            )
        )
    }

    /// Declare the nearest still-unresolved (weak/unknown) coverage
    /// cell to the current camera position. The bounded spatial scope
    /// comes from the coverage grid, not free text (#257).
    func declareNearestUnresolvedRegion(
        reason: DeclaredRegionReason
    ) {
        guard state == .scanning else {
            return
        }
        guard let camera = spatialCoverage.currentCameraPosition else {
            workingSetStatus = String(localized: "No camera position yet; move a little and try again")
            return
        }
        let cellSize = spatialCoverage.cellSizeMeters
        let declaredKeys = operatorRegionDeclarations.declaredKeys
        let candidate = spatialCoverage.regions
            .filter {
                $0.classification != .observed
                    && !declaredKeys.contains($0.key)
            }
            .min { a, b in
                let ax =
                    (Double(a.key.x) + 0.5) * cellSize - camera.x
                let az =
                    (Double(a.key.z) + 0.5) * cellSize - camera.z
                let bx =
                    (Double(b.key.x) + 0.5) * cellSize - camera.x
                let bz =
                    (Double(b.key.z) + 0.5) * cellSize - camera.z
                return ax * ax + az * az < bx * bx + bz * bz
            }
        guard let candidate else {
            workingSetStatus = String(localized: "No unresolved coverage region found near the camera")
            return
        }
        declareOperatorRegion(candidate.key, reason: reason)
        workingSetStatus = String(localized: "Region marked; it stays unresolved but guidance will not request it")
    }

    /// Reverse a declaration before finalization; the region returns to
    /// ordinary guidance eligibility.
    func revokeOperatorRegion(_ key: SpatialCoverageCellKey) {
        guard state == .scanning,
              operatorRegionDeclarations.revoke(key: key)
        else {
            return
        }
        declaredRegionList = operatorRegionDeclarations.regions
        motionGuidanceTracker.setDeclaredRegionKeys(
            operatorRegionDeclarations.declaredKeys
        )
        recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .revokedRegion,
                sessionTimestampSeconds:
                    latestScanTimestampSeconds ?? 0,
                detail: "cell_x=\(key.x) cell_z=\(key.z)"
            )
        )
    }

    // MARK: - Return-to-start consistency check (#273)

    /// Arm/disarm the optional loop-closure check. Arming records the
    /// intent; the assessment stays advisory and unavailable states
    /// report `.unavailable`, never a fabricated pass. Disarming keeps
    /// the last assessment so the end-scan note retains what the
    /// operator answered (#273).
    func setLoopClosureCheckActive(_ active: Bool) {
        if loopClosureCheckActive, !active {
            loopClosureLastAssessment =
                loopClosureAssessment ?? loopClosureLastAssessment
        }
        loopClosureCheckActive = active
        if active {
            updateLoopClosureAssessment()
        } else {
            loopClosureAssessment = nil
        }
    }

    /// Record the operator's response to the armed check (#273) as
    /// advisory provenance: "reobserve" clears the displayed
    /// assessment and keeps the check armed for a fresh walk-back;
    /// "accepted" / "continued" disarm the check. The response joins
    /// the end-scan note next to the verdict + residuals — the check
    /// never touches coordinates itself.
    func recordLoopClosureOutcome(_ response: String) {
        guard loopClosureCheckActive else {
            return
        }
        loopClosureOutcome = response
        loopClosureLastAssessment =
            loopClosureAssessment ?? loopClosureLastAssessment
        switch response {
        case "reobserve":
            loopClosureAssessment = nil
        case "accepted", "continued":
            loopClosureCheckActive = false
            loopClosureAssessment = nil
        default:
            break
        }
    }

    private func updateLoopClosureAssessment() {
        let distance = spatialCoverage.currentCameraPosition.map {
            hypot($0.x, $0.z)
        }
        let heading = spatialCoverage.currentRelativeHeadingRadians
            .map { abs($0) }
        loopClosureAssessment = loopClosurePolicy.assess(
            distanceToStartMeters: distance,
            headingResidualRadians: heading,
            referenceAvailable:
                spatialCoverage.referenceOriginWorld != nil,
            trackingState: spatialCoverage.latestTrackingState
        )
    }

    // MARK: - Non-visual guidance cues (#252)

    func setGuidanceCuesEnabled(_ enabled: Bool) {
        guidanceCuesEnabled = enabled
        if !enabled {
            scanGuidanceCuePolicy.reset()
        }
        // The toggle is a presentation preference (#338): persist it
        // so the choice survives relaunch; it never enters capture
        // authority.
        var copy = appSettings
        copy.presentation.guidanceCuesEnabled = enabled
        updateAppSettings(copy)
    }

    // MARK: - App-local settings (#338)

    /// Persists a new settings document and applies its side effects.
    /// Presentation choices take effect at once; the finalized backup
    /// policy is re-applied to `finalized/`/`exports/` and every
    /// artifact already inside them so existing captures get the
    /// operator's current policy — never a reinterpretation of their
    /// recorded content.
    func updateAppSettings(_ newSettings: CaptureAppSettings) {
        let previousPolicy =
            appSettings.storagePrivacy.finalizedBackupPolicy
        appSettings = newSettings
        guidanceCuesEnabled =
            newSettings.presentation.guidanceCuesEnabled

        if let appSettingsStore {
            do {
                try appSettingsStore.save(newSettings)
            } catch {
                workingSetStatus = String(localized: "Device settings could not be saved")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }

        if newSettings.storagePrivacy.finalizedBackupPolicy
            != previousPolicy,
           let captureRoot = Self.captureRootDirectory()
        {
            let failures = CaptureStoragePolicy
                .applyFinalizedBackupPolicy(
                    captureRoot: captureRoot,
                    policy: newSettings.storagePrivacy
                        .finalizedBackupPolicy
                )
            if !failures.isEmpty {
                workingSetStatus = String(localized: "The backup policy could not be applied to every stored capture")
                    + " ["
                    + failures.joined(separator: "; ")
                    + "]"
            }
        }

        if state == .setup {
            refreshCaptureSetupPresentation()
        }
    }

    /// Clears the durable equipment-catalog cache (#338): the import
    /// mirror is removed and the reference context resets for the
    /// next import. Committed captures keep the exact equipment
    /// tuples they recorded — the cache is convenience, never
    /// authority.
    func clearEquipmentCatalogCache() {
        if let equipmentCatalogStore {
            for stored in equipmentCatalogStore.list() {
                try? equipmentCatalogStore.remove(
                    contentKey: stored.contentKey
                )
            }
            if let legacyFileURL = equipmentCatalogStore.legacyFileURL {
                try? FileManager.default.removeItem(at: legacyFileURL)
            }
        }
        equipmentCatalog = nil
        equipmentCatalogLibrary = []
    }

    /// Applies the stored backup policy to a share archive (#305);
    /// export archives are app-owned transport output and follow the
    /// same policy as finalized data. A flag failure is surfaced,
    /// never fatal to the archive already produced.
    private func applyExportArchiveBackupPolicy(to archive: URL) {
        do {
            try CaptureStoragePolicy.applyExportArchivePolicy(
                archiveURL: archive,
                policy: appSettings.storagePrivacy
                    .finalizedBackupPolicy
            )
        } catch {
            workingSetStatus = String(localized: "The backup policy could not be applied to the export archive")
                + " ["
                + Self.persistenceDiagnostic(error)
                + "]"
        }
    }

    /// Emit one admitted cue: haptic + VoiceOver announcement. Haptics
    /// are skipped under Reduce Motion; announcements only reach a
    /// VoiceOver user, so they stay unconditional.
    private func playGuidanceCue(_ cue: ScanGuidanceCue) {
        #if canImport(UIKit)
        guard !UIAccessibility.isReduceMotionEnabled else {
            UIAccessibility.post(
                notification: .announcement,
                argument: cueAnnouncement(cue)
            )
            return
        }
        switch cue {
        case .trackingLost:
            UINotificationFeedbackGenerator()
                .notificationOccurred(.error)
        case .trackingRecovered, .guidanceComplete:
            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)
        case .endAvailable, .targetObserved:
            UIImpactFeedbackGenerator(style: .medium)
                .impactOccurred()
        case .evidenceSaved, .holdSteady, .revisitFlagSaved:
            UIImpactFeedbackGenerator(style: .light)
                .impactOccurred()
        case .moveLeft, .moveRight, .moveForward, .moveBack,
             .orbitLeft, .orbitRight:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: cueAnnouncement(cue)
        )
        #endif
    }

    private func playCueIfAdmitted(
        _ cue: ScanGuidanceCue,
        timestampSeconds: Double
    ) {
        let emitted: ScanGuidanceCue?
        switch cue {
        case .evidenceSaved:
            emitted = scanGuidanceCuePolicy
                .evidenceSaved(timestampSeconds: timestampSeconds)
        case .targetObserved:
            emitted = scanGuidanceCuePolicy
                .targetObserved(timestampSeconds: timestampSeconds)
        case .revisitFlagSaved:
            emitted = scanGuidanceCuePolicy
                .revisitFlagSaved(timestampSeconds: timestampSeconds)
        default:
            emitted = nil
        }
        if let emitted {
            playGuidanceCue(emitted)
        }
    }

    private func cueAnnouncement(_ cue: ScanGuidanceCue) -> String {
        switch cue {
        case .trackingLost:
            return String(localized: "Tracking lost")
        case .trackingRecovered:
            return String(localized: "Tracking recovered")
        case .moveLeft:
            return String(localized: "Move left")
        case .moveRight:
            return String(localized: "Move right")
        case .moveForward:
            return String(localized: "Move forward")
        case .moveBack:
            return String(localized: "Move back")
        case .holdSteady:
            return String(localized: "Hold steady")
        case .orbitLeft:
            return String(localized: "Orbit left")
        case .orbitRight:
            return String(localized: "Orbit right")
        case .targetObserved:
            return String(localized: "Target area observed")
        case .guidanceComplete:
            return String(localized: "Scan guidance complete")
        case .endAvailable:
            return String(localized: "Ending the scan is now reasonable")
        case .evidenceSaved:
            return String(localized: "Evidence frame saved")
        case .revisitFlagSaved:
            return String(localized: "Review flag saved")
        }
    }

    // MARK: - Automatic evidence keyframes (#216)

    /// Offer the current live sample to the bounded keyframe policy on
    /// the slow tick. Retention is decided only after frame-usability
    /// and all budget checks pass; a skipped or failed candidate costs
    /// the scan nothing.
    private func considerAutomaticKeyframe(
        _ sample: ScanCoverageSample
    ) {
        guard state == .scanning,
              !isEndingScan,
              automaticFrameSaveTask == nil,
              workingSetStore != nil
        else {
            return
        }

        // The estimator tracks its own byte bound; this persisted-byte
        // total is the authoritative backstop so a materialized overrun
        // also stops the selector (#216).
        guard automaticKeyframePersistedBytes
                <= automaticKeyframeTracker.configuration
                    .maximumRetainedBytes
        else {
            return
        }

        let usability =
            sessionController.currentFrameUsabilityAssessment()
        let perFrameEstimate = max(
            automaticEvidenceFrameCount > 0
                ? automaticKeyframePersistedBytes
                    / automaticEvidenceFrameCount
                : 0,
            8 * 1024 * 1024
        )
        let candidate = AutomaticKeyframeSample(
            timestampSeconds: sample.sessionTimestampSeconds,
            cameraX: sample.cameraPosition?.x,
            cameraZ: sample.cameraPosition?.z,
            yawRadians: sample.yawRadians,
            trackingState: sample.trackingState,
            hasSceneDepth: sample.hasSceneDepth,
            usabilityStatus: usability?.status,
            estimatedBytes: perFrameEstimate
        )
        guard automaticKeyframeTracker.evaluate(candidate)
                == .retain
        else {
            return
        }

        captureAutomaticEvidenceFrame(
            candidate,
            usability: usability
        )
    }

    /// Snapshot → materialize → persist an automatic keyframe. Runs off
    /// the manual save path's flags; End drains this task alongside the
    /// manual save so the End evidence boundary stays atomic (#179).
    private func captureAutomaticEvidenceFrame(
        _ sample: AutomaticKeyframeSample,
        usability: FrameUsabilityAssessment?
    ) {
        guard let store = workingSetStore else {
            return
        }

        let generation = captureGeneration
        let frameSnapshot: CapturedFrameSnapshot
        do {
            frameSnapshot =
                try sessionController.snapshotFrameEvidenceCapture(
                    depthSelection: .discrete
                )
        } catch {
            return
        }

        automaticFrameSaveTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.automaticFrameSaveTask = nil
            }
            await self.persistAutomaticKeyframe(
                frameSnapshot: frameSnapshot,
                sample: sample,
                usability: usability,
                store: store,
                generation: generation
            )
        }
    }

    private func persistAutomaticKeyframe(
        frameSnapshot: CapturedFrameSnapshot,
        sample: AutomaticKeyframeSample,
        usability: FrameUsabilityAssessment?,
        store: CaptureWorkingSetStore,
        generation: UUID
    ) async {
            let artifacts: CapturedFrameArtifacts
            let package: FrameEvidencePackage
            do {
                artifacts = try await ARFrameArtifactAdapter
                    .materialize(frameSnapshot)
                package = try FrameEvidencePackageBuilder.build(
                    descriptor: artifacts.descriptor,
                    pixelPayload: artifacts.pixelPayload,
                    depthPayload: artifacts.depthPayload,
                    confidencePayload: artifacts.confidencePayload,
                    previewPayload: artifacts.previewPayload
                )
            } catch {
                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "recoverable automatic keyframe failure: "
                            + Self.persistenceDiagnostic(error)
                    )
                )
                return
            }
            do {
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }
                try await store.persistFramePackage(package)

                let pixelBytes = artifacts.pixelPayload.count
                let depthBytes = artifacts.depthPayload?.count ?? 0
                let confidenceBytes = artifacts.confidencePayload?.count ?? 0
                let previewBytes = artifacts.previewPayload?.count ?? 0
                let persistedBytes =
                    pixelBytes + depthBytes + confidenceBytes + previewBytes
                self.automaticKeyframePersistedBytes += persistedBytes
                self.automaticKeyframeTracker.markRetained(
                    sample,
                    actualBytes: persistedBytes
                )
                self.automaticEvidenceFrameCount += 1

                var detail =
                    "policy=\(self.automaticKeyframeTracker.policyVersion)"
                    + " frame=\(frameSnapshot.frameID)"
                if let usability,
                   usability.status != .usable
                {
                    detail +=
                        " usability=\(usability.status.rawValue)"
                }
                self.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .automaticKeyframe,
                        sessionTimestampSeconds:
                            sample.timestampSeconds,
                        detail: detail
                    )
                )

                if self.guidanceCuesEnabled {
                    self.playCueIfAdmitted(
                        .evidenceSaved,
                        timestampSeconds:
                            sample.timestampSeconds
                    )
                }

                let snapshot = await store.snapshot()
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }
                self.scanEvidenceFrameCount =
                    snapshot.evidenceFrameCount
                self.scanDepthEvidenceCount =
                    snapshot.depthEvidenceCount
                self.updateLiveEndScanGuidance()
            } catch {
                // Roll back any partial write so no undeclared bytes
                // remain; rollback failure escalates to a host failure
                // because the working set can no longer be trusted.
                do {
                    try await store.discardUncommittedFramePackage(
                        package
                    )
                } catch {
                    self.fail(.persistenceFailure)
                    return
                }
                // Selection/persistence failure is advisory: the scan
                // continues, the budget is unconsumed (markRetained was
                // never reached), and the event is recorded for Review.
                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "recoverable automatic keyframe failure: "
                            + Self.persistenceDiagnostic(error)
                    )
                )
            }
    }

    /// Counts this RoomPlan `run()` as a new scan segment and, once
    /// the revision scans past its first segment, records provenance
    /// that the next accepted room model is a rebuild covering only
    /// the final segment — mesh anchors and evidence frames still
    /// accumulate across every segment.
    private func noteRoomPlanScanSegment() {
        roomPlanScanSegmentOrdinal += 1
        guard roomPlanScanSegmentOrdinal > 1 else {
            return
        }
        recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .roomPlanRescan,
                sessionTimestampSeconds:
                    latestScanTimestampSeconds ?? 0,
                detail:
                    "segment=\(roomPlanScanSegmentOrdinal)"
                    + " accepted_model_covers_final_segment_only"
            )
        )
    }

    /// Persist an advisory note when a store is live; silent during
    /// setup/review when none exists (the note channel only exists for
    /// a working capture).
    private func recordAdvisoryNote(_ note: CaptureAdvisoryNote) {
        guard let store = workingSetStore else {
            return
        }
        Task {
            try? await store.recordAdvisoryNote(note)
        }
    }

    func beginReview() {
        guard state == .scanning, !isEndingScan else {
            return
        }

        let generation = captureGeneration
        isEndingScan = true

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            // The End boundary must own a stable evidence set (#179):
            // drain an in-flight manual evidence save so its commit or
            // rollback is fully resolved before End snapshots the
            // working set. isEndingScan already blocks a new save from
            // starting and suppresses the drained save's UI
            // continuation, so the drained commit is deterministically
            // inside the End boundary.
            if let pendingSave = self.evidenceFrameSaveTask {
                await pendingSave.value
            }
            // The automatic selector's in-flight write lands inside the
            // same boundary as a manual save (#216, #179).
            if let pendingAuto = self.automaticFrameSaveTask {
                await pendingAuto.value
            }

            // #273: the return-to-start check, when the operator armed
            // it, leaves its verdict as advisory provenance. The check
            // never warps coordinates; an un-run or unavailable check
            // records nothing rather than implying a pass. An answered
            // check keeps the last assessment after disarm so the note
            // retains verdict + residual + response together.
            if let assessment = self.loopClosureAssessment
                ?? self.loopClosureLastAssessment
            {
                var detail =
                    "verdict=\(assessment.verdict.rawValue)"
                if let residual = assessment.residualMeters {
                    detail += " residual_m=\(residual)"
                }
                if let heading = assessment.headingResidualRadians {
                    detail += " heading_rad=\(heading)"
                }
                detail += " reference="
                    + (self.spatialCoverage
                        .referenceOriginWorld != nil
                        ? "scan_start_pose"
                        : "unavailable")
                if let response = self.loopClosureOutcome {
                    detail += " response=\(response)"
                }
                self.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .loopClosureCheck,
                        sessionTimestampSeconds:
                            self.latestScanTimestampSeconds ?? 0,
                        detail: detail
                    )
                )
            }
            self.loopClosureCheckActive = false
            self.loopClosureAssessment = nil
            self.loopClosureLastAssessment = nil
            self.loopClosureOutcome = nil
            self.endTargetScan()

            guard let prepared =
                    await self.prepareEndScan(
                        generation: generation
                    ),
                  self.captureGeneration == generation,
                  self.state == .scanning,
                  self.isEndingScan
            else {
                if self.captureGeneration == generation {
                    self.isEndingScan = false
                }
                return
            }

            self.endScanGuidance = nil
            await self.endScanForReview(
                prepared,
                generation: generation
            )
        }
    }

    func continueScanningFromReview() {
        // #236: saved annotation authority no longer blocks Continue
        // scanning. The committed annotation/measurement collections
        // and evidence frames survive the End-boundary rollback, so
        // the operator can keep scanning after saving annotations while
        // the same AR coordinate authority stays valid. After the next
        // End, `committedSpatialEvidenceIssues` surfaces any annotation
        // link left dangling by the replaced mesh/RoomPlan authority
        // instead of silently dropping it.
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive,
              acceptedRoomPlanRawSHA256 != nil,
              let store = workingSetStore
        else {
            return
        }

        reviewOperationInFlight = true
        let generation = captureGeneration
        let removeOwnedMesh = acceptedEndMeshWasPersisted
        workingSetStatus = String(localized: "Reopening this capture for additional scanning")

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            do {
                try self.sessionController.startRoomPlan()
                self.noteRoomPlanScanSegment()
            } catch {
                self.reviewOperationInFlight = false
                self.workingSetStatus =
                    String(localized: "RoomPlan could not resume additional scanning. The accepted Review evidence was kept intact; you can retry Continue scanning or finalize this capture.")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                return
            }

            do {
                try await store.rollbackAcceptedEndTransaction(
                    removeOwnedMesh: removeOwnedMesh
                )
            } catch {
                self.workingSetStatus =
                    String(localized: "RoomPlan restarted, but the accepted Review boundary could not be rolled back safely")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                self.fail(.persistenceFailure)
                return
            }

            guard self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            do {
                try self.transition(.resumeScanning)
            } catch {
                self.fail(.unknown)
                return
            }

            self.reviewOperationInFlight = false
            self.acceptedRoomPlanRawSHA256 = nil
            self.acceptedEndMeshWasPersisted = false
            self.qualityReport = nil
            self.validationReport = nil
            self.pendingEndAttempt = nil
            self.roomPlanCompletionInFlight = false
            self.isEndingScan = false
            self.endScanPreflightBlocked = false
            self.endScanGuidance = String(localized: "Continue scanning the weak or missing areas, then press End again. Previously saved frame/depth evidence is retained.")
            self.startScanCoverageSampling(
                generation: generation,
                resetTrackers: false
            )
            self.workingSetStatus =
                String(localized: "Scanning resumed in the same AR coordinate space")
        }
    }

    func beginAnnotation() {
        // Annotation editing is spatial continuation authority: once a
        // post-End resource/lifecycle condition sealed it (#112), the
        // accepted Review remains finalizable but live spatial capture
        // is unavailable. The workspace still opens — under the seal
        // it renders in non-spatial mode (raycast/orientation/scanning
        // hidden by the nil live space + torn-down preview) so label,
        // role, equipment, scalar, and required-task corrections stay
        // reachable instead of leaving a dead end.
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              let store = workingSetStore
        else {
            return
        }

        if annotationAuthorityCommitted {
            // Pre-finalization correction (#163): reload the canonical
            // annotation/measurement collections already committed
            // inside this working revision and reopen the editor seeded
            // with them. The immutable-revision contract only begins at
            // finalization; the Review working set is still correctable.
            reviewOperationInFlight = true
            let generation = captureGeneration
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let rootDirectory = await store.rootDirectory
                let loaded = await Task.detached(
                    priority: .userInitiated
                ) { () -> (AnnotationWorkspaceSeed, Data?)? in
                    try? Self.committedAnnotationSeed(
                        rootDirectory: rootDirectory
                    )
                }.value

                guard self.captureGeneration == generation,
                      self.state == .reviewing
                else {
                    return
                }
                self.reviewOperationInFlight = false

                guard let loaded else {
                    self.workingSetStatus = String(localized: "The saved annotation authority could not be reloaded for editing; the committed files are unchanged")
                    return
                }

                self.committedIdentityDocData = loaded.1
                self.annotationRevisionSeed = loaded.0
                self.annotationEditIsRevision = true
                do {
                    try self.transition(.beginAnnotation)
                    self.workingSetStatus = String(localized: "Correcting the saved annotations and measurements")
                } catch {
                    self.fail(.unknown)
                }
            }
            return
        }

        committedIdentityDocData = nil

        // Non-canonical draft restore (#266): a draft bound to this
        // exact working revision + coordinate space survived an
        // interruption; seed the workspace with it (marked unsaved) so
        // long authoring sessions are not lost. Mismatched or stale
        // drafts are refused by the store's binding check.
        var draftSeed: AnnotationWorkspaceSeed?
        if let revisionID = annotationDraftRevisionID,
           let spaceID = annotationWorkspaceCoordinateSpaceID
        {
            let draft = annotationDraftStore?.load(
                revisionID: revisionID,
                coordinateSpaceID: spaceID
            )
            if let draft {
                draftSeed = AnnotationWorkspaceSeed(
                    annotations: draft.annotations,
                    measurements: draft.measurements,
                    equipmentIdentityRecords:
                        draft.equipmentIdentityRecords,
                    speakerLayoutPlan: draft.speakerLayoutPlan,
                    isRestoredDraft: true,
                    authorities: draft.authorities
                        ?? draft.theaterAuthorities,
                    fieldAuthority: draft.fieldAuthority
                        ?? FieldAuthorityWorkspace()
                )
            }
        }
        annotationRevisionSeed = draftSeed
        annotationEditIsRevision = false
        do {
            try transition(.beginAnnotation)
            workingSetStatus = draftSeed == nil
                ? String(localized: "Editing annotations and measurements")
                : String(localized: "Editing annotations and measurements — unsaved draft restored")
        } catch {
            fail(.unknown)
        }
    }

    /// Reads the canonical annotation/measurement collections — plus
    /// the committed equipment-identity attestations (#239) — already
    /// inside the working revision so a pre-finalization edit starts
    /// from the persisted authority instead of blank state. Returns
    /// the raw identity-document bytes alongside so a later commit with
    /// no records can discard byte-identical. Pure reads of app-owned
    /// canonical files; all writes still pass through the store.
    nonisolated private static func committedAnnotationSeed(
        rootDirectory: URL
    ) throws -> (AnnotationWorkspaceSeed, Data?) {
        func loadCollection<C: Decodable>(
            _ type: C.Type,
            at path: String
        ) throws -> C? {
            let url = rootDirectory.appendingPathComponent(
                path,
                isDirectory: false
            )
            guard FileManager.default.fileExists(
                atPath: url.path
            ) else {
                return nil
            }
            return try JSONDecoder().decode(
                C.self,
                from: Data(contentsOf: url)
            )
        }

        let annotations = try loadCollection(
            CaptureAnnotationCollection.self,
            at: AnnotationEvidencePackage.path
        )?.entities ?? []
        let measurements = try loadCollection(
            CaptureMeasurementCollection.self,
            at: MeasurementEvidencePackage.path
        )?.measurements ?? []
        let identityData = try? Data(
            contentsOf: rootDirectory.appendingPathComponent(
                EquipmentIdentityEvidencePackage.path,
                isDirectory: false
            )
        )
        let identityRecords = try? identityData.flatMap {
            try? JSONDecoder().decode(
                EquipmentIdentityDocument.self,
                from: $0
            ).records
        }
        let authorities = try loadCollection(
            TheaterAuthorityCollection.self,
            at: TheaterAuthorityPackage.path
        )
        // Committed field-authority documents (#300/#301/#310/#314/
        // #324/#331) seed the editor as the effective state; asset
        // payloads stay on disk (write-once), so only newly captured
        // assets re-enter the staged-asset list.
        let targetsDoc = try loadCollection(
            ReferenceTargetCaptureDocument.self,
            at: ReferenceTargetCapturePackage.path
        )
        let fieldAuthority = FieldAuthorityWorkspace(
            operatorProfiles: try loadCollection(
                OperatorProfileDocument.self,
                at: OperatorProfilePackage.path
            )?.operators ?? [],
            fieldEvidence: try loadCollection(
                FieldEvidenceDocument.self,
                at: FieldEvidencePackage.path
            )?.records ?? [],
            instruments: try loadCollection(
                InstrumentProfileDocument.self,
                at: InstrumentProfilePackage.path
            )?.instruments ?? [],
            settingsObservations: try loadCollection(
                InstalledSettingsDocument.self,
                at: InstalledSettingsPackage.path
            )?.observations ?? [],
            wiringRoutes: try loadCollection(
                AsBuiltWiringDocument.self,
                at: AsBuiltWiringPackage.path
            )?.routes ?? [],
            // #227: committed targets/observations seed the editor so
            // they stay visible and editable; a byte-identical
            // re-commit is a no-op.
            referenceTargets: targetsDoc?.targets,
            referenceTargetObservations:
                targetsDoc?.observations
        )
        return (
            AnnotationWorkspaceSeed(
                annotations: annotations,
                measurements: measurements,
                equipmentIdentityRecords: identityRecords ?? [],
                authorities: authorities,
                fieldAuthority: fieldAuthority
            ),
            identityData
        )
    }

    /// Rebuilds mission/session state a recovered draft still carries:
    /// the verbatim plan imports and every capture-derived supplemental
    /// payload (task-plan status, connected-space map, as-built
    /// verification, repair link) are durable files inside the working
    /// revision — restoring them keeps the mission surface, item
    /// marks, and repair lineage live and lets the derived-document
    /// step at finalization write current truth instead of skipping.
    /// Decode failures leave the corresponding state absent rather
    /// than blocking the reopen — the persisted bytes stay the
    /// canonical copy.
    private func restoreRecoveredMissionState(
        rootDirectory: URL,
        identity: CaptureWorkingSetIdentity
    ) {
        func dataAt(_ path: String) -> Data? {
            let url = rootDirectory.appendingPathComponent(
                path,
                isDirectory: false
            )
            guard FileManager.default.fileExists(atPath: url.path)
            else {
                return nil
            }
            return try? Data(contentsOf: url)
        }
        func loadJSON<T: Decodable>(
            _ type: T.Type,
            at path: String
        ) -> T? {
            dataAt(path).flatMap {
                try? JSONDecoder().decode(T.self, from: $0)
            }
        }

        if let data = dataAt(CaptureTaskPlanImport.path),
           let planImport = try? CaptureTaskPlanImport(data: data)
        {
            captureTaskPlanImport = planImport
            captureTaskPlan = planImport.plan
            var status = CaptureTaskPlanStatus(
                planImport: planImport
            )
            if let document: CaptureTaskPlanStatusDocument =
                loadJSON(
                    CaptureTaskPlanStatusDocument.self,
                    at: CaptureTaskPlanStatusDocument.path
                )
            {
                status.restoreFulfillments(from: document)
            }
            captureTaskPlanStatus = status
        }

        if let data = dataAt(HTDTAsBuiltPlanImport.path),
           let planImport = try? HTDTAsBuiltPlanImport(data: data)
        {
            asBuiltPlanImport = planImport
            asBuiltPlan = planImport.plan
            if let document: AsBuiltVerificationDocument =
                loadJSON(
                    AsBuiltVerificationDocument.self,
                    at: AsBuiltVerificationDocument.path
                ),
               let restored = try? AsBuiltVerificationSession(
                    restoring: document,
                    coordinateSpaceID:
                        sessionController.context.coordinateSpaceID
               )
            {
                asBuiltSession = restored
            } else {
                configureAsBuiltSession()
            }
            asBuiltItems = (try? asBuiltSession?.items()) ?? []
            asBuiltAlignmentInstalled =
                asBuiltSession?.alignment != nil
        }

        if let document: ConnectedSpaceDocument =
            loadJSON(
                ConnectedSpaceDocument.self,
                at: ConnectedSpaceDocument.path
            )
        {
            connectedSpaceTracker = ConnectedSpaceTracker(
                restoring: document
            )
            connectedSpaceIntent = true
        }

        // Revision lineage lives in the working-set identity — the
        // repair-link lineage guard and the post-adoption compare
        // affordance both read it.
        activeRevisionLineage = identity.parentRevisionID.map {
            RevisionLineage(
                captureSeriesID: identity.captureSeriesID,
                parentRevisionID: $0
            )
        }

        if let link: HTDTRepairTaskLink =
            loadJSON(
                HTDTRepairTaskLink.self,
                at: HTDTRepairTaskLink.path
            )
        {
            persistedRepairLinkRevisionID = link.captureRevisionID
            refreshRepairTaskRows()
            activeRepairRow = repairTaskRows.first {
                $0.planID == link.repairPlanID
                    && $0.task.taskID == link.repairTaskID
            }
        }
    }

    /// Lists captured RoomPlan elements and mesh anchors so authority
    /// sheets offer user-assisted selection instead of typed IDs
    /// (#218). Pure reads of app-owned canonical files; decode failures
    /// simply yield an empty picker.
    nonisolated private static func capturedSurfaceOptions(
        rootDirectory: URL
    ) -> (roomPlan: [CapturedSurfaceOption], mesh: [CapturedSurfaceOption])
    {
        func option(
            _ identifier: UUID,
            _ kind: CapturedSurfaceOption.Kind,
            _ prefix: String
        ) -> CapturedSurfaceOption {
            CapturedSurfaceOption(
                identifier: identifier.uuidString.lowercased(),
                kind: kind,
                label: prefix + " " + identifier.uuidString.prefix(8)
            )
        }

        var roomPlan: [CapturedSurfaceOption] = []
        let roomURL = rootDirectory.appendingPathComponent(
            RoomPlanEvidenceArtifactBuilder.processedPath,
            isDirectory: false
        )
        if let data = try? Data(contentsOf: roomURL),
           let room = try? RoomPlanArtifactEncoder.makeJSONDecoder()
               .decode(
                   CapturedRoom.self,
                   from: data
               )
        {
            let surfaces: [(UUID, String)] =
                room.walls.map { ($0.identifier, "wall") }
                + room.floors.map { ($0.identifier, "floor") }
                + room.doors.map { ($0.identifier, "door") }
                + room.windows.map { ($0.identifier, "window") }
                + room.openings.map { ($0.identifier, "opening") }
            roomPlan = surfaces.map {
                option($0.0, .roomPlanSurface, $0.1)
            }
            roomPlan += room.objects.map {
                option(
                    $0.identifier,
                    .roomPlanObject,
                    "object " + String(describing: $0.category)
                )
            }
        }

        var mesh: [CapturedSurfaceOption] = []
        let meshURL = rootDirectory.appendingPathComponent(
            MeshEvidencePackage.indexPath,
            isDirectory: false
        )
        if let data = try? Data(contentsOf: meshURL),
           let index = try? JSONDecoder().decode(
               MeshAnchorEvidenceIndex.self,
               from: data
           )
        {
            mesh = index.anchors.compactMap { record in
                UUID(uuidString: record.anchorID).map {
                    option($0, .meshAnchor, "mesh anchor")
                }
            }
        }
        return (roomPlan, mesh)
    }

    func captureSpeakerOrientation()
        async throws -> AnnotationOrientationAuthority
    {
        guard state == .annotating,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotCameraOrientation(
                depthSelection: .discrete
            )
        // #177: materialize performs packing/hashing/HEIC off
        // MainActor; the retained snapshot preserves the same-frame
        // pose/pixel/depth association.
        let frameArtifacts =
            try await ARFrameArtifactAdapter.materialize(
                snapshot.frameArtifacts
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: frameArtifacts.descriptor,
            pixelPayload: frameArtifacts.pixelPayload,
            depthPayload: frameArtifacts.depthPayload,
            confidencePayload:
                frameArtifacts.confidencePayload,
            previewPayload:
                frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let evidenceRef = "path:" + package.descriptorPath
        annotationRetentionKinds[evidenceRef] = .speakerHeading
        let orientation = try OrientationAxes(
            frontAxisLocal: snapshot.frontAxisWorld,
            upAxisLocal: snapshot.upAxisWorld
        )
        let authority = try AnnotationOrientationAuthority(
            orientation: orientation,
            coordinateSpaceID:
                package.descriptor.coordinateSpaceID,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.orientationUnavailable
        }
        annotationEvidenceRefs =
            workingSnapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )
        workingSetStatus = String(localized: "Evidence-linked speaker heading captured")

        return authority
    }

    /// Full-3D orientation capture for measurement-point (microphone
    /// capsule) direction authority (issue #271). Unlike the speaker
    /// path this keeps the camera's whole orientation — pitch and roll
    /// included — because a microphone axis is not a horizontal
    /// heading.
    func capturePointOrientation()
        async throws -> AnnotationOrientationAuthority
    {
        guard !spatialAuthoritySealedForFinalization,
              state == .annotating,
              workingSetSpatialAuthorityLive,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotCameraOrientation(
                depthSelection: .discrete
            )
        let frameArtifacts =
            try await ARFrameArtifactAdapter.materialize(
                snapshot.frameArtifacts
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: frameArtifacts.descriptor,
            pixelPayload: frameArtifacts.pixelPayload,
            depthPayload: frameArtifacts.depthPayload,
            confidencePayload:
                frameArtifacts.confidencePayload,
            previewPayload:
                frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let evidenceRef = "path:" + package.descriptorPath
        let orientation = try OrientationAxes(
            frontAxisLocal: snapshot.frontAxisWorld,
            upAxisLocal: snapshot.upAxisWorld
        )
        let authority = try AnnotationOrientationAuthority(
            orientation: orientation,
            coordinateSpaceID:
                package.descriptor.coordinateSpaceID,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.orientationUnavailable
        }
        annotationEvidenceRefs =
            workingSnapshot.evidenceFrameRefs
        workingSetStatus = String(localized: "Evidence-linked point direction captured")

        return authority
    }

    func captureRaycastPlacement()
        async throws -> AnnotationPlacementAuthority
    {
        guard state == .annotating,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.raycastMiss
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotCenterRaycastPlacement(
                depthSelection: .discrete
            )
        // #177: materialize performs packing/hashing/HEIC off
        // MainActor; the retained snapshot preserves the same-frame
        // pose/pixel/depth association.
        let frameArtifacts =
            try await ARFrameArtifactAdapter.materialize(
                snapshot.frameArtifacts
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: frameArtifacts.descriptor,
            pixelPayload: frameArtifacts.pixelPayload,
            depthPayload: frameArtifacts.depthPayload,
            confidencePayload:
                frameArtifacts.confidencePayload,
            previewPayload:
                frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.raycastMiss
        }

        let evidenceRef = "path:" + package.descriptorPath
        annotationRetentionKinds[evidenceRef] = .annotationPlacement
        let position = snapshot.positionWorld
        let transform = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            position.x,
            position.y,
            position.z,
            1,
        ])
        // #173: the platform snapshot returns bounded hit provenance
        // (target type, alignment, hit transform, anchor identity,
        // distance); it is mapped into the annotation model's
        // `RaycastPlacementProvenance` so an estimated-plane fallback
        // stays distinguishable from observed-plane geometry after
        // serialization. The same type name exists in both modules, so
        // the model target is module-qualified.
        let raycast = try snapshot.raycastProvenance.map {
            try HTDTCaptureCore.RaycastPlacementProvenance(
                targetType: $0.target.rawValue,
                hitDistanceMeters: $0.hitDistanceMeters,
                hitAnchorIdentifier: $0.hitAnchorIdentifier,
                hitTransform: $0.hitWorldTransform
            )
        }
        let placement = try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: [evidenceRef],
            raycast: raycast
        )
        let authority = try AnnotationPlacementAuthority(
            worldFromAnnotation: transform,
            placement: placement,
            coordinateSpaceID:
                package.descriptor.coordinateSpaceID,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.raycastMiss
        }
        annotationEvidenceRefs =
            workingSnapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )
        workingSetStatus = String(localized: "Evidence-linked raycast placement captured")

        return authority
    }

    /// Live reticle probe for the camera capture sheet and the
    /// scanning-surface reticle (#214/#250): classifies what the
    /// shared session's center ray hits right now — mesh, RoomPlan
    /// object, or plane — with no side effects. During scanning the
    /// RoomPlan object list is empty, so hits classify as mesh or
    /// plane; the reticle still confirms the aim target before a
    /// center raycast executes.
    func probePlacementTarget() async -> AnnotationPlacementProbe {
        guard state == .annotating || state == .scanning else {
            return .unavailable
        }
        return sessionController.probeCenterPlacementTarget(
            roomPlanObjects: annotationRoomPlanObjects
        )
    }

    /// Live camera yaw for the heading arrow (#214).
    func probeCameraHeading() async -> Float? {
        guard state == .annotating else {
            return nil
        }
        return sessionController.currentCameraHeadingDegrees()
    }

    /// Targeted placement capture (#246): the resolved target class is
    /// preserved verbatim in `PlacementProvenance` — a mesh request
    /// produces `mesh_hit_test`, a RoomPlan request `roomplan_binding`,
    /// and an automatic capture never silently downgrades to a plane.
    /// Returns nil for a reticle miss so the form can show "aim at a
    /// surface" instead of destroying state.
    func captureTargetedPlacement(
        preference: PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority? {
        guard state == .annotating,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.raycastMiss
        }

        let generation = captureGeneration
        let capture:
            SharedARSessionController.TargetedPlacementCapture
        do {
            capture = try sessionController
                .snapshotTargetedPlacement(
                    preferring: preference,
                    roomPlanObjects: annotationRoomPlanObjects,
                    depthSelection: .discrete
                )
        } catch PlatformCaptureError.raycastMiss {
            return nil
        }

        // #177: materialize performs packing/hashing/HEIC off
        // MainActor; the retained snapshot preserves the same-frame
        // pose/pixel/depth association.
        let frameArtifacts =
            try await ARFrameArtifactAdapter.materialize(
                capture.frameArtifacts
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: frameArtifacts.descriptor,
            pixelPayload: frameArtifacts.pixelPayload,
            depthPayload: frameArtifacts.depthPayload,
            confidencePayload:
                frameArtifacts.confidencePayload,
            previewPayload:
                frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.raycastMiss
        }

        let evidenceRef = "path:" + package.descriptorPath
        annotationRetentionKinds[evidenceRef] = .annotationPlacement
        let position = capture.positionWorld
        let transform = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            position.x,
            position.y,
            position.z,
            1,
        ])
        let raycast = try capture.raycastProvenance.map {
            try HTDTCaptureCore.RaycastPlacementProvenance(
                targetType: $0.target.rawValue,
                hitDistanceMeters: $0.hitDistanceMeters,
                hitAnchorIdentifier: $0.hitAnchorIdentifier,
                hitTransform: $0.hitWorldTransform
            )
        }
        let placement = try PlacementProvenance(
            method: Self.placementMethod(for: capture.target),
            sourceMeshAnchorID: capture.meshAnchorID,
            sourceRoomPlanObjectID: capture.roomPlanObjectID,
            sourceEvidenceRefs: [evidenceRef],
            raycast: raycast
        )
        let authority = try AnnotationPlacementAuthority(
            worldFromAnnotation: transform,
            placement: placement,
            coordinateSpaceID:
                package.descriptor.coordinateSpaceID,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.raycastMiss
        }
        annotationEvidenceRefs = workingSnapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )
        workingSetStatus = String(localized: "Evidence-linked placement captured")
        return authority
    }

    /// Equipment-identity photo (#239): captures one plain evidence
    /// frame during annotation editing and returns its canonical
    /// `path:` ref so the form can bind it as identity evidence —
    /// distinct from spatial placement authority.
    /// Captures a dedicated close-up photo for a field-evidence
    /// record (#314): a fresh AR frame is materialized and its
    /// high-resolution HEIC rendering is returned as image bytes. No
    /// frame descriptor or spatial metadata is persisted, so a
    /// close-up can never impersonate canonical frame authority.
    func captureFieldEvidencePhoto() async throws
        -> CapturedFieldPhoto
    {
        guard state == .annotating else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotFrameEvidenceCapture(
                depthSelection: .none
            )
        let artifacts =
            try await ARFrameArtifactAdapter.materialize(snapshot)
        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        guard let preview = artifacts.previewPayload else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        return CapturedFieldPhoto(
            data: preview,
            mediaType: .heic,
            pixelWidth: artifacts.descriptor.imageWidth,
            pixelHeight: artifacts.descriptor.imageHeight
        )
    }

    /// Stashes the field-authority workspace staged in the annotation
    /// editor; `commitAnnotationAuthority` persists it inside the same
    /// commit pass so the derived documents land atomically with the
    /// canonical collections they reference (#300/#301/#310/#314/
    /// #324/#331).
    func commitFieldAuthority(
        _ workspace: FieldAuthorityWorkspace
    ) {
        pendingFieldAuthority = workspace
    }

    func captureIdentityPhoto() async throws -> String {
        guard state == .annotating,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotFrameEvidenceCapture(
                depthSelection: .discrete
            )
        let artifacts =
            try await ARFrameArtifactAdapter.materialize(snapshot)
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: artifacts.descriptor,
            pixelPayload: artifacts.pixelPayload,
            depthPayload: artifacts.depthPayload,
            confidencePayload: artifacts.confidencePayload,
            previewPayload: artifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let evidenceRef = "path:" + package.descriptorPath
        annotationRetentionKinds[evidenceRef] = .equipmentIdentity
        let workingSnapshot = await store.snapshot()
        annotationEvidenceRefs = workingSnapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )
        workingSetStatus = String(localized: "Identity evidence photo captured")
        return evidenceRef
    }

    /// Builds the field-authority bundle from the staged workspace —
    /// one derived package per non-empty document family plus staged
    /// asset writes/removals (#300/#301/#310/#314/#324/#331).
    private func buildFieldAuthorityBundle(
        _ workspace: FieldAuthorityWorkspace,
        revisionID: CaptureRevisionID
    ) throws -> FieldAuthorityBundle {
        try FieldAuthorityBundle(
            operators: workspace.operatorProfiles.isEmpty
                ? nil
                : OperatorProfilePackage(
                    document: OperatorProfileDocument(
                        captureRevisionID: revisionID,
                        operators: workspace.operatorProfiles
                    )
                ),
            fieldEvidence: workspace.fieldEvidence.isEmpty
                ? nil
                : FieldEvidencePackage(
                    document: FieldEvidenceDocument(
                        captureRevisionID: revisionID,
                        records: workspace.fieldEvidence
                    )
                ),
            instruments: workspace.instruments.isEmpty
                ? nil
                : InstrumentProfilePackage(
                    document: InstrumentProfileDocument(
                        captureRevisionID: revisionID,
                        instruments: workspace.instruments
                    )
                ),
            settings: workspace.settingsObservations.isEmpty
                ? nil
                : InstalledSettingsPackage(
                    document: InstalledSettingsDocument(
                        captureRevisionID: revisionID,
                        observations:
                            workspace.settingsObservations
                    )
                ),
            wiring: workspace.wiringRoutes.isEmpty
                ? nil
                : AsBuiltWiringPackage(
                    document: AsBuiltWiringDocument(
                        captureRevisionID: revisionID,
                        routes: workspace.wiringRoutes
                    )
                ),
            // #227: only carried when the operator declared targets —
            // the builder computes scale/revisit diagnostics at pack
            // time so the committed document is self-contained.
            referenceTargets:
                (workspace.referenceTargets?.isEmpty ?? true)
                    && (workspace.referenceTargetObservations?
                        .isEmpty ?? true)
                ? nil
                : try ReferenceTargetCaptureBuilder.build(
                    captureRevisionID: revisionID,
                    captureSessionID:
                        sessionController.context.captureSessionID,
                    targets: workspace.referenceTargets ?? [],
                    observations:
                        workspace.referenceTargetObservations ?? []
                ),
            assetWrites: workspace.fieldEvidenceAssets
                .filter { !$0.removal }
                .map {
                    try FieldEvidenceAssetPayload(
                        path: $0.path,
                        data: $0.data
                    )
                },
            assetRemovals: workspace.fieldEvidenceAssets
                .filter { $0.removal }
                .map {
                    try FieldEvidenceAssetPayload(
                        path: $0.path,
                        data: $0.data
                    )
                }
        )
    }

    private static func placementMethod(
        for target: PlacementProbeTarget
    ) -> PlacementMethod {
        switch target {
        case .mesh:
            return .meshHitTest
        case .roomPlanObject:
            return .roomPlanBinding
        case .existingPlaneGeometry, .estimatedPlane:
            return .raycast
        }
    }

    /// Rebuild the visual evidence rows (#255) from the canonical refs.
    private func refreshAnnotationEvidenceFrames(
        rootDirectory: URL
    ) {
        annotationEvidenceFrames =
            EvidenceFramePresentationLoader.load(
                references: annotationEvidenceRefs,
                workingSetRoot: rootDirectory,
                retentionKinds: annotationRetentionKinds
            )
    }

    /// Loads the accepted geometry context for plausibility checks
    /// (#247): persisted mesh bounds + floor level + RoomPlan room
    /// dimensions, plus the bindable object list for `roomplan_binding`
    /// targets (#246). Everything here is a pure read of canonical
    /// files; results are advisory only.
    private func refreshSpatialContext(
        store: CaptureWorkingSetStore,
        generation: UUID
    ) async {
        let rootDirectory = await store.rootDirectory
        let loaded = await Task.detached(
            priority: .userInitiated
        ) {
            (
                Self.loadPlausibilityContext(
                    rootDirectory: rootDirectory
                ),
                Self.loadRoomPlanObjects(
                    rootDirectory: rootDirectory
                )
            )
        }.value

        guard captureGeneration == generation,
              state == .reviewing || state == .annotating
        else {
            return
        }
        spatialPlausibilityContext = loaded.0
        annotationRoomPlanObjects = loaded.1
        annotationRoomPlanObjectsLoaded = true
        await evaluateSpatialPlausibility(
            store: store,
            generation: generation
        )
    }

    /// Re-evaluates advisory plausibility findings (#247) for the
    /// committed annotation set. Produces nil — rendered as
    /// "analysis unavailable" — when no geometry authority exists.
    private func evaluateSpatialPlausibility(
        store: CaptureWorkingSetStore,
        generation: UUID
    ) async {
        let rootDirectory = await store.rootDirectory
        let context = spatialPlausibilityContext
        let findings = await Task.detached(
            priority: .userInitiated
        ) { () -> [SpatialPlausibilityFinding]? in
            let annotations =
                (try? Self.committedAnnotationEntities(
                    rootDirectory: rootDirectory
                )) ?? []
            return SpatialPlausibilityEvaluator.evaluate(
                annotations: annotations,
                context: context
            )
        }.value
        guard captureGeneration == generation,
              state == .reviewing || state == .annotating
        else {
            return
        }
        spatialPlausibilityFindings = findings
    }

    nonisolated private static func committedAnnotationEntities(
        rootDirectory: URL
    ) throws -> [CaptureAnnotationEntity] {
        let url = rootDirectory.appendingPathComponent(
            AnnotationEvidencePackage.path,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: url.path)
        else {
            return []
        }
        return try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: Data(contentsOf: url)
        ).entities
    }

    /// Decodes persisted mesh evidence (`mesh/anchors.json` +
    /// `mesh/geometry/*.meshbin`) and the RoomPlan metadata summary
    /// into the plausibility context (#247). All-bounds or nothing:
    /// partial geometry produces a partial-but-real context, never a
    /// fabricated room.
    nonisolated private static func loadPlausibilityContext(
        rootDirectory: URL
    ) -> SpatialPlausibilityContext {
        var context = SpatialPlausibilityContext()
        let decoder = JSONDecoder()

        let indexURL = rootDirectory.appendingPathComponent(
            MeshEvidencePackage.indexPath,
            isDirectory: false
        )
        if let indexData = try? Data(contentsOf: indexURL),
           let index = try? decoder.decode(
               MeshAnchorEvidenceIndex.self,
               from: indexData
           )
        {
            var floorY: Float?
            var bounds: [SpatialAxisBounds] = []
            for record in index.anchors {
                let geometryURL = rootDirectory
                    .appendingPathComponent(
                        record.geometryPath,
                        isDirectory: false
                    )
                guard let data = try? Data(contentsOf: geometryURL),
                      let geometry = try? MeshBinaryCodec.decode(
                          data
                      )
                else {
                    continue
                }
                let bound = SpatialAxisBounds(
                    vertices: geometry.vertices,
                    worldFromAnchor: record.worldFromAnchor
                )
                bounds.append(bound)
                for vertex in geometry.vertices {
                    let world = record.worldFromAnchor
                        .applying(to: vertex)
                    if let y = floorY {
                        floorY = min(y, world.y)
                    } else {
                        floorY = world.y
                    }
                }
            }
            context.meshBounds = bounds
            context.floorYMeters = floorY
        }

        let metadataURL = rootDirectory.appendingPathComponent(
            CapturedRoomMetadataPackage.path,
            isDirectory: false
        )
        if let data = try? Data(contentsOf: metadataURL),
           let document = try? decoder.decode(
               CapturedRoomMetadataDocument.self,
               from: data
           )
        {
            context.roomDimensionsMeters =
                document.summary?.dimensionsMeters
        }
        return context
    }

    /// Decodes the persisted processed `CapturedRoom` into bindable
    /// objects (#246). iOS-gated inside the platform.
    nonisolated private static func loadRoomPlanObjects(
        rootDirectory: URL
    ) -> [RoomPlanBindableObject] {
        let url = rootDirectory.appendingPathComponent(
            "roomplan/captured-room.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return SharedARSessionController
            .roomPlanBindableObjects(fromProcessedData: data)
    }

    /// Marks a frame's retention reason for the visual picker (#255).
    private func markEvidenceRetention(
        _ ref: String,
        _ kind: EvidenceFrameRetentionKind
    ) {
        annotationRetentionKinds[ref] = kind
    }

    /// Discards the draft bound to the live working revision (#266).
    /// Called on every terminal path for the workspace: commit, cancel,
    /// finalize, reset — canonical files are never involved.
    private func discardAnnotationDraft() {
        if let revisionID = annotationDraftRevisionID {
            annotationDraftStore?.discard(revisionID: revisionID)
        }
    }

    func cancelAnnotation() {
        guard state == .annotating else {
            return
        }
        guard !annotationCommitInFlight else {
            workingSetStatus = String(localized: "Annotation authority is currently being saved. Wait for the save result before cancelling.")
            return
        }
        // Cancel is an explicit draft-discard signal (#266): the
        // operator chose to abandon staged work, so the non-canonical
        // draft is removed rather than restored next time.
        discardAnnotationDraft()
        do {
            try transition(.beginReview)
            annotationRevisionSeed = nil
            pendingFieldAuthority = FieldAuthorityWorkspace()
            annotationEditIsRevision = false
            workingSetStatus = String(localized: "Annotation editing cancelled; staged records not written")
        } catch {
            fail(.unknown)
        }
    }

    func commitAnnotationAuthority(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        identityRecords: [EquipmentIdentityRecord],
        authorities: TheaterAuthorityCollection
    ) {
        guard state == .annotating,
              !annotationCommitInFlight,
              let store = workingSetStore,
              let workingRevisionID =
                workingSetIdentity?.captureRevisionID
        else {
            return
        }

        // A re-opened editor (#163) saves a replacement for the
        // authority committed earlier in the same revision; a first
        // entry commits fresh authority.
        let isRevisionCommit =
            annotationEditIsRevision && annotationAuthorityCommitted

        annotationCommitInFlight = true
        let annotationPackage: AnnotationEvidencePackage
        let measurementPackage: MeasurementEvidencePackage
        // Identity attestations (#239) are validated against the staged
        // entity set before anything is written, so a bad binding
        // fails the commit atomically with no partial authority.
        let identityPackage: EquipmentIdentityEvidencePackage?
        let authorityPackage: TheaterAuthorityPackage?
        do {
            annotationPackage =
                try AnnotationEvidencePackageBuilder.build(
                    entities: annotations,
                    priorEntities: isRevisionCommit
                        ? annotationRevisionSeed?.annotations
                        : nil
                )
            measurementPackage =
                try MeasurementEvidencePackageBuilder.build(
                    measurements: measurements
                )
            identityPackage = try identityRecords.isEmpty
                ? nil
                : EquipmentIdentityEvidencePackage(
                    document: try EquipmentIdentityDocument(
                        captureRevisionID: workingRevisionID,
                        coordinateSpaceID:
                            annotationWorkspaceCoordinateSpaceID,
                        records: identityRecords,
                        entities: annotations
                    )
                )
            // authorities.json is written only once it carries records,
            // or when a previously committed authority set is being
            // replaced (an empty collection clears it).
            if authorities.isEmpty,
               annotationRevisionSeed?.authorities == nil
            {
                authorityPackage = nil
            } else {
                authorityPackage =
                    try TheaterAuthorityPackageBuilder.build(
                        collection: authorities
                    )
            }
        } catch {
            annotationCommitInFlight = false
            workingSetStatus =
                String(localized: "Annotation or measurement authority is not internally valid; nothing was committed")
                + " ["
                + Self.persistenceDiagnostic(error)
                + "]"
            return
        }

        let generation = captureGeneration
        workingSetStatus = String(localized: "Persisting annotation and measurement authority")

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .annotating
            else {
                return
            }

            do {
                if isRevisionCommit {
                    try await store
                        .replaceAnnotationAndMeasurementPackages(
                            annotationPackage: annotationPackage,
                            measurementPackage: measurementPackage,
                            authorityPackage: authorityPackage
                        )
                } else {
                    try await store
                        .persistAnnotationAndMeasurementPackages(
                            annotationPackage: annotationPackage,
                            measurementPackage: measurementPackage,
                            authorityPackage: authorityPackage
                        )
                }
                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                if let identityPackage {
                    try await store
                        .persistOrReplaceEquipmentIdentityEvidence(
                            identityPackage
                        )
                    self.committedIdentityDocData =
                        identityPackage.data
                } else if let priorDoc =
                    self.committedIdentityDocData
                {
                    // All attestations removed in this revision commit
                    // → the derived document is removed byte-identical.
                    try await store
                        .discardEquipmentIdentityEvidence(
                            data: priorDoc
                        )
                    self.committedIdentityDocData = nil
                }

                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                // #337: the finalized bundle declares every external
                // authority it depends on — exact equipment-definition
                // tuples + layout-profile bindings + the task plan —
                // so another HTDT instance resolves them portably and
                // never guesses a missing dependency.
                let dependencyPackage =
                    try ExternalAuthorityDependencyPackage(
                        manifest:
                            ExternalAuthorityDependencyBuilder
                                .manifest(
                                    entities: annotations,
                                    catalog: equipmentCatalog,
                                    identityRecords:
                                        identityRecords,
                                    taskPlan: taskPlan,
                                    taskPlanSHA256: taskPlanSHA256,
                                    generatedAtUTC:
                                        BundleTimestamp.utcString(
                                            from: Date()
                                        )
                                )
                    )
                try await store
                    .persistOrReplaceAuthorityDependencies(
                        dependencyPackage
                    )

                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                // Field-authority family (#300/#301/#310/#314/#324/
                // #331): the staged derived documents are validated
                // against the just-committed canonical collections —
                // the canonical write happens first so entity,
                // measurement and inventory bindings resolve.
                let fieldAuthority = self.pendingFieldAuthority
                if fieldAuthority.hasContent {
                    let bundle = try self.buildFieldAuthorityBundle(
                        fieldAuthority,
                        revisionID: workingRevisionID
                    )
                    if !bundle.isEmpty {
                        try await store
                            .persistFieldAuthorityBundle(bundle)
                    }
                }
                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                // Commit consumed the draft (#266).
                self.discardAnnotationDraft()
                self.annotationAuthorityCommitted = true
                self.annotationCommitInFlight = false
                self.annotationEditIsRevision = false
                self.annotationRevisionSeed = nil

                // #321: in-place repair kinds resolve on the
                // annotation authority commit inside the same
                // revision.
                if let row = self.activeRepairRow,
                   row.task.kind != .freshRescan
                {
                    try? self.repairPlanStore?.markTaskResolved(
                        planKey: row.planKey,
                        taskID: row.task.taskID,
                        resolvedBy: workingRevisionID,
                        at: BundleTimestamp.utcString(from: Date())
                    )
                    self.activeRepairRow = nil
                    self.refreshRepairTaskRows()
                }
                Task { await self.refreshMissionOutcomes() }

                self.pendingFieldAuthority = FieldAuthorityWorkspace()
                try self.transition(.beginReview)
                self.refreshReviewWorkspace()
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
            } catch {
                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                let diagnostic =
                    Self.persistenceDiagnostic(error)

                // Typed authority conflicts or a writer-level conflict/
                // rollback failure are not safe to retry in-place. Ordinary
                // filesystem/resource failures are safe because the paired
                // annotation+measurement write is one rollback-capable
                // batch.
                if error is CaptureWorkingSetError
                    || error is CaptureFileWriterError
                {
                    if isRevisionCommit {
                        // Revision-commit failures are non-terminal: the
                        // paired replace is one rollback-capable batch,
                        // so a recoverable write failure leaves the prior
                        // pair byte-for-byte intact and the editor stays
                        // open; cancelling keeps the prior save (#163).
                        self.annotationCommitInFlight = false
                        self.workingSetStatus =
                            String(localized: "The replacement could not be committed safely; the previously saved annotation and measurement collections remain. Cancel keeps the prior save.")
                            + " ["
                            + diagnostic
                            + "]"
                        return
                    }
                    self.workingSetStatus =
                        String(localized: "Annotation authority could not be committed safely")
                        + " ["
                        + diagnostic
                        + "]"
                    self.fail(.persistenceFailure)
                    return
                }

                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Recoverable annotation/measurement persistence failure: "
                            + diagnostic
                    )
                )
                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }
                self.annotationCommitInFlight = false
                self.workingSetStatus =
                    String(localized: "Annotation changes were not committed; editing remains open and Save can be retried")
                    + " ["
                    + diagnostic
                    + "]"
            }
        }
    }

    /// Validates and adopts an imported HTDT equipment-catalog snapshot
    /// (#211). The snapshot is operator reference context only: it is
    /// held on the host and mirrored to an app-support cache so it
    /// survives annotation cancel → Review → re-enter and app relaunch.
    /// No catalog bytes enter the capture bundle; annotations keep
    /// storing only the exact selected ID/version/SHA-256 tuple.
    ///
    /// A throw means the candidate failed schema/authority validation
    /// and the previously imported snapshot — if any — stays adopted.
    /// A failed cache write only means the next launch requires an
    /// explicit re-import; the in-session context remains usable.
    func importEquipmentCatalog(
        from data: Data
    ) throws -> HTDTEquipmentCatalogSnapshot {
        let snapshot = try JSONDecoder().decode(
            HTDTEquipmentCatalogSnapshot.self,
            from: data
        )
        // Store under its content key and make it active (#302); a
        // write failure leaves the previously adopted catalog active
        // and the in-session context usable.
        if let encoded = try? JSONEncoder().encode(snapshot) {
            _ = try? equipmentCatalogStore?.storeAndActivate(encoded)
        }
        equipmentCatalog = snapshot
        equipmentCatalogLibrary =
            equipmentCatalogStore?.list()
                ?? equipmentCatalogLibrary
        return snapshot
    }

    /// Explicit operator catalog selection (#302): activates a stored
    /// snapshot by content key; an unknown key is ignored rather than
    /// silently substituting a different catalog.
    func selectEquipmentCatalog(contentKey: String) {
        guard let equipmentCatalogStore else { return }
        guard let stored = equipmentCatalogStore.list().first(where: {
            $0.contentKey == contentKey
        }) else {
            return
        }
        try? equipmentCatalogStore.setActive(contentKey: contentKey)
        equipmentCatalog = stored.snapshot
        equipmentCatalogLibrary = equipmentCatalogStore.list()
    }

    /// Label-scan assist (#345): captures a fresh close-up frame,
    /// persists it as equipment-identity evidence, runs Vision
    /// OCR/barcode recognition, and returns suggestion candidates.
    /// Nothing is committed — the sheet only suggests; the operator
    /// confirms a candidate explicitly (or cancels and types manually).
    func scanEquipmentLabel() async throws
        -> EquipmentLabelScanResult
    {
        guard state == .annotating,
              let store = workingSetStore
        else {
            throw EquipmentLabelScanError.scanUnavailable
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotFrameEvidenceCapture(
                depthSelection: .discrete
            )
        // Recognition runs on the retained pixel buffer before the
        // expensive materialization; both stay off the AR boundary.
        let observations =
            try await EquipmentLabelVisionScan.recognize(
                snapshot.capturedImage
            )
        let artifacts =
            try await ARFrameArtifactAdapter.materialize(snapshot)
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: artifacts.descriptor,
            pixelPayload: artifacts.pixelPayload,
            depthPayload: artifacts.depthPayload,
            confidencePayload: artifacts.confidencePayload,
            previewPayload: artifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        guard captureGeneration == generation,
              state == .annotating
        else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let evidenceRef = "path:" + package.descriptorPath
        annotationRetentionKinds[evidenceRef] = .equipmentIdentity
        let workingSnapshot = await store.snapshot()
        annotationEvidenceRefs = workingSnapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )

        let candidates = EquipmentLabelScanMatcher.candidates(
            from: observations,
            catalog: equipmentCatalog?.definitions ?? []
        )
        workingSetStatus = String(localized: "Label scanned — review the suggestions")
        return EquipmentLabelScanResult(
            algorithm: EquipmentLabelScanMatcher.algorithm,
            algorithmVersion:
                EquipmentLabelScanMatcher.algorithmVersion,
            evidenceRef: evidenceRef,
            candidates: candidates,
            rawObservations:
                EquipmentLabelScanMatcher.rawStrings(
                    from: observations
                )
        )
    }

    func finalizeCapture() {
        // #320: a practice working set is never finalizable — the
        // store also rejects the seal, so the gate here is just the
        // early, honest refusal.
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              !practiceCaptureActive,
              let store = workingSetStore
        else {
            return
        }

        // #437: a new attempt replaces the rejection it answered.
        finalizeRejection = nil
        reviewOperationInFlight = true
        let generation = captureGeneration
        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            // Finalize is the point where accepted Review becomes
            // spatially immutable. Stop live resource notifications and AR
            // synchronously on the MainActor before the first suspension so
            // a critical callback cannot race this operation into terminal
            // failure. Keep the stopped monitor object as a synchronous
            // storage assessor for this attempt and any retry.
            let pendingBeforeStorage = self.resourceEventTask
            self.resourceMonitor?.stop()
            self.spatialAuthoritySealedForFinalization = true
            self.sessionController.stopAndPauseARSession()

            await pendingBeforeStorage?.value

            guard self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            if ProcessInfo.processInfo.thermalState == .critical {
                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .thermalPressure,
                        severity: .warning,
                        detail:
                            "finalization deferred because thermal state is still critical after accepted End"
                    )
                )
                guard self.captureGeneration == generation,
                      self.state == .reviewing
                else {
                    return
                }
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
                self.reviewOperationInFlight = false
                self.finalizeRejection = .deferredThermal
                self.workingSetStatus = String(localized: "Finalization is deferred while the device is critically hot. Let it cool, then retry.")
                return
            }

            // Final storage sampling is part of the quality authority, not a
            // fire-and-forget side channel. A critical result after accepted
            // End is transient: retain Review, seal spatial continuation, and
            // retry finalization after storage recovers.
            if let assessment =
                self.resourceMonitor?.currentStorageAssessment()
            {
                let eventToRecord: CaptureResourceEvent
                if assessment.failure == .storagePressure {
                    eventToRecord = CaptureResourceEvent(
                        kind: .storagePressure,
                        severity: .warning,
                        detail:
                            "finalization deferred because available storage is below the critical threshold after accepted End"
                    )
                } else {
                    eventToRecord = assessment.event
                }

                await store.recordResourceEvent(
                    eventToRecord
                )

                guard self.captureGeneration == generation,
                      self.state == .reviewing
                else {
                    return
                }

                if assessment.failure == .storagePressure {
                    await self.refreshQuality(
                        store: store,
                        generation: generation
                    )
                    self.reviewOperationInFlight = false
                    self.finalizeRejection = .deferredStorage
                    self.workingSetStatus = String(localized: "Finalization is deferred because storage is critically low. Free storage, then retry.")
                    return
                }

                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
            }

            // The monitor was stopped before the first await, so no new
            // lifecycle/thermal/storage callback can enter the resource-event
            // chain during the manual final assessment.
            guard self.captureGeneration == generation,
                  self.state == .reviewing,
                  let quality = self.qualityReport,
                  quality.readyForHTDTIngestion,
                  quality.integrityStatus == .pass
            else {
                self.reviewOperationInFlight = false
                self.finalizeRejection = .qualityRegression
                // Live spatial capture is sealed at this point — only
                // non-spatial corrections remain reachable, so name
                // the real options instead of 'resolve diagnostics'.
                self.workingSetStatus = String(localized: "Review quality changed before finalization. Open Details to check the findings and correct non-spatial items, retry saving, save the draft for later, or discard.")
                return
            }

            // Live spatial/resource authority was already sealed before
            // this transaction suspended. Drop the drained event-chain
            // handle; keep the stopped monitor object for retry assessment.
            self.resourceEventTask = nil

            do {
                try self.transition(.beginValidation)
            } catch {
                self.fail(.unknown)
                return
            }

            self.reviewOperationInFlight = false
            self.workingSetStatus = String(localized: "Persisting quality and finalizing revision")

            await self.performFinalization(
                store: store,
                quality: quality,
                generation: generation
            )
        }
    }

    /// Manual recovery for the committed-but-unverified state: the
    /// promoted revision is durable but post-promotion validation
    /// could not prove it, so Prepare/Rescan stayed withheld. Running
    /// the independent validation again on demand either unlocks the
    /// full finalized surface (export, revision lineage) or reports
    /// the concrete diagnostic — never a dead-end of no-op buttons.
    func revalidateAdoptedRevision() {
        guard state == .finalized,
              !exportOperationInFlight,
              !persistedDeletionInFlight,
              let finalizedRevision,
              validationReport == nil
        else {
            return
        }

        exportOperationInFlight = true
        workingSetStatus =
            String(localized: "Re-validating the committed revision")
        let generation = captureGeneration

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.captureGeneration == generation {
                    self.exportOperationInFlight = false
                }
            }

            let (report, diagnostic) =
                await Self.validatePromotedRevision(
                    directory: finalizedRevision.directory
                )
            guard self.captureGeneration == generation,
                  self.state == .finalized,
                  self.finalizedRevision?.captureRevisionID
                    == finalizedRevision.captureRevisionID
            else {
                return
            }

            if let report,
               report.bundleDigest == finalizedRevision.bundleDigest
            {
                self.validationReport = report
                self.workingSetStatus =
                    String(
                        format: String(localized: "Finalized revision; bundle digest %@"),
                        report.bundleDigest.description
                    )
            } else {
                self.validationReport = nil
                self.workingSetStatus =
                    String(localized: "The revision was committed to finalized storage, but post-promotion validation could not prove it; the committed bytes are preserved and stay discoverable through the persisted-capture inventory")
                    + " ["
                    + (report == nil
                        ? (diagnostic
                            ?? "post_promotion_validation_unverified")
                        : "bundle_digest_mismatch")
                    + "]"
            }
        }
    }

    func prepareExport() {
        guard state == .finalized,
              !exportOperationInFlight,
              !persistedDeletionInFlight,
              let finalizedRevision,
              let validationReport,
              validationReport.bundleDigest
                == finalizedRevision.bundleDigest
        else {
            return
        }

        // #437: a new attempt replaces the rejection it answered.
        exportRejection = nil
        exportOperationInFlight = true
        workingSetStatus = String(localized: "Creating validated .htdtcapture archive")
        let generation = captureGeneration

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.captureGeneration == generation {
                    self.exportOperationInFlight = false
                }
            }

            let destination: URL
            do {
                destination = try self.exportDestination(
                    for: finalizedRevision
                )
            } catch {
                guard self.captureGeneration == generation,
                      self.state == .finalized
                else {
                    return
                }
                self.exportRejection = .destinationUnavailable
                self.workingSetStatus =
                    String(localized: "Archive destination could not be prepared. The finalized revision is preserved and export can be retried.")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                return
            }

            func exportFreshArchive() async throws
                -> CaptureBundleArchiveResult
            {
                try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CaptureBundleArchiveExporter.export(
                        finalizedDirectory:
                            finalizedRevision.directory,
                        destination: destination
                    )
                }.value
            }

            do {
                var result: CaptureBundleArchiveResult
                do {
                    result = try await exportFreshArchive()
                } catch {
                    guard self.captureGeneration == generation,
                          self.state == .finalized
                    else {
                        return
                    }

                    guard case CaptureBundleArchiveError
                        .destinationAlreadyExists = error
                    else {
                        throw error
                    }

                    if ExistingExportArchiveClassifier.disposition(
                        at: destination,
                        expectedBundleDigest:
                            finalizedRevision.bundleDigest
                    ) == .recoverValidated {
                        self.exportURL = destination
                        try self.transition(.export)
                        self.applyExportArchiveBackupPolicy(
                            to: destination
                        )
                        self.workingSetStatus = String(localized: "Existing validated archive recovered and is ready to share")
                        self.loadPersistedCaptures()
                        return
                    }

                    // The destination is app-owned derived transport output.
                    // A corrupt or digest-mismatched wrapper is not capture
                    // authority; remove only that wrapper and rebuild once
                    // from the immutable finalized directory.
                    do {
                        try FileManager.default.removeItem(
                            at: destination
                        )
                    } catch {
                        self.exportRejection = .staleArchiveBlocked
                        self.workingSetStatus =
                            String(localized: "A stale export archive blocks rebuilding and could not be removed. The finalized revision is unchanged.")
                            + " ["
                            + Self.persistenceDiagnostic(error)
                            + "]"
                        return
                    }

                    result = try await exportFreshArchive()
                }

                guard result.bundleDigest
                        == finalizedRevision.bundleDigest
                else {
                    throw CaptureBundleArchiveError
                        .archiveLogicalDigestMismatch
                }

                let validation =
                    try StoredCaptureBundleArchiveValidator
                        .validate(archive: result.archiveURL)
                guard validation.bundleDigest
                        == finalizedRevision.bundleDigest
                else {
                    throw CaptureBundleArchiveError
                        .archiveLogicalDigestMismatch
                }

                guard self.captureGeneration == generation,
                      self.state == .finalized
                else {
                    return
                }

                self.exportURL = result.archiveURL
                try self.transition(.export)
                self.applyExportArchiveBackupPolicy(
                    to: result.archiveURL
                )
                self.workingSetStatus = String(localized: "Validated share-ready archive created")
                self.loadPersistedCaptures()
            } catch {
                guard self.captureGeneration == generation,
                      self.state == .finalized
                else {
                    return
                }

                self.exportRejection = .exportFailed
                self.workingSetStatus =
                    String(localized: "Archive export failed. The finalized revision is preserved; retry export when ready.")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    func resetCapture() {
        resetCaptureImpl(preservingFailedDraft: false)
    }

    /// #437: the failed surface's discard and draft-preservation
    /// paths share the same teardown. `preservingFailedDraft` keeps
    /// an end-accepted failed working set on disk as a recoverable
    /// draft — the inventory picks it up on the next refresh — and
    /// never purges its annotation drafts, because the draft is
    /// meant to be reopened.
    private func resetCaptureImpl(
        preservingFailedDraft: Bool
    ) {
        guard state == .failed
                || state == .finalized
                || state == .exported
        else {
            return
        }

        let preserveDraft =
            preservingFailedDraft && state == .failed
        let failedWorkingSet =
            state == .failed && !preserveDraft
                ? workingSetStore : nil
        let pendingResourceEvents = resourceEventTask
        resourceEventTask = nil

        captureGeneration = UUID()
        sessionController.stopAndPauseARSession()

        do {
            try transition(.reset)
        } catch {
            return
        }

        sessionController = SharedARSessionController()
        workingSetStore = nil
        finalizedRevision = nil
        qualityReport = nil
        advisoryReport = nil
        taskProfile = nil
        skippedTaskRequirementIDs = []
        validationReport = nil
        exportURL = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        annotationEvidenceFrames = []
        annotationRoomPlanObjects = []
        annotationRoomPlanObjectsLoaded = false
        spatialPlausibilityContext = SpatialPlausibilityContext()
        spatialPlausibilityFindings = nil
        annotationRetentionKinds = [:]
        committedIdentityDocData = nil
        // Terminal reset also drops imported mission inputs; the
        // active repair row survives because the repair loop spans
        // reset → new capture → finalize (#321).
        captureTaskPlan = nil
        captureTaskPlanImport = nil
        captureTaskPlanStatus = nil
        asBuiltPlan = nil
        asBuiltPlanImport = nil
        // A failed/finalized revision's drafts are bound to it
        // forever; purge them (#266) — except when the failed working
        // set is being preserved as a recoverable draft (#437): the
        // annotation drafts reopen with it.
        if !preserveDraft {
            annotationDraftStore?.discardAll()
        }
        annotationRoomPlanSurfaces = []
        annotationMeshAnchors = []
        activeRevisionLineage = nil
        workingSetIdentity = nil
        annotationRevisionSeed = nil
        pendingFieldAuthority = FieldAuthorityWorkspace()
        annotationEditIsRevision = false
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false
        annotationCommitInFlight = false
        reviewOperationInFlight = false
        exportOperationInFlight = false
        spatialAuthoritySealedForFinalization = false
        planUnderlayDocument = nil
        semanticCorrectionContext = nil
        semanticCorrectionParent = nil
        workingSetSpatialAuthorityLive = true
        recoveredDraftReport = nil
        practiceCaptureActive = false
        activeCaptureIsPractice = false
        finalizationCommit.reset()
        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        scanCoverageTracker = AdvisoryScanCoverageTracker()
        scanCoverage = scanCoverageTracker.summary()
        handoffDestinations = []
        handoffReceipts = []
        reviewWorkspace = nil
        taskPlanMission = nil
        persistedWorkspace = nil
        persistedWorkspaceRoomPlanObjects = []
        roomFrameOriginPending = nil
        openingCenterPending = nil
        danglingSpatialIssues = []
        failedInspection = nil
        connectedSpaceIntent = false
        connectedSpaceTracker = nil
        asBuiltSession = nil
        asBuiltItems = []
        asBuiltAlignmentInstalled = false
        asBuiltActualCandidates = []
        roomFrameAvailable = false
        missionTaskPlanOutcomes = []
        persistedRepairLinkRevisionID = nil
        observationStabilityTracker =
            ObservationStabilityTracker()
        observationStability =
            observationStabilityTracker.summary()
        spatialCoverageAggregator =
            SpatialScanCoverageAggregator()
        spatialCoverage = .empty
        motionGuidanceTracker = ScanMotionGuidanceTracker()
        motionGuidance = nil
        scanGuidanceProgress = .empty
        derivedObjectFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384,
                    maximumObservationCenterShiftMeters: 0.65
                )
            )
        derivedVolumeFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384,
                    maximumObservationCenterShiftMeters: 0.65
                )
            )
        derivedWallFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 4,
                    maximumAgeSeconds: 20,
                    voxelSizeMeters: 0.08,
                    maximumPointCount: 256
                )
            )
        derivedShapePreview = .empty
        derivedPreviewSuspendedForMemoryPressure = false
        scanEvidenceFrameCount = 0
        scanDepthEvidenceCount = 0
        endScanGuidance = nil
        endScanPreflightBlocked = false
        scanGuidanceCuePolicy.reset()
        automaticKeyframeTracker = AutomaticKeyframeTracker()
        automaticKeyframePersistedBytes = 0
        automaticEvidenceFrameCount = 0
        automaticFrameSaveTask?.cancel()
        automaticFrameSaveTask = nil
        scanLightingStatus = .unknown
        lowLightGuidanceActive = false
        endTargetScan()
        operatorRegionDeclarations = OperatorRegionDeclarations()
        declaredRegionList = []
        revisitFlagStore = CaptureRevisitFlagStore()
        revisitFlags = []
        pendingTaskPlanImport = nil
        pendingTaskPlanImportError = nil
        boundTaskPlanStatus = nil
        loopClosureCheckActive = false
        loopClosureAssessment = nil
        loopClosureLastAssessment = nil
        loopClosureOutcome = nil
        latestScanTimestampSeconds = nil
        captureSetup = nil
        deviceReadiness = nil
        stopDeviceReadinessObserving()
        reviewWorkspace = nil
        taskPlanMission = nil
        persistedWorkspace = nil
        persistedWorkspaceRoomPlanObjects = []
        roomFrameOriginPending = nil
        openingCenterPending = nil
        danglingSpatialIssues = []
        failedInspection = nil
        resourceMonitor?.stop()
        resourceMonitor = nil
        workingSetStatus =
            state == .idle
            ? String(localized: "Ready for a new capture")
            : String(localized: "Capture reset")
        isEndingScan = false
        isCapturingEvidenceFrame = false
        evidenceFrameSaveTask = nil
        scanTrackingTransitionGate.reset()
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()

        if let failedWorkingSet {
            Task { @MainActor [weak self] in
                await pendingResourceEvents?.value
                do {
                    try await failedWorkingSet
                        .discardIncompleteRevision()
                } catch {
                    guard let self,
                          self.state == .idle
                    else {
                        return
                    }
                    self.workingSetStatus = String(localized: "Ready; prior incomplete revision cleanup failed")
                }
            }
        }
    }

    /// Best-effort byte total for a directory tree — the same
    /// shallow FileManager enumeration the persisted inventory
    /// uses. Informational only; never gates a restore.
    private static func retainedByteTotal(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isRegularFileKey,
            ]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let values = try? file.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    /// #437 "Keep the draft for later" on the failed surface: the
    /// failed end-accepted working set is preserved on disk as a
    /// recoverable draft — teardown still runs, the working root
    /// stays, and the next inventory refresh lists it on Home.
    func preserveFailedCaptureAsDraft() {
        guard state == .failed, failedDraftRecoverable else {
            return
        }
        resetCaptureImpl(preservingFailedDraft: true)
        loadPersistedCaptures()
        workingSetStatus = String(
            localized: "Draft saved — reopen it from Home to finish the capture"
        )
    }

    /// #437 "Reopen the draft and finish" on the failed surface:
    /// preserves the failed end-accepted working set as a recoverable
    /// draft, then immediately reopens it into sealed Review — the
    /// same destination the home draft affordance offers.
    func resumeFailedCaptureAsDraft() {
        guard state == .failed, failedDraftRecoverable,
              let store = workingSetStore
        else {
            return
        }
        let draftURL = store.rootDirectory
        let document = CaptureWorkingSetStore.peekRevisionPhase(
            workingRevisionURL: draftURL
        )
        resetCaptureImpl(preservingFailedDraft: true)
        guard let document,
              document.phase.isRecoverableDraft
        else {
            // The phase marker went missing between fail() and the
            // action — the working set is still preserved; the next
            // inventory refresh decides what it lists.
            loadPersistedCaptures()
            workingSetStatus = String(
                localized: "Draft saved — reopen it from Home to finish the capture"
            )
            return
        }
        let draft = RecoverableWorkingRevision(
            url: draftURL,
            revisionID: document.captureRevisionID,
            phase: document.phase,
            captureSessionID: document.captureSessionID,
            coordinateSpaceID: document.coordinateSpaceID,
            retainedBytes: Self.retainedByteTotal(at: draftURL)
        )
        loadPersistedCaptures()
        openRecoveredDraft(draft)
    }

    /// #437 "Discard and start a new capture" on the failed surface:
    /// permanently removes the failed capture's retained data, then
    /// opens capture setup — a real two-step path, not a dead
    /// confirm.
    func discardFailedAndStartNewCapture() {
        guard state == .failed else {
            return
        }
        resetCapture()
        beginCapture()
    }

    /// Operator-initiated discard of the active capture (issue #254):
    /// scanning, review, or annotation state. The caller must
    /// have already shown a confirmation; this fence is terminal —
    /// AR is stopped, all in-flight writes are fenced by the store's
    /// discard barrier, the working revision is deleted, and finalized
    /// captures are never touched (this state can only run while the
    /// capture is still a working set).
    func discardActiveCapture() {
        guard [.preparing, .scanning, .reviewing, .annotating]
            .contains(state),
              !isEndingScan,
              !annotationCommitInFlight,
              !reviewOperationInFlight,
              !exportOperationInFlight,
              !isCapturingEvidenceFrame,
              !roomPlanCompletionInFlight
        else {
            return
        }

        // .preparing can be cancelled before the working-set store is
        // published; the in-flight preparation then removes the
        // revision it creates (its post-await guard), so nil here is
        // not an error.
        let discardedStore = workingSetStore

        // Fence every in-flight callback before tearing down so a late
        // evidence write cannot land in the revision being discarded.
        captureGeneration = UUID()
        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        resourceMonitor?.stop()
        resourceMonitor = nil
        sessionController.stopAndPauseARSession()

        do {
            try transition(.abortCapture)
        } catch {
            return
        }

        // Reuse the full reset teardown (same field-for-field cleanup as
        // a failed-capture reset) without re-entering transition: the
        // state machine is already at .idle.
        sessionController = SharedARSessionController()
        workingSetStore = nil
        finalizedRevision = nil
        qualityReport = nil
        validationReport = nil
        exportURL = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        activeRevisionLineage = nil
        workingSetIdentity = nil
        annotationRevisionSeed = nil
        pendingFieldAuthority = FieldAuthorityWorkspace()
        annotationEditIsRevision = false
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false
        annotationCommitInFlight = false
        reviewOperationInFlight = false
        exportOperationInFlight = false
        spatialAuthoritySealedForFinalization = false
        planUnderlayDocument = nil
        semanticCorrectionContext = nil
        semanticCorrectionParent = nil
        workingSetSpatialAuthorityLive = true
        recoveredDraftReport = nil
        practiceCaptureActive = false
        activeCaptureIsPractice = false
        finalizationCommit.reset()
        scanCoverageTracker = AdvisoryScanCoverageTracker()
        scanCoverage = .empty
        observationStabilityTracker = ObservationStabilityTracker()
        observationStability = .empty
        spatialCoverageAggregator = SpatialScanCoverageAggregator()
        spatialCoverage = .empty
        motionGuidanceTracker = ScanMotionGuidanceTracker()
        motionGuidance = nil
        scanGuidanceProgress = .empty
        derivedShapePreview = .empty
        derivedPreviewSuspendedForMemoryPressure = false
        scanEvidenceFrameCount = 0
        scanDepthEvidenceCount = 0
        endScanGuidance = nil
        endScanPreflightBlocked = false
        reviewWorkspace = nil
        taskPlanMission = nil
        persistedWorkspace = nil
        persistedWorkspaceRoomPlanObjects = []
        roomFrameOriginPending = nil
        openingCenterPending = nil
        danglingSpatialIssues = []
        failedInspection = nil
        handoffDestinations = []
        handoffReceipts = []
        scanTrackingTransitionGate.reset()
        isEndingScan = false
        isCapturingEvidenceFrame = false
        evidenceFrameSaveTask = nil
        workingSetStatus = String(localized: "Discarding the working revision")

        if let discardedStore {
            Task { @MainActor [weak self] in
                do {
                    try await discardedStore.discardIncompleteRevision()
                    guard let self, self.state == .idle else { return }
                    self.workingSetStatus = String(localized: "Capture discarded; working revision removed")
                    self.loadPersistedCaptures()
                } catch {
                    guard let self, self.state == .idle else { return }
                    self.workingSetStatus = String(localized: "The capture was stopped but its working data could not be fully removed; it is listed under abandoned working data") + " [" + Self.persistenceDiagnostic(error) + "]"
                    self.loadPersistedCaptures()
                }
            }
        } else {
            workingSetStatus = String(localized: "Capture cancelled")
            loadPersistedCaptures()
        }
    }

    /// #297: reopen an end-accepted working revision that survived a
    /// relaunch. `restoreWorkingRevision` rebuilds a full working-set
    /// store whose spatial authority is permanently sealed; the host
    /// lands in Review where semantic authoring and finalization work
    /// but live-capture affordances are gone.
    func openRecoveredDraft(_ draft: RecoverableWorkingRevision) {
        // #437: the setup surface offers the same stranded-draft
        // affordances as Home — resuming leaves setup for Review.
        if state == .setup {
            cancelCaptureSetup()
        }
        guard state == .idle,
              workingSetStore == nil,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight,
              !importOperationInFlight
        else {
            return
        }

        persistedAdoptionInFlight = true
        workingSetStatus = String(localized: "Reopening the saved draft")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let restored =
                    try await CaptureWorkingSetStore
                        .restoreWorkingRevision(draft)
                guard self.state == .idle else {
                    self.persistedAdoptionInFlight = false
                    return
                }
                let store = restored.store
                let snapshot = await store.snapshot()
                self.captureGeneration = UUID()
                self.workingSetStore = store
                self.workingSetIdentity = snapshot.identity
                self.workingSetSpatialAuthorityLive = false
                self.recoveredDraftReport = restored.report
                self.activeCaptureIsPractice = false
                self.practiceCaptureActive = false
                // Not the #112/#276 resource seal — the review controls
                // still run; only live-spatial paths are gated, by
                // `workingSetSpatialAuthorityLive`.
                self.spatialAuthoritySealedForFinalization = false
                self.activeRevisionLineage = nil
                // Rebind the shared session context to the persisted
                // capture session + coordinate space: every post-restore
                // binder (annotations, mission documents, repair links)
                // stamps `sessionController.context`, and the store
                // rejects commits whose authority does not match the
                // restored session foundation.
                if let sessionID = snapshot.captureSessionIDs.first,
                   let spaceID = snapshot.coordinateSpaceIDs.first
                {
                    self.sessionController =
                        SharedARSessionController(
                            context: CaptureSessionContext(
                                captureSessionID: sessionID,
                                coordinateSpaceID: spaceID
                            )
                        )
                }
                // "Committed" means the canonical annotation/
                // measurement payloads exist — not merely that a seed
                // decode produced an (empty) workspace. A draft that
                // crashed before its first commit must keep routing to
                // the fresh-annotation path.
                let committedPaths = [
                    AnnotationEvidencePackage.path,
                    MeasurementEvidencePackage.path,
                ]
                self.annotationAuthorityCommitted =
                    committedPaths.contains { path in
                        FileManager.default.fileExists(
                            atPath: snapshot.rootDirectory
                                .appendingPathComponent(path)
                                .path
                        )
                    }
                self.annotationEditIsRevision =
                    self.annotationAuthorityCommitted
                // Mission/session state is durable supplemental
                // payload inside the restored working set — rebuild
                // it so the mission surface, task marks, connected
                // space map, as-built session, and repair lineage keep
                // working on the reopened draft instead of silently
                // reverting to "no mission" (which also made every
                // mission-bearing draft unfinalizable through the
                // derived-document step).
                self.restoreRecoveredMissionState(
                    rootDirectory: snapshot.rootDirectory,
                    identity: snapshot.identity
                )
                if let document =
                    CaptureWorkingSetStore.peekRevisionPhase(
                        workingRevisionURL: draft.url
                    )
                {
                    self.taskProfile =
                        document.checkpoint?.taskProfile
                    self.skippedTaskRequirementIDs = Set(
                        document.checkpoint?
                            .skippedTaskRequirementIDs ?? []
                    )
                }
                do {
                    try self.transition(.reopenDraft)
                } catch {
                    self.fail(.unknown)
                    return
                }
                self.persistedAdoptionInFlight = false
                self.workingSetStatus = String(localized: "Draft reopened for review; spatial capture is sealed")
                let generation = self.captureGeneration
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
                self.refreshReviewWorkspace()
            } catch {
                self.persistedAdoptionInFlight = false
                self.workingSetStatus = String(localized: "The recoverable draft could not be reopened; it stays listed")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// #297 "Save and finish later": leave Review without discarding.
    /// The working revision's phase document already says
    /// end-accepted, so it stays listed as a recoverable draft on the
    /// home surface and on the next launch.
    func suspendReviewAndFinishLater() {
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              !annotationCommitInFlight,
              !exportOperationInFlight,
              workingSetStore != nil
        else {
            return
        }

        // Fence every in-flight callback before teardown, exactly like
        // discard — except the working revision stays on disk.
        captureGeneration = UUID()
        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        resourceMonitor?.stop()
        resourceMonitor = nil
        sessionController.stopAndPauseARSession()

        do {
            try transition(.suspendReview)
        } catch {
            return
        }

        sessionController = SharedARSessionController()
        workingSetStore = nil
        finalizedRevision = nil
        qualityReport = nil
        advisoryReport = nil
        taskProfile = nil
        skippedTaskRequirementIDs = []
        validationReport = nil
        exportURL = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        annotationEvidenceFrames = []
        annotationRoomPlanObjects = []
        annotationRoomPlanObjectsLoaded = false
        spatialPlausibilityContext = SpatialPlausibilityContext()
        spatialPlausibilityFindings = nil
        annotationRetentionKinds = [:]
        committedIdentityDocData = nil
        // Draft autosaves bound to this revision stay on disk (#266):
        // the draft is meant to be reopened, so unlike
        // discard/reset this does not purge the annotation-draft
        // store.
        annotationRoomPlanSurfaces = []
        annotationMeshAnchors = []
        activeRevisionLineage = nil
        workingSetIdentity = nil
        annotationRevisionSeed = nil
        annotationEditIsRevision = false
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false
        annotationCommitInFlight = false
        reviewOperationInFlight = false
        exportOperationInFlight = false
        spatialAuthoritySealedForFinalization = false
        workingSetSpatialAuthorityLive = true
        recoveredDraftReport = nil
        practiceCaptureActive = false
        activeCaptureIsPractice = false
        finalizationCommit.reset()
        scanCoverageTracker = AdvisoryScanCoverageTracker()
        scanCoverage = .empty
        observationStabilityTracker = ObservationStabilityTracker()
        observationStability = .empty
        spatialCoverageAggregator = SpatialScanCoverageAggregator()
        spatialCoverage = .empty
        motionGuidanceTracker = ScanMotionGuidanceTracker()
        motionGuidance = nil
        scanGuidanceProgress = .empty
        derivedShapePreview = .empty
        derivedPreviewSuspendedForMemoryPressure = false
        scanEvidenceFrameCount = 0
        scanDepthEvidenceCount = 0
        endScanGuidance = nil
        endScanPreflightBlocked = false
        reviewWorkspace = nil
        persistedWorkspace = nil
        persistedWorkspaceRoomPlanObjects = []
        roomFrameOriginPending = nil
        danglingSpatialIssues = []
        failedInspection = nil
        handoffDestinations = []
        handoffReceipts = []
        scanTrackingTransitionGate.reset()
        isEndingScan = false
        isCapturingEvidenceFrame = false
        evidenceFrameSaveTask = nil
        workingSetStatus = String(localized: "Draft saved; reopen it any time from Recoverable drafts")
        loadPersistedCaptures()
    }

    /// Permanently remove a recoverable draft's working revision
    /// (#297). Routed through the same path-safety-verified working-root
    /// removal as abandoned revisions.
    func discardRecoveredDraft(
        _ draft: RecoverableWorkingRevision
    ) {
        // #437: the setup surface offers the same discard affordance
        // as Home — removing a draft leaves setup too.
        if state == .setup {
            cancelCaptureSetup()
        }
        guard state == .idle,
              !persistedDeletionInFlight,
              !persistedAdoptionInFlight,
              !importOperationInFlight,
              let store = persistedStore
        else {
            return
        }

        persistedDeletionInFlight = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.persistedDeletionInFlight = false
                self.loadPersistedCaptures()
            }
            do {
                try await Task.detached(
                    priority: .userInitiated
                ) {
                    try store.removeWorkingOrphan(
                        PersistedCaptureWorkingOrphan(
                            kind: .abandonedRevision,
                            url: draft.url,
                            retainedBytes: draft.retainedBytes
                        )
                    )
                }.value
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus = String(localized: "Draft deleted")
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus = String(localized: "The draft could not be deleted; it stays listed for retry") + " [" + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// #298 remediation router: each action routes to the surface that
    /// can legitimately clear the finding — never a quality-gate
    /// bypass. Actions the current working set cannot support were
    /// already filtered out by the view layer.
    func performRemediation(
        _ action: CaptureRemediationAction
    ) {
        switch action {
        case .continueScanning:
            continueScanningFromReview()
        case .saveEvidenceFrame:
            // Still-frame capture lives on the scanning surface; the
            // honest route to it from Review is Continue scanning.
            continueScanningFromReview()
        case .addAnnotation,
             .addMeasurement,
             .reviewTaskRequirements:
            // The annotation workspace hosts entity/measurement
            // authoring plus the task-profile picker (#217/#259).
            beginAnnotation()
        case .verifyIntegrityAgain:
            guard state == .reviewing,
                  let store = workingSetStore
            else {
                return
            }
            let generation = captureGeneration
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
                self.refreshReviewWorkspace()
            }
        case .startReplacementRevision:
            guard state == .reviewing else {
                return
            }
            // For a recovered draft there is no AR session to stop —
            // discard removes the working revision; for a live review
            // this is the ordinary discard path. Either way the
            // operator lands in Idle and immediately starts the
            // replacement's setup flow.
            discardActiveCapture()
            beginCapture()
        case .discardDraft:
            discardActiveCapture()
        }
    }

    /// Rebuilds the review workspace model from the live working set
    /// (issues #213, #231, #232, #241). Called on entry to Review and
    /// after every authority commit that changes committed payloads.
    func refreshReviewWorkspace() {
        guard state == .reviewing || state == .annotating,
              let store = workingSetStore
        else {
            return
        }
        // A recovered draft's spatial authority ended with the prior
        // process (#297): the workspace renders it sealed even though
        // the #276 finalization seal flag is unset.
        let sealed = spatialAuthoritySealedForFinalization
            || !workingSetSpatialAuthorityLive
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await store.snapshot()
            guard self.state == .reviewing
                    || self.state == .annotating
            else {
                return
            }
            var model =
                CaptureReviewWorkspaceLoader.loadWorkingSet(
                    snapshot: snapshot,
                    endBoundaryFrameIDs: Set(
                        snapshot.endBoundaryFrameIDs
                    )
                )
            if sealed {
                model = CaptureReviewWorkspaceModel(
                    captureRevisionID: model.captureRevisionID,
                    coordinateSpaceID: model.coordinateSpaceID,
                    roomMetadata: model.roomMetadata,
                    planPreview: model.planPreview,
                    evidenceItems: model.evidenceItems,
                    annotations: model.annotations,
                    measurements: model.measurements,
                    operatorProfiles: model.operatorProfiles,
                    fieldEvidence: model.fieldEvidence,
                    instruments: model.instruments,
                    settingsObservations:
                        model.settingsObservations,
                    wiringRoutes: model.wiringRoutes,
                    referenceTargets: model.referenceTargets,
                    openingReview: model.openingReview,
                    roomReferenceFrame: model.roomReferenceFrame,
                    roomFieldDatum: model.roomFieldDatum,
                    roomFieldDatumStaleness:
                        model.roomFieldDatumStaleness,
                    qualityReport: model.qualityReport,
                    readOnly: model.readOnly,
                    spatialCaptureSealed: true,
                    revisitFlags: model.revisitFlags,
                    captureTaskPlan: model.captureTaskPlan,
                    taskPlanStatus: model.taskPlanStatus,
                    fieldNotes: model.fieldNotes,
                    contactSheet: model.contactSheet,
                    issues: model.issues
                )
            }
            #if os(iOS) && canImport(RoomPlan)
            if #available(iOS 17.0, *) {
                let processedURL = snapshot.rootDirectory
                    .appendingPathComponent(
                        "roomplan/captured-room.json",
                        isDirectory: false
                    )
                if let data = try? Data(contentsOf: processedURL),
                   let plan = try? RoomPlanReviewDeriver
                       .planPreview(processedPayload: data)
                {
                    model = CaptureReviewWorkspaceModel(
                        captureRevisionID: model.captureRevisionID,
                        coordinateSpaceID: model.coordinateSpaceID,
                        roomMetadata: model.roomMetadata,
                        planPreview: plan,
                        evidenceItems: model.evidenceItems,
                        annotations: model.annotations,
                        measurements: model.measurements,
                        referenceTargets: model.referenceTargets,
                        openingReview: model.openingReview,
                        roomReferenceFrame: model.roomReferenceFrame,
                        qualityReport: model.qualityReport,
                        readOnly: model.readOnly,
                        spatialCaptureSealed:
                            model.spatialCaptureSealed,
                        revisitFlags: model.revisitFlags,
                        captureTaskPlan: model.captureTaskPlan,
                        taskPlanStatus: model.taskPlanStatus,
                        issues: model.issues
                    )
                }
            }
            #endif
            self.reviewWorkspace = model
            // Required-task mission progress (#372): evaluated from
            // the committed records against the active plan — kept
            // separate from technical readiness.
            if let taskPlan {
                let authoritiesURL = snapshot.rootDirectory
                    .appendingPathComponent(
                        TheaterAuthorityPackage.path,
                        isDirectory: false
                    )
                let authorities = (try? Data(contentsOf: authoritiesURL))
                    .flatMap {
                        try? JSONDecoder().decode(
                            TheaterAuthorityCollection.self,
                            from: $0
                        )
                    } ?? .empty
                self.taskPlanMission = CaptureJourneyPresentation
                    .missionSummary(
                        plan: taskPlan,
                        annotations: model.annotations,
                        measurements: model.measurements,
                        authorities: authorities,
                        committedEvidenceRefs: annotationEvidenceRefs
                    )
            } else {
                self.taskPlanMission = nil
            }
        }
    }

    /// Captures the operator-confirmed room-origin point for the
    /// pending room reference frame (issue #232).
    func captureRoomFrameOriginPoint() {
        guard state == .reviewing || state == .annotating,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive
        else {
            return
        }
        do {
            let sample =
                try sessionController.currentScanCoverageSample()
            guard let position = sample.cameraPosition else {
                throw PlatformCaptureError.currentFrameUnavailable
            }
            roomFrameOriginPending = WorldPoint3D(
                x: position.x,
                y: position.y,
                z: position.z
            )
            workingSetStatus = String(localized: "Room origin captured; now point along the room front and confirm the second point")
        } catch {
            workingSetStatus = String(localized: "Camera position unavailable for the room frame") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Confirms the two-point room reference frame: builds the typed
    /// document from the pending origin + a second camera sample and
    /// commits it to the working set (issue #232).
    func confirmRoomReferenceFrame() {
        guard state == .reviewing || state == .annotating,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive,
              let origin = roomFrameOriginPending,
              let store = workingSetStore
        else {
            return
        }
        let generation = captureGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sample =
                    try self.sessionController
                        .currentScanCoverageSample()
                guard let second = sample.cameraPosition else {
                    throw PlatformCaptureError.currentFrameUnavailable
                }
                let front = WorldPoint3D(
                    x: second.x,
                    y: second.y,
                    z: second.z
                )
                let snapshot = await store.snapshot()
                guard let sessionID = snapshot.captureSessionIDs
                    .first,
                    let spaceID = snapshot.coordinateSpaceIDs.first
                else {
                    throw RoomReferenceFrameError
                        .coordinateSpaceUnbound
                }
                var evidenceRefs: [String] = []
                for frameID in snapshot.endBoundaryFrameIDs {
                    evidenceRefs.append(
                        "frame:" + frameID.description
                    )
                }
                let document = try RoomReferenceFrameDocument(
                    captureRevisionID:
                        snapshot.identity.captureRevisionID,
                    captureSessionID: sessionID,
                    coordinateSpaceID: spaceID,
                    originMeters: origin,
                    frontPointMeters: front,
                    evidenceRefs: evidenceRefs,
                    confirmedAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    )
                )
                let package =
                    try RoomReferenceFramePackageBuilder.build(
                        document: document
                    )
                try await store.commitRoomReferenceFrame(package)
                guard self.captureGeneration == generation,
                      self.state == .reviewing
                        || self.state == .annotating
                else {
                    return
                }
                self.roomFrameOriginPending = nil
                self.roomFrameAvailable = true
                self.workingSetStatus = String(localized: "Room reference frame confirmed and saved")
                self.refreshReviewWorkspace()
                Task { await self.refreshMissionOutcomes() }
            } catch {
                guard self.captureGeneration == generation else {
                    return
                }
                self.workingSetStatus = String(localized: "The room reference frame could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// Captures the camera position as the center for a
    /// user-declared opening candidate (issue #231).
    func captureOpeningCenterPoint() {
        guard state == .reviewing || state == .annotating,
              !spatialAuthoritySealedForFinalization,
              workingSetSpatialAuthorityLive
        else {
            return
        }
        do {
            let sample =
                try sessionController.currentScanCoverageSample()
            guard let position = sample.cameraPosition else {
                throw PlatformCaptureError.currentFrameUnavailable
            }
            openingCenterPending = WorldPoint3D(
                x: position.x,
                y: position.y,
                z: position.z
            )
            workingSetStatus = String(localized: "Opening center captured")
        } catch {
            workingSetStatus = String(localized: "Camera position unavailable for the opening") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Clears the pending user-declared opening center so another
    /// candidate can be marked (issue #231).
    func clearOpeningCenterPoint() {
        openingCenterPending = nil
    }

    /// Confirms the field/install datum (issue #232): derived from
    /// the committed room reference frame and the processed
    /// payload's finished-floor level, then committed as
    /// `session/room-field-datum.json`. Never a
    /// `T_scene_from_capture_world` — promotion into HTDT's scene is
    /// still the operator's explicit downstream step.
    func confirmFieldDatumFromRoomFrame() async -> Bool {
        guard state == .reviewing || state == .annotating,
              !spatialAuthoritySealedForFinalization,
              let store = workingSetStore
        else {
            return false
        }
        let snapshot = await store.snapshot()
        guard let frame = snapshot.roomReferenceFrame else {
            workingSetStatus = String(localized: "Confirm a room reference frame first")
            return false
        }
        var floorY: Double?
        let processedURL = snapshot.rootDirectory
            .appendingPathComponent(
                "roomplan/captured-room.json",
                isDirectory: false
            )
        if let data = try? Data(contentsOf: processedURL) {
            #if os(iOS) && canImport(RoomPlan)
            if #available(iOS 17.0, *) {
                floorY = RoomPlanReviewDeriver
                    .finishedFloorElevationMeters(
                        processedPayload: data
                    )
            }
            #endif
        }
        guard let zeroElevation = floorY else {
            workingSetStatus = String(localized: "No finished floor in the RoomPlan payload; field datum needs a floor level")
            return false
        }
        do {
            let sessionID = frame.captureSessionID
            let origin = try RoomFieldDatumOrigin(
                kind: .roomFrameOrigin,
                ref: "room_reference_frame",
                pointMeters: frame.originMeters
            )
            let axis = try RoomFieldDatumAxis(
                kind: .roomFrameFront,
                refs: ["room_reference_frame"],
                directionMeters: frame.frontDirection
            )
            let vertical = try RoomFieldDatumVertical(
                kind: .finishedFloor,
                ref: "room_reference_frame",
                zeroElevationMeters: zeroElevation
            )
            let transform = try RoomFieldDatumPackageBuilder
                .fieldTransform(
                    origin: origin,
                    axis: axis,
                    verticalDatum: vertical
                )
            let document = try RoomFieldDatumDocument(
                captureRevisionID:
                    snapshot.identity.captureRevisionID,
                captureSessionID: sessionID,
                coordinateSpaceID: frame.coordinateSpaceID,
                origin: origin,
                axis: axis,
                verticalDatum: vertical,
                fieldFromCaptureWorld: transform,
                uncertaintyMeters: nil,
                residualMeters: nil,
                sourceEvidenceRefs: ["room_reference_frame"],
                confirmedAtUTC: BundleTimestamp.utcString(
                    from: Date()
                )
            )
            let package = try RoomFieldDatumPackageBuilder.build(
                document: document
            )
            try await store.commitRoomFieldDatum(package)
            refreshReviewWorkspace()
            workingSetStatus = String(localized: "Field datum confirmed and saved")
            return true
        } catch {
            workingSetStatus = String(localized: "The field datum could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
            return false
        }
    }

    /// Commits a field datum declared from bounded operands —
    /// entity/measurement/room-frame/stated picks authored in
    /// Review (issue #232). Resolution is pure (entity positions,
    /// measurement endpoints, frame vectors); the host only binds
    /// revision/session/space and commits.
    func commitFieldDatum(
        _ request: RoomFieldDatumAuthoringRequest
    ) async -> Bool {
        guard state == .reviewing || state == .annotating,
              !spatialAuthoritySealedForFinalization,
              let store = workingSetStore,
              let model = reviewWorkspace
        else {
            return false
        }
        do {
            let resolution = try RoomFieldDatumAuthoring.resolve(
                origin: request.origin,
                statedOriginMeters: request.statedOriginMeters,
                axis: request.axis,
                statedDirectionMeters:
                    request.statedDirectionMeters,
                vertical: request.vertical,
                entities: model.annotations,
                measurements: model.measurements,
                roomReferenceFrame: model.roomReferenceFrame
            )
            let transform = try RoomFieldDatumPackageBuilder
                .fieldTransform(
                    origin: resolution.origin,
                    axis: resolution.axis,
                    verticalDatum: resolution.verticalDatum
                )
            let document = try RoomFieldDatumDocument(
                captureRevisionID:
                    await store.snapshot().identity
                        .captureRevisionID,
                captureSessionID:
                    sessionController.context.captureSessionID,
                coordinateSpaceID:
                    model.roomReferenceFrame?.coordinateSpaceID
                        ?? sessionController.context
                            .coordinateSpaceID,
                origin: resolution.origin,
                axis: resolution.axis,
                verticalDatum: resolution.verticalDatum,
                fieldFromCaptureWorld: transform,
                uncertaintyMeters: nil,
                residualMeters: nil,
                sourceEvidenceRefs:
                    resolution.sourceEvidenceRefs,
                confirmedAtUTC: BundleTimestamp.utcString(
                    from: Date()
                )
            )
            let package = try RoomFieldDatumPackageBuilder.build(
                document: document
            )
            try await store.commitRoomFieldDatum(package)
            refreshReviewWorkspace()
            workingSetStatus = String(
                localized: "Field datum confirmed and saved"
            )
            return true
        } catch {
            workingSetStatus = String(localized: "The field datum could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
            return false
        }
    }

    /// Removes the committed field datum payload (issue #232).
    func removeRoomFieldDatum() async {
        guard let store = workingSetStore else { return }
        do {
            try await store.removeRoomFieldDatum()
            refreshReviewWorkspace()
            workingSetStatus = String(localized: "Field datum removed")
        } catch {
            workingSetStatus = String(localized: "The field datum could not be removed") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Enumerates RoomPlan door/window/opening candidates from the
    /// committed processed payload and merges them with any committed
    /// review document (issue #231). Returns nil when no processed
    /// RoomPlan payload exists.
    func openingReviewCandidates()
        async -> [RoomOpeningCandidate]?
    {
        guard let store = workingSetStore else { return nil }
        let snapshot = await store.snapshot()
        let processedURL = snapshot.rootDirectory
            .appendingPathComponent(
                "roomplan/captured-room.json",
                isDirectory: false
            )
        guard let data = try? Data(contentsOf: processedURL) else {
            return nil
        }
        var enumerated: [RoomOpeningCandidate] = []
        #if os(iOS) && canImport(RoomPlan)
        if #available(iOS 17.0, *) {
            enumerated = (try? RoomPlanReviewDeriver
                .enumerateOpenings(processedPayload: data)) ?? []
        }
        #endif
        let existing = snapshot.openingReview?.openings ?? []
        return OpeningReviewEditor.merge(
            existing: existing,
            enumerated: enumerated
        )
    }

    /// Commits a revised opening-review document (issue #231). The
    /// store enforces revision/session/space binding and evidence-link
    /// congruence.
    func commitOpeningReview(
        _ openings: [RoomOpeningCandidate]
    ) async -> Bool {
        guard let store = workingSetStore else { return false }
        let snapshot = await store.snapshot()
        guard let sessionID = snapshot.captureSessionIDs.first,
              let spaceID = snapshot.coordinateSpaceIDs.first
        else {
            return false
        }
        do {
            let document = try OpeningReviewDocument(
                captureRevisionID:
                    snapshot.identity.captureRevisionID,
                captureSessionID: sessionID,
                coordinateSpaceID: spaceID,
                openings: openings
            )
            let package = try OpeningReviewPackageBuilder.build(
                document: document
            )
            try await store.commitOpeningReview(package)
            refreshReviewWorkspace()
            return true
        } catch {
            workingSetStatus = String(localized: "The opening review could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
            return false
        }
    }

    /// Removes an unreferenced optional evidence frame for privacy
    /// (issue #241). The store refuses end-boundary and referenced
    /// frames; on success the workspace is rebuilt so the gallery
    /// reflects the removal immediately.
    func removeEvidenceFrameForPrivacy(
        _ frameID: EvidenceFrameID
    ) async {
        guard let store = workingSetStore else { return }
        do {
            try await store.removeEvidenceFrame(frameID)
            await refreshQuality(
                store: store,
                generation: captureGeneration
            )
            refreshReviewWorkspace()
            workingSetStatus = String(localized: "Evidence frame removed")
        } catch {
            workingSetStatus = String(localized: "This frame is retained: it is closing or referenced evidence") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Loads the read-only persisted-capture workspace for a validated
    /// finalized record (issue #294). Runs off the main actor.
    func loadPersistedWorkspace(
        _ record: PersistedCaptureRecord
    ) {
        // #309: the read-only open had no in-flight guard at all —
        // every tap re-launched the decode. Guard + mark the row busy.
        guard state == .idle || state == .finalized
                || state == .exported,
              !persistedWorkspaceLoadInFlight
        else {
            return
        }
        persistedWorkspaceLoadInFlight = true
        operationTargetRevisionID = record.captureRevisionID
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.persistedWorkspaceLoadInFlight = false }
            let loaded = await Task.detached(
                priority: .userInitiated
            ) {
                () -> (
                    CaptureReviewWorkspaceModel?,
                    [RoomPlanBindableObject]
                ) in
                guard let directory = record.finalizedDirectory
                else {
                    return (nil, [])
                }
                guard let manifest = record.finalizedValidation?
                    .manifest
                else {
                    return (nil, [])
                }
                return (
                    CaptureReviewWorkspaceLoader.loadPersisted(
                        directory: directory,
                        manifest: manifest
                    ),
                    // #408/#409: bindables from the persisted
                    // bundle's captured-room.json — the read-only
                    // 3D scene and survey targets over the same
                    // committed surface list.
                    Self.loadRoomPlanObjects(
                        rootDirectory: directory
                    )
                )
            }.value
            self.persistedWorkspace = loaded.0
            self.persistedWorkspaceRoomPlanObjects = loaded.1
            let model = loaded.0
            if model == nil {
                self.workingSetStatus = String(localized: "The persisted capture could not be opened read-only")
            }
        }
    }

    /// Metadata-only comparison of the adopted finalized revision with
    /// its parent (issue #221). Loads both manifests' decoded contents.
    func compareAdoptedRevisionWithParent()
        async -> CaptureRevisionComparison?
    {
        guard let manifest = validationReport?.manifest,
              let parentID = manifest.parentRevisionID,
              let store = persistedStore
        else {
            return nil
        }
        guard let finalizedRevision else { return nil }
        let childDirectory = finalizedRevision.directory
        let parentRecord = await Task.detached(
            priority: .userInitiated
        ) {
            store.validatedRecord(captureRevisionID: parentID)
        }.value
        guard let parentDirectory = parentRecord?.finalizedDirectory
        else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            () -> CaptureRevisionComparison? in
            guard
                let parent = try? PersistedCaptureContentsLoader
                    .load(directory: parentDirectory),
                let child = try? PersistedCaptureContentsLoader
                    .load(directory: childDirectory)
            else {
                return nil
            }
            return CaptureRevisionComparator.compare(
                parent: parent,
                child: child
            )
        }.value
    }

    /// Inspects the retained working set of the current failed capture
    /// (issue #224). Runs off the main actor and publishes the result.
    func inspectFailedCapture() {
        guard state == .failed,
              let store = workingSetStore
        else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let failureCode = self.lastFailure
            let inspection = await Task.detached(
                priority: .userInitiated
            ) { () async -> FailedCaptureInspection in
                let root = await store.rootDirectory
                let identity = await store.identity
                let events: [CaptureResourceEvent]
                if let report = try? await store.evaluateQuality(
                    requirements: self.qualityRequirements
                ) {
                    events = report.resourceEvents
                } else {
                    events = []
                }
                return FailedCaptureInspector.inspect(
                    workingSetRoot: root,
                    captureRevisionID:
                        identity.captureRevisionID,
                    failureCode: failureCode,
                    resourceEvents: events
                )
            }.value
            guard self.state == .failed else { return }
            self.failedInspection = inspection
        }
    }

    /// Writes the diagnostic package for the current failed capture and
    /// returns its URL for sharing (issue #224). The package is a
    /// bounded JSON report — not a capture bundle — listing retained
    /// files plus decoded session/authority context.
    func exportFailedCaptureDiagnostics() async -> URL? {
        // #309: exporting a diagnostic package is a real IO
        // operation — guard against concurrent taps and surface it in
        // the busy-operation set.
        guard state == .failed,
              !exportDiagnosticsInFlight
        else { return nil }
        exportDiagnosticsInFlight = true
        defer { exportDiagnosticsInFlight = false }
        let inspection: FailedCaptureInspection?
        if let failedInspection {
            inspection = failedInspection
        } else {
            guard let store = workingSetStore else {
                return nil
            }
            let failureCode = self.lastFailure
            inspection = await Task.detached(
                priority: .userInitiated
            ) { () async -> FailedCaptureInspection in
                let root = await store.rootDirectory
                let identity = await store.identity
                let events: [CaptureResourceEvent]
                if let report = try? await store.evaluateQuality(
                    requirements: self.qualityRequirements
                ) {
                    events = report.resourceEvents
                } else {
                    events = []
                }
                return FailedCaptureInspector.inspect(
                    workingSetRoot: root,
                    captureRevisionID:
                        identity.captureRevisionID,
                    failureCode: failureCode,
                    resourceEvents: events
                )
            }.value
            self.failedInspection = inspection
        }
        guard let inspection,
              let captureRoot =
                Self.captureRootDirectory()
        else {
            return nil
        }
        let stem = inspection.captureRevisionID?.description
            ?? "failed-capture"
        do {
            return try CaptureDiagnosticPackageWriter.write(
                inspection: inspection,
                captureRoot: captureRoot,
                stem: stem
            )
        } catch {
            workingSetStatus = String(localized: "The diagnostic package could not be written") + " [" + Self.persistenceDiagnostic(error) + "]"
            return nil
        }
    }

    // MARK: derived export (issues #306 / #318)

    /// Where a finalized revision's directory, digest, manifest and
    /// display name come from for a derived export — the currently
    /// adopted revision when it matches, otherwise the validated
    /// library record for the revision.
    private struct DerivedExportContext {
        let directory: URL
        let bundleDigest: EvidenceSHA256
        let manifest: BundleManifest
        let displayName: String?
    }

    private func derivedExportContext(
        _ revisionID: CaptureRevisionID
    ) async -> DerivedExportContext? {
        if let finalizedRevision,
           finalizedRevision.captureRevisionID == revisionID,
           let manifest = validationReport?.manifest
        {
            return DerivedExportContext(
                directory: finalizedRevision.directory,
                bundleDigest: finalizedRevision.bundleDigest,
                manifest: manifest,
                displayName:
                    libraryMetadata.revisions[
                        revisionID.description
                    ]?.displayName
            )
        }
        guard let store = persistedStore else { return nil }
        let record = await Task.detached(
            priority: .userInitiated
        ) {
            store.validatedRecord(captureRevisionID: revisionID)
        }.value
        guard let directory = record?.finalizedDirectory,
              let validation = record?.finalizedValidation
        else {
            return nil
        }
        return DerivedExportContext(
            directory: directory,
            bundleDigest: validation.bundleDigest,
            manifest: validation.manifest,
            displayName:
                libraryMetadata.revisions[
                    revisionID.description
                ]?.displayName
        )
    }

    /// Availability probe for the derived-export sheets (issue #306):
    /// which geometry sources the finalized bundle carries, plus the
    /// preview-bearing evidence frames the report may offer for
    /// explicit opt-in.
    func derivedExportInfo(
        _ revisionID: CaptureRevisionID
    ) async -> DerivedExportInfo? {
        guard let context = await derivedExportContext(revisionID)
        else { return nil }
        return await Task.detached(
            priority: .userInitiated
        ) { () -> DerivedExportInfo in
            let manifest = context.manifest
            let declared = Set(manifest.files.map(\.path))
            var anchorCount = 0
            if declared.contains(MeshEvidencePackage.indexPath),
               let data = try? Data(
                   contentsOf: context.directory
                       .appendingPathComponent(
                           MeshEvidencePackage.indexPath,
                           isDirectory: false
                       )
               ),
               let index = try? JSONDecoder().decode(
                   MeshAnchorEvidenceIndex.self,
                   from: data
               )
            {
                anchorCount = index.anchors.count
            }
            var roomPlanAvailable = false
            var usdzAvailable = false
            #if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
            roomPlanAvailable =
                DerivedRoomPlanExportSupport.isAvailable(
                    manifest: manifest,
                    bundleDirectory: context.directory
                )
            usdzAvailable = roomPlanAvailable
            #endif
            let evidenceOptions =
                SurveyReportEvidenceEnumerator.options(
                    bundleDirectory: context.directory,
                    manifest: manifest
                )
            return DerivedExportInfo(
                roomPlanProcessedAvailable: roomPlanAvailable,
                usdzAvailable: usdzAvailable,
                arMeshAvailable: anchorCount > 0,
                arMeshAnchorCount: anchorCount,
                evidenceOptions: evidenceOptions
            )
        }.value
    }

    /// Runs a derived 3D export for a finalized capture (issue #306).
    /// The result is written under `<captureRoot>/derived-exports/` —
    /// never inside the canonical `finalized/` or `exports/` roots.
    func exportDerived3D(
        _ revisionID: CaptureRevisionID,
        _ selection: Derived3DExportSelection
    ) async -> DerivedExportOutcome {
        guard let context =
            await derivedExportContext(revisionID),
              let captureRoot = Self.captureRootDirectory()
        else {
            return DerivedExportOutcome(
                files: [],
                error: String(localized: "The finalized capture is no longer available")
            )
        }
        return await Task.detached(
            priority: .userInitiated
        ) { () -> DerivedExportOutcome in
            do {
                let result: Derived3DExportResult
                switch selection.source {
                case .arMeshAnchors:
                    result = try DerivedExportRunner.exportMesh(
                        bundleDirectory: context.directory,
                        bundleDigest: context.bundleDigest,
                        captureRoot: captureRoot,
                        format: selection.format,
                        source: .arMeshAnchors
                    )
                case .roomPlanProcessed:
                    if selection.format == .usdz {
                        #if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
                        if #available(iOS 17.0, *) {
                            result =
                                try DerivedExportRunner.exportUSDZ(
                                    bundleDirectory:
                                        context.directory,
                                    bundleDigest:
                                        context.bundleDigest,
                                    captureRoot: captureRoot
                                ) { destination in
                                    try DerivedRoomPlanExportSupport
                                        .writeUSDZ(
                                            bundleDirectory:
                                                context.directory,
                                            manifest:
                                                context.manifest,
                                            to: destination
                                        )
                                }
                        } else {
                            throw DerivedExportError
                                .unsupportedCombination(
                                    reason:
                                        "USDZ export requires iOS 17 RoomPlan"
                                )
                        }
                        #else
                        throw DerivedExportError
                            .unsupportedCombination(
                                reason:
                                    "USDZ export requires RoomPlan on iOS"
                            )
                        #endif
                    } else {
                        #if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
                        if #available(iOS 17.0, *) {
                            let objects =
                                try DerivedRoomPlanExportSupport
                                    .bindableObjects(
                                        bundleDirectory:
                                            context.directory,
                                        manifest: context.manifest
                                    )
                            result =
                                try DerivedExportRunner.exportMesh(
                                    bundleDirectory:
                                        context.directory,
                                    bundleDigest:
                                        context.bundleDigest,
                                    captureRoot: captureRoot,
                                    format: selection.format,
                                    source: .roomPlanProcessed,
                                    roomPlanObjects: objects
                                )
                        } else {
                            throw DerivedExportError
                                .unsupportedCombination(
                                    reason:
                                        "RoomPlan-derived exports require iOS 17 RoomPlan"
                                )
                        }
                        #else
                        throw DerivedExportError
                            .unsupportedCombination(
                                reason:
                                    "RoomPlan-derived exports require RoomPlan on iOS"
                            )
                        #endif
                    }
                }
                return DerivedExportOutcome(
                    files: [
                        result.primaryFileURL,
                        result.provenanceFileURL,
                    ],
                    error: nil
                )
            } catch let error as DerivedExportError {
                return DerivedExportOutcome(
                    files: [],
                    error: error.reason
                )
            } catch {
                return DerivedExportOutcome(
                    files: [],
                    error: error.localizedDescription
                )
            }
        }.value
    }

    /// Runs the field-survey report export (issue #318). Only the
    /// preview frames the operator explicitly selected are embedded;
    /// the canonical bundle is never modified.
    func exportSurveyReport(
        _ revisionID: CaptureRevisionID,
        _ selection: SurveyReportSelection
    ) async -> DerivedExportOutcome {
        guard let context =
            await derivedExportContext(revisionID),
              let captureRoot = Self.captureRootDirectory()
        else {
            return DerivedExportOutcome(
                files: [],
                error: String(localized: "The finalized capture is no longer available")
            )
        }
        return await Task.detached(
            priority: .userInitiated
        ) { () -> DerivedExportOutcome in
            var plan: RoomPlanPreviewModel? = nil
            #if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
            if #available(iOS 17.0, *) {
                if let data = try? DerivedRoomPlanExportSupport
                    .processedRoomData(
                        bundleDirectory: context.directory,
                        manifest: context.manifest
                    )
                {
                    plan = try? RoomPlanReviewDeriver
                        .planPreview(processedPayload: data)
                }
            }
            #endif

            let options =
                SurveyReportEvidenceEnumerator.options(
                    bundleDirectory: context.directory,
                    manifest: context.manifest
                )
            var images: [SurveyReportEvidenceImage] = []
            for option in options
            where selection.evidenceFrameIDs.contains(option.id)
            {
                guard let jpeg =
                    SurveyReportImageConverter.jpegData(
                        from: option.previewFileURL
                    )
                else { continue }
                images.append(
                    SurveyReportEvidenceImage(
                        frameID: option.frameID,
                        caption:
                            option.frameID.description
                                + "  t="
                                + String(
                                    format: "%.1f",
                                    option.sessionTimestampSeconds
                                )
                                + "s",
                        jpegData: jpeg
                    )
                )
            }

            do {
                let result = try SurveyReportRunner.export(
                    bundleDirectory: context.directory,
                    bundleDigest: context.bundleDigest,
                    captureRoot: captureRoot,
                    displayName: context.displayName,
                    planPreview: plan,
                    evidenceImages: images,
                    language: selection.language
                )
                return DerivedExportOutcome(
                    files: result.files,
                    error: nil
                )
            } catch let error as DerivedExportError {
                return DerivedExportOutcome(
                    files: [],
                    error: error.reason
                )
            } catch {
                return DerivedExportOutcome(
                    files: [],
                    error: error.localizedDescription
                )
            }
        }.value
    }

    /// Loads the handoff destinations for `sendCaptureToHTDT`
    /// (#225): the system file/share destination plus any
    /// operator-configured ingestion endpoints from
    /// `<captureRoot>/handoff-destinations.json`.
    func refreshHandoffDestinations() {
        var destinations = [
            HTDTHandoffDestination(
                name: String(localized: "Share archive file"),
                kind: .shareSheet
            )
        ]
        if let root = Self.captureRootDirectory() {
            // #379: QR-paired, identity-pinned receivers are named
            // destinations; configured raw endpoints remain as
            // unpinned fallbacks.
            if let paired = try? PairedHTDTDestinationStore(
                captureRoot: root
            ).activeDestinations() {
                destinations.append(
                    contentsOf: paired.map(\.handoffDestination)
                )
            }
            let url = root.appendingPathComponent(
                "handoff-destinations.json",
                isDirectory: false
            )
            if let data = try? Data(contentsOf: url),
               let configured = try? JSONDecoder().decode(
                    [HTDTHandoffDestination].self,
                    from: data
               )
            {
                for destination in configured
                where destination.kind == .endpoint {
                    destinations.append(destination)
                }
            }
        }
        handoffDestinations = destinations
    }

    /// Explicit operator Send-to-HTDT action (issue #225). Sends the
    /// validated archive bytes — the same `.htdtcapture` the share
    /// flow produces — and records an append-only receipt bound to the
    /// exact `capture_revision_id` and bundle digest. Never uploads
    /// silently: the destination is chosen per send and every attempt
    /// is receipted so it can be retried without weakening the digest
    /// binding. For share-sheet destinations the UI layer reports the
    /// system sheet's real outcome via `shareSheetOutcome`; a receipt
    /// of `delivered` is written only for a completed activity.
    func sendCaptureToHTDT(
        destination: HTDTHandoffDestination,
        shareSheetOutcome: HTDTShareSheetOutcome? = nil
    ) async {
        guard state == .finalized || state == .exported,
              let archiveURL = exportURL,
              let manifest = validationReport?.manifest,
              let finalizedRevision
        else {
            workingSetStatus = String(localized: "Prepare the validated archive first, then send it")
            return
        }
        guard let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let receiptStore = HTDTHandoffReceiptStore(
            captureRoot: captureRoot
        )
        let bundleDigest = finalizedRevision.bundleDigest

        // Digest-preserving check: the archive bytes must hash to the
        // recorded archive digest AND carry the finalized bundle digest.
        let archiveSHA: EvidenceSHA256
        let archiveBytes: Int64
        do {
            let data = try Data(contentsOf: archiveURL)
            archiveSHA = EvidenceIntegrity.sha256(of: data)
            archiveBytes = Int64(data.count)
        } catch {
            workingSetStatus = String(localized: "The export archive could not be read for handoff")
            return
        }

        switch destination.kind {
        case .shareSheet:
            // The UI layer presents the system share sheet over
            // archiveURL and reports the sheet's real completion: the
            // handoff is `delivered` only when an activity completed,
            // so a dismissed sheet never writes a delivery claim.
            let outcome = shareSheetOutcome ?? .cancelled
            let receiptOutcome: String
            let receiptDetail: String
            let outcomeStatus: String
            switch outcome {
            case .completed:
                receiptOutcome = "delivered"
                receiptDetail = "operator_shared_via_system_sheet"
                outcomeStatus = String(
                    localized: "Capture handed off to HTDT; receipt saved"
                )
            case .cancelled:
                receiptOutcome = "cancelled"
                receiptDetail = "operator_cancelled_share_sheet"
                outcomeStatus = String(
                    localized: "Share cancelled; nothing was delivered to HTDT"
                )
            case .failed(let message):
                receiptOutcome = "failed"
                receiptDetail = "share_sheet_error: \(message)"
                outcomeStatus = String(
                    localized: "The share sheet reported an error; nothing was delivered to HTDT"
                )
            }
            let receipt = HTDTHandoffReceipt(
                receiptID: UUID().uuidString.lowercased(),
                captureRevisionID: manifest.captureRevisionID,
                captureSeriesID: manifest.captureSeriesID,
                bundleDigest: bundleDigest.value,
                archiveSHA256: archiveSHA.value,
                archiveByteCount: archiveBytes,
                destination: destination,
                initiatedAtUTC: BundleTimestamp.utcString(
                    from: Date()
                ),
                outcome: receiptOutcome,
                detail: receiptDetail
            )
            do {
                try receiptStore.append(receipt)
            } catch {
                workingSetStatus = String(localized: "The handoff receipt could not be saved")
            }
            handoffReceipts = (try? receiptStore.receipts(
                for: manifest.captureRevisionID
            )) ?? [receipt]
            workingSetStatus = outcomeStatus

        case .endpoint:
            // #387: endpoint sends are durable jobs — recorded before
            // bytes move, idempotent at the receiver via the stable
            // delivery id, and retried under the queue's policy rather
            // than a one-shot fire-and-forget upload.
            guard let urlString = destination.url,
                  URL(string: urlString) != nil
            else {
                workingSetStatus = String(localized: "The destination has no valid HTTPS endpoint")
                return
            }
            let queue = HTDTDeliveryQueue(
                captureRoot: captureRoot
            )
            let pairedID = (try? PairedHTDTDestinationStore(
                captureRoot: captureRoot
            ).activeDestinations())?.first(where: {
                $0.endpointURL == urlString
            })?.destinationID
            let missionID = activeMissionRecordID.flatMap { id in
                missionRecords.first(where: {
                    $0.recordID == id
                        && $0.associatedCaptureRevisionIDs
                            .contains(
                                manifest.captureRevisionID
                                    .description
                            )
                })?.recordID
            }
            do {
                let job = try queue.enqueue(
                    captureRevisionID: manifest.captureRevisionID,
                    captureSeriesID: manifest.captureSeriesID,
                    bundleDigest: bundleDigest,
                    archiveSHA256: archiveSHA,
                    archiveByteCount: archiveBytes,
                    archiveURL: archiveURL,
                    destination: destination,
                    pairedDestinationID: pairedID,
                    missionRecordID: missionID,
                    compatibilitySummary: nil
                )
                if let missionID {
                    try? missionInboxStore?.associateDeliveryJob(
                        recordID: missionID,
                        deliveryJobID: job.deliveryJobID
                    )
                }
                let jobs = await queue.processDueJobs(
                    receiptStore: receiptStore,
                    onRepairPlan: { plan, receiptID in
                        Task { @MainActor in
                            self.recordRepairTaskPlan(
                                plan,
                                receiptID: receiptID ?? ""
                            )
                        }
                    }
                )
                deliveryJobs = jobs
                let updated = jobs.first {
                    $0.deliveryJobID == job.deliveryJobID
                }
                handoffReceipts = (try? receiptStore.receipts(
                    for: manifest.captureRevisionID
                )) ?? handoffReceipts
                switch updated?.state {
                case .deliveredStaged:
                    workingSetStatus = String(localized: "Capture delivered and staged at the receiver; receipt saved")
                case .rejected:
                    workingSetStatus = String(localized: "The receiver rejected the bundle semantically; it will not be retried")
                case .blocked:
                    workingSetStatus = String(localized: "Delivery is blocked and needs an operator decision (see Deliveries)")
                default:
                    workingSetStatus = String(localized: "Delivery queued; it will retry under the queue's policy (see Deliveries)")
                }
                refreshMissionDeliveryStores()
            } catch {
                workingSetStatus = String(localized: "The delivery could not be queued")
            }
        }
    }

    /// Refreshes the mission inbox, paired destinations and delivery
    /// queue into the published props the home screen renders (#386/
    /// #379/#387).
    private func refreshMissionDeliveryStores() {
        guard let captureRoot = Self.captureRootDirectory() else {
            missionRecords = []
            activeMissionRecordID = nil
            pairedDestinations = []
            deliveryJobs = []
            return
        }
        let inbox = HTDTMissionInboxStore(captureRoot: captureRoot)
        // #456: advance each record's lifecycle from the associations
        // already on disk — an associated committed artifact is
        // `finalized`, a staged send is `delivered`.
        _ = try? inbox.reconcileLifecycles(
            inventory: persistedInventory,
            deliveryQueue: HTDTDeliveryQueue(
                captureRoot: captureRoot
            )
        )
        missionRecords = (try? inbox.records()) ?? []
        let activeRecord = try? inbox.activeMissionRecord()
        activeMissionRecordID = activeRecord?.recordID
        pairedDestinations = (try? PairedHTDTDestinationStore(
            captureRoot: captureRoot
        ).load().destinations) ?? []
        deliveryJobs = (try? HTDTDeliveryQueue(
            captureRoot: captureRoot
        ).jobs()) ?? []
        crossRevisionRegistrations =
            (try? CrossRevisionRegistrationStore(
                captureRoot: captureRoot
            ).load().registrations) ?? []
        // #397: replay each mission's ledger into an evaluation —
        // plan compatibility is required to evaluate, so a record
        // whose embedded plan cannot decode simply yields no
        // evaluation rather than a guessed one.
        let ledgerStore = MissionProgressLedgerStore(
            captureRoot: captureRoot
        )
        var evaluations:
            [String: MissionProgressEvaluation] = [:]
        for record in missionRecords {
            guard let plan = try? inbox.plan(for: record),
                  let evaluation = try? ledgerStore.evaluate(
                      record: record,
                      plan: plan
                  )
            else {
                continue
            }
            evaluations[record.recordID] = evaluation
        }
        missionProgressEvaluations = evaluations
    }

    private var missionInboxStore: HTDTMissionInboxStore? {
        Self.captureRootDirectory().map {
            HTDTMissionInboxStore(captureRoot: $0)
        }
    }

    private var pairedDestinationStore: PairedHTDTDestinationStore? {
        Self.captureRootDirectory().map {
            PairedHTDTDestinationStore(captureRoot: $0)
        }
    }

    private var deliveryQueueStore: HTDTDeliveryQueue? {
        Self.captureRootDirectory().map {
            HTDTDeliveryQueue(captureRoot: $0)
        }
    }

    private var crossRevisionRegistrationStore:
        CrossRevisionRegistrationStore?
    {
        Self.captureRootDirectory().map {
            CrossRevisionRegistrationStore(captureRoot: $0)
        }
    }

    private var missionProgressLedgerStore:
        MissionProgressLedgerStore?
    {
        Self.captureRootDirectory().map {
            MissionProgressLedgerStore(captureRoot: $0)
        }
    }

    /// Sets or clears the operator's preferred head for a branched
    /// series (issue #396). App-local metadata only — the choice
    /// never mutates any revision bundle.
    func preferRevisionHead(
        _ seriesID: CaptureSeriesID,
        _ revisionID: CaptureRevisionID?
    ) {
        guard let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let store = CaptureLibraryMetadataStore(
            captureRoot: captureRoot
        )
        do {
            if let revisionID {
                try store.updatePreferredHead(
                    seriesID,
                    revisionID: revisionID
                )
            } else {
                try store.clearPreferredHead(seriesID)
            }
            libraryMetadata = try store.load()
        } catch {
            workingSetStatus = String(localized: "The preferred head could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// The declared field datum of a persisted finalized revision
    /// (#395): the shared physical anchor a registration is
    /// established from. nil when the revision never recorded one or
    /// its bytes no longer decode — the caller fails closed.
    private func fieldDatumDocument(
        for record: PersistedCaptureRecord
    ) -> RoomFieldDatumDocument? {
        guard let directory = record.finalizedDirectory
        else {
            return nil
        }
        let url = directory.appendingPathComponent(
            RoomFieldDatumPackage.path,
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            RoomFieldDatumDocument.self,
            from: data
        )
    }

    private func coordinateSpaceID(
        for record: PersistedCaptureRecord
    ) -> CoordinateSpaceID? {
        record.finalizedValidation?.manifest.coordinateSpaceIDs.first
    }

    /// Computes the inspectable shared-field-datum fit for a revision
    /// pair (#395) without persisting anything — the UI shows the
    /// residuals before any accept decision.
    func proposeRevisionAlignment(
        _ sourceRevisionID: CaptureRevisionID,
        _ targetRevisionID: CaptureRevisionID
    ) async -> CrossRevisionRegistrationSolve? {
        guard let source = persistedInventory.captures.first(where: {
            $0.captureRevisionID == sourceRevisionID
        }), let target = persistedInventory.captures.first(where: {
            $0.captureRevisionID == targetRevisionID
        }), let sourceDatum = fieldDatumDocument(for: source),
            let targetDatum = fieldDatumDocument(for: target),
            let store = crossRevisionRegistrationStore,
            let correspondences =
                try? CrossRevisionCorrespondenceGather
                    .fromSharedFieldDatums(
                        source: sourceDatum,
                        target: targetDatum
                    )
        else {
            return nil
        }
        return try? store.propose(
            correspondences: correspondences,
            scalePolicy: .rigidOnly
        )
    }

    /// Accepts the shared-field-datum registration for the pair as
    /// immutable authority (#395): re-solves from the same declared
    /// correspondences, refuses when a registration already binds the
    /// directed pair, and never rewrites either revision.
    @discardableResult
    func acceptRevisionAlignment(
        _ sourceRevisionID: CaptureRevisionID,
        _ targetRevisionID: CaptureRevisionID
    ) async -> CrossRevisionRegistration? {
        guard let source = persistedInventory.captures.first(where: {
            $0.captureRevisionID == sourceRevisionID
        }), let target = persistedInventory.captures.first(where: {
            $0.captureRevisionID == targetRevisionID
        }), let sourceDatum = fieldDatumDocument(for: source),
            let targetDatum = fieldDatumDocument(for: target),
            let sourceSpace = coordinateSpaceID(for: source),
            let targetSpace = coordinateSpaceID(for: target),
            let store = crossRevisionRegistrationStore,
            let correspondences =
                try? CrossRevisionCorrespondenceGather
                    .fromSharedFieldDatums(
                        source: sourceDatum,
                        target: targetDatum
                    )
        else {
            return nil
        }
        let accepted = try? store.accept(
            sourceRevisionID: sourceRevisionID,
            sourceCoordinateSpaceID: sourceSpace,
            targetRevisionID: targetRevisionID,
            targetCoordinateSpaceID: targetSpace,
            mechanism: .sharedFieldDatum,
            correspondences: correspondences,
            scalePolicy: .rigidOnly,
            evidenceRefs: [
                "path:\(RoomFieldDatumPackage.path)"
            ]
        )
        if accepted != nil {
            crossRevisionRegistrations =
                (try? store.load().registrations)
                    ?? crossRevisionRegistrations
        }
        return accepted
    }

    /// Commits `revision/registrations.json` into the working set
    /// (#395): when accepted registrations name this revision, the
    /// exported bundle carries the transform authority as a declared
    /// supplemental document for HTDT. Best-effort — a commit
    /// failure never blocks finalization; the app-local registry
    /// stays the standing authority.
    private func commitCrossRevisionRegistrations(
        _ store: CaptureWorkingSetStore
    ) async {
        guard let revisionID = workingSetIdentity?.captureRevisionID,
              let registrationStore = crossRevisionRegistrationStore,
              let document = try? CrossRevisionRegistrationBundleDocument(
                captureRevisionID: revisionID,
                registrations: registrationStore.load().registrations
                    .filter {
                        $0.sourceRevisionID == revisionID
                            || $0.targetRevisionID == revisionID
                    }
              ),
              !document.registrations.isEmpty,
              let package = try? CrossRevisionRegistrationPackageBuilder
                .build(document: document),
              let supplemental = try? WorkingSetSupplementalDocument(
                path: CrossRevisionRegistrationPackage.path,
                data: package.data,
                declaration: package.payloadDeclaration
              )
        else {
            return
        }
        try? await store.replaceSupplementalDocument(supplemental)
    }

    /// Ingests a finalized revision's task-plan status document into
    /// the mission progress ledger (#397): exact plan compatibility
    /// gates acceptance, and the ledger is app-local — failures never
    /// disturb the committed revision.
    private func ingestMissionProgress(
        finalizedDirectory: URL,
        missionRecordID: String
    ) {
        guard let inbox = missionInboxStore,
              let ledger = missionProgressLedgerStore,
              let record = try? inbox.record(id: missionRecordID),
              let plan = try? inbox.plan(for: record)
        else {
            return
        }
        let statusURL = finalizedDirectory.appendingPathComponent(
            "session/task-plan-status.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: statusURL),
              let statusDocument = try? JSONDecoder().decode(
                CaptureTaskPlanStatusDocument.self,
                from: data
              )
        else {
            return
        }
        try? ledger.ingestStatusDocument(
            statusDocument,
            for: record,
            plan: plan,
            sourceStatusSHA256: EvidenceIntegrity.sha256(of: data)
        )
    }

    /// Explicit mission-level waiver for a plan item (#397) —
    /// auditable and distinct from a revision-local skip.
    func waiveMissionItem(
        _ recordID: String,
        _ itemID: String,
        _ note: String?
    ) async {
        guard let inbox = missionInboxStore,
              let ledger = missionProgressLedgerStore,
              let record = try? inbox.record(id: recordID),
              let plan = try? inbox.plan(for: record)
        else {
            return
        }
        do {
            try ledger.waive(
                itemID: itemID,
                for: record,
                plan: plan,
                note: note
            )
            refreshMissionDeliveryStores()
        } catch {
            workingSetStatus = String(localized: "The mission waiver could not be recorded") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Inbox import shared by every mission entry point (#386/#457):
    /// envelopes and bare plans land as mission records with the
    /// dedup/supersession contract intact.
    private func importMissionEnvelopeData(_ data: Data) throws {
        guard let store = missionInboxStore else {
            throw RepairTaskError.unreadableDocument
        }
        let outcome = try store.importMission(data: data)
        refreshMissionDeliveryStores()
        switch outcome {
        case .imported:
            workingSetStatus = String(localized: "Mission imported")
        case .duplicate:
            workingSetStatus = String(localized: "This mission is already in the inbox")
        case .superseding:
            workingSetStatus = String(localized: "Mission imported; the replaced mission is marked superseded")
        }
    }

    /// Imports a mission package file — envelope or bare task plan —
    /// into the inbox (issue #386).
    func importMissionPackage(_ url: URL) async {
        let accessing =
            url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard missionInboxStore != nil,
              let data = try? Data(contentsOf: url)
        else {
            workingSetStatus = String(localized: "The mission package could not be read")
            return
        }
        do {
            try importMissionEnvelopeData(data)
        } catch {
            workingSetStatus = String(
                format: String(localized: "Mission import failed: %@"),
                String(describing: error)
            )
        }
    }

    /// Starts or resumes a mission record: dependencies are evaluated
    /// before Start, a single mission may be active at a time, and
    /// the embedded plan becomes the capture's task plan (#386).
    /// Launch routing (issue #410): the mission workflow never assumes
    /// spatial capture — the boundary classifies the record into a
    /// spatial, field-return, artifact-review, or unsupported route.
    func startMission(_ recordID: String) async {
        guard let store = missionInboxStore else { return }
        let decision = missionLaunchDecision(
            recordID: recordID
        )
        switch decision.route {
        case .fieldReturn:
            // Start still activates the record — the non-spatial
            // path continues in the field-return workspace, never
            // in a scan session (#410).
            do {
                _ = try store.startMission(
                    recordID: recordID,
                    inventory: persistedInventory,
                    deliveryQueue: deliveryQueueStore,
                    activeCatalog: equipmentCatalog
                )
            } catch {
                refreshMissionDeliveryStores()
                workingSetStatus = String(
                    format: String(
                        localized: "Mission cannot start: %@"
                    ),
                    String(describing: error)
                )
                return
            }
            _ = await openFieldReturnWorkspace(
                missionRecordID: recordID
            )
            refreshMissionDeliveryStores()
            workingSetStatus = String(
                localized:
                    "Mission activated — its tasks need no spatial capture; continue in Field return"
            )
            return
        case .artifactReview:
            workingSetStatus = String(
                localized:
                    "Mission is past field work — its captures are reviewable from the inbox"
            )
            return
        case .unsupported(let reason):
            workingSetStatus = missionLaunchUnsupportedText(
                reason
            )
            return
        case .spatialCapture:
            break
        }
        do {
            let resume = try store.startMission(
                recordID: recordID,
                inventory: persistedInventory,
                deliveryQueue: deliveryQueueStore,
                activeCatalog: equipmentCatalog
            )
            taskPlan = resume.planImport.plan
            taskPlanSHA256 = resume.planImport.planSHA256
            refreshMissionDeliveryStores()
            beginCapture()
        } catch {
            refreshMissionDeliveryStores()
            workingSetStatus = String(
                format: String(localized: "Mission cannot start: %@"),
                String(describing: error)
            )
        }
    }

    /// Mission launch routing (issue #410): re-decodes the record's
    /// embedded plan and classifies its items spatial vs field —
    /// the route a mission takes is decided at the boundary, never
    /// inside whichever surface Start was pressed on.
    func missionLaunchDecision(
        recordID: String
    ) -> MissionLaunchDecision {
        guard let store = missionInboxStore,
              let record = try? store.record(id: recordID)
        else {
            return MissionLaunchDecision(
                route: .unsupported(reason: .planUnavailable)
            )
        }
        let plan = try? store.plan(for: record)
        return MissionLaunchRouter.route(
            for: record,
            plan: plan,
            spatialAvailable: capabilities
                .roomPlanMeshEligible
        )
    }

    private func missionLaunchUnsupportedText(
        _ reason: MissionLaunchUnsupportedReason
    ) -> String {
        switch reason {
        case .spatialCaptureUnavailable:
            return String(
                localized:
                    "Mission requires spatial capture, which is unavailable on this device"
            )
        case .planUnavailable:
            return String(
                localized:
                    "Mission cannot start: its task plan could not be read"
            )
        case .noExecutableTasks:
            return String(
                localized:
                    "Mission has no tasks this device can execute"
            )
        }
    }

    /// Clears the active-mission pointer and the plan context —
    /// records and their captures are never touched (#386).
    func deactivateMission() async {
        try? missionInboxStore?.pauseActiveMission()
        taskPlan = nil
        taskPlanSHA256 = nil
        refreshMissionDeliveryStores()
    }

    /// Hides a record from the default inbox without deleting it.
    func archiveMission(_ recordID: String) async {
        try? missionInboxStore?.setLifecycle(
            recordID: recordID,
            .archived
        )
        refreshMissionDeliveryStores()
    }

    /// Closes a mission whose field work or delivery already landed
    /// (#456) — the explicit counterpart of the derived states.
    func completeMission(_ recordID: String) async {
        guard let store = missionInboxStore else { return }
        do {
            try store.completeMission(recordID: recordID)
        } catch {
            workingSetStatus = String(
                format: String(
                    localized: "Mission cannot be completed: %@"
                ),
                String(describing: error)
            )
        }
        refreshMissionDeliveryStores()
    }

    /// Persists the operator's mission annotation (#463) — operator
    /// truth only, never written into the mission payload.
    func updateMissionUserNote(
        _ recordID: String,
        _ note: String?
    ) async {
        guard let store = missionInboxStore else { return }
        do {
            try store.setUserNote(recordID: recordID, note)
        } catch {
            workingSetStatus = String(
                localized: "The mission note could not be saved"
            )
        }
        refreshMissionDeliveryStores()
    }

    /// The dependency report the mission detail view renders before
    /// Start (#386) — declared dependencies, catalog pin, and any
    /// mission-level receiver requirement gaps against paired
    /// destinations (#374).
    func evaluateMissionDependencies(
        _ recordID: String
    ) async throws -> HTDTMissionDependencyReport {
        guard let store = missionInboxStore else {
            throw HTDTMissionInboxError.unreadableDocument
        }
        var report = try store.evaluateDependencies(
            recordID: recordID,
            inventory: persistedInventory,
            deliveryQueue: deliveryQueueStore,
            activeCatalog: equipmentCatalog
        )
        if let requirement = try? store.record(id: recordID)?
            .receiverRequirement
        {
            // Check the requirement against paired receivers: use a
            // cached snapshot when one exists (labeled), else fetch
            // live when reachable.
            let paired = try? pairedDestinationStore?
                .activeDestinations()
            var gaps: [String] = []
            var checked = false
            for destination in paired ?? [] {
                guard let url = destination.capabilityEndpointURL
                    .flatMap(URL.init)
                    ?? URL(string: destination.endpointURL)
                else { continue }
                if let snapshot = try? await HTDTCapabilityClient()
                    .fetch(
                        endpoint: url,
                        pinnedIdentity:
                            destination.pinnedIdentity
                    )
                {
                    checked = true
                    try? pairedDestinationStore?
                        .updateCachedCapability(
                            destinationID:
                                destination.destinationID,
                            snapshot: snapshot
                        )
                    let verdict = HTDTCompatibilityChecker
                        .checkMissionRequirement(
                            requirement,
                            capabilities: snapshot.document
                        )
                    if case .incompatible(let g) = verdict {
                        gaps.append(
                            contentsOf: g.map(\.detail)
                        )
                    }
                }
            }
            if !checked, (paired ?? []).isEmpty {
                gaps.append(
                    "No paired receiver to check the mission's "
                        + "receiver requirement against"
                )
            }
            report.receiverGaps = gaps
        }
        return report
    }

    /// Decodes and validates a QR pairing payload for the confirm
    /// sheet (#379).
    func pairDestinationPayload(
        _ data: Data
    ) throws -> HTDTReceiverPairingPayload {
        try HTDTReceiverPairingPayload(data: data)
    }

    /// Stores the confirmed pairing — the pinned identity now binds
    /// sends to that receiver (#379).
    func confirmPairing(
        _ payload: HTDTReceiverPairingPayload
    ) async {
        do {
            _ = try pairedDestinationStore?.pair(payload: payload)
            refreshMissionDeliveryStores()
            refreshHandoffDestinations()
            // #422: a fresh pairing is one of the receive leg's
            // refresh triggers — pull pending missions now.
            _ = await checkHTDTForMissions()
        } catch {
            workingSetStatus = String(localized: "Pairing could not be stored")
        }
    }

    func forgetDestination(_ destinationID: String) async {
        try? pairedDestinationStore?.forget(
            destinationID: destinationID
        )
        refreshMissionDeliveryStores()
        refreshHandoffDestinations()
    }

    func revokeDestination(_ destinationID: String) async {
        try? pairedDestinationStore?.revoke(
            destinationID: destinationID
        )
        refreshMissionDeliveryStores()
        refreshHandoffDestinations()
    }

    /// Fetches a paired receiver's capability document with the
    /// pairing pin and stores it as a labeled cache (#374/#379).
    func refreshEndpointCapabilities(
        _ destinationID: String
    ) async {
        guard let destination = try? pairedDestinationStore?
            .load().destinations.first(where: {
                $0.destinationID == destinationID
            })
        else { return }
        guard let url = destination.capabilityEndpointURL
            .flatMap(URL.init)
            ?? URL(string: destination.endpointURL)
        else { return }
        if let snapshot = try? await HTDTCapabilityClient().fetch(
            endpoint: url,
            pinnedIdentity: destination.pinnedIdentity
        ) {
            try? pairedDestinationStore?.updateCachedCapability(
                destinationID: destinationID,
                snapshot: snapshot
            )
            try? pairedDestinationStore?.markSeen(
                destinationID: destinationID
            )
            refreshMissionDeliveryStores()
        }
    }

    /// Delivery queue operator controls (#387).
    func deliveryRetryNow(_ jobID: String) async {
        try? deliveryQueueStore?.retryNow(jobID: jobID)
        _ = await deliveryQueueStore?.processDueJobs(
            receiptStore: handoffReceiptStore()
        )
        refreshMissionDeliveryStores()
    }

    func deliveryPause(_ jobID: String) async {
        try? deliveryQueueStore?.pause(jobID: jobID)
        refreshMissionDeliveryStores()
    }

    func deliveryResume(_ jobID: String) async {
        try? deliveryQueueStore?.resume(jobID: jobID)
        _ = await deliveryQueueStore?.processDueJobs(
            receiptStore: handoffReceiptStore()
        )
        refreshMissionDeliveryStores()
    }

    func deliveryCancel(_ jobID: String) async {
        try? deliveryQueueStore?.cancel(jobID: jobID)
        refreshMissionDeliveryStores()
    }

    func deliveryPurgePayload(_ jobID: String) async {
        try? deliveryQueueStore?.purgePayload(jobID: jobID)
        refreshMissionDeliveryStores()
    }

    private func handoffReceiptStore()
        -> HTDTHandoffReceiptStore?
    {
        Self.captureRootDirectory().map {
            HTDTHandoffReceiptStore(captureRoot: $0)
        }
    }

    /// Endpoint capability preflight (#374): fetches the
    /// destination's capability document (pinned when the endpoint is
    /// paired) and classifies the validated export's compatibility —
    /// without uploading a single archive byte.
    func preflightDestination(
        _ destination: HTDTHandoffDestination
    ) async -> HTDTCompatibilityVerdict {
        let verdict = await evaluateDestinationPreflight(
            destination
        )
        recordEndpointPreflightVerdict(verdict)
        return verdict
    }

    private func evaluateDestinationPreflight(
        _ destination: HTDTHandoffDestination
    ) async -> HTDTCompatibilityVerdict {
        guard destination.kind == .endpoint,
              let urlString = destination.url,
              let base = URL(string: urlString),
              let manifest = validationReport?.manifest
        else {
            return .unknown(
                reason: "No endpoint or no validated archive"
            )
        }
        let paired = try? pairedDestinationStore?
            .activeDestinations().first(where: {
                $0.endpointURL == urlString
            })
        guard let capabilityURL = paired
            .flatMap({ $0.capabilityEndpointURL })
            .flatMap(URL.init) ?? Optional(base)
        else {
            return .unknown(
                reason: "Endpoint has no capability URL"
            )
        }
        // Inventory the bundle without opening it: manifest-declared
        // payloads + the committed authority collection + archive
        // size are all the checker needs.
        var authorities = TheaterAuthorityCollection.empty
        if let directory = finalizedRevision?.directory
            .appendingPathComponent(
                TheaterAuthorityPackage.path,
                isDirectory: false
            ),
            let data = try? Data(contentsOf: directory),
            let collection = try? JSONDecoder().decode(
                TheaterAuthorityCollection.self,
                from: data
            )
        {
            authorities = collection
        }
        let archiveBytes = exportURL.flatMap {
            try? FileManager.default.attributesOfItem(
                atPath: $0.path
            )[.size] as? Int64
        } ?? 0
        let inventory = HTDTBundleInventory(
            manifest: manifest,
            authorities: authorities,
            archiveByteCount: archiveBytes,
            projectRef: nil
        )
        do {
            let snapshot = try await HTDTCapabilityClient().fetch(
                endpoint: capabilityURL,
                pinnedIdentity: paired?.pinnedIdentity
            )
            if let paired {
                try? pairedDestinationStore?
                    .updateCachedCapability(
                        destinationID: paired.destinationID,
                        snapshot: snapshot
                    )
                refreshMissionDeliveryStores()
            }
            return HTDTCompatibilityChecker.check(
                inventory: inventory,
                capabilities: snapshot.document,
                requiresMissionReceipts:
                    missionRecords.contains {
                        $0.receiverRequirement?
                            .requireMissionReceipts == true
                            && $0.recordID
                                == activeMissionRecordID
                    }
            )
        } catch {
            if let cached = paired?.cachedCapability {
                return HTDTCompatibilityChecker.check(
                    inventory: inventory,
                    capabilities: cached.document,
                    requiresMissionReceipts: false
                )
            }
            return .unknown(
                reason: String(describing: error)
            )
        }
    }

    /// Deletes a validated export archive independently of its
    /// finalized capture (issue #251). Refuses when the finalized copy
    /// no longer exists on disk — the archive is the last copy, which
    /// is exactly the case where deleting it would lose the capture.
    func deleteExportArchive(
        _ record: PersistedCaptureRecord
    ) {
        guard let store = persistedStore,
              !persistedDeletionInFlight
        else {
            return
        }
        persistedDeletionInFlight = true
        operationTargetRevisionID = record.captureRevisionID
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.persistedDeletionInFlight = false }
            do {
                let removed = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try store.deleteExportArchive(
                        captureRevisionID:
                            record.captureRevisionID
                    )
                }.value
                self.workingSetStatus = removed
                    ? String(localized: "Export archive deleted; the finalized capture is unchanged")
                    : String(localized: "No export archive existed to delete")
            } catch {
                self.workingSetStatus = String(localized: "The export archive could not be deleted") + " [" + Self.persistenceDiagnostic(error) + "]"
            }
            self.loadPersistedCaptures()
        }
    }

    /// Saves operator library metadata — display name and note — for a
    /// series or a single revision (issue #219). App-local only; the
    /// capture bundle is never modified.
    func updateLibraryEntry(
        revisionID: CaptureRevisionID?,
        seriesID: CaptureSeriesID?,
        metadata: CaptureLibraryEntryMetadata
    ) {
        guard let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let store = CaptureLibraryMetadataStore(
            captureRoot: captureRoot
        )
        do {
            if let seriesID {
                try store.updateSeries(
                    seriesID,
                    displayName: metadata.displayName,
                    note: metadata.note
                )
            }
            if let revisionID {
                try store.updateRevision(
                    revisionID,
                    displayName: metadata.displayName,
                    note: metadata.note
                )
            }
            libraryMetadata = try store.load()
        } catch {
            workingSetStatus = String(localized: "Library metadata could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Enumerates and validates the app-owned persisted capture roots
    /// (`finalized/` and `exports/`) off the main actor, then publishes
    /// the result. The newest request always wins; stale scans are
    /// discarded so a slower pre-delete scan cannot overwrite a
    /// post-delete inventory.
    func loadPersistedCaptures() {
        persistedInventoryRequest += 1
        let request = persistedInventoryRequest

        guard let store = persistedStore else {
            persistedInventory =
                PersistedCaptureInventoryResult()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let activeRevisionID =
                await self.workingSetStore?.identity.captureRevisionID
            let inventory = await Task.detached(
                priority: .utility
            ) {
                store.scan(activeRevisionID: activeRevisionID)
            }.value
            guard self.persistedInventoryRequest == request
            else {
                return
            }
            self.persistedInventory = inventory
            // Operator-facing names/notes layer over the inventory
            // (issue #219); loaded with each scan so UI edits reflect
            // the latest document.
            if let root = Self.captureRootDirectory(),
               let document = try? CaptureLibraryMetadataStore(
                captureRoot: root
            ).load()
            {
                self.libraryMetadata = document
            }
            // Acquisition provenance join (#317): every validated
            // bundle gets a declared origin — explicit records stay
            // authoritative; entries that predate the provenance store
            // backfill as `legacy_unknown` rather than being silently
            // treated as device-created.
            if let originStore = self.captureOriginStore {
                let backfill = await Task.detached(
                    priority: .utility
                ) { () -> CaptureAcquisitionOriginDocument? in
                    let unknowns = inventory.captures.compactMap {
                        record -> CaptureAcquisitionOriginRecord? in
                        guard record.finalizedValidation != nil
                                || record.exportValidation != nil
                        else {
                            return nil
                        }
                        return try? CaptureAcquisitionOriginRecord(
                            captureRevisionID:
                                record.captureRevisionID,
                            kind: .legacyUnknown,
                            transport: .unknown,
                            acquiredAtUTC:
                                record.finalizedAtUTC
                        )
                    }
                    try? originStore.recordIfAbsent(unknowns)
                    return try? originStore.load()
                }.value
                if let backfill {
                    var joined:
                        [CaptureRevisionID:
                            CaptureAcquisitionOriginRecord] = [:]
                    for entry in backfill.entries {
                        joined[entry.captureRevisionID] = entry
                    }
                    self.captureOrigins = joined
                }
            }
        }
    }

    /// Adopts a persisted capture after relaunch. The record is
    /// revalidated against the manifest on disk before adoption; the
    /// working set and its AR coordinate authority are never
    /// reconstructed — the host lands directly in `.finalized` (or
    /// `.exported` when a matching validated archive already exists).
    func openPersistedCapture(
        _ captureRevisionID: CaptureRevisionID
    ) {
        guard state == .idle,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight,
              let store = persistedStore
        else {
            return
        }

        persistedAdoptionInFlight = true
        operationTargetRevisionID = captureRevisionID
        workingSetStatus = String(localized: "Revalidating the persisted capture")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let record = await Task.detached(
                priority: .userInitiated
            ) {
                store.validatedRecord(
                    captureRevisionID: captureRevisionID
                )
            }.value

            self.persistedAdoptionInFlight = false
            guard self.state == .idle else {
                return
            }
            guard let record,
                  let directory = record.finalizedDirectory,
                  let validation = record.finalizedValidation
            else {
                self.loadPersistedCaptures()
                self.workingSetStatus = String(localized: "The persisted capture could not be revalidated; the on-disk inventory was refreshed")
                return
            }

            self.finalizedRevision = FinalizedCaptureRevision(
                directory: directory,
                captureRevisionID: record.captureRevisionID,
                bundleDigest: validation.bundleDigest,
                payloadCount: validation.payloadCount
            )
            self.validationReport = validation
            self.qualityReport = Self.persistedQualityReport(
                in: directory,
                manifest: validation.manifest
            )
            self.advisoryReport = Self.persistedAdvisoryReport(
                in: directory,
                manifest: validation.manifest
            )
            self.exportURL = record.exportArchive
            self.refreshHandoffDestinations()
            if let captureRoot = Self.captureRootDirectory() {
                self.handoffReceipts =
                    (try? HTDTHandoffReceiptStore(
                        captureRoot: captureRoot
                    ).receipts(
                        for: record.captureRevisionID
                    )) ?? []
            }

            do {
                try self.transition(.adoptFinalized)
                if record.exportArchive != nil {
                    try self.transition(.export)
                }
            } catch {
                // A failed adoption must not leave a dangling finalized
                // state without its revision handle; reset returns the
                // host to a clean idle. If the first transition already
                // failed the host is still idle, so only the adopted
                // fields need clearing.
                if self.state == .finalized
                    || self.state == .exported
                {
                    self.resetCapture()
                }
                self.finalizedRevision = nil
                self.validationReport = nil
                self.qualityReport = nil
                self.advisoryReport = nil
                self.exportURL = nil
                self.workingSetStatus = String(localized: "The persisted capture could not be opened")
                return
            }

            self.workingSetStatus = record.exportArchive != nil
                ? String(localized: "Opened the persisted capture; its validated archive is ready to share")
                : String(localized: "Opened the persisted finalized capture; export can be prepared")
        }
    }

    /// Deletes the local copy of a persisted revision: its finalized
    /// directory and matching export archive, resolved strictly inside
    /// the app-owned capture roots. A partial deletion never reports
    /// success; whatever remains is republished through the inventory.
    func deletePersistedCapture(
        _ captureRevisionID: CaptureRevisionID
    ) {
        guard !persistedDeletionInFlight,
              !persistedAdoptionInFlight,
              !exportOperationInFlight,
              !importOperationInFlight,
              let store = persistedStore
        else {
            return
        }

        let isAdopted =
            finalizedRevision?.captureRevisionID
                == captureRevisionID
        if isAdopted {
            guard state == .finalized || state == .exported
            else {
                return
            }
        } else {
            guard state == .idle else {
                return
            }
        }

        persistedDeletionInFlight = true
        operationTargetRevisionID = captureRevisionID
        workingSetStatus = String(localized: "Deleting local capture data")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                store.deleteCapture(
                    captureRevisionID: captureRevisionID
                )
            }.value

            self.persistedDeletionInFlight = false

            if isAdopted,
               self.state == .finalized
                   || self.state == .exported
            {
                // Deleting the adopted capture releases its in-memory
                // handle and returns the host to idle. Other records
                // are untouched; whatever could not be removed stays
                // listed by the refreshed inventory.
                self.resetCapture()
            }

            self.loadPersistedCaptures()

            if result.succeeded {
                self.workingSetStatus = String(localized: "Local capture data was deleted")
            } else {
                let detail = result.remaining
                    .map {
                        $0.url.lastPathComponent
                            + " ("
                            + $0.reason
                            + ")"
                    }
                    .joined(separator: "; ")
                self.workingSetStatus =
                    String(localized: "Some local capture data could not be deleted; the remaining artifacts stay listed for retry")
                    + " ["
                    + detail
                    + "]"
            }
        }
    }

    /// Removes a quarantined artifact. Removal authority is limited to
    /// direct children of the app-owned capture roots; the store itself
    /// refuses anything else.
    func removeQuarantinedArtifact(
        _ artifact: PersistedCaptureQuarantinedArtifact
    ) {
        guard state == .idle,
              !persistedDeletionInFlight,
              !persistedAdoptionInFlight,
              let store = persistedStore
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.detached(
                    priority: .userInitiated
                ) {
                    try store.removeArtifact(artifact)
                }.value
                self.workingSetStatus = String(localized: "Unreadable artifact removed")
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus =
                    String(localized: "The artifact could not be removed")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
            self.loadPersistedCaptures()
        }
    }

    /// Removes one abandoned working-root item surfaced by the
    /// inventory. The store re-derives ownership proof from the
    /// resolved path (a canonical `<uuid>` revision directory or a
    /// `.tmp-*` writer file directly under `working/`), so a forged or
    /// misclassified item cannot be deleted through this action. A
    /// failure keeps the orphan listed with its retained byte count.
    func removeWorkingOrphan(
        _ orphan: PersistedCaptureWorkingOrphan
    ) {
        guard state == .idle,
              !persistedDeletionInFlight,
              !persistedAdoptionInFlight,
              !importOperationInFlight,
              let store = persistedStore
        else {
            return
        }

        persistedDeletionInFlight = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.persistedDeletionInFlight = false
                self.loadPersistedCaptures()
            }
            do {
                try await Task.detached(
                    priority: .userInitiated
                ) {
                    try store.removeWorkingOrphan(orphan)
                }.value
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus = String(localized: "Abandoned working data was deleted")
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus =
                    String(localized: "The abandoned working data could not be deleted; it stays listed for retry")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// Host-level validated import for an external `.htdtcapture`
    /// document (#165). The incoming archive is treated as untrusted:
    /// its bytes are validated before the manifest identity is read,
    /// and the staged importer only publishes the extracted directory
    /// into `finalized/` after the extracted bundle revalidates to the
    /// archive's declared digest. Only ever runs from idle, so an
    /// active capture's coordinate authority can never be overwritten
    /// by a document open. On success the imported revision is opened
    /// into the read-only finalized workflow, where any
    /// revise-existing action stays explicit (#155).
    func importCaptureArchive(from url: URL) {
        guard state == .idle else {
            workingSetStatus = String(localized: "An external capture archive can only be imported while no capture is active")
            return
        }
        guard !importOperationInFlight,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight,
              let store = persistedStore
        else {
            return
        }
        guard url.pathExtension
                == HTDTCaptureFileType.filenameExtension
        else {
            workingSetStatus = String(localized: "The selected file is not an .htdtcapture archive")
            return
        }

        // Security-scoped access must begin while the open/pick grant
        // is still live, so it starts here synchronously and is held
        // until the detached import work finishes.
        let accessing =
            url.startAccessingSecurityScopedResource()

        importOperationInFlight = true
        workingSetStatus = String(localized: "Validating the incoming .htdtcapture archive")

        Task { @MainActor [weak self] in
            guard let self else {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                return
            }
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                self.importOperationInFlight = false
            }

            do {
                let imported = try await Task.detached(
                    priority: .userInitiated
                ) { () throws -> (
                    revisionID: CaptureRevisionID,
                    bundleDigest: EvidenceSHA256,
                    promoted: Bool,
                    archiveStored: Bool
                ) in
                    // Validation runs before the manifest identity is
                    // used; the importer validates again internally
                    // before promotion.
                    let report =
                        try StoredCaptureBundleArchiveValidator
                            .validate(archive: url)
                    let revisionID =
                        report.manifest.captureRevisionID
                    let destination = store.finalizedDirectory(
                        for: revisionID
                    )

                    guard !FileManager.default.fileExists(
                        atPath: destination.path
                    ) else {
                        return (
                            revisionID, report.bundleDigest, false,
                            false
                        )
                    }

                    _ = try StoredCaptureBundleArchiveImporter
                        .importArchive(
                            archive: url,
                            destination: destination
                        )

                    // Preserve the exact validated archive bytes in the
                    // canonical exports slot so the imported revision
                    // can be re-shared without re-export. Best-effort:
                    // the finalized copy is already the import's
                    // authority.
                    var archiveStored = false
                    let archiveDestination =
                        store.exportArchiveURL(for: revisionID)
                    if !FileManager.default.fileExists(
                        atPath: archiveDestination.path
                    ) {
                        archiveStored =
                            (try? FileManager.default.copyItem(
                                at: url,
                                to: archiveDestination
                            )) != nil
                    } else {
                        archiveStored = true
                    }
                    return (
                        revisionID, report.bundleDigest, true,
                        archiveStored
                    )
                }.value

                guard self.state == .idle else {
                    return
                }
                // Acquisition provenance (#317): the imported bundle
                // carries `imported_file` — never silently grouped
                // with device-created captures. A digest-pinned
                // re-import of identical bytes stays a no-op; a
                // conflicting record for the same revision ID leaves
                // the first provenance authoritative.
                if let originStore = self.captureOriginStore,
                   let originRecord =
                    try? CaptureAcquisitionOriginRecord(
                        captureRevisionID: imported.revisionID,
                        kind: .importedFile,
                        transport: .fileImport,
                        acquiredAtUTC:
                            BundleTimestamp.utcString(
                                from: Date()
                            ),
                        originalFilename: url.lastPathComponent,
                        bundleDigestSHA256:
                            imported.bundleDigest.value
                    )
                {
                    try? originStore.record(originRecord)
                    self.captureOrigins[imported.revisionID] =
                        originRecord
                }
                self.loadPersistedCaptures()
                self.workingSetStatus = imported.promoted
                    ? String(localized: "Validated capture archive imported")
                    : String(localized: "This capture revision is already stored locally")
                if imported.promoted && !imported.archiveStored {
                    self.workingSetStatus +=
                        String(localized: " (archive copy was not retained in exports)")
                }
                self.openPersistedCapture(
                    imported.revisionID
                )
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.loadPersistedCaptures()
                self.workingSetStatus =
                    String(localized: "The .htdtcapture archive failed validation and was not imported; nothing was promoted")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// The single validated file-entry boundary (issue #393):
    /// identify the document kind, hold its security-scoped access
    /// for the whole async import, gate by capture state, then hand
    /// to the owning importer — which remains authoritative for its
    /// own schema.
    func importInboundDocument(from url: URL) {
        let classification =
            InboundDocumentRouter.classify(url: url)
        let availability = InboundDocumentRouter.availability(
            kind: classification.kind,
            captureState: state
        )
        switch availability {
        case .idleOnly:
            workingSetStatus = String(localized: "This document can only be imported while no capture is active")
            return
        case .unsupported:
            workingSetStatus = String(localized: "The selected file is not a recognized HTDT document")
            return
        case .allowed, .storableDuringActiveCapture:
            break
        }
        switch classification.kind {
        case .captureBundle:
            importCaptureArchive(from: url)
        case .captureLibraryPackage:
            importLibraryPackage(from: url)
        case .captureMission:
            Task { @MainActor [weak self] in
                await self?.importMissionPackage(url)
            }
        case .equipmentCatalog:
            importEquipmentCatalogDocument(from: url)
        case .unsupported:
            break
        }
    }

    /// Catalogs arriving via the shared boundary (#393): stored
    /// without activation while a capture is active — explicit
    /// adoption stays an operator action on the catalog picker;
    /// adopted immediately while idle.
    private func importEquipmentCatalogDocument(
        from url: URL
    ) {
        let access = SecurityScopedAccess(url: url)
        defer { access.finish() }
        guard let data = try? Data(contentsOf: url) else {
            workingSetStatus = String(localized: "The equipment catalog could not be read")
            return
        }
        do {
            // Decode through the validating snapshot type so the
            // stored bytes are exactly the validated document.
            let snapshot = try JSONDecoder().decode(
                HTDTEquipmentCatalogSnapshot.self,
                from: data
            )
            let encoded = try JSONEncoder().encode(snapshot)
            if state == .idle {
                _ = try equipmentCatalogStore?
                    .storeAndActivate(encoded)
                equipmentCatalog = snapshot
                workingSetStatus = String(localized: "Equipment catalog imported")
            } else {
                _ = try equipmentCatalogStore?.store(encoded)
                workingSetStatus = String(localized: "Equipment catalog stored; activate it from the catalog picker")
            }
            equipmentCatalogLibrary =
                equipmentCatalogStore?.list()
                    ?? equipmentCatalogLibrary
        } catch {
            workingSetStatus = String(localized: "The equipment catalog could not be imported") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// #378: validates a `.htdtcapturelibrary` package and stages an
    /// import preview — manifest → per-archive validation → dedup /
    /// conflict classification → merge counts. Nothing is imported
    /// until `confirmLibraryImport`.
    func importLibraryPackage(from url: URL) {
        guard state == .idle else {
            workingSetStatus = String(localized: "A library package can only be imported while no capture is active")
            return
        }
        guard !importOperationInFlight,
              !persistedAdoptionInFlight,
              !persistedDeletionInFlight,
              persistedStore != nil,
              let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let access = SecurityScopedAccess(url: url)
        importOperationInFlight = true
        workingSetStatus = String(localized: "Validating the library package")
        let localRecords = persistedInventory.captures
        Task { @MainActor [weak self] in
            guard let self else {
                access.finish()
                return
            }
            defer {
                access.finish()
                self.importOperationInFlight = false
            }
            let staging = captureRoot
                .appendingPathComponent(
                    "library-import-staging",
                    isDirectory: true
                )
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
            do {
                let preview = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CaptureLibraryImporter.preview(
                        package: url,
                        captureRoot: captureRoot,
                        localRecords: localRecords,
                        stagingDirectory: staging
                    )
                }.value
                guard self.state == .idle else {
                    try? CaptureLibraryImporter.discard(
                        preview: preview
                    )
                    return
                }
                self.libraryImportStagingDirectory = staging
                self.libraryImportPreview = preview
                self.workingSetStatus =
                    preview.importableCount > 0
                    ? captureCountPhrase(
                        preview.importableCount,
                        singular: String(
                            localized: "Library package ready: %lld revision to import"
                        ),
                        plural: String(
                            localized: "Library package ready: %lld revisions to import"
                        )
                    )
                    : String(localized: "Nothing new to import from this library package")
            } catch {
                try? FileManager.default.removeItem(
                    at: staging
                )
                guard self.state == .idle else { return }
                self.workingSetStatus =
                    String(localized: "The library package failed validation; nothing was imported")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// #378: commits the staged library import — each new revision's
    /// archive bytes are installed verbatim, filtered metadata merges
    /// with adopt-empty / retain-local-conflict, receipts append
    /// deduped.
    func confirmLibraryImport() {
        guard let preview = libraryImportPreview,
              !importOperationInFlight,
              let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        importOperationInFlight = true
        workingSetStatus = String(localized: "Importing the library package")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.importOperationInFlight = false
                self.libraryImportPreview = nil
                self.libraryImportStagingDirectory = nil
            }
            do {
                let result = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CaptureLibraryImporter.commit(
                        preview: preview,
                        captureRoot: captureRoot
                    )
                }.value
                self.loadPersistedCaptures()
                self.refreshMissionDeliveryStores()
                var status = captureCountPhrase(
                    result.imported.count,
                    singular: String(
                        localized: "Imported %lld revision"
                    ),
                    plural: String(
                        localized: "Imported %lld revisions"
                    )
                )
                if !result.failed.isEmpty {
                    status += String(format: String(localized: "; %lld could not be imported and were left untouched"), result.failed.count)
                }
                if !result.conflicts.isEmpty {
                    status += captureCountPhrase(
                        result.conflicts.count,
                        singular: String(
                            localized: "; %lld conflict skipped"
                        ),
                        plural: String(
                            localized: "; %lld conflicts skipped"
                        )
                    )
                }
                self.workingSetStatus = status
            } catch {
                self.loadPersistedCaptures()
                self.workingSetStatus =
                    String(localized: "The library package import did not complete")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// Dismisses the staged library preview and removes its staging
    /// directory (#378).
    func dismissLibraryImport() {
        if let preview = libraryImportPreview {
            try? CaptureLibraryImporter.discard(preview: preview)
        }
        libraryImportPreview = nil
        libraryImportStagingDirectory = nil
    }

    /// #378: exports every persisted capture — active and archived —
    /// plus filtered metadata and receipts as one
    /// `.htdtcapturelibrary` package under `exports/` for sharing.
    func exportLibraryPackage() {
        guard let captureRoot = Self.captureRootDirectory(),
              persistedStore != nil,
              !exportOperationInFlight
        else {
            return
        }
        exportOperationInFlight = true
        workingSetStatus = String(localized: "Exporting the capture library")
        let records = persistedInventory.captures
        let metadata = libraryMetadata
        let receipts = handoffReceipts
        let destination = captureRoot
            .appendingPathComponent(
                "exports",
                isDirectory: true
            )
            .appendingPathComponent(
                "htdt-library-"
                    + BundleTimestamp.utcString(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                    + "."
                    + HTDTCaptureLibraryFileType.filenameExtension,
                isDirectory: false
            )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.exportOperationInFlight = false }
            let runtime = PlatformRuntimeProvenance.current()
            do {
                let result = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CaptureLibraryPackageExporter.export(
                        records: records,
                        scope: .all,
                        metadata: metadata,
                        receipts: receipts,
                        destination: destination,
                        appVersion: runtime.appVersion,
                        appBuild: runtime.appBuild,
                        nowUTC: BundleTimestamp.utcString(
                            from: Date()
                        )
                    )
                }.value
                self.libraryExportURL = result.packageURL
                var status = captureCountPhrase(
                    result.revisionCount,
                    singular: String(
                        localized: "Library package exported (%lld revision)"
                    ),
                    plural: String(
                        localized: "Library package exported (%lld revisions)"
                    )
                )
                if !result.skippedRevisions.isEmpty {
                    status += captureCountPhrase(
                        result.skippedRevisions.count,
                        singular: String(
                            localized: "; %lld revision had no exportable evidence"
                        ),
                        plural: String(
                            localized: "; %lld revisions had no exportable evidence"
                        )
                    )
                }
                self.workingSetStatus = status
            } catch {
                self.workingSetStatus =
                    String(localized: "The library package could not be exported")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    /// #394: archives or restores a series — the lifecycle state is
    /// app-local metadata; the canonical bundles and receipts are
    /// untouched.
    func setSeriesArchived(
        _ seriesID: CaptureSeriesID,
        archived: Bool
    ) {
        guard let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let store = CaptureLibraryMetadataStore(
            captureRoot: captureRoot
        )
        do {
            try store.setSeriesState(
                seriesID,
                archived: archived,
                archivedAtUTC: archived
                    ? BundleTimestamp.utcString(from: Date())
                    : nil
            )
            libraryMetadata = try store.load()
            workingSetStatus = archived
                ? String(localized: "Series archived; its captures and history are unchanged")
                : String(localized: "Series restored to the active library")
        } catch {
            workingSetStatus = String(localized: "The series state could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// #394: sets/clears a revision's importance marks — milestone,
    /// keep local, favorite, pinned.
    func updateRevisionMark(
        _ revisionID: CaptureRevisionID,
        mark: CaptureRevisionMark
    ) {
        guard let captureRoot = Self.captureRootDirectory()
        else {
            return
        }
        let store = CaptureLibraryMetadataStore(
            captureRoot: captureRoot
        )
        do {
            try store.updateRevisionMark(
                revisionID,
                mark: mark
            )
            libraryMetadata = try store.load()
        } catch {
            workingSetStatus = String(localized: "The revision mark could not be saved") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// #394: dependency-aware series delete — the preview's blockers
    /// (pending delivery jobs, importance marks without the explicit
    /// override) skip revisions instead of deleting them, and the
    /// result names exactly what left the device.
    func deleteSeries(
        _ seriesID: CaptureSeriesID,
        includeProtected: Bool
    ) {
        guard let store = persistedStore,
              let captureRoot = Self.captureRootDirectory(),
              !persistedDeletionInFlight
        else {
            return
        }
        persistedDeletionInFlight = true
        let records = persistedInventory.captures
        let jobs = deliveryJobs
        let missions = missionRecords
        let receipts = handoffReceipts
        workingSetStatus = String(localized: "Deleting the series")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.persistedDeletionInFlight = false }
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                CaptureLibraryRetentionPlanner.deleteSeries(
                    seriesID: seriesID,
                    records: records.filter {
                        $0.captureSeriesID == seriesID
                    },
                    allRecords: records,
                    inventory: store,
                    metadataStore: CaptureLibraryMetadataStore(
                        captureRoot: captureRoot
                    ),
                    deliveryJobs: jobs,
                    missionRecords: missions,
                    receipts: receipts,
                    includeProtected: includeProtected
                )
            }.value
            self.loadPersistedCaptures()
            var status = captureCountPhrase(
                result.deleted.count,
                singular: String(
                    localized: "Deleted %lld revision"
                ),
                plural: String(
                    localized: "Deleted %lld revisions"
                )
            )
            if !result.skipped.isEmpty {
                status += captureCountPhrase(
                    result.skipped.count,
                    singular: String(
                        localized: "; %lld blocked revision was kept"
                    ),
                    plural: String(
                        localized: "; %lld blocked revisions were kept"
                    )
                )
            }
            if !result.remaining.isEmpty {
                status += captureCountPhrase(
                    result.remaining.count,
                    singular: String(
                        localized: "; %lld revision could not be fully removed"
                    ),
                    plural: String(
                        localized: "; %lld revisions could not be fully removed"
                    )
                )
            }
            self.workingSetStatus = status
        }
    }

    /// The persisted quality report lives inside the validated bundle
    /// at `quality/capture-quality.json`; because the manifest pins its
    /// hash, decoded bytes are authentic. Decoding is best-effort so an
    /// older or future schema degrades to a validation-only view
    /// instead of blocking adoption.
    nonisolated private static func persistedQualityReport(
        in directory: URL,
        manifest: BundleManifest
    ) -> CaptureQualityReport? {
        let path = "quality/capture-quality.json"
        guard manifest.files.contains(where: {
            $0.path == path
        }) else {
            return nil
        }
        var url = directory
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CaptureQualityReport.self,
            from: data
        )
    }

    /// Advisory payload decode for a reopened capture (#223): same
    /// manifest-authenticated pattern as the quality report, degrading
    /// to nil for captures finalized before the advisory contract.
    nonisolated private static func persistedAdvisoryReport(
        in directory: URL,
        manifest: BundleManifest
    ) -> CaptureAdvisoryReport? {
        let path = CaptureAdvisoryReport.payloadPath
        guard manifest.files.contains(where: {
            $0.path == path
        }) else {
            return nil
        }
        var url = directory
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CaptureAdvisoryReport.self,
            from: data
        )
    }

    /// Operator task-profile selection (#217/#259). Advisory only —
    /// recorded to the working set so seal persists the completeness
    /// evaluation inside the advisory payload.
    func selectTaskProfile(
        _ profile: CaptureTaskProfile?,
        skippedRequirementIDs: Set<String> = []
    ) {
        let previous = taskProfile
        taskProfile = profile
        self.skippedTaskRequirementIDs = skippedRequirementIDs
        // #352: profile selection on the setup screen is pending
        // mission intent, bound at Begin; keep the presentation in
        // sync. Once a working set exists the same action is an
        // explicit mission change and records provenance.
        if state == .setup {
            refreshCaptureSetupPresentation()
        }
        guard let store = workingSetStore else { return }
        let generation = captureGeneration
        let changedAfterBind =
            previous?.identifier != profile?.identifier
        let timestamp = latestScanTimestampSeconds ?? 0
        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }
            if changedAfterBind {
                try? await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .taskProfileChange,
                        sessionTimestampSeconds: timestamp,
                        detail:
                            "from=\(previous?.identifier ?? "none") to=\(profile?.identifier ?? "none")"
                    )
                )
            }
            try? await store.recordTaskProfile(
                profile,
                skippedRequirementIDs: skippedRequirementIDs
            )
        }
    }

    // MARK: - Revisit flags (#325)

    /// One-tap flag during scanning: snapshots the center-raycast
    /// target (or the camera pose when no hit exists), appends a
    /// bounded marker, persists the flag document, and confirms
    /// through the #252 cue channel. Returns the new flag id so the
    /// view can offer the optional details sheet, nil when the flag
    /// could not be recorded.
    func flagForReview() -> String? {
        guard state == .scanning,
              !isEndingScan,
              !revisitFlagStore.isFull,
              workingSetStore != nil,
              workingSetIdentity != nil
        else {
            return nil
        }

        let context = sessionController.context
        let orientation =
            try? sessionController.snapshotCameraOrientation()
        let raycast =
            try? sessionController.snapshotCenterRaycastPlacement()
        let pose =
            orientation?.frameArtifacts.worldFromCamera
            ?? raycast?.frameArtifacts.worldFromCamera
        let timestamp =
            orientation?.frameArtifacts
            .sessionTimestampSeconds
            ?? raycast?.frameArtifacts.sessionTimestampSeconds
            ?? latestScanTimestampSeconds
            ?? 0

        var target: ScanRevisitFlagVector?
        var targetFromRaycast = false
        var coverageCell: String?
        if let raycast {
            let p = raycast.positionWorld
            target = ScanRevisitFlagVector(
                x: Double(p.x),
                y: Double(p.y),
                z: Double(p.z)
            )
            targetFromRaycast = true
            if let cell = spatialCoverage.cellKey(
                forWorldPoint: SpatialCoveragePoint3D(
                    x: Double(p.x),
                    y: Double(p.y),
                    z: Double(p.z)
                )
            ) {
                coverageCell = "\(cell.x),\(cell.z)"
            }
        }
        var cameraPosition: ScanRevisitFlagVector?
        var cameraForward: ScanRevisitFlagVector?
        if let pose {
            cameraPosition = ScanRevisitFlagVector(
                x: Double(pose.values[12]),
                y: Double(pose.values[13]),
                z: Double(pose.values[14])
            )
            cameraForward = ScanRevisitFlagVector(
                x: Double(-pose.values[8]),
                y: Double(-pose.values[9]),
                z: Double(-pose.values[10])
            )
        }

        let flag = ScanRevisitFlag(
            coordinateSpaceID: context.coordinateSpaceID,
            captureSessionID: context.captureSessionID,
            targetPointWorld: target,
            targetFromRaycast: targetFromRaycast,
            cameraPositionWorld: cameraPosition,
            cameraForwardWorld: cameraForward,
            coverageCell: coverageCell,
            category: nil,
            note: nil,
            createdSessionTimestampSeconds: timestamp
        )
        guard revisitFlagStore.add(flag) else {
            return nil
        }
        revisitFlags = revisitFlagStore.flags
        playCueIfAdmitted(
            .revisitFlagSaved,
            timestampSeconds: timestamp
        )
        persistRevisitFlags()
        return flag.flagID
    }

    /// Saves the optional details (category/note) after the operator
    /// stopped to fill them in — never required to drop a flag.
    func updateRevisitFlagDetails(
        _ flagID: String,
        category: ScanRevisitFlagCategory?,
        note: String?
    ) {
        guard revisitFlagStore.updateDetails(
            flagID: flagID,
            category: category,
            note: note
        ) else {
            return
        }
        revisitFlags = revisitFlagStore.flags
        persistRevisitFlags()
    }

    /// #325 Review resolution: the outcome names what the flag
    /// resolved to — linked authority, acknowledged, or unavailable.
    func resolveRevisitFlag(
        _ flagID: String,
        outcome: ScanRevisitFlagResolution.Outcome,
        authorityRef: String?
    ) {
        guard revisitFlagStore.resolve(
            flagID: flagID,
            outcome: outcome,
            authorityRef: authorityRef,
            sessionTimestampSeconds: latestScanTimestampSeconds
        ) else {
            return
        }
        revisitFlags = revisitFlagStore.flags
        if let store = workingSetStore {
            let generation = captureGeneration
            Task { @MainActor [weak self] in
                guard self?.captureGeneration == generation else {
                    return
                }
                try? await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .revisitFlagResolution,
                        sessionTimestampSeconds:
                            self?.latestScanTimestampSeconds ?? 0,
                        detail:
                            "flag_id=\(flagID) outcome=\(outcome.rawValue)"
                    )
                )
            }
        }
        persistRevisitFlags()
    }

    func reopenRevisitFlag(_ flagID: String) {
        guard revisitFlagStore.reopen(flagID: flagID) else {
            return
        }
        revisitFlags = revisitFlagStore.flags
        persistRevisitFlags()
    }

    /// Persists the current flag document; failures surface on the
    /// status line rather than silently dropping flags (#325).
    private func persistRevisitFlags() {
        guard let store = workingSetStore,
              let identity = workingSetIdentity
        else {
            return
        }
        let context = sessionController.context
        let generation = captureGeneration
        // Flags pinned to a coordinate space a mid-scan discontinuity
        // left behind stay listed but marked unavailable — never
        // silently resolved (#325).
        revisitFlagStore.markFlagsUnavailable(
            notIn: context.coordinateSpaceID
        )
        revisitFlags = revisitFlagStore.flags
        let document = revisitFlagStore.document(
            captureRevisionID: identity.captureRevisionID
        )
        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }
            do {
                let data = try document.encoded()
                try await store.replaceSupplementalDocument(
                    WorkingSetSupplementalDocument(
                        path: CaptureRevisitFlagDocument.path,
                        data: data,
                        declaration: BundlePayloadDeclaration(
                            path: CaptureRevisitFlagDocument.path,
                            mediaType: "application/json",
                            producer: "capture_session",
                            provenanceClass: .captureAppDerived,
                            role: .canonical
                        ),
                        coordinateSpaceIDs: [
                            context.coordinateSpaceID,
                        ],
                        captureSessionIDs: [
                            context.captureSessionID,
                        ]
                    )
                )
            } catch {
                self.workingSetStatus = String(localized: "Review flag could not be saved") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// #352 Review-time checklist marks for the bound task plan.
    /// Also forwards the mark to an imported task plan (#240) — the
    /// two statuses coexist: `boundTaskPlanStatus` tracks the
    /// mission-bound plan persisted via the working set, while
    /// `captureTaskPlanStatus` is the standalone imported plan.
    /// #364 §10: an operator reason captured by the checklist's
    /// "with reason" marks persists as a mission-level waiver note
    /// (#397) on every mission record matching a marked plan.
    func markTaskPlanItem(
        _ itemID: String,
        outcome: TaskPlanItemOutcome,
        reason: String? = nil
    ) {
        if var status = boundTaskPlanStatus,
           let store = workingSetStore,
           let identity = workingSetIdentity
        {
            do {
                try status.mark(itemID: itemID, as: outcome)
            } catch {
                markTaskPlanItem(
                    itemID,
                    as: outcome,
                    reason: reason
                )
                return
            }
            boundTaskPlanStatus = status
            let context = sessionController.context
            let annotations = reviewWorkspace?.annotations ?? []
            let measurements = reviewWorkspace?.measurements ?? []
            let generation = captureGeneration
            Task { @MainActor [weak self] in
                guard let self,
                      self.captureGeneration == generation
                else {
                    return
                }
                guard let data = try? status.statusPackage(
                    captureRevisionID: identity.captureRevisionID,
                    captureSessionID: context.captureSessionID,
                    annotations: annotations,
                    measurements: measurements
                ) else {
                    return
                }
                try? await store.replaceSupplementalDocument(
                    WorkingSetSupplementalDocument(
                        path: CaptureTaskPlanStatusDocument.path,
                        data: data,
                        declaration: BundlePayloadDeclaration(
                            path: CaptureTaskPlanStatusDocument.path,
                            mediaType: "application/json",
                            producer: "capture_session",
                            provenanceClass: .captureAppDerived,
                            role: .canonical
                        ),
                        coordinateSpaceIDs: [context.coordinateSpaceID],
                        captureSessionIDs: [context.captureSessionID]
                    )
                )
                self.refreshReviewWorkspace()
            }
        }
        recordTaskPlanMarkWaiver(
            itemID: itemID,
            reason: reason,
            plan: boundTaskPlanStatus?.planImport.plan
        )
        markTaskPlanItem(itemID, as: outcome, reason: reason)
    }

    /// #364 §10: whether a mission-inbox record exists for the
    /// checklist's plan — the waiver note is the only audited reason
    /// channel, so "with reason" marking is only offered when a
    /// record can persist it.
    func canRecordTaskPlanMarkReason(
        _ plan: HTDTCaptureTaskPlan
    ) -> Bool {
        missionRecords.contains {
            $0.planID == plan.planID
                && $0.planVersion == plan.planVersion
        }
    }

    /// Persists a marking reason as an explicit mission-level waiver
    /// (#397) on the record matching the marked plan — append-only
    /// and auditable, and the status document contract keeps its
    /// unchanged no-reason field set. No matching record means no
    /// ledger channel: the mark still lands, the reason is reported
    /// dropped rather than silently lost.
    private func recordTaskPlanMarkWaiver(
        itemID: String,
        reason: String?,
        plan: HTDTCaptureTaskPlan?
    ) {
        guard let reason = reason?.trimmingCharacters(
                in: .whitespacesAndNewlines),
              !reason.isEmpty,
              let plan
        else {
            return
        }
        guard let record = missionRecords.first(where: {
            $0.planID == plan.planID
                && $0.planVersion == plan.planVersion
        }),
              let inbox = missionInboxStore,
              let ledger = missionProgressLedgerStore,
              let recordPlan = try? inbox.plan(for: record)
        else {
            workingSetStatus += " "
                + String(localized:
                    "(the reason could not be attached to a mission record)")
            return
        }
        do {
            try ledger.waive(
                itemID: itemID,
                for: record,
                plan: recordPlan,
                note: reason
            )
            refreshMissionDeliveryStores()
        } catch {
            workingSetStatus += " "
                + String(localized:
                    "(the reason could not be attached to a mission record)")
        }
    }

    /// Operator capture-strategy selection (#307). Advisory only —
    /// ignored when a pinned task-plan recommendation is in force, and
    /// applied only at the next `beginCapture`, never retroactively to
    /// a running scan.
    func selectCaptureStrategy(
        _ identifier: CaptureStrategyIdentifier
    ) {
        guard !strategyPinnedByTaskPlan else {
            return
        }
        selectedStrategyID = identifier
    }

    /// Applies a task plan's strategy recommendation (#307/#240).
    /// `recommended_capture_strategy` adopts the profile as a soft
    /// recommendation; `capture_strategy_pinned` locks the picker
    /// until the plan is cleared. Unknown ids are ignored — plan
    /// validation already rejects them.
    func applyTaskPlanStrategy(_ plan: HTDTCaptureTaskPlan) {
        guard let rawID = plan.recommendedCaptureStrategy,
              let identifier =
                CaptureStrategyCatalog.identifier(
                    forPersistedValue: rawID
                )
        else {
            taskPlanStrategyOverride = nil
            strategyPinnedByTaskPlan = false
            return
        }
        let pinned = plan.captureStrategyPinned
        taskPlanStrategyOverride = (identifier, pinned)
        selectedStrategyID = identifier
        strategyPinnedByTaskPlan = pinned
    }

    /// Clears any task-plan strategy override, returning the picker to
    /// the operator's explicit selection (#307).
    func clearTaskPlanStrategyOverride() {
        taskPlanStrategyOverride = nil
        strategyPinnedByTaskPlan = false
    }

    /// Resolves which published profile steers the next scan and under
    /// what source that choice is recorded (#307).
    private func resolvedCaptureStrategy()
        -> (CaptureStrategyProfile, CaptureStrategySource)
    {
        if let override = taskPlanStrategyOverride {
            let profile = CaptureStrategyCatalog.profile(
                for: override.identifier
            )
            return (
                profile,
                override.pinned
                    ? .taskPlanPinned
                    : .taskPlanRecommended
            )
        }
        return (
            CaptureStrategyCatalog.profile(
                for: selectedStrategyID
            ),
            .operatorSelected
        )
    }

    /// Imports a plan-reference underlay document (#322). The JSON
    /// must carry its own explicit scale/alignment authority — this
    /// path never infers scale. When a working set is already live the
    /// document is rebound to the active revision and persisted
    /// immediately; during setup it is held pending until session
    /// foundation assigns capture/coordinate-space identity.
    func importPlanReference(from url: URL) {
        let accessing =
            url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let imported: PlanUnderlayDocument
        do {
            let data = try Data(contentsOf: url)
            imported = try JSONDecoder().decode(
                PlanUnderlayDocument.self,
                from: data
            )
        } catch {
            workingSetStatus = String(localized: "The selected plan reference could not be read") + " [\(Self.persistenceDiagnostic(error))]"
            return
        }
        planUnderlayDocument = imported
        if workingSetStore != nil {
            Task { @MainActor [weak self] in
                await self?.persistPendingPlanUnderlay()
            }
        }
        workingSetStatus = String(localized: "Plan reference registered; it will guide capture as reference only")
    }

    /// Rebinds the pending underlay to the live revision's identity
    /// and writes `reference/plan-underlay.json` (#322). A failure is
    /// recorded as a warning — the underlay stays operator-visible
    /// in memory and never blocks scanning.
    private func persistPendingPlanUnderlay() async {
        guard let pending = planUnderlayDocument,
              let store = workingSetStore
        else {
            return
        }
        let snapshot = await store.snapshot()
        guard let coordinateSpaceID =
            snapshot.coordinateSpaceIDs.first
        else {
            return
        }
        let rebound: PlanUnderlayDocument
        do {
            rebound = try PlanUnderlayDocument(
                captureRevisionID:
                    snapshot.identity.captureRevisionID,
                coordinateSpaceID: coordinateSpaceID,
                sourceKind: pending.sourceKind,
                sourceFilename: pending.sourceFilename,
                sourceMediaType: pending.sourceMediaType,
                sourceSHA256: pending.sourceSHA256,
                htdtReferenceID: pending.htdtReferenceID,
                alignment: pending.alignment,
                importedAtUTC: BundleTimestamp.utcString(
                    from: Date()
                )
            )
            let package = try PlanUnderlayPackageBuilder.build(
                document: rebound
            )
            try await store.persistPlanUnderlay(package)
            planUnderlayDocument = rebound
        } catch {
            try? await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: .persistenceFailure,
                    severity: .warning,
                    detail:
                        "plan underlay could not be persisted: "
                        + Self.persistenceDiagnostic(error)
                )
            )
        }
    }

    // MARK: - Field notes (#375)

    /// Commits an operator field note bound to this revision. During
    /// scanning `attachLatestEvidence` binds the most recently
    /// committed evidence frame (the operator's "current camera
    /// evidence"); in Review `bindingRefs` carries the entity/
    /// measurement/frame refs the note was bound against. The note is
    /// never edited in place — corrections supersede.
    func recordFieldNote(
        text: String,
        category: CaptureFieldNoteCategory,
        needsAttention: Bool,
        severity: CaptureFieldNoteSeverity? = nil,
        bindingRefs: [String] = [],
        attachLatestEvidence: Bool = false,
        dictated: Bool = false,
        anchorRequest: CaptureFieldNoteAnchorRequest = .none
    ) {
        // Notes are operator-authored supplemental docs — not spatial
        // authority — so the #276 finalization seal never silences
        // them; the store's own mutability contract is the boundary.
        guard let store = workingSetStore,
              state == .scanning || state == .reviewing
                  || state == .annotating
        else {
            return
        }
        // #421: resolve the requested anchor against the live
        // session now — a validated raycast point or the device
        // viewpoint — while the AR session's pose is fresh. A miss
        // degrades to `spatialPosition = nil` (the note still
        // records) rather than fabricating a location.
        var spatialPosition: CaptureFieldNoteSpatialPosition?
        var anchorFailed = false
        if anchorRequest != .none, state == .scanning {
            do {
                spatialPosition = try fieldNoteAnchor(
                    request: anchorRequest
                )
            } catch {
                anchorFailed = true
            }
        }
        let sessionSeconds = latestScanTimestampSeconds
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = await store.snapshot()
                var evidenceRefs: [String] = []
                if attachLatestEvidence,
                   let path = snapshot.latestEvidenceDescriptorPath
                {
                    evidenceRefs.append("path:" + path)
                }
                let note = try CaptureFieldNote(
                    captureRevisionID:
                        snapshot.identity.captureRevisionID,
                    createdAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    ),
                    sessionTimestampSeconds: sessionSeconds,
                    category: category,
                    text: text,
                    severity: severity,
                    needsAttention: needsAttention,
                    bindingRefs: bindingRefs,
                    evidenceRefs: evidenceRefs,
                    spatialPosition: spatialPosition,
                    authoringMethod:
                        dictated ? .dictated : .typed
                )
                try await store.recordFieldNote(note)
                if anchorFailed {
                    self.workingSetStatus = String(
                        localized:
                            "Note saved without location — tracking was unavailable."
                    )
                }
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Note could not be saved") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// Resolves a scan-time anchor request into a validated spatial
    /// position (issue #421): `subjectPoint` performs the live center
    /// raycast against captured geometry; `viewpoint` takes the
    /// device pose from the current frame. Both record the exact
    /// coordinate space the session runs under. A ray miss or an
    /// unavailable session throws — the caller degrades to an
    /// unanchored note.
    private func fieldNoteAnchor(
        request: CaptureFieldNoteAnchorRequest
    ) throws -> CaptureFieldNoteSpatialPosition? {
        guard state == .scanning else { return nil }
        let spaceID = sessionController.context.coordinateSpaceID
        switch request {
        case .none:
            return nil
        case .subjectPoint:
            let placement = try sessionController
                .snapshotCenterRaycastPlacement()
            let p = placement.positionWorld
            return try CaptureFieldNoteSpatialPosition(
                coordinateSpaceID: spaceID,
                pointMeters: WorldPoint3D(
                    x: Double(p.x), y: Double(p.y), z: Double(p.z)
                ),
                anchorKind: .subjectPoint
            )
        case .viewpoint:
            let orientation = try sessionController
                .snapshotCameraOrientation()
            let m = orientation.frameArtifacts
                .worldFromCamera.values
            return try CaptureFieldNoteSpatialPosition(
                coordinateSpaceID: spaceID,
                pointMeters: WorldPoint3D(
                    x: Double(m[12]), y: Double(m[13]),
                    z: Double(m[14])
                ),
                anchorKind: .viewpoint
            )
        }
    }

    /// Marks an active field note resolved — the terminal lifecycle
    /// transition Review exposes (#375).
    func resolveFieldNote(_ noteID: CaptureFieldNoteID) {
        guard let store = workingSetStore else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await store.resolveFieldNote(noteID)
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Note could not be resolved") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// Supersedes a note with a corrected replacement — the stored
    /// bytes pair commits atomically so the lineage never splits
    /// (#375).
    func supersedeFieldNote(
        _ noteID: CaptureFieldNoteID,
        replacementText: String,
        category: CaptureFieldNoteCategory
    ) {
        guard let store = workingSetStore else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = await store.snapshot()
                guard let original = snapshot.fieldNotes
                    .first(where: { $0.noteID == noteID })
                else {
                    return
                }
                let replacement = try CaptureFieldNote(
                    captureRevisionID:
                        snapshot.identity.captureRevisionID,
                    createdAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    ),
                    sessionTimestampSeconds:
                        self.latestScanTimestampSeconds,
                    category: category,
                    text: replacementText,
                    severity: original.severity,
                    needsAttention: original.needsAttention,
                    bindingRefs: original.bindingRefs,
                    evidenceRefs: original.evidenceRefs,
                    spatialPosition: original.spatialPosition,
                    authoringMethod: .typed,
                    supersedesNoteID: original.noteID
                )
                try await store.supersedeFieldNote(
                    noteID,
                    replacement: replacement
                )
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Note could not be corrected") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// True when a field note may be authored right now — mid-scan
    /// (bind the latest committed frame as evidence) or in Review
    /// pre-finalization.
    var fieldNoteAuthoringAvailable: Bool {
        (state == .scanning || state == .reviewing
            || state == .annotating)
            && workingSetStore != nil
    }

    /// Review-side authoring entry point (#375): same commit path as
    /// a mid-scan note but carrying the operator's binding refs
    /// instead of the latest-evidence attachment.
    func recordReviewFieldNote(
        text: String,
        category: CaptureFieldNoteCategory,
        needsAttention: Bool,
        bindingRefs: [String]
    ) {
        recordFieldNote(
            text: text,
            category: category,
            needsAttention: needsAttention,
            bindingRefs: bindingRefs
        )
    }

    /// Binds an unbound note to an authority/evidence ref (#375) by
    /// superseding it — the stored pair keeps the original text and
    /// gains the binding, so the lineage shows the Review-time intent.
    func bindFieldNote(
        _ noteID: CaptureFieldNoteID,
        ref: String
    ) {
        guard let store = workingSetStore else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = await store.snapshot()
                guard let original = snapshot.fieldNotes
                    .first(where: { $0.noteID == noteID })
                else {
                    return
                }
                let replacement = try CaptureFieldNote(
                    captureRevisionID:
                        snapshot.identity.captureRevisionID,
                    createdAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    ),
                    sessionTimestampSeconds:
                        self.latestScanTimestampSeconds,
                    category: original.category,
                    text: original.text,
                    severity: original.severity,
                    needsAttention: original.needsAttention,
                    bindingRefs: original.bindingRefs + [ref],
                    evidenceRefs: original.evidenceRefs,
                    spatialPosition: original.spatialPosition,
                    authoringMethod: original.authoringMethod,
                    supersedesNoteID: original.noteID
                )
                try await store.supersedeFieldNote(
                    noteID,
                    replacement: replacement
                )
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Note could not be bound") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    // MARK: - Evidence privacy flag (#376)

    /// Marks an evidence frame privacy-sensitive in the contact sheet
    /// — an advisory note carrying `frame=<id>`, riding the same
    /// committed-document channel as other advisories so the flag is
    /// integrity-covered and survives finalize/export.
    func flagEvidenceFrameForPrivacy(_ frameID: EvidenceFrameID) {
        guard let store = workingSetStore else { return }
        let seconds = latestScanTimestampSeconds ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .privacyFlag,
                        sessionTimestampSeconds: seconds,
                        detail: "frame=\(frameID.description)"
                    )
                )
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Privacy flag could not be saved") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// #460: records the paired clearing note — the flag is advisory,
    /// so the operator must be able to undo it without losing the
    /// provenance trail (declare/revoke precedent).
    func unflagEvidenceFrameForPrivacy(_ frameID: EvidenceFrameID) {
        guard let store = workingSetStore else { return }
        let seconds = latestScanTimestampSeconds ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .privacyFlagCleared,
                        sessionTimestampSeconds: seconds,
                        detail: "frame=\(frameID.description)"
                    )
                )
                self.refreshReviewWorkspace()
            } catch {
                self.workingSetStatus = String(localized: "Privacy flag could not be saved") + " ["
                    + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    // MARK: - Support & Diagnostics (#389)

    /// Collects a privacy-reviewed app diagnostic package (#389).
    /// Everything is already privacy-shaped at collection: resource
    /// events arrive as counts, endpoint reachability as a verdict
    /// class, device identity as a model family — never serials,
    /// project names, secrets, or capture evidence.
    func collectSupportDiagnostics() async throws
        -> SupportDiagnosticsPackage
    {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"]
            as? String ?? "0"
        let appBuild = info?["CFBundleVersion"] as? String ?? "0"
        let deviceFamily = Self.diagnosticsDeviceFamily()
        #if os(iOS)
        let osFamily = UIDevice.current.systemName + " "
            + UIDevice.current.systemVersion
        #else
        let osFamily = ProcessInfo.processInfo
            .operatingSystemVersionString
        #endif
        let environment = SupportDiagnosticsEnvironment(
            appName: "HTDT Capture",
            appVersion: appVersion,
            appBuild: appBuild,
            deviceModelFamily: deviceFamily,
            osFamilyAndVersion: osFamily,
            emittedSchemaIDs: [
                "htdt.capture.bundle",
                "htdt.capture.field_notes",
                "htdt.field_return",
            ]
        )
        let capabilitySummary = DiagnosticsCapabilitySummary(
            roomPlanEligible: capabilities.roomPlanMeshEligible,
            sceneReconstructionEligible:
                capabilities.sceneReconstructionSupported,
            lidarDepthAvailable: capabilities.sceneDepthSupported,
            smoothedDepthAvailable:
                capabilities.smoothedSceneDepthSupported,
            meshAnchoringAvailable:
                capabilities.worldTrackingSupported
        )
        // Resource events live in the last evaluated quality report;
        // outside a capture there is none — an empty histogram is the
        // honest "no recent capture activity" signal.
        let events = qualityReport?.resourceEvents ?? []
        let storageVerdict = Self.currentStoragePreflight()
            .readiness
        let lastFailureClass = lastFailure.map {
            String(describing: $0)
        }
        return try SupportDiagnosticsCollector.collect(
            environment: environment,
            capabilities: capabilitySummary,
            resourceEvents: events,
            storagePreflightVerdict: storageVerdict,
            persistedCaptureCount:
                persistedInventory.captures.count,
            quarantinedArtifactCount:
                persistedInventory.quarantinedArtifacts.count,
            orphanedWorkingArtifactCount:
                persistedInventory.orphanedWorkingArtifacts.count,
            lastValidationFailureClass: lastFailureClass,
            endpointVerdict: lastEndpointPreflightVerdict,
            endpointCheckedAtUTC: lastEndpointPreflightCheckedAtUTC
        )
    }

    /// Model family only ("iPad") — never a serial or machine
    /// identifier, per the #389 privacy envelope.
    private static func diagnosticsDeviceFamily() -> String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "mac"
        #endif
    }

    /// The last endpoint capability-preflight result (#374), mirrored
    /// into diagnostics (#389) as a reachability verdict class.
    private var lastEndpointPreflightVerdict:
        HTDTCompatibilityVerdict?
    private var lastEndpointPreflightCheckedAtUTC: String?

    func recordEndpointPreflightVerdict(
        _ verdict: HTDTCompatibilityVerdict
    ) {
        lastEndpointPreflightVerdict = verdict
        lastEndpointPreflightCheckedAtUTC =
            BundleTimestamp.utcString(from: Date())
    }

    // MARK: - Field mission returns (#400)

    /// Index of finalized field returns under the capture root —
    /// never inside a capture bundle (issue #400). Draft workspaces
    /// live as `field-returns/<contribution>.draft.json` beside the
    /// finalized `.htdtfieldreturn` artifacts.
    private static func fieldReturnsDirectory(
        captureRoot: URL
    ) -> URL {
        captureRoot.appendingPathComponent(
            "field-returns",
            isDirectory: true
        )
    }

    private static func fieldReturnDraftURL(
        directory: URL,
        contributionID: HTDTFieldReturnID
    ) -> URL {
        directory.appendingPathComponent(
            contributionID.description + ".draft.json"
        )
    }

    /// Field-return draft workspace files under `field-returns/` —
    /// decoded best-effort; a corrupt draft is skipped, never
    /// repaired in place (issue #400).
    private func fieldReturnDrafts(
        directory: URL
    ) -> [HTDTFieldReturnWorkspace] {
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: directory.path)
        else {
            return []
        }
        let decoder = JSONDecoder()
        return names.filter {
            $0.hasSuffix(".draft.json")
        }.compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? decoder.decode(
                HTDTFieldReturnWorkspace.self,
                from: data
            )
        }
    }

    /// Finalized `.htdtfieldreturn` artifact files under
    /// `field-returns/` — listed in mission history (#400).
    func fieldReturnArtifacts() -> [URL] {
        guard let root = Self.captureRootDirectory(),
              let names = try? FileManager.default
                  .contentsOfDirectory(
                      atPath: Self
                          .fieldReturnsDirectory(captureRoot: root)
                          .path
                  )
        else {
            return []
        }
        return names.filter {
            $0.hasSuffix(".htdtfieldreturn")
        }.sorted().map {
            Self.fieldReturnsDirectory(captureRoot: root)
                .appendingPathComponent($0)
        }
    }

    /// Finalized field-return documents for mission history (#400) —
    /// each container is verified on read; a corrupt artifact is
    /// skipped rather than presented as a contribution.
    func listFieldReturns() async
        -> [HTDTFieldReturnDocument]
    {
        fieldReturnArtifacts().compactMap { url in
            try? HTDTFieldReturnArchiveReader.read(
                archive: url
            ).document
        }
    }

    /// Opens the field-return workspace for a mission record (#400):
    /// resumes a persisted draft when one exists, otherwise seeds the
    /// task ledger from the mission's plan items with the per-task
    /// capability preflight applied — spatial tasks enter the ledger
    /// disabled with the human-readable reason, non-spatial tasks
    /// stay actionable.
    func openFieldReturnWorkspace(
        missionRecordID: String
    ) async -> HTDTFieldReturnWorkspace? {
        guard let root = Self.captureRootDirectory(),
              let store = missionInboxStore,
              let record = try? store.record(id: missionRecordID)
        else {
            return nil
        }
        let directory = Self.fieldReturnsDirectory(captureRoot: root)
        if let draft = fieldReturnDrafts(directory: directory)
            .first(where: { $0.missionRecordID == missionRecordID }),
           !draft.isFinalized
        {
            return draft
        }

        var workspace = HTDTFieldReturnWorkspace(
            missionRecordID: record.recordID,
            missionID: record.missionID,
            planID: record.planID,
            planVersion: record.planVersion,
            planSHA256: record.planSHA256,
            relatedCaptureRevisionIDs:
                record.associatedCaptureRevisionIDs.compactMap {
                    CaptureRevisionID(canonicalString: $0)
                }
        )
        if let plan = try? store.plan(for: record) {
            let preflight = HTDTFieldTaskPreflightEvaluator.evaluate(
                plan: plan,
                spatialAvailable: capabilities.roomPlanMeshEligible
            )
            try? workspace.seedTaskLedger(preflight: preflight)
        }
        await persistFieldReturnDraft(workspace)
        return workspace
    }

    /// Persists a draft workspace to the field-returns directory so a
    /// relaunch resumes the operator's outcomes (#400).
    func persistFieldReturnDraft(
        _ workspace: HTDTFieldReturnWorkspace
    ) async {
        guard let root = Self.captureRootDirectory() else {
            return
        }
        let directory = Self.fieldReturnsDirectory(captureRoot: root)
        let draftURL = Self.fieldReturnDraftURL(
            directory: directory,
            contributionID: workspace.contributionID
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .sortedKeys, .prettyPrinted,
                .withoutEscapingSlashes,
            ]
            let data = try encoder.encode(workspace)
            try data.write(to: draftURL, options: .atomic)
        } catch {
            workingSetStatus = String(localized: "Field return draft could not be saved") + " ["
                + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Finalizes a field-return workspace into a `.htdtfieldreturn`
    /// container (#400): the assembler embeds the non-spatial
    /// authority documents and evidence assets, the archive writer
    /// produces a stored-ZIP container with a verified
    /// `container-manifest.json`, the index records the finalized
    /// workspace, and the mission record links the contribution.
    /// Returns the artifact URL for sharing.
    func finalizeFieldReturn(
        _ workspace: HTDTFieldReturnWorkspace
    ) async -> URL? {
        guard let root = Self.captureRootDirectory() else {
            return nil
        }
        var finalized = workspace
        let finalizedAt = BundleTimestamp.utcString(from: Date())
        do {
            let artifact = try HTDTFieldReturnAssembler.assemble(
                workspace: workspace,
                provenance: HTDTFieldReturnProvenance(
                    appName: "HTDT Capture",
                    appVersion:
                        Bundle.main.infoDictionary?[
                            "CFBundleShortVersionString"
                        ] as? String ?? "0",
                    deviceModelFamily: Self.diagnosticsDeviceFamily()
                ),
                finalizedAtUTC: finalizedAt
            )
            let directory = Self.fieldReturnsDirectory(
                captureRoot: root
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = directory.appendingPathComponent(
                workspace.contributionID.description
                    + ".htdtfieldreturn"
            )
            try HTDTFieldReturnArchiveWriter.write(
                artifact: artifact,
                to: destination
            )
            finalized.finalizedAtUTC = finalizedAt
            finalized.finalizedDigest = artifact.document
                .contentDigest.value
            var index = try HTDTFieldReturnStore(
                captureRoot: root
            ).load()
            index.workspaces.removeAll {
                $0.contributionID == finalized.contributionID
            }
            index.workspaces.append(finalized)
            try HTDTFieldReturnStore(captureRoot: root).save(index)
            if let missionRecordID = workspace.missionRecordID {
                try? missionInboxStore?.associateFieldReturn(
                    recordID: missionRecordID,
                    contributionID:
                        workspace.contributionID
                )
            }
            try? FileManager.default.removeItem(
                at: Self.fieldReturnDraftURL(
                    directory: directory,
                    contributionID: workspace.contributionID
                )
            )
            refreshMissionDeliveryStores()
            return destination
        } catch {
            workingSetStatus = String(localized: "Field return could not be finalized") + " ["
                + Self.persistenceDiagnostic(error) + "]"
            return nil
        }
    }

    /// Paired Mission receive leg (issue #422): pulls pending
    /// Mission packages from every active paired receiver,
    /// verifies the exact bytes against each descriptor's pinned
    /// digest, and feeds the canonical Mission Inbox importer —
    /// the same validator the Files/share-sheet path uses. Runs as
    /// a bounded foreground action only ("Check HTDT", missions
    /// open, post-pairing); revoked pairings are skipped but their
    /// local records persist. A receiver must be reachable on the
    /// same network with its Mission service running (HTDT #593) —
    /// otherwise pending missions stay pending and the Files/share
    /// import remains the path.
    func checkHTDTForMissions() async
        -> [HTDTMissionReceiveReport]
    {
        guard let root = Self.captureRootDirectory() else {
            return []
        }
        let reports = await HTDTMissionReceiveService(
            captureRoot: root
        ).syncAll()
        refreshMissionDeliveryStores()
        let imported = reports.reduce(0) { $0 + $1.imported }
        let superseded = reports.reduce(0) { $0 + $1.superseded }
        let conflicts = reports.reduce(0) { $0 + $1.conflicts.count }
        let enumerated = reports.reduce(0) { $0 + $1.enumerated }
        if reports.isEmpty {
            workingSetStatus = String(
                localized:
                    "No paired HTDT receivers — pair a receiver or import the mission file"
            )
        } else if imported + superseded > 0 {
            workingSetStatus = "Checked HTDT — "
                + captureCountPhrase(
                    imported + superseded,
                    singular: String(
                        localized: "%lld new mission received into the inbox"
                    ),
                    plural: String(
                        localized: "%lld new missions received into the inbox"
                    )
                )
        } else if conflicts > 0 {
            workingSetStatus = String(
                localized:
                    "Checked HTDT — a pending mission conflicts with a local record; it was not merged"
            )
        } else if enumerated > 0 {
            workingSetStatus = "Checked HTDT — "
                + captureCountPhrase(
                    enumerated,
                    singular: String(
                        localized: "%lld pending mission could not be staged (see receipt ledger)"
                    ),
                    plural: String(
                        localized: "%lld pending missions could not be staged (see receipt ledger)"
                    )
                )
        }
        return reports
    }

    /// Resolves the finalized `.htdtfieldreturn` container's URL
    /// (#423) — nil until finalize has produced the artifact.
    func fieldReturnArtifactURL(
        contributionID: HTDTFieldReturnID
    ) -> URL? {
        guard let root = Self.captureRootDirectory() else {
            return nil
        }
        let url = Self.fieldReturnsDirectory(captureRoot: root)
            .appendingPathComponent(
                contributionID.description + ".htdtfieldreturn"
            )
        return FileManager.default.fileExists(
            atPath: url.path
        ) ? url : nil
    }

    /// Field-return artifact preflight (#423 §5): classifies the
    /// `.htdtfieldreturn` container against the destination's
    /// capability document — kind/schema/size admission, never a
    /// bundle-manifest check against non-bundle bytes. Fetch failure
    /// falls back to the labeled cache; a receiver that cannot take
    /// field returns answers `incompatible` so the Send button can
    /// be disabled with the explanation.
    func preflightFieldReturn(
        contributionID: HTDTFieldReturnID,
        destination: HTDTHandoffDestination
    ) async -> HTDTCompatibilityVerdict {
        guard destination.kind == .endpoint,
              let urlString = destination.url,
              let root = Self.captureRootDirectory()
        else {
            return .unknown(
                reason: "Share destinations accept every artifact"
            )
        }
        guard let document = try? HTDTFieldReturnStore(
            captureRoot: root
        ).load().workspaces.first(where: {
            $0.contributionID == contributionID
        }), document.isFinalized,
              let digest = document.finalizedDigest
        else {
            return .unknown(reason: "Field return not finalized")
        }
        let deliverable = HTDTDeliverableIdentity.fieldReturn(
            contributionID: contributionID,
            contentDigest: digest,
            missionRecordID: document.missionRecordID
        )
        let archiveURL = Self.fieldReturnsDirectory(
            captureRoot: root
        ).appendingPathComponent(
            contributionID.description + ".htdtfieldreturn"
        )
        let archiveBytes = Int64(
            (try? FileManager.default.attributesOfItem(
                atPath: archiveURL.path
            )[.size] as? Int64) ?? 0
        )
        let paired = try? PairedHTDTDestinationStore(
            captureRoot: root
        ).activeDestinations().first(where: {
            $0.endpointURL == urlString
        })
        guard let capabilityURL = paired
            .flatMap({ $0.capabilityEndpointURL })
            .flatMap(URL.init)
            ?? URL(string: urlString)
        else {
            return .unknown(
                reason: "Endpoint has no capability URL"
            )
        }
        do {
            let snapshot = try await HTDTCapabilityClient().fetch(
                endpoint: capabilityURL,
                pinnedIdentity: paired?.pinnedIdentity
            )
            if let paired {
                try? PairedHTDTDestinationStore(captureRoot: root)
                    .updateCachedCapability(
                        destinationID: paired.destinationID,
                        snapshot: snapshot
                    )
            }
            return HTDTCompatibilityChecker.checkDeliverable(
                deliverable: deliverable,
                archiveByteCount: archiveBytes,
                capabilities: snapshot.document,
                requiresMissionReceipts:
                    document.missionRecordID != nil
            )
        } catch {
            if let cached = paired?.cachedCapability {
                return HTDTCompatibilityChecker.checkDeliverable(
                    deliverable: deliverable,
                    archiveByteCount: archiveBytes,
                    capabilities: cached.document,
                    requiresMissionReceipts:
                        document.missionRecordID != nil
                )
            }
            return .unknown(
                reason: String(describing: error)
            )
        }
    }

    /// Sends a finalized `.htdtfieldreturn` container through the
    /// same durable delivery queue captures ride (issue #423): the
    /// job is recorded before any bytes move, idempotent at the
    /// receiver via its stable delivery id, and retries carry the
    /// exact finalized bytes — re-finalization is never required.
    /// The artifact kind travels as `field_return`; no fake
    /// CaptureRevisionID is minted.
    func sendFieldReturnToHTDT(
        contributionID: HTDTFieldReturnID,
        destination: HTDTHandoffDestination
    ) async {
        guard destination.kind == .endpoint,
              let urlString = destination.url,
              URL(string: urlString) != nil
        else {
            workingSetStatus = String(
                localized:
                    "The destination has no valid HTTPS endpoint"
            )
            return
        }
        guard let root = Self.captureRootDirectory() else {
            return
        }
        guard let document = try? HTDTFieldReturnStore(
            captureRoot: root
        ).load().workspaces.first(where: {
            $0.contributionID == contributionID
        }), document.isFinalized,
              let digest = document.finalizedDigest
        else {
            workingSetStatus = String(
                localized:
                    "Finalize the field return before sending it"
            )
            return
        }
        let archiveURL = Self.fieldReturnsDirectory(
            captureRoot: root
        ).appendingPathComponent(
            contributionID.description + ".htdtfieldreturn"
        )
        guard FileManager.default.fileExists(
            atPath: archiveURL.path
        ) else {
            workingSetStatus = String(
                localized:
                    "The finalized field-return file is missing"
            )
            return
        }
        let pairedID = (try? PairedHTDTDestinationStore(
            captureRoot: root
        ).activeDestinations())?.first(where: {
            $0.endpointURL == urlString
        })?.destinationID
        let queue = HTDTDeliveryQueue(captureRoot: root)
        do {
            let (sha, bytes) = try BundleFileReader.sha256(
                archiveURL, maxBytes: Int64.max
            )
            let job = try queue.enqueueFieldReturn(
                contributionID: contributionID,
                contentDigest: digest,
                archiveSHA256: sha,
                archiveByteCount: bytes,
                archiveURL: archiveURL,
                destination: destination,
                pairedDestinationID: pairedID,
                missionRecordID: document.missionRecordID,
                projectRef: nil,
                compatibilitySummary: nil
            )
            if let missionRecordID = document.missionRecordID {
                try? missionInboxStore?.associateDeliveryJob(
                    recordID: missionRecordID,
                    deliveryJobID: job.deliveryJobID
                )
            }
            let jobs = await queue.processDueJobs(
                receiptStore: HTDTHandoffReceiptStore(
                    captureRoot: root
                )
            )
            deliveryJobs = jobs
            switch jobs.first(where: {
                $0.deliveryJobID == job.deliveryJobID
            })?.state {
            case .deliveredStaged:
                workingSetStatus = String(
                    localized:
                        "Field return delivered and staged at the receiver; receipt saved"
                )
            case .rejected:
                workingSetStatus = String(
                    localized:
                        "The receiver rejected the field return; it will not be retried"
                )
            case .blocked:
                workingSetStatus = String(
                    localized:
                        "Delivery is blocked and needs an operator decision (see Deliveries)"
                )
            default:
                workingSetStatus = String(
                    localized:
                        "Field return queued; it will retry under the queue's policy (see Deliveries)"
                )
            }
            refreshMissionDeliveryStores()
        } catch {
            workingSetStatus = String(
                localized:
                    "The field-return delivery could not be queued"
            )
        }
    }

    /// Opens the semantic-correction sheet (#319): the selected
    /// library record's finalized bundle is validated and its semantic
    /// records decoded as the correction's starting point. The parent
    /// stays untouched — edits produce a new child revision only on
    /// explicit commit.
    func beginSemanticCorrection(
        _ record: PersistedCaptureRecord
    ) {
        guard let directory = record.finalizedDirectory else {
            return
        }
        semanticCorrectionParent = record
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let context = await Task.detached(
                priority: .userInitiated
            ) {
                try? SemanticChildRevisionBuilder.loadContext(
                    parentDirectory: directory
                )
            }.value
            guard let context,
                  self.semanticCorrectionParent?
                        .captureRevisionID
                        == record.captureRevisionID
            else {
                if self.semanticCorrectionParent?
                        .captureRevisionID
                        == record.captureRevisionID
                {
                    self.workingSetStatus = String(localized: "The selected capture could not be opened for correction")
                    self.semanticCorrectionParent = nil
                }
                return
            }
            self.semanticCorrectionContext = context
        }
    }

    /// Builds the semantic child revision (#319): metadata edits only —
    /// the parent's sensor evidence is carried over byte-for-byte and
    /// the child gets its own lifecycle timestamps plus the exact
    /// semantic diff in `revision/intent.json`.
    func commitSemanticCorrection(
        _ edits: SemanticChildRevisionEdits
    ) async -> Bool {
        guard !semanticCorrectionInFlight,
              let context = semanticCorrectionContext,
              semanticCorrectionParent != nil,
              let captureRoot = Self.captureRootDirectory()
        else {
            return false
        }
        semanticCorrectionInFlight = true
        defer {
            semanticCorrectionInFlight = false
        }
        let childRevisionID = CaptureRevisionID(rawValue: UUID())
        let stagingDirectory = captureRoot
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                childRevisionID.description,
                isDirectory: true
            )
        let destinationDirectory = captureRoot
            .appendingPathComponent("finalized", isDirectory: true)
            .appendingPathComponent(
                childRevisionID.description,
                isDirectory: true
            )
        let runtime = PlatformRuntimeProvenance.current()
        do {
            let built = try await SemanticChildRevisionBuilder.build(
                context: context,
                childRevisionID: childRevisionID,
                edits: edits,
                stagingDirectory: stagingDirectory,
                destinationDirectory: destinationDirectory,
                app: BundleAppIdentity(
                    version: runtime.appVersion,
                    build: runtime.appBuild
                )
            )
            try? CaptureStoragePolicy.applyFileProtection(
                to: built.bundleDirectory
            )
            if let originStore = captureOriginStore,
               let originRecord =
                   try? CaptureAcquisitionOriginRecord(
                    captureRevisionID: childRevisionID,
                    kind: .createdOnThisDevice,
                    transport: .localCapture,
                    acquiredAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    ),
                    bundleDigestSHA256:
                        built.bundleDigestSHA256.value
                   )
            {
                try? originStore.record(originRecord)
                captureOrigins[childRevisionID] = originRecord
            }
            semanticCorrectionContext = nil
            semanticCorrectionParent = nil
            workingSetStatus = String(localized: "Created a corrected revision that reuses the original scan evidence")
            loadPersistedCaptures()
            return true
        } catch {
            workingSetStatus = String(localized: "The corrected revision could not be created") + " [\(Self.persistenceDiagnostic(error))]"
            return false
        }
    }

    func cancelSemanticCorrection() {
        semanticCorrectionContext = nil
        semanticCorrectionParent = nil
    }

    private static func captureRootDirectory() -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
    }

    /// #352: freezes the mission the operator chose on the setup
    /// screen onto the fresh working revision — the imported HTDT
    /// task-plan bytes persist verbatim at
    /// `session/capture-task-plan.json` with an initial all-pending
    /// status document at `session/task-plan-status.json`, or the
    /// generic task profile is recorded. Either binding writes a
    /// `mission_bound` provenance note; a persistence failure surfaces
    /// on the status line, never silently.
    private func bindPendingMission(
        store: CaptureWorkingSetStore,
        revisionID: CaptureRevisionID,
        context: CaptureSessionContext
    ) async {
        do {
            if let planImport = pendingTaskPlanImport {
                try await store.persistSupplementalDocument(
                    WorkingSetSupplementalDocument(
                        path: CaptureTaskPlanImport.path,
                        data: planImport.data,
                        declaration: BundlePayloadDeclaration(
                            path: CaptureTaskPlanImport.path,
                            mediaType: "application/json",
                            producer: "htdt_plan",
                            provenanceClass: .importedReference,
                            role: .canonical
                        ),
                        coordinateSpaceIDs: [
                            context.coordinateSpaceID,
                        ],
                        captureSessionIDs: [
                            context.captureSessionID,
                        ]
                    )
                )
                let status = CaptureTaskPlanStatus(
                    planImport: planImport
                )
                boundTaskPlanStatus = status
                let statusData = try status.statusPackage(
                    captureRevisionID: revisionID,
                    captureSessionID: context.captureSessionID,
                    annotations: [],
                    measurements: []
                )
                try await store.replaceSupplementalDocument(
                    WorkingSetSupplementalDocument(
                        path: CaptureTaskPlanStatusDocument.path,
                        data: statusData,
                        declaration: BundlePayloadDeclaration(
                            path: CaptureTaskPlanStatusDocument.path,
                            mediaType: "application/json",
                            producer: "capture_session",
                            provenanceClass: .captureAppDerived,
                            role: .canonical
                        ),
                        coordinateSpaceIDs: [
                            context.coordinateSpaceID,
                        ],
                        captureSessionIDs: [
                            context.captureSessionID,
                        ]
                    )
                )
                try? await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .missionBound,
                        sessionTimestampSeconds: 0,
                        detail:
                            "mission=htdt_task_plan plan_id=\(planImport.plan.planID) plan_version=\(planImport.plan.planVersion) plan_sha256=\(planImport.planSHA256.value)"
                    )
                )
            } else if let taskProfile {
                try await store.recordTaskProfile(
                    taskProfile,
                    skippedRequirementIDs:
                        skippedTaskRequirementIDs
                )
                try? await store.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .missionBound,
                        sessionTimestampSeconds: 0,
                        detail:
                            "mission=task_profile profile=\(taskProfile.identifier)"
                    )
                )
            }
        } catch {
            boundTaskPlanStatus = nil
            workingSetStatus += String(localized: " (mission binding failed)")
        }
    }

    private static func makePersistedStore()
        -> PersistedCaptureInventory?
    {
        guard let captureRoot = captureRootDirectory() else {
            return nil
        }
        return PersistedCaptureInventory(
            captureRoot: captureRoot
        )
    }

    /// App-owned catalog library (#302): every imported snapshot kept
    /// under its content key with an explicit active-selection pointer.
    /// The legacy single-slot cache file (`imported-equipment-catalog
    /// .json`, #211) migrates in on first use. The directory lives
    /// directly under the capture app-support root — outside
    /// `finalized/`, `exports/` and `working/` — so the persisted-
    /// capture inventory never classifies it as a capture artifact and
    /// no catalog bytes ever enter a bundle.
    private static func makeEquipmentCatalogLibrary()
        -> HTDTEquipmentCatalogLibrary?
    {
        captureRootDirectory().map {
            HTDTEquipmentCatalogLibrary(
                directory: $0.appendingPathComponent(
                    "equipment-catalogs",
                    isDirectory: true
                ),
                legacyFileURL: $0.appendingPathComponent(
                    "imported-equipment-catalog.json",
                    isDirectory: false
                )
            )
        }
    }

    /// #458: the roster file sits directly under the capture root —
    /// outside `finalized/`, `exports/` and `working/` — for the same
    /// reason the equipment catalog does: the persisted-capture
    /// inventory must never classify app-owned identity metadata as a
    /// capture artifact.
    private static func makeOperatorRosterStore()
        -> HTDTOperatorProfileRosterStore?
    {
        captureRootDirectory().map {
            HTDTOperatorProfileRosterStore(captureRoot: $0)
        }
    }

    /// #458: remember an operator profile app-wide (upsert by
    /// `operator_id`). Called when the workspace saves an Author
    /// profile — committed captures keep their own immutable copy.
    func updateOperatorRoster(_ profile: OperatorProfile) {
        guard let store = operatorRosterStore,
              let roster = try? store.upsert(profile)
        else {
            return
        }
        operatorRoster = roster.operators
    }

    /// #458: forget a roster profile; in-capture records keep the
    /// copy they already committed.
    func removeFromOperatorRoster(
        operatorID: OperatorProfileID
    ) {
        guard let store = operatorRosterStore,
              let roster = try? store.remove(operatorID: operatorID)
        else {
            return
        }
        operatorRoster = roster.operators
    }

    private func continueBeginCapture() async {
        capabilities = PlatformCapabilityProbe.current()

        guard capabilities.roomPlanMeshEligible else {
            fail(.unsupportedDevice)
            return
        }

        do {
            try transition(.capabilitiesAccepted)
        } catch {
            fail(.unknown)
            return
        }

        cameraPermission = CameraPermissionController.currentStatus()
        if cameraPermission != .authorized {
            cameraPermission =
                await CameraPermissionController.requestAccessIfNeeded()
        }

        guard cameraPermission == .authorized else {
            // #295: a denied/restricted/unavailable camera is a
            // recoverable prerequisite, not a failed capture. Stay in
            // `.permissions` so the operator can open iOS Settings or
            // retry; no working revision is created for a pre-capture
            // permission failure.
            workingSetStatus = String(localized: "Camera permission is required before capture can start")
            return
        }

        do {
            try transition(.permissionsGranted)
        } catch {
            fail(.unknown)
            return
        }

        await continueCapturePreparation()
    }

    /// Everything after the permission gate (#295): working-set
    /// creation, handler binding, `.prepared` → `.scanning`. Reached
    /// from `continueBeginCapture` or from a permission retry after
    /// the operator enabled camera access in Settings.
    private func continueCapturePreparation() async {
        let prepared: (
            store: CaptureWorkingSetStore,
            identity: CaptureWorkingSetIdentity,
            generation: UUID,
            rootDirectory: URL,
            storagePolicyWarnings: [String]
        )
        do {
            prepared = try makeWorkingSet()
        } catch {
            fail(.persistenceFailure)
            return
        }

        workingSetStore = prepared.store
        workingSetIdentity = prepared.identity
        captureGeneration = prepared.generation
        workingSetStatus = String(
            format: String(localized: "Prepared revision %@"),
            prepared.identity.captureRevisionID.description
        )

        // Backup-exclusion / Data Protection failures never silently
        // pass: they enter the revision's own resource-event record and
        // remain visible in the working-set status (#136, #166).
        if !prepared.storagePolicyWarnings.isEmpty {
            for warning in prepared.storagePolicyWarnings {
                await prepared.store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "working-revision storage policy was not fully applied: "
                            + warning
                    )
                )
            }
            workingSetStatus +=
                String(localized: " (storage protection policy incomplete)")
        }

        let context = sessionController.context
        let runtime = PlatformRuntimeProvenance.current()
        let generation = prepared.generation
        let store = prepared.store

        // Mission payloads imported before the working set existed
        // persist into this revision now (#353); a pending repair
        // link binds it to the task it answers (#321).
        await activateStagedMissionState(store: store)

        // #352: bind the mission configured on the setup screen to the
        // new working revision before any scan sample lands — plan
        // identity+version are recorded verbatim; the mission is
        // workflow intent, never observed truth.
        await bindPendingMission(
            store: store,
            revisionID: prepared.identity.captureRevisionID,
            context: context
        )
        sessionController.setRoomPlanCompletionHandler {
            [weak self] data, error in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            self.handleRoomPlanCompletion(
                data,
                frameworkFailed: error != nil,
                store: store,
                generation: generation,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                runtime: runtime
            )
        }

        // CONTRACT (#168): the sibling platform agent exposes an
        // ARSession lifecycle surface `sessionLifecycleHandler` on
        // SharedARSessionController delivering interruption-began,
        // interruption-ended, and terminal-failure events on MainActor.
        // Bind it to this capture generation so stale callbacks from a
        // prior session authority cannot reach the current working set.
        sessionController.sessionLifecycleHandler = {
            [weak self] event in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }
            self.handleSessionLifecycleEvent(
                event,
                store: store,
                generation: generation
            )
        }

        // Bounded mesh lifecycle + RoomPlan instruction diagnostics
        // (#268/#260). Both are advisory provenance sinks on the store,
        // never quality gates.
        sessionController.meshAnchorLifecycleHandler = {
            [weak self] kind, anchorIDs, timestampSeconds in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                for anchorID in anchorIDs {
                    await store.recordMeshAnchorLifecycle(
                        kind,
                        anchorID: anchorID,
                        sessionTimestampSeconds: timestampSeconds
                    )
                }
            }
        }
        sessionController.roomPlanInstructionHandler = {
            [weak self] observation in
            Task { @MainActor [weak self] in
                guard let self,
                      self.captureGeneration == generation
                else {
                    return
                }
                await store.recordRoomPlanGuidanceInstruction(
                    observation
                )
            }
        }
        // A RoomCaptureSession end outside the bounded End transaction
        // stops the room model accumulating while the operator still
        // sees a scanning surface — record it as provenance and say so.
        // Inside End (`isEndingScan`) the transaction already owns the
        // transition, so the callback is expected there.
        sessionController.roomPlanDidEndHandler = {
            [weak self] errorDescription in
            Task { @MainActor [weak self] in
                guard let self,
                      self.captureGeneration == generation,
                      self.state == .scanning,
                      !self.isEndingScan
                else {
                    return
                }
                let detail =
                    errorDescription.map {
                        "ended_with_error error=\($0)"
                    } ?? "ended_without_error"
                self.recordAdvisoryNote(
                    CaptureAdvisoryNote(
                        kind: .roomPlanSessionEnded,
                        sessionTimestampSeconds:
                            self.latestScanTimestampSeconds ?? 0,
                        detail: detail
                    )
                )
                if errorDescription != nil {
                    self.workingSetStatus =
                        String(localized: "RoomPlan scanning ended unexpectedly; press End to finish with the evidence captured so far, or discard")
                }
            }
        }

        // Benchmark binding (#285): resolve refs whose compatibility
        // predicates deterministically match this capture's app/device/
        // OS/configuration context. An empty authority publishes an
        // explicit empty list.
        let deviceDocument =
            try? PlatformRuntimeProvenance.currentDeviceDocument()
        let benchmarkRefs =
            BenchmarkReferenceAuthority.compatibleReferences(
                context: BenchmarkBindingContext(
                    appVersion: runtime.appVersion,
                    deviceClass:
                        deviceDocument?.hardwareModel ?? "unknown",
                    osMajorVersion: ProcessInfo.processInfo
                        .operatingSystemVersion.majorVersion,
                    captureMode: CaptureMode.roomPlanMesh.rawValue,
                    rulesetVersion: qualityRequirements.rulesetVersion,
                    bundleSchemaVersion: "1.0.0"
                )
            )
        do {
            try await store.recordBenchmarkReferences(benchmarkRefs)
        } catch {
            await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: .persistenceFailure,
                    severity: .warning,
                    detail:
                        "benchmark reference binding was rejected: "
                        + "\(error)"
                )
            )
        }

        // Discard races: the abort can run while preparation is
        // suspended — before `workingSetStore` was published (the
        // store exists locally but the abort saw nil) or after it was
        // already torn down. Either way the state/generation fence
        // decides; a locally-created store the abort could not see is
        // removed here so it never survives as an orphan.
        guard state == .preparing,
              captureGeneration == generation
        else {
            if workingSetStore === store {
                workingSetStore = nil
                try? await store.discardIncompleteRevision()
            }
            return
        }

        do {
            try transition(.prepared)
        } catch {
            fail(.unknown)
            return
        }

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        configureResourceMonitor(
            store: store,
            rootDirectory: prepared.rootDirectory,
            generation: generation
        )
        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        workingSetStatus = String(localized: "Presenting the live RoomPlan camera…")

        let liveViewReady =
            await sessionController
                .waitForLiveRoomCaptureViewPresentation()

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        guard liveViewReady else {
            workingSetStatus = String(localized: "The live RoomPlan camera view did not attach in time")
            fail(.roomPlanFailure)
            return
        }

        let startedAtUTC = BundleTimestamp.utcString(
            from: Date()
        )
        do {
            try sessionController.startRoomPlan()
            noteRoomPlanScanSegment()
        } catch {
            await store.recordRoomPlanGuidanceUnavailable()
            workingSetStatus = String(localized: "RoomPlan could not start after the live camera view was presented")
            fail(.roomPlanFailure)
            return
        }

        // #200: RoomPlan's run() necessarily starts the shared ARSession,
        // so the first usable monotonic↔UTC correlation is captured
        // immediately here — before the active-configuration retry window
        // and before session-foundation persistence, which must not delay
        // the start-boundary sample. The correlation's method label
        // ("bracketed_first_arframe_at_session_start") records that this
        // is the first frame delivered after the start request; any
        // framework-internal observation between run() and that frame
        // precedes the stored correlation interval.
        do {
            captureStartTimingCorrelation =
                try await waitForInitialTimingCorrelation()
        } catch {
            workingSetStatus = String(localized: "AR tracking did not produce an initial frame in time")
            fail(.trackingUnavailable)
            return
        }

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        let activeConfiguration: CaptureConfigurationProfile
        do {
            activeConfiguration =
                try await waitForActiveConfiguration()
        } catch PlatformCaptureError
            .requestedCaptureModeUnsatisfied(let resolved)
        {
            workingSetStatus = String(localized: "RoomPlan started, but the running AR configuration cannot produce mesh (resolved mode: \(resolved.rawValue)); the capture was stopped rather than persisting a mesh claim")
            fail(.roomPlanFailure)
            return
        } catch {
            workingSetStatus = String(localized: "RoomPlan started, but the active AR configuration was not available in time")
            fail(.roomPlanFailure)
            return
        }

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        let foundation: CaptureSessionFoundationPackage
        do {
            // Combined-mode probe: RoomPlan is running now, so the
            // running-phase observation can verify whether scene
            // reconstruction + scene depth are jointly active on this
            // session before the foundation is sealed write-once.
            let probedCapabilities = PlatformCapabilityProbe
                .applyingCombinedFeatureVerification(
                    sessionController
                        .currentCombinedFeatureObservation(
                            roomPlanPhase: .running
                        ),
                    to: capabilities
                )
            foundation =
                try CaptureSessionFoundationPackageBuilder.build(
                    context: context,
                    capabilities: probedCapabilities,
                    configurationProfile: activeConfiguration,
                    startedAtUTC: startedAtUTC,
                    device:
                        try PlatformRuntimeProvenance
                            .currentDeviceDocument()
                )
            try await store.persistSessionFoundation(foundation)
        } catch {
            workingSetStatus = String(localized: "Capture session metadata could not be persisted")
            fail(.persistenceFailure)
            return
        }

        // Strategy provenance (#307): record which published
        // guidance/evidence policy steers this scan so a consumer can
        // read exactly what the advisory budgets were. Advisory
        // provenance only — a write failure degrades to a status note,
        // never a session abort, and the payload never feeds
        // `ready_for_htdt_ingestion`.
        if let strategyPackage = try? CaptureStrategyPackageBuilder
            .build(
                document: try CaptureStrategyDocument(
                    captureRevisionID:
                        prepared.identity.captureRevisionID,
                    captureSessionID:
                        foundation.session.captureSessionID,
                    coordinateSpaceID:
                        foundation.session.coordinateSpaceID,
                    profile: activeCaptureStrategy,
                    source: pendingStrategySource,
                    selectedAtUTC: startedAtUTC
                )
            )
        {
            if (try? await store.persistCaptureStrategy(
                strategyPackage
            )) == nil {
                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "capture strategy document could not be persisted; advisory provenance only"
                    )
                )
            }
        }

        // Plan-reference underlay (#322): an operator import held
        // during setup is rebound to the live revision and persisted
        // now that capture/coordinate-space identity exists.
        if planUnderlayDocument != nil {
            await persistPendingPlanUnderlay()
        }

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        startScanCoverageSampling(
            generation: generation
        )
        startStorageSampling(
            store: store,
            generation: generation
        )
        workingSetStatus = String(localized: "Scanning; live RoomPlan camera and active AR configuration are ready")
    }

    /// Periodic storage accounting for the #308 advisory surface. Runs
    /// at the resource-monitor cadence while `.scanning`; each sample
    /// recomputes the working revision's retained bytes by category,
    /// the measured device free space against the warning/critical
    /// thresholds, and the automatic-keyframe budget usage. Advisory
    /// only — a failed sample degrades to `unknown`, never a gate.
    private func startStorageSampling(
        store: CaptureWorkingSetStore,
        generation: UUID
    ) {
        storageSampleTask?.cancel()
        let policy = CaptureResourceMonitorPolicy()
        storageSampleTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }
                let profileSample = await Task.detached(
                    priority: .utility
                ) {
                    try await store.storageProfile()
                }.result
                let profile: CaptureWorkingSetStorageProfile
                let profileScanFailed: Bool
                switch profileSample {
                case .success(let sampled):
                    profile = sampled
                    profileScanFailed = false
                case .failure:
                    // Scan failure means the working set crossed the
                    // scanner's size caps and can no longer seal —
                    // report critical pressure and keep the last
                    // measured profile instead of publishing zeros.
                    profile = self.evidenceStorageAdvisory?.profile
                        ?? CaptureWorkingSetStorageProfile()
                    profileScanFailed = true
                }
                let availableBytes =
                    Self.measuredAvailableStorageBytes()
                let band: CaptureStoragePressureBand
                if profileScanFailed {
                    band = .critical
                } else if let availableBytes {
                    if availableBytes <= policy.storageCriticalBytes {
                        band = .critical
                    } else if availableBytes
                        <= policy.storageWarningBytes
                    {
                        band = .warning
                    } else {
                        band = .nominal
                    }
                } else {
                    band = .unknown
                }
                self.evidenceStorageAdvisory =
                    CaptureEvidenceStorageAdvisory(
                        profile:
                            profile
                                ?? CaptureWorkingSetStorageProfile(),
                        evidenceFrameCount:
                            self.scanEvidenceFrameCount,
                        depthEvidenceCount:
                            self.scanDepthEvidenceCount,
                        deviceAvailableBytes: availableBytes,
                        pressureBand: band,
                        storageWarningBytes:
                            policy.storageWarningBytes,
                        storageCriticalBytes:
                            policy.storageCriticalBytes,
                        keyframeBudget:
                            AutomaticKeyframeBudgetStatus(
                                tracker:
                                    self.automaticKeyframeTracker
                            )
                    )
                try? await Task.sleep(
                    for: policy.storageSampleInterval,
                    clock: .continuous
                )
            }
        }
    }

    /// Measured device free capacity for important usage (#308):
    /// nil when the platform cannot report a value — the UI then
    /// shows "unknown" rather than a fabricated number.
    private static func measuredAvailableStorageBytes() -> Int64? {
        guard let root = captureRootDirectory(),
              let value = try? root.resourceValues(
                forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey
                ]
              ).volumeAvailableCapacityForImportantUsage
        else {
            return nil
        }
        return Int64(max(0, value))
    }

    /// Re-check camera authorization while the permission gate is
    /// open (#295): granted resumes the ordinary preparation
    /// pipeline; anything else only refreshes the displayed state.
    func retryCameraPermission() {
        guard state == .permissions else {
            return
        }
        cameraPermission =
            CameraPermissionController.currentStatus()
        guard cameraPermission == .notDetermined else {
            continueAfterPermissionIfAuthorized()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            cameraPermission = await CameraPermissionController
                .requestAccessIfNeeded()
            continueAfterPermissionIfAuthorized()
        }
    }

    /// Foreground refresh (#295): an iOS Settings trip can flip camera
    /// authorization; an authorized status resumes capture
    /// preparation and refreshes the setup presentation when pending.
    func sceneDidBecomeActive() {
        cameraPermission =
            CameraPermissionController.currentStatus()
        if state == .permissions {
            continueAfterPermissionIfAuthorized()
        } else if state == .setup {
            refreshCaptureSetupPresentation()
        }
    }

    /// Opens the app's iOS Settings page where the operator can enable
    /// camera access (#295). Platforms without a Settings deep link
    /// treat this as a no-op.
    func openCameraSettings() {
        #if os(iOS) && canImport(UIKit)
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }
        UIApplication.shared.open(url)
        #endif
    }

    /// Leaves the capability/permission gate without a capture (#295):
    /// nothing was started, so no working revision exists to clean up.
    func cancelCaptureStart() {
        guard state == .capabilityCheck
                || state == .permissions
        else {
            return
        }
        do {
            try transition(.reset)
        } catch {
            fail(.unknown)
            return
        }
        workingSetStatus = String(localized: "Ready")
    }

    private func continueAfterPermissionIfAuthorized() {
        guard state == .permissions,
              cameraPermission == .authorized
        else {
            return
        }
        do {
            try transition(.permissionsGranted)
        } catch {
            fail(.unknown)
            return
        }
        Task { @MainActor [weak self] in
            await self?.continueCapturePreparation()
        }
    }

    private func updateLiveEndScanGuidance() {
        guard !isEndingScan else {
            return
        }

        guard state == .scanning else {
            endScanGuidance = nil
            return
        }

        guard scanGuidanceProgress.isComplete else {
            // Before basic scan completion, normal scan guidance remains the
            // primary instruction.
            if endScanGuidance != nil {
                endScanGuidance = nil
            }
            return
        }

        if scanCoverage.latestTrackingState == .unavailable {
            endScanGuidance = String(localized: "Before ending: hold the phone steady and point it at previously scanned room features until tracking recovers.")
            return
        }

        let hasPersistedDepth = scanDepthEvidenceCount > 0
        let hasLiveDepth = spatialCoverage.latestHasSceneDepth
        let hasMesh =
            spatialCoverage.meshAvailability.state
                == .anchorsObserved

        if !hasPersistedDepth,
           !hasLiveDepth,
           !hasMesh
        {
            endScanGuidance = String(localized: "Before ending: no usable depth or mesh evidence is available. Keep the target in view and move slowly until Scene Depth observation appears.")
            return
        }

        if endScanPreflightBlocked {
            // A failed End attempt leaves its failure text on screen,
            // but the live conditions just checked are healthy again —
            // replace it with a truthful retry hint. Pressing End
            // re-runs the full preflight either way.
            endScanGuidance = String(localized: "The issue that blocked End may have cleared. Press End to try again.")
            return
        }

        endScanGuidance = nil
    }

    private struct PreparedEndScanAttempt {
        let trackingQualityEvent: TrackingQualityEvent
        let framePackage: FrameEvidencePackage
        let meshPackage: MeshEvidencePackage?
        let meshSnapshotUnavailable: Bool
    }

    private struct PendingEndScanAttempt {
        let id: UUID
        let timingPackage: CaptureTimingPackage
        let meshSnapshotUnavailable: Bool
    }

    private func prepareEndScan(
        generation: UUID
    ) async -> PreparedEndScanAttempt? {
        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return nil
        }

        endScanPreflightBlocked = false
        var succeeded = false
        defer {
            if captureGeneration == generation,
               state == .scanning
            {
                endScanPreflightBlocked = !succeeded
            }
        }

        guard let store = workingSetStore else {
            endScanGuidance = String(localized: "Cannot end yet: capture working data is unavailable. Start a fresh capture.")
            return nil
        }

        guard let startTiming = captureStartTimingCorrelation else {
            endScanGuidance = String(localized: "Cannot end yet: capture timing has not initialized. Keep the phone steady for a moment; if this does not clear, restart the capture.")
            return nil
        }

        let snapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return nil
        }

        do {
            let values = try snapshot.rootDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            if let available =
                values.volumeAvailableCapacityForImportantUsage
            {
                let policy = CaptureResourceMonitorPolicy()
                if available < policy.storageCriticalBytes {
                    endScanGuidance = String(localized: "Cannot end safely: device storage is below the capture safety threshold. Free storage, then try End again.")
                    return nil
                }
            }
        } catch {
            // Failure to query free space is not itself a proven capture
            // failure. The real pre-stop persistence attempt below remains
            // authoritative.
        }

        guard state == .scanning else {
            return nil
        }

        let evidence: CaptureReviewEvidenceSnapshot
        do {
            evidence = try sessionController.snapshotReviewEvidence(
                depthSelection: .discrete
            )
        } catch PlatformCaptureError.currentFrameUnavailable {
            endScanGuidance = String(localized: "Cannot end yet: there is no current AR frame. Hold the phone steady and point it at previously scanned features until tracking is normal, then try End again.")
            return nil
        } catch {
            endScanGuidance = String(localized: "Cannot end yet: the selected camera/depth frame could not be prepared. Hold the phone steady on the target for 1–2 seconds, then try End again.")
            return nil
        }

        if evidence.trackingQualityEvent.state == .unavailable {
            endScanGuidance = String(localized: "Cannot end yet: AR tracking is unavailable in the frame that would be saved. Hold the phone steady on previously scanned room features until tracking returns to normal, then try End again.")
            return nil
        }

        let endTiming: CaptureTimingCorrelation
        do {
            endTiming =
                try sessionController.snapshotTimingCorrelation(
                    boundary: .sessionEnd
                )
        } catch {
            endScanGuidance = String(localized: "Cannot end yet: the current AR frame cannot be correlated to capture time. Keep the phone steady until tracking recovers, then try End again.")
            return nil
        }

        // #177: binary packing, hashing and the HEIC preview for the
        // retained End frame run off MainActor inside the materialize
        // boundary; the synchronous snapshot above already rejected an
        // unavailable-tracking frame before this expensive step.
        let endFrameArtifacts: CapturedFrameArtifacts
        do {
            endFrameArtifacts = try await ARFrameArtifactAdapter
                .materialize(evidence.frameArtifacts)
        } catch {
            endScanGuidance = String(localized: "Cannot end yet: the selected camera/depth frame could not be prepared. Hold the phone steady on the target for 1–2 seconds, then try End again.")
            return nil
        }

        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return nil
        }

        let framePackage: FrameEvidencePackage
        do {
            framePackage = try FrameEvidencePackageBuilder.build(
                descriptor: endFrameArtifacts.descriptor,
                pixelPayload: endFrameArtifacts.pixelPayload,
                depthPayload: endFrameArtifacts.depthPayload,
                confidencePayload:
                    endFrameArtifacts.confidencePayload,
                previewPayload:
                    endFrameArtifacts.previewPayload
            )
            // Preflight only: prove the start/end correlation builds a
            // valid package before any persistence work starts. The
            // committed package is rebuilt in endScanForReview with a
            // fresher session-end correlation, so this one is
            // intentionally discarded.
            _ = try CaptureTimingPackageBuilder.build(
                start: startTiming,
                end: endTiming
            )
        } catch {
            endScanGuidance = String(localized: "Cannot end yet: the final evidence package is not internally valid. Keep the phone steady and try End again; if it repeats, save one evidence frame before ending.")
            return nil
        }

        let hasDepth =
            snapshot.depthEvidenceCount > 0
            || endFrameArtifacts.depthPayload != nil
        let hasMesh =
            evidence.meshSnapshotSucceeded
            && !evidence.meshAnchors.isEmpty

        if !hasDepth && !hasMesh {
            endScanGuidance = String(localized: "Cannot end yet: this capture has no retained depth evidence and no mesh anchors. Keep a nearby surface in view and move slowly until Scene Depth observation appears, then try End again.")
            return nil
        }

        var meshPackage: MeshEvidencePackage?
        var meshSnapshotUnavailable =
            !evidence.meshSnapshotSucceeded
            || evidence.meshAnchors.isEmpty
        if evidence.meshSnapshotSucceeded,
           !evidence.meshAnchors.isEmpty
        {
            do {
                meshPackage = try MeshEvidencePackageBuilder.build(
                    snapshots: evidence.meshAnchors
                )
            } catch {
                meshSnapshotUnavailable = true
            }
        }

        if !hasDepth,
           meshPackage == nil
        {
            endScanGuidance = String(localized: "Cannot end yet: AR mesh anchors were observed, but they could not be converted into valid retained mesh evidence and no Scene Depth fallback exists. Keep scanning a nearby surface until depth evidence is retained, then try End again.")
            return nil
        }

        endScanGuidance = nil
        succeeded = true
        return PreparedEndScanAttempt(
            trackingQualityEvent: evidence.trackingQualityEvent,
            framePackage: framePackage,
            meshPackage: meshPackage,
            meshSnapshotUnavailable: meshSnapshotUnavailable
        )
    }

    private func endScanForReview(
        _ prepared: PreparedEndScanAttempt,
        generation: UUID
    ) async {
        var handedOffToRoomPlanCompletion = false
        defer {
            if !handedOffToRoomPlanCompletion {
                isEndingScan = false
            }
        }

        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan,
              let store = workingSetStore
        else {
            return
        }

        // Persist the append-only frame/depth evidence first while RoomPlan
        // and the shared ARSession are still live.
        workingSetStatus = String(localized: "Checking that selected frame and depth evidence can be saved before ending")

        do {
            try await store.persistFramePackage(
                prepared.framePackage
            )
        } catch {
            workingSetStatus = String(localized: "Retrying selected frame/depth evidence save before ending")
            try? await Task.sleep(for: .milliseconds(120))

            guard captureGeneration == generation,
                  state == .scanning
            else {
                return
            }

            do {
                try await store.persistFramePackage(
                    prepared.framePackage
                )
            } catch {
                let diagnostic =
                    Self.persistenceDiagnostic(error)

                if error is CaptureWorkingSetError {
                    workingSetStatus =
                        String(localized: "End-frame persistence hit a capture-authority conflict and cannot continue safely")
                        + " ["
                        + diagnostic
                        + "]"
                    fail(.persistenceFailure)
                    return
                }

                do {
                    try await store.discardUncommittedFramePackage(
                        prepared.framePackage
                    )
                } catch {
                    workingSetStatus =
                        String(localized: "End-frame persistence failed and its partial files could not be rolled back safely")
                        + " ["
                        + diagnostic
                        + "]"
                    fail(.persistenceFailure)
                    return
                }

                guard captureGeneration == generation,
                      state == .scanning
                else {
                    return
                }

                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Recoverable pre-stop end-frame persistence failure: "
                            + diagnostic
                    )
                )
                guard captureGeneration == generation,
                      state == .scanning
                else {
                    return
                }
                workingSetStatus =
                    String(localized: "End was not committed because the selected frame/depth evidence could not be saved; this scan is still active")
                    + " ["
                    + diagnostic
                    + "]"
                endScanGuidance = String(localized: "This scan is still active. Check device storage, keep scanning or save another evidence frame if useful, then try End again.")
                endScanPreflightBlocked = true
                return
            }
        }

        // Mark the committed End-boundary frame (issue #241): it is the
        // closing spatial observation and is not removable in the
        // visual evidence review.
        try? await store.markEndBoundaryFrames(
            [prepared.framePackage.descriptor.frameID]
        )

        let frameSnapshot = await store.snapshot()
        guard captureGeneration == generation,
              state == .scanning
        else {
            return
        }
        scanEvidenceFrameCount = frameSnapshot.evidenceFrameCount
        scanDepthEvidenceCount = frameSnapshot.depthEvidenceCount

        let timingPackage: CaptureTimingPackage
        do {
            guard let startTiming = captureStartTimingCorrelation else {
                throw CaptureSessionMetadataError
                    .invalidCorrelationOrder
            }
            let endTiming =
                try sessionController.snapshotTimingCorrelation(
                    boundary: .sessionEnd
                )
            timingPackage =
                try CaptureTimingPackageBuilder.build(
                    start: startTiming,
                    end: endTiming
                )
        } catch {
            workingSetStatus =
                String(localized: "End timing could not be prepared; this scan is still active")
            endScanGuidance = String(localized: "This scan is still active. Hold the phone steady until tracking is normal, then try End again.")
            endScanPreflightBlocked = true
            return
        }

        // Mesh is optional because retained frame/depth evidence is the
        // bounded geometry fallback. Commit it only after every recoverable
        // pre-stop timing check has succeeded, then release its large payload
        // before RoomPlan allocates the final CapturedRoomData/RoomBuilder
        // result.
        var meshSnapshotUnavailable =
            prepared.meshSnapshotUnavailable
        if let meshPackage = prepared.meshPackage {
            workingSetStatus = String(localized: "Saving available mesh evidence before ending")
            do {
                try await store.persistMeshPackage(meshPackage)
            } catch {
                let diagnostic =
                    Self.persistenceDiagnostic(error)

                if error is CaptureWorkingSetError
                    || error is CaptureFileWriterError
                {
                    workingSetStatus =
                        String(localized: "Mesh persistence hit a canonical capture-authority conflict and cannot fall back safely")
                        + " ["
                        + diagnostic
                        + "]"
                    fail(.persistenceFailure)
                    return
                }

                meshSnapshotUnavailable = true
                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Optional pre-stop mesh persistence failed: "
                            + diagnostic
                            + "; retained frame/depth evidence is required for bounded fallback."
                    )
                )

                guard captureGeneration == generation,
                      state == .scanning
                else {
                    return
                }

                if frameSnapshot.depthEvidenceCount == 0 {
                    workingSetStatus =
                        String(localized: "End was not committed because mesh evidence could not be saved and no retained Scene Depth fallback exists")
                        + " ["
                        + diagnostic
                        + "]"
                    endScanGuidance = String(localized: "This scan is still active. Keep a nearby surface in view until depth evidence is retained, then try End again.")
                    endScanPreflightBlocked = true
                    return
                }
            }
        }

        guard captureGeneration == generation,
              state == .scanning
        else {
            return
        }

        await store.recordTrackingEvent(
            prepared.trackingQualityEvent
        )

        guard captureGeneration == generation,
              state == .scanning
        else {
            return
        }

        let attempt = PendingEndScanAttempt(
            id: UUID(),
            timingPackage: timingPackage,
            meshSnapshotUnavailable: meshSnapshotUnavailable
        )
        pendingEndAttempt = attempt
        roomPlanCompletionInFlight = false
        endScanGuidance = String(localized: "Finishing RoomPlan. Keep the phone steady; the capture will stay recoverable until the final RoomPlan result is accepted.")
        workingSetStatus = String(localized: "Waiting for final RoomPlan result")

        // Persist the bounded End-boundary advisory coverage/task
        // context while the tracker state is still live (#223, #217).
        // The report is written later at seal so a rejected End attempt
        // never leaves a stale advisory payload.
        let coverage = scanCoverage
        let spatial = spatialCoverage
        let progress = scanGuidanceProgress
        let stability = observationStability
        let vertical = spatial.vertical
        await store.recordAdvisoryEndContext(
            CaptureEndCoverageSummary(
                // 1.1.0: adds the additive 3D voxel layer summary
                // (#329); older payloads read as azimuth-only 2D.
                algorithm: "advisory-scan-coverage",
                algorithmVersion: "1.1.0",
                endSessionTimestampSeconds:
                    prepared.trackingQualityEvent
                    .sessionTimestampSeconds,
                sectorCount: coverage.sectorCount,
                minimumSamplesPerCell: coverage.minimumSamplesPerCell,
                cellSampleCounts: coverage.cellSampleCounts,
                coverageFraction: coverage.coverageFraction,
                pitchBandFractions: Dictionary(
                    uniqueKeysWithValues:
                        ScanCoveragePitchBand.allCases.map {
                            (
                                String($0.rawValue),
                                coverage.pitchBandCoverageFraction($0)
                            )
                        }
                ),
                weakCells: (0..<coverage.sectorCount).flatMap { sector in
                    ScanCoveragePitchBand.allCases.compactMap { band in
                        coverage.isObserved(
                            sectorIndex: sector,
                            pitchBand: band
                        )
                            ? nil
                            : "\(sector)/\(band.rawValue)"
                    }
                },
                latestTrackingState: coverage.latestTrackingState,
                latestTrackingReason: coverage.latestTrackingReason,
                latestMeshAnchorCount: coverage.latestMeshAnchorCount,
                latestHasSceneDepth: coverage.latestHasSceneDepth,
                spatialCellSizeMeters: spatial.cellSizeMeters,
                observedRegionCount: spatial.observedRegionCount,
                weakRegionCount: spatial.weakRegionCount,
                displayUnknownRegionCount:
                    spatial.displayUnknownRegionCount,
                usesDepthFallback: spatial.usesDepthFallback,
                meshAvailabilityState:
                    spatial.meshAvailability.state.rawValue,
                weakRegionKeys: spatial.regions.filter {
                    $0.classification == .weak
                }.map { "\($0.key.x),\($0.key.z)" },
                geometryEvidenceMode:
                    stability.geometryEvidenceMode.rawValue,
                movementCapability:
                    progress.movementCapability.rawValue,
                guidanceCompletedAttempts:
                    progress.completedSpatialGuidanceAttemptCount,
                guidanceMaximumAttempts:
                    progress.maximumSpatialGuidanceAttempts,
                actionableWeakRegionCount:
                    progress.actionableWeakRegionCount,
                saturatedWeakRegionCount:
                    progress.saturatedWeakRegionCount,
                guidanceComplete: progress.isComplete,
                viewpointDiversitySemantics:
                    "azimuth_elevation_3d",
                verticalCellSizeMeters:
                    vertical.verticalCellSizeMeters,
                verticalVoxelCount: vertical.voxelCount,
                verticalObservedVoxelCount:
                    vertical.observedVoxelCount,
                verticalWeakVoxelCount: vertical.weakVoxelCount,
                verticalWeakVoxelKeys: vertical.voxels
                    .filter {
                        $0.classification == .weak
                    }
                    .map {
                        "\($0.key.x),\($0.key.z),\($0.key.yBand)"
                    },
                verticalBandSummaries: Dictionary(
                    uniqueKeysWithValues: vertical.displayBands
                        .map {
                            (
                                $0.band.rawValue,
                                CaptureVerticalBandSummary(
                                    voxelCount: $0.voxelCount,
                                    observedCount: $0.observedCount,
                                    weakCount: $0.weakCount
                                )
                            )
                        }
                ),
                guidanceCompletionSource:
                    progress.completionSource.rawValue,
                // #347: unresolved weak regions beyond the displayed
                // map window, and #336: the retention capacity outcome
                // — both persist with the end advisory so a completed
                // capture's global/capacity state is never lost.
                remoteWeakRegionCount:
                    progress.remoteWeakRegionCount,
                spatialMaxRegionCount:
                    spatial.capacity.maxRegionCount,
                spatialPeakRegionCount:
                    spatial.capacity.peakRegionCount,
                spatialRegionEvictionCount:
                    spatial.capacity.evictionCount,
                spatialCapacitySaturated:
                    spatial.capacity.isSaturated,
                // #343: sector/octant labels on this capture resolve
                // against the starting facing direction.
                directionReference:
                    StartRelativeDirection.convention
            )
        )
        try? await store.recordTaskProfile(
            taskProfile,
            skippedRequirementIDs: skippedTaskRequirementIDs
        )

        // Advisory live coverage / derived-shape sampling is not End
        // authority. Stop its 250 ms depth/geometry work before RoomPlan
        // allocates and processes the final CapturedRoomData. The tracker
        // state is retained and can resume if this End attempt is rejected.
        scanCoverageTask?.cancel()
        scanCoverageTask = nil

        handedOffToRoomPlanCompletion = true
        sessionController.stopRoomPlanPreservingARSession()

        let attemptID = attempt.id
        let timeoutPolicy = Self.roomPlanEndTimeoutPolicy
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeoutPolicy.warningDelay)
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .scanning,
                  self.isEndingScan,
                  !self.roomPlanCompletionInFlight,
                  self.pendingEndAttempt?.id == attemptID
            else {
                return
            }

            // RoomPlan's callback does not carry this End attempt UUID.
            // Restarting the same RoomCaptureSession here could let a late
            // callback from this unresolved stop be consumed by a later End
            // attempt. Keep waiting briefly, but never leave the operator in
            // an unbounded pseudo-scanning state (#96).
            self.workingSetStatus = String(localized: "RoomPlan is still producing the final result")
            self.endScanGuidance = String(localized: "Final RoomPlan processing is taking longer than usual. Keep the app in the foreground; HTDT will stop this unresolved attempt if RoomPlan does not complete.")

            try? await Task.sleep(
                for: timeoutPolicy.unresolvedGracePeriod
            )
            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  self.isEndingScan,
                  !self.roomPlanCompletionInFlight,
                  self.pendingEndAttempt?.id == attemptID
            else {
                return
            }

            await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: .interruption,
                    severity: .error,
                    detail:
                        "RoomPlan final completion callback was not observed within the bounded 30-second End window."
                )
            )

            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  self.isEndingScan,
                  !self.roomPlanCompletionInFlight,
                  self.pendingEndAttempt?.id == attemptID
            else {
                return
            }

            self.workingSetStatus = String(localized: "RoomPlan did not return a final result within the safe End window; retained evidence remains on disk")
            self.endScanGuidance = nil
            self.fail(.roomPlanFailure)
        }
    }

    private func handleRoomPlanCompletion(
        _ data: CapturedRoomData,
        frameworkFailed: Bool,
        store: CaptureWorkingSetStore,
        generation: UUID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        runtime: CaptureRuntimeProvenance
    ) {
        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan,
              let pending = pendingEndAttempt,
              !roomPlanCompletionInFlight
        else {
            return
        }

        roomPlanCompletionInFlight = true

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .scanning,
                  self.pendingEndAttempt?.id == pending.id
            else {
                return
            }

            if frameworkFailed {
                await self.recoverRoomPlanEndAttempt(
                    diagnostic: "roomplan_framework_failure",
                    store: store,
                    generation: generation
                )
                return
            }

            // #208: raw/processed RoomPlan JSON materialization, hashing
            // and descriptor construction are nonisolated CPU work on
            // the Sendable CapturedRoomData/CapturedRoom values; each
            // `await` suspends this MainActor task so the encoding runs
            // on the cooperative executor instead of blocking the
            // UI/capture actor during the End critical section. The
            // strict ordering — raw payload, processed lineage, then the
            // persistence transaction — is unchanged.
            let raw: RoomPlanRawArtifactPayload
            do {
                raw = try await RoomPlanArtifactProcessor.encodeRaw(
                    data,
                    captureSessionID: captureSessionID,
                    coordinateSpaceID: coordinateSpaceID,
                    runtime: runtime
                )
            } catch {
                await self.recoverRoomPlanEndAttempt(
                    diagnostic:
                        "roomplan_raw_"
                        + RoomPlanArtifactEncoder
                            .diagnosticToken(error),
                    store: store,
                    generation: generation
                )
                return
            }

            let lineage: RoomPlanArtifactLineage
            do {
                lineage =
                    try await RoomPlanArtifactProcessor
                        .deriveProcessed(
                            from: data,
                            rawArtifact: raw
                        )
            } catch {
                await self.recoverRoomPlanEndAttempt(
                    diagnostic: "roomplan_processing_failed",
                    store: store,
                    generation: generation
                )
                return
            }

            do {
                try await store.persistEndRoomPlanTransaction(
                    timingPackage: pending.timingPackage,
                    roomPlanLineage: lineage
                )
            } catch {
                await self.recoverRoomPlanEndAttempt(
                    diagnostic:
                        "roomplan_transaction_"
                        + Self.persistenceDiagnostic(error),
                    store: store,
                    generation: generation
                )
                return
            }

            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  self.pendingEndAttempt?.id == pending.id
            else {
                return
            }

            let meshSnapshotUnavailable =
                pending.meshSnapshotUnavailable

            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  self.pendingEndAttempt?.id == pending.id
            else {
                return
            }

            self.acceptedRoomPlanRawSHA256 =
                raw.descriptor.sha256
            self.acceptedEndMeshWasPersisted =
                !meshSnapshotUnavailable
            self.pendingEndAttempt = nil
            self.roomPlanCompletionInFlight = false
            self.endScanPreflightBlocked = false
            self.endScanGuidance = nil
            self.scanCoverageTask?.cancel()
            self.scanCoverageTask = nil

            do {
                try self.transition(.beginReview)
            } catch {
                self.isEndingScan = false
                self.fail(.unknown)
                return
            }

            await self.refreshQuality(
                store: store,
                generation: generation
            )

            guard self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            self.isEndingScan = false

            // #236: after a re-End following Continue scanning, any
            // committed annotation link that referenced the rolled-back
            // mesh/RoomPlan authority must surface for repair — it is
            // never silently dropped or rewritten.
            self.danglingSpatialIssues =
                await store.committedSpatialEvidenceIssues()
            self.refreshReviewWorkspace()

            // A background/thermal/storage event may have sealed spatial
            // continuation while Review quality was being refreshed. In that
            // case the ordered resource-event path owns the recovery status;
            // do not overwrite it with the generic End-success message.
            guard !self.spatialAuthoritySealedForFinalization else {
                return
            }

            if meshSnapshotUnavailable {
                self.workingSetStatus = String(localized: "Reviewing; frame/depth evidence was retained, but the mesh snapshot was unavailable")
            } else {
                self.workingSetStatus = String(localized: "Reviewing; required end evidence and RoomPlan result were saved")
            }
        }
    }

    private func recoverRoomPlanEndAttempt(
        diagnostic: String,
        store: CaptureWorkingSetStore,
        generation: UUID
    ) async {
        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return
        }

        let ownedMeshWasPersisted =
            pendingEndAttempt?.meshSnapshotUnavailable == false
        pendingEndAttempt = nil
        roomPlanCompletionInFlight = false
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false

        if ownedMeshWasPersisted {
            do {
                try await store.rollbackCurrentMeshPackage()
            } catch {
                isEndingScan = false
                workingSetStatus =
                    String(localized: "The rejected End mesh snapshot could not be rolled back safely")
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                fail(.persistenceFailure)
                return
            }

            guard captureGeneration == generation,
                  state == .scanning,
                  isEndingScan
            else {
                return
            }
        }

        await store.recordResourceEvent(
            CaptureResourceEvent(
                kind: .persistenceFailure,
                severity: .warning,
                detail:
                    "Recoverable RoomPlan end attempt rejected: "
                    + diagnostic
            )
        )

        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return
        }

        do {
            try sessionController.startRoomPlan()
            noteRoomPlanScanSegment()
        } catch {
            isEndingScan = false
            workingSetStatus =
                String(localized: "RoomPlan end failed and scanning could not be restarted")
                + " ["
                + diagnostic
                + "]"
            fail(.roomPlanFailure)
            return
        }

        guard captureGeneration == generation,
              state == .scanning,
              isEndingScan
        else {
            return
        }

        startScanCoverageSampling(
            generation: generation,
            resetTrackers: false
        )

        isEndingScan = false
        endScanPreflightBlocked = true
        workingSetStatus =
            String(localized: "The final RoomPlan result was not accepted; the same HTDT capture is still active")
            + " ["
            + diagnostic
            + "]"
        endScanGuidance = String(localized: "RoomPlan scanning restarted in the same AR coordinate space. Revisit important walls/furniture, continue scanning as needed, then press End again.")
    }

    private func startScanCoverageSampling(
        generation: UUID,
        resetTrackers: Bool = true
    ) {
        scanCoverageTask?.cancel()

        if resetTrackers {
            scanCoverageTracker = AdvisoryScanCoverageTracker()
            scanCoverage = scanCoverageTracker.summary()
            observationStabilityTracker =
                ObservationStabilityTracker()
            observationStability =
                observationStabilityTracker.summary()
            spatialCoverageAggregator =
                SpatialScanCoverageAggregator()
            spatialCoverage = .empty
            // Mid-scan tracker reset keeps the strategy resolved at
            // Begin (#307): the budgets persist for the whole
            // revision, not per sampling restart.
            motionGuidanceTracker = ScanMotionGuidanceTracker(
                configuration:
                    activeCaptureStrategy.motionGuidance
            )
            motionGuidance = nil
            scanGuidanceProgress = .empty
            scanTrackingTransitionGate.reset()
            derivedObjectFusionTracker =
                DerivedShapeTemporalFusionTracker(
                    configuration: DerivedShapeTemporalFusionConfiguration(
                        maximumFrameCount: 6,
                        maximumAgeSeconds: 24,
                        voxelSizeMeters: 0.055,
                        maximumPointCount: 384,
                        maximumObservationCenterShiftMeters: 0.65
                    )
                )
            derivedVolumeFusionTracker =
                DerivedShapeTemporalFusionTracker(
                    configuration: DerivedShapeTemporalFusionConfiguration(
                        maximumFrameCount: 6,
                        maximumAgeSeconds: 24,
                        voxelSizeMeters: 0.055,
                        maximumPointCount: 384,
                        maximumObservationCenterShiftMeters: 0.65
                    )
                )
            derivedWallFusionTracker =
                DerivedShapeTemporalFusionTracker(
                    configuration: DerivedShapeTemporalFusionConfiguration(
                        maximumFrameCount: 4,
                        maximumAgeSeconds: 20,
                        voxelSizeMeters: 0.08,
                        maximumPointCount: 256
                    )
                )
            derivedShapePreview = .empty
        }

        scanCoverageTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var sampleIndex = 0
            while !Task.isCancelled {
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }

                if let sample =
                    try? self.sessionController
                        .currentScanCoverageSample()
                {
                    self.latestScanTimestampSeconds =
                        sample.sessionTimestampSeconds
                    self.scanCoverage =
                        self.scanCoverageTracker.record(sample)
                    self.observationStability =
                        self.observationStabilityTracker.record(
                            sample
                        )
                    self.motionGuidance =
                        self.motionGuidanceTracker.record(
                            timestampSeconds:
                                sample.sessionTimestampSeconds,
                            coverage: self.scanCoverage,
                            spatialCoverage: self.spatialCoverage,
                            observation:
                                self.observationStability
                        )
                    self.scanGuidanceProgress =
                        self.motionGuidanceTracker.progress(
                            coverage: self.scanCoverage,
                            spatialCoverage: self.spatialCoverage
                        )

                    // #283: live lighting assessment drives the
                    // low-light recovery surface; a missing ambient
                    // reading leaves the status `unknown`.
                    self.scanLightingStatus =
                        self.scanLightingPolicy.assess(
                            ambientIntensityLumens:
                                sample.ambientLightIntensityLumens,
                            trackingState: sample.trackingState,
                            trackingReason: sample.trackingReason
                        )
                    self.lowLightGuidanceActive =
                        self.scanLightingPolicy
                            .shouldSurfaceLowLightGuidance(
                                status: self.scanLightingStatus,
                                trackingState: sample.trackingState
                            )

                    // #252: edge-triggered, rate-limited non-visual
                    // cues; 4 Hz sampling never becomes a stream.
                    if self.guidanceCuesEnabled {
                        let cues = self.scanGuidanceCuePolicy.update(
                            ScanGuidanceCueInputs(
                                trackingState: sample.trackingState,
                                guidance: self.motionGuidance,
                                guidanceComplete:
                                    self.scanGuidanceProgress
                                        .isComplete,
                                endScanAvailable:
                                    !self.isEndingScan
                                        && !self.endScanPreflightBlocked
                            ),
                            timestampSeconds:
                                sample.sessionTimestampSeconds
                        )
                        for cue in cues {
                            self.playGuidanceCue(cue)
                        }
                    }

                    // #250: a live targeted-object pass tracks camera
                    // position against its bounded anchor.
                    if self.targetScanTracker != nil,
                       let position = sample.cameraPosition
                    {
                        self.targetScanStatus =
                            self.targetScanTracker?.record(
                                cameraX: position.x,
                                cameraZ: position.z,
                                timestampSeconds:
                                    sample.sessionTimestampSeconds,
                                trackingState: sample.trackingState
                            )
                    }

                    // #273: while the operator armed the return-to-start
                    // check, keep the residual updated each tick.
                    if self.loopClosureCheckActive {
                        self.updateLoopClosureAssessment()
                    }

                    // #216/#274: bounded automatic keyframe selection,
                    // evaluated on the slow (4 s) tick so evidence
                    // writes never join the 250 ms path.
                    if sampleIndex.isMultiple(of: 16) {
                        self.considerAutomaticKeyframe(sample)
                    }

                    // RoomCaptureView may reclaim `arSession.delegate`
                    // asynchronously after `run()`; the bridge only
                    // asserts ownership once at start. Re-assert on the
                    // slow tick — the install keeps the current owner
                    // as passthrough — so mesh-anchor lifecycle and
                    // tracking provenance cannot silently starve.
                    if sampleIndex.isMultiple(of: 16) {
                        self.sessionController
                            .installSessionLifecycleBridge()
                    }

                    // Persist transition-compacted tracking history into
                    // the canonical quality authority (#148). The gate
                    // emits the baseline observation and then only
                    // (state, reason) transitions; identical samples are
                    // compacted and the store bounds retained history.
                    // A transition into .unavailable is recorded
                    // faithfully and surfaces through the existing
                    // tracking_unavailable_observed quality policy. The
                    // End path still records the selected final frame's
                    // tracking event separately; while End holds the
                    // boundary this loop must not append more history.
                    if !self.isEndingScan,
                       let store = self.workingSetStore
                    {
                        let trackingEvent = TrackingQualityEvent(
                            sessionTimestampSeconds:
                                sample.sessionTimestampSeconds,
                            state: sample.trackingState,
                            reason: sample.trackingReason
                        )
                        if self.scanTrackingTransitionGate
                            .shouldRecord(trackingEvent)
                        {
                            await store.recordTrackingEvent(
                                trackingEvent
                            )
                        }
                    }
                }

                if sampleIndex.isMultiple(of: 2),
                   let spatialSample =
                    try? self.sessionController
                        .currentSpatialCoverageSample()
                {
                    let spatialSummary =
                        await self.spatialCoverageAggregator
                            .record(spatialSample)
                    guard self.captureGeneration == generation,
                          self.state == .scanning
                    else {
                        return
                    }
                    self.spatialCoverage = spatialSummary
                    self.updateLiveEndScanGuidance()
                    self.motionGuidance =
                        self.motionGuidanceTracker.record(
                            timestampSeconds:
                                spatialSample.sessionTimestampSeconds,
                            coverage: self.scanCoverage,
                            spatialCoverage: spatialSummary,
                            observation:
                                self.observationStability
                        )
                    self.scanGuidanceProgress =
                        self.motionGuidanceTracker.progress(
                            coverage: self.scanCoverage,
                            spatialCoverage: spatialSummary
                        )

                    if sampleIndex.isMultiple(of: 16) {
                        let thermalState =
                            ProcessInfo.processInfo.thermalState
                        let resourcePressure =
                            self.derivedPreviewSuspendedForMemoryPressure
                            || thermalState == .serious
                            || thermalState == .critical
                        self.setRoomPlanModelRenderingEnabled(
                            !resourcePressure
                        )
                        let derivedWorkAllowed = !resourcePressure

                        if derivedWorkAllowed,
                           (
                                spatialSummary.meshAvailability.state
                                    == .anchorsObserved
                                || spatialSummary.latestHasSceneDepth
                           ),
                           let observations =
                            try? self.sessionController
                                .currentDerivedShapeObservations(
                                    maxObjectPoints: 160,
                                    maxWallPoints: 192
                                )
                        {
                            let timestamp =
                                spatialSample.sessionTimestampSeconds
                            let fused = DerivedShapeLiveObservationSet(
                                objectObservation:
                                    self.derivedObjectFusionTracker.record(
                                        observations.objectObservation,
                                        timestampSeconds: timestamp
                                    ),
                                objectVolumeObservation:
                                    self.derivedVolumeFusionTracker.record(
                                        observations.objectVolumeObservation,
                                        timestampSeconds: timestamp
                                    ),
                                wallObservation:
                                    self.derivedWallFusionTracker.record(
                                        observations.wallObservation,
                                        timestampSeconds: timestamp
                                    ),
                                floorReferenceY:
                                    observations.floorReferenceY
                            )

                            let preview = await Task.detached(
                                priority: .utility
                            ) {
                                Self.buildDerivedShapePreview(
                                    fused
                                )
                            }.value
                            guard self.captureGeneration
                                    == generation,
                                  self.state == .scanning
                            else {
                                return
                            }
                            self.derivedShapePreview = preview
                        }
                    }
                }

                sampleIndex += 1
                try? await Task.sleep(
                    for: .milliseconds(250)
                )
            }
        }
    }

    nonisolated private static func buildDerivedShapePreview(
        _ observations: DerivedShapeLiveObservationSet
    ) -> DerivedShapePreviewSnapshot {
        var objectProxies: [DerivedShapeProxy] = []
        var objectDecomposition: DerivedObjectDecomposition?
        var supportAnalysis: DerivedSupportAnalysis?

        if let objectObservation = observations.objectObservation {
            let volumeObservation =
                observations.objectVolumeObservation
                ?? objectObservation

            let decomposition = DerivedObjectDecomposer.decompose(
                observation: volumeObservation
            )
            objectDecomposition = decomposition

            if decomposition.state != .unresolvedDecomposition {
                let rankedProxies =
                    decomposition.components.prefix(6).flatMap {
                        component in
                        Self.fitDerivedObjectProfiles(
                            component.observation
                        ).map {
                            (
                                proxy: $0,
                                pointCount: component.pointCount
                            )
                        }
                    }

                objectProxies = Array(
                    rankedProxies.sorted { lhs, rhs in
                        let lhsResolved =
                            lhs.proxy.selected != nil
                        let rhsResolved =
                            rhs.proxy.selected != nil
                        if lhsResolved != rhsResolved {
                            return lhsResolved && !rhsResolved
                        }

                        // A tiny geometrically perfect fragment should not
                        // become the compact HUD's primary shape ahead of a
                        // substantially better-supported furniture surface.
                        if lhs.pointCount != rhs.pointCount {
                            return lhs.pointCount > rhs.pointCount
                        }

                        let lhsScore =
                            lhs.proxy.selected?.metrics.fitScore
                            ?? lhs.proxy.provenance.fitScore
                            ?? 0
                        let rhsScore =
                            rhs.proxy.selected?.metrics.fitScore
                            ?? rhs.proxy.provenance.fitScore
                            ?? 0
                        return lhsScore > rhsScore
                    }
                    .prefix(4)
                    .map { $0.proxy }
                )
            } else {
                objectProxies = Self.fitDerivedObjectProfiles(
                    objectObservation
                )
            }

            supportAnalysis = DerivedSupportAnalyzer.analyze(
                observation: volumeObservation,
                floorY: observations.floorReferenceY
            )
        }

        let wallChain = observations.wallObservation.flatMap {
            DerivedShapeProxyFitter.wallChain(
                observation: $0
            )
        }

        return DerivedShapePreviewSnapshot(
            objectProxies: objectProxies,
            wallChain: wallChain,
            supportAnalysis: supportAnalysis,
            objectDecomposition: objectDecomposition,
            disagreements:
                DerivedShapeDisagreementEvaluator.evaluate(
                    objectProxies: objectProxies,
                    wallChain: wallChain
                )
        )
    }

    nonisolated private static func fitDerivedObjectProfiles(
        _ observation: DerivedShapeObservation
    ) -> [DerivedShapeProxy] {
        let fittingObservations: [DerivedShapeObservation]

        if observation.points.contains(where: {
            $0.evidenceKind == .sceneDepth
        }) {
            // A single connected 3D object can legitimately have several
            // materially different horizontal silhouettes (for example a
            // smaller cabinet body on top of a larger base). Preserve those
            // observed levels without forcing the 3D decomposer to split a
            // continuous object.
            fittingObservations =
                DerivedShapeProxyFitter
                    .horizontalProfileObservations(
                        from: observation
                    )
                    .map {
                        DerivedShapeProxyFitter
                            .boundaryObservation(from: $0)
                    }
        } else {
            fittingObservations = [observation]
        }

        return fittingObservations.map {
            DerivedShapeProxyFitter.fit(
                observation: $0
            )
        }
    }

    private func waitForActiveConfiguration()
        async throws -> CaptureConfigurationProfile
    {
        for _ in 0..<60 {
            do {
                // Resolve the mode from the configuration actually
                // running — never assert `.roomPlanMesh`; a session
                // whose scene reconstruction is off must fail closed
                // rather than persist a mesh claim it cannot satisfy.
                let resolution = try sessionController
                    .snapshotActiveConfigurationResolution(
                        requestedMode: .roomPlanMesh
                    )
                if resolution.unsatisfiedRequestedMode != nil {
                    throw PlatformCaptureError
                        .requestedCaptureModeUnsatisfied(
                            resolved: resolution.resolvedCaptureMode
                        )
                }
                return try ARConfigurationSnapshotAdapter.snapshot(
                    session: sessionController.arSession,
                    captureMode: resolution.resolvedCaptureMode
                )
            } catch PlatformCaptureError.configurationUnavailable {
                try await Task.sleep(for: .milliseconds(50))
            } catch ARConfigurationSnapshotError
                .configurationUnavailable
            {
                // The configuration can drop between the resolution
                // and the snapshot — same transient, keep polling.
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        throw PlatformCaptureError.configurationUnavailable
    }

    /// Start-boundary correlation (#200): returns the first bracketed
    /// ARSession frame↔UTC sample available after the start request,
    /// labelled `.sessionStart` so the timing document identifies it as
    /// the earliest observed session time. Invoked immediately after
    /// `startRoomPlan()`, before any unrelated awaits.
    private func waitForInitialTimingCorrelation()
        async throws -> CaptureTimingCorrelation
    {
        for _ in 0..<40 {
            if let correlation =
                try? sessionController.snapshotTimingCorrelation(
                    boundary: .sessionStart
                )
            {
                return correlation
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw PlatformCaptureError.currentFrameUnavailable
    }

    private func refreshQuality(
        store: CaptureWorkingSetStore,
        generation: UUID
    ) async {
        let report = await store.evaluateQuality(
            requirements: self.qualityRequirements
        )
        let snapshot = await store.snapshot()

        // Publish Review UI only after every store-actor suspension has
        // completed. A failure/reset/reopen may invalidate this generation
        // while either call is suspended.
        let advisory = await store.evaluateAdvisoryDiagnostics()

        guard captureGeneration == generation,
              state == .reviewing
        else {
            return
        }

        qualityReport = report
        advisoryReport = advisory
        annotationEvidenceRefs = snapshot.evidenceFrameRefs
        refreshAnnotationEvidenceFrames(
            rootDirectory: await store.rootDirectory
        )
        // Accepted-geometry context for Review plausibility (#247)
        // and RoomPlan binding targets (#246); pure reads of canonical
        // files, advisory only.
        await refreshSpatialContext(
            store: store,
            generation: generation
        )
        (
            annotationRoomPlanSurfaces,
            annotationMeshAnchors
        ) = Self.capturedSurfaceOptions(
            rootDirectory: snapshot.rootDirectory
        )

        // A resource/lifecycle event may have sealed spatial
        // continuation while this refresh was suspended on the store
        // actor. Under the seal the ordered resource-event chain owns
        // the user-facing recovery status (#115); publishing the
        // generic Review quality text here could overwrite that
        // explanation depending on which continuation resumes last.
        // The refreshed report/refs above still publish so a deferred
        // finalization retry observes current quality authority.
        guard !spatialAuthoritySealedForFinalization else {
            return
        }

        if report.readyForHTDTIngestion {
            workingSetStatus = String(
                format: String(localized: "Ready to finalize; %d evidence payloads passed preflight"),
                snapshot.payloadDeclarations.count
            )
        } else {
            let errorCount = report.diagnostics.filter {
                $0.severity == .error
            }.count
            workingSetStatus = captureCountPhrase(
                errorCount,
                singular: String(
                    localized: "Reviewing; %lld blocking quality diagnostic"
                ),
                plural: String(
                    localized: "Reviewing; %lld blocking quality diagnostics"
                )
            )
        }
    }

    private func performFinalization(
        store: CaptureWorkingSetStore,
        quality: CaptureQualityReport,
        generation: UUID
    ) async {
        // Claim the commit transaction before the first suspension so a
        // lifecycle/resource failure can no longer invalidate this
        // generation underneath an in-flight promotion (#185). Ordinary
        // stale callbacks still hit the generation guards below.
        finalizationCommit.claimCommit()

        var promotedRevision: FinalizedCaptureRevision?
        var protectionWarning: String?
        /// The report whose bytes the seal committed to
        /// `quality/capture-quality.json` — distinct from `quality`
        /// whenever the frozen-state evaluation differed from the
        /// pre-seal report, and the payload any abort must roll back.
        var stagedQualityReport: CaptureQualityReport?

        do {
            // #353/#240/#222/#293: mission-derived payloads are part
            // of the bundle — persist before the seal freezes the
            // working set.
            try await persistMissionDerivedDocuments(store: store)

            // #395: when accepted cross-revision registrations name
            // this revision, commit the registrations document now —
            // before the seal — so the frozen snapshot's payload
            // declarations include the transform authority.
            await commitCrossRevisionRegistrations(store)

            // CONTRACT (#180): the sibling store agent adds
            // sealForFinalization()/unseal() on CaptureWorkingSetStore.
            // The seal drains in-flight writes, then rejects further
            // working-set mutations for the rest of the commit
            // transaction so the snapshot and the finalizer's staging
            // scan describe one frozen authority. The seal re-evaluates
            // quality from the frozen state, so it must apply the same
            // ruleset the Review gate used — the default requirements
            // would reject the very report this transaction already
            // persisted (e.g. dropping the depth fallback devices
            // without ARMesh anchors rely on). The sealed report is
            // also the exact quality payload the bundle ships: building
            // the finalization request from the SealedWorkingSet makes
            // the finalizer's staged-bytes equality check true by
            // construction instead of relying on a pre-seal report
            // staying byte-identical to the sealed one.
            let sealed = try await store.sealForFinalization(
                requirements: self.qualityRequirements
            )
            stagedQualityReport = sealed.qualityReport

            guard captureGeneration == generation else {
                // A non-lifecycle failure already invalidated this
                // generation; release the seal and resolve the
                // transaction so the dead store is not left claimed.
                try? await store.unseal()
                finalizationCommit.reset()
                return
            }

            let runtime = PlatformRuntimeProvenance.current()
            let request =
                try CaptureWorkingSetFinalizationRequestBuilder.build(
                    sealed: sealed,
                    app: BundleAppIdentity(
                        version: runtime.appVersion,
                        build: runtime.appBuild
                    )
                )
            let destination = finalizedDirectory(
                for: sealed.snapshot
            )

            // Pre-commit cancellation point (#185): a lifecycle failure
            // fenced before the promotion begins aborts the
            // transaction. No finalized destination is produced; the
            // working set returns to Review and the deferred lifecycle
            // policy is applied there.
            if let fencedFailure =
                finalizationCommit.preCommitFailure()
            {
                await abortUnpromotedFinalization(
                    diagnostic: nil,
                    fencedFailure: fencedFailure,
                    store: store,
                    quality: stagedQualityReport ?? quality,
                    generation: generation
                )
                return
            }

            // The atomic move inside finalize(...) is the irreversible
            // filesystem commit point (#160): the working directory was
            // renamed into finalized/, so the returned revision is
            // durable finalized authority. Beyond this line the host
            // must adopt the revision, never roll it back, and never
            // classify post-promotion errors as a failed working set.
            let finalized =
                try await BundleRevisionFinalizer().finalize(
                    stagingDirectory: sealed.snapshot.rootDirectory,
                    destinationDirectory: destination,
                    request: request
                )
            promotedRevision = finalized
            finalizationCommit.markPromoted()

            // #166: promotion is a same-volume move, which preserves the
            // Data Protection class applied at working-revision
            // creation; reapply it explicitly so the finalized
            // directory can never silently sit under a weaker class. A
            // failure is surfaced to the operator, never fatal to the
            // already-promoted bundle.
            do {
                try CaptureStoragePolicy.applyFileProtection(
                    to: finalized.directory
                )
            } catch {
                protectionWarning =
                    Self.persistenceDiagnostic(error)
            }

            // #305: a same-volume rename carries the working
            // directory's backup-exclusion flag into finalized/;
            // write the selected policy explicitly so finalized
            // data honors it (default: backup-eligible per
            // ADR-0004). Like the protection class above, a
            // failure is surfaced, never fatal to the promoted
            // bundle.
            do {
                try CaptureStoragePolicy
                    .applyFinalizedRevisionPolicy(
                        revisionRoot: finalized.directory,
                        policy: appSettings.storagePrivacy
                            .finalizedBackupPolicy
                    )
            } catch {
                let warning = Self.persistenceDiagnostic(error)
                protectionWarning =
                    protectionWarning.map { $0 + "; " + warning }
                    ?? warning
            }
        } catch {
            // Errors here are strictly pre-commit: promotion never
            // began, no finalized destination was produced, and the
            // working set still owns the revision, so the staged
            // quality payload may be rolled back for a Review retry.
            guard captureGeneration == generation else {
                try? await store.unseal()
                finalizationCommit.reset()
                return
            }
            await abortUnpromotedFinalization(
                diagnostic: Self.persistenceDiagnostic(error),
                fencedFailure: finalizationCommit.preCommitFailure(),
                store: store,
                quality: stagedQualityReport ?? quality,
                generation: generation
            )
            return
        }

        guard let promotedRevision else {
            return
        }
        await adoptPromotedRevision(
            promotedRevision,
            protectionWarning: protectionWarning
        )
    }

    /// Shared pre-commit abort for the finalization transaction:
    /// release the working-set seal, remove the staged quality payload,
    /// record the recoverable event, and transition
    /// validating -> reviewing so the attempt can be retried — or, when
    /// a lifecycle failure was fenced before promotion, apply it through
    /// the ordinary resource/lifecycle policy once the mutable Review
    /// boundary is restored. The promoted path never reaches here:
    /// nothing in this method may run after the commit point.
    private func abortUnpromotedFinalization(
        diagnostic: String?,
        fencedFailure: CaptureFailureCode?,
        store: CaptureWorkingSetStore,
        quality: CaptureQualityReport,
        generation: UUID
    ) async {
        // Release the seal before any rollback mutation; unseal is
        // best-effort across the boundary (the seal may not have been
        // held if the failure preceded it).
        try? await store.unseal()
        finalizationCommit.reset()

        do {
            try await store.discardUncommittedQualityReport(
                quality
            )
        } catch {
            workingSetStatus =
                String(localized: "Finalization failed and the staged quality record could not be rolled back safely")
                + " ["
                + (diagnostic ?? Self.persistenceDiagnostic(error))
                + "]"
            fail(.persistenceFailure)
            return
        }

        if let diagnostic {
            await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: .persistenceFailure,
                    severity: .warning,
                    detail:
                        "Recoverable finalization failure: "
                        + diagnostic
                )
            )
        }

        guard captureGeneration == generation,
              state == .validating
        else {
            return
        }

        do {
            try transition(.validationFailed)
        } catch {
            fail(.unknown)
            return
        }

        await refreshQuality(
            store: store,
            generation: generation
        )

        guard captureGeneration == generation,
              state == .reviewing
        else {
            return
        }

        // #437: the commit aborted and rolled back — the capture is
        // still in Review unchanged, so the rejection surface names
        // the step and the concrete next-step set. A fenced
        // lifecycle failure below may still route elsewhere; that
        // transition clears this flag.
        finalizeRejection = .commitRejected

        if let fencedFailure {
            // The lifecycle failure was fenced only while the commit
            // transaction held the generation. Now that the attempt
            // aborted back to a mutable Review boundary, the ordinary
            // resource/lifecycle policy applies it (preserved-Review
            // seal or terminal failure). It is applied after the outer
            // operation unwinds so reviewOperationInFlight no longer
            // suppresses the preserved-Review path.
            let deferredEvent =
                Self.lifecycleResourceEvent(for: fencedFailure)
            Task { @MainActor [weak self] in
                guard let self,
                      self.captureGeneration == generation
                else {
                    return
                }
                self.applyResourceLifecycleEvent(
                    deferredEvent,
                    failure: fencedFailure,
                    store: store,
                    generation: generation
                )
            }
            return
        }

        if let diagnostic {
            workingSetStatus =
                String(localized: "Finalization was not committed. The capture remains in Review and can be retried.")
                + " ["
                + diagnostic
                + "]"
        }
    }

    /// Post-commit adoption (#160): the working directory was already
    /// moved into `finalized/` atomically, so the promoted revision is
    /// durable truth. The independent post-promotion validation runs in
    /// a bounded detached task so the full re-hash never executes on
    /// MainActor (#192); only the compact report crosses back.
    ///
    /// Commit wins: a generation change alone must not abandon a
    /// successfully promoted revision, so adoption is unconditional.
    /// A validation failure never reverts to working-set rollback —
    /// the host adopts the committed revision as finalized-but-
    /// unverified and reports that explicitly; the persisted inventory
    /// re-examines it (and quarantines it if still unreadable) on the
    /// next scan, keeping exactly one terminal owner.
    private func adoptPromotedRevision(
        _ finalized: FinalizedCaptureRevision,
        protectionWarning: String? = nil
    ) async {
        let (validation, validationDiagnostic) =
            await Self.validatePromotedRevision(
                directory: finalized.directory
            )

        // Commit wins (#185): a lifecycle failure fenced while the
        // finalizer or revalidation was suspended becomes post-capture
        // status, never a reason to abandon the promoted revision.
        let fencedFailure = finalizationCommit.postCommitFailure()
        finalizationCommit.reset()

        let fencedNote: String
        if let fencedFailure {
            fencedNote = String(
                format: String(localized: "; a %@ lifecycle event arrived during the commit window and was surfaced after adoption"),
                fencedFailure.rawValue
            )
        } else {
            fencedNote = ""
        }

        let protectionNote: String
        if let protectionWarning {
            protectionNote = String(localized: " (file protection reapply failed)") + " [" + protectionWarning + "]"
        } else {
            protectionNote = ""
        }

        // Finalization consumed the working revision: discard the
        // non-canonical annotation draft so a later session can never
        // restore pre-commit staging (#266).
        discardAnnotationDraft()

        sessionController.stopAndPauseARSession()
        resourceMonitor?.stop()
        resourceMonitor = nil
        workingSetStore = nil
        finalizedRevision = finalized
        exportURL = nil
        reviewWorkspace = nil
        // #364 §11: the mission summary survives finalization — the
        // finalized surface reports required-task completion for the
        // capture just committed. Every fresh capture/reset path
        // clears it before a new working set begins.
        danglingSpatialIssues = []

        // Acquisition provenance (#317): a bundle produced by this
        // device's capture flow records `created_on_this_device`.
        // Failure here never disturbs the committed revision — it is
        // app-local metadata, not bundle authority.
        if let originStore = captureOriginStore,
           let originRecord = try? CaptureAcquisitionOriginRecord(
            captureRevisionID: finalized.captureRevisionID,
            kind: .createdOnThisDevice,
            transport: .localCapture,
            acquiredAtUTC: BundleTimestamp.utcString(from: Date()),
            bundleDigestSHA256: finalized.bundleDigest.value
           )
        {
            try? originStore.record(originRecord)
            captureOrigins[finalized.captureRevisionID] = originRecord
        }

        // #386: a finalized capture under an active mission joins
        // that mission's associations — the mission record, never
        // the bundle, carries the intent.
        if let missionID = activeMissionRecordID {
            try? missionInboxStore?.associateCapture(
                recordID: missionID,
                captureRevisionID:
                    finalized.captureRevisionID
            )
            // #397: the revision's accepted item outcomes join the
            // mission's append-only ledger — replayable completeness
            // across every associated revision, never a stored
            // percentage.
            ingestMissionProgress(
                finalizedDirectory: finalized.directory,
                missionRecordID: missionID
            )
            refreshMissionDeliveryStores()
        }

        refreshHandoffDestinations()
        if let captureRoot = Self.captureRootDirectory() {
            handoffReceipts =
                (try? HTDTHandoffReceiptStore(
                    captureRoot: captureRoot
                ).receipts(
                    for: finalized.captureRevisionID
                )) ?? []
        }

        // #321: a promoted revision carrying a persisted repair link
        // resolves the fresh-rescan task it answers.
        if let row = activeRepairRow,
           persistedRepairLinkRevisionID
            == finalized.captureRevisionID
        {
            try? repairPlanStore?.markTaskResolved(
                planKey: row.planKey,
                taskID: row.task.taskID,
                resolvedBy: finalized.captureRevisionID,
                at: BundleTimestamp.utcString(from: Date())
            )
            activeRepairRow = nil
            persistedRepairLinkRevisionID = nil
        }
        refreshRepairTaskRows()
        clearCaptureMissionInputs()

        if let validation,
           validation.bundleDigest == finalized.bundleDigest
        {
            validationReport = validation
            do {
                try transition(.finalize)
            } catch {
                // Even when the host transition itself fails, the
                // committed revision stays adopted; the committed
                // bytes remain recoverable through the persisted
                // inventory instead of being misclassified as a
                // failed working set.
                workingSetStatus = String(localized: "The revision was committed but the host could not reflect finalized state; it stays discoverable in the persisted-capture inventory")
                self.loadPersistedCaptures()
                return
            }
            workingSetStatus =
                String(
                    format: String(localized: "Finalized revision; bundle digest %@"),
                    validation.bundleDigest.description
                ) + fencedNote + protectionNote
            self.loadPersistedCaptures()
            return
        }

        // Committed-but-unverified: durable bytes exist under
        // finalized/, but independent revalidation could not prove
        // them (or the digest disagreed with the finalizer's manifest
        // record). Adopt the revision so there is exactly one terminal
        // owner and surface the unverified state explicitly instead of
        // Failed + rollback.
        validationReport = nil
        let unverifiedDiagnostic =
            validation == nil
            ? (validationDiagnostic
                ?? "post_promotion_validation_unverified")
            : "bundle_digest_mismatch"
        do {
            try transition(.adoptFinalized)
        } catch {
            workingSetStatus = String(localized: "The revision was committed but the host could not reflect finalized state; it stays discoverable in the persisted-capture inventory")
            self.loadPersistedCaptures()
            return
        }
        workingSetStatus =
            String(localized: "The revision was committed to finalized storage, but post-promotion validation could not prove it; the committed bytes are preserved and stay discoverable through the persisted-capture inventory")
            + " ["
            + unverifiedDiagnostic
            + "]"
            + fencedNote
        self.loadPersistedCaptures()
    }

    /// Independent post-promotion revalidation (#192): the full
    /// directory scan + digest run on a bounded detached worker and
    /// only the compact report (or a diagnostic token) returns to the
    /// MainActor. One retry distinguishes a transient read failure
    /// from a genuinely unverifiable committed bundle.
    nonisolated private static func validatePromotedRevision(
        directory: URL
    ) async -> (report: BundleValidationReport?, diagnostic: String?) {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let report = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try BundleDirectoryValidator.validate(
                        root: directory
                    )
                }.value
                return (report, nil)
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(
                        for: .milliseconds(150)
                    )
                }
            }
        }
        let diagnostic =
            lastError.map { Self.persistenceDiagnostic($0) }
            ?? "post_promotion_validation_unverified"
        return (nil, diagnostic)
    }

    private func configureResourceMonitor(
        store: CaptureWorkingSetStore,
        rootDirectory: URL,
        generation: UUID
    ) {
        resourceMonitor?.stop()

        resourceEventTask = nil

        let monitor = CaptureResourceMonitor(
            rootDirectory: rootDirectory
        ) { [weak self] event, failure in
            self?.applyResourceLifecycleEvent(
                event,
                failure: failure,
                store: store,
                generation: generation
            )
        }

        resourceMonitor = monitor
        monitor.start()
    }

    /// Shared ordered entry point for every resource/lifecycle event:
    /// CaptureResourceMonitor notifications and ARSession lifecycle
    /// callbacks (#168) converge here so generation fencing, the
    /// preserved-Review seal, the ordered event-record chain, and the
    /// finalization commit fence (#185) stay identical across sources.
    private func applyResourceLifecycleEvent(
        _ event: CaptureResourceEvent,
        failure: CaptureFailureCode?,
        store: CaptureWorkingSetStore,
        generation: UUID
    ) {
        guard captureGeneration == generation else {
            return
        }

        var eventToRecord = event
        var failureToApply = failure
        var sealedReviewResourceCondition = false
        var discardedUnsavedAnnotationEdits = false

        let canPreserveAcceptedReview =
            (
                state == .reviewing
                && !reviewOperationInFlight
            )
            || (
                state == .annotating
                && !annotationCommitInFlight
            )

        if let failure,
           (
               failure == .interrupted
               || failure == .thermalPressure
               || failure == .storagePressure
           ),
           canPreserveAcceptedReview,
           acceptedRoomPlanRawSHA256 != nil,
           !spatialAuthoritySealedForFinalization
        {
            if state == .annotating {
                do {
                    try transition(.beginReview)
                    discardedUnsavedAnnotationEdits = true
                } catch {
                    self.fail(.unknown)
                    return
                }
            }

            // Accepted End artifacts are already durable. A transient
            // resource/lifecycle condition invalidates only future live
            // spatial continuation; it must not retroactively discard
            // the evidence accepted before that condition.
            let detail: String
            switch failure {
            case .interrupted:
                detail =
                    "application entered background after accepted End; spatial continuation was sealed but persisted Review evidence remains finalizable"
            case .thermalPressure:
                detail =
                    "critical thermal pressure occurred after accepted End; spatial continuation was sealed and finalization is deferred until the device cools"
            case .storagePressure:
                detail =
                    "critical storage pressure occurred after accepted End; spatial continuation was sealed and finalization is deferred until storage recovers"
            default:
                detail = event.detail
            }

            eventToRecord = CaptureResourceEvent(
                kind: event.kind,
                severity: .warning,
                detail:
                    discardedUnsavedAnnotationEdits
                    ? detail
                        + "; unsaved annotation edits were discarded"
                    : detail
            )
            failureToApply = nil
            sealedReviewResourceCondition = true
            spatialAuthoritySealedForFinalization = true
            scanCoverageTask?.cancel()
            scanCoverageTask = nil
            sessionController.stopAndPauseARSession()
            resourceMonitor?.stop()
            endScanGuidance = nil
        }

        // Keep resource provenance ordered. Finalization can await this
        // chain before it freezes quality authority, and reset can drain
        // it before deleting an incomplete working set.
        let predecessor = resourceEventTask
        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            await store.recordResourceEvent(eventToRecord)

            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            if self.state == .reviewing {
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
                self.danglingSpatialIssues =
                    await store.committedSpatialEvidenceIssues()
                self.refreshReviewWorkspace()
                if sealedReviewResourceCondition,
                   self.state == .reviewing
                {
                    if discardedUnsavedAnnotationEdits {
                        self.workingSetStatus =
                            String(localized: "Review retained after the resource/lifecycle interruption. Unsaved annotation edits were discarded; accepted capture evidence can still be finalized or retried.")
                    } else {
                        self.workingSetStatus =
                            String(localized: "Review retained; additional scanning/annotation is sealed by the current resource/lifecycle condition, while accepted evidence remains available for finalization or retry")
                    }
                }
            }
        }
        resourceEventTask = task

        if let failureToApply,
           state != .failed,
           state != .finalized,
           state != .exported
        {
            fail(failureToApply)
        }
    }

    /// CONTRACT (#168): the sibling platform agent exposes an ARSession
    /// lifecycle surface `sessionLifecycleHandler` on
    /// SharedARSessionController delivering interruption-began,
    /// interruption-ended, and terminal-failure events on MainActor.
    /// The event enum name below is the agreed contract; if it lands
    /// under a different name this method is the single host-side
    /// adaptation site.
    private func handleSessionLifecycleEvent(
        _ event: ARSessionLifecycleEvent,
        store: CaptureWorkingSetStore,
        generation: UUID
    ) {
        guard captureGeneration == generation else {
            return
        }

        switch event {
        case .wasInterrupted:
            // Interruption alone is not terminal: the session may
            // resume. Record warning provenance only; #148's tracking
            // transition recording captures the observable degradation,
            // and a genuine coordinate-space reset is registered by the
            // platform layer when continuity is demonstrably lost.
            applyResourceLifecycleEvent(
                CaptureResourceEvent(
                    kind: .interruption,
                    severity: .warning,
                    detail:
                        "ARSession interruption began during active capture"
                ),
                failure: nil,
                store: store,
                generation: generation
            )
        case .interruptionEnded:
            applyResourceLifecycleEvent(
                CaptureResourceEvent(
                    kind: .interruption,
                    severity: .warning,
                    detail:
                        "ARSession interruption ended; tracking-state transitions continue through canonical tracking history"
                ),
                failure: nil,
                store: store,
                generation: generation
            )
        case .failed(let reason):
            applyResourceLifecycleEvent(
                CaptureResourceEvent(
                    kind: .interruption,
                    severity: .error,
                    detail: "ARSession failed: " + reason
                ),
                failure: .interrupted,
                store: store,
                generation: generation
            )
        case .cameraTrackingStateChanged(let trackingEvent):
            // Route through the same transition gate as the scan
            // coverage loop so delegate-delivered transitions extend
            // the bounded #148 history without duplicate recordings.
            guard state == .scanning, !isEndingScan,
                  scanTrackingTransitionGate
                    .shouldRecord(trackingEvent)
            else {
                return
            }
            Task { @MainActor [weak self] in
                guard self?.captureGeneration == generation else {
                    return
                }
                await store.recordTrackingEvent(trackingEvent)
            }
        case .didOutputCollaborationData:
            // Collaboration data is unused by this capture flow.
            return
        }
    }

    private func makeWorkingSet() throws -> (
        store: CaptureWorkingSetStore,
        identity: CaptureWorkingSetIdentity,
        generation: UUID,
        rootDirectory: URL,
        storagePolicyWarnings: [String]
    ) {
        guard let applicationSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        // A revise-existing capture keeps the parent's series identity
        // and records the exact prior revision as its parent; a fresh
        // capture starts a new series root (#155).
        let identity = CaptureWorkingSetIdentity(
            captureSeriesID:
                activeRevisionLineage?.captureSeriesID
                    ?? CaptureSeriesID(),
            parentRevisionID:
                activeRevisionLineage?.parentRevisionID
        )
        let root = applicationSupport
            .appendingPathComponent(
                "HTDTCapture",
                isDirectory: true
            )
            .appendingPathComponent(
                "working",
                isDirectory: true
            )
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )

        // #320: a practice working set carries the marker in its
        // durable state document — it can never be finalized and is
        // never listed as a recoverable draft.
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: root,
            practice: activeCaptureIsPractice
        )

        // The revision directory exists now: apply the transient-working
        // at-rest policy (backup exclusion + Data Protection class)
        // before any evidence lands (#136, #166). Failures are reported
        // to the caller instead of being silently ignored.
        var storagePolicyWarnings: [String] = []
        do {
            try CaptureStoragePolicy.applyWorkingRevisionPolicy(
                revisionRoot: root
            )
        } catch {
            storagePolicyWarnings.append(
                Self.persistenceDiagnostic(error)
            )
        }

        return (
            store: store,
            identity: identity,
            generation: UUID(),
            rootDirectory: root,
            storagePolicyWarnings: storagePolicyWarnings
        )
    }

    private func exportDestination(
        for finalized: FinalizedCaptureRevision
    ) throws -> URL {
        guard let applicationSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        return applicationSupport
            .appendingPathComponent(
                "HTDTCapture",
                isDirectory: true
            )
            .appendingPathComponent(
                "exports",
                isDirectory: true
            )
            .appendingPathComponent(
                finalized.captureRevisionID.description
                    + ".htdtcapture",
                isDirectory: false
            )
    }

    private func finalizedDirectory(
        for snapshot: CaptureWorkingSetSnapshot
    ) -> URL {
        let applicationRoot = snapshot.rootDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return applicationRoot
            .appendingPathComponent(
                "finalized",
                isDirectory: true
            )
            .appendingPathComponent(
                snapshot.identity.captureRevisionID.description,
                isDirectory: true
            )
    }

    nonisolated private static func persistenceDiagnostic(
        _ error: Error
    ) -> String {
        if let writerError = error as? CaptureFileWriterError {
            switch writerError {
            case let .alreadyExists(path):
                return "file_conflict:" + path
            case let .batchRollbackFailed(path):
                return "batch_rollback_failed:" + path
            }
        }

        if let workingSetError =
            error as? CaptureWorkingSetError
        {
            switch workingSetError {
            case let .duplicatePayloadDeclaration(path):
                return "declaration_conflict:" + path
            case .authorityMismatch:
                return "authority_mismatch"
            case .integrityVerificationFailed:
                return "integrity_verification_failed"
            default:
                return "working_set:"
                    + String(describing: workingSetError)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code
                == CocoaError.Code.fileWriteOutOfSpace.rawValue
            {
                return "storage_full"
            }
            if nsError.code
                == CocoaError.Code.fileWriteNoPermission.rawValue
            {
                return "write_permission_denied"
            }
            return "cocoa:" + String(nsError.code)
        }

        if nsError.domain == NSPOSIXErrorDomain {
            if nsError.code
                == Int(POSIXErrorCode.ENOSPC.rawValue)
            {
                return "storage_full"
            }
            return "posix:" + String(nsError.code)
        }

        return String(reflecting: type(of: error))
            + ":"
            + nsError.domain
            + ":"
            + String(nsError.code)
    }

    /// Map a fenced lifecycle failure to the ordered
    /// resource/lifecycle event that a live monitor callback would
    /// have carried, so a deferred application keeps identical
    /// provenance shape (#185). Warning severity preserves the
    /// Review-retained quality policy if the deferred application
    /// lands on a preservable boundary.
    nonisolated private static func lifecycleResourceEvent(
        for failure: CaptureFailureCode
    ) -> CaptureResourceEvent {
        let kind: CaptureResourceEventKind
        switch failure {
        case .thermalPressure:
            kind = .thermalPressure
        case .storagePressure:
            kind = .storagePressure
        default:
            kind = .interruption
        }
        return CaptureResourceEvent(
            kind: kind,
            severity: .warning,
            detail:
                "lifecycle failure observed during the finalization commit transaction: "
                + failure.rawValue
        )
    }

    private func transition(_ event: CaptureEvent) throws {
        try stateMachine.apply(event)
        state = stateMachine.state
        lastFailure = stateMachine.lastFailure
        // #456: entering Review from a live scan under an active
        // mission completes the field-capture leg of its lifecycle;
        // the store only advances `in_progress` records.
        if case .beginReview = event,
           state == .reviewing,
           let missionID = activeMissionRecordID {
            try? missionInboxStore?.noteFieldCaptureCompleted(
                recordID: missionID
            )
        }
        // #437: a rejection flag lives only while the surface that
        // shows it is active — entering `.validating` (a retry) or
        // leaving Review/finalized/failed clears it.
        if state != .reviewing {
            finalizeRejection = nil
        }
        if state != .finalized {
            exportRejection = nil
        }
        if state != .failed {
            failedDraftRecoverable = false
        }
        // #272: the display keep-awake override is scoped strictly to
        // `.scanning`; every transition out of it restores the device
        // default regardless of which path left scanning.
        updateDisplayIdleTimer()
        // Battery observation exists only for setup and the live scan;
        // any exit to reviewing/failed/finalized drops it.
        if deviceReadinessObserving,
           state != .setup, state != .scanning
        {
            stopDeviceReadinessObserving()
        }
    }

    private func fail(_ code: CaptureFailureCode) {
        // (#185) While the finalization commit transaction is claimed,
        // a lifecycle/resource failure is fenced instead of
        // invalidating the capture generation underneath an in-flight
        // promotion. The commit path observes the fenced failure at its
        // pre-commit cancellation point (abort with no finalized
        // destination produced) or after promotion (commit wins: the
        // revision is adopted and the failure becomes post-capture
        // status). A fenced failure is fully absorbed with no side
        // effects; non-lifecycle failures and ordinary stale callbacks
        // keep their immediate generation-invalidation handling.
        if state == .validating,
           finalizationCommit.fenceLifecycleFailure(code)
        {
            return
        }

        annotationCommitInFlight = false
        reviewOperationInFlight = false
        guard state != .finalized,
              state != .exported
        else {
            workingSetStatus =
                String(localized: "A post-finalization operation failed, but the finalized revision remains intact")
            return
        }

        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        resourceMonitor?.stop()
        resourceMonitor = nil
        stopDeviceReadinessObserving()
        endTargetScan()
        loopClosureCheckActive = false
        loopClosureAssessment = nil
        loopClosureLastAssessment = nil
        loopClosureOutcome = nil
        captureSetup = nil
        automaticFrameSaveTask?.cancel()
        automaticFrameSaveTask = nil
        latestScanTimestampSeconds = nil

        // Invalidate all in-flight callbacks before stopping RoomPlan. A
        // terminal failure must not accept late evidence into the failed
        // coordinate authority.
        captureGeneration = UUID()

        if code == .interrupted {
            workingSetStatus = String(localized: "Capture stopped because the app left the foreground")
        } else if code == .thermalPressure {
            workingSetStatus = String(localized: "Capture stopped because the device reached a critical thermal state")
        } else if code == .storagePressure {
            workingSetStatus = String(localized: "Capture stopped because available storage fell below the safe threshold")
        } else {
            // Non-lifecycle failure codes keep a truthful status too —
            // otherwise the failed screen would carry forward whatever
            // in-progress text happened to be showing.
            workingSetStatus =
                String(localized: "Capture failed")
                + " [" + code.rawValue + "]"
        }

        // A terminal failure must not leave a hidden RoomPlan / AR session
        // running. Restart creates a fresh session and coordinate authority.
        sessionController.stopAndPauseARSession()

        do {
            try transition(.fail(code))
        } catch {
            state = .failed
            lastFailure = .unknown
        }

        // #437: whether the failed working set's durable End boundary
        // survived decides if "reopen as draft" is a real recovery —
        // a mid-scan failure leaves non-resumable data and the failed
        // surface says so plainly instead of offering a dead path.
        failedDraftRecoverable =
            workingSetStore.flatMap { store in
                CaptureWorkingSetStore.peekRevisionPhase(
                    workingRevisionURL: store.rootDirectory
                )?.phase.isRecoverableDraft
            } ?? false
    }

    // MARK: - Mission workflows (issues #353, #240, #222, #293, #321)

    /// Schema probe for the unified mission-document importer (#353):
    /// the `schema` field alone decides which importer owns the file.
    private struct MissionSchemaProbe: Decodable {
        let schema: String?
    }

    /// Reachable mission surfaces for the current context — the
    /// production entry list the root view renders (#353).
    var missionEntries: [MissionWorkflowEntry] {
        let captureInProgress =
            state == .scanning
            || state == .reviewing || state == .annotating
        return MissionWorkflowRouter.entries(
            for: MissionWorkflowContext(
                taskPlanLoaded: captureTaskPlan != nil,
                connectedSpaceIntent: connectedSpaceIntent,
                connectedSpaceActive: connectedSpaceTracker != nil,
                asBuiltPlanLoaded: asBuiltPlan != nil,
                spatialAuthorityLive: captureInProgress
                    && !spatialAuthoritySealedForFinalization
                    && workingSetSpatialAuthorityLive,
                captureInProgress: captureInProgress,
                // Matches beginAnnotation()'s guard: the workspace
                // also opens under the finalization seal, rendering
                // in non-spatial mode (#276).
                annotationWorkspaceEnterable:
                    state == .reviewing
                    && !isEndingScan
                    && !reviewOperationInFlight,
                unresolvedRepairTasks: repairTaskRows.filter {
                    !$0.resolved
                }.count
            )
        )
    }

    var asBuiltGhostOverlayEnabled: Bool {
        asBuiltSession?.ghostOverlayEnabled ?? false
    }

    /// The installed plan→capture alignment authority (#293).
    var asBuiltAlignment: PlanAlignmentAuthority? {
        asBuiltSession?.alignment
    }

    /// Versioned tolerance policy the plan supplies (#293), when any.
    var asBuiltTolerancePolicyRef: String? {
        asBuiltSession?.tolerancePolicyRef
    }

    /// #293: ghost-overlay plan model — planned targets projected
    /// through the installed alignment authority with observed
    /// actuals and deviation connectors. nil until an explicit
    /// alignment authority is established.
    var asBuiltOverlayModel: RoomPlanPreviewModel? {
        AsBuiltPlanOverlay.model(
            items: asBuiltItems,
            alignment: asBuiltSession?.alignment
        )
    }

    func setConnectedSpaceIntent(_ intent: Bool) {
        connectedSpaceIntent = intent
    }

    /// Unified mission-document importer (#353). Allowed while the
    /// capture is idle, in setup, or in progress — imported payloads
    /// persist as supplemental documents once a working set exists,
    /// so a plan can be staged before the scan or added mid-capture.
    func importMissionDocument(_ url: URL) {
        guard state == .idle || state == .setup
            || state == .scanning
            || state == .reviewing || state == .annotating
        else {
            workingSetStatus = String(localized: "Mission documents can only be imported while idle, in setup, or during a capture")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            workingSetStatus = String(localized: "The mission document could not be read")
            return
        }
        do {
            try activateMissionDocument(data)
        } catch {
            workingSetStatus =
                String(localized: "Mission document rejected")
                + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Schema-sniffed dispatch (#353). Task plans and as-built plans
    /// persist verbatim as imported-reference supplemental documents;
    /// repair plans enter the app-local ledger (#321).
    private func activateMissionDocument(_ data: Data) throws {
        let schema = try? JSONDecoder().decode(
            MissionSchemaProbe.self,
            from: data
        ).schema
        switch schema {
        case HTDTMissionPackage.schema:
            // #457: a mission envelope picked on the document import
            // belongs to the inbox — every mission import affordance
            // accepts every mission payload shape.
            try importMissionEnvelopeData(data)
        case HTDTCaptureTaskPlan.schema:
            let planImport = try CaptureTaskPlanImport(data: data)
            captureTaskPlanImport = planImport
            captureTaskPlan = planImport.plan
            captureTaskPlanStatus =
                CaptureTaskPlanStatus(planImport: planImport)
            Task {
                await persistMissionImportDocuments()
                await refreshMissionOutcomes()
            }
            workingSetStatus = String(localized: "Task plan imported") + " — " + planImport.plan.planID
        case HTDTAsBuiltPlan.schema:
            let planImport = try HTDTAsBuiltPlanImport(data: data)
            asBuiltPlanImport = planImport
            asBuiltPlan = planImport.plan
            configureAsBuiltSession()
            Task { await persistMissionImportDocuments() }
            workingSetStatus = String(localized: "As-built plan imported") + " — " + planImport.plan.planID
        case HTDTRepairTaskPlan.schema:
            let planImport = try HTDTRepairTaskPlanImport(data: data)
            guard let repairPlanStore else {
                throw RepairTaskError.unreadableDocument
            }
            let stored = try repairPlanStore.record(
                planImport,
                receivedAtUTC: BundleTimestamp.utcString(from: Date())
            )
            refreshRepairTaskRows()
            workingSetStatus = String(localized: "Repair plan recorded") + " — " + stored.plan.planID
        default:
            throw RepairTaskError.unsupportedSchema
        }
    }

    /// Creates the as-built verification session against the live
    /// coordinate authority (#293). Deferred when no spatial
    /// authority is bound yet — `activateStagedMissionState` retries
    /// once the working set exists.
    private func configureAsBuiltSession() {
        guard let planImport = asBuiltPlanImport else {
            return
        }
        do {
            asBuiltSession = try AsBuiltVerificationSession(
                planID: planImport.plan.planID,
                planVersion: planImport.plan.planVersion,
                planSHA256: planImport.planSHA256,
                tolerancePolicyRef:
                    planImport.plan.tolerancePolicyRef,
                coordinateSpaceID:
                    sessionController.context.coordinateSpaceID,
                specs: planImport.plan.specs
            )
            asBuiltAlignmentInstalled = false
            asBuiltItems = (try? asBuiltSession?.items()) ?? []
        } catch {
            asBuiltSession = nil
            asBuiltItems = []
        }
    }

    /// Working set just bound: build the as-built session on the live
    /// space and persist staged mission payloads plus the repair link
    /// into this revision (#353/#321).
    private func activateStagedMissionState(
        store: CaptureWorkingSetStore
    ) async {
        if asBuiltPlanImport != nil, asBuiltSession == nil {
            configureAsBuiltSession()
        }
        await persistMissionImportDocuments()
        await refreshMissionOutcomes()
    }

    /// Persists the verbatim mission payloads and a pending repair
    /// link as supplemental documents. The store treats an identical
    /// replay as a no-op, so repeated calls are idempotent.
    private func persistMissionImportDocuments() async {
        guard let store = workingSetStore else {
            return
        }
        do {
            if let planImport = captureTaskPlanImport {
                try await store.persistSupplementalDocument(
                    try supplementalDocument(
                        path: CaptureTaskPlanImport.path,
                        data: planImport.data,
                        producer: "htdt_plan",
                        provenanceClass: .importedReference
                    )
                )
            }
            if let planImport = asBuiltPlanImport {
                try await store.persistSupplementalDocument(
                    try supplementalDocument(
                        path: HTDTAsBuiltPlanImport.path,
                        data: planImport.data,
                        producer: "htdt_plan",
                        provenanceClass: .importedReference
                    )
                )
            }
            if let link = makeRepairLink() {
                try await store.persistSupplementalDocument(
                    try supplementalDocument(
                        path: HTDTRepairTaskLink.path,
                        data: link.package(),
                        producer: "capture_session",
                        provenanceClass: .captureAppDerived,
                        bindContext: true
                    )
                )
                persistedRepairLinkRevisionID =
                    link.captureRevisionID
            }
        } catch {
            workingSetStatus += " ["
                + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Mission-derived payloads packaged at finalization (#353):
    /// task-plan status, connected-space map, as-built verdicts — all
    /// captureAppDerived and bound to this revision's authority.
    private func persistMissionDerivedDocuments(
        store: CaptureWorkingSetStore
    ) async throws {
        guard let revisionID =
            workingSetIdentity?.captureRevisionID
        else {
            return
        }
        let context = sessionController.context
        let seed = (try? Self.committedAnnotationSeed(
            rootDirectory: await store.rootDirectory
        ).0) ?? AnnotationWorkspaceSeed()
        if let status = captureTaskPlanStatus {
            try await store.replaceSupplementalDocument(
                try supplementalDocument(
                    path: CaptureTaskPlanStatusDocument.path,
                    data: status.statusPackage(
                        captureRevisionID: revisionID,
                        captureSessionID: context.captureSessionID,
                        annotations: seed.annotations,
                        measurements: seed.measurements
                    ),
                    producer: "capture_session",
                    provenanceClass: .captureAppDerived,
                    bindContext: true
                )
            )
        }
        if let tracker = connectedSpaceTracker {
            try await store.replaceSupplementalDocument(
                try supplementalDocument(
                    path: ConnectedSpaceDocument.path,
                    data: tracker.package(
                        captureRevisionID: revisionID
                    ),
                    producer: "capture_session",
                    provenanceClass: .captureAppDerived,
                    bindContext: true
                )
            )
        }
        if let session = asBuiltSession {
            try await store.replaceSupplementalDocument(
                try supplementalDocument(
                    path: AsBuiltVerificationDocument.path,
                    data: session.package(
                        captureRevisionID: revisionID,
                        captureSessionID: context.captureSessionID
                    ),
                    producer: "asbuilt_verification",
                    provenanceClass: .captureAppDerived,
                    bindContext: true
                )
            )
        }
    }

    private func supplementalDocument(
        path: String,
        data: Data,
        producer: String,
        provenanceClass: BundleProvenanceClass,
        bindContext: Bool = false
    ) throws -> WorkingSetSupplementalDocument {
        try WorkingSetSupplementalDocument(
            path: path,
            data: data,
            declaration: BundlePayloadDeclaration(
                path: path,
                mediaType: "application/json",
                producer: producer,
                provenanceClass: provenanceClass,
                role: .canonical
            ),
            coordinateSpaceIDs: bindContext
                ? [sessionController.context.coordinateSpaceID] : [],
            captureSessionIDs: bindContext
                ? [sessionController.context.captureSessionID] : []
        )
    }

    /// The link document binding this new revision back to the repair
    /// task it answers (#321). Only built when this capture is a
    /// revision OF the task's pinned source revision — an unrelated
    /// capture must never claim the repair.
    private func makeRepairLink() -> HTDTRepairTaskLink? {
        guard let row = activeRepairRow,
              let revisionID = workingSetIdentity?.captureRevisionID,
              let stored = storedRepairPlan(for: row),
              let sourceID = CaptureRevisionID(
                  canonicalString: stored.plan.sourceCaptureRevisionID
              ),
              activeRevisionLineage?.parentRevisionID == sourceID,
              let planSHA = try? EvidenceSHA256(stored.planSHA256)
        else {
            return nil
        }
        return try? HTDTRepairTaskLink(
            captureRevisionID: revisionID,
            captureSessionID: sessionController.context.captureSessionID,
            repairPlanID: row.planID,
            repairPlanVersion: row.planVersion,
            repairPlanSHA256: planSHA,
            repairTaskID: row.task.taskID,
            sourceCaptureRevisionID: sourceID,
            ingestionReceiptRef: stored.plan.ingestionReceiptRef
        )
    }

    private func storedRepairPlan(
        for row: HTDTRepairTaskRow
    ) -> HTDTRepairPlanStore.StoredPlan? {
        try? repairPlanStore?.load().plans.first {
            $0.planKey == row.planKey
        }
    }

    /// Clears mission inputs whose payloads are now inside the
    /// finalized bundle (called after adoption and on terminal reset).
    private func clearCaptureMissionInputs() {
        captureTaskPlan = nil
        captureTaskPlanImport = nil
        captureTaskPlanStatus = nil
        missionTaskPlanOutcomes = []
        asBuiltPlan = nil
        asBuiltPlanImport = nil
        asBuiltSession = nil
        asBuiltItems = []
        asBuiltAlignmentInstalled = false
        asBuiltActualCandidates = []
        roomFrameAvailable = false
        connectedSpaceIntent = false
        connectedSpaceTracker = nil
    }

    /// Operator mark on a task-plan item (#240). Completion of
    /// entity/measurement items stays computed from committed
    /// evidence — explicit marks only assert non-evidence outcomes.
    /// #364 §10: a collected reason persists as a mission waiver
    /// note when the imported plan matches a mission record.
    func markTaskPlanItem(
        _ itemID: String,
        as outcome: TaskPlanItemOutcome,
        reason: String? = nil
    ) {
        do {
            try captureTaskPlanStatus?.mark(
                itemID: itemID,
                as: outcome
            )
            recordTaskPlanMarkWaiver(
                itemID: itemID,
                reason: reason,
                plan: captureTaskPlan
            )
            Task { await refreshMissionOutcomes() }
        } catch {
            workingSetStatus = String(localized: "That task plan item cannot be marked")
        }
    }

    /// Connected-space ops (#222): the tracker binds to the live
    /// coordinate authority lazily on first use.
    private func withConnectedTracker(
        _ statusOnFailure: String,
        _ op: (inout ConnectedSpaceTracker) throws -> Void
    ) {
        guard state == .scanning
            || state == .reviewing || state == .annotating
        else {
            workingSetStatus = String(localized: "Connected-space tracking needs a capture in progress")
            return
        }
        if connectedSpaceTracker == nil {
            connectedSpaceTracker = ConnectedSpaceTracker(
                coordinateSpaceID:
                    sessionController.context.coordinateSpaceID,
                captureSessionID:
                    sessionController.context.captureSessionID
            )
        }
        do {
            try op(&connectedSpaceTracker!)
            connectedSpaceIntent = true
        } catch {
            workingSetStatus = statusOnFailure + " ["
                + Self.persistenceDiagnostic(error) + "]"
        }
    }

    func beginConnectedSegment(
        label: String,
        kind: CaptureRegionKind
    ) {
        withConnectedTracker(
            String(localized: "Could not begin the region")
        ) { tracker in
            try tracker.beginSegment(label: label, kind: kind)
        }
    }

    func completeConnectedSegment() {
        withConnectedTracker(
            String(localized: "Could not complete the region")
        ) { tracker in
            try tracker.completeActiveSegment()
        }
    }

    func recordConnectedPortal(_ regionID: CaptureRegionID) {
        withConnectedTracker(
            String(localized: "Could not record the portal")
        ) { tracker in
            try tracker.recordPortal(
                toRegionID: regionID,
                kind: .doorway
            )
        }
    }

    func revisitConnectedRegion(_ regionID: CaptureRegionID) {
        withConnectedTracker(
            String(localized: "Could not revisit the region")
        ) { tracker in
            try tracker.revisitRegion(regionID)
        }
    }

    func asBuiltMarkUnavailable(_ plannedEntityID: String) {
        do {
            try asBuiltSession?.markUnavailable(plannedEntityID)
            asBuiltItems = (try? asBuiltSession?.items()) ?? []
        } catch {
            workingSetStatus = String(localized: "Could not mark the planned item")
        }
    }

    /// Establishes plan→capture alignment from the committed room
    /// reference frame (#293): scene axes are origin O, front F, up U
    /// — the columns of `worldFromScene` are [U×F, U, F, O], so
    /// `sceneFromCapture = inverse(worldFromScene)` is exact rigid
    /// math rather than a guess.
    func asBuiltEstablishAlignment() {
        guard asBuiltSession != nil else {
            return
        }
        Task { @MainActor in
            guard let store = workingSetStore,
                  let snapshot = try? await store.snapshot(),
                  let frame = snapshot.roomReferenceFrame
            else {
                workingSetStatus = String(localized: "Plan alignment requires a committed room reference frame")
                return
            }
            let up = Float3(0, 1, 0)
            let front = Float3(
                Float(frame.frontDirection.x),
                Float(frame.frontDirection.y),
                Float(frame.frontDirection.z)
            )
            let right = up.cross(front)
            let origin = Float3(
                Float(frame.originMeters.x),
                Float(frame.originMeters.y),
                Float(frame.originMeters.z)
            )
            do {
                let worldFromScene = try Matrix4x4F(values: [
                    right.x, right.y, right.z, 0,
                    up.x, up.y, up.z, 0,
                    front.x, front.y, front.z, 0,
                    origin.x, origin.y, origin.z, 1,
                ])
                let authority = try PlanAlignmentAuthority(
                    mechanism: .roomReferenceFrame,
                    sceneFromCapture: try worldFromScene.invertedRigid(),
                    authorityRef: RoomReferenceFramePackage.path,
                    evidenceRefs: frame.evidenceRefs,
                    establishedAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    )
                )
                asBuiltSession?.installAlignment(authority)
                asBuiltAlignmentInstalled = true
                asBuiltItems = (try? asBuiltSession?.items()) ?? []
            } catch {
                workingSetStatus = String(localized: "Plan alignment could not be established") + " [" + Self.persistenceDiagnostic(error) + "]"
            }
        }
    }

    /// Records a committed annotation entity as the actual position
    /// for one planned item (#293) — the observation keeps the
    /// entity's exact world transform and placement provenance, never
    /// retyped numbers.
    func asBuiltRecordActual(
        _ plannedEntityID: String,
        entityID: AnnotationEntityID
    ) {
        guard let entity = asBuiltActualCandidates.first(where: {
            $0.entityID == entityID
        }) else {
            return
        }
        do {
            let position = entity.worldFromAnnotation.translationWorld
            // `orientationWorld` is contracted in the capture world
            // frame — the committed entity stores local axes, so the
            // annotation transform rotates them into world before the
            // observation is written (issue #293).
            let orientationWorld: OrientationAxes? = try entity
                .orientation.map { axes in
                    let front = entity.worldFromAnnotation.applying(
                        toDirection: Float3(
                            axes.frontAxisLocal.x,
                            axes.frontAxisLocal.y,
                            axes.frontAxisLocal.z
                        )
                    )
                    let up = entity.worldFromAnnotation.applying(
                        toDirection: Float3(
                            axes.upAxisLocal.x,
                            axes.upAxisLocal.y,
                            axes.upAxisLocal.z
                        )
                    )
                    return try OrientationAxes(
                        frontAxisLocal: SpatialVector3F(
                            front.x, front.y, front.z
                        ),
                        upAxisLocal: SpatialVector3F(
                            up.x, up.y, up.z
                        )
                    )
                }
            try asBuiltSession?.recordActual(
                AsBuiltObservation(
                    plannedEntityID: plannedEntityID,
                    positionWorld: SpatialVector3F(
                        position.x, position.y, position.z
                    ),
                    orientationWorld: orientationWorld,
                    coordinateSpaceID:
                        sessionController.context.coordinateSpaceID,
                    placement: entity.placement,
                    observedAtUTC: BundleTimestamp.utcString(
                        from: Date()
                    ),
                    evidenceRefs: [
                        "annotation:" + entity.entityID.description
                    ],
                    uncertainty: entity.uncertainty
                )
            )
            asBuiltItems = (try? asBuiltSession?.items()) ?? []
        } catch {
            workingSetStatus = String(localized: "The actual observation could not be recorded") + " [" + Self.persistenceDiagnostic(error) + "]"
        }
    }

    /// Routes an unresolved repair task into its remediation path
    /// (#321). Fresh-rescan tasks revise the pinned source revision so
    /// the new capture's coordinate authority is clean; in-place
    /// kinds enter the annotation workspace of the live revision.
    /// The source revision is never opened for mutation.
    func resolveRepairTask(_ row: HTDTRepairTaskRow) {
        guard !row.resolved else {
            return
        }
        activeRepairRow = row
        if row.task.kind == .freshRescan {
            guard let record = persistedInventory.captures
                .first(where: {
                    $0.captureRevisionID.description
                        == storedRepairPlan(for: row)?.plan
                            .sourceCaptureRevisionID
                })
            else {
                workingSetStatus = String(localized: "The source capture for this repair is not on this device — start a fresh capture to answer it")
                return
            }
            if state == .idle {
                revisePersistedCapture(record)
            } else {
                workingSetStatus = String(localized: "Repair task armed — it binds to the next finalized revision of the source")
            }
        } else {
            if state == .reviewing {
                beginAnnotation()
            } else {
                workingSetStatus = String(localized: "Repair task armed — open the annotation workspace on the review surface to correct it in place")
            }
        }
    }

    /// Records an HTDT-returned repair plan into the app-local ledger
    /// (#321). The canonical re-encode pins the plan digest that the
    /// repair link cites.
    private func recordRepairTaskPlan(
        _ plan: HTDTRepairTaskPlan,
        receiptID: String
    ) {
        guard let repairPlanStore,
              let planImport = try? HTDTRepairTaskPlanImport(
                  plan: plan
              )
        else {
            return
        }
        _ = try? repairPlanStore.record(
            planImport,
            receivedAtUTC: BundleTimestamp.utcString(from: Date())
        )
        refreshRepairTaskRows()
        workingSetStatus += String(localized: "; HTDT returned a repair task plan")
    }

    private func refreshRepairTaskRows() {
        repairTaskRows =
            (try? repairPlanStore?.unresolvedTaskRows()) ?? []
    }

    /// Recomputes mission checklist state from committed evidence —
    /// task-plan outcomes, as-built candidates/items, and whether a
    /// room frame exists to anchor plan alignment.
    private func refreshMissionOutcomes() async {
        guard let store = workingSetStore else {
            missionTaskPlanOutcomes = []
            asBuiltActualCandidates = []
            roomFrameAvailable = false
            return
        }
        let seed = (try? Self.committedAnnotationSeed(
            rootDirectory: await store.rootDirectory
        ).0) ?? AnnotationWorkspaceSeed()
        missionTaskPlanOutcomes =
            captureTaskPlanStatus?.itemOutcomes(
                annotations: seed.annotations,
                measurements: seed.measurements
            ) ?? []
        asBuiltActualCandidates = seed.annotations
        roomFrameAvailable =
            (try? await store.snapshot().roomReferenceFrame) != nil
        if let asBuiltSession {
            asBuiltItems = (try? asBuiltSession.items()) ?? []
        }
    }
}
