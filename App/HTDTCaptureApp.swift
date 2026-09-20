import Combine
import Foundation
import RoomPlan
import SwiftUI
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
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginReview: coordinator.beginReview,
                captureEvidenceFrame: coordinator.captureEvidenceFrame,
                beginAnnotation: coordinator.beginAnnotation,
                captureRaycastPlacement:
                    coordinator.captureRaycastPlacement,
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

@MainActor
private final class HTDTCaptureHostCoordinator: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var capabilities: CaptureCapabilityMatrix
    @Published private(set) var cameraPermission: CameraPermissionStatus
    @Published private(set) var lastFailure: CaptureFailureCode?
    @Published private(set) var workingSetStatus = "Not prepared"
    @Published private(set) var qualityReport: CaptureQualityReport?
    @Published private(set) var validationReport: BundleValidationReport?
    @Published private(set) var exportURL: URL?
    @Published private(set)
    var annotationAuthorityCommitted = false
    @Published private(set)
    var annotationEvidenceRefs: [String] = []

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
    private let qualityRequirements = CaptureQualityRequirements()

    init() {
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()
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
                    confidencePayload: artifacts.confidencePayload
                )
                try await store.persistFramePackage(package)
                let snapshot = await store.snapshot()
                guard self.captureGeneration == generation,
                      self.state == .scanning
                else {
                    return
                }
                self.workingSetStatus =
                    "Scanning; "
                    + String(snapshot.evidenceFrameCount)
                    + " evidence frame(s) persisted"
            } catch {
                self.fail(.persistenceFailure)
            }
        }
    }

    func beginReview() {
        guard state == .scanning, !isEndingScan else {
            return
        }
        isEndingScan = true

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
            workingSetStatus =
                "Editing annotations and measurements"
        } catch {
            fail(.unknown)
        }
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
                snapshot.frameArtifacts.confidencePayload
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
        workingSetStatus =
            "Evidence-linked raycast placement captured"

        return authority
    }

    func cancelAnnotation() {
        guard state == .annotating else {
            return
        }
        do {
            try transition(.beginReview)
            workingSetStatus =
                "Annotation editing cancelled; staged records not written"
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
        workingSetStatus =
            "Persisting annotation and measurement authority"

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

        workingSetStatus = "Persisting quality and finalizing revision"

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

        workingSetStatus = "Creating validated .htdtcapture archive"
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
                workingSetStatus =
                    "Validated share-ready archive created"
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
        resourceMonitor?.stop()
        resourceMonitor = nil
        workingSetStatus =
            state == .idle
            ? "Ready for a new capture"
            : "Capture reset"
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
                    self.workingSetStatus =
                        "Ready; prior incomplete revision cleanup failed"
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
            "Prepared revision "
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

        let startedAtUTC = BundleTimestamp.utcString(
            from: Date()
        )
        do {
            try sessionController.startRoomPlan()
        } catch {
            fail(.roomPlanFailure)
            return
        }

        let foundation: CaptureSessionFoundationPackage
        do {
            let activeConfiguration =
                try ARConfigurationSnapshotAdapter.snapshot(
                    session: sessionController.arSession,
                    captureMode: .roomPlanMesh
                )
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
            captureStartTimingCorrelation =
                try await waitForInitialTimingCorrelation()
        } catch {
            workingSetStatus =
                "Active AR configuration could not be persisted"
            fail(.persistenceFailure)
            return
        }

        do {
            try transition(.prepared)
            configureResourceMonitor(
                store: store,
                rootDirectory: await store.rootDirectory,
                generation: generation
            )
            guard state == .scanning else {
                return
            }
            workingSetStatus =
                "Scanning; active AR configuration persisted"
        } catch {
            fail(.unknown)
        }
    }

    private func endScanForReview() async {
        defer {
            isEndingScan = false
        }

        guard let store = workingSetStore else {
            fail(.persistenceFailure)
            return
        }

        resourceMonitor?.sampleStorage()
        guard state == .scanning else {
            return
        }

        let meshPackage: MeshEvidencePackage
        let framePackage: FrameEvidencePackage
        let trackingEvent: TrackingQualityEvent
        let endTimingCorrelation: CaptureTimingCorrelation
        do {
            let evidence =
                try sessionController.snapshotReviewEvidence(
                    depthSelection: .discrete
                )
            trackingEvent = evidence.trackingQualityEvent
            endTimingCorrelation =
                try sessionController.snapshotTimingCorrelation()
            meshPackage = try MeshEvidencePackageBuilder.build(
                snapshots: evidence.meshAnchors
            )
            framePackage = try FrameEvidencePackageBuilder.build(
                descriptor: evidence.frameArtifacts.descriptor,
                pixelPayload: evidence.frameArtifacts.pixelPayload,
                depthPayload: evidence.frameArtifacts.depthPayload,
                confidencePayload:
                    evidence.frameArtifacts.confidencePayload
            )
        } catch PlatformCaptureError.currentFrameUnavailable {
            fail(.trackingUnavailable)
            return
        } catch {
            fail(.persistenceFailure)
            return
        }

        sessionController.stopRoomPlanPreservingARSession()

        do {
            try transition(.beginReview)
        } catch {
            fail(.unknown)
            return
        }

        workingSetStatus =
            "Persisting final mesh and selected frame evidence"

        do {
            guard let startTimingCorrelation =
                captureStartTimingCorrelation
            else {
                throw CaptureSessionMetadataError
                    .invalidCorrelationOrder
            }
            let timingPackage =
                try CaptureTimingPackageBuilder.build(
                    start: startTimingCorrelation,
                    end: endTimingCorrelation
                )
            try await store.persistTimingPackage(timingPackage)
            await store.recordTrackingEvent(trackingEvent)
            try await store.persistMeshPackage(meshPackage)
            try await store.persistFramePackage(framePackage)
            await refreshQuality(
                store: store,
                generation: captureGeneration
            )
        } catch {
            fail(.persistenceFailure)
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

        workingSetStatus = "Persisting raw RoomPlan evidence"

        Task { @MainActor [weak self] in
            guard let self,
                  self.captureGeneration == generation
            else {
                return
            }

            do {
                try await store.persistRawRoomPlan(raw)
            } catch {
                self.fail(.persistenceFailure)
                return
            }

            guard self.captureGeneration == generation else {
                return
            }

            if frameworkFailed {
                self.workingSetStatus =
                    "Raw RoomPlan retained; RoomPlan reported failure"
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
                self.workingSetStatus =
                    "Raw RoomPlan retained; postprocessing failed"
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
                "Ready to finalize; "
                + String(snapshot.payloadDeclarations.count)
                + " evidence payloads passed preflight"
        } else {
            let errorCount = report.diagnostics.filter {
                $0.severity == .error
            }.count
            workingSetStatus =
                "Reviewing; "
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
                "Finalized revision; bundle digest "
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
        resourceMonitor?.stop()
        resourceMonitor = nil
        do {
            try transition(.fail(code))
        } catch {
            state = .failed
            lastFailure = .unknown
        }
    }
}
