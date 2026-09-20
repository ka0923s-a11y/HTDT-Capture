import SwiftUI

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

@available(iOS 17.0, *)
@MainActor
public struct RoomPlanLiveCaptureView: UIViewRepresentable {
    public let controller: SharedARSessionController

    public init(controller: SharedARSessionController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> RoomCaptureView {
        controller.roomCaptureView
    }

    public func updateUIView(
        _ uiView: RoomCaptureView,
        context: Context
    ) {
        uiView.isModelEnabled = true
    }
}
#endif
