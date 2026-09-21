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

    var body: some View {
        CaptureRootView(
            state: coordinator.state,
            capabilities: coordinator.capabilities,
            cameraPermission: coordinator.cameraPermission,
            lastFailure: coordinator.lastFailure,
            workingSetStatus: coordinator.workingSetStatus,
            qualityReport: coordinator.qualityReport,
            validationReport: coordinator.validationReport,
            exportURL: coordinator.exportURL,
            annotationCoordinateSpaceID:
                coordinator.annotationCoordinateSpaceID,
            annotationEvidenceRefs:
                coordinator.annotationEvidenceRefs,
            annotationAuthorityCommitted:
                coordinator.annotationAuthorityCommitted,
            annotationRevisionSeed:
                coordinator.annotationRevisionSeed,
            equipmentCatalog:
                coordinator.equipmentCatalog,
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
            persistedInventory:
                coordinator.persistedInventory,
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginReview: coordinator.beginReview,
                captureEvidenceFrame: coordinator.captureEvidenceFrame,
                setScanMovementCapability:
                    coordinator.setScanMovementCapability,
                continueScanning:
                    coordinator.continueScanningFromReview,
                beginAnnotation: coordinator.beginAnnotation,
                captureRaycastPlacement:
                    coordinator.captureRaycastPlacement,
                captureSpeakerOrientation:
                    coordinator.captureSpeakerOrientation,
                probePlacementTarget:
                    coordinator.probePlacementTarget,
                probeCameraHeading:
                    coordinator.probeCameraHeading,
                captureTargetedPlacement:
                    coordinator.captureTargetedPlacement,
                captureIdentityPhoto:
                    coordinator.captureIdentityPhoto,
                commitAnnotationAuthority:
                    coordinator.commitAnnotationAuthority,
                cancelAnnotation: coordinator.cancelAnnotation,
                importEquipmentCatalog:
                    coordinator.importEquipmentCatalog,
                finalizeCapture: coordinator.finalizeCapture,
                prepareExport: coordinator.prepareExport,
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
                    coordinator.importCaptureArchive
            )
        )
        .onOpenURL { url in
            coordinator.importCaptureArchive(from: url)
        }
    }
}

private enum HostLocalization {
    static var isJapanese: Bool {
        Locale.preferredLanguages.first?
            .lowercased()
            .hasPrefix("ja") == true
    }

    static func text(_ english: String, _ japanese: String) -> String {
        isJapanese ? japanese : english
    }
}

@MainActor
private final class HTDTCaptureHostCoordinator: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var capabilities: CaptureCapabilityMatrix
    @Published private(set) var cameraPermission: CameraPermissionStatus
    @Published private(set) var lastFailure: CaptureFailureCode?
    @Published private(set) var workingSetStatus =
        HostLocalization.text("Not prepared", "未準備")
    @Published private(set) var qualityReport: CaptureQualityReport?
    @Published private(set) var validationReport: BundleValidationReport?
    @Published private(set) var exportURL: URL?
    @Published private(set)
    var annotationAuthorityCommitted = false
    @Published private(set)
    var annotationEvidenceRefs: [String] = []
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
    @Published private(set)
    var persistedInventory = PersistedCaptureInventoryResult()
    /// Identity of the live working revision; carries the
    /// series/parent lineage so Review can show when a capture revises
    /// a stored finalized revision.
    @Published private(set)
    var workingSetIdentity: CaptureWorkingSetIdentity?
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
    private let equipmentCatalogCache =
        HTDTCaptureHostCoordinator.makeEquipmentCatalogCache()

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
    private var annotationRoomPlanObjectsLoaded = false

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var finalizedRevision: FinalizedCaptureRevision?
    private var resourceMonitor: CaptureResourceMonitor?
    private var resourceEventTask: Task<Void, Never>?
    private var captureGeneration = UUID()
    private var isEndingScan = false
    private var isCapturingEvidenceFrame = false
    /// Handle on the in-flight manual evidence-save persistence task.
    /// End drains it before sampling the working set so a committed
    /// save lands wholly before the End boundary (#179).
    private var evidenceFrameSaveTask: Task<Void, Never>?
    private var endScanPreflightBlocked = false
    private var captureStartTimingCorrelation:
        CaptureTimingCorrelation?
    private var acceptedRoomPlanRawSHA256: EvidenceSHA256?
    private var acceptedEndMeshWasPersisted = false
    private var pendingEndAttempt: PendingEndScanAttempt?
    private var roomPlanCompletionInFlight = false
    private var annotationCommitInFlight = false
    private var reviewOperationInFlight = false
    private var exportOperationInFlight = false
    private var spatialAuthoritySealedForFinalization = false
    /// Explicit commit-point policy for the finalization transaction
    /// (#185). While claimed, terminal lifecycle/resource failures are
    /// fenced instead of invalidating the capture generation; a fenced
    /// failure either cancels the transaction pre-promotion (no
    /// finalized destination produced) or is surfaced as post-capture
    /// status after the promoted revision is adopted (commit wins).
    private var finalizationCommit = FinalizationCommitPolicy()
    private var persistedStore: PersistedCaptureInventory?
    private var persistedInventoryRequest = 0
    private var persistedAdoptionInFlight = false
    private var persistedDeletionInFlight = false
    private var importOperationInFlight = false
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
    private var memoryWarningCancellable: AnyCancellable?
    private var derivedPreviewSuspendedForMemoryPressure = false
    private var roomPlanModelRenderingEnabled = true
    private let qualityRequirements = CaptureQualityRequirements(
        rulesetVersion: "1.1.0",
        allowDepthEvidenceAsMeshFallback: true
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

        // At-rest policy is applied before the first inventory scan so
        // the app-owned roots carry their backup/protection attributes
        // even when no capture has ever run (#136, #166). Failures are
        // surfaced in the status line rather than silently ignored.
        if let captureRoot = Self.captureRootDirectory() {
            let policyFailures =
                CaptureStoragePolicy.applyCaptureRootPolicy(
                    captureRoot: captureRoot
                )
            if !policyFailures.isEmpty {
                workingSetStatus =
                    HostLocalization.text(
                        "Storage protection policy was not fully applied to the capture roots",
                        "キャプチャの保存先への保護属性を完全に適用できませんでした"
                    )
                    + " ["
                    + policyFailures.joined(separator: "; ")
                    + "]"
            }
        }

        loadPersistedCaptures()

        // #211: restore the last validated equipment-catalog snapshot so
        // the operator's reference context survives relaunch. A missing
        // or no-longer-valid cache simply means the annotation workspace
        // asks for an explicit re-import; annotation authority already
        // committed in any capture is unaffected.
        equipmentCatalog = equipmentCatalogCache?.load()

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

    func beginCapture() {
        beginCapture(revisionLineage: nil)
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
        workingSetStatus = HostLocalization.text(
            "Revalidating the parent revision",
            "親リビジョンを再検証しています"
        )

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
                self.workingSetStatus = HostLocalization.text(
                    "The parent capture could not be revalidated; the on-disk inventory was refreshed",
                    "親キャプチャを再検証できませんでした。ディスク上の一覧を更新しました"
                )
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
        revisionLineage: RevisionLineage?
    ) {
        guard state == .idle else {
            return
        }

        activeRevisionLineage = revisionLineage
        workingSetIdentity = nil
        annotationRevisionSeed = nil
        annotationEditIsRevision = false
        qualityReport = nil
        validationReport = nil
        exportURL = nil
        finalizedRevision = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        acceptedEndMeshWasPersisted = false
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
        setRoomPlanModelRenderingEnabled(true)
        scanEvidenceFrameCount = 0
        scanDepthEvidenceCount = 0
        endScanGuidance = nil
        endScanPreflightBlocked = false
        scanTrackingTransitionGate.reset()
        resourceMonitor?.stop()
        resourceMonitor = nil
        resourceEventTask = nil

        do {
            try transition(.beginCapabilityCheck)
        } catch {
            fail(.unknown)
            return
        }

        Task {
            await continueBeginCapture()
        }
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
            workingSetStatus = HostLocalization.text(
                "Evidence frame was not captured because the current AR frame is temporarily unavailable; this scan is still active",
                "現在の AR フレームを一時的に取得できないため証拠フレームを保存しませんでした。現在のスキャンは継続中です"
            )
            endScanGuidance = HostLocalization.text(
                "Hold the phone steady on previously scanned features until tracking is normal, then retry Evidence Save or continue scanning.",
                "既に撮影した特徴へ向けて iPhone を静止し、トラッキングが正常になってから「証拠保存」を再試行するか、そのままスキャンを続けてください。"
            )
            return
        } catch {
            isCapturingEvidenceFrame = false
            workingSetStatus =
                HostLocalization.text(
                    "Evidence frame could not be prepared; this scan is still active",
                    "証拠フレームを準備できませんでしたが、現在のスキャンは継続中です"
                )
                + " ["
                + Self.persistenceDiagnostic(error)
                + "]"
            return
        }

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
                    HostLocalization.text(
                        "Evidence frame could not be prepared; this scan is still active",
                        "証拠フレームを準備できませんでしたが、現在のスキャンは継続中です"
                    )
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
                    HostLocalization.text(
                        "Evidence frame package could not be built; this scan is still active",
                        "証拠フレームのパッケージを作成できませんでしたが、現在のスキャンは継続中です"
                    )
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
                        HostLocalization.text(
                            "Evidence-frame persistence hit a capture-authority conflict and cannot continue safely",
                            "証拠フレームの保存でキャプチャ authority の競合が発生し、安全に継続できません"
                        )
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
                        HostLocalization.text(
                            "Evidence-frame persistence failed and partial canonical files could not be rolled back safely",
                            "証拠フレームの保存に失敗し、部分保存された正規データを安全に取り消せませんでした"
                        )
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
                    HostLocalization.text(
                        "Evidence frame was not committed; this scan is still active",
                        "証拠フレームは確定されませんでしたが、現在のスキャンは継続中です"
                    )
                    + " ["
                    + diagnostic
                    + "]"
                self.endScanGuidance = HostLocalization.text(
                    "Continue scanning or retry Evidence Save. End remains available after the required end evidence can be persisted.",
                    "スキャンを続けるか「証拠保存」を再試行してください。終了時に必要な証拠データを保存できれば、そのまま「終了」できます。"
                )
                return
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
            self.workingSetStatus =
                HostLocalization.isJapanese
                ? "スキャン中：証拠フレームを "
                    + String(snapshot.evidenceFrameCount)
                    + " 件保存しました"
                : "Scanning; "
                    + String(snapshot.evidenceFrameCount)
                    + " evidence frame(s) persisted"
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
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              !annotationAuthorityCommitted,
              !spatialAuthoritySealedForFinalization,
              acceptedRoomPlanRawSHA256 != nil,
              let store = workingSetStore
        else {
            return
        }

        reviewOperationInFlight = true
        let generation = captureGeneration
        let removeOwnedMesh = acceptedEndMeshWasPersisted
        workingSetStatus = HostLocalization.text(
            "Reopening this capture for additional scanning",
            "このキャプチャを追加スキャンのために再開しています"
        )

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation,
                  self.state == .reviewing
            else {
                return
            }

            do {
                try self.sessionController.startRoomPlan()
            } catch {
                self.reviewOperationInFlight = false
                self.workingSetStatus =
                    HostLocalization.text(
                        "RoomPlan could not resume additional scanning. The accepted Review evidence was kept intact; you can retry Continue scanning or finalize this capture.",
                        "RoomPlan で追加スキャンを再開できませんでした。受理済みの確認データはそのまま保持しています。「スキャンを続ける」を再試行するか、このキャプチャを確定できます。"
                    )
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
                    HostLocalization.text(
                        "RoomPlan restarted, but the accepted Review boundary could not be rolled back safely",
                        "RoomPlan は再開しましたが、受理済みの確認境界を安全に取り消せませんでした"
                    )
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
            self.endScanGuidance = HostLocalization.text(
                "Continue scanning the weak or missing areas, then press End again. Previously saved frame/depth evidence is retained.",
                "不足している場所を追加スキャンしてから、もう一度「終了」を押してください。以前に保存したフレーム／深度証拠は保持されています。"
            )
            self.startScanCoverageSampling(
                generation: generation,
                resetTrackers: false
            )
            self.workingSetStatus =
                HostLocalization.text(
                    "Scanning resumed in the same AR coordinate space",
                    "同じ AR 座標空間でスキャンを再開しました"
                )
        }
    }

    func beginAnnotation() {
        // Annotation editing is spatial continuation authority: once a
        // post-End resource/lifecycle condition sealed it (#112), the
        // accepted Review remains finalizable but the annotation
        // workspace must not reopen — its coordinate space is already
        // torn down, so an entry here could strand .annotating with no
        // rendered workspace or Cancel affordance.
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              !spatialAuthoritySealedForFinalization,
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
                    self.workingSetStatus = HostLocalization.text(
                        "The saved annotation authority could not be reloaded for editing; the committed files are unchanged",
                        "保存済みの注釈データを編集用に読み込めませんでした。確定済みのファイルは変更されていません"
                    )
                    return
                }

                self.committedIdentityDocData = loaded.1
                self.annotationRevisionSeed = loaded.0
                self.annotationEditIsRevision = true
                do {
                    try self.transition(.beginAnnotation)
                    self.workingSetStatus = HostLocalization.text(
                        "Correcting the saved annotations and measurements",
                        "保存済みの注釈と計測値を修正中"
                    )
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
           let spaceID = annotationCoordinateSpaceID
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
                    isRestoredDraft: true
                )
            }
        }
        annotationRevisionSeed = draftSeed
        annotationEditIsRevision = false
        do {
            try transition(.beginAnnotation)
            workingSetStatus = HostLocalization.text(
                draftSeed == nil
                    ? "Editing annotations and measurements"
                    : "Editing annotations and measurements — unsaved draft restored",
                draftSeed == nil
                    ? "注釈と計測値を編集中"
                    : "注釈と計測値を編集中 — 未保存の下書きを復元"
            )
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
        return (
            AnnotationWorkspaceSeed(
                annotations: annotations,
                measurements: measurements,
                equipmentIdentityRecords: identityRecords ?? []
            ),
            identityData
        )
    }

    func captureSpeakerOrientation()
        async throws -> AnnotationOrientationAuthority
    {
        guard state == .annotating,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let generation = captureGeneration
        let snapshot =
            try sessionController.snapshotHorizontalCameraHeading(
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
            upAxisLocal: .unit(0, 1, 0)
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
        workingSetStatus = HostLocalization.text(
            "Evidence-linked speaker heading captured",
            "証拠フレームに紐付いたスピーカー向きを取得しました"
        )

        return authority
    }

    func captureRaycastPlacement()
        async throws -> AnnotationPlacementAuthority
    {
        guard state == .annotating,
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
        workingSetStatus = HostLocalization.text(
            "Evidence-linked raycast placement captured",
            "証拠フレームに紐付いたレイキャスト位置を取得しました"
        )

        return authority
    }

    /// Live reticle probe for the camera capture sheet (#214):
    /// classifies what the shared session's center ray hits right now
    /// — mesh, RoomPlan object, or plane — with no side effects.
    func probePlacementTarget() async -> AnnotationPlacementProbe {
        guard state == .annotating else {
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
        workingSetStatus = HostLocalization.text(
            "Evidence-linked placement captured",
            "証拠フレームに紐付いた配置を取得しました"
        )
        return authority
    }

    /// Equipment-identity photo (#239): captures one plain evidence
    /// frame during annotation editing and returns its canonical
    /// `path:` ref so the form can bind it as identity evidence —
    /// distinct from spatial placement authority.
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
        workingSetStatus = HostLocalization.text(
            "Identity evidence photo captured",
            "機器識別の証拠写真を保存しました"
        )
        return evidenceRef
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
            workingSetStatus = HostLocalization.text(
                "Annotation authority is currently being saved. Wait for the save result before cancelling.",
                "注釈 authority を保存中です。保存結果が出るまで待ってからキャンセルしてください。"
            )
            return
        }
        // Cancel is an explicit draft-discard signal (#266): the
        // operator chose to abandon staged work, so the non-canonical
        // draft is removed rather than restored next time.
        discardAnnotationDraft()
        do {
            try transition(.beginReview)
            annotationRevisionSeed = nil
            annotationEditIsRevision = false
            workingSetStatus = HostLocalization.text(
                "Annotation editing cancelled; staged records not written",
                "注釈編集をキャンセルしました。未保存の項目は書き込まれていません"
            )
        } catch {
            fail(.unknown)
        }
    }

    func commitAnnotationAuthority(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        identityRecords: [EquipmentIdentityRecord]
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
        do {
            annotationPackage =
                try AnnotationEvidencePackageBuilder.build(
                    entities: annotations
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
                            annotationCoordinateSpaceID,
                        records: identityRecords,
                        entities: annotations
                    )
                )
        } catch {
            annotationCommitInFlight = false
            workingSetStatus =
                HostLocalization.text(
                    "Annotation or measurement authority is not internally valid; nothing was committed",
                    "注釈または計測 authority の内部検証に通りませんでした。データは確定されていません"
                )
                + " ["
                + Self.persistenceDiagnostic(error)
                + "]"
            return
        }

        let generation = captureGeneration
        workingSetStatus = HostLocalization.text(
            "Persisting annotation and measurement authority",
            "注釈と計測値を保存中"
        )

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
                            measurementPackage: measurementPackage
                        )
                } else {
                    try await store
                        .persistAnnotationAndMeasurementPackages(
                            annotationPackage: annotationPackage,
                            measurementPackage: measurementPackage
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

                // Commit consumed the draft (#266).
                self.discardAnnotationDraft()
                self.annotationAuthorityCommitted = true
                self.annotationCommitInFlight = false
                self.annotationEditIsRevision = false
                self.annotationRevisionSeed = nil
                try self.transition(.beginReview)
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
                            HostLocalization.text(
                                "The replacement could not be committed safely; the previously saved annotation and measurement collections remain. Cancel keeps the prior save.",
                                "置き換えを安全に確定できませんでした。以前に保存した注釈と計測値は保持されています。キャンセルすると以前の保存が保持されます。"
                            )
                            + " ["
                            + diagnostic
                            + "]"
                        return
                    }
                    self.workingSetStatus =
                        HostLocalization.text(
                            "Annotation authority could not be committed safely",
                            "注釈 authority を安全に確定できませんでした"
                        )
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
                    HostLocalization.text(
                        "Annotation changes were not committed; editing remains open and Save can be retried",
                        "注釈の変更は確定されていません。編集画面は保持されているため、保存を再試行できます"
                    )
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
        equipmentCatalog = snapshot
        // Best-effort durable mirror of the exact imported bytes. A
        // failure only means the next launch requires an explicit
        // re-import; the in-session context remains usable.
        _ = try? equipmentCatalogCache?.store(data)
        return snapshot
    }

    func finalizeCapture() {
        guard state == .reviewing,
              !isEndingScan,
              !reviewOperationInFlight,
              let store = workingSetStore
        else {
            return
        }

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
                self.workingSetStatus = HostLocalization.text(
                    "Finalization is deferred while the device is critically hot. Let it cool, then retry.",
                    "端末温度が危険な間は確定を延期します。端末を冷ましてから再試行してください。"
                )
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
                    self.workingSetStatus = HostLocalization.text(
                        "Finalization is deferred because storage is critically low. Free storage, then retry.",
                        "空き容量が危険域のため確定を延期します。空き容量を増やしてから再試行してください。"
                    )
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
                self.workingSetStatus = HostLocalization.text(
                    "Review quality changed before finalization; resolve the diagnostics and retry",
                    "確定直前に品質状態が変化しました。診断内容を確認して解消し、再試行してください"
                )
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
            self.workingSetStatus = HostLocalization.text(
                "Persisting quality and finalizing revision",
                "品質情報を保存し、リビジョンを確定中"
            )

            await self.performFinalization(
                store: store,
                quality: quality,
                generation: generation
            )
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

        exportOperationInFlight = true
        workingSetStatus = HostLocalization.text(
            "Creating validated .htdtcapture archive",
            "検証済み .htdtcapture アーカイブを作成中"
        )
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
                self.workingSetStatus =
                    HostLocalization.text(
                        "Archive destination could not be prepared. The finalized revision is preserved and export can be retried.",
                        "アーカイブの保存先を準備できませんでした。確定済みリビジョンは保持されているため、書き出しを再試行できます。"
                    )
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
                        self.workingSetStatus = HostLocalization.text(
                            "Existing validated archive recovered and is ready to share",
                            "既存の検証済みアーカイブを復旧し、共有できる状態にしました"
                        )
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
                        self.workingSetStatus =
                            HostLocalization.text(
                                "A stale export archive blocks rebuilding and could not be removed. The finalized revision is unchanged.",
                                "古い書き出しアーカイブが再作成を妨げていますが、削除できませんでした。確定済みリビジョン自体は変更されていません。"
                            )
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
                self.workingSetStatus = HostLocalization.text(
                    "Validated share-ready archive created",
                    "検証済みの共有用アーカイブを作成しました"
                )
                self.loadPersistedCaptures()
            } catch {
                guard self.captureGeneration == generation,
                      self.state == .finalized
                else {
                    return
                }

                self.workingSetStatus =
                    HostLocalization.text(
                        "Archive export failed. The finalized revision is preserved; retry export when ready.",
                        "アーカイブの書き出しに失敗しました。確定済みリビジョンは保持されているため、準備ができたら再試行してください。"
                    )
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
        }
    }

    func resetCapture() {
        guard state == .failed
                || state == .finalized
                || state == .exported
        else {
            return
        }

        let failedWorkingSet =
            state == .failed ? workingSetStore : nil
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
        // A failed/finalized revision's drafts are bound to it
        // forever; purge them (#266).
        annotationDraftStore?.discardAll()
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
        finalizationCommit.reset()
        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        scanCoverageTracker = AdvisoryScanCoverageTracker()
        scanCoverage = scanCoverageTracker.summary()
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
        resourceMonitor?.stop()
        resourceMonitor = nil
        workingSetStatus =
            state == .idle
            ? HostLocalization.text(
                "Ready for a new capture",
                "新しいキャプチャを開始できます"
            )
            : HostLocalization.text(
                "Capture reset",
                "キャプチャをリセットしました"
            )
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
                    self.workingSetStatus = HostLocalization.text(
                        "Ready; prior incomplete revision cleanup failed",
                        "開始可能ですが、以前の未完了データを削除できませんでした"
                    )
                }
            }
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
        workingSetStatus = HostLocalization.text(
            "Revalidating the persisted capture",
            "保存済みキャプチャを再検証しています"
        )

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
                self.workingSetStatus = HostLocalization.text(
                    "The persisted capture could not be revalidated; the on-disk inventory was refreshed",
                    "保存済みキャプチャを再検証できませんでした。ディスク上の一覧を更新しました"
                )
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
            self.exportURL = record.exportArchive

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
                self.exportURL = nil
                self.workingSetStatus = HostLocalization.text(
                    "The persisted capture could not be opened",
                    "保存済みキャプチャを開けませんでした"
                )
                return
            }

            self.workingSetStatus = record.exportArchive != nil
                ? HostLocalization.text(
                    "Opened the persisted capture; its validated archive is ready to share",
                    "保存済みキャプチャを開きました。検証済みアーカイブを共有できます"
                )
                : HostLocalization.text(
                    "Opened the persisted finalized capture; export can be prepared",
                    "保存済みの確定キャプチャを開きました。書き出しを作成できます"
                )
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
        workingSetStatus = HostLocalization.text(
            "Deleting local capture data",
            "ローカルのキャプチャデータを削除しています"
        )

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
                self.workingSetStatus = HostLocalization.text(
                    "Local capture data was deleted",
                    "ローカルのキャプチャデータを削除しました"
                )
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
                    HostLocalization.text(
                        "Some local capture data could not be deleted; the remaining artifacts stay listed for retry",
                        "一部のキャプチャデータを削除できませんでした。残ったデータは一覧に保持され、再試行できます"
                    )
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
                self.workingSetStatus = HostLocalization.text(
                    "Unreadable artifact removed",
                    "読み取れないデータを削除しました"
                )
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus =
                    HostLocalization.text(
                        "The artifact could not be removed",
                        "そのデータを削除できませんでした"
                    )
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
                self.workingSetStatus = HostLocalization.text(
                    "Abandoned working data was deleted",
                    "中断された作業データを削除しました"
                )
            } catch {
                guard self.state == .idle else {
                    return
                }
                self.workingSetStatus =
                    HostLocalization.text(
                        "The abandoned working data could not be deleted; it stays listed for retry",
                        "中断された作業データを削除できませんでした。一覧に保持されているため再試行できます"
                    )
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
            workingSetStatus = HostLocalization.text(
                "An external capture archive can only be imported while no capture is active",
                "キャプチャ実行中は外部アーカイブを読み込めません"
            )
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
            workingSetStatus = HostLocalization.text(
                "The selected file is not an .htdtcapture archive",
                "選択されたファイルは .htdtcapture アーカイブではありません"
            )
            return
        }

        // Security-scoped access must begin while the open/pick grant
        // is still live, so it starts here synchronously and is held
        // until the detached import work finishes.
        let accessing =
            url.startAccessingSecurityScopedResource()

        importOperationInFlight = true
        workingSetStatus = HostLocalization.text(
            "Validating the incoming .htdtcapture archive",
            "受信した .htdtcapture アーカイブを検証しています"
        )

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
                        return (revisionID, false, false)
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
                    return (revisionID, true, archiveStored)
                }.value

                guard self.state == .idle else {
                    return
                }
                self.loadPersistedCaptures()
                self.workingSetStatus = imported.promoted
                    ? HostLocalization.text(
                        "Validated capture archive imported",
                        "検証済みキャプチャアーカイブを読み込みました"
                    )
                    : HostLocalization.text(
                        "This capture revision is already stored locally",
                        "このキャプチャリビジョンはすでにローカルに保存されています"
                    )
                if imported.promoted && !imported.archiveStored {
                    self.workingSetStatus +=
                        HostLocalization.text(
                            " (archive copy was not retained in exports)",
                            "（書き出しスロットへアーカイブを保持できませんでした）"
                        )
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
                    HostLocalization.text(
                        "The .htdtcapture archive failed validation and was not imported; nothing was promoted",
                        ".htdtcapture アーカイブの検証に失敗したため読み込まれませんでした。データは昇格されていません"
                    )
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
            }
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

    private static func captureRootDirectory() -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "HTDTCapture",
            isDirectory: true
        )
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

    /// App-owned cache for the last validated HTDT equipment-catalog
    /// snapshot (#211). It lives directly under the capture app-support
    /// root — outside `finalized/`, `exports/` and `working/` — so the
    /// persisted-capture inventory never classifies it as a capture
    /// artifact and no catalog bytes ever enter a bundle.
    private static func makeEquipmentCatalogCache()
        -> HTDTEquipmentCatalogCache?
    {
        captureRootDirectory().map {
            HTDTEquipmentCatalogCache(
                fileURL: $0.appendingPathComponent(
                    "imported-equipment-catalog.json",
                    isDirectory: false
                )
            )
        }
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
            fail(.permissionDenied)
            return
        }

        do {
            try transition(.permissionsGranted)
        } catch {
            fail(.unknown)
            return
        }

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
        workingSetStatus =
            HostLocalization.isJapanese
            ? "リビジョンを準備しました: "
                + prepared.identity.captureRevisionID.description
            : "Prepared revision "
                + prepared.identity.captureRevisionID.description

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
                HostLocalization.text(
                    " (storage protection policy incomplete)",
                    "（保存先の保護属性が未適用です）"
                )
        }

        let context = sessionController.context
        let runtime = PlatformRuntimeProvenance.current()
        let generation = prepared.generation
        let store = prepared.store

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

        workingSetStatus = HostLocalization.text(
            "Presenting the live RoomPlan camera…",
            "RoomPlan のライブカメラを表示中…"
        )

        let liveViewReady =
            await sessionController
                .waitForLiveRoomCaptureViewPresentation()

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        guard liveViewReady else {
            workingSetStatus = HostLocalization.text(
                "The live RoomPlan camera view did not attach in time",
                "RoomPlan のライブカメラ画面を時間内に表示できませんでした"
            )
            fail(.roomPlanFailure)
            return
        }

        let startedAtUTC = BundleTimestamp.utcString(
            from: Date()
        )
        do {
            try sessionController.startRoomPlan()
        } catch {
            workingSetStatus = HostLocalization.text(
                "RoomPlan could not start after the live camera view was presented",
                "ライブカメラ表示後に RoomPlan を開始できませんでした"
            )
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
            workingSetStatus = HostLocalization.text(
                "AR tracking did not produce an initial frame in time",
                "AR トラッキングの初期フレームを時間内に取得できませんでした"
            )
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
        } catch {
            workingSetStatus = HostLocalization.text(
                "RoomPlan started, but the active AR configuration was not available in time",
                "RoomPlan は開始しましたが、実行中の AR 設定を時間内に取得できませんでした"
            )
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
            foundation =
                try CaptureSessionFoundationPackageBuilder.build(
                    context: context,
                    capabilities: capabilities,
                    configurationProfile: activeConfiguration,
                    startedAtUTC: startedAtUTC,
                    device:
                        try PlatformRuntimeProvenance
                            .currentDeviceDocument()
                )
            try await store.persistSessionFoundation(foundation)
        } catch {
            workingSetStatus = HostLocalization.text(
                "Capture session metadata could not be persisted",
                "キャプチャのセッション情報を保存できませんでした"
            )
            fail(.persistenceFailure)
            return
        }

        guard state == .scanning,
              captureGeneration == generation
        else {
            return
        }

        startScanCoverageSampling(
            generation: generation
        )
        workingSetStatus = HostLocalization.text(
            "Scanning; live RoomPlan camera and active AR configuration are ready",
            "スキャン中：ライブカメラと実行中の AR 設定を確認しました"
        )
    }

    private func updateLiveEndScanGuidance() {
        guard !isEndingScan,
              !endScanPreflightBlocked
        else {
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
            endScanGuidance = HostLocalization.text(
                "Before ending: hold the phone steady and point it at previously scanned room features until tracking recovers.",
                "終了前：iPhone を安定させ、すでに撮影した壁・角・家具へ向けてトラッキングが回復するまで待ってください。"
            )
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
            endScanGuidance = HostLocalization.text(
                "Before ending: no usable depth or mesh evidence is available. Keep the target in view and move slowly until Scene Depth observation appears.",
                "終了前：利用できる深度／メッシュ証拠がありません。対象を画面内に保ち、ゆっくり動かして「シーン深度による観測」が有効になるまで待ってください。"
            )
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
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: capture working data is unavailable. Start a fresh capture.",
                "まだ終了できません：キャプチャ作業データを利用できません。新しいキャプチャを開始してください。"
            )
            return nil
        }

        guard let startTiming = captureStartTimingCorrelation else {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: capture timing has not initialized. Keep the phone steady for a moment; if this does not clear, restart the capture.",
                "まだ終了できません：キャプチャ時刻が初期化されていません。iPhone を少し静止し、解消しない場合はキャプチャをやり直してください。"
            )
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
                    endScanGuidance = HostLocalization.text(
                        "Cannot end safely: device storage is below the capture safety threshold. Free storage, then try End again.",
                        "安全に終了できません：端末の空き容量がキャプチャ安全閾値を下回っています。空き容量を増やしてから、もう一度「終了」を押してください。"
                    )
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
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: there is no current AR frame. Hold the phone steady and point it at previously scanned features until tracking is normal, then try End again.",
                "まだ終了できません：現在の AR フレームを取得できません。iPhone を静止して既に撮影した特徴へ向け、トラッキングが正常になってからもう一度「終了」を押してください。"
            )
            return nil
        } catch {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: the selected camera/depth frame could not be prepared. Hold the phone steady on the target for 1–2 seconds, then try End again.",
                "まだ終了できません：終了用のカメラ／深度フレームを準備できません。対象へ向けたまま 1〜2 秒静止してから、もう一度「終了」を押してください。"
            )
            return nil
        }

        if evidence.trackingQualityEvent.state == .unavailable {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: AR tracking is unavailable in the frame that would be saved. Hold the phone steady on previously scanned room features until tracking returns to normal, then try End again.",
                "まだ終了できません：終了時に保存されるフレームで AR トラッキングが利用不可です。既に撮影した壁・角・家具へ向けて静止し、トラッキングが正常に戻ってからもう一度「終了」を押してください。"
            )
            return nil
        }

        let endTiming: CaptureTimingCorrelation
        do {
            endTiming =
                try sessionController.snapshotTimingCorrelation(
                    boundary: .sessionEnd
                )
        } catch {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: the current AR frame cannot be correlated to capture time. Keep the phone steady until tracking recovers, then try End again.",
                "まだ終了できません：現在の AR フレームとキャプチャ時刻を対応付けできません。トラッキングが回復するまで静止してから、もう一度「終了」を押してください。"
            )
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
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: the selected camera/depth frame could not be prepared. Hold the phone steady on the target for 1–2 seconds, then try End again.",
                "まだ終了できません：終了用のカメラ／深度フレームを準備できません。対象へ向けたまま 1〜2 秒静止してから、もう一度「終了」を押してください。"
            )
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
            _ = try CaptureTimingPackageBuilder.build(
                start: startTiming,
                end: endTiming
            )
        } catch {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: the final evidence package is not internally valid. Keep the phone steady and try End again; if it repeats, save one evidence frame before ending.",
                "まだ終了できません：終了用の証拠パッケージが内部検証に通りません。iPhone を静止して再度「終了」を押し、繰り返す場合は終了前に「証拠保存」を1回実行してください。"
            )
            return nil
        }

        let hasDepth =
            snapshot.depthEvidenceCount > 0
            || endFrameArtifacts.depthPayload != nil
        let hasMesh =
            evidence.meshSnapshotSucceeded
            && !evidence.meshAnchors.isEmpty

        if !hasDepth && !hasMesh {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: this capture has no retained depth evidence and no mesh anchors. Keep a nearby surface in view and move slowly until Scene Depth observation appears, then try End again.",
                "まだ終了できません：このキャプチャには保存済み深度証拠もメッシュアンカーもありません。近くの面を画面内に保ってゆっくり動かし、「シーン深度による観測」が有効になってからもう一度「終了」を押してください。"
            )
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
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: AR mesh anchors were observed, but they could not be converted into valid retained mesh evidence and no Scene Depth fallback exists. Keep scanning a nearby surface until depth evidence is retained, then try End again.",
                "まだ終了できません：AR メッシュアンカーは観測されていますが、有効な保存用メッシュ証拠へ変換できず、Scene Depth の代替証拠もありません。近くの面を追加スキャンして深度証拠が保存されてから、もう一度「終了」を押してください。"
            )
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
        workingSetStatus = HostLocalization.text(
            "Checking that selected frame and depth evidence can be saved before ending",
            "終了前に選択フレームと深度証拠を安全に保存できるか確認中"
        )

        do {
            try await store.persistFramePackage(
                prepared.framePackage
            )
        } catch {
            workingSetStatus = HostLocalization.text(
                "Retrying selected frame/depth evidence save before ending",
                "終了前の選択フレーム／深度証拠保存を再試行中"
            )
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
                        HostLocalization.text(
                            "End-frame persistence hit a capture-authority conflict and cannot continue safely",
                            "終了用フレームの保存でキャプチャ権限データの競合が発生し、安全に継続できません"
                        )
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
                        HostLocalization.text(
                            "End-frame persistence failed and its partial files could not be rolled back safely",
                            "終了用フレームの保存に失敗し、部分保存データを安全に取り消せませんでした"
                        )
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
                    HostLocalization.text(
                        "End was not committed because the selected frame/depth evidence could not be saved; this scan is still active",
                        "選択フレーム／深度証拠を保存できなかったため終了していません。現在のスキャンは継続中です"
                    )
                    + " ["
                    + diagnostic
                    + "]"
                endScanGuidance = HostLocalization.text(
                    "This scan is still active. Check device storage, keep scanning or save another evidence frame if useful, then try End again.",
                    "このキャプチャはまだ継続中です。空き容量を確認し、必要なら追加スキャンや「証拠保存」を行ってから、もう一度「終了」を押してください。"
                )
                endScanPreflightBlocked = true
                return
            }
        }

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
                HostLocalization.text(
                    "End timing could not be prepared; this scan is still active",
                    "終了時刻を準備できなかったため終了していません。現在のスキャンは継続中です"
                )
            endScanGuidance = HostLocalization.text(
                "This scan is still active. Hold the phone steady until tracking is normal, then try End again.",
                "このキャプチャはまだ継続中です。トラッキングが正常になるまで iPhone を静止してから、もう一度「終了」を押してください。"
            )
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
            workingSetStatus = HostLocalization.text(
                "Saving available mesh evidence before ending",
                "終了前に利用可能なメッシュ証拠を保存中"
            )
            do {
                try await store.persistMeshPackage(meshPackage)
            } catch {
                let diagnostic =
                    Self.persistenceDiagnostic(error)

                if error is CaptureWorkingSetError
                    || error is CaptureFileWriterError
                {
                    workingSetStatus =
                        HostLocalization.text(
                            "Mesh persistence hit a canonical capture-authority conflict and cannot fall back safely",
                            "メッシュ保存で正規キャプチャ authority の競合が発生し、安全に代替処理へ進めません"
                        )
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
                        HostLocalization.text(
                            "End was not committed because mesh evidence could not be saved and no retained Scene Depth fallback exists",
                            "メッシュ証拠を保存できず、保存済み Scene Depth の代替証拠もないため終了していません"
                        )
                        + " ["
                        + diagnostic
                        + "]"
                    endScanGuidance = HostLocalization.text(
                        "This scan is still active. Keep a nearby surface in view until depth evidence is retained, then try End again.",
                        "このキャプチャはまだ継続中です。近くの面を画面内に保ち、深度証拠が保存されてからもう一度「終了」を押してください。"
                    )
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
        endScanGuidance = HostLocalization.text(
            "Finishing RoomPlan. Keep the phone steady; the capture will stay recoverable until the final RoomPlan result is accepted.",
            "RoomPlan の終了処理中です。iPhone を静止してください。最終 RoomPlan 結果を受理できるまでは、このキャプチャを復旧可能な状態で保持します。"
        )
        workingSetStatus = HostLocalization.text(
            "Waiting for final RoomPlan result",
            "RoomPlan の最終結果を待機中"
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
            self.workingSetStatus = HostLocalization.text(
                "RoomPlan is still producing the final result",
                "RoomPlan の最終結果を引き続き生成中です"
            )
            self.endScanGuidance = HostLocalization.text(
                "Final RoomPlan processing is taking longer than usual. Keep the app in the foreground; HTDT will stop this unresolved attempt if RoomPlan does not complete.",
                "RoomPlan の終了処理に通常より時間がかかっています。アプリを前面にしたまま待ってください。完了しない場合は、この未解決の終了処理を HTDT が停止します。"
            )

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

            self.workingSetStatus = HostLocalization.text(
                "RoomPlan did not return a final result within the safe End window; retained evidence remains on disk",
                "RoomPlan が安全な終了待機時間内に最終結果を返しませんでした。保存済みの証拠データは端末上に保持されています"
            )
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

            // A background/thermal/storage event may have sealed spatial
            // continuation while Review quality was being refreshed. In that
            // case the ordered resource-event path owns the recovery status;
            // do not overwrite it with the generic End-success message.
            guard !self.spatialAuthoritySealedForFinalization else {
                return
            }

            if meshSnapshotUnavailable {
                self.workingSetStatus = HostLocalization.text(
                    "Reviewing; frame/depth evidence was retained, but the mesh snapshot was unavailable",
                    "確認中：フレーム／深度証拠は保存しましたが、メッシュスナップショットは取得できませんでした"
                )
            } else {
                self.workingSetStatus = HostLocalization.text(
                    "Reviewing; required end evidence and RoomPlan result were saved",
                    "確認中：終了に必要な証拠データと RoomPlan 結果を保存しました"
                )
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
                    HostLocalization.text(
                        "The rejected End mesh snapshot could not be rolled back safely",
                        "受理されなかった終了処理のメッシュスナップショットを安全に取り消せませんでした"
                    )
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
        } catch {
            isEndingScan = false
            workingSetStatus =
                HostLocalization.text(
                    "RoomPlan end failed and scanning could not be restarted",
                    "RoomPlan の終了処理に失敗し、スキャンも再開できませんでした"
                )
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
            HostLocalization.text(
                "The final RoomPlan result was not accepted; the same HTDT capture is still active",
                "最終 RoomPlan 結果を受理できませんでしたが、同じ HTDT キャプチャは継続中です"
            )
            + " ["
            + diagnostic
            + "]"
        endScanGuidance = HostLocalization.text(
            "RoomPlan scanning restarted in the same AR coordinate space. Revisit important walls/furniture, continue scanning as needed, then press End again.",
            "同じ AR 座標空間のまま RoomPlan スキャンを再開しました。重要な壁や家具をもう一度映し、必要なだけ追加スキャンしてから、再度「終了」を押してください。"
        )
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
            motionGuidanceTracker = ScanMotionGuidanceTracker()
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
                return try ARConfigurationSnapshotAdapter.snapshot(
                    session: sessionController.arSession,
                    captureMode: .roomPlanMesh
                )
            } catch ARConfigurationSnapshotError.configurationUnavailable {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        throw ARConfigurationSnapshotError.configurationUnavailable
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
            requirements: qualityRequirements
        )
        let snapshot = await store.snapshot()

        // Publish Review UI only after every store-actor suspension has
        // completed. A failure/reset/reopen may invalidate this generation
        // while either call is suspended.
        guard captureGeneration == generation,
              state == .reviewing
        else {
            return
        }

        qualityReport = report
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
            workingSetStatus =
                HostLocalization.isJapanese
                ? "確定可能："
                    + String(snapshot.payloadDeclarations.count)
                    + " 件の証拠データが事前確認に合格しました"
                : "Ready to finalize; "
                    + String(snapshot.payloadDeclarations.count)
                    + " evidence payloads passed preflight"
        } else {
            let errorCount = report.diagnostics.filter {
                $0.severity == .error
            }.count
            workingSetStatus =
                HostLocalization.isJapanese
                ? "確認中："
                    + String(errorCount)
                    + " 件の品質エラーがあります"
                : "Reviewing; "
                    + String(errorCount)
                    + " blocking quality diagnostic(s)"
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

        do {
            try await store.persistQualityReport(quality)

            // CONTRACT (#180): the sibling store agent adds
            // sealForFinalization()/unseal() on CaptureWorkingSetStore.
            // The seal drains in-flight writes, then rejects further
            // working-set mutations for the rest of the commit
            // transaction so the snapshot and the finalizer's staging
            // scan describe one frozen authority.
            try await store.sealForFinalization()

            let snapshot = await store.snapshot()

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
                    snapshot: snapshot,
                    qualityReport: quality,
                    app: BundleAppIdentity(
                        version: runtime.appVersion,
                        build: runtime.appBuild
                    )
                )
            let destination = finalizedDirectory(
                for: snapshot
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
                    quality: quality,
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
                    stagingDirectory: snapshot.rootDirectory,
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
                quality: quality,
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
                HostLocalization.text(
                    "Finalization failed and the staged quality record could not be rolled back safely",
                    "確定処理に失敗し、途中保存された品質情報を安全に取り消せませんでした"
                )
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
                HostLocalization.text(
                    "Finalization was not committed. The capture remains in Review and can be retried.",
                    "確定処理はコミットされませんでした。キャプチャは確認画面に保持されており、再試行できます。"
                )
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
            fencedNote = HostLocalization.text(
                "; a "
                    + fencedFailure.rawValue
                    + " lifecycle event arrived during the commit window and was surfaced after adoption",
                "；コミット中に "
                    + fencedFailure.rawValue
                    + " ライフサイクルイベントを検出したため、確定後の状態として記録しました"
            )
        } else {
            fencedNote = ""
        }

        let protectionNote: String
        if let protectionWarning {
            protectionNote = HostLocalization.text(
                " (file protection reapply failed)",
                "（保護属性の再適用に失敗）"
            ) + " [" + protectionWarning + "]"
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
                workingSetStatus = HostLocalization.text(
                    "The revision was committed but the host could not reflect finalized state; it stays discoverable in the persisted-capture inventory",
                    "リビジョンはコミットされましたが、確定状態を反映できませんでした。保存済みキャプチャ一覧から確認できます"
                )
                self.loadPersistedCaptures()
                return
            }
            workingSetStatus =
                (
                    HostLocalization.isJapanese
                    ? "リビジョンを確定しました。バンドルダイジェスト: "
                        + validation.bundleDigest.description
                    : "Finalized revision; bundle digest "
                        + validation.bundleDigest.description
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
            workingSetStatus = HostLocalization.text(
                "The revision was committed but the host could not reflect finalized state; it stays discoverable in the persisted-capture inventory",
                "リビジョンはコミットされましたが、確定状態を反映できませんでした。保存済みキャプチャ一覧から確認できます"
            )
            self.loadPersistedCaptures()
            return
        }
        workingSetStatus =
            HostLocalization.text(
                "The revision was committed to finalized storage, but post-promotion validation could not prove it; the committed bytes are preserved and stay discoverable through the persisted-capture inventory",
                "リビジョンは確定済み領域にコミットされましたが、昇格後の検証で証明できませんでした。コミット済みデータは保持され、保存済みキャプチャ一覧から確認できます"
            )
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
                if sealedReviewResourceCondition,
                   self.state == .reviewing
                {
                    if discardedUnsavedAnnotationEdits {
                        self.workingSetStatus =
                            HostLocalization.text(
                                "Review retained after the resource/lifecycle interruption. Unsaved annotation edits were discarded; accepted capture evidence can still be finalized or retried.",
                                "リソース／ライフサイクル中断後も確認データを保持しました。未保存の注釈編集は破棄されましたが、受理済みキャプチャ証拠は確定または再試行できます。"
                            )
                    } else {
                        self.workingSetStatus =
                            HostLocalization.text(
                                "Review retained; additional scanning/annotation is sealed by the current resource/lifecycle condition, while accepted evidence remains available for finalization or retry",
                                "確認データを保持しました。現在のリソース／ライフサイクル状態により追加スキャン／注釈は封印されていますが、受理済み証拠は確定または再試行に利用できます"
                            )
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

        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: root
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
                HostLocalization.text(
                    "A post-finalization operation failed, but the finalized revision remains intact",
                    "確定後の処理でエラーが発生しましたが、確定済みリビジョンは保持されています"
                )
            return
        }

        scanCoverageTask?.cancel()
        scanCoverageTask = nil
        resourceMonitor?.stop()
        resourceMonitor = nil

        // Invalidate all in-flight callbacks before stopping RoomPlan. A
        // terminal failure must not accept late evidence into the failed
        // coordinate authority.
        captureGeneration = UUID()

        if code == .interrupted {
            workingSetStatus = HostLocalization.text(
                "Capture stopped because the app left the foreground",
                "アプリがバックグラウンドに移動したためキャプチャを停止しました"
            )
        } else if code == .thermalPressure {
            workingSetStatus = HostLocalization.text(
                "Capture stopped because the device reached a critical thermal state",
                "端末温度が危険な状態になったためキャプチャを停止しました"
            )
        } else if code == .storagePressure {
            workingSetStatus = HostLocalization.text(
                "Capture stopped because available storage fell below the safe threshold",
                "安全に保存できる空き容量を下回ったためキャプチャを停止しました"
            )
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
    }
}
