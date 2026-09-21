import HTDTCaptureCore

#if os(iOS) && canImport(UIKit)
import Foundation
import UIKit

/// Stable, machine-safe tokens used in `CaptureResourceEvent.detail` values
/// produced by `CaptureResourceMonitor`. Event details are persisted in
/// canonical `quality/capture-quality.json`, so they must never embed
/// localized or platform-versioned text (#183).
public enum CaptureResourceMonitorDetailToken {
    /// `volumeAvailableCapacityForImportantUsage` could not be determined:
    /// the query succeeded but the platform reported no value. Distinct from
    /// "enough storage" — see #181.
    public static let storageCapacityUnavailable =
        "storage_capacity_unavailable"
    /// The capacity query threw. The detail appends the stable `NSError`
    /// domain and integer code as ` domain=<domain> code=<code>` so the same
    /// failure produces identical canonical bytes regardless of locale.
    public static let storageSampleFailed = "storage_sample_failed"
}

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

public struct CaptureResourceAssessment: Sendable {
    public let event: CaptureResourceEvent
    public let failure: CaptureFailureCode?

    public init(
        event: CaptureResourceEvent,
        failure: CaptureFailureCode?
    ) {
        self.event = event
        self.failure = failure
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

    public func currentStorageAssessment()
        -> CaptureResourceAssessment?
    {
        do {
            let values = try rootDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            guard let available =
                values.volumeAvailableCapacityForImportantUsage
            else {
                return nil
            }

            if available < policy.storageCriticalBytes {
                return CaptureResourceAssessment(
                    event: CaptureResourceEvent(
                        kind: .storagePressure,
                        severity: .error,
                        detail:
                            "available storage below critical capture threshold: "
                            + String(available)
                            + " bytes"
                    ),
                    failure: .storagePressure
                )
            }
            if available < policy.storageWarningBytes {
                return CaptureResourceAssessment(
                    event: CaptureResourceEvent(
                        kind: .storagePressure,
                        severity: .warning,
                        detail:
                            "available storage below warning capture threshold: "
                            + String(available)
                            + " bytes"
                    ),
                    failure: nil
                )
            }
            return nil
        } catch {
            // NSError domain + integer code are stable machine identifiers,
            // unlike `localizedDescription` (#183). The domain is bounded so
            // canonical detail bytes stay bounded.
            let nsError = error as NSError
            return CaptureResourceAssessment(
                event: CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .warning,
                    detail:
                        CaptureResourceMonitorDetailToken
                            .storageSampleFailed
                        + " domain="
                        + String(nsError.domain.prefix(128))
                        + " code="
                        + String(nsError.code)
                ),
                failure: nil
            )
        }
    }

    public func sampleStorage() {
        guard isStarted,
              let assessment = currentStorageAssessment()
        else {
            return
        }

        eventHandler(
            assessment.event,
            assessment.failure
        )
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
