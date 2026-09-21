import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
import HTDTCapturePlatform

public struct CaptureRootActions {
    public let beginCapture: () -> Void
    public let beginReview: () -> Void
    public let captureEvidenceFrame: () -> Void
    public let setScanMovementCapability:
        (ScanMovementCapability) -> Void
    public let continueScanning: () -> Void
    public let beginAnnotation: () -> Void
    public let captureRaycastPlacement:
        () async throws -> AnnotationPlacementAuthority
    public let captureSpeakerOrientation:
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
    public let commitAnnotationAuthority: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement],
        [EquipmentIdentityRecord]
    ) -> Void
    public let cancelAnnotation: () -> Void
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

    public init(
        beginCapture: @escaping () -> Void = {},
        beginReview: @escaping () -> Void = {},
        captureEvidenceFrame: @escaping () -> Void = {},
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
        commitAnnotationAuthority: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement],
            [EquipmentIdentityRecord]
        ) -> Void = { _, _, _ in },
        cancelAnnotation: @escaping () -> Void = {},
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
        importCaptureArchive: @escaping (URL) -> Void = { _ in }
    ) {
        self.beginCapture = beginCapture
        self.beginReview = beginReview
        self.captureEvidenceFrame = captureEvidenceFrame
        self.setScanMovementCapability =
            setScanMovementCapability
        self.continueScanning = continueScanning
        self.beginAnnotation = beginAnnotation
        self.captureRaycastPlacement = captureRaycastPlacement
        self.captureSpeakerOrientation =
            captureSpeakerOrientation
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureIdentityPhoto = captureIdentityPhoto
        self.commitAnnotationAuthority =
            commitAnnotationAuthority
        self.cancelAnnotation = cancelAnnotation
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
    }
}

/// The pending delete-local-capture confirmation: which validated
/// revision is selected and whether its canonical export slot exists.
private struct PendingCaptureDeletion {
    let revisionID: CaptureRevisionID
    let includesExport: Bool
}

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let lastFailure: CaptureFailureCode?
    public let workingSetStatus: String?
    public let qualityReport: CaptureQualityReport?
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
    public let persistedInventory:
        PersistedCaptureInventoryResult
    public let actions: CaptureRootActions

    @State private var pendingDeletion:
        PendingCaptureDeletion?
    @State private var importingCaptureArchive = false

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        lastFailure: CaptureFailureCode? = nil,
        workingSetStatus: String? = nil,
        qualityReport: CaptureQualityReport? = nil,
        validationReport: BundleValidationReport? = nil,
        exportURL: URL? = nil,
        annotationCoordinateSpaceID: CoordinateSpaceID? = nil,
        annotationEvidenceRefs: [String] = [],
        annotationAuthorityCommitted: Bool = false,
        annotationRevisionSeed: AnnotationWorkspaceSeed? = nil,
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
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
        persistedInventory:
            PersistedCaptureInventoryResult
                = PersistedCaptureInventoryResult(),
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.state = state
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.lastFailure = lastFailure
        self.workingSetStatus = workingSetStatus
        self.qualityReport = qualityReport
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
        self.persistedInventory = persistedInventory
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
                    captureEvidenceFrame:
                        actions.captureEvidenceFrame,
                    setMovementCapability:
                        actions.setScanMovementCapability,
                    endScan: actions.beginReview
                )
            } else {
                NavigationStack {
            if state == .annotating,
               let coordinateSpaceID =
                    annotationCoordinateSpaceID
            {
                CaptureAnnotationWorkspaceView(
                    coordinateSpaceID: coordinateSpaceID,
                    availableEvidenceRefs:
                        annotationEvidenceRefs,
                    evidenceFrames: annotationEvidenceFrames,
                    statusMessage: workingSetStatus,
                    seed: annotationRevisionSeed,
                    replacesCommittedAuthority:
                        annotationAuthorityCommitted,
                    equipmentCatalog: equipmentCatalog,
                    // The same shared AR surface renders inside the
                    // camera capture sheets — no second session
                    // (#214).
                    cameraPreview: scanningPreview,
                    probePlacementTarget:
                        actions.probePlacementTarget,
                    probeCameraHeading:
                        actions.probeCameraHeading,
                    captureTargetedPlacement:
                        actions.captureTargetedPlacement,
                    captureSpeakerOrientation:
                        actions.captureSpeakerOrientation,
                    captureIdentityPhoto:
                        actions.captureIdentityPhoto,
                    roomPlanObjects: annotationRoomPlanObjects,
                    plausibilityContext:
                        annotationPlausibilityContext,
                    equipmentRecents: equipmentRecents,
                    speakerLayoutPlans: speakerLayoutPlans,
                    draftStore: annotationDraftStore,
                    draftRevisionID: annotationDraftRevisionID,
                    onImportEquipmentCatalog:
                        actions.importEquipmentCatalog,
                    onCommit:
                        actions.commitAnnotationAuthority,
                    onCancel: actions.cancelAnnotation
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
                                spatialFindings:
                                    spatialPlausibilityFindings
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
                    }
                }

                if state == .idle,
                   !persistedInventory.captures.isEmpty
                       || !persistedInventory
                           .quarantinedArtifacts.isEmpty
                       || !persistedInventory
                           .enumerationFailures.isEmpty
                {
                    Section("Persisted captures") {
                        ForEach(persistedInventory.captures) {
                            record in
                            persistedCaptureRow(record)
                        }
                        ForEach(
                            persistedInventory
                                .quarantinedArtifacts
                        ) { artifact in
                            quarantinedArtifactRow(artifact)
                        }
                        ForEach(
                            persistedInventory
                                .enumerationFailures,
                            id: \.self
                        ) { failure in
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

        case .paused:
            Text(
                "The host app does not enter a pseudo-paused RoomPlan state. Ending RoomPlan creates a scan boundary."
            )

        case .reviewing:
            if annotationCoordinateSpaceID != nil {
                if !annotationAuthorityCommitted {
                    Button(
                        "Continue scanning",
                        action: actions.continueScanning
                    )
                    Button(
                        "Add annotations & measurements",
                        action: actions.beginAnnotation
                    )
                } else {
                    Text("Annotation authority saved.")
                    Button(
                        "Edit saved annotations & measurements",
                        action: actions.beginAnnotation
                    )
                }
            } else if annotationAuthorityCommitted {
                Text("Annotation authority saved.")
            }

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
            Button(
                "Start new capture",
                action: actions.resetCapture
            )
            Button(
                "Revise this capture",
                action: actions.reviseAdoptedCapture
            )
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
                    "Validated .htdtcapture archive is ready to share."
                )
                Button(
                    "Start new capture",
                    action: actions.resetCapture
                )
                Button(
                    "Revise this capture",
                    action: actions.reviseAdoptedCapture
                )
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
    }

    @ViewBuilder
    private func persistedCaptureRow(
        _ record: PersistedCaptureRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.captureRevisionID.description)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            if let validation = record.finalizedValidation {
                LabeledContent(
                    "Finalized",
                    value: record.finalizedAtUTC
                )
                LabeledContent(
                    "Payloads",
                    value: String(validation.payloadCount)
                )
            } else {
                Text("Export archive only")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if record.canOpen {
                    Button("Open") {
                        actions.openPersistedCapture(
                            record.captureRevisionID
                        )
                    }
                }
                if record.canOpen || record.exportArchive != nil {
                    Button("Revise") {
                        actions.revisePersistedCapture(
                            record
                        )
                    }
                }
                if let archive = record.exportArchive {
                    ShareLink(item: archive) {
                        Label(
                            "Share",
                            systemImage:
                                "square.and.arrow.up"
                        )
                    }
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

    private func localizedState(_ state: CaptureState) -> String {
        switch state {
        case .idle:
            return String(localized: "Idle")
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
