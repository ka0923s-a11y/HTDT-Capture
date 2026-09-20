import Darwin
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

    public static func currentDeviceDocument(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) throws -> CaptureDeviceDocument {
        let runtime = current(
            bundle: bundle,
            processInfo: processInfo
        )
        return try CaptureDeviceDocument(
            osVersion: runtime.osVersion,
            osBuild: runtime.osBuild,
            hardwareModel: hardwareModelIdentifier(),
            appVersion: runtime.appVersion,
            appBuild: runtime.appBuild
        )
    }

    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return "unknown"
        }

        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            let chars = bytes.bindMemory(to: CChar.self)
            guard let baseAddress = chars.baseAddress else {
                return "unknown"
            }
            return String(cString: baseAddress)
        }
    }
}
