import SwiftUI

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

@available(iOS 17.0, *)
@MainActor
public struct RoomPlanLiveCaptureView: UIViewRepresentable {
    public final class Coordinator {
        fileprivate let controller: SharedARSessionController

        fileprivate init(
            controller: SharedARSessionController
        ) {
            self.controller = controller
        }
    }

    public let controller: SharedARSessionController

    public init(controller: SharedARSessionController) {
        self.controller = controller
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    public func makeUIView(context: Context) -> RoomCaptureView {
        let view = controller.roomCaptureView
        controller.markLiveRoomCaptureViewMounted(view)
        return view
    }

    public func updateUIView(
        _ uiView: RoomCaptureView,
        context: Context
    ) {
        // The controller is the single authority for model-rendering policy.
        // Do not silently undo memory/thermal pressure mitigation here.
        controller.markLiveRoomCaptureViewMounted(uiView)
    }

    public static func dismantleUIView(
        _ uiView: RoomCaptureView,
        coordinator: Coordinator
    ) {
        coordinator.controller
            .markLiveRoomCaptureViewUnmounted(uiView)
    }
}
#endif
