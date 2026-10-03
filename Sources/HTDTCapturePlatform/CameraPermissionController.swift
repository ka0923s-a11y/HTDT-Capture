public enum CameraPermissionStatus: String, Sendable, Equatable {
    case notDetermined = "not_determined"
    case authorized
    case denied
    case restricted
    case unavailable
}

#if os(iOS) && canImport(AVFoundation)
import AVFoundation

public enum CameraPermissionController {
    @MainActor
    public static func currentStatus() -> CameraPermissionStatus {
        map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    @MainActor
    public static func requestAccessIfNeeded() async -> CameraPermissionStatus {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        guard current == .notDetermined else {
            return map(current)
        }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    private static func map(
        _ status: AVAuthorizationStatus
    ) -> CameraPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }
}
#else
public enum CameraPermissionController {
    public static func currentStatus() -> CameraPermissionStatus {
        .unavailable
    }

    public static func requestAccessIfNeeded() async -> CameraPermissionStatus {
        .unavailable
    }
}
#endif
