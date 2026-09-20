import SwiftUI
import HTDTCaptureCore
import HTDTCapturePlatform

public struct CaptureRootActions {
    public let beginCapture: () -> Void
    public let pauseCapture: () -> Void
    public let resumeCapture: () -> Void
    public let beginReview: () -> Void
    public let resetAfterFailure: () -> Void

    public init(
        beginCapture: @escaping () -> Void = {},
        pauseCapture: @escaping () -> Void = {},
        resumeCapture: @escaping () -> Void = {},
        beginReview: @escaping () -> Void = {},
        resetAfterFailure: @escaping () -> Void = {}
    ) {
        self.beginCapture = beginCapture
        self.pauseCapture = pauseCapture
        self.resumeCapture = resumeCapture
        self.beginReview = beginReview
        self.resetAfterFailure = resetAfterFailure
    }
}

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let lastFailure: CaptureFailureCode?
    public let actions: CaptureRootActions

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        lastFailure: CaptureFailureCode? = nil,
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.state = state
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.lastFailure = lastFailure
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    LabeledContent("State", value: state.rawValue)
                    if let cameraPermission {
                        LabeledContent(
                            "Camera permission",
                            value: cameraPermission.rawValue
                        )
                    }
                    if let lastFailure {
                        LabeledContent("Failure", value: lastFailure.rawValue)
                    }
                }

                Section("Capabilities") {
                    LabeledContent(
                        "RoomPlan + mesh",
                        value: capabilities.roomPlanMeshEligible
                            ? "Available"
                            : "Unavailable"
                    )
                    LabeledContent(
                        "Scene depth",
                        value: capabilities.sceneDepthSupported
                            ? "Available"
                            : "Unavailable"
                    )
                    if capabilities.requiresCombinedFeatureProbe {
                        Text(
                            "Combined RoomPlan/depth behavior still requires "
                            + "physical-device verification."
                        )
                    }
                }

                Section("Controls") {
                    controls
                }

                if state == .reviewing {
                    Section("Next step") {
                        Text(
                            "The RoomPlan capture has stopped without pausing "
                            + "the shared ARSession, preserving the current "
                            + "coordinate-space authority for follow-up evidence "
                            + "and annotations."
                        )
                        Text(
                            "Live artifact persistence, quality review, "
                            + "finalization, and export remain separate follow-up "
                            + "integration work."
                        )
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("HTDT Capture")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .idle:
            Button("Start capture", action: actions.beginCapture)
                .disabled(!capabilities.roomPlanMeshEligible)

        case .capabilityCheck:
            progressRow("Checking device capabilities…")

        case .permissions:
            progressRow("Requesting camera permission…")

        case .preparing:
            progressRow("Starting shared RoomPlan session…")

        case .scanning:
            Button("Pause capture", action: actions.pauseCapture)
            Button("Stop and review", action: actions.beginReview)

        case .paused:
            Button("Resume capture", action: actions.resumeCapture)

        case .reviewing:
            Text("Capture stopped; shared AR world frame remains active.")

        case .failed:
            Button("Reset capture", action: actions.resetAfterFailure)

        case .annotating:
            Text("Annotation workflow is not wired to the host app yet.")

        case .validating:
            progressRow("Validating capture…")

        case .finalized:
            Text("Capture revision finalized.")

        case .exported:
            Text("Capture bundle exported.")
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }
}
