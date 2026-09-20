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
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginReview: coordinator.beginReview,
                captureEvidenceFrame: coordinator.captureEvidenceFrame,
                setScanMovementCapability:
                    coordinator.setScanMovementCapability,
                beginAnnotation: coordinator.beginAnnotation,
                captureRaycastPlacement:
                    coordinator.captureRaycastPlacement,
                captureSpeakerOrientation:
                    coordinator.captureSpeakerOrientation,
                commitAnnotationAuthority:
                    coordinator.commitAnnotationAuthority,
                cancelAnnotation: coordinator.cancelAnnotation,
                finalizeCapture: coordinator.finalizeCapture,
                prepareExport: coordinator.prepareExport,
                resetCapture: coordinator.resetCapture
            )
        )
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

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var finalizedRevision: FinalizedCaptureRevision?
    private var resourceMonitor: CaptureResourceMonitor?
    private var captureGeneration = UUID()
    private var isEndingScan = false
    private var isCapturingEvidenceFrame = false
    private var endScanPreflightBlocked = false
    private var captureStartTimingCorrelation:
        CaptureTimingCorrelation?
    private var acceptedRoomPlanRawSHA256: EvidenceSHA256?
    private var pendingEndAttempt: PendingEndScanAttempt?
    private var roomPlanCompletionInFlight = false
    private var spatialAuthoritySealedForFinalization = false
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
    private var memoryWarningCancellable: AnyCancellable?
    private var derivedPreviewSuspendedForMemoryPressure = false
    private var roomPlanModelRenderingEnabled = true
    private let qualityRequirements = CaptureQualityRequirements(
        rulesetVersion: "1.1.0",
        allowDepthEvidenceAsMeshFallback: true
    )

    init() {
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()

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
        guard state == .idle else {
            return
        }

        qualityReport = nil
        validationReport = nil
        exportURL = nil
        finalizedRevision = nil
        annotationAuthorityCommitted = false
        annotationEvidenceRefs = []
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        pendingEndAttempt = nil
        roomPlanCompletionInFlight = false
        spatialAuthoritySealedForFinalization = false
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
        resourceMonitor?.stop()
        resourceMonitor = nil

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
        let artifacts: CapturedFrameArtifacts

        do {
            artifacts =
                try sessionController.snapshotFrameEvidence(
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

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isCapturingEvidenceFrame = false
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

                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Recoverable manual evidence-frame persistence failure: "
                            + diagnostic
                    )
                )
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
        isEndingScan = true

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let prepared = await self.prepareEndScan(),
                  self.state == .scanning
            else {
                self.isEndingScan = false
                return
            }

            self.endScanGuidance = nil
            await self.endScanForReview(prepared)
        }
    }

    func beginAnnotation() {
        guard state == .reviewing,
              !annotationAuthorityCommitted
        else {
            return
        }
        do {
            try transition(.beginAnnotation)
            workingSetStatus = HostLocalization.text(
                "Editing annotations and measurements",
                "注釈と計測値を編集中"
            )
        } catch {
            fail(.unknown)
        }
    }

    func captureSpeakerOrientation()
        async throws -> AnnotationOrientationAuthority
    {
        guard state == .annotating,
              let store = workingSetStore
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let snapshot =
            try sessionController.snapshotHorizontalCameraHeading(
                depthSelection: .discrete
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: snapshot.frameArtifacts.descriptor,
            pixelPayload: snapshot.frameArtifacts.pixelPayload,
            depthPayload: snapshot.frameArtifacts.depthPayload,
            confidencePayload:
                snapshot.frameArtifacts.confidencePayload,
            previewPayload:
                snapshot.frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        let evidenceRef = "path:" + package.descriptorPath
        let orientation = try OrientationAxes(
            frontAxisLocal: snapshot.frontAxisWorld,
            upAxisLocal: .unit(0, 1, 0)
        )
        let authority = try AnnotationOrientationAuthority(
            orientation: orientation,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        annotationEvidenceRefs =
            workingSnapshot.evidenceFrameRefs
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

        let snapshot =
            try sessionController.snapshotCenterRaycastPlacement(
                depthSelection: .discrete
            )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: snapshot.frameArtifacts.descriptor,
            pixelPayload: snapshot.frameArtifacts.pixelPayload,
            depthPayload: snapshot.frameArtifacts.depthPayload,
            confidencePayload:
                snapshot.frameArtifacts.confidencePayload,
            previewPayload:
                snapshot.frameArtifacts.previewPayload
        )
        try await store.persistFramePackage(package)

        let evidenceRef = "path:" + package.descriptorPath
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
        let placement = try PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: [evidenceRef]
        )
        let authority = try AnnotationPlacementAuthority(
            worldFromAnnotation: transform,
            placement: placement,
            evidenceRefs: [evidenceRef]
        )

        let workingSnapshot = await store.snapshot()
        annotationEvidenceRefs =
            workingSnapshot.evidenceFrameRefs
        workingSetStatus = HostLocalization.text(
            "Evidence-linked raycast placement captured",
            "証拠フレームに紐付いたレイキャスト位置を取得しました"
        )

        return authority
    }

    func cancelAnnotation() {
        guard state == .annotating else {
            return
        }
        do {
            try transition(.beginReview)
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
        measurements: [CaptureMeasurement]
    ) {
        guard state == .annotating,
              !annotationAuthorityCommitted,
              let store = workingSetStore
        else {
            return
        }

        let annotationPackage: AnnotationEvidencePackage
        let measurementPackage: MeasurementEvidencePackage
        do {
            annotationPackage =
                try AnnotationEvidencePackageBuilder.build(
                    entities: annotations
                )
            measurementPackage =
                try MeasurementEvidencePackageBuilder.build(
                    measurements: measurements
                )
        } catch {
            fail(.persistenceFailure)
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
                try await store
                    .persistAnnotationAndMeasurementPackages(
                        annotationPackage: annotationPackage,
                        measurementPackage: measurementPackage
                    )
                guard self.captureGeneration == generation,
                      self.state == .annotating
                else {
                    return
                }

                self.annotationAuthorityCommitted = true
                try self.transition(.beginReview)
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
            } catch {
                self.fail(.persistenceFailure)
            }
        }
    }

    func finalizeCapture() {
        guard state == .reviewing,
              let qualityReport,
              qualityReport.readyForHTDTIngestion,
              qualityReport.integrityStatus == .pass,
              let store = workingSetStore
        else {
            return
        }

        resourceMonitor?.sampleStorage()
        guard state == .reviewing else {
            return
        }

        // Committing a ready Review to validation closes spatial capture
        // authority. Resource/background callbacks must not invalidate the
        // generation while revision promotion is in flight.
        resourceMonitor?.stop()
        resourceMonitor = nil
        spatialAuthoritySealedForFinalization = true
        sessionController.stopAndPauseARSession()

        do {
            try transition(.beginValidation)
        } catch {
            fail(.unknown)
            return
        }

        workingSetStatus = HostLocalization.text(
            "Persisting quality and finalizing revision",
            "品質情報を保存し、リビジョンを確定中"
        )

        let generation = captureGeneration
        Task {
            await performFinalization(
                store: store,
                quality: qualityReport,
                generation: generation
            )
        }
    }

    func prepareExport() {
        guard state == .finalized,
              let finalizedRevision,
              let validationReport,
              validationReport.bundleDigest
                == finalizedRevision.bundleDigest
        else {
            return
        }

        workingSetStatus = HostLocalization.text(
            "Creating validated .htdtcapture archive",
            "検証済み .htdtcapture アーカイブを作成中"
        )
        let generation = captureGeneration

        Task {
            let destination: URL
            do {
                destination = try exportDestination(
                    for: finalizedRevision
                )
            } catch {
                guard captureGeneration == generation,
                      state == .finalized
                else {
                    return
                }
                workingSetStatus =
                    HostLocalization.text(
                        "Archive destination could not be prepared. The finalized revision is preserved and export can be retried.",
                        "アーカイブの保存先を準備できませんでした。確定済みリビジョンは保持されているため、書き出しを再試行できます。"
                    )
                    + " ["
                    + Self.persistenceDiagnostic(error)
                    + "]"
                return
            }

            do {
                let result = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CaptureBundleArchiveExporter.export(
                        finalizedDirectory:
                            finalizedRevision.directory,
                        destination: destination
                    )
                }.value
                guard result.bundleDigest
                        == finalizedRevision.bundleDigest
                else {
                    throw CaptureBundleArchiveError
                        .archiveLogicalDigestMismatch
                }
                guard captureGeneration == generation,
                      state == .finalized
                else {
                    return
                }

                exportURL = result.archiveURL
                try transition(.export)
                workingSetStatus = HostLocalization.text(
                    "Validated share-ready archive created",
                    "検証済みの共有用アーカイブを作成しました"
                )
            } catch {
                guard captureGeneration == generation,
                      state == .finalized
                else {
                    return
                }

                if case CaptureBundleArchiveError
                    .destinationAlreadyExists = error,
                   let existingValidation =
                    try? StoredCaptureBundleArchiveValidator
                        .validate(archive: destination),
                   existingValidation.bundleDigest
                    == finalizedRevision.bundleDigest
                {
                    exportURL = destination
                    do {
                        try transition(.export)
                        workingSetStatus = HostLocalization.text(
                            "Existing validated archive recovered and is ready to share",
                            "既存の検証済みアーカイブを復旧し、共有できる状態にしました"
                        )
                    } catch {
                        workingSetStatus =
                            HostLocalization.text(
                                "Validated archive exists, but the export state could not be committed",
                                "検証済みアーカイブは存在しますが、書き出し状態を確定できませんでした"
                            )
                    }
                    return
                }

                workingSetStatus =
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
        guard state == .failed || state == .exported else {
            return
        }

        let failedWorkingSet =
            state == .failed ? workingSetStore : nil

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
        captureStartTimingCorrelation = nil
        acceptedRoomPlanRawSHA256 = nil
        spatialAuthoritySealedForFinalization = false
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
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()

        if let failedWorkingSet {
            Task { @MainActor [weak self] in
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
            generation: UUID
        )
        do {
            prepared = try makeWorkingSet()
        } catch {
            fail(.persistenceFailure)
            return
        }

        workingSetStore = prepared.store
        captureGeneration = prepared.generation
        workingSetStatus =
            HostLocalization.isJapanese
            ? "リビジョンを準備しました: "
                + prepared.identity.captureRevisionID.description
            : "Prepared revision "
                + prepared.identity.captureRevisionID.description

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

        configureResourceMonitor(
            store: store,
            rootDirectory: await store.rootDirectory,
            generation: generation
        )
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
        let evidence: CaptureReviewEvidenceSnapshot
        let framePackage: FrameEvidencePackage
        let meshPackage: MeshEvidencePackage?
        let meshSnapshotUnavailable: Bool
    }

    private struct PendingEndScanAttempt {
        let id: UUID
        let prepared: PreparedEndScanAttempt
        let timingPackage: CaptureTimingPackage
    }

    private func prepareEndScan() async -> PreparedEndScanAttempt? {
        endScanPreflightBlocked = false
        var succeeded = false
        defer {
            endScanPreflightBlocked = !succeeded
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
            endTiming = try sessionController.snapshotTimingCorrelation()
        } catch {
            endScanGuidance = HostLocalization.text(
                "Cannot end yet: the current AR frame cannot be correlated to capture time. Keep the phone steady until tracking recovers, then try End again.",
                "まだ終了できません：現在の AR フレームとキャプチャ時刻を対応付けできません。トラッキングが回復するまで静止してから、もう一度「終了」を押してください。"
            )
            return nil
        }

        let framePackage: FrameEvidencePackage
        do {
            framePackage = try FrameEvidencePackageBuilder.build(
                descriptor: evidence.frameArtifacts.descriptor,
                pixelPayload: evidence.frameArtifacts.pixelPayload,
                depthPayload: evidence.frameArtifacts.depthPayload,
                confidencePayload:
                    evidence.frameArtifacts.confidencePayload,
                previewPayload:
                    evidence.frameArtifacts.previewPayload
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
            || evidence.frameArtifacts.depthPayload != nil
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

        endScanGuidance = nil
        succeeded = true
        return PreparedEndScanAttempt(
            evidence: evidence,
            framePackage: framePackage,
            meshPackage: meshPackage,
            meshSnapshotUnavailable: meshSnapshotUnavailable
        )
    }

    private func endScanForReview(
        _ prepared: PreparedEndScanAttempt
    ) async {
        var handedOffToRoomPlanCompletion = false
        defer {
            if !handedOffToRoomPlanCompletion {
                isEndingScan = false
            }
        }

        guard let store = workingSetStore else {
            workingSetStatus = HostLocalization.text(
                "Capture working set is unavailable",
                "キャプチャ作業データを利用できません"
            )
            fail(.persistenceFailure)
            return
        }

        let generation = captureGeneration
        guard state == .scanning else {
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

                await store.recordResourceEvent(
                    CaptureResourceEvent(
                        kind: .persistenceFailure,
                        severity: .warning,
                        detail:
                            "Recoverable pre-stop end-frame persistence failure: "
                            + diagnostic
                    )
                )
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
                try sessionController.snapshotTimingCorrelation()
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

        await store.recordTrackingEvent(
            prepared.evidence.trackingQualityEvent
        )

        guard captureGeneration == generation,
              state == .scanning
        else {
            return
        }

        let attempt = PendingEndScanAttempt(
            id: UUID(),
            prepared: prepared,
            timingPackage: timingPackage
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

        handedOffToRoomPlanCompletion = true
        sessionController.stopRoomPlanPreservingARSession()

        let attemptID = attempt.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
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
            // Restarting here could let a late callback from this unresolved
            // stop be consumed by a later End attempt. Keep the attempt
            // pending until RoomPlan actually resolves it.
            self.workingSetStatus = HostLocalization.text(
                "RoomPlan is still producing the final result",
                "RoomPlan の最終結果を引き続き生成中です"
            )
            self.endScanGuidance = HostLocalization.text(
                "Final RoomPlan processing is taking longer than usual. Keep the app in the foreground and wait; another End attempt will not be started.",
                "RoomPlan の終了処理に通常より時間がかかっています。アプリを前面にしたまま待ってください。別の終了処理は開始しません。"
            )
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

            let raw: RoomPlanRawArtifactPayload
            do {
                raw = try RoomPlanArtifactProcessor.encodeRaw(
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

            var meshSnapshotUnavailable =
                pending.prepared.meshSnapshotUnavailable
            if let meshPackage = pending.prepared.meshPackage {
                self.workingSetStatus = HostLocalization.text(
                    "Saving available mesh evidence",
                    "利用可能なメッシュ証拠を保存中"
                )
                do {
                    try await store.persistMeshPackage(meshPackage)
                } catch {
                    meshSnapshotUnavailable = true
                    await store.recordResourceEvent(
                        CaptureResourceEvent(
                            kind: .persistenceFailure,
                            severity: .warning,
                            detail:
                                "Optional end-scan mesh persistence failed; retained frame/depth evidence will be used as the bounded geometry fallback."
                        )
                    )
                }
            }

            guard self.captureGeneration == generation,
                  self.state == .scanning,
                  self.pendingEndAttempt?.id == pending.id
            else {
                return
            }

            self.acceptedRoomPlanRawSHA256 =
                raw.descriptor.sha256
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

        pendingEndAttempt = nil
        roomPlanCompletionInFlight = false
        acceptedRoomPlanRawSHA256 = nil

        await store.recordResourceEvent(
            CaptureResourceEvent(
                kind: .persistenceFailure,
                severity: .warning,
                detail:
                    "Recoverable RoomPlan end attempt rejected: "
                    + diagnostic
            )
        )

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
        generation: UUID
    ) {
        scanCoverageTask?.cancel()
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

    private func waitForInitialTimingCorrelation()
        async throws -> CaptureTimingCorrelation
    {
        for _ in 0..<40 {
            if let correlation =
                try? sessionController.snapshotTimingCorrelation()
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

        guard captureGeneration == generation,
              state == .reviewing
        else {
            return
        }

        qualityReport = report
        let snapshot = await store.snapshot()
        annotationEvidenceRefs = snapshot.evidenceFrameRefs

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
        var promotedRevision: FinalizedCaptureRevision?

        do {
            try await store.persistQualityReport(quality)
            let snapshot = await store.snapshot()

            guard captureGeneration == generation else {
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
            let finalized =
                try await BundleRevisionFinalizer().finalize(
                    stagingDirectory: snapshot.rootDirectory,
                    destinationDirectory: destination,
                    request: request
                )
            promotedRevision = finalized

            let validation =
                try BundleDirectoryValidator.validate(
                    root: finalized.directory
                )
            guard validation.bundleDigest == finalized.bundleDigest else {
                throw BundleFinalizationError.promotionFailed
            }

            guard captureGeneration == generation else {
                return
            }

            sessionController.stopAndPauseARSession()
            resourceMonitor?.stop()
            resourceMonitor = nil
            workingSetStore = nil
            finalizedRevision = finalized
            validationReport = validation
            exportURL = nil
            try transition(.finalize)
            workingSetStatus =
                HostLocalization.isJapanese
                ? "リビジョンを確定しました。バンドルダイジェスト: "
                    + validation.bundleDigest.description
                : "Finalized revision; bundle digest "
                    + validation.bundleDigest.description
        } catch {
            guard captureGeneration == generation else {
                return
            }

            let diagnostic =
                Self.persistenceDiagnostic(error)

            if promotedRevision != nil {
                workingSetStatus =
                    HostLocalization.text(
                        "The revision was promoted but failed post-promotion validation; capture cannot safely resume",
                        "リビジョン昇格後の検証に失敗したため、安全にキャプチャへ戻れません"
                    )
                    + " ["
                    + diagnostic
                    + "]"
                fail(.persistenceFailure)
                return
            }

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
                    + diagnostic
                    + "]"
                fail(.persistenceFailure)
                return
            }

            await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: .persistenceFailure,
                    severity: .warning,
                    detail:
                        "Recoverable finalization failure: "
                        + diagnostic
                )
            )

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

    private func configureResourceMonitor(
        store: CaptureWorkingSetStore,
        rootDirectory: URL,
        generation: UUID
    ) {
        resourceMonitor?.stop()

        let monitor = CaptureResourceMonitor(
            rootDirectory: rootDirectory
        ) { [weak self] event, failure in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            Task {
                await store.recordResourceEvent(event)
                if self.state == .reviewing {
                    await self.refreshQuality(
                        store: store,
                        generation: generation
                    )
                }
            }

            if let failure,
               self.state != .failed,
               self.state != .finalized,
               self.state != .exported
            {
                self.fail(failure)
            }
        }

        resourceMonitor = monitor
        monitor.start()
    }

    private func makeWorkingSet() throws -> (
        store: CaptureWorkingSetStore,
        identity: CaptureWorkingSetIdentity,
        generation: UUID
    ) {
        guard let applicationSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let identity = CaptureWorkingSetIdentity()
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

        return (
            store: try CaptureWorkingSetStore(
                identity: identity,
                rootDirectory: root
            ),
            identity: identity,
            generation: UUID()
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

    private func transition(_ event: CaptureEvent) throws {
        try stateMachine.apply(event)
        state = stateMachine.state
        lastFailure = stateMachine.lastFailure
    }

    private func fail(_ code: CaptureFailureCode) {
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
