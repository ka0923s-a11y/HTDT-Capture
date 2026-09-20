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
            actions: CaptureRootActions(
                beginCapture: coordinator.beginCapture,
                beginReview: coordinator.beginReview,
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

    private var stateMachine = CaptureStateMachine()
    private var sessionController = SharedARSessionController()
    private var workingSetStore: CaptureWorkingSetStore?
    private var captureGeneration = UUID()
    private var isEndingScan = false

    init() {
        capabilities = PlatformCapabilityProbe.current()
        cameraPermission = CameraPermissionController.currentStatus()
    }

    func beginCapture() {
        guard state == .idle else {
            return
        }

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

        do {
            let prepared = try makeWorkingSet()
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

            try sessionController.startRoomPlan()
            try transition(.prepared)
            workingSetStatus = "Scanning; working revision open"
        } catch is CaptureStateMachineError {
            fail(.unknown)
        } catch {
            fail(.persistenceFailure)
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

        let package: MeshEvidencePackage
        do {
            let snapshots =
                try sessionController.snapshotActiveMeshAnchors()
            package = try MeshEvidencePackageBuilder.build(
                snapshots: snapshots
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

        workingSetStatus = "Persisting final active mesh evidence"

        do {
            try await store.persistMeshPackage(package)
            let snapshot = await store.snapshot()
            workingSetStatus =
                "Reviewing; "
                + String(snapshot.payloadDeclarations.count)
                + " payloads persisted"
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
                let snapshot = await store.snapshot()
                guard self.captureGeneration == generation else {
                    return
                }
                self.workingSetStatus =
                    "Reviewing; "
                    + String(snapshot.payloadDeclarations.count)
                    + " payloads persisted"
            } catch {
                self.fail(.persistenceFailure)
            }
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
