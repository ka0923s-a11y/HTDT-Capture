import HTDTCaptureCore

#if os(iOS) && canImport(UIKit)
import Foundation
import UIKit

public struct CaptureResourceMonitorPolicy: Sendable, Equatable {
    public let storageWarningBytes: Int64
    public let storageCriticalBytes: Int64

    public init(
        storageWarningBytes: Int64 = 2 * 1024 * 1024 * 1024,
        storageCriticalBytes: Int64 = 512 * 1024 * 1024
    ) {
        precondition(storageWarningBytes > storageCriticalBytes)
        precondition(storageCriticalBytes >= 0)
        self.storageWarningBytes = storageWarningBytes
        self.storageCriticalBytes = storageCriticalBytes
    }
}

@available(iOS 17.0, *)
@MainActor
public final class CaptureResourceMonitor: NSObject {
    public typealias EventHandler = @MainActor (
        CaptureResourceEvent,
        CaptureFailureCode?
    ) -> Void

    private let rootDirectory: URL
    private let policy: CaptureResourceMonitorPolicy
    private let eventHandler: EventHandler
    private var isStarted = false

    public init(
        rootDirectory: URL,
        policy: CaptureResourceMonitorPolicy = .init(),
        eventHandler: @escaping EventHandler
    ) {
        self.rootDirectory = rootDirectory
        self.policy = policy
        self.eventHandler = eventHandler
        super.init()
    }

    public func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(thermalStateChanged(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(memoryWarning(_:)),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        emitCurrentThermalState()
        sampleStorage()
    }

    public func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
    }

    public func sampleStorage() {
        guard isStarted else {
            return
        }

        do {
            let values = try rootDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            guard let available =
                values.volumeAvailableCapacityForImportantUsage
            else {
                return
            }

            if available < policy.storageCriticalBytes {
                eventHandler(
                    CaptureResourceEvent(
                        kind: .storagePressure,
                        severity: .error,
                        detail:
                            "available storage below critical capture threshold: "
                            + String(available)
                            + " bytes"
                    ),
                    .storagePressure
                )
            } else if available < policy.storageWarningBytes {
                eventHandler(
                    CaptureResourceEvent(
                        kind: .storagePressure,
                        severity: .warning,
                        detail:
                            "available storage below warning capture threshold: "
                            + String(available)
                            + " bytes"
                    ),
                    nil
                )
            }
        } catch {
            eventHandler(
                CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .warning,
                    detail:
                        "available storage could not be sampled: "
                        + error.localizedDescription
                ),
                nil
            )
        }
    }

    @objc
    private func thermalStateChanged(_ notification: Notification) {
        emitCurrentThermalState()
    }

    @objc
    private func memoryWarning(_ notification: Notification) {
        guard isStarted else {
            return
        }
        eventHandler(
            CaptureResourceEvent(
                kind: .memoryPressure,
                severity: .warning,
                detail: "UIApplication memory warning received"
            ),
            nil
        )
    }

    @objc
    private func applicationDidEnterBackground(
        _ notification: Notification
    ) {
        guard isStarted else {
            return
        }
        eventHandler(
            CaptureResourceEvent(
                kind: .interruption,
                severity: .error,
                detail:
                    "application entered background during active capture"
            ),
            .interrupted
        )
    }

    private func emitCurrentThermalState() {
        guard isStarted else {
            return
        }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            break
        case .fair:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state fair"
                ),
                nil
            )
        case .serious:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state serious"
                ),
                nil
            )
        case .critical:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .error,
                    detail: "thermal state critical"
                ),
                .thermalPressure
            )
        @unknown default:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "unknown thermal state"
                ),
                nil
            )
        }
    }
}
#endif
