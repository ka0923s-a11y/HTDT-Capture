import SwiftUI
import HTDTCaptureCore
import HTDTCapturePlatform

public struct CaptureRootActions {
    public let beginCapture: () -> Void
    public let beginReview: () -> Void
    public let resetAfterFailure: () -> Void

    public init(
        beginCapture: @escaping () -> Void = {},
        beginReview: @escaping () -> Void = {},
        resetAfterFailure: @escaping () -> Void = {}
    ) {
        self.beginCapture = beginCapture
        self.beginReview = beginReview
        self.resetAfterFailure = resetAfterFailure
    }
}

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let lastFailure: CaptureFailureCode?
    public let workingSetStatus: String?
    public let actions: CaptureRootActions

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        lastFailure: CaptureFailureCode? = nil,
        workingSetStatus: String? = nil,
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.state = state
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.lastFailure = lastFailure
        self.workingSetStatus = workingSetStatus
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
                    if let workingSetStatus {
                        LabeledContent(
                            "Working set",
                            value: workingSetStatus
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
                    Section("Working revision") {
                        Text(
                            "The RoomPlan scan ended without pausing the "
                            + "shared ARSession. Raw RoomPlan evidence, "
                            + "postprocessed RoomPlan evidence, and the final "
                            + "active mesh snapshot are persisted into the "
                            + "mutable capture working set as they become "
                            + "available."
                        )
                        Text(
                            "Quality gating, finalization, and export remain "
                            + "separate follow-up authorities."
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
            progressRow("Preparing capture working set…")

        case .scanning:
            Button("End scan and review", action: actions.beginReview)

        case .paused:
            Text(
                "The host app does not enter a pseudo-paused RoomPlan state. "
                + "Ending RoomPlan creates a scan boundary."
            )

        case .reviewing:
            Text("Scan ended; shared AR world frame remains active.")

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
