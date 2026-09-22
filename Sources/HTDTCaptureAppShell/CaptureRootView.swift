import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
import HTDTCapturePlatform
#if os(iOS)
import UIKit
#endif

public struct CaptureRootActions {
    public let beginCapture: () -> Void
    /// #212: operator confirmed the pre-capture setup screen; leaves
    /// `.setup` and starts the real capability→RoomPlan pipeline.
    public let beginScanning: () -> Void
    /// #212: operator cancelled setup; back to Idle, no capture made.
    public let cancelCaptureSetup: () -> Void
    public let beginReview: () -> Void
    public let captureEvidenceFrame: () -> Void
    /// #250 targeted-object pass actions.
    public let beginTargetScan: () -> Void
    public let retakeTargetScan: () -> Void
    public let acceptTargetScan: () -> Void
    public let cancelTargetScan: () -> Void
    /// #257 declared-region actions.
    public let declareNearestUnresolvedRegion:
        (DeclaredRegionReason) -> Void
    public let revokeOperatorRegion:
        (SpatialCoverageCellKey) -> Void
    /// #252 non-visual cue switch.
    public let setGuidanceCuesEnabled: (Bool) -> Void
    /// #273 return-to-start check arm/disarm.
    public let setLoopClosureCheckActive: (Bool) -> Void
    public let setScanMovementCapability:
        (ScanMovementCapability) -> Void
    public let continueScanning: () -> Void
    public let beginAnnotation: () -> Void
    public let captureRaycastPlacement:
        () async throws -> AnnotationPlacementAuthority
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Full-3D orientation capture for measurement-point direction
    /// authority (issue #271); distinct from the horizontal-heading
    /// `captureSpeakerOrientation` convention.
    public let capturePointOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Pollable reticle probe for the camera capture sheet (#214): a
    /// live classification of what the center ray is hitting.
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    /// Pollable camera yaw in degrees for the live heading arrow
    /// (#214).
    public let probeCameraHeading: () async -> Float?
    /// Targeted placement capture (#246): mesh / RoomPlan object /
    /// plane, never silently downgraded; nil means no hit.
    public let captureTargetedPlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    /// Captures a plain evidence frame for equipment-identity photos
    /// (#239); returns its canonical `path:` ref.
    public let captureIdentityPhoto: () async throws -> String
    /// Label-scan assist (#345): captures a close-up label frame, runs
    /// Vision OCR/barcode recognition, and returns suggestion
    /// candidates for explicit operator confirmation — it never
    /// commits anything.
    public let scanEquipmentLabel: () async throws
        -> EquipmentLabelScanResult
    /// Captures a dedicated close-up photo for field evidence
    /// (#314): image bytes + dims, no frame descriptor persisted.
    public let captureFieldEvidencePhoto:
        () async throws -> CapturedFieldPhoto
    /// Persists the staged field-authority workspace on Save (#300/
    /// #301/#310/#314/#324/#331).
    public let commitFieldAuthority:
        (FieldAuthorityWorkspace) -> Void
    public let commitAnnotationAuthority: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement],
        [EquipmentIdentityRecord],
        TheaterAuthorityCollection
    ) -> Void
    public let cancelAnnotation: () -> Void
    /// Operator capture-task profile selection (#217/#259/#352):
    /// on the setup screen it sets pending mission intent bound at
    /// Begin; once a working set exists it is an explicit recorded
    /// mission change. Carries optional skipped-requirement outcome.
    public let selectTaskProfile:
        (CaptureTaskProfile?, Set<String>) -> Void
    /// #352: imports an HTDT task plan file from the setup screen,
    /// before acquisition starts.
    public let importTaskPlan: (URL) -> Void
    /// #352: removes the pending imported plan during setup.
    public let clearTaskPlan: () -> Void
    /// #325: one-tap revisit flag while scanning; returns the new
    /// flag id when persisted (the view may then offer the optional
    /// category/note sheet), nil when the flag could not be recorded.
    public let flagForReview: () -> String?
    /// #325: saves the optional flag category/note sheet.
    public let updateRevisitFlagDetails:
        (String, ScanRevisitFlagCategory?, String?) -> Void
    /// #325: Review-side flag resolution — links authority,
    /// acknowledges, or marks unavailable.
    public let resolveRevisitFlag:
        (
            String,
            ScanRevisitFlagResolution.Outcome,
            String?
        ) -> Void
    /// #325: reopens a resolved/skipped/unavailable flag.
    public let reopenRevisitFlag: (String) -> Void
    /// #352: marks a bound task-plan checklist item in Review.
    public let markTaskPlanItem:
        (String, TaskPlanItemOutcome) -> Void
    /// Validates and adopts an imported HTDT equipment-catalog snapshot
    /// (#211). The host owns the catalog context for the app session and
    /// mirrors it to a durable app-support cache; the default simply
    /// decodes through the validating initializer without persisting.
    public let importEquipmentCatalog:
        (Data) throws -> HTDTEquipmentCatalogSnapshot
    /// Explicitly activates a catalog already stored in the host's
    /// multi-catalog library (#302); argument is the content key shown
    /// in `equipmentCatalogLibrary`.
    public let selectEquipmentCatalog: (String) -> Void
    public let finalizeCapture: () -> Void
    public let prepareExport: () -> Void
    public let resetCapture: () -> Void
    public let openPersistedCapture:
        (CaptureRevisionID) -> Void
    public let deletePersistedCapture:
        (CaptureRevisionID) -> Void
    public let removeQuarantinedArtifact:
        (PersistedCaptureQuarantinedArtifact) -> Void
    public let removeWorkingOrphan:
        (PersistedCaptureWorkingOrphan) -> Void
    public let revisePersistedCapture:
        (PersistedCaptureRecord) -> Void
    public let reviseAdoptedCapture: () -> Void
    public let importCaptureArchive: (URL) -> Void
    /// Explicit operator Cancel/Discard of the in-progress capture
    /// (#254): confirms in UI, tears down the live working set, and
    /// never touches finalized copies.
    public let discardActiveCapture: () -> Void
    /// Rebuilds the review-workspace model (#213) before the
    /// workspace is pushed.
    public let refreshReviewWorkspace: () -> Void
    /// Two-point room-reference-frame capture (#232).
    public let captureRoomFrameOrigin: () -> Void
    public let confirmRoomReferenceFrame: () -> Void
    /// Field/install datum capture (#232): derives the datum from
    /// the committed room reference frame, or removes the committed
    /// datum payload.
    public let confirmFieldDatumFromRoomFrame: () async -> Bool
    public let removeRoomFieldDatum: () async -> Void
    /// Captures the camera position for a user-declared opening
    /// candidate's center (#231).
    public let captureOpeningCenter: () -> Void
    /// Clears a pending opening-center capture (#231).
    public let clearOpeningCenter: () -> Void
    /// Enumerates opening candidates for the review step (#231).
    public let openingReviewCandidates:
        () async -> [RoomOpeningCandidate]?
    public let commitOpeningReview:
        ([RoomOpeningCandidate]) async -> Bool
    /// Privacy review: permanently removes an unreferenced evidence
    /// frame from the working capture (#241).
    public let removeEvidenceFrameForPrivacy:
        (EvidenceFrameID) async -> Void
    /// Loads a persisted capture into the read-only viewer (#294).
    public let loadPersistedWorkspace:
        (PersistedCaptureRecord) -> Void
    /// Field-level parent/child comparison for a revised capture
    /// (#221).
    public let compareAdoptedRevisionWithParent:
        () async -> CaptureRevisionComparison?
    /// Failed-capture inspection + diagnostic package (#224).
    public let inspectFailedCapture: () -> Void
    public let exportFailedCaptureDiagnostics:
        () async -> URL?
    /// Explicit Send-to-HTDT handoff (#225).
    public let sendCaptureToHTDT:
        (HTDTHandoffDestination) async -> Void
    /// Mission inbox (#386): import a mission package file, start or
    /// resume a record, deactivate the active mission, archive a
    /// record, and evaluate a record's dependency report for display
    /// before Start.
    public let importMissionPackage: (URL) async -> Void
    public let startMission: (String) async -> Void
    public let deactivateMission: () async -> Void
    public let archiveMission: (String) async -> Void
    public let evaluateMissionDependencies:
        (String) async throws -> HTDTMissionDependencyReport
    /// Destination pairing (#379): decode+validate a pasted/scanned
    /// QR payload, then confirm (stores the pinned pairing), forget,
    /// or revoke a pairing, and refresh a paired receiver's cached
    /// capability snapshot.
    public let pairDestinationPayload:
        (Data) throws -> HTDTReceiverPairingPayload
    public let confirmPairing:
        (HTDTReceiverPairingPayload) async -> Void
    public let forgetDestination: (String) async -> Void
    public let revokeDestination: (String) async -> Void
    public let refreshEndpointCapabilities:
        (String) async -> Void
    /// Delivery queue (#387): operator controls for the durable job
    /// ledger — retry-now skips backoff, pause/resume gate attempts,
    /// cancel marks the job terminal, purge frees the queue-owned
    /// payload copy.
    public let deliveryRetryNow: (String) async -> Void
    public let deliveryPause: (String) async -> Void
    public let deliveryResume: (String) async -> Void
    public let deliveryCancel: (String) async -> Void
    public let deliveryPurgePayload: (String) async -> Void
    /// Endpoint capability preflight (#374): fetches (or reads the
    /// cached snapshot of) the destination's capability document and
    /// classifies the current export's compatibility.
    public let preflightDestination:
        (HTDTHandoffDestination) async
            -> HTDTCompatibilityVerdict
    /// Independent export-archive deletion (#251).
    public let deleteExportArchive:
        (PersistedCaptureRecord) -> Void
    /// App-local library metadata (names, notes, series grouping)
    /// (#219).
    public let updateLibraryEntry:
        (CaptureRevisionID?, CaptureSeriesID?,
         CaptureLibraryEntryMetadata) -> Void
    /// Capture-strategy profile selection (#307). Advisory guidance
    /// and evidence budgets only; a task-plan-pinned strategy cannot
    /// be changed by the operator.
    public let selectCaptureStrategy:
        (CaptureStrategyIdentifier) -> Void
    /// Plan-reference underlay import (#322): the host reads and
    /// validates the plan document at the given URL. Underlay
    /// authority stays reference-only — it never becomes observed
    /// truth.
    public let importPlanReference: (URL) -> Void
    /// Semantic-only child revision (#319): loads the parent context
    /// and opens the correction sheet.
    public let beginSemanticCorrection:
        (PersistedCaptureRecord) -> Void
    /// Builds the semantic child from the sheet's edits; true on
    /// success.
    public let commitSemanticCorrection:
        (SemanticChildRevisionEdits) async -> Bool
    public let cancelSemanticCorrection: () -> Void
    /// Reopen an end-accepted working revision that survived a
    /// relaunch (issue #297): the draft comes back as a spatially
    /// sealed Review — semantic work continues, live AR capture never
    /// resumes.
    public let openRecoveredDraft:
        (RecoverableWorkingRevision) -> Void
    /// Permanently remove a recoverable draft's working revision.
    public let discardRecoveredDraft:
        (RecoverableWorkingRevision) -> Void
    /// "Save and finish later" (issue #297): leave Review without
    /// discarding the working revision; it stays listed as a
    /// recoverable draft on the next launch.
    public let suspendReview: () -> Void
    /// Review remediation affordance (issue #298): routes the operator
    /// to the surface that can legitimately clear a diagnostic — never
    /// a quality-gate bypass.
    public let performRemediation:
        (CaptureRemediationAction) -> Void
    /// Practice/onboarding mode (issue #320): a guided rehearsal
    /// capture that can never produce a real finalized bundle.
    public let beginPracticeCapture: () -> Void
    /// Dismiss the first-launch practice prompt; `permanently` records
    /// "Don't show again" so the prompt is skipped forever while
    /// practice stays reachable from the home surface.
    public let dismissPracticePrompt: (Bool) -> Void
    /// #295 permission-recovery actions for the `.permissions` and
    /// `.setup` states: re-check the camera permission and resume the
    /// pre-capture pipeline, open iOS Settings, or leave the
    /// prerequisite flow back to idle without fabricating a failed
    /// capture.
    public let retryCameraPermission: () -> Void
    public let openCameraSettings: () -> Void
    /// Leaves `.capabilityCheck`/`.permissions` back to `.idle`.
    public let cancelCaptureStart: () -> Void

    public init(
        beginCapture: @escaping () -> Void = {},
        beginScanning: @escaping () -> Void = {},
        cancelCaptureSetup: @escaping () -> Void = {},
        beginReview: @escaping () -> Void = {},
        captureEvidenceFrame: @escaping () -> Void = {},
        beginTargetScan: @escaping () -> Void = {},
        retakeTargetScan: @escaping () -> Void = {},
        acceptTargetScan: @escaping () -> Void = {},
        cancelTargetScan: @escaping () -> Void = {},
        declareNearestUnresolvedRegion: @escaping
            (DeclaredRegionReason) -> Void = { _ in },
        revokeOperatorRegion: @escaping
            (SpatialCoverageCellKey) -> Void = { _ in },
        setGuidanceCuesEnabled: @escaping
            (Bool) -> Void = { _ in },
        setLoopClosureCheckActive: @escaping
            (Bool) -> Void = { _ in },
        setScanMovementCapability: @escaping
            (ScanMovementCapability) -> Void = { _ in },
        continueScanning: @escaping () -> Void = {},
        beginAnnotation: @escaping () -> Void = {},
        captureRaycastPlacement: @escaping
            () async throws -> AnnotationPlacementAuthority = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        capturePointOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError
                    .pointDirectionUnavailable
            },
        probePlacementTarget: @escaping
            () async -> AnnotationPlacementProbe = { .unavailable },
        probeCameraHeading: @escaping
            () async -> Float? = { nil },
        captureTargetedPlacement: @escaping (
            PlacementTargetPreference
        ) async throws -> AnnotationPlacementAuthority? = { _ in
            nil
        },
        captureIdentityPhoto: @escaping
            () async throws -> String = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        scanEquipmentLabel: @escaping
            () async throws -> EquipmentLabelScanResult = {
                throw EquipmentLabelScanError.scanUnavailable
            },
        captureFieldEvidencePhoto: @escaping
            () async throws -> CapturedFieldPhoto = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        commitFieldAuthority: @escaping
            (FieldAuthorityWorkspace) -> Void = { _ in },
        commitAnnotationAuthority: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement],
            [EquipmentIdentityRecord],
            TheaterAuthorityCollection
        ) -> Void = { _, _, _, _ in },
        cancelAnnotation: @escaping () -> Void = {},
        selectTaskProfile: @escaping
            (CaptureTaskProfile?, Set<String>) -> Void
                = { _, _ in },
        importTaskPlan: @escaping (URL) -> Void = { _ in },
        clearTaskPlan: @escaping () -> Void = {},
        flagForReview: @escaping () -> String? = { nil },
        updateRevisitFlagDetails: @escaping
            (String, ScanRevisitFlagCategory?, String?) -> Void
                = { _, _, _ in },
        resolveRevisitFlag: @escaping
            (
                String,
                ScanRevisitFlagResolution.Outcome,
                String?
            ) -> Void = { _, _, _ in },
        reopenRevisitFlag: @escaping (String) -> Void = { _ in },
        markTaskPlanItem: @escaping
            (String, TaskPlanItemOutcome) -> Void = { _, _ in },
        importEquipmentCatalog: @escaping
            (Data) throws -> HTDTEquipmentCatalogSnapshot = { data in
                try JSONDecoder().decode(
                    HTDTEquipmentCatalogSnapshot.self,
                    from: data
                )
            },
        selectEquipmentCatalog: @escaping (String) -> Void = { _ in },
        finalizeCapture: @escaping () -> Void = {},
        prepareExport: @escaping () -> Void = {},
        resetCapture: @escaping () -> Void = {},
        openPersistedCapture: @escaping
            (CaptureRevisionID) -> Void = { _ in },
        deletePersistedCapture: @escaping
            (CaptureRevisionID) -> Void = { _ in },
        removeQuarantinedArtifact: @escaping
            (PersistedCaptureQuarantinedArtifact) -> Void
                = { _ in },
        removeWorkingOrphan: @escaping
            (PersistedCaptureWorkingOrphan) -> Void
                = { _ in },
        revisePersistedCapture: @escaping
            (PersistedCaptureRecord) -> Void = { _ in },
        reviseAdoptedCapture: @escaping () -> Void = {},
        importCaptureArchive: @escaping (URL) -> Void = { _ in },
        discardActiveCapture: @escaping () -> Void = {},
        refreshReviewWorkspace: @escaping () -> Void = {},
        captureRoomFrameOrigin: @escaping () -> Void = {},
        confirmRoomReferenceFrame: @escaping () -> Void = {},
        confirmFieldDatumFromRoomFrame: @escaping
            () async -> Bool = { false },
        removeRoomFieldDatum: @escaping
            () async -> Void = {},
        captureOpeningCenter: @escaping () -> Void = {},
        clearOpeningCenter: @escaping () -> Void = {},
        openingReviewCandidates: @escaping
            () async -> [RoomOpeningCandidate]? = { nil },
        commitOpeningReview: @escaping
            ([RoomOpeningCandidate]) async -> Bool = {
                _ in false
            },
        removeEvidenceFrameForPrivacy: @escaping
            (EvidenceFrameID) async -> Void = { _ in },
        loadPersistedWorkspace: @escaping
            (PersistedCaptureRecord) -> Void = { _ in },
        compareAdoptedRevisionWithParent: @escaping
            () async -> CaptureRevisionComparison? = { nil },
        inspectFailedCapture: @escaping () -> Void = {},
        exportFailedCaptureDiagnostics: @escaping
            () async -> URL? = { nil },
        sendCaptureToHTDT: @escaping
            (HTDTHandoffDestination) async -> Void = { _ in },
        importMissionPackage: @escaping (URL) async -> Void
            = { _ in },
        startMission: @escaping (String) async -> Void = { _ in },
        deactivateMission: @escaping () async -> Void = {},
        archiveMission: @escaping (String) async -> Void = { _ in },
        evaluateMissionDependencies: @escaping
            (String) async throws -> HTDTMissionDependencyReport = { _ in
                HTDTMissionDependencyReport()
            },
        pairDestinationPayload: @escaping
            (Data) throws -> HTDTReceiverPairingPayload = { data in
                try HTDTReceiverPairingPayload(data: data)
            },
        confirmPairing: @escaping
            (HTDTReceiverPairingPayload) async -> Void = { _ in },
        forgetDestination: @escaping (String) async -> Void
            = { _ in },
        revokeDestination: @escaping (String) async -> Void
            = { _ in },
        refreshEndpointCapabilities: @escaping
            (String) async -> Void = { _ in },
        deliveryRetryNow: @escaping (String) async -> Void
            = { _ in },
        deliveryPause: @escaping (String) async -> Void = { _ in },
        deliveryResume: @escaping (String) async -> Void = { _ in },
        deliveryCancel: @escaping (String) async -> Void = { _ in },
        deliveryPurgePayload: @escaping (String) async -> Void
            = { _ in },
        preflightDestination: @escaping
            (HTDTHandoffDestination) async
                -> HTDTCompatibilityVerdict = { _ in
                    .unknown(reason: "No preflight host bound")
                },
        deleteExportArchive: @escaping
            (PersistedCaptureRecord) -> Void = { _ in },
        updateLibraryEntry: @escaping (
            CaptureRevisionID?,
            CaptureSeriesID?,
            CaptureLibraryEntryMetadata
        ) -> Void = { _, _, _ in },
        selectCaptureStrategy: @escaping
            (CaptureStrategyIdentifier) -> Void = { _ in },
        importPlanReference: @escaping (URL) -> Void = { _ in },
        beginSemanticCorrection: @escaping
            (PersistedCaptureRecord) -> Void = { _ in },
        commitSemanticCorrection: @escaping
            (SemanticChildRevisionEdits) async -> Bool = {
                _ in false
            },
        cancelSemanticCorrection: @escaping () -> Void = {},
        openRecoveredDraft: @escaping
            (RecoverableWorkingRevision) -> Void = { _ in },
        discardRecoveredDraft: @escaping
            (RecoverableWorkingRevision) -> Void = { _ in },
        suspendReview: @escaping () -> Void = {},
        performRemediation: @escaping
            (CaptureRemediationAction) -> Void = { _ in },
        beginPracticeCapture: @escaping () -> Void = {},
        dismissPracticePrompt: @escaping (Bool) -> Void = { _ in },
        retryCameraPermission: @escaping () -> Void = {},
        openCameraSettings: @escaping () -> Void = {},
        cancelCaptureStart: @escaping () -> Void = {}
    ) {
        self.beginCapture = beginCapture
        self.beginScanning = beginScanning
        self.cancelCaptureSetup = cancelCaptureSetup
        self.beginReview = beginReview
        self.captureEvidenceFrame = captureEvidenceFrame
        self.beginTargetScan = beginTargetScan
        self.retakeTargetScan = retakeTargetScan
        self.acceptTargetScan = acceptTargetScan
        self.cancelTargetScan = cancelTargetScan
        self.declareNearestUnresolvedRegion =
            declareNearestUnresolvedRegion
        self.revokeOperatorRegion = revokeOperatorRegion
        self.setGuidanceCuesEnabled = setGuidanceCuesEnabled
        self.setLoopClosureCheckActive = setLoopClosureCheckActive
        self.setScanMovementCapability =
            setScanMovementCapability
        self.continueScanning = continueScanning
        self.beginAnnotation = beginAnnotation
        self.captureRaycastPlacement = captureRaycastPlacement
        self.captureSpeakerOrientation =
            captureSpeakerOrientation
        self.capturePointOrientation =
            capturePointOrientation
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureIdentityPhoto = captureIdentityPhoto
        self.scanEquipmentLabel = scanEquipmentLabel
        self.captureFieldEvidencePhoto =
            captureFieldEvidencePhoto
        self.commitFieldAuthority = commitFieldAuthority
        self.commitAnnotationAuthority =
            commitAnnotationAuthority
        self.cancelAnnotation = cancelAnnotation
        self.selectTaskProfile = selectTaskProfile
        self.importTaskPlan = importTaskPlan
        self.clearTaskPlan = clearTaskPlan
        self.flagForReview = flagForReview
        self.updateRevisitFlagDetails = updateRevisitFlagDetails
        self.resolveRevisitFlag = resolveRevisitFlag
        self.reopenRevisitFlag = reopenRevisitFlag
        self.markTaskPlanItem = markTaskPlanItem
        self.importEquipmentCatalog = importEquipmentCatalog
        self.selectEquipmentCatalog = selectEquipmentCatalog
        self.finalizeCapture = finalizeCapture
        self.prepareExport = prepareExport
        self.resetCapture = resetCapture
        self.openPersistedCapture = openPersistedCapture
        self.deletePersistedCapture = deletePersistedCapture
        self.removeQuarantinedArtifact =
            removeQuarantinedArtifact
        self.removeWorkingOrphan = removeWorkingOrphan
        self.revisePersistedCapture = revisePersistedCapture
        self.reviseAdoptedCapture = reviseAdoptedCapture
        self.importCaptureArchive = importCaptureArchive
        self.discardActiveCapture = discardActiveCapture
        self.refreshReviewWorkspace = refreshReviewWorkspace
        self.captureRoomFrameOrigin = captureRoomFrameOrigin
        self.confirmRoomReferenceFrame =
            confirmRoomReferenceFrame
        self.confirmFieldDatumFromRoomFrame =
            confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = removeRoomFieldDatum
        self.captureOpeningCenter = captureOpeningCenter
        self.clearOpeningCenter = clearOpeningCenter
        self.openingReviewCandidates = openingReviewCandidates
        self.commitOpeningReview = commitOpeningReview
        self.removeEvidenceFrameForPrivacy =
            removeEvidenceFrameForPrivacy
        self.loadPersistedWorkspace = loadPersistedWorkspace
        self.compareAdoptedRevisionWithParent =
            compareAdoptedRevisionWithParent
        self.inspectFailedCapture = inspectFailedCapture
        self.exportFailedCaptureDiagnostics =
            exportFailedCaptureDiagnostics
        self.sendCaptureToHTDT = sendCaptureToHTDT
        self.importMissionPackage = importMissionPackage
        self.startMission = startMission
        self.deactivateMission = deactivateMission
        self.archiveMission = archiveMission
        self.evaluateMissionDependencies =
            evaluateMissionDependencies
        self.pairDestinationPayload = pairDestinationPayload
        self.confirmPairing = confirmPairing
        self.forgetDestination = forgetDestination
        self.revokeDestination = revokeDestination
        self.refreshEndpointCapabilities =
            refreshEndpointCapabilities
        self.deliveryRetryNow = deliveryRetryNow
        self.deliveryPause = deliveryPause
        self.deliveryResume = deliveryResume
        self.deliveryCancel = deliveryCancel
        self.deliveryPurgePayload = deliveryPurgePayload
        self.preflightDestination = preflightDestination
        self.deleteExportArchive = deleteExportArchive
        self.updateLibraryEntry = updateLibraryEntry
        self.selectCaptureStrategy = selectCaptureStrategy
        self.importPlanReference = importPlanReference
        self.beginSemanticCorrection = beginSemanticCorrection
        self.commitSemanticCorrection =
            commitSemanticCorrection
        self.cancelSemanticCorrection = cancelSemanticCorrection
        self.openRecoveredDraft = openRecoveredDraft
        self.discardRecoveredDraft = discardRecoveredDraft
        self.suspendReview = suspendReview
        self.performRemediation = performRemediation
        self.beginPracticeCapture = beginPracticeCapture
        self.dismissPracticePrompt = dismissPracticePrompt
        self.retryCameraPermission = retryCameraPermission
        self.openCameraSettings = openCameraSettings
        self.cancelCaptureStart = cancelCaptureStart
    }
}

#if os(iOS)
/// The system share sheet used for the share-destination HTDT
/// handoff (#225): presenting it and completing the share is the
/// operator's explicit transfer action.
private struct HandoffShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#else
/// Non-iOS fallback: the share destination renders as an inert view;
/// endpoint destinations still send through the network path.
private struct HandoffShareSheet: View {
    let items: [Any]

    var body: some View {
        Text("Sharing is available on iOS only")
    }
}
#endif

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let lastFailure: CaptureFailureCode?
    public let workingSetStatus: String?
    public let qualityReport: CaptureQualityReport?
    public let advisoryReport: CaptureAdvisoryReport?
    /// Operator capture-task profile selected for this capture
    /// (#217/#259). Nil = geometry-only / no profile.
    public let taskProfile: CaptureTaskProfile?
    public let validationReport: BundleValidationReport?
    public let exportURL: URL?
    public let annotationCoordinateSpaceID: CoordinateSpaceID?
    public let annotationEvidenceRefs: [String]
    /// Captured RoomPlan elements/mesh anchors the authority sheets
    /// offer as binding targets (#218).
    public let annotationRoomPlanSurfaces: [CapturedSurfaceOption]
    public let annotationMeshAnchors: [CapturedSurfaceOption]
    public let annotationAuthorityCommitted: Bool
    /// Reloaded canonical authority used to seed a pre-finalization
    /// correction pass through the annotation workspace (#163).
    public let annotationRevisionSeed: AnnotationWorkspaceSeed?
    /// Host-owned HTDT equipment-catalog reference context for the
    /// annotation workspace (#211). Survives annotation cancel → Review
    /// → re-enter and relaunch; never part of capture-bundle authority.
    public let equipmentCatalog: HTDTEquipmentCatalogSnapshot?
    /// Every snapshot stored in the host's catalog library (#302); the
    /// workspace renders identity rows and explicit switching.
    public let equipmentCatalogLibrary:
        [HTDTEquipmentCatalogLibrary.StoredCatalog]
    /// Imported capture task plan (#240), when loaded — drives the
    /// pinned-catalog requirement (#302) and the role-binding profile
    /// (#315) in the annotation workspace.
    public let taskPlan: HTDTCaptureTaskPlan?
    /// Identity of the live working revision; carries the
    /// series/parent linkage for a revise-existing capture (#155).
    public let workingSetIdentity: CaptureWorkingSetIdentity?
    /// Visual presentation rows for the evidence refs (#255).
    public let annotationEvidenceFrames: [EvidenceFramePresentation]
    /// RoomPlan objects offered for direct placement binding (#246).
    public let annotationRoomPlanObjects: [RoomPlanBindableObject]
    /// Advisory plausibility findings for Review (#247); nil while the
    /// accepted-geometry context is unavailable.
    public let spatialPlausibilityFindings:
        [SpatialPlausibilityFinding]?
    /// The geometry context those findings / the workspace's live
    /// hints were evaluated against (#247).
    public let annotationPlausibilityContext:
        SpatialPlausibilityContext
    /// Speaker-layout plans offered for guided batch capture (#278).
    public let speakerLayoutPlans: [SpeakerLayoutPlan]
    /// Session equipment-picker recents (#265).
    public let equipmentRecents: EquipmentRecents
    /// Draft store + binding for workspace autosave (#266).
    public let annotationDraftStore: AnnotationWorkspaceDraftStore?
    public let annotationDraftRevisionID: CaptureRevisionID?
    public let scanningPreview: AnyView?
    public let scanCoverage: ScanCoverageSummary
    public let observationStability: ObservationStabilitySummary
    public let spatialCoverage: SpatialScanCoverageSummary
    public let motionGuidance: ScanMotionGuidance?
    public let scanGuidanceProgress: ScanGuidanceProgress
    public let derivedShapePreview: DerivedShapePreviewSnapshot
    public let scanEvidenceFrameCount: Int
    public let endScanGuidance: String?
    /// Pre-capture setup model shown while `state == .setup` (#212).
    public let captureSetup: CaptureSetupPresentation?
    /// Scanning surfaces for #250/#257/#252/#273/#279/#216/#283.
    public let isEndingScan: Bool
    public let isCapturingEvidence: Bool
    public let automaticEvidenceCount: Int
    public let lowLightGuidanceActive: Bool
    public let targetScanStatus: TargetScanStatus?
    public let declaredRegions: [DeclaredCoverageRegion]
    public let loopClosureCheckActive: Bool
    public let loopClosureAssessment: LoopClosureAssessment?
    public let guidanceCuesEnabled: Bool
    /// Revisit flags dropped during the live scan (#325).
    public let revisitFlags: [ScanRevisitFlag]
    /// True when the bounded flag store is full.
    public let revisitFlagsFull: Bool
    public let persistedInventory:
        PersistedCaptureInventoryResult
    /// Live review-workspace model (#213); rebuilt by the host on
    /// request.
    public let reviewWorkspace: CaptureReviewWorkspaceModel?
    /// Read-only persisted workspace (#294).
    public let persistedWorkspace: CaptureReviewWorkspaceModel?
    /// First captured room-frame point pending the front point
    /// (#232).
    public let roomFrameOriginPending: WorldPoint3D?
    /// Pending camera-captured center for a user-declared opening
    /// candidate (issue #231).
    public let openingCenterPending: WorldPoint3D?
    /// Committed evidence references dangling after a re-End (#236).
    public let danglingSpatialIssues: [SpatialEvidenceIssue]
    /// Operator-visible Send-to-HTDT destinations + receipts (#225).
    public let handoffDestinations: [HTDTHandoffDestination]
    public let handoffReceipts: [HTDTHandoffReceipt]
    /// Mission inbox records (#386), the active record id, QR-paired
    /// receivers (#379) and the durable delivery-job ledger (#387) —
    /// surfaced on the home screen's sidebar.
    public let missionRecords: [HTDTMissionRecord]
    public let activeMissionRecordID: String?
    public let pairedDestinations: [PairedHTDTDestination]
    public let deliveryJobs: [HTDTDeliveryJob]
    /// App-local capture names/notes/series metadata (#219).
    public let libraryMetadata: CaptureLibraryMetadataDocument
    /// Retained-evidence inspection for a failed capture (#224).
    public let failedInspection: FailedCaptureInspection?
    /// Required-task mission progress shown in the journey header
    /// (#372); nil when no plan is active.
    public let taskPlanMission: CaptureJourneyMissionSummary?
    /// Spatial authority sealed for finalization (#276).
    public let spatialCaptureSealed: Bool
    /// Live evidence-storage advisory for the scanning HUD (#308).
    public let evidenceStorageAdvisory:
        CaptureEvidenceStorageAdvisory?
    /// Selected capture-strategy profile for setup display (#307);
    /// pinned means the active task plan fixed it.
    public let selectedStrategyID: CaptureStrategyIdentifier
    public let strategyPinnedByTaskPlan: Bool
    /// App-local acquisition origins keyed by revision (#317).
    public let captureOrigins:
        [CaptureRevisionID: CaptureAcquisitionOriginRecord]
    /// Pending/committed plan-reference underlay (#322).
    public let planUnderlayDocument: PlanUnderlayDocument?
    /// Parent context for the in-flight semantic correction (#319);
    /// nil when no correction sheet is open.
    public let semanticCorrectionContext:
        SemanticChildRevisionContext?
    /// Whether the working set's AR coordinate authority is still
    /// live (issue #297). False on a draft recovered after relaunch:
    /// spatial evidence is frozen and live-capture affordances
    /// (Continue scanning, evidence frames) must not appear.
    public let liveSpatialAuthority: Bool
    /// Recovery provenance for a draft reopened after relaunch
    /// (issue #297): unsupported/superseded files the restore pass
    /// found, surfaced instead of guessed.
    public let recoveredDraftReport: WorkingRevisionRestoreReport?
    /// True while the active working set is a practice capture
    /// (issue #320): never finalizable, never sendable to HTDT.
    public let practiceCaptureActive: Bool
    /// First-launch practice prompt (#320): the host shows it once
    /// unless the operator permanently dismissed it.
    public let practicePromptShown: Bool
    /// Long-running host operations currently in flight (#309).
    /// Controls whose underlying guard would silently no-op are
    /// disabled and each in-flight op shows explicit progress.
    public let activeOperations: Set<CaptureHostOperation>
    /// The persisted revision an open/delete operation targets, so
    /// the library row itself can show its busy state (#309).
    public let operationTargetRevisionID: CaptureRevisionID?
    /// Bound space for the annotation workspace (#276): while live
    /// capture runs it is the active session space; once sealed after
    /// a committed pass it stays bound so non-spatial corrections can
    /// reopen the saved authority.
    public let annotationWorkspaceCoordinateSpaceID: CoordinateSpaceID?
    public let actions: CaptureRootActions

    @State private var pendingDeletion:
        PendingCaptureDeletion?
    @State private var importingCaptureArchive = false
    @State private var confirmingDiscard = false
    @State private var reviewWorkspaceShown = false
    @State private var handoffDestinationsShown = false
    @State private var shareArchiveForHandoff = false
    @State private var revisionComparison:
        CaptureRevisionComparison?
    @State private var comparisonLoading = false
    @State private var importingPlanReference = false
    @State private var confirmingExport = false
    @State private var diagnosticShareURL: URL?
    /// Per-destination endpoint preflight results keyed by
    /// destination id (#374).
    @State private var preflightVerdicts:
        [String: HTDTCompatibilityVerdict] = [:]
    @State private var preflightInFlight: Set<String> = []

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        lastFailure: CaptureFailureCode? = nil,
        workingSetStatus: String? = nil,
        qualityReport: CaptureQualityReport? = nil,
        advisoryReport: CaptureAdvisoryReport? = nil,
        taskProfile: CaptureTaskProfile? = nil,
        validationReport: BundleValidationReport? = nil,
        exportURL: URL? = nil,
        annotationCoordinateSpaceID: CoordinateSpaceID? = nil,
        annotationWorkspaceCoordinateSpaceID: CoordinateSpaceID? = nil,
        annotationEvidenceRefs: [String] = [],
        annotationRoomPlanSurfaces: [CapturedSurfaceOption] = [],
        annotationMeshAnchors: [CapturedSurfaceOption] = [],
        annotationAuthorityCommitted: Bool = false,
        annotationRevisionSeed: AnnotationWorkspaceSeed? = nil,
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        equipmentCatalogLibrary:
            [HTDTEquipmentCatalogLibrary.StoredCatalog] = [],
        taskPlan: HTDTCaptureTaskPlan? = nil,
        /// Required-task progress for the journey header (#372):
        /// evaluated by the host from the plan plus the committed
        /// records — nil when no plan is active or none are required.
        taskPlanMission: CaptureJourneyMissionSummary? = nil,
        workingSetIdentity: CaptureWorkingSetIdentity? = nil,
        annotationEvidenceFrames: [EvidenceFramePresentation] = [],
        annotationRoomPlanObjects: [RoomPlanBindableObject] = [],
        spatialPlausibilityFindings:
            [SpatialPlausibilityFinding]? = nil,
        annotationPlausibilityContext: SpatialPlausibilityContext =
            SpatialPlausibilityContext(),
        speakerLayoutPlans: [SpeakerLayoutPlan] = [],
        equipmentRecents: EquipmentRecents = EquipmentRecents(),
        annotationDraftStore: AnnotationWorkspaceDraftStore? = nil,
        annotationDraftRevisionID: CaptureRevisionID? = nil,
        scanningPreview: AnyView? = nil,
        scanCoverage: ScanCoverageSummary = .empty,
        observationStability: ObservationStabilitySummary = .empty,
        spatialCoverage: SpatialScanCoverageSummary = .empty,
        motionGuidance: ScanMotionGuidance? = nil,
        scanGuidanceProgress: ScanGuidanceProgress = .empty,
        derivedShapePreview: DerivedShapePreviewSnapshot = .empty,
        scanEvidenceFrameCount: Int = 0,
        endScanGuidance: String? = nil,
        captureSetup: CaptureSetupPresentation? = nil,
        isEndingScan: Bool = false,
        isCapturingEvidence: Bool = false,
        automaticEvidenceCount: Int = 0,
        lowLightGuidanceActive: Bool = false,
        targetScanStatus: TargetScanStatus? = nil,
        declaredRegions: [DeclaredCoverageRegion] = [],
        loopClosureCheckActive: Bool = false,
        loopClosureAssessment: LoopClosureAssessment? = nil,
        guidanceCuesEnabled: Bool = true,
        revisitFlags: [ScanRevisitFlag] = [],
        revisitFlagsFull: Bool = false,
        persistedInventory:
            PersistedCaptureInventoryResult
                = PersistedCaptureInventoryResult(),
        reviewWorkspace: CaptureReviewWorkspaceModel? = nil,
        persistedWorkspace: CaptureReviewWorkspaceModel? = nil,
        roomFrameOriginPending: WorldPoint3D? = nil,
        openingCenterPending: WorldPoint3D? = nil,
        danglingSpatialIssues: [SpatialEvidenceIssue] = [],
        handoffDestinations: [HTDTHandoffDestination] = [],
        handoffReceipts: [HTDTHandoffReceipt] = [],
        missionRecords: [HTDTMissionRecord] = [],
        activeMissionRecordID: String? = nil,
        pairedDestinations: [PairedHTDTDestination] = [],
        deliveryJobs: [HTDTDeliveryJob] = [],
        libraryMetadata: CaptureLibraryMetadataDocument
            = CaptureLibraryMetadataDocument(),
        failedInspection: FailedCaptureInspection? = nil,
        spatialCaptureSealed: Bool = false,
        evidenceStorageAdvisory:
            CaptureEvidenceStorageAdvisory? = nil,
        selectedStrategyID: CaptureStrategyIdentifier = .standard,
        strategyPinnedByTaskPlan: Bool = false,
        captureOrigins:
            [CaptureRevisionID: CaptureAcquisitionOriginRecord] = [:],
        planUnderlayDocument: PlanUnderlayDocument? = nil,
        semanticCorrectionContext:
            SemanticChildRevisionContext? = nil,
        liveSpatialAuthority: Bool = true,
        recoveredDraftReport: WorkingRevisionRestoreReport? = nil,
        practiceCaptureActive: Bool = false,
        practicePromptShown: Bool = false,
        activeOperations: Set<CaptureHostOperation> = [],
        operationTargetRevisionID: CaptureRevisionID? = nil,
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.state = state
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.lastFailure = lastFailure
        self.workingSetStatus = workingSetStatus
        self.qualityReport = qualityReport
        self.advisoryReport = advisoryReport
        self.taskProfile = taskProfile
        self.validationReport = validationReport
        self.exportURL = exportURL
        self.annotationCoordinateSpaceID =
            annotationCoordinateSpaceID
        self.annotationWorkspaceCoordinateSpaceID =
            annotationWorkspaceCoordinateSpaceID
        self.annotationEvidenceRefs = annotationEvidenceRefs
        self.annotationRoomPlanSurfaces =
            annotationRoomPlanSurfaces
        self.annotationMeshAnchors = annotationMeshAnchors
        self.annotationAuthorityCommitted =
            annotationAuthorityCommitted
        self.annotationRevisionSeed = annotationRevisionSeed
        self.equipmentCatalog = equipmentCatalog
        self.equipmentCatalogLibrary = equipmentCatalogLibrary
        self.taskPlan = taskPlan
        self.taskPlanMission = taskPlanMission
        self.workingSetIdentity = workingSetIdentity
        self.annotationEvidenceFrames = annotationEvidenceFrames
        self.annotationRoomPlanObjects = annotationRoomPlanObjects
        self.spatialPlausibilityFindings =
            spatialPlausibilityFindings
        self.annotationPlausibilityContext =
            annotationPlausibilityContext
        self.speakerLayoutPlans = speakerLayoutPlans
        self.equipmentRecents = equipmentRecents
        self.annotationDraftStore = annotationDraftStore
        self.annotationDraftRevisionID = annotationDraftRevisionID
        self.scanningPreview = scanningPreview
        self.scanCoverage = scanCoverage
        self.observationStability = observationStability
        self.spatialCoverage = spatialCoverage
        self.motionGuidance = motionGuidance
        self.scanGuidanceProgress = scanGuidanceProgress
        self.derivedShapePreview = derivedShapePreview
        self.scanEvidenceFrameCount = scanEvidenceFrameCount
        self.endScanGuidance = endScanGuidance
        self.captureSetup = captureSetup
        self.isEndingScan = isEndingScan
        self.isCapturingEvidence = isCapturingEvidence
        self.automaticEvidenceCount = automaticEvidenceCount
        self.lowLightGuidanceActive = lowLightGuidanceActive
        self.targetScanStatus = targetScanStatus
        self.declaredRegions = declaredRegions
        self.loopClosureCheckActive = loopClosureCheckActive
        self.loopClosureAssessment = loopClosureAssessment
        self.guidanceCuesEnabled = guidanceCuesEnabled
        self.revisitFlags = revisitFlags
        self.revisitFlagsFull = revisitFlagsFull
        self.persistedInventory = persistedInventory
        self.reviewWorkspace = reviewWorkspace
        self.persistedWorkspace = persistedWorkspace
        self.roomFrameOriginPending = roomFrameOriginPending
        self.openingCenterPending = openingCenterPending
        self.danglingSpatialIssues = danglingSpatialIssues
        self.handoffDestinations = handoffDestinations
        self.handoffReceipts = handoffReceipts
        self.missionRecords = missionRecords
        self.activeMissionRecordID = activeMissionRecordID
        self.pairedDestinations = pairedDestinations
        self.deliveryJobs = deliveryJobs
        self.libraryMetadata = libraryMetadata
        self.failedInspection = failedInspection
        self.spatialCaptureSealed = spatialCaptureSealed
        self.evidenceStorageAdvisory = evidenceStorageAdvisory
        self.selectedStrategyID = selectedStrategyID
        self.strategyPinnedByTaskPlan = strategyPinnedByTaskPlan
        self.captureOrigins = captureOrigins
        self.planUnderlayDocument = planUnderlayDocument
        self.semanticCorrectionContext =
            semanticCorrectionContext
        self.liveSpatialAuthority = liveSpatialAuthority
        self.recoveredDraftReport = recoveredDraftReport
        self.practiceCaptureActive = practiceCaptureActive
        self.practicePromptShown = practicePromptShown
        self.activeOperations = activeOperations
        self.operationTargetRevisionID =
            operationTargetRevisionID
        self.actions = actions
    }

    /// Manifest-declared `evidence/frames/*.pixelbin` payloads — the
    /// visual camera evidence the export would package (issue #241).
    private var retainedVisualEvidenceCount: Int {
        validationReport?.manifest.files
            .filter {
                $0.path.hasPrefix("evidence/frames/")
                    && $0.path.hasSuffix(".pixelbin")
            }
            .count ?? 0
    }

    public var body: some View {
        Group {
            if state == .scanning,
               let scanningPreview
            {
                CaptureScanningView(
                    preview: scanningPreview,
                    coverage: scanCoverage,
                    observation: observationStability,
                    spatialCoverage: spatialCoverage,
                    motionGuidance: motionGuidance,
                    guidanceProgress: scanGuidanceProgress,
                    derivedPreview: derivedShapePreview,
                    evidenceFrameCount: scanEvidenceFrameCount,
                    statusMessage: workingSetStatus,
                    endScanGuidance: endScanGuidance,
                    isEndingScan: isEndingScan,
                    isCapturingEvidence: isCapturingEvidence,
                    automaticEvidenceCount: automaticEvidenceCount,
                    evidenceStorageAdvisory: evidenceStorageAdvisory,
                    lowLightGuidanceActive: lowLightGuidanceActive,
                    targetScanStatus: targetScanStatus,
                    declaredRegions: declaredRegions,
                    loopClosureCheckActive: loopClosureCheckActive,
                    loopClosureAssessment: loopClosureAssessment,
                    guidanceCuesEnabled: guidanceCuesEnabled,
                    revisitFlagCount: revisitFlags.filter {
                        $0.status == .unresolved
                    }.count,
                    revisitFlagsFull: revisitFlagsFull,
                    flagForReview: actions.flagForReview,
                    updateRevisitFlagDetails:
                        actions.updateRevisitFlagDetails,
                    beginTargetScan: actions.beginTargetScan,
                    retakeTargetScan: actions.retakeTargetScan,
                    acceptTargetScan: actions.acceptTargetScan,
                    cancelTargetScan: actions.cancelTargetScan,
                    declareNearestUnresolvedRegion:
                        actions.declareNearestUnresolvedRegion,
                    revokeOperatorRegion:
                        actions.revokeOperatorRegion,
                    setGuidanceCuesEnabled:
                        actions.setGuidanceCuesEnabled,
                    setLoopClosureCheckActive:
                        actions.setLoopClosureCheckActive,
                    captureEvidenceFrame:
                        actions.captureEvidenceFrame,
                    setMovementCapability:
                        actions.setScanMovementCapability,
                    endScan: actions.beginReview
                )
            } else if state == .idle {
                // #360/#362: capture-first home + series-first
                // library. NavigationSplitView collapses to the push
                // stack on compact width and splits on regular width.
                CaptureHomeView(
                    capabilities: capabilities,
                    cameraPermission: cameraPermission,
                    persistedInventory: persistedInventory,
                    libraryMetadata: libraryMetadata,
                    persistedWorkspace: persistedWorkspace,
                    captureOrigins: captureOrigins,
                    missionRecords: missionRecords,
                    activeMissionRecordID: activeMissionRecordID,
                    pairedDestinations: pairedDestinations,
                    deliveryJobs: deliveryJobs,
                    actions: actions
                )
            } else {
                NavigationStack {
            if state == .setup,
               let captureSetup
            {
                CaptureSetupView(
                    presentation: captureSetup,
                    selectedStrategyID: selectedStrategyID,
                    strategyPinnedByTaskPlan:
                        strategyPinnedByTaskPlan,
                    planUnderlay: planUnderlayDocument,
                    selectCaptureStrategy:
                        actions.selectCaptureStrategy,
                    importPlanReference: {
                        importingPlanReference = true
                    },
                    beginScanning: actions.beginScanning,
                    cancel: actions.cancelCaptureSetup,
                    selectTaskProfile: { profile in
                        actions.selectTaskProfile(profile, [])
                    },
                    importTaskPlan: actions.importTaskPlan,
                    clearTaskPlan: actions.clearTaskPlan,
                    openCameraSettings: actions.openCameraSettings
                )
            } else if state == .annotating,
               let coordinateSpaceID =
                    annotationWorkspaceCoordinateSpaceID,
               let captureRevisionID =
                    workingSetIdentity?.captureRevisionID
            {
                CaptureAnnotationWorkspaceView(
                    coordinateSpaceID: coordinateSpaceID,
                    captureRevisionID: captureRevisionID,
                    commitInFlight: activeOperations.contains(
                        .annotationCommit
                    ),
                    availableEvidenceRefs:
                        annotationEvidenceRefs,
                    evidenceFrames: annotationEvidenceFrames,
                    roomPlanSurfaces:
                        annotationRoomPlanSurfaces,
                    meshAnchors: annotationMeshAnchors,
                    statusMessage: workingSetStatus,
                    seed: annotationRevisionSeed,
                    replacesCommittedAuthority:
                        annotationAuthorityCommitted,
                    spatialCaptureSealed: spatialCaptureSealed,
                    equipmentCatalog: equipmentCatalog,
                    // The same shared AR surface renders inside the
                    // camera capture sheets — no second session
                    // (#214). Under a finalization seal (#276) the
                    // session is torn down: passing nil hides every
                    // raycast/orientation/scan capture affordance in
                    // the workspace and its sheets.
                    cameraPreview:
                        spatialCaptureSealed ? nil : scanningPreview,
                    probePlacementTarget:
                        actions.probePlacementTarget,
                    probeCameraHeading:
                        actions.probeCameraHeading,
                    captureTargetedPlacement:
                        actions.captureTargetedPlacement,
                    captureSpeakerOrientation:
                        actions.captureSpeakerOrientation,
                    capturePointOrientation:
                        actions.capturePointOrientation,
                    captureIdentityPhoto:
                        actions.captureIdentityPhoto,
                    captureFieldEvidencePhoto:
                        actions.captureFieldEvidencePhoto,
                    onCommitFieldAuthority:
                        actions.commitFieldAuthority,
                    roomPlanObjects: annotationRoomPlanObjects,
                    plausibilityContext:
                        annotationPlausibilityContext,
                    equipmentRecents: equipmentRecents,
                    speakerLayoutPlans:
                        spatialCaptureSealed ? [] : speakerLayoutPlans,
                    draftStore: annotationDraftStore,
                    draftRevisionID: annotationDraftRevisionID,
                    onImportEquipmentCatalog:
                        actions.importEquipmentCatalog,
                    equipmentCatalogLibrary: equipmentCatalogLibrary,
                    onSelectEquipmentCatalog:
                        actions.selectEquipmentCatalog,
                    taskPlan: taskPlan,
                    scanEquipmentLabel: {
                        try await actions.scanEquipmentLabel()
                    },
                    onCommit:
                        actions.commitAnnotationAuthority,
                    taskProfile: taskProfile,
                    onSelectTaskProfile:
                        actions.selectTaskProfile,
                    onCancel: actions.cancelAnnotation,
                    onDiscard: {
                        confirmingDiscard = true
                    }
                )
                .navigationTitle(
                    LocalizedStringKey(
                        CaptureJourneyStage.details.pageTitleKey
                    )
                )
            } else {
                List {
                Section {
                    // The loop-aware journey header (#372) replaces
                    // the bare state banner: current stage, truthful
                    // per-stage statuses, mission progress and
                    // technical readiness — all derived, never
                    // persisted.
                    CaptureJourneyHeader(presentation: journey)
                    if let workingSetStatus {
                        Text(workingSetStatus)
                            .font(
                                CaptureDesign.Typography
                                    .secondary
                            )
                            .foregroundStyle(.secondary)
                    }
                }

                if state == .failed,
                   let lastFailure
                {
                    Section {
                        CaptureNotice(
                            status: .blocked,
                            title: LocalizedStringKey(
                                failureReasonText(lastFailure)
                            ),
                            message: LocalizedStringKey(
                                failureRecoveryText(lastFailure)
                            )
                        )
                        .listRowSeparator(.hidden)
                    }
                }

                if let lastFailure {
                    Section("Details") {
                        CaptureTechnicalDetail(
                            "Failure code",
                            value: lastFailure.rawValue
                        )
                        if let cameraPermission {
                            CaptureTechnicalDetail(
                                "Camera permission",
                                value: cameraPermission
                                    .rawValue
                            )
                        }
                        if let identity = workingSetIdentity {
                            CaptureTechnicalDetail(
                                "Series",
                                value: identity
                                    .captureSeriesID
                                    .description
                            )
                            if let parent =
                                identity.parentRevisionID
                            {
                                CaptureTechnicalDetail(
                                    "Revises",
                                    value: parent.description
                                )
                            }
                        }
                    }
                }

                Section("Controls") {
                    controls
                }

                if state == .failed,
                   lastFailure != nil
                {
                    if let failedInspection {
                        failedInspectionSection(
                            failedInspection
                        )
                    }
                }

                evidenceIssuesSection

                if state == .reviewing,
                   let qualityReport
                {
                    Section("Quality") {
                        CaptureStatusContent(
                            "HTDT ingestion",
                            status: qualityReport
                                .readyForHTDTIngestion
                                ? .ready
                                : .incomplete
                        )
                        CaptureStatusContent(
                            "Integrity preflight",
                            status: integrityStatus(
                                qualityReport.integrityStatus
                            )
                        )
                        NavigationLink("Review diagnostics") {
                            CaptureReviewView(
                                quality: qualityReport,
                                advisory: advisoryReport,
                                spatialFindings:
                                    spatialPlausibilityFindings,
                                spatialAuthorityLive:
                                    liveSpatialAuthority,
                                practiceCapture:
                                    practiceCaptureActive,
                                onRemediationAction:
                                    actions.performRemediation
                            )
                        }
                    }
                }

                if (state == .finalized || state == .exported),
                   let validationReport
                {
                    Section {
                        CaptureStatusContent(
                            "Validator",
                            status: validationReport.valid
                                ? .verified
                                : .blocked
                        )
                        if let qualityReport {
                            NavigationLink(
                                "Review finalized capture"
                            ) {
                                CaptureReviewView(
                                    quality: qualityReport,
                                    advisory: advisoryReport,
                                    validation: validationReport,
                                    spatialFindings:
                                        spatialPlausibilityFindings
                                )
                            }
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label(
                                    "Share .htdtcapture",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                        }
                    } header: {
                        Text("Finalized bundle")
                    } footer: {
                        VStack(
                            alignment: .leading,
                            spacing: CaptureDesign.Spacing.micro
                        ) {
                            CaptureTechnicalText(
                                validationReport.bundleDigest
                                    .description
                            )
                            CaptureTechnicalText(
                                validationReport.manifest
                                    .captureSeriesID
                                    .description
                            )
                            if let parent =
                                validationReport.manifest
                                    .parentRevisionID
                            {
                                CaptureTechnicalText(
                                    String(
                                        format: String(
                                            localized: "Revises %@"
                                        ),
                                        parent.description
                                    )
                                )
                            }
                        }
                    }
                }
            }
                .navigationTitle(
                    LocalizedStringKey(
                        journey.currentStage.pageTitleKey
                    )
                )
                .navigationDestination(
                    isPresented: $reviewWorkspaceShown
                ) {
                    if let reviewWorkspace {
                        CaptureReviewWorkspaceView(
                            model: reviewWorkspace,
                            roomFrameOriginPending:
                                roomFrameOriginPending,
                            openingCenterPending:
                                openingCenterPending,
                            removeEvidenceFrame: actions
                                .removeEvidenceFrameForPrivacy,
                            openingReviewCandidates: actions
                                .openingReviewCandidates,
                            commitOpeningReview: actions
                                .commitOpeningReview,
                            captureRoomFrameOrigin: actions
                                .captureRoomFrameOrigin,
                            confirmRoomReferenceFrame: actions
                                .confirmRoomReferenceFrame,
                            resolveRevisitFlag: actions
                                .resolveRevisitFlag,
                            reopenRevisitFlag: actions
                                .reopenRevisitFlag,
                            markTaskPlanItem: actions
                                .markTaskPlanItem,
                            confirmFieldDatumFromRoomFrame:
                                actions
                                    .confirmFieldDatumFromRoomFrame,
                            removeRoomFieldDatum:
                                actions.removeRoomFieldDatum,
                            captureOpeningCenter:
                                actions.captureOpeningCenter,
                            clearOpeningCenter:
                                actions.clearOpeningCenter
                        )
                    } else {
                        ProgressView("Loading workspace…")
                    }
                }
                .confirmationDialog(
                    "Discard capture?",
                    isPresented: $confirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button(
                        "Discard capture",
                        role: .destructive
                    ) {
                        actions.discardActiveCapture()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Stops scanning and permanently removes the working revision. Finalized captures are never touched."
                    )
                }
                .sheet(
                    isPresented: $handoffDestinationsShown
                ) {
                    NavigationStack {
                        List {
                            Section(
                                "Choose a destination. The archive bytes and bundle digest are verified before transfer, and every send records a receipt."
                            ) {
                                ForEach(
                                    handoffDestinations
                                ) { destination in
                                    VStack(
                                        alignment: .leading,
                                        spacing: 4
                                    ) {
                                        Button(destination.name) {
                                            selectHandoffDestination(
                                                destination
                                            )
                                        }
                                        if destination.kind
                                            == .endpoint
                                        {
                                            preflightRow(
                                                for: destination
                                            )
                                        }
                                    }
                                }
                            }
                            if !deliveryJobs.isEmpty {
                                Section("Delivery queue") {
                                    ForEach(
                                        deliveryJobs.filter {
                                            !$0.isTerminal
                                        }
                                    ) { job in
                                        LabeledContent(
                                            job.destination.name,
                                            value: job.state.rawValue
                                                .replacingOccurrences(
                                                    of: "_",
                                                    with: " "
                                                )
                                        )
                                        .font(.caption)
                                    }
                                }
                            }
                            if !handoffReceipts.isEmpty {
                                Section("HTDT receipts") {
                                    ForEach(handoffReceipts) {
                                        receipt in
                                        VStack(
                                            alignment: .leading,
                                            spacing: 2
                                        ) {
                                                            LabeledContent(
                                                receipt.outcome,
                                                value: receipt
                                                    .initiatedAtUTC
                                            )
                                            if let detail =
                                                receipt.detail
                                            {
                                                Text(detail)
                                                    .font(
                                                        .caption2
                                                    )
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .navigationTitle("Send to HTDT")
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(
                    isPresented: $shareArchiveForHandoff,
                    onDismiss: recordShareSheetHandoff
                ) {
                    if let exportURL {
                        HandoffShareSheet(items: [exportURL])
                            .ignoresSafeArea()
                    }
                }
                .sheet(
                    isPresented: comparisonShown
                ) {
                    NavigationStack {
                        List {
                            if let revisionComparison {
                                Section(
                                    "Parent → child"
                                ) {
                                    LabeledContent(
                                        "Parent",
                                        value:
                                            revisionComparison
                                                .parentRevisionID
                                                .description
                                    )
                                    .font(.caption.monospaced())
                                    LabeledContent(
                                        "Child",
                                        value:
                                            revisionComparison
                                                .childRevisionID
                                                .description
                                    )
                                    .font(.caption.monospaced())
                                }
                                ForEach(
                                    revisionComparison.fields,
                                    id: \.field
                                ) { field in
                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        Text(field.field)
                                            .font(
                                                .caption.bold()
                                            )
                                        LabeledContent(
                                            "Was",
                                            value: field
                                                .parent
                                        )
                                        LabeledContent(
                                            "Now",
                                            value: field
                                                .child
                                        )
                                        if field.changed {
                                            Text("Changed")
                                                .font(.caption2)
                                                .foregroundStyle(
                                                    .orange
                                                )
                                        }
                                    }
                                    .font(.caption)
                                }
                            } else {
                                ProgressView("Comparing…")
                            }
                        }
                        .navigationTitle(
                            "Revision comparison"
                        )
                    }
                }
                .confirmationDialog(
                    "Delete local capture?",
                    isPresented: Binding(
                        get: { pendingDeletion != nil },
                        set: { presented in
                            if !presented {
                                pendingDeletion = nil
                            }
                        }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { pending in
                    Button(
                        pending.includesExport
                            ? "Delete capture and export"
                            : "Delete capture",
                        role: .destructive
                    ) {
                        actions.deletePersistedCapture(
                            pending.revisionID
                        )
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text(
                        "This permanently deletes the finalized capture and any export archive stored for it from this device."
                    )
                }
                .fileImporter(
                    isPresented: $importingCaptureArchive,
                    allowedContentTypes: [.htdtCapture],
                    allowsMultipleSelection: false
                ) { result in
                    guard let urls = try? result.get(),
                          let url = urls.first
                    else {
                        return
                    }
                    actions.importCaptureArchive(url)
                }
            }
                }
            }
        }
        .fileImporter(
            isPresented: $importingPlanReference,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard let urls = try? result.get(),
                  let url = urls.first
            else {
                return
            }
            actions.importPlanReference(url)
        }
        .sheet(
            isPresented: Binding(
                get: { semanticCorrectionContext != nil },
                set: { presented in
                    if !presented {
                        actions.cancelSemanticCorrection()
                    }
                }
            )
        ) {
            if let context = semanticCorrectionContext {
                SemanticCorrectionSheet(
                    context: context,
                    commit: actions.commitSemanticCorrection,
                    cancel: actions.cancelSemanticCorrection
                )
            }
        }
    }

    /// True while any long-running host operation is in flight
    /// (#309): controls whose coordinator guard would silently no-op
    /// are rendered disabled with the in-flight progress instead.
    private var hostBusy: Bool {
        !activeOperations.isEmpty
    }

    /// The loop-aware capture journey (#372): which stage the operator
    /// is in, each stage's truthful status, the one dominant action,
    /// and mission/readiness summaries — derived here, never
    /// persisted. An adopted persisted capture (`workingSetIdentity
    /// == nil`) has no earlier-stage lineage in this session, so the
    /// trail marks them unavailable instead of faking checks.
    private var journey: CaptureJourneyPresentation {
        CaptureJourneyPresentation.resolve(
            CaptureJourneyInputs(
                state: state,
                lastFailure: lastFailure,
                hasQualityReport: qualityReport != nil,
                qualityReadyForIngestion:
                    qualityReport?.readyForHTDTIngestion ?? false,
                integrityPass:
                    qualityReport?.integrityStatus == .pass,
                integrityFail:
                    qualityReport?.integrityStatus == .fail,
                hasSpatialAuthority:
                    annotationCoordinateSpaceID != nil
                        && liveSpatialAuthority,
                detailsCommitted: annotationAuthorityCommitted,
                spatialCaptureSealed: spatialCaptureSealed,
                hasValidationReport: validationReport != nil,
                hasExportArchive: exportURL != nil,
                isImportedFinalized: workingSetIdentity == nil,
                mission: taskPlanMission,
                cameraPermissionDenied:
                    cameraPermission == .denied
            )
        )
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .idle:
            Button("Start capture", action: actions.beginCapture)
                .disabled(!capabilities.roomPlanMeshEligible)

            // #320 practice mode: a guided rehearsal of the real
            // scan → End → Review flow that can never produce a
            // finalized bundle. Always reachable from here; the
            // first-launch prompt is dismissible forever.
            if practicePromptShown {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New here? Try a practice capture first.")
                        .font(.headline)
                    Text(
                        "Practice mode walks through scanning, End, and Review exactly like a real capture, but nothing is finalized or sent to HTDT. The data stays on this device marked as practice."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(
                        "Start practice capture",
                        action: actions.beginPracticeCapture
                    )
                    .disabled(!capabilities.roomPlanMeshEligible)
                    Button("Not now") {
                        actions.dismissPracticePrompt(false)
                    }
                    Button("Don't show again") {
                        actions.dismissPracticePrompt(true)
                    }
                    .font(.caption)
                }
            } else {
                Button(
                    "Practice a capture (no real bundle)",
                    action: actions.beginPracticeCapture
                )
                .disabled(!capabilities.roomPlanMeshEligible)
            }

        case .setup:
            EmptyView()
                .disabled(
                    !capabilities.roomPlanMeshEligible || hostBusy
                )
            ForEach(
                Array(activeOperations),
                id: \.self
            ) { operation in
                progressRow(operationLabel(operation))
            }
            Button("Import .htdtcapture") {
                importingCaptureArchive = true
            }
            .disabled(hostBusy)

        case .setup:
            EmptyView()
            if hostBusy {
                ForEach(
                    Array(activeOperations),
                    id: \.self
                ) { operation in
                    progressRow(operationLabel(operation))
                }
            }
            Button("Import .htdtcapture") {
                importingCaptureArchive = true
            }
            .disabled(hostBusy)

        case .capabilityCheck:
            progressRow("Checking device capabilities…")
            Button(
                "Cancel",
                role: .cancel,
                action: actions.cancelCaptureStart
            )

        case .permissions:
            permissionRecoveryControls

        case .preparing:
            progressRow("Preparing capture working set…")

        case .scanning:
            if practiceCaptureActive {
                Text(
                    "Practice mode — this capture is never finalized or sent to HTDT."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(
                "Capture evidence frame",
                action: actions.captureEvidenceFrame
            )
            Button("End scan and review", action: actions.beginReview)
            discardButton

        case .paused:
            Text(
                "The host app does not enter a pseudo-paused RoomPlan state. Ending RoomPlan creates a scan boundary."
            )
            discardButton

        case .reviewing:
            // #297: a draft recovered after relaunch has no live AR
            // coordinate authority — Continue scanning and evidence
            // capture must never appear; semantic review/authoring and
            // finalization still work.
            if !liveSpatialAuthority {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovered draft")
                        .font(.headline)
                    Text(
                        "This capture was reopened after the app relaunched. Spatial evidence is sealed — you can review, author annotations and measurements, or finalize. You cannot resume scanning; start a new capture to add spatial evidence."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let report = recoveredDraftReport {
                        if !report.unsupportedPaths.isEmpty {
                            Text(
                                String(
                                    format: String(
                                        localized: "%d file(s) kept but unsupported by this app version."
                                    ),
                                    report.unsupportedPaths.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !report.supersededPaths.isEmpty {
                            Text(
                                String(
                                    format: String(
                                        localized: "%d stale analysis file(s) will be recomputed."
                                    ),
                                    report.supersededPaths.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if practiceCaptureActive {
                Text(
                    "Practice mode — a rehearsal only; nothing here can be finalized or sent to HTDT."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // One dominant action per stage (#372): a blocking
            // integrity problem → Review diagnostics; required
            // mission tasks outstanding → Complete required tasks;
            // coverage unknown → Continue scanning; otherwise →
            // Validate and finalize.
            switch journey.primaryAction {
            case .reviewDiagnostics:
                if let qualityReport {
                    NavigationLink("Review diagnostics") {
                        CaptureReviewView(
                            quality: qualityReport,
                            advisory: advisoryReport,
                            spatialFindings:
                                spatialPlausibilityFindings
                        )
                    }
                    .capturePrimaryAction()
                }
            case .completeRequiredTasks:
                Button(
                    "Complete required tasks",
                    action: actions.beginAnnotation
                )
                .capturePrimaryAction()
                .disabled(hostBusy)
            case .continueScanning:
                Button(
                    "Continue scanning",
                    action: actions.continueScanning
                )
                .capturePrimaryAction()
                .disabled(hostBusy)
            case .validateAndFinalize:
                if practiceCaptureActive {
                    Text(
                        "Practice captures are never finalized; use Discard to end practice."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button(
                        "Validate and finalize",
                        action: actions.finalizeCapture
                    )
                    .capturePrimaryAction()
                    .disabled(
                        !(qualityReport?.readyForHTDTIngestion ?? false)
                        || qualityReport?.integrityStatus != .pass
                        || hostBusy
                    )
                    // #298: the disabled gate names its blocking
                    // reasons inline instead of leaving the operator
                    // to hunt through the diagnostics section.
                    let blockers = (qualityReport?.diagnostics ?? [])
                        .filter { $0.severity == .error }
                    if !blockers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                "Blocked by quality diagnostics:"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ForEach(
                                Array(blockers.enumerated()),
                                id: \.offset
                            ) { _, diagnostic in
                                Button {
                                    actions.performRemediation(
                                        QualityRemediationCatalog
                                            .remediation(
                                                for: diagnostic
                                            ).actions.first
                                            ?? .discardDraft
                                    )
                                } label: {
                                    Text(diagnostic.code)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                Button(
                    "Validate and finalize",
                    action: actions.finalizeCapture
                )
                .capturePrimaryAction()
                .disabled(
                    !(qualityReport?.readyForHTDTIngestion ?? false)
                    || qualityReport?.integrityStatus != .pass
                    || hostBusy
                )
            case .openReviewWorkspace:
                reviewWorkspaceButton()
                    .capturePrimaryAction()
            default:
                EmptyView()
            }
            if let blocked = journey.primaryActionBlockedKey {
                Text(LocalizedStringKey(blocked))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if annotationAuthorityCommitted {
                Text("Details saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(journey.secondaryActions, id: \.self) { id in
                journeyActionRow(id)
            }
            if qualityReport == nil {
                progressRow("Waiting for persisted evidence…")
            }
            if activeOperations.contains(.reviewOperation) {
                progressRow("Finalizing capture…")
            }
            // #297 "Save and finish later": the end-accepted draft is
            // durable; leaving Review keeps it listed as a recoverable
            // draft on the home surface and next launch.
            if workingSetIdentity != nil {
                Button(
                    "Save and finish later",
                    action: actions.suspendReview
                )
            }

            // Discarding the working revision is always legal while
            // unfinalized — kept last and visually separated.
            discardButton
                .disabled(hostBusy)

        case .failed:
            Button(
                "Inspect retained evidence",
                action: actions.inspectFailedCapture
            )
            .capturePrimaryAction()
            .disabled(hostBusy)
            if activeOperations.contains(.exportDiagnostics) {
                progressRow("Preparing diagnostic package…")
            }
            Button("Export diagnostic package") {
                Task {
                    diagnosticShareURL =
                        await actions
                            .exportFailedCaptureDiagnostics()
                }
            }
            .captureSecondaryAction()
            .disabled(hostBusy)
            if let diagnosticShareURL {
                ShareLink(item: diagnosticShareURL) {
                    Label(
                        "Share diagnostic package",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
            Button("Start new capture") {
                confirmingDiscard = true
            }
            .captureSecondaryAction()
            .disabled(hostBusy)
            Button(
                "Discard failed capture",
                role: .destructive,
                action: actions.resetCapture
            )
            .disabled(hostBusy)

        case .annotating:
            EmptyView()

        case .validating:
            progressRow("Validating and finalizing capture…")

        case .finalized:
            // The export always packages every retained pixel
            // payload; the operator confirms visual evidence is
            // included before preparing it (issue #241). One
            // dominant action per stage (#372).
            Button("Prepare .htdtcapture") {
                confirmingExport = true
            }
            .capturePrimaryAction()
            .disabled(hostBusy)
            .confirmationDialog(
                "Export includes visual evidence?",
                isPresented: $confirmingExport,
                titleVisibility: .visible
            ) {
                Button("Prepare .htdtcapture") {
                    actions.prepareExport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The archive packages \(retainedVisualEvidenceCount) retained camera frame pixel payload(s) with the capture. Open Visual evidence review first if you need to remove unreferenced frames for privacy."
                )
            }
            if activeOperations.contains(.prepareExport) {
                progressRow("Preparing archive…")
            }
            revisionControls
            if let revisionID =
                validationReport?.manifest.captureRevisionID
            {
                Button(
                    "Delete local capture",
                    role: .destructive
                ) {
                    pendingDeletion = PendingCaptureDeletion(
                        revisionID: revisionID,
                        includesExport: exportURL != nil
                    )
                }
                .disabled(hostBusy)
            }

        case .exported:
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Validated .htdtcapture archive is ready to send to HTDT. Nothing uploads automatically."
                )
                Button("Send to HTDT…") {
                    handoffDestinationsShown = true
                }
                .capturePrimaryAction()
                .disabled(hostBusy)
                Button("Share .htdtcapture") {
                    shareArchiveForHandoff = true
                }
                .captureSecondaryAction()
                .disabled(hostBusy)
            }
            revisionControls
            if let revisionID =
                validationReport?.manifest.captureRevisionID
            {
                Button(
                    "Delete local capture and export",
                    role: .destructive
                ) {
                    pendingDeletion = PendingCaptureDeletion(
                        revisionID: revisionID,
                        includesExport: exportURL != nil
                    )
                }
                .disabled(hostBusy)
            }
        }
    }

    /// The `.permissions` state is a prerequisite/recovery surface
    /// (#295), never a failed capture: a denied operator gets a direct
    /// path to iOS Settings and an in-place retry, a restricted device
    /// gets a distinct explanation, and either path can always cancel
    /// back to idle without fabricating a working revision.
    @ViewBuilder
    private var permissionRecoveryControls: some View {
        switch cameraPermission {
        case .denied:
            Text(
                "Camera access is off. HTDT Capture needs the camera to record RoomPlan and AR evidence — nothing is captured until you allow it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Button(
                "Open Settings",
                action: actions.openCameraSettings
            )
            .capturePrimaryAction()
            Button(
                "Check again",
                action: actions.retryCameraPermission
            )
            .captureSecondaryAction()
            Button(
                "Cancel",
                role: .cancel,
                action: actions.cancelCaptureStart
            )
        case .restricted:
            Text(
                "Camera access is restricted on this device — for example by Screen Time or a device-management profile — so it cannot be enabled in Settings. Contact the device administrator."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Button(
                "Check again",
                action: actions.retryCameraPermission
            )
            Button(
                "Cancel",
                role: .cancel,
                action: actions.cancelCaptureStart
            )
        case .unavailable:
            Text(
                "The camera is unavailable on this device, so capture cannot start."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Button(
                "Cancel",
                role: .cancel,
                action: actions.cancelCaptureStart
            )
        case .notDetermined, .authorized, nil:
            progressRow("Requesting camera permission…")
            Button(
                "Cancel",
                role: .cancel,
                action: actions.cancelCaptureStart
            )
        }
    }

    private func operationLabel(
        _ operation: CaptureHostOperation
    ) -> LocalizedStringKey {
        switch operation {
        case .importArchive:
            return "Importing capture…"
        case .openPersisted:
            return "Opening capture…"
        case .deletePersisted:
            return "Deleting local capture…"
        case .prepareExport:
            return "Preparing archive…"
        case .reviewOperation:
            return "Finalizing capture…"
        case .annotationCommit:
            return "Saving annotation authority…"
        case .exportDiagnostics:
            return "Preparing diagnostic package…"
        }
    }

    /// Shared post-capture controls (#221): rescan-as-revision with the
    /// fresh-authority explainer, and the parent/child comparison.
    @ViewBuilder
    private var revisionControls: some View {
        Button(
            "Start new capture",
            action: actions.resetCapture
        )
        .disabled(hostBusy)
        if validationReport?.manifest.parentRevisionID != nil {
            Button("Compare with revised capture") {
                comparisonLoading = true
                Task {
                    revisionComparison =
                        await actions
                            .compareAdoptedRevisionWithParent()
                    comparisonLoading = false
                }
            }
            .disabled(comparisonLoading || hostBusy)
        }
        Button(
            "Rescan as new revision",
            action: actions.reviseAdoptedCapture
        )
        .disabled(hostBusy)
        Text(
            "Rescan starts a fresh scan with its own coordinate space. The revised capture stays finalized and unchanged."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var discardButton: some View {
        Button("Discard capture", role: .destructive) {
            confirmingDiscard = true
        }
    }

    private func reviewWorkspaceButton() -> some View {
        Button("Open review workspace") {
            actions.refreshReviewWorkspace()
            reviewWorkspaceShown = true
        }
        .disabled(hostBusy)
    }

    /// A journey-declared secondary action (#372): the presentation
    /// orders the row set; the view binds each stable id to its host
    /// callback and keeps destructive actions visually separated.
    @ViewBuilder
    private func journeyActionRow(
        _ id: CaptureJourneyAction
    ) -> some View {
        switch id {
        case .openReviewWorkspace:
            reviewWorkspaceButton()
                .captureSecondaryAction()
        case .continueScanning:
            // Saved annotations/measurements survive a reopen while
            // the same coordinate authority is still valid (#236).
            Button(
                "Continue scanning",
                action: actions.continueScanning
            )
            .captureSecondaryAction()
            .disabled(hostBusy)
        case .addDetails:
            Button(
                "Add details",
                action: actions.beginAnnotation
            )
            .captureSecondaryAction()
            .disabled(hostBusy)
        case .editSavedDetails:
            Button(
                spatialCaptureSealed
                    ? "Edit labels, roles, equipment, and values"
                    : "Edit saved annotations & measurements",
                action: actions.beginAnnotation
            )
            .captureSecondaryAction()
            .disabled(hostBusy)
        case .completeRequiredTasks:
            Button(
                "Complete required tasks",
                action: actions.beginAnnotation
            )
            .captureSecondaryAction()
            .disabled(hostBusy)
        case .discardCapture:
            discardButton
                .disabled(hostBusy)
        default:
            EmptyView()
        }
    }

    private func progressRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }

    /// Failed-capture retained-evidence detail (#224), extracted from
    /// the List body so the type-checker stays inside its budget.
    @ViewBuilder
    private func failedInspectionSection(
        _ inspection: FailedCaptureInspection
    ) -> some View {
        Section("Retained evidence") {
            LabeledContent(
                "Working set files",
                value: String(inspection.entries.count)
            )
            LabeledContent(
                "Retained bytes",
                value: String(inspection.totalByteCount)
            )
            ForEach(
                inspection.entries,
                id: \.relativePath
            ) { file in
                LabeledContent(
                    file.relativePath,
                    value: String(file.byteCount)
                )
                .font(.caption2.monospaced())
            }
            Text(
                "The diagnostic package is a non-canonical report only — it never mutates the retained working set."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Dangling-evidence section, extracted from the List body so the
    /// type-checker stays inside its budget.
    @ViewBuilder
    private var evidenceIssuesSection: some View {
        if state == .reviewing
            || state == .annotating,
            !danglingSpatialIssues.isEmpty
        {
            Section("Evidence issues") {
                ForEach(
                    danglingSpatialIssues,
                    id: \.ref
                ) { issue in
                    danglingIssueRow(issue)
                }
                Text(
                    "Committed annotations or measurements reference evidence that is no longer in the working set. Reopen the annotation authority to repair or remove them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Row extracted from the List body so the type-checker stays
    /// inside its budget.
    private func danglingIssueRow(
        _ issue: SpatialEvidenceIssue
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issue.owner).font(.caption.bold())
            Text(issue.ref).font(.caption2.monospaced())
            Text(issue.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Routes a chosen Send-to-HTDT destination: share-sheet
    /// destinations present the system sheet (receipt recorded on
    /// dismissal); endpoint destinations POST through the client
    /// (#225).
    private func selectHandoffDestination(
        _ destination: HTDTHandoffDestination
    ) {
        handoffDestinationsShown = false
        if destination.kind == .shareSheet {
            shareArchiveForHandoff = true
        } else {
            Task {
                await actions.sendCaptureToHTDT(destination)
            }
        }
    }

    /// Endpoint capability preflight row (#374): an explicit "check
    /// compatibility" action per endpoint destination, then the
    /// verdict rendered as the exact gap list — never a bare pass.
    @ViewBuilder
    private func preflightRow(
        for destination: HTDTHandoffDestination
    ) -> some View {
        if let verdict = preflightVerdicts[destination.id] {
            switch verdict {
            case .compatible:
                Label(
                    "Compatible",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.green)
            case .compatibleWithOmissions(let gaps):
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "Compatible with omissions",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    ForEach(
                        Array(gaps.enumerated()),
                        id: \.offset
                    ) { _, gap in
                        Text(gap.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .incompatible(let gaps):
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "Incompatible",
                        systemImage: "xmark.octagon"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    ForEach(
                        Array(gaps.enumerated()),
                        id: \.offset
                    ) { _, gap in
                        Text(gap.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .unknown(let reason):
                Label(reason, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if preflightInFlight.contains(destination.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Check compatibility") {
                preflightInFlight.insert(destination.id)
                Task {
                    let verdict = await actions
                        .preflightDestination(destination)
                    preflightInFlight.remove(destination.id)
                    preflightVerdicts[destination.id] = verdict
                }
            }
            .font(.caption)
        }
    }

    /// The system share completion IS the share-sheet handoff; the
    /// receipt records it durably (#225).
    private func recordShareSheetHandoff() {
        guard let destination = handoffDestinations.first(
            where: { $0.kind == .shareSheet }
        ) else {
            return
        }
        Task {
            await actions.sendCaptureToHTDT(destination)
        }
    }

    /// Sheet-binding plumbing for the comparison overlay: a bool is
    /// enough because `revisionComparison` holds the payload.
    private var comparisonShown: Binding<Bool> {
        Binding(
            get: {
                revisionComparison != nil || comparisonLoading
            },
            set: { shown in
                if !shown { revisionComparison = nil }
            }
        )
    }

    private func localizedState(_ state: CaptureState) -> String {
        switch state {
        case .idle:
            return String(localized: "Idle")
        case .setup:
            return String(localized: "Capture setup")
        case .capabilityCheck:
            return String(localized: "Checking capabilities")
        case .permissions:
            return String(localized: "Requesting permissions")
        case .preparing:
            return String(localized: "Preparing")
        case .scanning:
            return String(localized: "Scanning")
        case .paused:
            return String(localized: "Paused")
        case .reviewing:
            return String(localized: "Reviewing")
        case .annotating:
            return String(localized: "Annotating")
        case .validating:
            return String(localized: "Validating")
        case .finalized:
            return String(localized: "Finalized")
        case .exported:
            return String(localized: "Exported")
        case .failed:
            return String(localized: "Failed")
        }
    }

    /// Maps the capture state onto the frozen status vocabulary
    /// (#361/#364): every screen reports state through the same
    /// symbol+label.
    private func captureStateStatus(
        _ state: CaptureState
    ) -> CaptureSemanticStatus {
        switch state {
        case .idle, .setup, .capabilityCheck, .permissions,
             .preparing:
            return .pending
        case .scanning, .annotating:
            return .pending
        case .paused:
            return .pending
        case .reviewing:
            return .needsReview
        case .validating:
            return .pending
        case .finalized:
            return .finalized
        case .exported:
            return .verified
        case .failed:
            return .blocked
        }
    }

    private func integrityStatus(
        _ status: BundleIntegrityStatus
    ) -> CaptureSemanticStatus {
        switch status {
        case .notChecked:
            return .pending
        case .pass:
            return .verified
        case .fail:
            return .blocked
        }
    }

    private func failureReasonText(
        _ failure: CaptureFailureCode
    ) -> String {
        switch failure {
        case .interrupted:
            return String(
                localized:
                    "The app left the foreground during an active capture. HTDT no longer assumes the same AR coordinate space is valid."
            )
        case .trackingUnavailable:
            return String(
                localized:
                    "AR tracking or the current camera frame became unavailable during capture."
            )
        case .roomPlanFailure:
            return String(
                localized:
                    "RoomPlan could not start or continue the room scan reliably."
            )
        case .storagePressure:
            return String(
                localized:
                    "Available storage fell below the safe capture threshold."
            )
        case .thermalPressure:
            return String(
                localized:
                    "The device reached a critical thermal state during capture."
            )
        case .persistenceFailure:
            return String(
                localized:
                    "Required capture evidence could not be written safely."
            )
        case .permissionDenied:
            return String(
                localized:
                    "Camera access is required to capture RoomPlan and AR evidence."
            )
        case .unsupportedDevice:
            return String(
                localized:
                    "This device does not provide the required RoomPlan and mesh capture capabilities."
            )
        case .unknown:
            return String(
                localized:
                    "The capture stopped because of an unexpected error."
            )
        }
    }

    private func failureRecoveryText(
        _ failure: CaptureFailureCode
    ) -> String {
        switch failure {
        case .interrupted:
            return String(
                localized:
                    "This scan is not silently resumed. Discard the failed capture and start a new scan so a fresh coordinate-space authority is created."
            )
        case .trackingUnavailable:
            return String(
                localized:
                    "Move to a well-lit area with visible room features, then discard this failed capture and start a new scan."
            )
        case .roomPlanFailure:
            return String(
                localized:
                    "Discard this failed capture and start again. Move slowly and keep walls, corners, and furniture edges in view."
            )
        case .storagePressure:
            return String(
                localized:
                    "Free device storage before starting another capture."
            )
        case .thermalPressure:
            return String(
                localized:
                    "Let the device cool before starting another capture."
            )
        case .persistenceFailure:
            return String(
                localized:
                    "A canonical evidence or authority conflict prevented safe continuation. Check the work-data diagnostic; if recovery is not offered, discard this capture and retry."
            )
        case .permissionDenied:
            return String(
                localized:
                    "Allow camera access in iOS Settings, then start a new capture."
            )
        case .unsupportedDevice:
            return String(
                localized:
                    "Use a supported LiDAR-capable iPhone or iPad for this capture workflow."
            )
        case .unknown:
            return String(
                localized:
                    "Discard the failed capture and retry. If the error repeats, record the screen state before resetting."
            )
        }
    }

}
