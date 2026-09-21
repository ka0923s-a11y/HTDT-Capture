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
    public let commitAnnotationAuthority: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement]
    ) -> Void
    public let cancelAnnotation: () -> Void
    /// Operator capture-task profile selection (#217/#259): sets the
    /// capture intent plus optional skipped-requirement outcome.
    public let selectTaskProfile:
        (CaptureTaskProfile?, Set<String>) -> Void
    /// Validates and adopts an imported HTDT equipment-catalog snapshot
    /// (#211). The host owns the catalog context for the app session and
    /// mirrors it to a durable app-support cache; the default simply
    /// decodes through the validating initializer without persisting.
    public let importEquipmentCatalog:
        (Data) throws -> HTDTEquipmentCatalogSnapshot
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
    /// Independent export-archive deletion (#251).
    public let deleteExportArchive:
        (PersistedCaptureRecord) -> Void
    /// App-local library metadata (names, notes, series grouping)
    /// (#219).
    public let updateLibraryEntry:
        (CaptureRevisionID?, CaptureSeriesID?,
         CaptureLibraryEntryMetadata) -> Void

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
        commitAnnotationAuthority: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement]
        ) -> Void = { _, _ in },
        cancelAnnotation: @escaping () -> Void = {},
        selectTaskProfile: @escaping
            (CaptureTaskProfile?, Set<String>) -> Void
                = { _, _ in },
        importEquipmentCatalog: @escaping
            (Data) throws -> HTDTEquipmentCatalogSnapshot = { data in
                try JSONDecoder().decode(
                    HTDTEquipmentCatalogSnapshot.self,
                    from: data
                )
            },
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
        deleteExportArchive: @escaping
            (PersistedCaptureRecord) -> Void = { _ in },
        updateLibraryEntry: @escaping (
            CaptureRevisionID?,
            CaptureSeriesID?,
            CaptureLibraryEntryMetadata
        ) -> Void = { _, _, _ in }
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
        self.commitAnnotationAuthority =
            commitAnnotationAuthority
        self.cancelAnnotation = cancelAnnotation
        self.selectTaskProfile = selectTaskProfile
        self.importEquipmentCatalog = importEquipmentCatalog
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
        self.deleteExportArchive = deleteExportArchive
        self.updateLibraryEntry = updateLibraryEntry
    }
}

/// The pending delete-local-capture confirmation: which validated
/// revision is selected and whether its canonical export slot exists.
private struct PendingCaptureDeletion {
    let revisionID: CaptureRevisionID
    let includesExport: Bool
}

/// Identifiable target for the library-metadata editor sheet (#219):
/// exactly one of `revisionID`/`seriesID` is set.
private struct LibraryMetadataEditorTarget: Identifiable {
    let revisionID: CaptureRevisionID?
    let seriesID: CaptureSeriesID?
    var id: String {
        revisionID?.description
            ?? seriesID?.description
            ?? "editor"
    }
}

/// Edits an operator-facing name + note for a capture revision or a
/// whole series (#219). App-local metadata only — the capture bundle
/// on disk is never touched.
private struct LibraryMetadataEditor: View {
    let revisionID: CaptureRevisionID?
    let seriesID: CaptureSeriesID?
    let document: CaptureLibraryMetadataDocument
    let onSave:
        (CaptureRevisionID?, CaptureSeriesID?,
         CaptureLibraryEntryMetadata) -> Void

    @State private var displayName: String
    @State private var note: String
    @Environment(\.dismiss) private var dismiss

    init(
        revisionID: CaptureRevisionID?,
        seriesID: CaptureSeriesID?,
        document: CaptureLibraryMetadataDocument,
        onSave: @escaping (
            CaptureRevisionID?,
            CaptureSeriesID?,
            CaptureLibraryEntryMetadata
        ) -> Void
    ) {
        self.revisionID = revisionID
        self.seriesID = seriesID
        self.document = document
        self.onSave = onSave
        let existing = revisionID.flatMap {
            document.revisions[$0.description]
        } ?? seriesID.flatMap {
            document.series[$0.description]
        }
        _displayName = State(
            initialValue: existing?.displayName ?? ""
        )
        _note = State(
            initialValue: existing?.note ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Room or project name", text: $displayName)
                TextField(
                    "Notes",
                    text: $note,
                    axis: .vertical
                )
            }
            .navigationTitle("Capture details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            revisionID,
                            seriesID,
                            CaptureLibraryEntryMetadata(
                                displayName: displayName.isEmpty
                                    ? nil
                                    : displayName,
                                note: note.isEmpty ? nil : note
                            )
                        )
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
    public let annotationAuthorityCommitted: Bool
    /// Reloaded canonical authority used to seed a pre-finalization
    /// correction pass through the annotation workspace (#163).
    public let annotationRevisionSeed: AnnotationWorkspaceSeed?
    /// Host-owned HTDT equipment-catalog reference context for the
    /// annotation workspace (#211). Survives annotation cancel → Review
    /// → re-enter and relaunch; never part of capture-bundle authority.
    public let equipmentCatalog: HTDTEquipmentCatalogSnapshot?
    /// Identity of the live working revision; carries the
    /// series/parent linkage for a revise-existing capture (#155).
    public let workingSetIdentity: CaptureWorkingSetIdentity?
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
    /// Committed evidence references dangling after a re-End (#236).
    public let danglingSpatialIssues: [SpatialEvidenceIssue]
    /// Operator-visible Send-to-HTDT destinations + receipts (#225).
    public let handoffDestinations: [HTDTHandoffDestination]
    public let handoffReceipts: [HTDTHandoffReceipt]
    /// App-local capture names/notes/series metadata (#219).
    public let libraryMetadata: CaptureLibraryMetadataDocument
    /// Retained-evidence inspection for a failed capture (#224).
    public let failedInspection: FailedCaptureInspection?
    /// Spatial authority sealed for finalization (#276).
    public let spatialCaptureSealed: Bool
    public let actions: CaptureRootActions

    @State private var pendingDeletion:
        PendingCaptureDeletion?
    @State private var importingCaptureArchive = false
    @State private var confirmingDiscard = false
    @State private var reviewWorkspaceShown = false
    @State private var persistedViewerShown = false
    @State private var handoffDestinationsShown = false
    @State private var shareArchiveForHandoff = false
    @State private var revisionComparison:
        CaptureRevisionComparison?
    @State private var comparisonLoading = false
    @State private var metadataEditorTarget:
        LibraryMetadataEditorTarget?
    @State private var libraryQuery = ""
    @State private var diagnosticShareURL: URL?

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
        annotationEvidenceRefs: [String] = [],
        annotationAuthorityCommitted: Bool = false,
        annotationRevisionSeed: AnnotationWorkspaceSeed? = nil,
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        workingSetIdentity: CaptureWorkingSetIdentity? = nil,
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
        persistedInventory:
            PersistedCaptureInventoryResult
                = PersistedCaptureInventoryResult(),
        reviewWorkspace: CaptureReviewWorkspaceModel? = nil,
        persistedWorkspace: CaptureReviewWorkspaceModel? = nil,
        roomFrameOriginPending: WorldPoint3D? = nil,
        danglingSpatialIssues: [SpatialEvidenceIssue] = [],
        handoffDestinations: [HTDTHandoffDestination] = [],
        handoffReceipts: [HTDTHandoffReceipt] = [],
        libraryMetadata: CaptureLibraryMetadataDocument
            = CaptureLibraryMetadataDocument(),
        failedInspection: FailedCaptureInspection? = nil,
        spatialCaptureSealed: Bool = false,
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
        self.annotationEvidenceRefs = annotationEvidenceRefs
        self.annotationAuthorityCommitted =
            annotationAuthorityCommitted
        self.annotationRevisionSeed = annotationRevisionSeed
        self.equipmentCatalog = equipmentCatalog
        self.workingSetIdentity = workingSetIdentity
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
        self.persistedInventory = persistedInventory
        self.reviewWorkspace = reviewWorkspace
        self.persistedWorkspace = persistedWorkspace
        self.roomFrameOriginPending = roomFrameOriginPending
        self.danglingSpatialIssues = danglingSpatialIssues
        self.handoffDestinations = handoffDestinations
        self.handoffReceipts = handoffReceipts
        self.libraryMetadata = libraryMetadata
        self.failedInspection = failedInspection
        self.spatialCaptureSealed = spatialCaptureSealed
        self.actions = actions
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
                    lowLightGuidanceActive: lowLightGuidanceActive,
                    targetScanStatus: targetScanStatus,
                    declaredRegions: declaredRegions,
                    loopClosureCheckActive: loopClosureCheckActive,
                    loopClosureAssessment: loopClosureAssessment,
                    guidanceCuesEnabled: guidanceCuesEnabled,
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
            } else {
                NavigationStack {
            if state == .setup,
               let captureSetup
            {
                CaptureSetupView(
                    presentation: captureSetup,
                    beginScanning: actions.beginScanning,
                    cancel: actions.cancelCaptureSetup
                )
            } else if state == .annotating,
               let coordinateSpaceID =
                    annotationCoordinateSpaceID
            {
                CaptureAnnotationWorkspaceView(
                    coordinateSpaceID: coordinateSpaceID,
                    availableEvidenceRefs:
                        annotationEvidenceRefs,
                    statusMessage: workingSetStatus,
                    seed: annotationRevisionSeed,
                    replacesCommittedAuthority:
                        annotationAuthorityCommitted,
                    equipmentCatalog: equipmentCatalog,
                    captureRaycastPlacement:
                        actions.captureRaycastPlacement,
                    captureSpeakerOrientation:
                        actions.captureSpeakerOrientation,
                    capturePointOrientation:
                        actions.capturePointOrientation,
                    onImportEquipmentCatalog:
                        actions.importEquipmentCatalog,
                    taskProfile: taskProfile,
                    onSelectTaskProfile:
                        actions.selectTaskProfile,
                    onCommit:
                        actions.commitAnnotationAuthority,
                    onCancel: actions.cancelAnnotation,
                    onDiscard: {
                        confirmingDiscard = true
                    }
                )
                .navigationTitle("Capture authority")
            } else {
                List {
                Section("Capture") {
                    LabeledContent(
                        "State",
                        value: localizedState(state)
                    )
                    if let cameraPermission {
                        LabeledContent(
                            "Camera permission",
                            value: localizedPermission(
                                cameraPermission
                            )
                        )
                    }
                    if let workingSetStatus {
                        LabeledContent(
                            "Working set",
                            value: workingSetStatus
                        )
                    }
                    if let lastFailure {
                        LabeledContent(
                            "Failure",
                            value: localizedFailure(lastFailure)
                        )
                    }
                    if let identity = workingSetIdentity,
                       let parent = identity.parentRevisionID
                    {
                        LabeledContent(
                            "Series",
                            value: identity
                                .captureSeriesID.description
                        )
                        LabeledContent(
                            "Revises",
                            value: parent.description
                        )
                    }
                }

                Section("Capabilities") {
                    LabeledContent(
                        "RoomPlan + mesh",
                        value: localizedAvailability(
                            capabilities.roomPlanMeshEligible
                        )
                    )
                    LabeledContent(
                        "Scene depth",
                        value: localizedAvailability(
                            capabilities.sceneDepthSupported
                        )
                    )
                    if capabilities.requiresCombinedFeatureProbe {
                        Text(
                            "Combined RoomPlan/depth behavior still requires physical-device verification."
                        )
                    }
                }

                Section("Controls") {
                    controls
                }

                if state == .failed,
                   let lastFailure
                {
                    Section("Recovery") {
                        Text(
                            failureReasonText(lastFailure)
                        )
                        .font(.headline)

                        Text(
                            failureRecoveryText(lastFailure)
                        )
                        .foregroundStyle(.secondary)
                    }

                    if let failedInspection {
                        failedInspectionSection(
                            failedInspection
                        )
                    }
                }

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

                if state == .reviewing,
                   let qualityReport
                {
                    Section("Quality") {
                        LabeledContent(
                            "HTDT ingestion",
                            value: localizedReadiness(
                                qualityReport.readyForHTDTIngestion
                            )
                        )
                        LabeledContent(
                            "Integrity preflight",
                            value: localizedIntegrity(
                                qualityReport.integrityStatus
                            )
                        )
                        NavigationLink("Review diagnostics") {
                            CaptureReviewView(
                                quality: qualityReport,
                                advisory: advisoryReport
                            )
                        }
                    }
                }

                if (state == .finalized || state == .exported),
                   let validationReport
                {
                    Section("Finalized bundle") {
                        LabeledContent(
                            "Validator",
                            value: localizedPassFail(
                                validationReport.valid
                            )
                        )
                        Text(validationReport.bundleDigest.description)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        LabeledContent(
                            "Series",
                            value: validationReport.manifest
                                .captureSeriesID.description
                        )
                        if let parent =
                            validationReport.manifest
                                .parentRevisionID
                        {
                            LabeledContent(
                                "Revises",
                                value: parent.description
                            )
                        }
                        if let qualityReport {
                            NavigationLink(
                                "Review finalized capture"
                            ) {
                                CaptureReviewView(
                                    quality: qualityReport,
                                    advisory: advisoryReport,
                                    validation: validationReport
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
                    }
                }

                if state == .idle,
                   !persistedInventory.captures.isEmpty
                       || !persistedInventory
                           .quarantinedArtifacts.isEmpty
                       || !persistedInventory
                           .enumerationFailures.isEmpty
                {
                    captureLibrarySection
                }

                if state == .idle,
                   !persistedInventory
                       .orphanedWorkingArtifacts.isEmpty
                {
                    Section("Abandoned working data") {
                        ForEach(
                            persistedInventory
                                .orphanedWorkingArtifacts
                        ) { orphan in
                            workingOrphanRow(orphan)
                        }
                        Text(
                            "Left by an interrupted capture. It is never resumed as an active scan and can be safely deleted."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
                .navigationTitle("HTDT Capture")
                .navigationDestination(
                    isPresented: $reviewWorkspaceShown
                ) {
                    if let reviewWorkspace {
                        CaptureReviewWorkspaceView(
                            model: reviewWorkspace,
                            roomFrameOriginPending:
                                roomFrameOriginPending,
                            removeEvidenceFrame: actions
                                .removeEvidenceFrameForPrivacy,
                            openingReviewCandidates: actions
                                .openingReviewCandidates,
                            commitOpeningReview: actions
                                .commitOpeningReview,
                            captureRoomFrameOrigin: actions
                                .captureRoomFrameOrigin,
                            confirmRoomReferenceFrame: actions
                                .confirmRoomReferenceFrame
                        )
                    } else {
                        ProgressView("Loading workspace…")
                    }
                }
                .navigationDestination(
                    isPresented: $persistedViewerShown
                ) {
                    if let persistedWorkspace {
                        CaptureReviewWorkspaceView(
                            model: persistedWorkspace
                        )
                    } else {
                        ProgressView("Loading capture…")
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
                                    Button(destination.name) {
                                        selectHandoffDestination(
                                            destination
                                        )
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
                .sheet(item: $metadataEditorTarget) { target in
                    LibraryMetadataEditor(
                        revisionID: target.revisionID,
                        seriesID: target.seriesID,
                        document: libraryMetadata,
                        onSave: actions.updateLibraryEntry
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
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .idle:
            Button("Start capture", action: actions.beginCapture)
                .disabled(!capabilities.roomPlanMeshEligible)

        case .setup:
            EmptyView()
            Button("Import .htdtcapture") {
                importingCaptureArchive = true
            }

        case .capabilityCheck:
            progressRow("Checking device capabilities…")

        case .permissions:
            progressRow("Requesting camera permission…")

        case .preparing:
            progressRow("Preparing capture working set…")

        case .scanning:
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
            Button("Open review workspace") {
                actions.refreshReviewWorkspace()
                reviewWorkspaceShown = true
            }

            if annotationCoordinateSpaceID != nil {
                // Saved annotations/measurements survive a reopen
                // while the same coordinate authority is still valid
                // (#236), so Continue stays available after a saved
                // annotation pass.
                Button(
                    "Continue scanning",
                    action: actions.continueScanning
                )
                if !annotationAuthorityCommitted {
                    Button(
                        "Add annotations & measurements",
                        action: actions.beginAnnotation
                    )
                } else {
                    Text("Annotation authority saved.")
                    Button(
                        spatialCaptureSealed
                            ? "Edit labels, roles, equipment, and values"
                            : "Edit saved annotations & measurements",
                        action: actions.beginAnnotation
                    )
                }
            } else if annotationAuthorityCommitted {
                Text("Annotation authority saved.")
                Button(
                    "Edit labels, roles, equipment, and values",
                    action: actions.beginAnnotation
                )
            }
            discardButton

            if let qualityReport {
                Button(
                    "Validate and finalize",
                    action: actions.finalizeCapture
                )
                .disabled(
                    !qualityReport.readyForHTDTIngestion
                    || qualityReport.integrityStatus != .pass
                )
            } else {
                progressRow("Waiting for persisted evidence…")
            }

        case .failed:
            Button(
                "Inspect retained evidence",
                action: actions.inspectFailedCapture
            )
            Button("Export diagnostic package") {
                Task {
                    diagnosticShareURL =
                        await actions
                            .exportFailedCaptureDiagnostics()
                }
            }
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
            Button(
                "Discard failed capture",
                role: .destructive,
                action: actions.resetCapture
            )

        case .annotating:
            EmptyView()

        case .validating:
            progressRow("Validating and finalizing capture…")

        case .finalized:
            Button(
                "Prepare .htdtcapture",
                action: actions.prepareExport
            )
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
            }

        case .exported:
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Validated .htdtcapture archive is ready to send to HTDT. Nothing uploads automatically."
                )
                Button("Send to HTDT…") {
                    handoffDestinationsShown = true
                }
                Button("Share .htdtcapture") {
                    shareArchiveForHandoff = true
                }
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
            }
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
            .disabled(comparisonLoading)
        }
        Button(
            "Rescan as new revision",
            action: actions.reviseAdoptedCapture
        )
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

    /// The capture library (#219/#251): series grouping, names/notes,
    /// search, and per-revision storage breakdown. Extracted so the
    /// type-checker stays inside its budget.
    @ViewBuilder
    private var captureLibrarySection: some View {
        Section("Capture library") {
            LabeledContent(
                "Total storage",
                value: String(
                    persistedInventory.totalRetainedBytes
                )
            )
            TextField(
                "Search captures",
                text: $libraryQuery
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }

        ForEach(
            libraryGroups.filter {
                CaptureSeriesGrouper.matches(
                    group: $0,
                    revisionNotes: revisionNotesByID,
                    query: libraryQuery
                )
            }
        ) { group in
            Section(seriesTitle(group)) {
                Button("Edit series name") {
                    metadataEditorTarget =
                        LibraryMetadataEditorTarget(
                            revisionID: nil,
                            seriesID: group.captureSeriesID
                        )
                }
                .font(.caption)
                ForEach(group.revisions) { record in
                    persistedCaptureRow(record)
                }
            }
        }

        if !persistedInventory.quarantinedArtifacts.isEmpty
            || !persistedInventory.enumerationFailures.isEmpty
        {
            Section("Inventory issues") {
                ForEach(
                    persistedInventory.quarantinedArtifacts
                ) { artifact in
                    quarantinedArtifactRow(artifact)
                }
                ForEach(
                    persistedInventory.enumerationFailures,
                    id: \.self
                ) { failure in
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Series-grouped view of the persisted inventory (#219).
    private var libraryGroups: [CaptureSeriesGroup] {
        CaptureSeriesGrouper.group(
            records: persistedInventory.captures,
            metadata: libraryMetadata
        )
    }

    private var revisionNotesByID:
        [String: CaptureLibraryEntryMetadata]
    {
        libraryMetadata.revisions
    }

    private func seriesTitle(
        _ group: CaptureSeriesGroup
    ) -> String {
        if let name = group.displayName, !name.isEmpty {
            return name
        }
        return String(
            localized: "Series "
        ) + group.captureSeriesID.description
    }

    @ViewBuilder
    private func persistedCaptureRow(
        _ record: PersistedCaptureRecord
    ) -> some View {
        let entry = libraryMetadata.revisions[
            record.captureRevisionID.description
        ]
        VStack(alignment: .leading, spacing: 6) {
            if let name = entry?.displayName, !name.isEmpty {
                Text(name).font(.headline)
            }
            Text(record.captureRevisionID.description)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            if let note = entry?.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validation = record.finalizedValidation {
                LabeledContent(
                    "Finalized",
                    value: record.finalizedAtUTC
                )
                LabeledContent(
                    "Payloads",
                    value: String(validation.payloadCount)
                )
                LabeledContent(
                    "Finalized bytes",
                    value: String(
                        record.finalizedByteCount ?? 0
                    )
                )
            } else {
                Text("Export archive only")
                    .foregroundStyle(.secondary)
            }
            if record.exportArchive != nil {
                LabeledContent(
                    "Archive bytes",
                    value: String(
                        record.exportArchiveByteCount ?? 0
                    )
                )
                if record.exportArchiveIsDerivedCopy {
                    Text(
                        "Archive is a derived copy of the finalized bundle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            LabeledContent(
                "Retained bytes",
                value: String(record.retainedByteCount)
            )

            HStack(spacing: 16) {
                if record.canOpen {
                    Button("View") {
                        actions.loadPersistedWorkspace(record)
                        persistedViewerShown = true
                    }
                    Button("Adopt") {
                        actions.openPersistedCapture(
                            record.captureRevisionID
                        )
                    }
                }
                if record.canOpen || record.exportArchive != nil {
                    Button("Rescan") {
                        actions.revisePersistedCapture(
                            record
                        )
                    }
                }
                Button("Edit name") {
                    metadataEditorTarget =
                        LibraryMetadataEditorTarget(
                            revisionID: record.captureRevisionID,
                            seriesID: nil
                        )
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    pendingDeletion = PendingCaptureDeletion(
                        revisionID: record.captureRevisionID,
                        includesExport:
                            record.exportArchive != nil
                    )
                }
            }
            if record.exportArchive != nil,
               record.finalizedDirectory != nil
            {
                // The archive is a derived copy: it can be deleted
                // without touching the canonical finalized capture
                // (#251).
                Button("Delete archive only") {
                    actions.deleteExportArchive(record)
                }
                .font(.caption)
            }
        }
    }

    private func workingOrphanRow(
        _ orphan: PersistedCaptureWorkingOrphan
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                orphan.kind == .abandonedRevision
                    ? String(localized: "Abandoned revision")
                    : String(localized: "Writer temp file"),
                value: orphan.url.lastPathComponent
            )
            LabeledContent(
                "Retained bytes",
                value: String(orphan.retainedBytes)
            )
            Button("Delete", role: .destructive) {
                actions.removeWorkingOrphan(orphan)
            }
        }
    }

    private func quarantinedArtifactRow(
        _ artifact: PersistedCaptureQuarantinedArtifact
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                "Unreadable artifact",
                value: artifact.url.lastPathComponent
            )
            Text(artifact.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Remove artifact", role: .destructive) {
                actions.removeQuarantinedArtifact(artifact)
            }
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

    private func localizedPermission(
        _ status: CameraPermissionStatus
    ) -> String {
        switch status {
        case .notDetermined:
            return String(localized: "Not determined")
        case .authorized:
            return String(localized: "Authorized")
        case .denied:
            return String(localized: "Denied")
        case .restricted:
            return String(localized: "Restricted")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    private func localizedFailure(_ failure: CaptureFailureCode) -> String {
        switch failure {
        case .permissionDenied:
            return String(localized: "Permission denied")
        case .unsupportedDevice:
            return String(localized: "Unsupported device")
        case .trackingUnavailable:
            return String(localized: "Tracking unavailable")
        case .roomPlanFailure:
            return String(localized: "RoomPlan failure")
        case .storagePressure:
            return String(localized: "Storage pressure")
        case .persistenceFailure:
            return String(localized: "Persistence failure")
        case .thermalPressure:
            return String(localized: "Thermal pressure")
        case .interrupted:
            return String(localized: "Interrupted")
        case .unknown:
            return String(localized: "Unknown error")
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

    private func localizedAvailability(_ available: Bool) -> String {
        available
            ? String(localized: "Available")
            : String(localized: "Unavailable")
    }

    private func localizedReadiness(_ ready: Bool) -> String {
        ready
            ? String(localized: "Ready")
            : String(localized: "Not ready")
    }

    private func localizedPassFail(_ pass: Bool) -> String {
        pass
            ? String(localized: "Pass")
            : String(localized: "Fail")
    }

    private func localizedIntegrity(
        _ status: BundleIntegrityStatus
    ) -> String {
        switch status {
        case .notChecked:
            return String(localized: "Not checked")
        case .pass:
            return String(localized: "Pass")
        case .fail:
            return String(localized: "Fail")
        }
    }
}
