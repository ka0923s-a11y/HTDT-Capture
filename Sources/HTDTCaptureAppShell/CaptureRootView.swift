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
    /// #269: operator seed/refine gesture over the preview — points are
    /// view-normalized; the coordinator maps them through the recorded
    /// display-transform authority.
    public let segmentationGesture:
        (SegmentationGesture) -> Void
    /// #269: fuse + persist the accepted mask ("Use").
    public let useSegmentation: () -> Void
    /// #269: drop the live run ("Cancel" / "New selection").
    public let cancelSegmentation: () -> Void
    /// #269: explicit operator asset-prep request — the only mid-scan
    /// path allowed to reach `downloadAssets()`.
    public let segmentationAssetPrepare: () -> Void
    /// #257 declared-region actions.
    public let declareNearestUnresolvedRegion:
        (DeclaredRegionReason) -> Void
    public let revokeOperatorRegion:
        (SpatialCoverageCellKey) -> Void
    /// #252 non-visual cue switch.
    public let setGuidanceCuesEnabled: (Bool) -> Void
    /// #273 return-to-start check arm/disarm.
    public let setLoopClosureCheckActive: (Bool) -> Void
    /// Operator response to the armed loop-closure check (#273).
    public let recordLoopClosureOutcome: (String) -> Void
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
    /// #364 §10: the optional third argument is the collected
    /// reason, persisted as a mission-level waiver note (#397) when
    /// the marked plan maps to a mission record.
    public let markTaskPlanItem:
        (String, TaskPlanItemOutcome, String?) -> Void
    /// Whether a mission-inbox record exists for the given plan —
    /// the waiver note is the only audited reason channel, so the
    /// checklist's "with reason" items are gated on this (#364 §10).
    public let canRecordTaskPlanMarkReason:
        (HTDTCaptureTaskPlan) -> Bool
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
    /// Re-runs independent validation on a committed-but-unverified
    /// finalized revision — the manual recovery path when automatic
    /// post-promotion validation could not prove the bundle.
    public let revalidateAdoptedRevision: () -> Void
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
    /// #437 "Reopen the draft and finish" on the failed surface:
    /// preserves the failed end-accepted working set as a recoverable
    /// draft and reopens it into sealed Review.
    public let resumeFailedAsDraft: () -> Void
    /// #437 "Keep the draft for later" on the failed surface:
    /// preserves the working set as a recoverable draft without
    /// reopening it.
    public let keepFailedAsDraft: () -> Void
    /// #437 "Discard and start a new capture" on the failed surface:
    /// permanently removes the failed capture's retained data, then
    /// opens capture setup.
    public let discardFailedAndStartNew: () -> Void
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
    /// #232: commits a field datum declared from bounded
    /// evidence operands (entity/measurement/frame/stated).
    public let commitFieldDatum:
        (RoomFieldDatumAuthoringRequest) async -> Bool
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
    /// Loads a persisted capture into the read-only viewer (#294) —
    /// `true` only when the load actually started.
    public let loadPersistedWorkspace:
        (PersistedCaptureRecord) -> Bool
    /// Field-level parent/child comparison for a revised capture
    /// (#221).
    public let compareAdoptedRevisionWithParent:
        () async -> CaptureRevisionComparison?
    /// Failed-capture inspection + diagnostic package (#224).
    public let inspectFailedCapture: () -> Void
    public let exportFailedCaptureDiagnostics:
        () async -> URL?
    /// Mission workflows (#353) + closed-loop repair (#321).
    public let importMissionDocument: (URL) -> Void
    public let setConnectedSpaceIntent: (Bool) -> Void
    public let beginConnectedSegment:
        (String, CaptureRegionKind) -> Void
    public let completeConnectedSegment: () -> Void
    public let recordConnectedPortal: (CaptureRegionID, CapturePortalKind) -> Void
    public let revisitConnectedRegion: (CaptureRegionID) -> Void
    public let asBuiltMarkUnavailable: (String) -> Void
    public let asBuiltEstablishAlignment: () -> Void
    public let asBuiltRecordActual:
        (String, AnnotationEntityID) -> Void
    public let resolveRepairTask: (HTDTRepairTaskRow) -> Void
    /// Explicit Send-to-HTDT handoff (#225). For share-sheet
    /// destinations `shareSheetOutcome` carries the system sheet's
    /// real completion so the receipt can never claim a delivery the
    /// operator did not make; nil for endpoint sends.
    public let sendCaptureToHTDT:
        (HTDTHandoffDestination, HTDTShareSheetOutcome?)
            async -> Void
    /// Mission inbox (#386): import a mission package file, start or
    /// resume a record, deactivate the active mission, archive a
    /// record, and evaluate a record's dependency report for display
    /// before Start.
    public let importMissionPackage: (URL) async -> Void
    public let startMission: (String) async -> Void
    public let deactivateMission: () async -> Void
    public let archiveMission: (String) async -> Void
    /// Closes a mission whose field work or delivery landed (#456).
    public let completeMission: (String) async -> Void
    /// Persists the operator's mission annotation (#463).
    public let updateMissionUserNote:
        (String, String?) async -> Void
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
    /// #393: the shared inbound-document boundary — identifies the
    /// file, gates it by capture state, and hands it to the owning
    /// importer.
    public let importInboundDocument: (URL) -> Void
    /// #378: commits or dismisses the staged library-package import
    /// preview shown on the home surface.
    public let confirmLibraryImport: () -> Void
    public let dismissLibraryImport: () -> Void
    /// #378: writes a `.htdtcapturelibrary` package of every
    /// persisted capture plus filtered metadata and receipts.
    public let exportLibraryPackage: () -> Void
    /// #394: archives or restores a series — lifecycle state only;
    /// canonical bundles are untouched.
    public let setSeriesArchived:
        (CaptureSeriesID, Bool) -> Void
    /// #394: sets a revision's importance marks (milestone,
    /// keep-local, favorite, pinned).
    public let updateRevisionMark:
        (CaptureRevisionID, CaptureRevisionMark) -> Void
    /// #394: dependency-aware whole-series delete; `Bool` is the
    /// explicit protected-marks override.
    public let deleteSeries:
        (CaptureSeriesID, Bool) -> Void
    /// Derived export support (#306/#318): availability probe plus the
    /// two export actions. All take the finalized capture's revision
    /// id — the host resolves the finalized directory itself.
    public let derivedExportInfo:
        (CaptureRevisionID) async -> DerivedExportInfo?
    public let exportDerived3D:
        (CaptureRevisionID, Derived3DExportSelection)
            async -> DerivedExportOutcome
    public let exportSurveyReport:
        (CaptureRevisionID, SurveyReportSelection)
            async -> DerivedExportOutcome
    /// Persists a new app-local settings document (#338). The host
    /// owns the store and applies side effects (backup policy,
    /// guidance cues).
    public let updateAppSettings: (CaptureAppSettings) -> Void
    /// Clears the durable equipment-catalog cache (#338).
    public let clearEquipmentCatalogCache: () -> Void
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
    /// Revision lineage (#396): operator-picked preferred head for a
    /// branched series — app-local metadata only, bundles never
    /// change; nil revision clears the pick.
    public let preferRevisionHead:
        (CaptureSeriesID, CaptureRevisionID?) -> Void
    /// Cross-revision spatial registration (#395): the preview stage
    /// — gathers shared-field-datum correspondences between the two
    /// finalized revisions and returns the proposed transform with
    /// per-correspondence residuals/RMS for inspection. Nil when the
    /// pair cannot be registered (missing datum, degenerate
    /// correspondences).
    public let proposeRevisionAlignment:
        (CaptureRevisionID, CaptureRevisionID) async
            -> CrossRevisionRegistrationSolve?
    /// Cross-revision spatial registration (#395): accept — immutably
    /// records the alignment the operator previewed; returns the
    /// accepted record, nil on refusal (conflicting registration or
    /// solve failure).
    public let acceptRevisionAlignment:
        (CaptureRevisionID, CaptureRevisionID) async
            -> CrossRevisionRegistration?
    /// Mission progress ledger (#397): records an explicit,
    /// auditable mission-level waiver for a plan item — recordID,
    /// itemID, optional operator note.
    public let waiveMissionItem:
        (String, String, String?) async -> Void
    /// #375 operator field notes: record a note mid-scan or in Review
    /// (text, category, needsAttention, attachLatestEvidence,
    /// dictated), resolve one, supersede one with corrected text, or
    /// bind an unbound note to an authority/evidence ref.
    public let recordFieldNote:
        (String, CaptureFieldNoteCategory, Bool, Bool, Bool,
         CaptureFieldNoteAnchorRequest) -> Void
    public let recordReviewFieldNote:
        (String, CaptureFieldNoteCategory, Bool, [String]) -> Void
    public let resolveFieldNote: (CaptureFieldNoteID) -> Void
    public let supersedeFieldNote:
        (CaptureFieldNoteID, String, CaptureFieldNoteCategory) -> Void
    public let bindFieldNote:
        (CaptureFieldNoteID, String) -> Void
    /// #376: marks an evidence frame privacy-sensitive in the contact
    /// sheet (advisory flag — never deletes or mutates pixels).
    public let flagEvidenceFrameForPrivacy:
        (EvidenceFrameID) -> Void
    /// #460: clears a frame's privacy flag — the paired revocation of
    /// `flagEvidenceFrameForPrivacy`.
    public let unflagEvidenceFrameForPrivacy:
        (EvidenceFrameID) -> Void
    /// #389 Support & Diagnostics: collect a privacy-reviewed
    /// diagnostic package independent of any capture bundle.
    public let collectSupportDiagnostics:
        () async throws -> SupportDiagnosticsPackage
    /// #458: app-local operator roster mutations — the workspace
    /// remembers each saved Author profile app-wide and lets the
    /// operator forget one; committed captures keep their own copy.
    public let updateOperatorRoster: (OperatorProfile) -> Void
    public let removeFromOperatorRoster: (OperatorProfileID) -> Void
    /// #400 non-spatial field mission returns: open (or resume) the
    /// field-return workspace for a mission record, persist a draft
    /// edit, finalize it into a `.htdtfieldreturn` artifact, and list
    /// finalized field-return documents for mission history.
    public let openFieldReturnWorkspace:
        (String) async -> HTDTFieldReturnWorkspace?
    public let persistFieldReturnDraft:
        (HTDTFieldReturnWorkspace) async -> Void
    public let finalizeFieldReturn:
        (HTDTFieldReturnWorkspace) async -> URL?
    public let listFieldReturns:
        () async -> [HTDTFieldReturnDocument]
    /// #422 paired Mission receive leg: bounded pull refresh
    /// ("Check HTDT") — enumerates each active paired receiver's
    /// pairing-scoped pending-Mission listing and stages verified
    /// packages through the canonical Mission Inbox importer.
    public let checkHTDTForMissions:
        () async -> [HTDTMissionReceiveReport]
    /// #423 artifact-aware delivery: capability preflight and
    /// durable-queue send for a finalized `.htdtfieldreturn`.
    public let preflightFieldReturn:
        (HTDTFieldReturnID, HTDTHandoffDestination) async
            -> HTDTCompatibilityVerdict
    public let sendFieldReturnToHTDT:
        (HTDTFieldReturnID, HTDTHandoffDestination) async -> Void
    /// #423: the finalized `.htdtfieldreturn` container's URL for
    /// the share sheet — nil when no finalized artifact exists.
    public let fieldReturnArtifactURL:
        (HTDTFieldReturnID) -> URL?

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
        segmentationGesture: @escaping
            (SegmentationGesture) -> Void = { _ in },
        useSegmentation: @escaping () -> Void = {},
        cancelSegmentation: @escaping () -> Void = {},
        segmentationAssetPrepare: @escaping () -> Void = {},
        declareNearestUnresolvedRegion: @escaping
            (DeclaredRegionReason) -> Void = { _ in },
        revokeOperatorRegion: @escaping
            (SpatialCoverageCellKey) -> Void = { _ in },
        setGuidanceCuesEnabled: @escaping
            (Bool) -> Void = { _ in },
        setLoopClosureCheckActive: @escaping
            (Bool) -> Void = { _ in },
        recordLoopClosureOutcome: @escaping
            (String) -> Void = { _ in },
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
            (String, TaskPlanItemOutcome, String?) -> Void =
                { _, _, _ in },
        canRecordTaskPlanMarkReason: @escaping
            (HTDTCaptureTaskPlan) -> Bool = { _ in false },
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
        revalidateAdoptedRevision: @escaping () -> Void = {},
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
        resumeFailedAsDraft: @escaping () -> Void = {},
        keepFailedAsDraft: @escaping () -> Void = {},
        discardFailedAndStartNew: @escaping () -> Void = {},
        refreshReviewWorkspace: @escaping () -> Void = {},
        captureRoomFrameOrigin: @escaping () -> Void = {},
        confirmRoomReferenceFrame: @escaping () -> Void = {},
        confirmFieldDatumFromRoomFrame: @escaping
            () async -> Bool = { false },
        removeRoomFieldDatum: @escaping
            () async -> Void = {},
        commitFieldDatum: @escaping
            (RoomFieldDatumAuthoringRequest) async -> Bool =
            { _ in false },
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
            (PersistedCaptureRecord) -> Bool = { _ in false },
        compareAdoptedRevisionWithParent: @escaping
            () async -> CaptureRevisionComparison? = { nil },
        inspectFailedCapture: @escaping () -> Void = {},
        exportFailedCaptureDiagnostics: @escaping
            () async -> URL? = { nil },
        importMissionDocument: @escaping (URL) -> Void
            = { _ in },
        setConnectedSpaceIntent: @escaping (Bool) -> Void
            = { _ in },
        beginConnectedSegment: @escaping
            (String, CaptureRegionKind) -> Void = { _, _ in },
        completeConnectedSegment: @escaping () -> Void = {},
        recordConnectedPortal: @escaping
            (CaptureRegionID, CapturePortalKind) -> Void
            = { _, _ in },
        revisitConnectedRegion: @escaping
            (CaptureRegionID) -> Void = { _ in },
        asBuiltMarkUnavailable: @escaping (String) -> Void
            = { _ in },
        asBuiltEstablishAlignment: @escaping () -> Void = {},
        asBuiltRecordActual: @escaping
            (String, AnnotationEntityID) -> Void = { _, _ in },
        resolveRepairTask: @escaping
            (HTDTRepairTaskRow) -> Void = { _ in },
        sendCaptureToHTDT: @escaping
            (HTDTHandoffDestination, HTDTShareSheetOutcome?)
                async -> Void = { _, _ in },
        importMissionPackage: @escaping (URL) async -> Void
            = { _ in },
        startMission: @escaping (String) async -> Void = { _ in },
        deactivateMission: @escaping () async -> Void = {},
        archiveMission: @escaping (String) async -> Void = { _ in },
        completeMission: @escaping (String) async -> Void = { _ in },
        updateMissionUserNote: @escaping
            (String, String?) async -> Void = { _, _ in },
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
        importInboundDocument: @escaping (URL) -> Void = { _ in },
        confirmLibraryImport: @escaping () -> Void = {},
        dismissLibraryImport: @escaping () -> Void = {},
        exportLibraryPackage: @escaping () -> Void = {},
        setSeriesArchived: @escaping
            (CaptureSeriesID, Bool) -> Void = { _, _ in },
        updateRevisionMark: @escaping
            (CaptureRevisionID, CaptureRevisionMark) -> Void
                = { _, _ in },
        deleteSeries: @escaping
            (CaptureSeriesID, Bool) -> Void = { _, _ in },
        derivedExportInfo: @escaping
            (CaptureRevisionID) async -> DerivedExportInfo? = {
                _ in nil
            },
        exportDerived3D: @escaping (
            CaptureRevisionID,
            Derived3DExportSelection
        ) async -> DerivedExportOutcome = { _, _ in
            DerivedExportOutcome(files: [], error: nil)
        },
        exportSurveyReport: @escaping (
            CaptureRevisionID,
            SurveyReportSelection
        ) async -> DerivedExportOutcome = { _, _ in
            DerivedExportOutcome(files: [], error: nil)
        },
        updateAppSettings: @escaping
            (CaptureAppSettings) -> Void = { _ in },
        clearEquipmentCatalogCache: @escaping () -> Void = {},
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
        cancelCaptureStart: @escaping () -> Void = {},
        preferRevisionHead: @escaping
            (CaptureSeriesID, CaptureRevisionID?) -> Void
                = { _, _ in },
        proposeRevisionAlignment: @escaping
            (CaptureRevisionID, CaptureRevisionID) async
                -> CrossRevisionRegistrationSolve? = { _, _ in nil },
        acceptRevisionAlignment: @escaping
            (CaptureRevisionID, CaptureRevisionID) async
                -> CrossRevisionRegistration? = { _, _ in nil },
        waiveMissionItem: @escaping
            (String, String, String?) async -> Void
                = { _, _, _ in },
        recordFieldNote: @escaping
            (String, CaptureFieldNoteCategory, Bool, Bool, Bool,
             CaptureFieldNoteAnchorRequest) -> Void
                = { _, _, _, _, _, _ in },
        recordReviewFieldNote: @escaping
            (String, CaptureFieldNoteCategory, Bool, [String])
                -> Void = { _, _, _, _ in },
        resolveFieldNote: @escaping (CaptureFieldNoteID) -> Void
            = { _ in },
        supersedeFieldNote: @escaping
            (CaptureFieldNoteID, String, CaptureFieldNoteCategory)
                -> Void = { _, _, _ in },
        bindFieldNote: @escaping
            (CaptureFieldNoteID, String) -> Void = { _, _ in },
        flagEvidenceFrameForPrivacy: @escaping
            (EvidenceFrameID) -> Void = { _ in },
        unflagEvidenceFrameForPrivacy: @escaping
            (EvidenceFrameID) -> Void = { _ in },
        collectSupportDiagnostics: @escaping
            () async throws -> SupportDiagnosticsPackage = {
                throw SupportDiagnosticsError.emptyPackage
            },
        openFieldReturnWorkspace: @escaping
            (String) async -> HTDTFieldReturnWorkspace? = { _ in
                nil
            },
        persistFieldReturnDraft: @escaping
            (HTDTFieldReturnWorkspace) async -> Void = { _ in },
        finalizeFieldReturn: @escaping
            (HTDTFieldReturnWorkspace) async -> URL? = { _ in nil },
        listFieldReturns: @escaping
            () async -> [HTDTFieldReturnDocument] = { [] },
        checkHTDTForMissions: @escaping
            () async -> [HTDTMissionReceiveReport] = { [] },
        preflightFieldReturn: @escaping
            (HTDTFieldReturnID, HTDTHandoffDestination) async
                -> HTDTCompatibilityVerdict = { _, _ in
                    .unknown(reason: "Not configured")
                },
        sendFieldReturnToHTDT: @escaping
            (HTDTFieldReturnID, HTDTHandoffDestination) async
                -> Void = { _, _ in },
        fieldReturnArtifactURL: @escaping
            (HTDTFieldReturnID) -> URL? = { _ in nil },
        updateOperatorRoster: @escaping
            (OperatorProfile) -> Void = { _ in },
        removeFromOperatorRoster: @escaping
            (OperatorProfileID) -> Void = { _ in }
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
        self.segmentationGesture = segmentationGesture
        self.useSegmentation = useSegmentation
        self.cancelSegmentation = cancelSegmentation
        self.segmentationAssetPrepare = segmentationAssetPrepare
        self.declareNearestUnresolvedRegion =
            declareNearestUnresolvedRegion
        self.revokeOperatorRegion = revokeOperatorRegion
        self.setGuidanceCuesEnabled = setGuidanceCuesEnabled
        self.setLoopClosureCheckActive = setLoopClosureCheckActive
        self.recordLoopClosureOutcome = recordLoopClosureOutcome
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
        self.canRecordTaskPlanMarkReason =
            canRecordTaskPlanMarkReason
        self.importEquipmentCatalog = importEquipmentCatalog
        self.selectEquipmentCatalog = selectEquipmentCatalog
        self.finalizeCapture = finalizeCapture
        self.prepareExport = prepareExport
        self.revalidateAdoptedRevision = revalidateAdoptedRevision
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
        self.resumeFailedAsDraft = resumeFailedAsDraft
        self.keepFailedAsDraft = keepFailedAsDraft
        self.discardFailedAndStartNew = discardFailedAndStartNew
        self.refreshReviewWorkspace = refreshReviewWorkspace
        self.captureRoomFrameOrigin = captureRoomFrameOrigin
        self.confirmRoomReferenceFrame =
            confirmRoomReferenceFrame
        self.confirmFieldDatumFromRoomFrame =
            confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = removeRoomFieldDatum
        self.commitFieldDatum = commitFieldDatum
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
        self.importMissionDocument = importMissionDocument
        self.setConnectedSpaceIntent = setConnectedSpaceIntent
        self.beginConnectedSegment = beginConnectedSegment
        self.completeConnectedSegment =
            completeConnectedSegment
        self.recordConnectedPortal = recordConnectedPortal
        self.revisitConnectedRegion = revisitConnectedRegion
        self.asBuiltMarkUnavailable = asBuiltMarkUnavailable
        self.asBuiltEstablishAlignment =
            asBuiltEstablishAlignment
        self.asBuiltRecordActual = asBuiltRecordActual
        self.resolveRepairTask = resolveRepairTask
        self.sendCaptureToHTDT = sendCaptureToHTDT
        self.importMissionPackage = importMissionPackage
        self.startMission = startMission
        self.deactivateMission = deactivateMission
        self.archiveMission = archiveMission
        self.completeMission = completeMission
        self.updateMissionUserNote = updateMissionUserNote
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
        self.importInboundDocument = importInboundDocument
        self.confirmLibraryImport = confirmLibraryImport
        self.dismissLibraryImport = dismissLibraryImport
        self.exportLibraryPackage = exportLibraryPackage
        self.setSeriesArchived = setSeriesArchived
        self.updateRevisionMark = updateRevisionMark
        self.deleteSeries = deleteSeries
        self.derivedExportInfo = derivedExportInfo
        self.exportDerived3D = exportDerived3D
        self.exportSurveyReport = exportSurveyReport
        self.updateAppSettings = updateAppSettings
        self.clearEquipmentCatalogCache = clearEquipmentCatalogCache
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
        self.preferRevisionHead = preferRevisionHead
        self.proposeRevisionAlignment = proposeRevisionAlignment
        self.acceptRevisionAlignment = acceptRevisionAlignment
        self.waiveMissionItem = waiveMissionItem
        self.recordFieldNote = recordFieldNote
        self.recordReviewFieldNote = recordReviewFieldNote
        self.resolveFieldNote = resolveFieldNote
        self.supersedeFieldNote = supersedeFieldNote
        self.bindFieldNote = bindFieldNote
        self.flagEvidenceFrameForPrivacy =
            flagEvidenceFrameForPrivacy
        self.unflagEvidenceFrameForPrivacy =
            unflagEvidenceFrameForPrivacy
        self.collectSupportDiagnostics = collectSupportDiagnostics
        self.openFieldReturnWorkspace = openFieldReturnWorkspace
        self.persistFieldReturnDraft = persistFieldReturnDraft
        self.finalizeFieldReturn = finalizeFieldReturn
        self.listFieldReturns = listFieldReturns
        self.checkHTDTForMissions = checkHTDTForMissions
        self.preflightFieldReturn = preflightFieldReturn
        self.sendFieldReturnToHTDT = sendFieldReturnToHTDT
        self.fieldReturnArtifactURL = fieldReturnArtifactURL
        self.updateOperatorRoster = updateOperatorRoster
        self.removeFromOperatorRoster = removeFromOperatorRoster
    }
}

#if os(iOS)
/// The system share sheet used for the share-destination HTDT
/// handoff (#225): completing a share activity is the operator's
/// explicit transfer action, and `completionWithItemsHandler` reports
/// whether that actually happened — a dismissed sheet is not a
/// delivery.
private struct HandoffShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool, Error?) -> Void

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = {
            _, completed, _, error in
            onComplete(completed, error)
        }
        return controller
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
    let onComplete: (Bool, Error?) -> Void

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
    /// #458: profiles remembered on this device for reuse across
    /// captures — fed to the Operators sheet in the workspace.
    public let operatorRoster: [OperatorProfile]
    /// Every snapshot stored in the host's catalog library (#302); the
    /// workspace renders identity rows and explicit switching.
    public let equipmentCatalogLibrary:
        [HTDTEquipmentCatalogLibrary.StoredCatalog]
    /// Imported capture task plan (#240), when loaded — drives the
    /// pinned-catalog requirement (#302) and the role-binding profile
    /// (#315) in the annotation workspace.
    public let taskPlan: HTDTCaptureTaskPlan?
    /// Live status for that plan — the annotation workspace's
    /// mark/bind actions write through it; nil when no plan is
    /// loaded.
    public let taskPlanStatus: Binding<CaptureTaskPlanStatus>?
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
    /// #269 live iterative-segmentation interaction state for the
    /// object-pass UI (nil-equivalent `.unavailable` when idle).
    public let segmentationInteraction: SegmentationInteractionState
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
    /// RoomPlan bindables decoded from the persisted bundle
    /// (#408/#409) — drive the read-only 3D scene and survey
    /// targets on the persisted workspace.
    public let persistedWorkspaceRoomPlanObjects:
        [RoomPlanBindableObject]
    /// The last persisted-workspace open failed — the pushed viewer
    /// shows a failure pane rather than a spinner that never ends.
    public let persistedWorkspaceLoadFailed: Bool
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
    /// The full receipt ledger across every revision (#394) — the
    /// retention previews consult it so receipts for revisions other
    /// than the adopted one are not invisible to delete previews.
    public let allHandoffReceipts: [HTDTHandoffReceipt]
    /// Mission inbox records (#386), the active record id, QR-paired
    /// receivers (#379) and the durable delivery-job ledger (#387) —
    /// surfaced on the home screen's sidebar.
    public let missionRecords: [HTDTMissionRecord]
    public let activeMissionRecordID: String?
    public let pairedDestinations: [PairedHTDTDestination]
    public let deliveryJobs: [HTDTDeliveryJob]
    /// App-local capture names/notes/series metadata (#219).
    public let libraryMetadata: CaptureLibraryMetadataDocument
    /// #390: one-line notice when a durable document was preserved
    /// rather than upgraded (its bytes are kept, never emptied).
    public let localStateUpgradeNotice: String?
    /// #378: staged library-package import preview awaiting confirm.
    public let libraryImportPreview:
        CaptureLibraryImportPreview?
    /// #378: the `.htdtcapturelibrary` the host last wrote, offered
    /// to the home surface's share affordance.
    public let libraryExportURL: URL?
    /// Retained-evidence inspection for a failed capture (#224).
    public let failedInspection: FailedCaptureInspection?
    /// #437: the failed capture's working revision can be preserved
    /// as a recoverable draft — set when `.failed` was entered with
    /// an end-accepted phase marker committed.
    public let failedDraftRecoverable: Bool
    /// #437: typed reason the last finalize attempt was rejected —
    /// drives the structured recovery notice on the Review surface.
    public let finalizeRejection: CaptureFinalizeRejection?
    /// #437: typed reason the last export attempt was rejected —
    /// drives the structured recovery notice on the Finalized
    /// surface.
    public let exportRejection: CaptureExportRejection?
    /// Required-task mission progress shown in the journey header
    /// (#372); nil when no plan is active.
    public let taskPlanMission: CaptureJourneyMissionSummary?
    /// Spatial authority sealed for finalization (#276).
    public let spatialCaptureSealed: Bool
    /// App-local device settings shown in the Settings surface
    /// (#338) — presentation, defaults, storage policy.
    public let appSettings: CaptureAppSettings
    /// Mission workflow state surfaced on the root (#353/#321).
    public let missionEntries: [MissionWorkflowEntry]
    public let missionTaskPlan: HTDTCaptureTaskPlan?
    public let missionTaskPlanOutcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome]
    public let connectedSpaceIntent: Bool
    public let connectedTracker: ConnectedSpaceTracker?
    public let asBuiltPlanLoaded: Bool
    public let asBuiltItems: [AsBuiltVerificationItem]
    public let asBuiltGhostOverlayEnabled: Bool
    public let asBuiltAlignmentInstalled: Bool
    /// The installed plan→capture alignment authority (#293), when
    /// established — surfaced in the mission as-built destination.
    public let asBuiltAlignment: PlanAlignmentAuthority?
    /// Ghost-overlay plan model for the as-built destination (#293);
    /// nil until an explicit alignment authority is installed.
    public let asBuiltOverlayModel: RoomPlanPreviewModel?
    /// Versioned tolerance policy supplied by the plan (#293).
    public let asBuiltTolerancePolicyRef: String?
    public let asBuiltActualCandidates: [CaptureAnnotationEntity]
    public let roomFrameAvailable: Bool
    public let repairTaskRows: [HTDTRepairTaskRow]
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
    /// Accepted cross-revision spatial registrations (#395) —
    /// app-local transform authority listed in series detail.
    public let crossRevisionRegistrations:
        [CrossRevisionRegistration]
    /// Replayed mission progress per inbox record id (#397) —
    /// derived each load from the append-only ledger, never a stored
    /// percentage.
    public let missionProgressEvaluations:
        [String: MissionProgressEvaluation]
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
    /// Which terminal discard the `.failed` surface's destructive
    /// recovery step asks the operator to confirm (#437) — start a
    /// new capture afterward, or only remove the retained data.
    @State private var pendingFailedDiscard: FailedDiscardIntent?
    @State private var reviewWorkspaceShown = false
    /// #364 §11: read-only re-open of the committed capture from the
    /// finalized summary.
    @State private var viewingFinalizedCapture = false
    @State private var handoffDestinationsShown = false
    @State private var shareArchiveForHandoff = false
    @State private var revisionComparison:
        CaptureRevisionComparison?
    @State private var comparisonLoading = false
    @State private var importingPlanReference = false
    @State private var confirmingExport = false
    /// A destructive remediation step awaiting confirmation: quality
    /// chips and the diagnostics surface route discard-type actions
    /// through this dialog instead of deleting the working set on a
    /// single tap.
    @State private var pendingRemediation:
        CaptureRemediationAction?
    @State private var diagnosticShareURL: URL?
    /// Derived export sheets (#306/#318): which validated finalized
    /// capture to export from — the active adoption or a library row.
    @State private var derived3DTarget: DerivedExportTarget?
    @State private var surveyReportTarget: DerivedExportTarget?
    @State private var missionWorkflowsShown = false
    @State private var importingMissionDocument = false
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
        operatorRoster: [OperatorProfile] = [],
        equipmentCatalogLibrary:
            [HTDTEquipmentCatalogLibrary.StoredCatalog] = [],
        taskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanStatus: Binding<CaptureTaskPlanStatus>? = nil,
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
        segmentationInteraction: SegmentationInteractionState =
            .unavailable,
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
        persistedWorkspaceRoomPlanObjects:
            [RoomPlanBindableObject] = [],
        persistedWorkspaceLoadFailed: Bool = false,
        roomFrameOriginPending: WorldPoint3D? = nil,
        openingCenterPending: WorldPoint3D? = nil,
        danglingSpatialIssues: [SpatialEvidenceIssue] = [],
        handoffDestinations: [HTDTHandoffDestination] = [],
        handoffReceipts: [HTDTHandoffReceipt] = [],
        allHandoffReceipts: [HTDTHandoffReceipt] = [],
        missionRecords: [HTDTMissionRecord] = [],
        activeMissionRecordID: String? = nil,
        pairedDestinations: [PairedHTDTDestination] = [],
        deliveryJobs: [HTDTDeliveryJob] = [],
        libraryMetadata: CaptureLibraryMetadataDocument
            = CaptureLibraryMetadataDocument(),
        localStateUpgradeNotice: String? = nil,
        libraryImportPreview:
            CaptureLibraryImportPreview? = nil,
        libraryExportURL: URL? = nil,
        failedInspection: FailedCaptureInspection? = nil,
        failedDraftRecoverable: Bool = false,
        finalizeRejection: CaptureFinalizeRejection? = nil,
        exportRejection: CaptureExportRejection? = nil,
        spatialCaptureSealed: Bool = false,
        appSettings: CaptureAppSettings = CaptureAppSettings(),
        missionEntries: [MissionWorkflowEntry] = [],
        missionTaskPlan: HTDTCaptureTaskPlan? = nil,
        missionTaskPlanOutcomes:
            [CaptureTaskPlanStatusDocument.ItemOutcome] = [],
        connectedSpaceIntent: Bool = false,
        connectedTracker: ConnectedSpaceTracker? = nil,
        asBuiltPlanLoaded: Bool = false,
        asBuiltItems: [AsBuiltVerificationItem] = [],
        asBuiltGhostOverlayEnabled: Bool = false,
        asBuiltAlignmentInstalled: Bool = false,
        asBuiltAlignment: PlanAlignmentAuthority? = nil,
        asBuiltOverlayModel: RoomPlanPreviewModel? = nil,
        asBuiltTolerancePolicyRef: String? = nil,
        asBuiltActualCandidates: [CaptureAnnotationEntity] = [],
        roomFrameAvailable: Bool = false,
        repairTaskRows: [HTDTRepairTaskRow] = [],
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
        crossRevisionRegistrations:
            [CrossRevisionRegistration] = [],
        missionProgressEvaluations:
            [String: MissionProgressEvaluation] = [:],
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
        self.operatorRoster = operatorRoster
        self.equipmentCatalogLibrary = equipmentCatalogLibrary
        self.taskPlan = taskPlan
        self.taskPlanStatus = taskPlanStatus
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
        self.segmentationInteraction = segmentationInteraction
        self.declaredRegions = declaredRegions
        self.loopClosureCheckActive = loopClosureCheckActive
        self.loopClosureAssessment = loopClosureAssessment
        self.guidanceCuesEnabled = guidanceCuesEnabled
        self.revisitFlags = revisitFlags
        self.revisitFlagsFull = revisitFlagsFull
        self.persistedInventory = persistedInventory
        self.reviewWorkspace = reviewWorkspace
        self.persistedWorkspace = persistedWorkspace
        self.persistedWorkspaceRoomPlanObjects =
            persistedWorkspaceRoomPlanObjects
        self.persistedWorkspaceLoadFailed =
            persistedWorkspaceLoadFailed
        self.roomFrameOriginPending = roomFrameOriginPending
        self.openingCenterPending = openingCenterPending
        self.danglingSpatialIssues = danglingSpatialIssues
        self.handoffDestinations = handoffDestinations
        self.handoffReceipts = handoffReceipts
        self.allHandoffReceipts = allHandoffReceipts
        self.missionRecords = missionRecords
        self.activeMissionRecordID = activeMissionRecordID
        self.pairedDestinations = pairedDestinations
        self.deliveryJobs = deliveryJobs
        self.libraryMetadata = libraryMetadata
        self.localStateUpgradeNotice = localStateUpgradeNotice
        self.libraryImportPreview = libraryImportPreview
        self.libraryExportURL = libraryExportURL
        self.failedInspection = failedInspection
        self.failedDraftRecoverable = failedDraftRecoverable
        self.finalizeRejection = finalizeRejection
        self.exportRejection = exportRejection
        self.spatialCaptureSealed = spatialCaptureSealed
        self.appSettings = appSettings
        self.missionEntries = missionEntries
        self.missionTaskPlan = missionTaskPlan
        self.missionTaskPlanOutcomes = missionTaskPlanOutcomes
        self.connectedSpaceIntent = connectedSpaceIntent
        self.connectedTracker = connectedTracker
        self.asBuiltPlanLoaded = asBuiltPlanLoaded
        self.asBuiltItems = asBuiltItems
        self.asBuiltGhostOverlayEnabled =
            asBuiltGhostOverlayEnabled
        self.asBuiltAlignmentInstalled = asBuiltAlignmentInstalled
        self.asBuiltAlignment = asBuiltAlignment
        self.asBuiltOverlayModel = asBuiltOverlayModel
        self.asBuiltTolerancePolicyRef = asBuiltTolerancePolicyRef
        self.asBuiltActualCandidates = asBuiltActualCandidates
        self.roomFrameAvailable = roomFrameAvailable
        self.repairTaskRows = repairTaskRows
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
        self.crossRevisionRegistrations =
            crossRevisionRegistrations
        self.missionProgressEvaluations =
            missionProgressEvaluations
        self.activeOperations = activeOperations
        self.operationTargetRevisionID =
            operationTargetRevisionID
        self.actions = actions
    }

    /// The terminal-discard choice a `.failed` destructive recovery
    /// step confirms before running (#437).
    private enum FailedDiscardIntent {
        /// Remove the retained data, then open capture setup.
        case discardAndStartNew
        /// Remove the retained data only.
        case discardOnly
    }

    /// #437: the resolved failure → recovery contract for the
    /// current capture-terminal surface — nil when the surface is
    /// healthy and shows its normal controls.
    private var recoveryPlan: CaptureRecoveryPlan? {
        switch state {
        case .failed:
            return CaptureRecoveryPresentation.failedPlan(
                failure: lastFailure ?? .unknown,
                draftRecoverable: failedDraftRecoverable
            )
        case .reviewing:
            guard let finalizeRejection else { return nil }
            return CaptureRecoveryPresentation
                .finalizeRejectedPlan(finalizeRejection)
        case .finalized:
            guard let exportRejection else { return nil }
            return CaptureRecoveryPresentation
                .exportRejectedPlan(exportRejection)
        default:
            return nil
        }
    }

    /// Routes a quality-remediation affordance. Destructive steps
    /// (replace-revision / discard) go through the pendingRemediation
    /// confirmation dialog first — a one-tap chip or diagnostics row
    /// must never delete the working set outright.
    private func routeRemediation(
        _ action: CaptureRemediationAction
    ) {
        switch action {
        case .startReplacementRevision, .discardDraft:
            pendingRemediation = action
        default:
            actions.performRemediation(action)
        }
    }

    /// Binds a plan step to its real host action (#437) — every
    /// action id the resolver emits lands here.
    private func performRecoveryAction(
        _ action: CaptureRecoveryAction
    ) {
        switch action {
        case .resumeFailedAsDraft:
            actions.resumeFailedAsDraft()
        case .keepFailedAsDraft:
            actions.keepFailedAsDraft()
        case .retryFinalize:
            actions.finalizeCapture()
        case .openAnnotations:
            actions.beginAnnotation()
        case .saveDraftAndFinishLater:
            actions.suspendReview()
        case .inspectRetainedEvidence:
            actions.inspectFailedCapture()
        case .exportDiagnostics:
            Task {
                diagnosticShareURL =
                    await actions
                        .exportFailedCaptureDiagnostics()
            }
        case .retryExport:
            confirmingExport = true
        case .discardAndStartNew:
            pendingFailedDiscard = .discardAndStartNew
        case .discardFailedCapture:
            pendingFailedDiscard = .discardOnly
        case .discardCapture:
            confirmingDiscard = true
        case .deleteLocalCapture:
            if let revisionID =
                validationReport?.manifest.captureRevisionID
            {
                pendingDeletion = PendingCaptureDeletion(
                    revisionID: revisionID,
                    includesExport: exportURL != nil,
                    record: finalizedPersistedRecord,
                    allRecords: persistedInventory.captures,
                    metadata: libraryMetadata,
                    deliveryJobs: deliveryJobs,
                    missionRecords: missionRecords,
                    receipts: allHandoffReceipts
                )
            }
        case .startNewCapture:
            // "Leaves this capture saved and begins a fresh one" —
            // reset drops the finalized surface to .idle, then
            // setup opens.
            actions.resetCapture()
            actions.beginCapture()
        case .openCameraSettings:
            actions.openCameraSettings()
        case .retryCameraPermission:
            actions.retryCameraPermission()
        }
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
                    segmentationInteraction:
                        segmentationInteraction,
                    segmentationGesture:
                        actions.segmentationGesture,
                    useSegmentation: actions.useSegmentation,
                    cancelSegmentation:
                        actions.cancelSegmentation,
                    segmentationAssetPrepare:
                        actions.segmentationAssetPrepare,
                    declareNearestUnresolvedRegion:
                        actions.declareNearestUnresolvedRegion,
                    revokeOperatorRegion:
                        actions.revokeOperatorRegion,
                    setGuidanceCuesEnabled:
                        actions.setGuidanceCuesEnabled,
                    setLoopClosureCheckActive:
                        actions.setLoopClosureCheckActive,
                    recordLoopClosureOutcome:
                        actions.recordLoopClosureOutcome,
                    discardCapture: actions.discardActiveCapture,
                    probePlacementTarget:
                        actions.probePlacementTarget,
                    recordFieldNote: actions.recordFieldNote,
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
                    localStateUpgradeNotice:
                        localStateUpgradeNotice,
                    libraryImportPreview: libraryImportPreview,
                    libraryImportCommitInFlight:
                        activeOperations.contains(.importArchive),
                    libraryExportURL: libraryExportURL,
                    persistedWorkspace: persistedWorkspace,
                    persistedWorkspaceRoomPlanObjects:
                        persistedWorkspaceRoomPlanObjects,
                    persistedWorkspaceLoadFailed:
                        persistedWorkspaceLoadFailed,
                    handoffReceipts: handoffReceipts,
                    allHandoffReceipts: allHandoffReceipts,
                    captureOrigins: captureOrigins,
                    missionRecords: missionRecords,
                    activeMissionRecordID: activeMissionRecordID,
                    pairedDestinations: pairedDestinations,
                    deliveryJobs: deliveryJobs,
                    crossRevisionRegistrations:
                        crossRevisionRegistrations,
                    missionProgressEvaluations:
                        missionProgressEvaluations,
                    workingSetStatus: workingSetStatus,
                    appSettings: appSettings,
                    equipmentCatalog: equipmentCatalog,
                    actions: actions
                )
            } else {
                NavigationStack {
            if state == .setup,
               let captureSetup
            {
                CaptureSetupView(
                    presentation: captureSetup,
                    connectedSpaceIntent: Binding(
                        get: { connectedSpaceIntent },
                        set: {
                            actions.setConnectedSpaceIntent($0)
                        }
                    ),
                    onImportMissionDocument: {
                        importingMissionDocument = true
                    },
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
                    onResumeDraft: actions.openRecoveredDraft,
                    onDiscardDraft: {
                        draft in
                        actions.discardRecoveredDraft(draft)
                    },
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
                    taskPlanStatus: taskPlanStatus,
                    onImportEquipmentCatalog:
                        actions.importEquipmentCatalog,
                    equipmentCatalogLibrary: equipmentCatalogLibrary,
                    onSelectEquipmentCatalog:
                        actions.selectEquipmentCatalog,
                    operatorRoster: operatorRoster,
                    onUpdateOperatorRoster:
                        actions.updateOperatorRoster,
                    onRemoveFromOperatorRoster:
                        actions.removeFromOperatorRoster,
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
                   let plan = recoveryPlan
                {
                    // #437: the failure banner names the failed step,
                    // gives the reason in plain language, and states
                    // whether the data survives as a resumable draft.
                    Section {
                        CaptureNotice(
                            status: .blocked,
                            title: LocalizedStringKey(
                                plan.titleKey
                            ),
                            message: LocalizedStringKey(
                                plan.reasonKey
                            )
                        )
                        .listRowSeparator(.hidden)
                        if let detailKey = plan.detailKey {
                            Text(
                                LocalizedStringKey(detailKey)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
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

                Section("Settings") {
                    NavigationLink("Preferences & storage") {
                        CaptureSettingsView(
                            settings: appSettings,
                            equipmentCatalog: equipmentCatalog,
                            retainedByteCount: persistedInventory
                                .totalRetainedBytes,
                            onChange: actions.updateAppSettings,
                            onClearEquipmentCatalog: actions
                                .clearEquipmentCatalogCache
                        )
                    }
                }

                // #353: mission workflows reachable from production
                // root; entries appear only when a mission requires
                // them. #321: unresolved repair tasks surface here.
                Section("Mission workflows") {
                    Button("Mission workflows…") {
                        missionWorkflowsShown = true
                    }
                    Button("Import mission document (.json)") {
                        importingMissionDocument = true
                    }
                    let unresolved = repairTaskRows.filter {
                        $0.resolvedByRevisionID == nil
                    }
                    if !unresolved.isEmpty {
                        LabeledContent(
                            "Repair tasks",
                            value: String(
                                format: "%d open",
                                unresolved.count
                            )
                        )
                    }
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
                                spatialAuthoritySealed:
                                    spatialCaptureSealed,
                                practiceCapture:
                                    practiceCaptureActive,
                                onRemediationAction:
                                    routeRemediation
                            )
                        }
                    }
                }

                if (state == .finalized || state == .exported),
                   let validationReport
                {
                    finalizedSummarySection(
                        validation: validationReport
                    )
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
                        Button("Export derived 3D model…") {
                            derived3DTarget = DerivedExportTarget(
                                revisionID:
                                    validationReport.manifest
                                        .captureRevisionID,
                                displayName:
                                    libraryMetadata.revisions[
                                        validationReport.manifest
                                            .captureRevisionID
                                            .description
                                    ]?.displayName
                            )
                        }
                        Button("Export survey report…") {
                            surveyReportTarget = DerivedExportTarget(
                                revisionID:
                                    validationReport.manifest
                                        .captureRevisionID,
                                displayName:
                                    libraryMetadata.revisions[
                                        validationReport.manifest
                                            .captureRevisionID
                                            .description
                                    ]?.displayName
                            )
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
                            canRecordTaskPlanReason:
                                reviewWorkspace.captureTaskPlan
                                    .map {
                                        actions
                                            .canRecordTaskPlanMarkReason(
                                                $0
                                            )
                                    } ?? false,
                            confirmFieldDatumFromRoomFrame:
                                actions
                                    .confirmFieldDatumFromRoomFrame,
                            removeRoomFieldDatum:
                                actions.removeRoomFieldDatum,
                            commitFieldDatum:
                                actions.commitFieldDatum,
                            captureOpeningCenter:
                                actions.captureOpeningCenter,
                            clearOpeningCenter:
                                actions.clearOpeningCenter,
                            recordReviewFieldNote:
                                actions.recordReviewFieldNote,
                            resolveFieldNote:
                                actions.resolveFieldNote,
                            supersedeFieldNote:
                                actions.supersedeFieldNote,
                            bindFieldNote:
                                actions.bindFieldNote,
                            flagEvidenceFrameForPrivacy:
                                actions
                                    .flagEvidenceFrameForPrivacy,
                            unflagEvidenceFrameForPrivacy:
                                actions
                                    .unflagEvidenceFrameForPrivacy,
                            roomPlanObjects:
                                annotationRoomPlanObjects
                        )
                    } else {
                        ProgressView("Loading workspace…")
                    }
                }
                .navigationDestination(
                    isPresented: $viewingFinalizedCapture
                ) {
                    // #364 §11: read-only re-open of the committed
                    // capture — same pattern as the home surface's
                    // persisted viewer (#294).
                    if let persistedWorkspace {
                        CaptureReviewWorkspaceView(
                            model: persistedWorkspace,
                            roomPlanObjects:
                                persistedWorkspaceRoomPlanObjects
                        )
                    } else if persistedWorkspaceLoadFailed {
                        ContentUnavailableView(
                            "Couldn't open capture",
                            systemImage: "exclamationmark.triangle",
                            description: Text(
                                "The saved bundle could not be read; it stays in the library."
                            )
                        )
                    } else {
                        ProgressView("Loading capture…")
                    }
                }
                // #364 §7.5: Review carries exactly one prominent
                // primary action in a persistent bottom bar instead
                // of a CTA row that scrolls away mid-list — same
                // pattern as the Setup stage's Begin footer.
                .safeAreaInset(edge: .bottom) {
                    if state == .reviewing {
                        VStack(
                            spacing: CaptureDesign.Spacing.row
                        ) {
                            reviewingPrimaryAction
                        }
                        .padding(
                            .horizontal,
                            CaptureDesign.Spacing.edge
                        )
                        .padding(
                            .vertical,
                            CaptureDesign.Spacing.row
                        )
                        .background(.bar)
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
                        "Stops the capture and permanently removes the working revision. Finalized captures are never touched."
                    )
                }
                // #437: the destructive steps on the failed surface
                // confirm before removing retained data — optionally
                // continuing into capture setup.
                .confirmationDialog(
                    "Discard the failed capture's data?",
                    isPresented: Binding(
                        get: { pendingFailedDiscard != nil },
                        set: { presented in
                            if !presented {
                                pendingFailedDiscard = nil
                            }
                        }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingFailedDiscard
                ) { intent in
                    switch intent {
                    case .discardAndStartNew:
                        Button(
                            "Discard and start a new capture",
                            role: .destructive
                        ) {
                            actions.discardFailedAndStartNew()
                        }
                    case .discardOnly:
                        Button(
                            "Discard the failed capture",
                            role: .destructive
                        ) {
                            actions.resetCapture()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text(
                        "Permanently removes the data this capture kept. Finalized captures are never touched."
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
                                            value: MissionPresentation
                                                .deliveryJobStateName(
                                                    job.state
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
                    isPresented: $shareArchiveForHandoff
                ) {
                    if let exportURL {
                        HandoffShareSheet(
                            items: [exportURL],
                            onComplete: recordShareSheetHandoff
                        )
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
                .sheet(item: $derived3DTarget) { target in
                    Derived3DExportSheet(
                        target: target,
                        actions: actions
                    )
                }
                .sheet(item: $surveyReportTarget) { target in
                    SurveyReportExportSheet(
                        target: target,
                        actions: actions
                    )
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
                    // Each branch carries its own Cancel — iOS 26
                    // renders only the first action-producing child,
                    // so a button written after the `if` never
                    // appears.
                    if pending.blockers.isEmpty {
                        Button(
                            pending.archiveOnly
                                ? "Delete export archive"
                                : pending.includesExport
                                    ? "Delete capture and export"
                                    : "Delete capture",
                            role: .destructive
                        ) {
                            actions.deletePersistedCapture(
                                pending.revisionID
                            )
                        }
                        Button("Cancel", role: .cancel) {}
                    } else {
                        Button("Cancel", role: .cancel) {}
                    }
                } message: { pending in
                    // iOS 26 renders only the first `message:`
                    // child — the blocker list and its guidance must
                    // fold into one `Text` to reach the operator.
                    if pending.blockers.isEmpty {
                        Text(deletionExplanationText(for: pending))
                    } else {
                        Text(
                            (pending.blockers.map(\.deletionSummary)
                                + [
                                    String(
                                        localized:
                                            "Delete is unavailable until the block is cleared — cancel the delivery job or remove the mark first."
                                    )
                                ]).joined(separator: "\n")
                        )
                    }
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
                .fileImporter(
                    isPresented: $importingMissionDocument,
                    // #457: `.htdtmission` mission packages are
                    // pickable alongside JSON mission documents.
                    allowedContentTypes: [
                        .json, .plainText, .htdtMission,
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    guard let urls = try? result.get(),
                          let url = urls.first
                    else {
                        return
                    }
                    actions.importMissionDocument(url)
                }
                .sheet(isPresented: $missionWorkflowsShown) {
                    MissionWorkflowsView(
                        entries: missionEntries,
                        taskPlan: missionTaskPlan,
                        taskPlanOutcomes: missionTaskPlanOutcomes,
                        connectedSpaceIntent: connectedSpaceIntent,
                        connectedTracker: connectedTracker,
                        asBuiltPlanLoaded: asBuiltPlanLoaded,
                        asBuiltItems: asBuiltItems,
                        asBuiltGhostOverlayEnabled:
                            asBuiltGhostOverlayEnabled,
                        asBuiltAlignmentInstalled:
                            asBuiltAlignmentInstalled,
                        asBuiltAlignment: asBuiltAlignment,
                        asBuiltOverlayModel: asBuiltOverlayModel,
                        asBuiltTolerancePolicyRef:
                            asBuiltTolerancePolicyRef,
                        asBuiltActualCandidates:
                            asBuiltActualCandidates,
                        roomFrameAvailable: roomFrameAvailable,
                        repairRows: repairTaskRows,
                        canRecordReason: missionTaskPlan
                            .map {
                                actions
                                    .canRecordTaskPlanMarkReason($0)
                            } ?? false,
                        onMarkTaskPlanItem:
                            actions.markTaskPlanItem,
                        onSetConnectedSpaceIntent:
                            actions.setConnectedSpaceIntent,
                        onBeginConnectedSegment:
                            actions.beginConnectedSegment,
                        onCompleteConnectedSegment:
                            actions.completeConnectedSegment,
                        onRecordPortal:
                            actions.recordConnectedPortal,
                        onRevisitRegion:
                            actions.revisitConnectedRegion,
                        onAsBuiltMarkUnavailable:
                            actions.asBuiltMarkUnavailable,
                        onAsBuiltEstablishAlignment:
                            actions.asBuiltEstablishAlignment,
                        onAsBuiltRecordActual:
                            actions.asBuiltRecordActual,
                        onResolveRepairTask:
                            actions.resolveRepairTask,
                        onOpenAnnotationWorkspace:
                            actions.beginAnnotation
                    )
                    .presentationDetents([.medium, .large])
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
        // Anchored to the outermost container: the remediation
        // trigger can live inside a pushed diagnostics detail, and a
        // dialog attached to the list behind it would stay hidden
        // until the operator navigates back.
        .confirmationDialog(
            pendingRemediation
                == .startReplacementRevision
                ? "Start a replacement capture?"
                : "Discard the working capture?",
            isPresented: Binding(
                get: { pendingRemediation != nil },
                set: { presented in
                    if !presented {
                        pendingRemediation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            // Each branch carries its own Cancel — iOS 26 renders
            // only the first action-producing child, so a button
            // written after the `if` never appears.
            if pendingRemediation
                == .startReplacementRevision
            {
                Button(
                    "Discard and start replacement",
                    role: .destructive
                ) {
                    if let action = pendingRemediation {
                        actions.performRemediation(action)
                    }
                    pendingRemediation = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRemediation = nil
                }
            } else {
                Button(
                    "Discard capture",
                    role: .destructive
                ) {
                    if let action = pendingRemediation {
                        actions.performRemediation(action)
                    }
                    pendingRemediation = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRemediation = nil
                }
            }
        } message: {
            Text(
                pendingRemediation
                    == .startReplacementRevision
                    ? "Permanently removes this working revision and opens capture setup. Finalized captures are never touched."
                    : "Permanently removes the working revision. Finalized captures are never touched."
            )
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
                .disabled(
                    !capabilities.roomPlanMeshEligible || hostBusy
                )
            // #351: import is a library/home action, not a capture
            // capability — it stays available on non-capture-capable
            // devices.
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
            // Working-set creation is cancellable too — a stalled
            // preparation must not strand the operator (#254).
            discardButton

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

        case .reviewing:
            // #437: a rejected finalize attempt names the specific
            // step and the ordered next-step set — retry, save the
            // draft for later, or discard. The capture stays
            // mutable; nothing was lost.
            if let plan = recoveryPlan {
                CaptureNotice(
                    status: .needsReview,
                    title: LocalizedStringKey(plan.titleKey),
                    message: LocalizedStringKey(plan.reasonKey)
                )
                .listRowSeparator(.hidden)
                if let detailKey = plan.detailKey {
                    Text(LocalizedStringKey(detailKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                recoveryStepsView(plan)
            }
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
                                captureCountPhrase(
                                    report.unsupportedPaths.count,
                                    singular: String(
                                        localized: "%lld file kept but unsupported by this app version."
                                    ),
                                    plural: String(
                                        localized: "%lld files kept but unsupported by this app version."
                                    )
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !report.supersededPaths.isEmpty {
                            Text(
                                captureCountPhrase(
                                    report.supersededPaths.count,
                                    singular: String(
                                        localized: "%lld stale analysis file will be recomputed."
                                    ),
                                    plural: String(
                                        localized: "%lld stale analysis files will be recomputed."
                                    )
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !report.unmanifestablePaths.isEmpty {
                            Text(
                                captureCountPhrase(
                                    report.unmanifestablePaths.count,
                                    singular: String(
                                        localized: "%lld file could not be included in the bundle and was removed."
                                    ),
                                    plural: String(
                                        localized: "%lld files could not be included in the bundle and were removed."
                                    )
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

            // #364 §7.5: the stage's single primary action is pinned
            // to the persistent bottom bar (see the safeAreaInset on
            // this screen) — the list keeps only secondary actions.
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
            // #437: the ordered recovery contract — reopen/keep the
            // draft when the End boundary survived, inspect or
            // export the retained evidence, or discard. Every step
            // is a real action; the resolver never emits a dead
            // control.
            if let plan = recoveryPlan {
                recoveryStepsView(plan)
            }
            if activeOperations.contains(.exportDiagnostics) {
                progressRow("Preparing diagnostic package…")
            }

        case .annotating:
            EmptyView()

        case .validating:
            progressRow("Validating and finalizing capture…")

        case .finalized:
            // #437: a rejected export attempt names the specific
            // step and the ordered next-step set — the finalized
            // revision itself is durable; only the transport failed.
            if let plan = recoveryPlan {
                CaptureNotice(
                    status: .needsReview,
                    title: LocalizedStringKey(plan.titleKey),
                    message: LocalizedStringKey(plan.reasonKey)
                )
                .listRowSeparator(.hidden)
                if let detailKey = plan.detailKey {
                    Text(LocalizedStringKey(detailKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                recoveryStepsView(plan)
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
                            captureCountPhrase(
                                retainedVisualEvidenceCount,
                                singular: String(
                                    localized: "The archive packages %lld retained camera frame pixel payload with the capture. Open Visual evidence review first if you need to remove unreferenced frames for privacy."
                                ),
                                plural: String(
                                    localized: "The archive packages %lld retained camera frame pixel payloads with the capture. Open Visual evidence review first if you need to remove unreferenced frames for privacy."
                                )
                            )
                        )
                    }
                if activeOperations.contains(.prepareExport) {
                    progressRow("Preparing archive…")
                }
                revisionControls
            } else if validationReport == nil {
                // Committed-but-unverified: the promoted bytes are
                // durable, but independent post-promotion validation
                // did not prove them, so export/revision actions stay
                // withheld. Offer explicit recovery — re-validate on
                // demand or start over — instead of dead controls.
                CaptureNotice(
                    status: .needsReview,
                    title: "Committed but unverified",
                    message: "The finalized revision could not be proven by post-promotion validation; its bytes are preserved. Re-validate to unlock export, or start a new capture."
                )
                .listRowSeparator(.hidden)
                Button("Re-validate bundle") {
                    actions.revalidateAdoptedRevision()
                }
                .capturePrimaryAction()
                .disabled(hostBusy)
                if activeOperations.contains(.prepareExport) {
                    progressRow("Re-validating bundle…")
                }
                Button(
                    "Start new capture",
                    action: actions.resetCapture
                )
                .disabled(hostBusy)
            } else {
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
                        captureCountPhrase(
                            retainedVisualEvidenceCount,
                            singular: String(
                                localized: "The archive packages %lld retained camera frame pixel payload with the capture. Open Visual evidence review first if you need to remove unreferenced frames for privacy."
                            ),
                            plural: String(
                                localized: "The archive packages %lld retained camera frame pixel payloads with the capture. Open Visual evidence review first if you need to remove unreferenced frames for privacy."
                            )
                        )
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
                            includesExport: exportURL != nil,
                            record: finalizedPersistedRecord,
                            allRecords: persistedInventory.captures,
                            metadata: libraryMetadata,
                            deliveryJobs: deliveryJobs,
                            missionRecords: missionRecords,
                            receipts: allHandoffReceipts
                        )
                    }
                    .disabled(hostBusy)
                }
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
                        includesExport: exportURL != nil,
                        record: finalizedPersistedRecord,
                        allRecords: persistedInventory.captures,
                        metadata: libraryMetadata,
                        deliveryJobs: deliveryJobs,
                        missionRecords: missionRecords,
                        receipts: allHandoffReceipts
                    )
                }
                .disabled(hostBusy)
            }
        }
    }

    /// #364 §7.5: the review stage's single primary action lives in a
    /// persistent bottom bar — always present, always exactly one
    /// prominent action, chosen by the same journey rule as before
    /// (#372): a blocking integrity problem → Review diagnostics;
    /// required mission tasks outstanding → Complete required tasks;
    /// coverage unknown → Continue scanning; otherwise → Validate and
    /// finalize.
    @ViewBuilder
    private var reviewingPrimaryAction: some View {
        switch journey.primaryAction {
        case .reviewDiagnostics:
            if let qualityReport {
                NavigationLink("Review diagnostics") {
                    CaptureReviewView(
                        quality: qualityReport,
                        advisory: advisoryReport,
                        spatialFindings:
                            spatialPlausibilityFindings,
                        spatialAuthorityLive:
                            liveSpatialAuthority,
                        spatialAuthoritySealed:
                            spatialCaptureSealed,
                        practiceCapture:
                            practiceCaptureActive,
                        onRemediationAction:
                            routeRemediation
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
                            let remediation =
                                QualityRemediationCatalog
                                    .remediation(
                                        for: diagnostic
                                    )
                            let available = spatialCaptureSealed
                                ? remediation.draftActions
                                : remediation.actions
                            if let first = available.first {
                                Button {
                                    routeRemediation(first)
                                } label: {
                                    Text(
                                        localizedQualityDiagnosticMessage(
                                            diagnostic
                                        )
                                    )
                                        .font(.caption)
                                }
                            } else {
                                Text(
                                    localizedQualityDiagnosticMessage(
                                        diagnostic
                                    )
                                )
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
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
    }

    /// #364 §11: the finalized surface opens with a plain-language
    /// summary — what was committed, how much evidence it carries and
    /// the mission outcome — before the export/handoff controls.
    /// Counts come from the validated manifest and quality report,
    /// never re-derived from filesystem guesses.
    private func finalizedSummarySection(
        validation: BundleValidationReport
    ) -> some View {
        let manifest = validation.manifest
        let revisionID = manifest.captureRevisionID
        let entry = libraryMetadata.revisions[revisionID.description]
        let seriesEntry =
            libraryMetadata.series[manifest.captureSeriesID.description]
        let dateLabel = CaptureSeriesPresentation.dateLabel(
            for: manifest.finalizedAtUTC
        ) ?? manifest.finalizedAtUTC
        let displayName =
            (entry?.displayName?.isEmpty == false
                ? entry?.displayName : nil)
            ?? (seriesEntry?.displayName?.isEmpty == false
                ? seriesEntry?.displayName : nil)
        let titleDetail = displayName.map {
            String(format: String(localized: "%@ · %@"), $0, dateLabel)
        } ?? dateLabel
        let evidenceFrameCount = manifest.files.filter {
            $0.provenanceClass == .arkitFrameObservation
        }.count
        let annotationCount =
            qualityReport?.annotationCompleteness.present.count ?? 0
        let measurementCount =
            qualityReport?.measurementCompleteness.present.count ?? 0
        return Section {
            VStack(
                alignment: .leading,
                spacing: CaptureDesign.Spacing.micro
            ) {
                Text("Capture finalized")
                    .font(CaptureDesign.Typography.taskHeadline)
                Text(titleDetail)
                    .font(CaptureDesign.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)

            finalizedSummaryRow(
                validation.valid ? .verified : .blocked,
                String(localized: "Bundle validated")
            )
            finalizedSummaryRow(
                evidenceFrameCount > 0 ? .verified : .incomplete,
                String(
                    format: String(localized: "%lld evidence frames"),
                    evidenceFrameCount
                )
            )
            if qualityReport != nil {
                finalizedSummaryRow(
                    annotationCount > 0 ? .verified : .incomplete,
                    String(
                        format: String(localized: "%lld annotations"),
                        annotationCount
                    )
                )
                finalizedSummaryRow(
                    measurementCount > 0 ? .verified : .incomplete,
                    String(
                        format: String(
                            localized: "%lld measurements"
                        ),
                        measurementCount
                    )
                )
            }
            if let mission = taskPlanMission {
                finalizedSummaryRow(
                    mission.outstanding == 0
                        ? .verified : .incomplete,
                    String(
                        format: String(
                            localized: "Required tasks %lld/%lld"
                        ),
                        mission.requiredCompleted,
                        mission.requiredTotal
                    )
                )
            }

            // #364 §11: the committed capture reopens read-only in the
            // same review workspace the operator already knows.
            if finalizedPersistedRecord != nil {
                Button("View capture") {
                    if let record = finalizedPersistedRecord {
                        viewingFinalizedCapture =
                            actions.loadPersistedWorkspace(record)
                    }
                }
            }
        }
    }

    private func finalizedSummaryRow(
        _ status: CaptureSemanticStatus,
        _ label: String
    ) -> some View {
        HStack(spacing: CaptureDesign.Spacing.row) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.colorRole.color)
            Text(label)
                .font(CaptureDesign.Typography.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The validated persisted record for the capture currently on
    /// screen — required to reopen it read-only through
    /// `loadPersistedWorkspace` (#294).
    private var finalizedPersistedRecord: PersistedCaptureRecord? {
        guard let revisionID =
                validationReport?.manifest.captureRevisionID
        else {
            return nil
        }
        return persistedInventory.captures.first {
            $0.captureRevisionID == revisionID && $0.canOpen
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
        case .semanticCorrection:
            return "Building corrected revision…"
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

    /// One plan step rendered as its role demands (#437): primary
    /// and secondary are real buttons bound through
    /// `performRecoveryAction`, destructive asks for confirmation,
    /// guidance is an instruction line — never a control. The
    /// step's detail (consequence or pre-condition) renders as a
    /// caption under it.
    @ViewBuilder
    private func recoveryStepRow(
        _ step: CaptureRecoveryStep
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch step.role {
            case .primary:
                Button(LocalizedStringKey(step.titleKey)) {
                    if let action = step.action {
                        performRecoveryAction(action)
                    }
                }
                .capturePrimaryAction()
                .disabled(hostBusy)
            case .secondary:
                Button(LocalizedStringKey(step.titleKey)) {
                    if let action = step.action {
                        performRecoveryAction(action)
                    }
                }
                .captureSecondaryAction()
                .disabled(hostBusy)
            case .destructive:
                Button(
                    LocalizedStringKey(step.titleKey),
                    role: .destructive
                ) {
                    if let action = step.action {
                        performRecoveryAction(action)
                    }
                }
                .disabled(hostBusy)
            case .guidance:
                Text(LocalizedStringKey(step.titleKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let detailKey = step.detailKey {
                Text(LocalizedStringKey(detailKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The ordered next-step list for a resolved recovery plan
    /// (#437) — reason + detail are already shown by the surface's
    /// notice; this renders only the actionable steps in order.
    @ViewBuilder
    private func recoveryStepsView(
        _ plan: CaptureRecoveryPlan
    ) -> some View {
        ForEach(
            Array(plan.steps.enumerated()),
            id: \.offset
        ) { _, step in
            recoveryStepRow(step)
        }
        if let diagnosticShareURL {
            ShareLink(item: diagnosticShareURL) {
                Label(
                    "Share diagnostic package",
                    systemImage: "square.and.arrow.up"
                )
            }
        }
    }

    private func progressRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }

    /// Where finalized data is retained + its backup state (#305) —
    /// stated on the library itself, not only inside Settings.
    private var finalizedRetentionText: String {
        switch appSettings.storagePrivacy.finalizedBackupPolicy {
        case .backupEligible:
            return String(
                localized:
                    "Finalized captures and export archives stay in this app's on-device storage and may be included in your device backup."
            )
        case .excludedFromBackup:
            return String(
                localized:
                    "Finalized captures and export archives stay in this app's on-device storage and are excluded from device backup."
            )
        }
    }

    /// Deletion scope (#305): always states what is removed locally;
    /// when finalized data may join device backup it also says a
    /// backup copy is managed by the system.
    private func deletionExplanationText(
        for pending: PendingCaptureDeletion
    ) -> String {
        var base: String
        if pending.archiveOnly {
            base = String(
                localized:
                    "This permanently deletes the export archive for this capture from this device — it is the only local copy; no finalized bundle is stored here."
            )
        } else {
            switch appSettings.storagePrivacy.finalizedBackupPolicy {
            case .backupEligible:
                base = String(
                    localized:
                        "This permanently deletes the finalized capture and any export archive stored for it from this device. A copy already inside a device backup is managed by the system."
                )
            case .excludedFromBackup:
                base = String(
                    localized:
                        "This permanently deletes the finalized capture and any export archive stored for it from this device. Nothing is uploaded or backed up by this app."
                )
            }
        }
        // Lineage-aware deletion (issue #396): a revision that still
        // has descendants naming it parent gets the extra warning.
        if pending.descendantCount > 0 {
            base += " " + captureCountPhrase(
                pending.descendantCount,
                singular: String(
                    localized: "%lld revision declares it as its parent — its lineage link will no longer resolve."
                ),
                plural: String(
                    localized: "%lld revisions declare it as their parent — their lineage links will no longer resolve."
                )
            )
        }
        // Retention warnings (#394): receipts, mission links, and
        // only-local-copy are advisory context, not blocks.
        for warning in pending.warnings {
            base += " " + warning.deletionSummary
        }
        return base
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
    /// destinations present the system sheet (receipt recorded when
    /// the sheet reports its outcome); endpoint destinations POST
    /// through the client (#225).
    private func selectHandoffDestination(
        _ destination: HTDTHandoffDestination
    ) {
        handoffDestinationsShown = false
        if destination.kind == .shareSheet {
            shareArchiveForHandoff = true
        } else {
            Task {
                await actions.sendCaptureToHTDT(destination, nil)
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
                .foregroundStyle(CaptureColorRole.success.color)
            case .compatibleWithOmissions(let gaps):
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "Compatible with omissions",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(CaptureColorRole.attention.color)
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
                    .foregroundStyle(CaptureColorRole.blocked.color)
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
    /// receipt records the outcome the sheet actually reported —
    /// `delivered` only when an activity completed (#225).
    private func recordShareSheetHandoff(
        completed: Bool,
        error: Error?
    ) {
        guard let destination = handoffDestinations.first(
            where: { $0.kind == .shareSheet }
        ) else {
            return
        }
        let outcome: HTDTShareSheetOutcome
        if let error {
            outcome = .failed(error.localizedDescription)
        } else if completed {
            outcome = .completed
        } else {
            outcome = .cancelled
        }
        Task {
            await actions.sendCaptureToHTDT(destination, outcome)
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

}
