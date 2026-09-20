import Foundation
import HTDTCaptureCore

public enum PlatformRuntimeProvenance {
    public static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> CaptureRuntimeProvenance {
        let info = bundle.infoDictionary ?? [:]
        let appVersion =
            info["CFBundleShortVersionString"] as? String
            ?? "unknown"
        let appBuild =
            info["CFBundleVersion"] as? String
            ?? "unknown"

        return CaptureRuntimeProvenance(
            osVersion: processInfo.operatingSystemVersionString,
            appVersion: appVersion,
            appBuild: appBuild
        )
    }
}
