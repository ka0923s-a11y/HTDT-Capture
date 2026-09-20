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
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginReview: coordinator.beginReview,
                finalizeCapture: coordinator.finalizeCapture,
                resetAfterFailure: coordinator.resetAfterFailure
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

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var captureGeneration = UUID()
    private var isEndingScan = false
    private let qualityRequirements = CaptureQualityRequirements()

    init() {
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()
    }

    func beginCapture() {
        guard state == .idle else {
            return
        }

        qualityReport = nil
        validationReport = nil

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

    func beginReview() {
        guard state == .scanning, !isEndingScan else {
            return
        }
        isEndingScan = true

        Task {
            await endScanForReview()
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

    func resetAfterFailure() {
        guard state == .failed else {
            return
        }

        captureGeneration = UUID()
        sessionController.stopAndPauseARSession()

        do {
            try transition(.reset)
        } catch {
            return
        }

        sessionController = SharedARSessionController()
        workingSetStore = nil
        qualityReport = nil
        validationReport = nil
        workingSetStatus = "Failed revision retained; new capture not prepared"
        isEndingScan = false
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()
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

        do {
            try sessionController.startRoomPlan()
            try transition(.prepared)
            workingSetStatus = "Scanning; working revision open"
        } catch is CaptureStateMachineError {
            fail(.unknown)
        } catch {
            fail(.roomPlanFailure)
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

        let meshPackage: MeshEvidencePackage
        let framePackage: FrameEvidencePackage
        do {
            let evidence =
                try sessionController.snapshotReviewEvidence(
                    depthSelection: .discrete
                )
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
            workingSetStore = nil
            validationReport = validation
            try transition(.finalize)
            workingSetStatus =
                "Finalized revision; bundle digest "
                + validation.bundleDigest.description
        } catch {
            fail(.persistenceFailure)
        }
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
        do {
            try transition(.fail(code))
        } catch {
            state = .failed
            lastFailure = .unknown
        }
    }
}
