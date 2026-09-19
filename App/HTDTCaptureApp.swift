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
    var body: some View {
        CaptureRootView(
            state: .idle,
            capabilities: PlatformCapabilityProbe.current()
        )
    }
}
