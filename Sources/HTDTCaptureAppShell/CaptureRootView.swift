import SwiftUI
import HTDTCaptureCore
import HTDTCapturePlatform

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix
    ) {
        self.state = state
        self.capabilities = capabilities
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    LabeledContent("State", value: state.rawValue)
                    LabeledContent(
                        "RoomPlan + mesh",
                        value: capabilities.roomPlanMeshEligible ? "Available" : "Unavailable"
                    )
                    LabeledContent(
                        "Scene depth",
                        value: capabilities.sceneDepthSupported ? "Available" : "Unavailable"
                    )
                    if capabilities.requiresCombinedFeatureProbe {
                        Text("Combined RoomPlan/depth behavior requires physical-device verification.")
                    }
                }
            }
            .navigationTitle("HTDT Capture")
        }
    }
}
