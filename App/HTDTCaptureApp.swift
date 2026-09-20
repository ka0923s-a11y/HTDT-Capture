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

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var finalizedRevision: FinalizedCaptureRevision?
    private var resourceMonitor: CaptureResourceMonitor?
    private var captureGeneration = UUID()
    private var isEndingScan = false
    private var isCapturingEvidenceFrame = false
    private var captureStartTimingCorrelation:
        CaptureTimingCorrelation?
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
        guard state == .reviewing || state == .annotating else {
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
                    maximumPointCount: 384
                )
            )
        derivedVolumeFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384
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
            fail(.trackingUnavailable)
            return
        } catch {
            isCapturingEvidenceFrame = false
            fail(.persistenceFailure)
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

            do {
                let package = try FrameEvidencePackageBuilder.build(
                    descriptor: artifacts.descriptor,
                    pixelPayload: artifacts.pixelPayload,
                    depthPayload: artifacts.depthPayload,
                    confidencePayload: artifacts.confidencePayload,
                    previewPayload: artifacts.previewPayload
                )
                try await store.persistFramePackage(package)
                let snapshot = await store.snapshot()
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }
                self.scanEvidenceFrameCount =
                    snapshot.evidenceFrameCount
                self.workingSetStatus =
                    HostLocalization.isJapanese
                    ? "スキャン中：証拠フレームを "
                        + String(snapshot.evidenceFrameCount)
                        + " 件保存しました"
                    : "Scanning; "
                        + String(snapshot.evidenceFrameCount)
                        + " evidence frame(s) persisted"
            } catch {
                self.workingSetStatus = HostLocalization.text(
                    "Processed RoomPlan evidence could not be saved",
                    "RoomPlan の処理済みデータを保存できませんでした"
                )
                self.fail(.persistenceFailure)
            }
        }
    }

    func beginReview() {
        guard state == .scanning, !isEndingScan else {
            return
        }
        isEndingScan = true
        scanCoverageTask?.cancel()
        scanCoverageTask = nil

        Task {
            await endScanForReview()
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
                try await store.persistAnnotationPackage(
                    annotationPackage
                )
                try await store.persistMeasurementPackage(
                    measurementPackage
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
            do {
                let destination = try exportDestination(
                    for: finalizedRevision
                )
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
                fail(.persistenceFailure)
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
                    maximumPointCount: 384
                )
            )
        derivedVolumeFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384
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

    private func endScanForReview() async {
        defer {
            isEndingScan = false
        }

        guard let store = workingSetStore else {
            workingSetStatus = HostLocalization.text(
                "Capture working set is unavailable",
                "キャプチャ作業データを利用できません"
            )
            fail(.persistenceFailure)
            return
        }

        resourceMonitor?.sampleStorage()
        guard state == .scanning else {
            return
        }

        let evidence: CaptureReviewEvidenceSnapshot
        do {
            evidence =
                try sessionController.snapshotReviewEvidence(
                    depthSelection: .discrete
                )
        } catch PlatformCaptureError.currentFrameUnavailable {
            workingSetStatus = HostLocalization.text(
                "No current AR frame was available at scan end",
                "スキャン終了時の AR フレームを取得できませんでした"
            )
            fail(.trackingUnavailable)
            return
        } catch {
            workingSetStatus = HostLocalization.text(
                "Selected frame/depth evidence could not be prepared",
                "選択フレーム／深度証拠を準備できませんでした"
            )
            fail(.persistenceFailure)
            return
        }

        let endTimingCorrelation: CaptureTimingCorrelation
        do {
            endTimingCorrelation =
                try sessionController.snapshotTimingCorrelation()
        } catch {
            workingSetStatus = HostLocalization.text(
                "Capture end timing could not be correlated",
                "キャプチャ終了時刻を AR フレームと対応付けできませんでした"
            )
            fail(.trackingUnavailable)
            return
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
        } catch {
            workingSetStatus = HostLocalization.text(
                "Selected frame/depth package validation failed",
                "選択フレーム／深度パッケージの検証に失敗しました"
            )
            fail(.persistenceFailure)
            return
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

        sessionController.stopRoomPlanPreservingARSession()

        do {
            try transition(.beginReview)
        } catch {
            fail(.unknown)
            return
        }

        let timingPackage: CaptureTimingPackage
        do {
            guard let startTimingCorrelation =
                captureStartTimingCorrelation
            else {
                throw CaptureSessionMetadataError
                    .invalidCorrelationOrder
            }
            timingPackage =
                try CaptureTimingPackageBuilder.build(
                    start: startTimingCorrelation,
                    end: endTimingCorrelation
                )
        } catch {
            workingSetStatus = HostLocalization.text(
                "Capture timing metadata could not be prepared",
                "キャプチャ時刻メタデータを準備できませんでした"
            )
            fail(.persistenceFailure)
            return
        }

        workingSetStatus = HostLocalization.text(
            "Saving capture timing",
            "キャプチャ時刻を保存中"
        )
        do {
            try await store.persistTimingPackage(timingPackage)
        } catch {
            workingSetStatus = HostLocalization.text(
                "Capture timing metadata could not be saved",
                "キャプチャ時刻メタデータを保存できませんでした"
            )
            fail(.persistenceFailure)
            return
        }

        await store.recordTrackingEvent(
            evidence.trackingQualityEvent
        )

        workingSetStatus = HostLocalization.text(
            "Saving selected frame and depth evidence",
            "選択フレームと深度証拠を保存中"
        )
        do {
            try await store.persistFramePackage(framePackage)
        } catch {
            workingSetStatus = HostLocalization.text(
                "Selected frame/depth evidence could not be saved",
                "選択フレーム／深度証拠を保存できませんでした"
            )
            fail(.persistenceFailure)
            return
        }

        if let meshPackage {
            workingSetStatus = HostLocalization.text(
                "Saving available mesh evidence",
                "利用可能なメッシュ証拠を保存中"
            )
            do {
                try await store.persistMeshPackage(meshPackage)
            } catch {
                // Frame/depth evidence has already been durably persisted.
                // ARMesh is an optional geometric accelerator at this stage;
                // do not destroy an otherwise valid capture when its snapshot
                // cannot be written. Quality evaluation will accept the
                // explicit scene-depth fallback only when depth really exists.
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

        await refreshQuality(
            store: store,
            generation: captureGeneration
        )

        if meshSnapshotUnavailable,
           state == .reviewing
        {
            workingSetStatus = HostLocalization.text(
                "Reviewing; frame/depth evidence was retained, but the mesh snapshot was unavailable",
                "確認中：フレーム／深度証拠は保存しましたが、メッシュスナップショットは取得できませんでした"
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
        let raw: RoomPlanRawArtifactPayload
        do {
            raw = try RoomPlanArtifactProcessor.encodeRaw(
                data,
                captureSessionID: captureSessionID,
                coordinateSpaceID: coordinateSpaceID,
                runtime: runtime
            )
        } catch {
            fail(.persistenceFailure)
            return
        }

        workingSetStatus = HostLocalization.text(
            "Persisting raw RoomPlan evidence",
            "RoomPlan の生データを保存中"
        )

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            do {
                try await store.persistRawRoomPlan(raw)
            } catch {
                self.workingSetStatus = HostLocalization.text(
                    "Raw RoomPlan evidence could not be saved",
                    "RoomPlan の生データを保存できませんでした"
                )
                self.fail(.persistenceFailure)
                return
            }

            guard self.captureGeneration == generation else {
                return
            }

            if frameworkFailed {
                self.workingSetStatus = HostLocalization.text(
                    "Raw RoomPlan retained; RoomPlan reported failure",
                    "RoomPlan の生データは保持しましたが、RoomPlan が失敗を報告しました"
                )
                self.fail(.roomPlanFailure)
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
                self.workingSetStatus = HostLocalization.text(
                    "Raw RoomPlan retained; postprocessing failed",
                    "RoomPlan の生データは保持しましたが、後処理に失敗しました"
                )
                self.fail(.roomPlanFailure)
                return
            }

            guard self.captureGeneration == generation,
                  let processed = lineage.processed
            else {
                if self.captureGeneration == generation {
                    self.fail(.roomPlanFailure)
                }
                return
            }

            do {
                try await store.persistProcessedRoomPlan(
                    processed
                )
                await self.refreshQuality(
                    store: store,
                    generation: generation
                )
            } catch {
                self.fail(.persistenceFailure)
            }
        }
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
                    maximumPointCount: 384
                )
            )
        derivedVolumeFusionTracker =
            DerivedShapeTemporalFusionTracker(
                configuration: DerivedShapeTemporalFusionConfiguration(
                    maximumFrameCount: 6,
                    maximumAgeSeconds: 24,
                    voxelSizeMeters: 0.055,
                    maximumPointCount: 384
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
                let proxies =
                    decomposition.components.prefix(6).flatMap {
                        Self.fitDerivedObjectProfiles(
                            $0.observation
                        )
                    }

                objectProxies = Array(
                    proxies.sorted { lhs, rhs in
                        let lhsResolved = lhs.selected != nil
                        let rhsResolved = rhs.selected != nil
                        if lhsResolved != rhsResolved {
                            return lhsResolved && !rhsResolved
                        }
                        let lhsScore =
                            lhs.selected?.metrics.fitScore
                            ?? lhs.provenance.fitScore
                            ?? 0
                        let rhsScore =
                            rhs.selected?.metrics.fitScore
                            ?? rhs.provenance.fitScore
                            ?? 0
                        return lhsScore > rhsScore
                    }
                    .prefix(4)
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
            fail(.persistenceFailure)
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

    private func transition(_ event: CaptureEvent) throws {
        try stateMachine.apply(event)
        state = stateMachine.state
        lastFailure = stateMachine.lastFailure
    }

    private func fail(_ code: CaptureFailureCode) {
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
